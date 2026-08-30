//! Convert the tree-sitter CST into the owned AST.
//!
//! Every `_expr` alternative and every pattern form has a branch here, and an
//! unrecognized node kind is an error naming the kind and position rather than a
//! silent skip (the c-2d38 lesson). Type nodes are recognized and erased but
//! never evaluated; a node in type position that cannot be recognized is an
//! error, never a passthrough.
//!
//! tree-sitter's Node methods need the source bytes to read text, so the tree
//! is walked by a Builder that owns the source.

use crate::ast::*;
use tree_sitter::Node;

pub fn syntax_error(node: Node) -> bool {
    node.is_error() || node.is_missing()
}

/// Walks the whole tree and returns the first ERROR/MISSING node, if any.
pub fn find_error(node: Node) -> Option<Node> {
    if syntax_error(node) {
        return Some(node);
    }
    let mut c = node.walk();
    for child in node.children(&mut c) {
        if let Some(e) = find_error(child) {
            return Some(e);
        }
    }
    None
}

pub struct Builder<'src> {
    src: &'src [u8],
}

impl<'src> Builder<'src> {
    pub fn new(src: &'src [u8]) -> Self {
        Builder { src }
    }

    fn text(&self, node: Node) -> String {
        node.utf8_text(self.src).map(|s| s.to_string()).unwrap_or_default()
    }

