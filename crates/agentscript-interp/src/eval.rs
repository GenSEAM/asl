//! The tree-walking evaluator.
//!
//! Dynamic value model, lexical scope, trapping arithmetic at operand width,
//! `try` unwinding to the enclosing defun (a lambda is not a return target),
//! and the full builtin vocabulary. Resolution follows to_python: lexical scope
//! first, then the module's own top-level names, then prelude builtins; a
//! qualified name resolves through the current unit's import aliases to the
//! defining module (identity is keyed by defining module path, never alias).
//!
//! A literal integer's width: unsuffixed ints are Int64 unless the called
//! function's declared signature (or a sibling Int32 operand) fixes them Int32
//! (spec §2.5 and ROADMAP l-4d92).

use crate::ast::{Expr, FnLit, NumericWidth, Pattern, Program};
use crate::builtins;
use crate::io;
use crate::num;
use crate::value::{eq, Callable, Lambda, MapKey, Value};
use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap, HashSet};

/// A trapping/internal error: diagnostic on stderr, exit 2.
#[derive(Debug)]
pub enum Err {
    Trap(String),
    Internal(String),
}

impl std::fmt::Display for Err {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Err::Trap(s) => write!(f, "trap: {}", s),
            Err::Internal(s) => write!(f, "internal error: {}", s),
        }
    }
}

impl From<String> for Err {
    fn from(s: String) -> Err {
        Err::Trap(s)
    }
}

/// Result of evaluating one expression. `OK(v)` is a normal value; `Ret(v)`
/// means "a `try` saw an err — return v from the nearest defun frame".
#[derive(Debug)]
pub enum Step {
    OK(Value),
    Ret(Value),
}

impl Step {
    fn into_ok(self) -> Result<Value, Err> {
        match self {
            Step::OK(v) | Step::Ret(v) => Ok(v),
        }
    }
}

type Env = Vec<BTreeMap<String, Value>>;

/// Every builtin name from prelude.json (the call heads). Constructor cases
/// (ok/err/some/none/pair/list) are routed by the grammar as constructor_call,
/// and IoError cases as crate::io::IO_ERROR_CASES; the rest dispatch here.
const BUILTINS: &[&str] = &[
    "+", "-", "*", "/", "mod", "checked-div", "checked-mod", "neg", "abs",
    "min", "max", "=", "!=", "<", "<=", ">", ">=", "and", "or", "not",
    "string-length", "string-empty?", "str", "string-slice", "string-index-of",
    "string-contains?", "string-starts-with?", "string-ends-with?",
    "string-split", "string-join", "string-upper", "string-lower", "string-trim",
    "string-reverse", "string-replace", "string-chars", "string-from-int64",
    "string-from-float64", "string-to-int64", "string-to-float64",
    "int32-to-int64", "int64-to-int32", "int64-to-float64", "float64-to-int64",
    "list", "list-empty?", "list-length", "list-get", "list-head", "list-tail",
    "list-cons", "list-append", "list-reverse", "list-slice", "list-contains?",
    "list-index-of", "list-sort", "list-sort-by", "map", "filter", "fold",
    "range", "zip", "list-sum", "list-min", "list-max",
    "map-empty", "map-get", "map-set", "map-remove", "map-has?", "map-size",
    "map-keys", "map-values", "map-pairs", "map-from-pairs",
    "is-some?", "is-none?", "is-ok?", "is-err?", "option-or", "result-or",
    "option-map", "result-map", "result-map-err", "option-to-result",
    "result-to-option",
    "read-line", "read-all", "print", "println", "eprintln",
    "file-read", "file-write", "file-append", "file-exists?",
];

fn is_builtin(name: &str) -> bool {
    BUILTINS.contains(&name)
}

pub struct Interp<'a> {
    program: &'a Program,
    units: Vec<crate::ast::Unit>,
    /// per unit: alias -> module path
    aliases: Vec<HashMap<String, String>>,
    /// module path -> unit index
    mod_index: HashMap<String, usize>,
    /// per unit: defun name -> index into units[i].defuns
    defun_index: Vec<HashMap<String, usize>>,
    /// per unit: bare enum/prelude case names
    case_index: Vec<HashSet<String>>,
    cur: usize,
    env: Env,
    argv: Vec<String>,
    /// global declaration-order index per user case (user-type sort)
    tag_order: HashMap<String, usize>,
    /// width hint for the next integer literal evaluated (None = Int64 default)
    lit_hint: Option<NumericWidth>,
}

