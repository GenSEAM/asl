#!/usr/bin/env python3
"""The type layer: rules 3, 5 and 6, and everything they imply.

Generalisation happens only at declarations, over their { } binders — a type
variable is a declared thing (rule 10), never something inferred into existence.
Inside a body those variables are rigid; at a call site the callee's are fresh
metavariables, which is what makes inference at call sites (PCP r-8f23) work
without let-generalisation.

`N` is the one constrained variable in the vocabulary, and an unsuffixed integer
literal is the one constrained literal. Both are metavariables carrying the set
they may still become; rule 6 falls out of that rather than being checked
separately, because no implicit conversion means one numeric type per form.
"""
import sys
from pathlib import Path

from lark import Token, Tree

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "prelude"))

from collect import Module  # noqa: E402
from parse import kids, tok  # noqa: E402
from vocab import parse_signature, signatures, type_aliases, unions  # noqa: E402

NUMERIC = {"Int32", "Int64", "Float64"}
INTEGRAL = {"Int32", "Int64"}
KIND_SET = {"any": None, "num": NUMERIC, "int": INTEGRAL}
TAGS = {"some": 1, "none": 0, "ok": 1, "err": 1, "list": 0, "cons": 2, "pair": 2}
# A prelude union's cases are nullary constructors; nothing downstream should
# care whether a union came from the prelude or from a user `defenum`.
PRELUDE_CASES = {case: name for name, cases in unions().items() for case in cases}


class Mismatch(Exception):
    def __init__(self, left, right, numeric: bool):
        super().__init__(f"expected {show(left)}, found {show(right)}")
        self.numeric = numeric


class Var:
    _n = 0

    def __init__(self, kind: str = "any"):
        Var._n += 1
        self.id = Var._n
        self.kind = kind
        self.ref = None


class Con:
    """A nominal type. `mod` is the path of the module that DECLARED it and is
    part of its identity; the name alone is not, because two modules may declare
    the same one. Built-ins carry no module. `shown` is the spelling the source
    used, kept so a diagnostic reads back as written rather than as a key."""

    def __init__(self, name: str, args=(), mod: str | None = None,
                 shown: str | None = None):
        self.name = name
        self.args = tuple(args)
        self.mod = mod
        self.shown = shown


class Fun:
    def __init__(self, params, ret):
        self.params = tuple(params)
        self.ret = ret


def prune(t):
    while isinstance(t, Var) and t.ref is not None:
        t = t.ref
    return t


def show(t) -> str:
    t = prune(t)
    if isinstance(t, Var):
        return {"any": "_", "num": "a number", "int": "an integer"}[t.kind]
    if isinstance(t, Fun):
        return f"(fn [{' '.join(show(p) for p in t.params)}] -> {show(t.ret)})"
    name = t.shown or (t.name[1:] if t.name.startswith("#") else t.name)
    return f"({name} {' '.join(show(a) for a in t.args)})" if t.args else name


def _narrow(kind: str, other: str) -> str | None:
    order = ["any", "num", "int"]
    if kind == "any":
        return other
    if other == "any":
        return kind
    return kind if order.index(kind) >= order.index(other) else other


def unify(a, b) -> None:
    a, b = prune(a), prune(b)
    if a is b:
        return
    if isinstance(a, Var) or isinstance(b, Var):
        var, other = (a, b) if isinstance(a, Var) else (b, a)
        if isinstance(other, Var):
            kind = _narrow(var.kind, other.kind)
            other.kind = kind
            var.ref = other
            return
        allowed = KIND_SET[var.kind]
        if allowed is not None and not (isinstance(other, Con) and other.name in allowed):
            raise Mismatch(var, other, numeric=isinstance(other, Con) and other.name in NUMERIC)
        var.ref = other
        return
    if isinstance(a, Fun) and isinstance(b, Fun):
        if len(a.params) != len(b.params):
            raise Mismatch(a, b, numeric=False)
        for p, q in zip(a.params, b.params):
            unify(p, q)
        unify(a.ret, b.ret)
        return
    if isinstance(a, Con) and isinstance(b, Con):
        if a.name != b.name or a.mod != b.mod or len(a.args) != len(b.args):
            raise Mismatch(a, b, numeric=a.name in NUMERIC and b.name in NUMERIC)
        for p, q in zip(a.args, b.args):
            unify(p, q)
        return
    raise Mismatch(a, b, numeric=False)