    /// Child tagged with a field name.
    fn field<'a>(&self, node: Node<'a>, name: &str) -> Option<Node<'a>> {
        node.child_by_field_name(name)
    }

    /// Every child tagged with a field name (a fielded repeat in the grammar).
    fn fields<'a>(&self, node: Node<'a>, name: &str) -> Vec<Node<'a>> {
        let mut c = node.walk();
        node.children_by_field_name(name, &mut c).collect()
    }

    fn children<'a>(&self, node: Node<'a>) -> Vec<Node<'a>> {
        let mut out = vec![];
        let mut c = node.walk();
        for k in node.children(&mut c) {
            // The grammar attaches anonymous tokens ((, ), [, ], ->, keywords)
            // as unnamed children; only named nodes carry structure.
            if k.is_named() {
                out.push(k);
            }
        }
        out
    }

    fn span(&self, node: Node) -> Span {
        Span {
            line: node.start_position().row + 1,
            col: node.start_position().column + 1,
        }
    }

    // ------------------------------------------------------------ types

    fn parse_type(&self, node: Node) -> Type {
        let t = self.text(node);
        match node.kind() {
            "type_name" => match t.as_str() {
                "Int32" => Type::Int32,
                "Int64" => Type::Int64,
                "Float64" => Type::Float64,
                other => Type::Named(other.to_string()),
            },
            "qualified_type" => {
                let (a, m) = t.split_once('/').expect("qualified_type always has /");
                Type::Qualified(a.to_string(), m.to_string())
            }
            "type_app" => {
                let ch = self.children(node);
                let head = ch[0];
                let inner: Vec<Type> = ch[1..].iter().map(|c| self.parse_type(*c)).collect();
                Type::App(Box::new(self.parse_type(head)), inner)
            }
            other => panic!("unrecognized type node: {} at {}", other, t),
        }
    }

    // --------------------------------------------------------- expressions

    fn parse_expr(&self, node: Node) -> Expr {
        if node.is_missing() || node.is_error() || node.kind() == "ERROR" {
            panic!("syntax error in expression at line {}", self.span(node).line);
        }
        match node.kind() {
            "int" => {
                Expr::Int(IntLit { digits: self.text(node), width: None, span: self.span(node) })
            }
            "float" => Expr::Float(self.text(node).parse().expect("float literal must parse")),
            "string" => {
                let raw = self.text(node);
                Expr::Str(unescape(&raw[1..raw.len() - 1]))
            }
            "bool" => Expr::Bool(self.text(node) == "true"),
            "unit" => Expr::Unit,
            "operator" => Expr::Ident(self.text(node)),
            "ident" => Expr::Ident(self.text(node)),
            "qualified" => {
                let t = self.text(node);
                let (a, m) = t.split_once('/').expect("qualified always has /");
                Expr::Qualified(a.to_string(), m.to_string())
            }
            "let_form" => {
                let mut bindings = vec![];
                for child in self.children(node) {
                    if child.kind() == "binding" {
                        let n = self.field(child, "name").unwrap();
                        let v = self.field(child, "value").unwrap();
                        bindings.push((self.text(n), self.parse_expr(v)));
                    }
                }
                let body: Vec<Expr> = self.body_exprs(node);
                Expr::Let(bindings, body)
            }
            "if_form" => {
                let f = self.field(node, "condition").unwrap();
                let c = self.field(node, "consequence").unwrap();
                let a = self.field(node, "alternative").unwrap();
                Expr::If(Box::new(self.parse_expr(f)), Box::new(self.parse_expr(c)),
                         Box::new(self.parse_expr(a)))
            }
            "cond_form" => {
                let mut clauses = vec![];
                for child in self.children(node) {
                    if child.kind() == "cond_clause" {
                        let cond = self.field(child, "condition").unwrap();
                        let body: Vec<Expr> = self.body_exprs(child);
                        clauses.push(CondClause {
                            condition: Some(self.parse_expr(cond)),
                            body,
                        });
                    } else if child.kind() == "else_clause" {
                        let body: Vec<Expr> = self.body_exprs(child);
                        clauses.push(CondClause { condition: None, body });
                    }
                }
                Expr::Cond(clauses)
            }
            "match_form" => {
                let subj = self.field(node, "subject").unwrap();
                let mut arms = vec![];
                for child in self.children(node) {
                    if child.kind() == "match_arm" {
                        let pat = self.field(child, "pattern").unwrap();
                        let body: Vec<Expr> = self.body_exprs(child);
                        arms.push((self.parse_pattern(pat), body));
                    }
                }
                Expr::Match(Box::new(self.parse_expr(subj)), arms)
            }
            "try_form" => {
                let b = self.field(node, "body").unwrap();
                Expr::Try(Box::new(self.parse_expr(b)))
            }
            "fn_form" => {
                let params = self.field(node, "params").unwrap();
                let ret = self.field(node, "return_type").map(|n| self.parse_type(n));
                let body: Vec<Expr> = self.body_exprs(node);
                Expr::Fn(FnLit { params: self.parse_fn_params(params), body })
            }
            "constructor_call" => {
                // Head is an anonymous keyword (ok/err/some/none/pair/list);
                // children() drops it, so walk raw children, skipping ( and ).
                let mut kids = vec![];
                let mut c = node.walk();
                for k in node.children(&mut c) {
                    if k.is_named() || (k.kind() != "(" && k.kind() != ")") {
                        kids.push(k);
                    }
                }
                let head = self.text(kids[0]);
                let args: Vec<Expr> = kids[1..].iter()
                    .map(|a| self.parse_expr(*a))
                    .collect();
                Expr::Ctor(head, args)
            }
            "ctor" => {
                let type_node = self.field(node, "type").unwrap();
                let type_text = self.text(type_node);
                let mut fields = vec![];
                for a in (1..node.child_count()).map(|i| node.child(i).unwrap()) {
                    if a.kind() == "ctor_arg" {
                        let key = self.field(a, "key").unwrap();
                        let v = self.field(a, "value").unwrap();
                        fields.push((strip_key(&self.text(key)), self.parse_expr(v)));
                    }
                }
                Expr::Record(qual_type_name(&type_text), fields)
            }
            "field_access" => {
                let f = self.field(node, "field").unwrap();
                let t = self.field(node, "target").unwrap();
                Expr::FieldAccess {
                    field: self.text(f).trim_start_matches(".-").to_string(),
                    target: Box::new(self.parse_expr(t)),
                }
            }
            "call" => {
                let callee = self.field(node, "callee").unwrap();
                let args: Vec<Expr> = self.fields(node, "argument").into_iter()
                    .map(|a| self.parse_expr(a))
                    .collect();
                Expr::Call(Box::new(self.parse_expr(callee)), args)
            }
            other => panic!("unrecognized expression node: {} at line {}", other, self.span(node).line),
        }
    }

    /// The `body` fielded repeat of an expr form, as expressions.
    fn body_exprs(&self, node: Node) -> Vec<Expr> {
        self.fields(node, "body").into_iter().map(|b| self.parse_expr(b)).collect()
    }

    const FIELD: &'static str = "body";

    fn parse_fn_params(&self, node: Node) -> Vec<Param> {
        let mut out = vec![];
        for child in self.children(node) {
            let name = self.field(child, "name").unwrap();
            let ty = self.field(child, "type")
                .map(|n| self.parse_type(n))
                .unwrap_or(Type::Named("erased".to_string()));
            out.push(Param { name: self.text(name), ty });
        }
        out
    }

    // ---------------------------------------------------------- patterns

    fn parse_pattern(&self, node: Node) -> Pattern {
        match node.kind() {
            "ident" => Pattern::Bind(self.text(node)),
            "wildcard" => Pattern::Wildcard,
            "int" => Pattern::Int(self.text(node)),
            "float" => Pattern::Float(self.text(node).parse().expect("float literal in pattern")),
            "string" => {
                let raw = self.text(node);
                Pattern::Str(unescape(&raw[1..raw.len() - 1]))
            }
            "bool" => Pattern::Bool(self.text(node) == "true"),
            "ok_pattern" => Pattern::Ok(Box::new(self.parse_pattern(self.children(node)[0]))),
            "err_pattern" => Pattern::Err(Box::new(self.parse_pattern(self.children(node)[0]))),
            "some_pattern" => Pattern::Some(Box::new(self.parse_pattern(self.children(node)[0]))),
            "none_pattern" => Pattern::None,
            "list_pattern" => Pattern::List,
            "cons_pattern" => {
                let kids = self.children(node);
                Pattern::Cons(
                    Box::new(self.parse_pattern(kids[0])),
                    Box::new(self.parse_pattern(kids[1])),
                )
            }
            "pair_pattern" => {
                let kids = self.children(node);
                Pattern::Pair(
                    Box::new(self.parse_pattern(kids[0])),
                    Box::new(self.parse_pattern(kids[1])),
                )
            }
            "enum_pattern" => {
                // case is a fielded head (ident/qualified); the rest are subpatterns
                let head = self.field(node, "case").unwrap();
                let case = self.text(head);
                let case = case.rsplit('/').next().unwrap_or(&case).to_string();
                // named children after the first are the sub-patterns
                let kids = self.children(node);
                let subs: Vec<Pattern> = kids[1..].iter()
                    .map(|c| self.parse_pattern(*c))
                    .collect();
                Pattern::Case(case, subs)
            }
            "pattern" => self.parse_pattern(node.child(0).unwrap()),
            other => panic!("unrecognized pattern node: {}", other),
        }
    }

    // ---------------------------------------------------------- toplevel

    pub fn build_unit(&self, root: Node) -> Unit {
        let mut module_path = None;
        let mut imports = vec![];
        let mut exports = vec![];
        let mut defuns = vec![];
        let mut schemas = vec![];
        let mut enum_cases = vec![];

        for child in self.children(root) {
            match child.kind() {
                "module_decl" => {
                    if let Some(p) = self.field(child, "path") {
                        module_path = Some(self.text(p));
                    }
                    for opt in self.children(child) {
                        if opt.kind() != "module_opt" {
                            continue;
                        }
                        let kw = opt.child(0).map(|x| self.text(x)).unwrap_or_default();
                        if kw.starts_with(":import") {
                            for sub in self.children(opt) {
                                if sub.kind() == "import_spec" {
                                    let p = self.field(sub, "path").unwrap();
                                    let alias = self.field(sub, "alias").unwrap();
                                    imports.push((self.text(alias), self.text(p)));
                                }
                            }
                        } else if kw.starts_with(":export") {
                            for sub in self.children(opt) {
                                exports.push(self.text(sub));
                            }
                        }
                    }
                }
                "defun" => defuns.push(self.parse_defun(child)),
                "defschema" => schemas.push(self.parse_schema(child)),
                "defenum" => {
                    let name = self.field(child, "name").map(|n| self.text(n)).unwrap_or_default();
                    let mut cases = vec![];
                    for c in 1..child.child_count() {
                        let cc = child.child(c).unwrap();
                        if cc.kind() == "enum_case" {
                            if let Some(n) = self.field(cc, "name") {
                                cases.push(self.text(n));
                            }
                        }
                    }
                    enum_cases.push((name, cases));
                }
                "comment" => {}
                other => panic!("unrecognized toplevel node: {}", other),
            }
        }

        let prelude_unions: &[(&str, &[&str])] = &[("IoError", crate::io::IO_ERROR_CASES)];
        for (name, cases) in prelude_unions {
            if !enum_cases.iter().any(|(n, _)| n == name) {
                enum_cases.push((name.to_string(), cases.iter().map(|s| s.to_string()).collect()));
            }
        }

        Unit {
            module_path,
            imports,
            defuns,
            schemas,
            enum_cases,
            exports,
        }
    }

    fn parse_defun(&self, node: Node) -> Defun {
        let effect = node.child_by_field_name("effect").is_some();
        let name = self.field(node, "name").map(|n| self.text(n)).unwrap_or_default();
        let params = self.field(node, "params").map(|p| self.parse_defun_params(p)).unwrap_or_default();
        let ret = self.field(node, "return_type")
            .map(|n| self.parse_type(n))
            .unwrap_or(Type::Named("erased".to_string()));
        let body: Vec<Expr> = self.body_exprs(node);
        Defun { name, effect, params, ret, body }
    }

    fn parse_defun_params(&self, node: Node) -> Vec<Param> {
        let mut out = vec![];
        for child in self.children(node) {
            if child.kind() == "param" {
                let n = self.field(child, "name").unwrap();
                let ty = self.field(child, "type")
                    .map(|t| self.parse_type(t))
                    .unwrap_or(Type::Named("erased".to_string()));
                out.push(Param { name: self.text(n), ty });
            }
        }
        out
    }

    fn parse_schema(&self, node: Node) -> Schema {
        let name = self.field(node, "name").map(|n| self.text(n)).unwrap_or_default();
        let mut fields = vec![];
        for child in self.children(node) {
            if child.kind() == "field" {
                let fname = self.field(child, "name").map(|n| self.text(n)).unwrap_or_default();
                let default = self.field(child, "default").map(|d| self.parse_expr(d));
                fields.push(SchemaField { name: fname, default });
            }
        }
        Schema { name, fields }
    }
}

fn strip_key(k: &str) -> String {
    k.trim_start_matches(':').to_string()
}

fn qual_type_name(t: &str) -> String {
    t.split('/').next_back().unwrap_or(t).to_string()
}

/// Unescape the six language escapes inside a string literal's content.
pub fn unescape(s: &str) -> String {
    let mut out = String::new();
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some('"') => out.push('"'),
                Some('\\') => out.push('\\'),
                Some('n') => out.push('\n'),
                Some('t') => out.push('\t'),
                Some('r') => out.push('\r'),
                Some('0') => out.push('\0'),
                Some(other) => out.push(other),
                None => {}
            }
        } else {
            out.push(c);
        }
    }
    out
}