impl<'a> Interp<'a> {
    pub fn new(program: &'a Program, argv: Vec<String>) -> Result<Interp<'a>, Err> {
        let mut interp = Interp {
            program,
            units: vec![],
            aliases: vec![],
            mod_index: HashMap::new(),
            defun_index: vec![],
            case_index: vec![],
            cur: program.units.len().checked_sub(1).unwrap_or(0),
            env: vec![],
            argv,
            tag_order: HashMap::new(),
            lit_hint: None,
        };
        interp.link()?;
        Ok(interp)
    }

    fn link(&mut self) -> Result<(), Err> {
        for (_, u) in &self.program.units {
            for (_, cases) in &u.enum_cases {
                for c in cases {
                    if !self.tag_order.contains_key(c) {
                        self.tag_order.insert(c.clone(), self.tag_order.len());
                    }
                }
            }
        }
        for (i, (path, u)) in self.program.units.iter().enumerate() {
            let mut a = HashMap::new();
            for (al, m) in &u.imports {
                a.insert(al.clone(), m.clone());
            }
            self.aliases.push(a);
            self.mod_index.insert(path.clone(), i);
            if let Some(mp) = &u.module_path {
                self.mod_index.insert(mp.clone(), i);
            }

            let mut defun_index = HashMap::new();
            for (j, d) in u.defuns.iter().enumerate() {
                defun_index.insert(d.name.clone(), j);
            }
            self.defun_index.push(defun_index);

            let mut case_index = HashSet::new();
            for (_, cases) in &u.enum_cases {
                for c in cases {
                    case_index.insert(c.clone());
                }
            }
            self.case_index.push(case_index);

            self.units.push(u.clone());
        }
        Ok(())
    }

    // ---------------------------------------------------------------- entry

    pub fn run_main(&mut self) -> Result<i32, Err> {
        let root = self.units.len() - 1;
        let has_main = self.units[root].defuns.iter().any(|d| d.name == "main");
        if !has_main {
            return Ok(0);
        }
        let argv = Value::List(self.argv.iter().map(|s| Value::Str(s.clone())).collect());
        let r = self.call_defun(root, "main", vec![argv])?;
        let v = match r {
            Step::OK(v) => v,
            Step::Ret(v) => v,
        };
        Ok(exit_glue(&v))
    }

    /// The function-mode entry protocol: evaluate the named defun with concrete
    /// argument values and return its value, for the differential harness.
    pub fn call_entry(&mut self, ti: usize, name: &str, args: Vec<Value>) -> Result<Value, Err> {
        let r = self.call_defun(ti, name, args)?;
        Ok(match r {
            Step::OK(v) | Step::Ret(v) => v,
        })
    }

    // ----------------------------------------------------------- evaluation

    fn eval_seq(&mut self, body: &[Expr]) -> Result<Step, Err> {
        let mut last = Step::OK(Value::Unit);
        for e in body {
            let s = self.eval(e)?;
            if let Step::Ret(_) = &s {
                return Ok(s);
            }
            last = s;
        }
        Ok(last)
    }

    fn eval(&mut self, e: &Expr) -> Result<Step, Err> {
        use Expr::*;
        match e {
            Int(lit) => {
                let w = self.lit_hint.take().unwrap_or(NumericWidth::I64);
                let v = num::parse_int_lit(&lit.digits, w)?;
                Ok(Step::OK(Value::int(v, w)))
            }
            Float(f) => Ok(Step::OK(Value::Float(*f))),
            Str(s) => Ok(Step::OK(Value::Str(s.clone()))),
            Bool(b) => Ok(Step::OK(Value::Bool(*b))),
            Unit => Ok(Step::OK(Value::Unit)),
            Ident(name) => self.eval_ident(name),
            Qualified(alias, member) => self.eval_qualified(alias, member),
            Let(bindings, body) => {
                // let*: a binding's initialiser sees the earlier bindings, so
                // the frame grows one binder at a time (15-shadowed-binders).
                self.env.push(BTreeMap::new());
                for (name, v) in bindings {
                    let val = self.eval(v)?.into_ok()?;
                    self.env.last_mut().unwrap().insert(name.clone(), val);
                }
                let r = self.eval_seq(body);
                self.env.pop();
                r
            }
            If(c, t, f) => {
                let cond = self.eval(&**c)?.into_ok()?;
                if self.as_bool(&cond, "if condition")? {
                    self.eval(&**t)
                } else {
                    self.eval(&**f)
                }
            }
            Cond(clauses) => {
                for cl in clauses {
                    match &cl.condition {
                        Some(c) => {
                            let v = self.eval(c)?.into_ok()?;
                            match v {
                                Value::Bool(true) => return self.eval_seq(&cl.body),
                                Value::Bool(false) => {}
                                _ => return Err(Err::Internal("cond needs Bool".into())),
                            }
                        }
                        None => return self.eval_seq(&cl.body),
                    }
                }
                Err(Err::Internal("cond had no :else branch".to_string()))
            }
            Match(subj, arms) => {
                let sv = self.eval(subj)?.into_ok()?;
                for (pat, body) in arms {
                    let mut binds = BTreeMap::new();
                    if self.pmatch(pat, &sv, &mut binds) {
                        self.env.push(binds);
                        let r = self.eval_seq(body);
                        self.env.pop();
                        return r;
                    }
                }
                Err(Err::Internal("match was not exhaustive".to_string()))
            }
            Try(inner) => {
                let s = self.eval(inner)?;
                match s {
                    Step::Ret(v) => Ok(Step::Ret(v)),
                    Step::OK(v) => match &v {
                        Value::Tagged(t, args) if t == "ok" => Ok(Step::OK(args[0].clone())),
                        Value::Tagged(t, _) if t == "err" => Ok(Step::Ret(v)),
                        other => Err(Err::Internal(format!("try needs Result, got {:?}", other))),
                    },
                }
            }
            Fn(lit) => {
                let lam = Lambda {
                    params: lit.params.clone(),
                    body: lit.body.clone(),
                    captured: self.env.clone(),
                };
                Ok(Step::OK(Value::Closure(Callable::Lambda(lam))))
            }
            Ctor(head, args) => {
                let mut vals = vec![];
                for a in args {
                    vals.push(self.eval(a)?.into_ok()?);
                }
                Ok(Step::OK(construct(head, vals)))
            }
            Record(_, fields) => {
                let mut rec = vec![];
                for (fname, val) in fields {
                    rec.push((fname.clone(), self.eval(val)?.into_ok()?));
                }
                Ok(Step::OK(Value::Record(rec)))
            }
            FieldAccess { field, target } => {
                let tv = self.eval(target)?.into_ok()?;
                self.field(&tv, field)
            }
            Call(callee, args) => {
                let (name, is_qualified) = match &**callee {
                    Ident(n) => (Some(n.clone()), false),
                    Qualified(a, m) => (Some(format!("{}/{}", a, m)), true),
                    _ => (None, false),
                };
                if name.as_deref() == Some("and") {
                    return self.eval_logical(args, true);
                }
                if name.as_deref() == Some("or") {
                    return self.eval_logical(args, false);
                }
                // A bare identifier that names a builtin (and is not shadowed by
                // a lexical binder or a module defun) dispatches there. Qualified
                // names never name a builtin.
                if let Some(n) = &name {
                    if !is_qualified && is_builtin(n) && self.lookup_lex(n).is_none()
                        && !self.defun_index[self.cur].contains_key(n)
                        && !self.case_index[self.cur].contains(n) {
                        let mut vals = vec![];
                        for a in args {
                            vals.push(self.eval(a)?.into_ok()?);
                        }
                        return self.builtin(n, vals).map(Step::OK);
                    }
                }
                let callable = self.resolve_call(callee)?;
                // literal width hint from callee's declared params
                let hints = self.param_hints(&callable, args.len());
                let mut vals = vec![];
                for (i, a) in args.iter().enumerate() {
                    if let Some(h) = hints.get(i) {
                        self.lit_hint = *h;
                    }
                    match self.eval(a)? {
                        Step::OK(v) => vals.push(v),
                        Step::Ret(v) => return Ok(Step::Ret(v)),
                    }
                }
                self.apply(callable, vals)
            }
        }
    }

    fn eval_logical(&mut self, args: &[Expr], is_and: bool) -> Result<Step, Err> {
        for a in args {
            let v = self.eval(a)?.into_ok()?;
            let b = self.as_bool(&v, "logical op")?;
            if is_and {
                if !b {
                    return Ok(Step::OK(Value::Bool(false)));
                }
            } else if b {
                return Ok(Step::OK(Value::Bool(true)));
            }
        }
        // All clauses passed: `and` of all-true is true, `or` of all-false is
        // false, so the terminal is exactly `is_and`.
        Ok(Step::OK(Value::Bool(is_and)))
    }

    /// A bare identifier in expression position: lexical scope, then the
    /// current unit's defuns/cases, then prelude IoError cases as bare tags.
    fn ident_value(&mut self, name: &str) -> Result<Value, Err> {
        if let Some(v) = self.lookup_lex(name) {
            return Ok(v);
        }
        if let Some(c) = self.resolve_local(name) {
            return Ok(Value::Closure(c));
        }
        if io::IO_ERROR_CASES.contains(&name) {
            return Ok(Value::Tagged(name.to_string(), vec![]));
        }
        Err(Err::Internal(format!("unbound name {}", name)))
    }

    fn eval_ident(&mut self, name: &str) -> Result<Step, Err> {
        self.ident_value(name).map(Step::OK)
    }

    /// A qualified member in expression position, resolved through the current
    /// unit's import aliases to the defining unit.
    fn qualified_value(&mut self, alias: &str, member: &str) -> Result<Value, Err> {
        let ti = self.resolve_alias(alias)?;
        self.resolve_in_unit(ti, member)
    }

    fn eval_qualified(&mut self, alias: &str, member: &str) -> Result<Step, Err> {
        self.qualified_value(alias, member).map(Step::OK)
    }

    fn resolve_alias(&self, alias: &str) -> Result<usize, Err> {
        self.aliases
            .get(self.cur)
            .and_then(|a| a.get(alias))
            .and_then(|m| self.mod_index.get(m).copied())
            .ok_or_else(|| Err::Internal(format!("unbound alias {}", alias)))
    }

    fn lookup_lex(&self, name: &str) -> Option<Value> {
        for frame in self.env.iter().rev() {
            if let Some(v) = frame.get(name) {
                return Some(v.clone());
            }
        }
        None
    }

    fn resolve_local(&self, name: &str) -> Option<Callable> {
        if self.defun_index[self.cur].contains_key(name) {
            return Some(Callable::Defun { unit: self.cur, name: name.to_string() });
        }
        if self.case_index[self.cur].contains(name) {
            return Some(Callable::Case(name.to_string()));
        }
        None
    }

    fn resolve_in_unit(&self, ti: usize, name: &str) -> Result<Value, Err> {
        if self.defun_index[ti].contains_key(name) {
            return Ok(Value::Closure(Callable::Defun { unit: ti, name: name.to_string() }));
        }
        if self.case_index[ti].contains(name) {
            return Ok(Value::Closure(Callable::Case(name.to_string())));
        }
        Err(Err::Internal(format!("unbound member {}", name)))
    }

    // ---------------------------------------------------------------- calls

    fn resolve_call(&mut self, callee: &Expr) -> Result<Callable, Err> {
        match callee {
            Expr::Ident(name) => {
                // Prelude IoError cases are constructors in call position
                // ((not-found)); ident_value yields the bare tag value, which
                // would misread as a non-function here.
                if self.lookup_lex(name).is_none()
                    && self.resolve_local(name).is_none()
                    && io::IO_ERROR_CASES.contains(&name.as_str())
                {
                    return Ok(Callable::Case(name.clone()));
                }
                self.ident_value(name).and_then(|v| self.value_to_callable(v))
            }
            Expr::Qualified(alias, member) => self
                .qualified_value(alias, member)
                .and_then(|v| self.value_to_callable(v)),
            _ => {
                let v = self.eval(callee)?.into_ok()?;
                self.value_to_callable(v)
            }
        }
    }

    fn value_to_callable(&self, v: Value) -> Result<Callable, Err> {
        match v {
            Value::Closure(c) => Ok(c),
            _ => Err(Err::Internal("called a non-function value".to_string())),
        }
    }

    /// Width hints per argument position, from the callable's declared params.
    fn param_hints(&self, c: &Callable, n: usize) -> Vec<Option<NumericWidth>> {
        let mut out = vec![None; n];
        match c {
            Callable::Defun { unit, name } => {
                if let Some(&idx) = self.defun_index[*unit].get(name) {
                    for (i, p) in self.units[*unit].defuns[idx].params.iter().enumerate() {
                        if i < n {
                            out[i] = p.ty.width();
                        }
                    }
                }
            }
            Callable::Lambda(lam) => {
                for (i, p) in lam.params.iter().enumerate() {
                    if i < n {
                        out[i] = p.ty.width();
                    }
                }
            }
            _ => {}
        }
        out
    }

    fn apply(&mut self, c: Callable, args: Vec<Value>) -> Result<Step, Err> {
        match c {
            Callable::Defun { unit, name } => self.call_defun(unit, &name, args),
            Callable::Case(tag) => Ok(Step::OK(Value::Tagged(tag, args))),
            Callable::Lambda(lam) => {
                if lam.params.len() != args.len() {
                    return Err(Err::Internal("lambda arity".to_string()));
                }
                let saved = std::mem::replace(&mut self.env, lam.captured);
                let mut frame = BTreeMap::new();
                for (p, a) in lam.params.iter().zip(args.iter()) {
                    frame.insert(p.name.clone(), a.clone());
                }
                self.env.push(frame);
                let r = self.eval_seq(&lam.body);
                self.env = saved;
                match r? {
                    Step::OK(v) => Ok(Step::OK(v)),
                    // lambda is not a return target: propagate the try return
                    Step::Ret(v) => Ok(Step::Ret(v)),
                }
            }
        }
    }

    fn call_defun(&mut self, ti: usize, name: &str, args: Vec<Value>) -> Result<Step, Err> {
        let idx = *self
            .defun_index[ti]
            .get(name)
            .ok_or_else(|| Err::Internal(format!("no defun {}", name)))?;
        let def = &self.units[ti].defuns[idx];
        if def.params.len() != args.len() {
            return Err(Err::Internal(format!(
                "{}: expected {} arg(s), got {}",
                name,
                def.params.len(),
                args.len()
            )));
        }
        // Clone only the two slices evaluation reads; name/effect/ret are dead
        // during the call.
        let params = def.params.clone();
        let body = def.body.clone();
        let saved_cur = self.cur;
        self.cur = ti;
        let mut frame = BTreeMap::new();
        for (p, a) in params.iter().zip(args.iter()) {
            frame.insert(p.name.clone(), a.clone());
        }
        self.env.push(frame);
        let r = self.eval_seq(&body);
        self.env.pop();
        self.cur = saved_cur;
        match r? {
            Step::OK(v) => Ok(Step::OK(v)),
            Step::Ret(v) => Ok(Step::OK(v)), // defun boundary consumes try return
        }
    }

    // -------------------------------------------------------------- builtins

    pub fn builtin(&mut self, name: &str, args: Vec<Value>) -> Result<Value, Err> {
        use Value::*;
        match name {
            // --- arithmetic ---
            "+" | "-" | "*" | "/" | "mod" | "checked-div" | "checked-mod" => {
                self.num_binop(name, &args)
            }
            "neg" | "abs" => {
                let a = &args[0];
                match a {
                    Int { v, w } => {
                        let r = if name == "neg" { num::ineg(*v, *w) } else { num::iabs(*v, *w) }?;
                        Ok(Value::int(r, *w))
                    }
                    Float(x) => Ok(Value::Float(if name == "neg" { -*x } else { x.abs() })),
                    _ => Err(Err::Internal("numeric op on non-number".into())),
                }
            }
            "min" | "max" => {
                let ord = self.compare(&args[0], &args[1]);
                if name == "min" {
                    Ok(if ord == Ordering::Greater { args[1].clone() } else { args[0].clone() })
                } else {
                    Ok(if ord == Ordering::Less { args[1].clone() } else { args[0].clone() })
                }
            }
            "=" => Ok(Bool(eq(&args[0], &args[1]))),
            "!=" => Ok(Bool(!eq(&args[0], &args[1]))),
            "<" | "<=" | ">" | ">=" => {
                let ord = self.compare(&args[0], &args[1]);
                let b = match name {
                    "<" => ord == Ordering::Less,
                    "<=" => ord != Ordering::Greater,
                    ">" => ord == Ordering::Greater,
                    ">=" => ord != Ordering::Less,
                    _ => unreachable!(),
                };
                Ok(Bool(b))
            }
            "not" => Ok(Bool(!self.as_bool(&args[0], "not")?)),
            // --- strings ---
            "string-length" => Ok(Value::int(self.as_str(&args[0])?.chars().count() as i64, NumericWidth::I64)),
            "string-empty?" => Ok(Bool(self.as_str(&args[0])?.is_empty())),
            "str" => {
                let mut s = String::new();
                for a in &args {
                    s.push_str(self.as_str(a)?);
                }
                Ok(Str(s))
            }
            "string-slice" => Ok(builtins::str_slice(
                self.as_str(&args[0])?, self.as_i64(&args[1])?, self.as_i64(&args[2])?)),
            "string-index-of" => Ok(builtins::str_index_of(
                self.as_str(&args[0])?, self.as_str(&args[1])?)),
            "string-contains?" => Ok(Bool(self.as_str(&args[0])?.contains(self.as_str(&args[1])?))),
            "string-starts-with?" => Ok(Bool(self.as_str(&args[0])?.starts_with(self.as_str(&args[1])?))),
            "string-ends-with?" => Ok(Bool(self.as_str(&args[0])?.ends_with(self.as_str(&args[1])?))),
            "string-split" => {
                let sep = self.as_str(&args[1])?;
                Ok(List(self.as_str(&args[0])?.split(sep).map(|x| Str(x.to_string())).collect()))
            }
            "string-join" => {
                let sep = self.as_str(&args[1])?;
                let parts = self.as_list(&args[0])?;
                let mut out = String::new();
                for (i, p) in parts.iter().enumerate() {
                    if i > 0 { out.push_str(sep); }
                    out.push_str(self.as_str(p)?);
                }
                Ok(Str(out))
            }
            "string-upper" => Ok(Str(self.as_str(&args[0])?.to_uppercase())),
            "string-lower" => Ok(Str(self.as_str(&args[0])?.to_lowercase())),
            "string-trim" => Ok(Str(self.as_str(&args[0])?.trim().to_string())),
            "string-reverse" => Ok(Str(self.as_str(&args[0])?.chars().rev().collect())),
            "string-replace" => Ok(Str(
                self.as_str(&args[0])?.replace(self.as_str(&args[1])?, self.as_str(&args[2])?))),
            "string-chars" => Ok(List(builtins::str_chars_vec(self.as_str(&args[0])?))),
            "string-from-int64" => Ok(Str(self.as_i64(&args[0])?.to_string())),
            "string-from-float64" => Ok(Str(num::fmt_f64(self.as_f64(&args[0])?))),
            "string-to-int64" => Ok(match num::to_int(self.as_str(&args[0])?) {
                Some(n) => Tagged("some".into(), vec![Value::int(n, NumericWidth::I64)]),
                None => Tagged("none".into(), vec![]),
            }),
            "string-to-float64" => Ok(match num::to_float(self.as_str(&args[0])?) {
                Some(x) => Tagged("some".into(), vec![Float(x)]),
                None => Tagged("none".into(), vec![]),
            }),
            // --- conversions ---
            "int32-to-int64" => Ok(Value::int(self.as_i64(&args[0])?, NumericWidth::I64)),
            "int64-to-int32" => Ok(match num::to_i32(self.as_i64(&args[0])?) {
                Some(n) => Tagged("some".into(), vec![Value::int(n, NumericWidth::I32)]),
                None => Tagged("none".into(), vec![]),
            }),
            "int64-to-float64" => Ok(Float(self.as_i64(&args[0])? as f64)),
            "float64-to-int64" => Ok(match num::f_to_i(self.as_f64(&args[0])?) {
                Some(n) => Tagged("some".into(), vec![Value::int(n, NumericWidth::I64)]),
                None => Tagged("none".into(), vec![]),
            }),
            // --- lists ---
            "list-empty?" => Ok(Bool(self.as_list(&args[0])?.is_empty())),
            "list-length" => Ok(Value::int(self.as_list(&args[0])?.len() as i64, NumericWidth::I64)),
            "list-get" => Ok(builtins::at(self.as_list(&args[0])?, self.as_i64(&args[1])?)),
            "list-head" => Ok(builtins::at(self.as_list(&args[0])?, 0)),
            "list-tail" => Ok(builtins::tail(self.as_list(&args[0])?)),
            "list-cons" => {
                let mut v = vec![args[0].clone()];
                v.extend(self.as_list(&args[1])?.iter().cloned());
                Ok(List(v))
            }
            "list-append" => {
                let mut v = self.as_list(&args[0])?.clone();
                v.extend(self.as_list(&args[1])?.iter().cloned());
                Ok(List(v))
            }
            "list-reverse" => {
                let mut v = self.as_list(&args[0])?.clone();
                v.reverse();
                Ok(List(v))
            }
            "list-slice" => Ok(builtins::list_slice(
                self.as_list(&args[0])?, self.as_i64(&args[1])?, self.as_i64(&args[2])?)),
            "list-contains?" => Ok(Bool(self.as_list(&args[0])?.iter().any(|x| eq(x, &args[1])))),
            "list-index-of" => Ok(self.index_of(self.as_list(&args[0])?, &args[1])),
            "range" => {
                let a = self.as_i64(&args[0])?;
                let b = self.as_i64(&args[1])?;
                let v: Vec<Value> = if a >= b { vec![] } else {
                    (a..b).map(|x| Value::int(x, NumericWidth::I64)).collect()
                };
                Ok(List(v))
            }
            "zip" => {
                let a = self.as_list(&args[0])?.clone();
                let b = self.as_list(&args[1])?.clone();
                Ok(List(a.iter().zip(b.iter())
                    .map(|(x, y)| Tagged("pair".into(), vec![x.clone(), y.clone()]))
                    .collect()))
            }
            "list-sum" => self.list_sum(self.as_list(&args[0])?),
            "list-min" | "list-max" => self.list_extreme(name, self.as_list(&args[0])?),
            "list-sort" => {
                let mut v = self.as_list(&args[0])?.clone();
                v.sort_by(|a, b| self.compare(a, b));
                Ok(List(v))
            }
            // --- maps ---
            "map-empty" => Ok(Map(BTreeMap::new())),
            "map-get" => {
                let m = self.as_map(&args[0])?;
                let k = self.key(&args[1])?;
                Ok(builtins::m_get(m, &k))
            }
            "map-set" => {
                let m = self.as_map(&args[0])?;
                let k = self.key(&args[1])?;
                Ok(Map(builtins::m_set(m, k, args[2].clone())))
            }
            "map-remove" => {
                let m = self.as_map(&args[0])?;
                let k = self.key(&args[1])?;
                Ok(Map(builtins::m_del(m, &k)))
            }
            "map-has?" => Ok(Bool(self.as_map(&args[0])?.contains_key(&self.key(&args[1])?))),
            "map-size" => Ok(Value::int(self.as_map(&args[0])?.len() as i64, NumericWidth::I64)),
            "map-keys" => Ok(List(self.as_map(&args[0])?.keys().map(key_to_value).collect())),
            "map-values" => Ok(List(self.as_map(&args[0])?.values().cloned().collect())),
            "map-pairs" => Ok(List(self.as_map(&args[0])?.iter()
                .map(|(k, val)| Tagged("pair".into(), vec![key_to_value(k), val.clone()]))
                .collect())),
            "map-from-pairs" => {
                let ps = self.as_list(&args[0])?;
                Ok(Map(builtins::m_from(ps).map_err(Err::Internal)?))
            }
            // --- option / result ---
            "is-some?" => Ok(Bool(matches!(&args[0], Tagged(t, _) if t == "some"))),
            "is-none?" => Ok(Bool(matches!(&args[0], Tagged(t, _) if t == "none"))),
            "is-ok?" => Ok(Bool(matches!(&args[0], Tagged(t, _) if t == "ok"))),
            "is-err?" => Ok(Bool(matches!(&args[0], Tagged(t, _) if t == "err"))),
            "option-or" => match &args[0] {
                Tagged(t, a) if t == "some" => Ok(a[0].clone()),
                _ => Ok(args.get(1).cloned().unwrap_or(Value::Unit)),
            },
            "result-or" => match &args[0] {
                Tagged(t, a) if t == "ok" => Ok(a[0].clone()),
                _ => Ok(args.get(1).cloned().unwrap_or(Value::Unit)),
            },
            "option-map" => self.apply_higher(&args[0], &args[1], true, false),
            "result-map" => self.apply_higher(&args[0], &args[1], false, false),
            "result-map-err" => self.apply_higher(&args[0], &args[1], false, true),
            "option-to-result" => Ok(match &args[0] {
                Tagged(t, a) if t == "some" => Tagged("ok".into(), a.clone()),
                _ => Tagged("err".into(), vec![args[1].clone()]),
            }),
            "result-to-option" => Ok(match &args[0] {
                Tagged(t, a) if t == "ok" => Tagged("some".into(), a.clone()),
                _ => Tagged("none".into(), vec![]),
            }),
            "map" | "filter" | "fold" | "list-sort-by" => self.list_higher(name, args),
            // --- I/O ---
            "read-line" => self.read_line(),
            "read-all" => self.read_all(),
            "print" => io::write_out(self.as_str(&args[0])?, ""),
            "println" => io::write_out(self.as_str(&args[0])?, "\n"),
            "eprintln" => io::write_err(self.as_str(&args[0])?, "\n"),
            "file-read" => io::file_read(self.as_str(&args[0])?),
            "file-write" => io::file_write(self.as_str(&args[0])?, self.as_str(&args[1])?),
            "file-append" => io::file_append(self.as_str(&args[0])?, self.as_str(&args[1])?),
            "file-exists?" => io::file_exists(self.as_str(&args[0])?),
            other => Err(Err::Internal(format!("unknown builtin {}", other))),
        }
    }

    // ------------------------------------------------------------ arithmetic

    fn num_binop(&self, name: &str, args: &[Value]) -> Result<Value, Err> {
        use Value::*;
        let (a, b) = (&args[0], &args[1]);
        match (a, b) {
            (Int { v: x, w: wx }, Int { v: y, .. }) => {
                // Both ints: width is the operand width. A literal next to an
                // Int32 operand is Int32 (l-4d92), so any Int32 wins.
                let w = if *wx == NumericWidth::I32
                    || matches!(b, Int { w: NumericWidth::I32, .. }) {
                    NumericWidth::I32
                } else {
                    NumericWidth::I64
                };
                if name == "/" || name == "mod" {
                    if *y == 0 {
                        return Err(Err::Trap(format!("{} by zero", if name == "/" { "division" } else { "modulo" })));
                    }
                    if name == "/" {
                        return Ok(Value::int(num::idiv(*x, *y, w)?, w));
                    }
                    return Ok(Value::int(num::imod(*x, *y)?, w));
                }
                if name == "checked-div" {
                    return Ok(match num::checked_div(*x, *y, w) {
                        Some(q) => Tagged("some".into(), vec![Value::int(q, w)]),
                        None => Tagged("none".into(), vec![]),
                    });
                }
                if name == "checked-mod" {
                    return Ok(match num::checked_mod(*x, *y) {
                        Some(q) => Tagged("some".into(), vec![Value::int(q, w)]),
                        None => Tagged("none".into(), vec![]),
                    });
                }
                let r = match name {
                    "+" => num::iadd(*x, *y, w)?,
                    "-" => num::isub(*x, *y, w)?,
                    "*" => num::imul(*x, *y, w)?,
                    _ => return Err(Err::Internal("bad int op".into())),
                };
                Ok(Value::int(r, w))
            }
            _ => {
                // float leg
                let x = self.as_f64(a)?;
                let y = self.as_f64(b)?;
                if name == "/" || name == "mod" || name == "checked-div" || name == "checked-mod" {
                    let r = match name {
                        "/" => x / y,
                        "mod" => math_fmod(x, y),
                        "checked-div" => {
                            if y == 0.0 { return Ok(Tagged("none".into(), vec![])); }
                            return Ok(Tagged("some".into(), vec![Float(x / y)]));
                        }
                        "checked-mod" => {
                            if y == 0.0 { return Ok(Tagged("none".into(), vec![])); }
                            return Ok(Tagged("some".into(), vec![Float(math_fmod(x, y))]));
                        }
                        _ => unreachable!(),
                    };
                    return Ok(Float(r));
                }
                let r = match name {
                    "+" => x + y,
                    "-" => x - y,
                    "*" => x * y,
                    _ => return Err(Err::Internal("bad float op".into())),
                };
                Ok(Float(r))
            }
        }
    }

    fn list_sum(&mut self, xs: &[Value]) -> Result<Value, Err> {
        let has_float = xs.iter().any(|x| matches!(x, Value::Float(_)));
        if has_float {
            let mut acc = 0.0f64;
            for x in xs {
                acc += self.as_f64(x)?;
            }
            return Ok(Value::Float(acc));
        }
        let mut acc: i64 = 0;
        let mut width = NumericWidth::I64;
        for x in xs {
            match x {
                Value::Int { v, w } => {
                    acc = num::iadd(acc, *v, width_or(*w, NumericWidth::I64))?;
                    width = width_or(*w, width);
                }
                _ => return Err(Err::Internal("list-sum over non-number".into())),
            }
        }
        Ok(Value::int(acc, width))
    }

    fn list_extreme(&mut self, name: &str, xs: &[Value]) -> Result<Value, Err> {
        if xs.is_empty() {
            return Ok(Value::Tagged("none".into(), vec![]));
        }
        let mut best = xs[0].clone();
        for x in &xs[1..] {
            let ord = self.compare(x, &best);
            if (name == "list-min" && ord == Ordering::Less)
                || (name == "list-max" && ord == Ordering::Greater) {
                best = x.clone();
            }
        }
        Ok(Value::Tagged("some".into(), vec![best]))
    }

    fn index_of(&self, xs: &[Value], x: &Value) -> Value {
        for (i, y) in xs.iter().enumerate() {
            if eq(y, x) {
                return Value::Tagged("some".into(), vec![Value::int(i as i64, NumericWidth::I64)]);
            }
        }
        Value::Tagged("none".into(), vec![])
    }

    // ------------------------------------------------------------ higher order

    fn apply_higher(&mut self, func: &Value, arg: &Value, is_option: bool, is_err: bool) -> Result<Value, Err> {
        match arg {
            Value::Tagged(t, a) if t == "some" || t == "ok" => {
                if is_err {
                    // result-map-err: ok passes through untouched
                    Ok(Value::Tagged(t.clone(), a.clone()))
                } else {
                    let mapped = self.apply_closure_n(func, vec![a[0].clone()])?;
                    Ok(Value::Tagged(if is_option { "some" } else { "ok" }.to_string(), vec![mapped]))
                }
            }
            Value::Tagged(t, a) if t == "err" => {
                if is_err {
                    let mapped = self.apply_closure_n(func, vec![a[0].clone()])?;
                    Ok(Value::Tagged("err".into(), vec![mapped]))
                } else {
                    Ok(Value::Tagged("err".to_string(), a.clone()))
                }
            }
            Value::Tagged(t, _) if t == "none" => Ok(Value::Tagged("none".into(), vec![])),
            _ => Err(Err::Internal("apply_higher on non-option/result".into())),
        }
    }

    fn list_higher(&mut self, name: &str, args: Vec<Value>) -> Result<Value, Err> {
        let f = args[0].clone();
        match name {
            "map" => {
                let xs = self.as_list(&args[1])?.clone();
                let mut out = vec![];
                for x in xs {
                    out.push(self.apply_closure_n(&f, vec![x])?);
                }
                Ok(Value::List(out))
            }
            "filter" => {
                let xs = self.as_list(&args[1])?.clone();
                let mut out = vec![];
                for x in xs {
                    let ok = self.apply_closure_n(&f, vec![x.clone()])?;
                    let keep = self.as_bool(&ok, "filter pred")?;
                    if keep {
                        out.push(x);
                    }
                }
                Ok(Value::List(out))
            }
            "fold" => {
                let init = args[1].clone();
                let xs = self.as_list(&args[2])?.clone();
                let mut acc = init;
                for x in xs {
                    acc = self.apply_closure_n(&f, vec![acc, x])?;
                }
                Ok(acc)
            }
            "list-sort-by" => {
                let xs = self.as_list(&args[1])?.clone();
                let mut keyed: Vec<(Value, Value)> = xs.into_iter()
                    .map(|x| {
                        let k = self.apply_closure_n(&f, vec![x.clone()]).unwrap_or(Value::Unit);
                        (x, k)
                    })
                    .collect();
                keyed.sort_by(|a, b| self.compare(&a.1, &b.1));
                Ok(Value::List(keyed.into_iter().map(|(x, _)| x).collect()))
            }
            _ => Err(Err::Internal("bad list higher".into())),
        }
    }

    fn apply_closure_n(&mut self, func: &Value, args: Vec<Value>) -> Result<Value, Err> {
        match func {
            Value::Closure(c) => self.apply(c.clone(), args)?.into_ok(),
            _ => Err(Err::Internal("higher-order got a non-function".into())),
        }
    }

    /// The language's total sort order: NaN-holding values last (stable), user
    /// enum/union values by declaration order. Used by list-sort, comparisons,
    /// min/max, list-min/max.
    pub fn compare(&self, a: &Value, b: &Value) -> Ordering {
        use Value::*;
        let an = a.is_nan_holding();
        let bn = b.is_nan_holding();
        match (an, bn) {
            (true, true) => Ordering::Equal,
            (true, false) => Ordering::Greater, // NaN sorts last
            (false, true) => Ordering::Less,
            (false, false) => self.compare_orderable(a, b),
        }
    }

    fn compare_orderable(&self, a: &Value, b: &Value) -> Ordering {
        use Value::*;
        match (a, b) {
            (Int { v: x, .. }, Int { v: y, .. }) => x.cmp(y),
            (Int { v: x, .. }, Float(y)) => (*x as f64).partial_cmp(y).unwrap_or(Ordering::Equal),
            (Float(x), Int { v: y, .. }) => x.partial_cmp(&(*y as f64)).unwrap_or(Ordering::Equal),
            (Float(x), Float(y)) => x.partial_cmp(y).unwrap_or(Ordering::Equal),
            (Str(x), Str(y)) => x.cmp(y),
            (Bool(x), Bool(y)) => x.cmp(y),
            (Tagged(t1, p1), Tagged(t2, p2)) => {
                // declaration-order index for user types
                let i1 = self.tag_order.get(t1).copied().unwrap_or(self.tag_order.len());
                let i2 = self.tag_order.get(t2).copied().unwrap_or(self.tag_order.len());
                i1.cmp(&i2).then_with(|| cmp_lists(self, p1, p2))
            }
            (List(xs), List(ys)) => cmp_lists(self, xs, ys),
            (Unit, Unit) => Ordering::Equal,
            // unrelated types / records / maps: not compared in the corpus
            _ => Ordering::Equal,
        }
    }

    // ---------------------------------------------------------- coercions

    pub fn as_bool(&self, v: &Value, what: &str) -> Result<bool, Err> {
        match v {
            Value::Bool(b) => Ok(*b),
            _ => Err(Err::Internal(format!("{}: expected Bool", what))),
        }
    }
    pub fn as_str<'v>(&self, v: &'v Value) -> Result<&'v str, Err> {
        match v {
            Value::Str(s) => Ok(s),
            _ => Err(Err::Internal("expected String".into())),
        }
    }
    pub fn as_i64(&self, v: &Value) -> Result<i64, Err> {
        match v {
            Value::Int { v, .. } => Ok(*v),
            _ => Err(Err::Internal("expected Int".into())),
        }
    }
    pub fn as_f64(&self, v: &Value) -> Result<f64, Err> {
        match v {
            Value::Float(x) => Ok(*x),
            Value::Int { v, .. } => Ok(*v as f64),
            _ => Err(Err::Internal("expected Float".into())),
        }
    }
    pub fn as_list<'v>(&self, v: &'v Value) -> Result<&'v Vec<Value>, Err> {
        match v {
            Value::List(xs) => Ok(xs),
            _ => Err(Err::Internal("expected List".into())),
        }
    }
    pub fn as_map<'v>(&self, v: &'v Value) -> Result<&'v BTreeMap<MapKey, Value>, Err> {
        match v {
            Value::Map(m) => Ok(m),
            _ => Err(Err::Internal("expected Map".into())),
        }
    }
    pub fn key(&self, v: &Value) -> Result<MapKey, Err> {
        MapKey::from_value(v)
            .ok_or_else(|| Err::Internal("map key is not orderable".into()))
    }

    fn field(&mut self, v: &Value, f: &str) -> Result<Step, Err> {
        match v {
            Value::Record(fs) => {
                for (n, val) in fs {
                    if n == f {
                        return Ok(Step::OK(val.clone()));
                    }
                }
                Err(Err::Internal(format!("no field {} in record", f)))
            }
            Value::Tagged(t, a) if t == "pair" && a.len() == 2 => {
                if f == "first" {
                    Ok(Step::OK(a[0].clone()))
                } else if f == "second" {
                    Ok(Step::OK(a[1].clone()))
                } else {
                    Err(Err::Internal(format!("bad pair field {}", f)))
                }
            }
            _ => Err(Err::Internal(format!("field access on non-record: {}", f))),
        }
    }

    // ----------------------------------------------------------------- patterns

    fn pmatch(&mut self, pat: &Pattern, v: &Value, binds: &mut BTreeMap<String, Value>) -> bool {
        match pat {
            Pattern::Wildcard => true,
            Pattern::Bind(n) => {
                binds.insert(n.clone(), v.clone());
                true
            }
            Pattern::Bool(b) => matches!(v, Value::Bool(x) if x == b),
            Pattern::Int(digits) => {
                let w = self.lit_hint.take().unwrap_or(NumericWidth::I64);
                match num::parse_int_lit(digits, w) {
                    Ok(n) => matches!(v, Value::Int { v, .. } if *v == n),
                    Err(_) => false,
                }
            }
            Pattern::Float(f) => matches!(v, Value::Float(x) if x == f),
            Pattern::Str(s) => matches!(v, Value::Str(x) if x == s),
            Pattern::Ok(p) => match v {
                Value::Tagged(t, a) if t == "ok" && !a.is_empty() => self.pmatch(p, &a[0], binds),
                _ => false,
            },
            Pattern::Err(p) => match v {
                Value::Tagged(t, a) if t == "err" && !a.is_empty() => self.pmatch(p, &a[0], binds),
                _ => false,
            },
            Pattern::Some(p) => match v {
                Value::Tagged(t, a) if t == "some" && !a.is_empty() => self.pmatch(p, &a[0], binds),
                _ => false,
            },
            Pattern::None => matches!(v, Value::Tagged(t, _) if t == "none"),
            Pattern::List => matches!(v, Value::List(x) if x.is_empty()),
            Pattern::Cons(ph, pt) => match v {
                Value::List(xs) if !xs.is_empty() => {
                    self.pmatch(ph, &xs[0], binds)
                        && self.pmatch(pt, &Value::List(xs[1..].to_vec()), binds)
                }
                _ => false,
            },
            Pattern::Pair(pa, pb) => match v {
                Value::Tagged(t, a) if t == "pair" && a.len() == 2 => {
                    self.pmatch(pa, &a[0], binds) && self.pmatch(pb, &a[1], binds)
                }
                _ => false,
            },
            Pattern::Case(name, subs) => match v {
                Value::Tagged(t, args) if name == t => {
                    if subs.len() != args.len() {
                        return false;
                    }
                    for (p, a) in subs.iter().zip(args.iter()) {
                        if !self.pmatch(p, a, binds) {
                            return false;
                        }
                    }
                    true
                }
                _ => false,
            },
        }
    }

    // ------------------------------------------------------------------ I/O

    fn read_line(&mut self) -> Result<Value, Err> {
        io::read_line()
    }

    fn read_all(&mut self) -> Result<Value, Err> {
        io::read_all()
    }
}