def from_json(spec: dict, fresh: dict):
    """A parsed prelude signature -> a type, instantiating its variables."""
    if "var" in spec:
        name = spec["var"]
        if name not in fresh:
            fresh[name] = Var("num" if name == "N" else "any")
        return fresh[name]
    if "fn" in spec:
        return Fun([from_json(p, fresh) for p in spec["fn"]], from_json(spec["ret"], fresh))
    return Con(spec["con"], [from_json(a, fresh) for a in spec["args"]])


class Types:
    """Declaration types, drawn from the tree, with type variables either rigid
    (inside the body that binds them) or fresh (at a call site)."""

    def __init__(self, mod: Module, report, loader):
        self.mod = mod
        self.report = report
        self.loader = loader
        self.aliases = type_aliases()
        self.builtins = {name: parse_signature(sig) for name, sig in signatures().items()}
        self.ret_type = None                  # enclosing defun's declared return
        self.in_lambda = False
        self.lambdas: list = []

    # ---------- declared types ----------

    def declared(self, node: Tree, rigid: set[str], fresh: dict | None = None, owner=None):
        """A `type` tree -> a type, read in `owner`'s scope so an imported
        signature's names resolve where they were written. Names in `rigid` stay
        rigid; if `fresh` is given they instead become shared metavariables,
        which is instantiation."""
        owner = owner or self.mod
        parts = node.children
        args = [self.declared(p, rigid, fresh, owner) for p in parts[1:]]
        head = parts[0]
        if isinstance(head, Token) and head.type == "QUALIFIED_TYPE":
            return self.imported_con(head, args, owner)
        name = self.aliases.get(str(head), str(head))
        if name in rigid:
            if fresh is None:
                return Con("#" + name)
            return fresh.setdefault(name, Var())
        declaring = owner.name if name in owner.schemas or name in owner.enums else None
        return Con(name, args, declaring)

    def imported_con(self, token: Token, args, owner):
        """Keyed by the module that defines the type, never by the alias: the
        alias is module-local, so two of them for one module must give one type
        and two modules' same-named types must give two."""
        alias, _, member = str(token).partition("/")
        target = self.loader.load(owner.imports.get(alias, ""))
        return Con(member, args, target.name if target is not None else None, str(token))

    def module_of(self, con: Con):
        """The module a nominal type was declared in, found by its key rather
        than by an alias."""
        if con.mod is None or con.mod == self.mod.name:
            return self.mod
        for path in self.mod.imports.values():
            target = self.loader.load(path)
            if target is not None and target.name == con.mod:
                return target
        return None

    def case_type(self, owner, enum_name: str, case: str, alias: str | None) -> Fun:
        """A union case is a constructor whose return type is its union, carrying
        the union's defining module."""
        enum = owner.enums[enum_name]
        fresh: dict = {}
        params = [self.declared(t, enum.typevars, fresh, owner) for _, t in enum.cases[case]]
        ret = Con(enum.name, [fresh.setdefault(v, Var()) for v in sorted(enum.typevars)],
                  owner.name, f"{alias}/{enum.name}" if alias else None)
        return Fun(params, ret)

    def fun_type(self, fun, rigid_ok: bool, owner=None):
        rigid = fun.typevars
        fresh = None if rigid_ok else {}
        return Fun([self.declared(t, rigid, fresh, owner) for _, t in fun.params],
                   self.declared(fun.ret, rigid, fresh, owner))

    def lookup(self, name: str):
        if name in self.mod.funs:
            return self.fun_type(self.mod.funs[name], rigid_ok=False)
        if name in self.builtins:
            args, variadic, ret = self.builtins[name]
            fresh: dict = {}
            params = [from_json(a, fresh) for a in args]
            return Fun(params, from_json(ret, fresh)), variadic
        case_owner = self.mod.case_owner
        if name in case_owner:
            return self.case_type(self.mod, case_owner[name], name, None)
        return None

    def qualified(self, text: str):
        alias, _, member = text.partition("/")
        target = self.loader.load(self.mod.imports.get(alias, ""))
        if target is None:
            return None
        if member in target.funs:
            return self.fun_type(target.funs[member], rigid_ok=False, owner=target)
        if member in target.exported_cases:
            return self.case_type(target, target.exported_cases[member], member, alias)
        return None

    # ---------- expressions ----------

    def check_module(self) -> None:
        self.field_defaults()
        for fun in self.mod.funs.values():
            env = {name: self.declared(t, fun.typevars) for name, t in fun.params}
            self.ret_type = self.declared(fun.ret, fun.typevars)
            body = [k for k in kids(fun.node) if isinstance(k, Tree) and k.data == "expr"]
            for e in body[:-1]:
                self.infer(e, env)
            self.expect(body[-1], env, self.ret_type, f"return of {fun.name}")
        self.undetermined_lambdas()

    def field_defaults(self) -> None:
        """§4.1's default stands in for a value the constructor omits, so it has
        to be one: an ill-typed default is a mismatch every caller inherits and
        no construction site can be blamed for."""
        for schema in self.mod.schemas.values():
            for fname, literal in schema.defaults.items():
                want = self.declared(schema.fields[fname][0], schema.typevars)
                self.expect(literal, {}, want, f"default for {schema.name}.{fname}")

    def undetermined_lambdas(self) -> None:
        """Elision is legal where the position determines the type. Where it did
        not, the annotation is required — otherwise the program is typed only by
        accident of what the body happens to allow."""
        for node, params, ret in self.lambdas:
            loose = [p for p in (*params, ret) if isinstance(prune(p), Var)]
            if loose:
                self.report("annotation",
                            "nothing in this position determines the lambda's types; "
                            "write them", node)

    def expect(self, node, env, want, where: str):
        got = self.infer(node, env)
        if got is None:
            return
        try:
            unify(want, got)
        except Mismatch as exc:
            self.report("rule-6" if exc.numeric else "type", f"{where}: {exc}", node)

    def infer(self, node, env):
        if isinstance(node, Token):
            return self.atom(node, env)
        if node.data == "expr":
            return self.infer(node.children[0], env)
        handler = getattr(self, f"_{node.data}", None)
        return handler(node, env) if handler else None

    def atom(self, token: Token, env):
        text = str(token)
        if token.type == "INT":
            return Var("int")
        if token.type == "FLOAT":
            return Con("Float64")
        if token.type == "STRING":
            return Con("String")
        if token.type == "BOOL":
            return Con("Bool")
        if token.type == "UNIT":
            return Con("Unit")
        if token.type == "QUALIFIED":
            return self.qualified(text)
        if text in env:
            return env[text]
        found = self.lookup(text)
        if isinstance(found, tuple):
            return found[0]
        return found

    def _literal(self, node, env):
        return self.atom(node.children[0], env)

    def _call(self, node, env):
        parts = [k for k in node.children if isinstance(k, Tree) and k.data == "expr"]
        head, args = parts[0], parts[1:]
        inner = head.children[0]
        variadic = False
        if isinstance(inner, Token) and str(inner) not in env:
            found = (self.lookup(str(inner)) if inner.type != "QUALIFIED"
                     else self.qualified(str(inner)))
            if isinstance(found, tuple):
                found, variadic = found
            callee = found
        else:
            callee = self.infer(head, env)
        if callee is None:
            for a in args:
                self.infer(a, env)
            return None
        callee = prune(callee)
        if not isinstance(callee, Fun):
            for a in args:
                self.infer(a, env)
            return None
        params = list(callee.params)
        if variadic and params:
            params = [params[-1]] * len(args) if len(args) >= len(params) else params
        if len(params) != len(args):
            for a in args:
                self.infer(a, env)
            return callee.ret                 # arity is reported by the resolve pass
        for want, arg in zip(params, args):
            self.expect(arg, env, want, f"argument to {self.head_name(inner)}")
        return callee.ret

    @staticmethod
    def head_name(inner) -> str:
        return str(inner) if isinstance(inner, Token) else "a call"

    def _let_form(self, node, env):
        inner = dict(env)
        last = None
        for k in node.children:
            if isinstance(k, Tree) and k.data == "binding":
                inner[tok(k.children[0])] = self.infer(k.children[1], inner) or Var()
            elif isinstance(k, Tree) and k.data == "expr":
                last = self.infer(k, inner)
        return last

    def _if_form(self, node, env):
        cond, a, b = kids(node)
        self.expect(cond, env, Con("Bool"), "if condition")
        ta = self.infer(a, env)
        self.expect(b, env, ta or Var(), "if branches")
        return ta

    def _cond_form(self, node, env):
        result = Var()
        for clause in kids(node):
            body = [k for k in clause.children if isinstance(k, Tree) and k.data == "expr"]
            if clause.data == "cond_clause":
                self.expect(body[0], env, Con("Bool"), "cond test")
                body = body[1:]
            for e in body[:-1]:
                self.infer(e, env)
            self.expect(body[-1], env, result, "cond branches")
        return result

    def _fn_form(self, node, env):
        body = kids(node)
        rigid = {v for f in self.mod.funs.values() for v in f.typevars}
        params = []
        for p in body[0].children:
            if not (isinstance(p, Tree) and p.data == "fn_param"):
                continue
            parts = kids(p)
            # An elided annotation becomes a metavariable, which the callee's
            # signature binds when this lambda is unified into its argument
            # position. That is what makes elision safe rather than untyped.
            params.append((tok(parts[0]),
                           self.declared(parts[1], rigid) if len(parts) > 1 else Var()))
        rest = list(body[1:])
        if rest and isinstance(rest[0], Tree) and rest[0].data == "type":
            ret = self.declared(rest[0], rigid)
            rest = rest[1:]
        else:
            ret = Var()
        inner = dict(env)
        inner.update(dict(params))
        exprs = [k for k in rest if isinstance(k, Tree) and k.data == "expr"]
        was, self.in_lambda = self.in_lambda, True
        for e in exprs[:-1]:
            self.infer(e, inner)
        self.expect(exprs[-1], inner, ret, "lambda body")
        self.in_lambda = was
        self.lambdas.append((node, [ty for _, ty in params], ret))
        return Fun([ty for _, ty in params], ret)

    def _try_form(self, node, env):
        inner = [k for k in node.children if isinstance(k, Tree) and k.data == "expr"][0]
        if self.in_lambda:
            # try returns from the enclosing defun, and a lambda is not one; the
            # specification does not say what this means, so it is refused.
            self.report("rule-5", "try inside fn: it would return from the enclosing "
                                  "defun, not from the lambda", node)
            return self.infer(inner, env)
        ret = prune(self.ret_type) if self.ret_type is not None else None
        if not (isinstance(ret, Con) and ret.name == "Result"):
            self.report("rule-5", "try outside a defun returning (Result _ E)", node)
            return self.infer(inner, env)
        value = Var()
        self.expect(inner, env, Con("Result", [value, ret.args[1]]), "try")
        return value

    def _ctor(self, node, env):
        head = node.children[0]
        name = str(head)
        if isinstance(head, Token) and head.type == "QUALIFIED_TYPE":
            alias, _, member = name.partition("/")
            owner, shown = self.loader.load(self.mod.imports.get(alias, "")), name
        else:
            owner, member, shown = self.mod, name, None
        schema = owner.schemas.get(member) if owner is not None else None
        if schema is None:
            return None
        fresh: dict = {}
        for arg in node.children[1:]:
            key = str(arg.children[0])[1:]
            if key in schema.fields:
                want = self.declared(schema.fields[key][0], schema.typevars, fresh, owner)
                self.expect(arg.children[1], env, want, f"field {name}.{key}")
            else:
                self.infer(arg.children[1], env)
        return Con(member, [fresh.setdefault(v, Var()) for v in sorted(schema.typevars)],
                   owner.name, shown)

    def _field_access(self, node, env):
        field = str(node.children[0])[2:]
        target = prune(self.infer(node.children[1], env) or Var())
        if not isinstance(target, Con):
            return None
        if target.name == "Pair" and field in ("first", "second"):
            return target.args[0] if field == "first" else target.args[1]
        owner = self.module_of(target)
        schema = owner.schemas.get(target.name) if owner is not None else None
        if schema is None or field not in schema.fields:
            self.report("type", f"{show(target)} has no field {field}", node.children[0])
            return None
        fresh = dict(zip(sorted(schema.typevars), target.args))
        return self.declared(schema.fields[field][0], schema.typevars, fresh, owner)

    def _match_form(self, node, env):
        body = kids(node)
        scrutinee = self.infer(body[0], env) or Var()
        result = Var()
        for arm in body[1:]:
            inner = dict(env)
            self.pattern(arm.children[0], scrutinee, inner)
            exprs = [k for k in arm.children[1:] if isinstance(k, Tree) and k.data == "expr"]
            for e in exprs[:-1]:
                self.infer(e, inner)
            self.expect(exprs[-1], inner, result, "match arms")
        return result

    def pattern(self, node: Tree, want, env: dict) -> None:
        if node.data == "enum_pattern":
            parts = kids(node)
            head = tok(parts[0])
            subs = [p for p in parts[1:]
                    if isinstance(p, Tree) and p.data in ("pattern", "enum_pattern")]
            types = self.pattern_types(head, want, node)
            for sub, sub_want in zip(subs, types or [Var()] * len(subs)):
                self.pattern(sub, sub_want, env)
            return
        child = node.children[0]
        if isinstance(child, Token) and child.type == "IDENT":
            env[str(child)] = want
        elif isinstance(child, Tree) and child.data == "enum_pattern":
            self.pattern(child, want, env)
        elif isinstance(child, Tree) and child.data == "literal":
            self.expect(child, env, want, "pattern")

    def case_owner_of(self, head: str):
        """(defining module, union, alias, case name) for a pattern head, local
        or alias-qualified."""
        alias, sep, member = head.partition("/")
        if sep:
            owner = self.loader.load(self.mod.imports.get(alias, ""))
            if owner is None or member not in owner.exported_cases:
                return None
            return owner, owner.enums[owner.exported_cases[member]], alias, member
        if head in self.mod.case_owner:
            return self.mod, self.mod.enums[self.mod.case_owner[head]], None, head
        return None

    def pattern_types(self, head: str, want, node) -> list | None:
        """Types the sub-patterns of a constructor pattern must have, unifying
        the scrutinee with the union that constructor belongs to."""
        shapes = {
            "some": lambda v: (Con("Option", [v[0]]), [v[0]]),
            "none": lambda v: (Con("Option", [v[0]]), []),
            "ok":   lambda v: (Con("Result", [v[0], v[1]]), [v[0]]),
            "err":  lambda v: (Con("Result", [v[0], v[1]]), [v[1]]),
            "list": lambda v: (Con("List", [v[0]]), []),
            "cons": lambda v: (Con("List", [v[0]]), [v[0], Con("List", [v[0]])]),
            "pair": lambda v: (Con("Pair", [v[0], v[1]]), [v[0], v[1]]),
        }
        if head in PRELUDE_CASES:
            whole, fields = Con(PRELUDE_CASES[head]), []
            try:
                unify(want, whole)
            except Mismatch as exc:
                self.report("type", f"pattern {head}: {exc}", node)
                return None
            return fields
        source = self.case_owner_of(head)
        if source is not None:
            owner, enum, alias, member = source
            fresh: dict = {}
            fields = [self.declared(t, enum.typevars, fresh, owner) for _, t in enum.cases[member]]
            whole = Con(enum.name, [fresh.setdefault(v, Var()) for v in sorted(enum.typevars)],
                        owner.name, f"{alias}/{enum.name}" if alias else None)
        elif head in shapes:
            whole, fields = shapes[head]([Var(), Var()])
        else:
            return None
        try:
            unify(want, whole)
        except Mismatch as exc:
            self.report("type", f"pattern {head}: {exc}", node)
            return None
        return fields