fn cmp_lists(i: &Interp, a: &[Value], b: &[Value]) -> Ordering {
    for (x, y) in a.iter().zip(b.iter()) {
        let ord = i.compare(x, y);
        if ord != Ordering::Equal {
            return ord;
        }
    }
    a.len().cmp(&b.len())
}

fn width_or(w: NumericWidth, fallback: NumericWidth) -> NumericWidth {
    if w == NumericWidth::I32 { NumericWidth::I32 } else { fallback }
}

fn math_fmod(a: f64, b: f64) -> f64 {
    if b == 0.0 { return f64::NAN; }
    let r = a % b;
    if (a < 0.0) != (r < 0.0) && r != 0.0 {
        r + b
    } else {
        r
    }
}

pub fn construct(head: &str, vals: Vec<Value>) -> Value {
    match head {
        "ok" => Value::Tagged("ok".to_string(), vals),
        "err" => Value::Tagged("err".to_string(), vals),
        "some" => Value::Tagged("some".to_string(), vals),
        "none" => Value::Tagged("none".to_string(), vec![]),
        "pair" => Value::Tagged("pair".to_string(), vals),
        "list" => Value::List(vals),
        other if io::IO_ERROR_CASES.contains(&other) => Value::Tagged(other.to_string(), vals),
        other => Value::Tagged(other.to_string(), vals),
    }
}

pub fn key_to_value(k: &MapKey) -> Value {
    match k {
        MapKey::S(s) => Value::Str(s.clone()),
        MapKey::I(i) => Value::int(*i, NumericWidth::I64),
        MapKey::B(b) => Value::Bool(*b),
        MapKey::L(ks) => Value::List(ks.iter().map(key_to_value).collect()),
    }
}

pub fn exit_glue(v: &Value) -> i32 {
    match v {
        Value::Tagged(t, _) if t == "ok" => 0,
        Value::Tagged(t, a) if t == "err" => {
            if let Some(Value::Tagged(c, _)) = a.first() {
                eprintln!("{}", c);
            }
            1
        }
        _ => {
            eprintln!("main must return a Result");
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::modules::parse_source;

    fn interp(src: &str) -> Interp<'static> {
        let tree = parse_source(src).expect("test source parses");
        let unit = crate::modules::build_unit_from(&tree, src.as_bytes());
        let program = Program { units: vec![("root".to_string(), unit)] };
        let units_ref: &'static mut Program = Box::leak(Box::new(program));
        Interp::new(units_ref, vec![]).expect("interp links")
    }

    fn f(v: f64) -> Value { Value::Float(v) }

    #[test]
    fn nan_sorts_last_and_ties_with_equal() {
        let i = interp("(defun f [] -> Int64 1)");
        // NaN vs NaN: stable tie
        assert_eq!(i.compare(&f(f64::NAN), &f(f64::NAN)), Ordering::Equal);
        // NaN last: NAN > 1.0 and NAN < 1.0 are both Less/Greater accordingly
        assert_eq!(i.compare(&f(f64::NAN), &f(1.0)), Ordering::Greater);
        assert_eq!(i.compare(&f(1.0), &f(f64::NAN)), Ordering::Less);
    }

    #[test]
    fn two_nan_sort_is_stable() {
        // Two NaN-holding values that compare Equal but are distinguishable by
        // shape: a bare NaN float and a list wrapping a NaN. A stable sort must
        // keep their input order after both sort after the finite floats.
        let i = interp("(defun f [] -> Int64 1)");
        let bare = Value::Float(f64::NAN);
        let wrapped = Value::List(vec![Value::Float(f64::NAN)]);
        assert_eq!(i.compare(&bare, &wrapped), Ordering::Equal);
        let mut v = vec![bare.clone(), wrapped.clone(), f(1.0), f(2.0)];
        v.sort_by(|a, b| i.compare(a, b));
        assert!(matches!(&v[0], Value::Float(x) if *x == 1.0));
        assert!(matches!(&v[1], Value::Float(x) if *x == 2.0));
        assert!(matches!(&v[2], Value::Float(x) if x.is_nan()));
        assert!(matches!(&v[3], Value::List(_)));
    }

    #[test]
    fn map_keys_iterate_in_codepoint_order() {
        // BTreeMap key order = codepoint order. Order is asserted indirectly by
        // map-pairs producing the round-tripped sequence, not a HashMap's order.
        let pairs = vec![
            Value::Tagged("pair".into(), vec![Value::Str("b".into()), Value::int(1, NumericWidth::I64)]),
            Value::Tagged("pair".into(), vec![Value::Str("a".into()), Value::int(2, NumericWidth::I64)]),
        ];
        let m = crate::builtins::m_from(&pairs).expect("map builds");
        let keys: Vec<String> = m.keys()
            .map(|k| match k { MapKey::S(s) => s.clone(), _ => String::new() })
            .collect();
        assert_eq!(keys, vec!["a".to_string(), "b".to_string()]);
    }
}
