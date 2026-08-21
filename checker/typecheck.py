#!/usr/bin/env python3
"""The type layer: §9 rules 3 and 6, which no other gate can decide.

Named `typecheck` rather than `types`: `checker/` goes on `sys.path`, and a
module called `types` there shadows the standard library's, which `enum` imports
during interpreter start-up. The failure is a circular-import error far from its
cause.

**Bidirectional checking with local inference, not Hindley–Milner.** The language
annotates every binding site — parameters and returns on `defun` and `fn`,
`defschema` fields, `defenum` cases — so the only unannotated position is a `let`
binding. That removes the need for generalisation and leaves first-order
unification, used in one place: instantiating a `{A B}` binder at a call site.

**Unknown is not an error.** A construct this layer cannot type yields `UNKNOWN`,
which unifies with anything. A type checker that fires on the programs the
handbook teaches is worse than no type checker, so every gap fails open. The
cost is stated rather than hidden: silence here is not proof of well-typedness.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from lark import Token, Tree

ROOT = Path(__file__).parent.parent
PRELUDE = json.loads((ROOT / "prelude" / "prelude.json").read_text())

PRIMS = set(PRELUDE["types"]["primitive"])
ALIASES = PRELUDE["types"]["aliases"]
CONSTRUCTED = set(PRELUDE["types"]["constructed"])
RECORDS = PRELUDE["types"]["records"]
NUMERIC = {"Int32", "Int64", "Float64"}

# Single capitals are type variables in a builtin signature; `N` additionally
# means "some numeric type", which is what makes `(+ 1 2.0)` an error rather
# than a promotion.
SIG_VARS = {"T", "A", "B", "K", "V", "E", "F", "N"}


# ---------- the type language ----------

@dataclass(frozen=True)
class Ty:
    pass


@dataclass(frozen=True)
class Prim(Ty):
    name: str

    def __str__(self):
        return self.name


@dataclass(frozen=True)
class Con(Ty):
    name: str
    args: tuple = ()

    def __str__(self):
        return f"({self.name} {' '.join(str(a) for a in self.args)})" if self.args else self.name


@dataclass(frozen=True)
class Var(Ty):
    name: str
    numeric: bool = False

    def __str__(self):
        return self.name


@dataclass(frozen=True)
class FnTy(Ty):
    params: tuple
    ret: Ty
    variadic: bool = False

    def __str__(self):
        return f"(fn [{' '.join(str(p) for p in self.params)}] -> {self.ret})"


class Unknown(Ty):
    """A type this layer declined to determine. Unifies with everything."""

    def __str__(self):
        return "?"

    def __eq__(self, other):
        return isinstance(other, Unknown)

    def __hash__(self):
        return hash("?")


UNKNOWN = Unknown()


class TypeError_(Exception):
    """A mismatch worth reporting. Carries the two types for the message."""

    def __init__(self, want: Ty, got: Ty, why: str = ""):
        self.want, self.got, self.why = want, got, why
        super().__init__(f"expected {want}, found {got}" + (f" ({why})" if why else ""))


# ---------- reading types ----------

def split_top(text: str, sep: str = " ") -> list:
    """Split at nesting depth zero, so `(Map K V) K` is two parts, not three."""
    out, cur, depth = [], "", 0
    for ch in text:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == sep and depth == 0:
            if cur.strip():
                out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def top_arrow(text: str) -> int:
    """Index of the `->` at depth zero, or -1. `(fn [A] -> B) X -> Y` has one."""
    depth = 0
    for i, ch in enumerate(text):
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "-" and depth == 0 and text[i:i + 2] == "->":
            return i
    return -1


def parse_sig(text: str) -> FnTy:
    """A builtin's declared type string as a function type."""
    arrow = top_arrow(text)
    lhs = text[:arrow].strip() if arrow >= 0 else ""
    rhs = text[arrow + 2:].strip() if arrow >= 0 else text.strip()
    variadic = "..." in lhs
    params = tuple(parse_ty(p.replace("...", "")) for p in split_top(lhs)) if lhs else ()
    return FnTy(params, parse_ty(rhs), variadic)


def parse_ty(text: str) -> Ty:
    text = text.strip()
    if not text:
        return UNKNOWN
    if text.startswith("(") and text.endswith(")"):
        inner = text[1:-1].strip()
        if inner.startswith("fn "):
            body = inner[3:].strip()
            ps = body[body.index("[") + 1:body.index("]")]
            ret = body[body.index("]") + 1:].lstrip()
            ret = ret[2:].strip() if ret.startswith("->") else ret
            return FnTy(tuple(parse_ty(p) for p in split_top(ps)), parse_ty(ret))
        parts = split_top(inner)
        return Con(parts[0], tuple(parse_ty(p) for p in parts[1:]))
    name = ALIASES.get(text, text)
    if name in PRIMS:
        return Prim(name)
    if name in SIG_VARS:
        return Var(name, numeric=(name == "N"))
    return Con(name)


def from_tree(node, typevars: set) -> Ty:
    """A `type` node from the grammar."""
    if isinstance(node, Tree) and node.data == "type":
        if len(node.children) == 1:
            return from_tree(node.children[0], typevars)
        return from_tree_app(node, typevars)
    if isinstance(node, Token):
        name = ALIASES.get(str(node), str(node))
        if name in PRIMS:
            return Prim(name)
        if name in typevars:
            return Var(name)
        return Con(name)
    if isinstance(node, Tree):
        return from_tree_app(node, typevars)
    return UNKNOWN


def from_tree_app(node, typevars: set) -> Ty:
    kids = [k for k in node.children if not (isinstance(k, Token) and k.type == "ARROW")]
    head = kids[0]
    name = str(head) if isinstance(head, Token) else str(head.children[0])
    return Con(ALIASES.get(name, name), tuple(from_tree(a, typevars) for a in kids[1:]))


# ---------- unification ----------

def resolve(t: Ty, subst: dict) -> Ty:
    while isinstance(t, Var) and t.name in subst:
        t = subst[t.name]
    if isinstance(t, Con) and t.args:
        return Con(t.name, tuple(resolve(a, subst) for a in t.args))
    if isinstance(t, FnTy):
        return FnTy(tuple(resolve(p, subst) for p in t.params), resolve(t.ret, subst), t.variadic)
    return t


def unify(a: Ty, b: Ty, subst: dict) -> None:
    """First-order unification. Raises TypeError_ on a genuine mismatch."""
    a, b = resolve(a, subst), resolve(b, subst)
    if isinstance(a, Unknown) or isinstance(b, Unknown):
        return
    if isinstance(a, Var):
        if isinstance(b, Var) and b.name == a.name:
            return
        if a.numeric and not numeric_ok(b):
            raise TypeError_(Prim("a number"), b)
        subst[a.name] = b
        return
    if isinstance(b, Var):
        unify(b, a, subst)
        return
    if isinstance(a, Prim) and isinstance(b, Prim):
        if a.name != b.name:
            raise TypeError_(a, b)
        return
    if isinstance(a, Con) and isinstance(b, Con):
        if a.name != b.name:
            raise TypeError_(a, b)
        # An unapplied constructed type carries no argument information; treat
        # it as compatible rather than invent a mismatch.
        if a.args and b.args:
            if len(a.args) != len(b.args):
                raise TypeError_(a, b)
            for x, y in zip(a.args, b.args):
                unify(x, y, subst)
        return
    if isinstance(a, FnTy) and isinstance(b, FnTy):
        if len(a.params) == len(b.params):
            for x, y in zip(a.params, b.params):
                unify(x, y, subst)
        unify(a.ret, b.ret, subst)
        return
    raise TypeError_(a, b)


def numeric_ok(t: Ty) -> bool:
    if isinstance(t, (Unknown, Var)):
        return True
    return isinstance(t, Prim) and t.name in NUMERIC


def fresh(t: Ty, tag: str) -> Ty:
    """Rename a signature's variables so two call sites do not share them."""
    if isinstance(t, Var):
        return Var(f"{t.name}#{tag}", t.numeric)
    if isinstance(t, Con) and t.args:
        return Con(t.name, tuple(fresh(a, tag) for a in t.args))
    if isinstance(t, FnTy):
        return FnTy(tuple(fresh(p, tag) for p in t.params), fresh(t.ret, tag), t.variadic)
    return t


BUILTIN_SIGS = {b["name"]: parse_sig(b["type"]) for b in PRELUDE["builtins"]}


# ---------- checking a module ----------

FORM_KW = {"DEFUN", "DEFSCHEMA", "DEFENUM", "DEFENTRY", "DEFEXTERN", "DEFOPAQUE",
           "MODULE", "IF", "COND", "MATCH", "TRY", "LET", "FN", "ARROW", "ELSE_KW",
           "CASE_KW", "FIELD_KW", "DOC_KW", "EXPORT_KW", "IMPORT_KW", "EXTERN_KW",
           "AS_KW", "DEFAULT_KW", "JSON_KW", "EFFECTS_KW", "TARGET_KW", "SYMBOL_KW",
           "OK", "ERR", "SOME", "NONE", "LIST", "CONS", "PAIR"}

LIT = {"INT": Prim("Int64"), "FLOAT": Prim("Float64"), "STRING": Prim("String"),
       "BOOL": Prim("Bool"), "UNIT": Prim("Unit")}

# ok/err/some/none/list/pair are grammar forms rather than vocabulary entries in
# expression position, so their types are written here rather than read from the
# prelude.
CTOR_SIGS = {
    "ok":   FnTy((Var("T"),), Con("Result", (Var("T"), Var("E")))),
    "err":  FnTy((Var("E"),), Con("Result", (Var("T"), Var("E")))),
    "some": FnTy((Var("T"),), Con("Option", (Var("T"),))),
    "none": FnTy((), Con("Option", (Var("T"),))),
    "pair": FnTy((Var("A"), Var("B")), Con("Pair", (Var("A"), Var("B")))),
    "list": FnTy((Var("T"),), Con("List", (Var("T"),)), variadic=True),
}


@dataclass
class Surface:
    """What one module offers: function signatures, records, enums, opaques."""
    funs: dict = field(default_factory=dict)        # name -> FnTy
    schemas: dict = field(default_factory=dict)     # name -> {field: Ty}
    enum_of: dict = field(default_factory=dict)     # case -> (enum, [Ty])
    opaques: set = field(default_factory=set)


def kids(node) -> list:
    return [k for k in node.children if not (isinstance(k, Token) and k.type in FORM_KW)]


def tok(n) -> str:
    return str(n) if isinstance(n, Token) else str(n.children[0])


def typevars_of(node) -> set:
    tp = [x for x in node.children if isinstance(x, Tree) and x.data == "type_params"]
    return {str(t) for x in tp for t in x.children if isinstance(t, Token)}


def surface_of(tops) -> Surface:
    """Read every declaration's declared type. No bodies are looked at."""
    s = Surface()
    for n in tops:
        if not isinstance(n, Tree):
            continue
        if n.data == "defopaque":
            s.opaques.add(tok(kids(n)[0]))
        elif n.data == "defschema":
            tv = typevars_of(n)
            k = [x for x in kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
            fields = {}
            for f in n.children:
                if isinstance(f, Tree) and f.data == "field":
                    fk = kids(f)
                    fields[tok(fk[0])] = from_tree(fk[1], tv)
            s.schemas[tok(k[0])] = fields
        elif n.data == "defenum":
            tv = typevars_of(n)
            k = [x for x in kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
            owner = tok(k[0])
            for c in n.children:
                if isinstance(c, Tree) and c.data == "enum_case":
                    ck = kids(c)
                    ps = [p for p in c.children if isinstance(p, Tree) and p.data == "param"]
                    s.enum_of[tok(ck[0])] = (
                        owner, [from_tree(kids(p)[1], tv) for p in ps], sorted(tv))
        elif n.data in ("defun", "defextern"):
            tv = typevars_of(n)
            k = [x for x in kids(n)
                 if not (isinstance(x, Tree) and x.data in ("type_params", "decl_opt",
                                                            "extern_opt"))]
            name = tok(k[0])
            params, ret = signature_parts(n, tv)
            if n.data == "defextern":
                # §11: the declared type is the SUCCESS type; the call site sees
                # a Result. Recording it that way is what makes rule 5's
                # structural check a type error rather than a shape heuristic.
                ret = Con("Result", (ret, Prim("String")))
            s.funs[name] = FnTy(tuple(params), ret)
    return s


def signature_parts(n, tv: set):
    k = [x for x in kids(n)
         if not (isinstance(x, Tree) and x.data in ("type_params", "decl_opt", "extern_opt"))]
    params = [from_tree(kids(p)[1], tv)
              for p in n.children if isinstance(p, Tree) and p.data == "params"
              for p in p.children if isinstance(p, Tree) and p.data == "param"]
    ret = UNKNOWN
    for i, x in enumerate(k):
        if isinstance(x, Tree) and x.data == "type":
            ret = from_tree(x, tv)
            break
    return params, ret


@dataclass
class Finding:
    node: object
    message: str
    rule: int = 3        # §9 rule 3 by default; 6 when numbers are being mixed


class Walk:
    """Type-check one module's bodies against their declared signatures."""

    def __init__(self, surface: Surface, imported: dict, module_name: str = ""):
        self.s = surface
        self.imported = imported          # alias -> Surface of that module
        self.module = module_name
        self.subst: dict = {}
        self.n = 0
        self.out: list = []
        # How much of the module this layer actually typed. It fails open, so
        # without this the difference between "checked and clean" and "declined
        # to look" is invisible — which is the whole risk of failing open.
        self.typed = 0
        self.untyped = 0

    def tag(self) -> str:
        self.n += 1
        return f"{self.module}{self.n}"

    def report(self, node, message: str, rule: int = 3) -> None:
        self.out.append(Finding(node, message, rule))

    # ---------- declarations ----------

    def declaration(self, n) -> None:
        tv = typevars_of(n)
        params, ret = signature_parts(n, tv)
        env = {}
        for p in n.children:
            if isinstance(p, Tree) and p.data == "params":
                for q in p.children:
                    if isinstance(q, Tree) and q.data == "param":
                        qk = kids(q)
                        env[tok(qk[0])] = from_tree(qk[1], tv)
                break
        body = self.body_of(n)
        if not body:
            return
        for e in body[:-1]:
            self.synth(e, env)
        self.check(body[-1], ret, env, "the declared return type")

    @staticmethod
    def body_of(n) -> list:
        k = [x for x in kids(n)
             if not (isinstance(x, Tree) and x.data in ("type_params", "decl_opt"))]
        for i, x in enumerate(k):
            if isinstance(x, Tree) and x.data == "type":
                return k[i + 1:]
        return []

    # ---------- the two directions ----------

    def check(self, e, want: Ty, env: dict, why: str = "", numeric_site: str = "") -> None:
        got = self.synth(e, env)
        try:
            unify(want, got, self.subst)
        except TypeError_ as exc:
            a, b = resolve(exc.want, self.subst), resolve(exc.got, self.subst)
            # Rule 6 is specifically about mixing *numeric* types. A Result or a
            # String reaching an arithmetic operand is an ordinary type error,
            # and calling it a numeric mix would misname it.
            if numeric_site and numeric_ok(a) and numeric_ok(b) \
                    and isinstance(a, Prim) and isinstance(b, Prim):
                # §9 rule 6 owns this: the operands of one arithmetic form must
                # be the same numeric type, and §6.4 has the explicit
                # conversions. Saying "argument 2 expected Int64" describes the
                # symptom; naming the mix describes what to fix.
                self.report(e, f"`{numeric_site}` mixes {a} and {b}; there is no implicit "
                               f"conversion, so one of them has to be converted", 6)
            else:
                self.report(e, f"expected {a}, found {b}" + (f" — {why}" if why else ""))

    def synth(self, e, env: dict) -> Ty:
        e = unwrap(e)
        if isinstance(e, Token):
            if e.type in LIT:
                return LIT[e.type]
            if e.type == "IDENT":
                name = str(e)
                if name in env:
                    return env[name]
                if name in self.s.funs:
                    return fresh(self.s.funs[name], self.tag())
                if name in BUILTIN_SIGS:
                    return fresh(BUILTIN_SIGS[name], self.tag())
                if name in CTOR_SIGS:
                    return fresh(CTOR_SIGS[name], self.tag())
            return UNKNOWN
        if not isinstance(e, Tree):
            return UNKNOWN

        handler = getattr(self, "t_" + e.data, None)
        result = handler(e, env) if handler else UNKNOWN
        if isinstance(resolve(result, self.subst), Unknown):
            self.untyped += 1
        else:
            self.typed += 1
        return result

    # ---------- forms ----------

    def t_let_form(self, e, env) -> Ty:
        inner = dict(env)
        for b in e.children:
            if isinstance(b, Tree) and b.data == "binding":
                bk = kids(b)
                inner[tok(bk[0])] = self.synth(bk[1], inner)
        rest = [x for x in kids(e) if not (isinstance(x, Tree) and x.data == "binding")]
        last = UNKNOWN
        for x in rest:
            last = self.synth(x, inner)
        return last

    def t_if_form(self, e, env) -> Ty:
        c, a, b = kids(e)
        self.check(c, Prim("Bool"), env, "an `if` condition")
        ta = self.synth(a, env)
        tb = self.synth(b, env)
        try:
            unify(ta, tb, self.subst)
        except TypeError_:
            self.report(e, f"branches of `if` disagree: {resolve(ta, self.subst)} "
                           f"and {resolve(tb, self.subst)}")
            return UNKNOWN
        return ta if not isinstance(ta, Unknown) else tb

    def t_cond_form(self, e, env) -> Ty:
        result = UNKNOWN
        for cl in kids(e):
            if not isinstance(cl, Tree):
                continue
            ck = kids(cl)
            if cl.data == "cond_clause":
                self.check(ck[0], Prim("Bool"), env, "a `cond` condition")
                body = ck[1:]
            else:
                body = ck
            last = UNKNOWN
            for x in body:
                last = self.synth(x, env)
            if isinstance(result, Unknown):
                result = last
        return result

    def t_try_form(self, e, env) -> Ty:
        inner = self.synth(kids(e)[0], env)
        r = resolve(inner, self.subst)
        if isinstance(r, Con) and r.name == "Result" and r.args:
            return r.args[0]
        return UNKNOWN

    def t_fn_form(self, e, env) -> Ty:
        tv = typevars_of(e)
        inner = dict(env)
        params = []
        for p in e.children:
            if isinstance(p, Tree) and p.data == "params":
                for q in p.children:
                    if isinstance(q, Tree) and q.data == "param":
                        qk = kids(q)
                        t = from_tree(qk[1], tv)
                        inner[tok(qk[0])] = t
                        params.append(t)
                break
        k = [x for x in kids(e) if not (isinstance(x, Tree) and x.data == "type_params")]
        ret = UNKNOWN
        for i, x in enumerate(k):
            if isinstance(x, Tree) and x.data == "type":
                ret = from_tree(x, tv)
                for b in k[i + 1:-1]:
                    self.synth(b, inner)
                if k[i + 1:]:
                    self.check(k[-1], ret, inner, "a `fn` return type")
                break
        return FnTy(tuple(params), ret)

    def t_field_access(self, e, env) -> Ty:
        fld = tok(e.children[0])[2:]
        target = resolve(self.synth(e.children[1], env), self.subst)
        name = target.name if isinstance(target, Con) else None
        if name in self.s.schemas:
            fields = self.s.schemas[name]
            if fld not in fields:
                self.report(e, f"`{name}` has no field `{fld}`")
                return UNKNOWN
            return fields[fld]
        if name == "Pair" and getattr(target, "args", ()):
            return target.args[0] if fld == "first" else target.args[1]
        if name == "ProcessResult" or (name is None and fld in
                                       {f[0] for f in RECORDS["ProcessResult"]}):
            for fname, fty, _ in RECORDS["ProcessResult"]:
                if fname == fld:
                    return parse_ty(fty)
        return UNKNOWN

    def t_ctor(self, e, env) -> Ty:
        name = tok(e.children[0])
        fields = self.s.schemas.get(name)
        given = {}
        for a in e.children[1:]:
            if isinstance(a, Tree) and a.data == "ctor_arg":
                given[tok(a.children[0])[1:]] = a.children[1]
        if fields is None:
            for v in given.values():
                self.synth(v, env)
            return Con(name)
        tag = self.tag()
        for fname, value in given.items():
            if fname not in fields:
                self.report(e, f"`{name}` has no field `{fname}`")
                continue
            self.check(value, fresh(fields[fname], tag), env, f"field `{fname}` of `{name}`")
        return Con(name)

    def t_call(self, e, env) -> Ty:
        head = unwrap(e.children[0])
        args = e.children[1:]
        name = str(head) if isinstance(head, Token) else None
        sig = self.lookup(name, env)
        if sig is None or not isinstance(sig, FnTy):
            for a in args:
                self.synth(a, env)
            return UNKNOWN
        if not sig.variadic and len(args) != len(sig.params):
            self.report(e, f"`{name}` takes {len(sig.params)} argument"
                           f"{'' if len(sig.params) == 1 else 's'}, given {len(args)}")
            for a in args:
                self.synth(a, env)
            return UNKNOWN
        for i, a in enumerate(args):
            want = sig.params[min(i, len(sig.params) - 1)] if sig.params else UNKNOWN
            numeric = name if isinstance(want, Var) and want.numeric else ""
            self.check(a, want, env, f"argument {i + 1} of `{name}`", numeric_site=numeric)
        return sig.ret

    def lookup(self, name, env):
        if name is None:
            return None
        if name in env:
            t = env[name]
            return t if isinstance(t, FnTy) else None
        if name in self.s.funs:
            return fresh(self.s.funs[name], self.tag())
        if name in CTOR_SIGS:
            return fresh(CTOR_SIGS[name], self.tag())
        if name in BUILTIN_SIGS:
            return fresh(BUILTIN_SIGS[name], self.tag())
        if name in self.s.enum_of:
            owner, ptys, tvs = self.s.enum_of[name]
            tag = self.tag()
            args = tuple(fresh(Var(v), tag) for v in tvs)
            return FnTy(tuple(fresh(p, tag) for p in ptys), Con(owner, args))
        if "/" in name:
            alias, member = name.split("/", 1)
            other = self.imported.get(alias)
            if other and member in other.funs:
                return fresh(other.funs[member], self.tag())
        return None

    def t_match_form(self, e, env) -> Ty:
        mk = kids(e)
        subject = resolve(self.synth(mk[0], env), self.subst)
        result = UNKNOWN
        for arm in mk[1:]:
            if not (isinstance(arm, Tree) and arm.data == "match_arm"):
                continue
            ak = kids(arm)
            inner = dict(env)
            self.bind_pattern(ak[0], subject, inner)
            last = UNKNOWN
            for b in ak[1:]:
                last = self.synth(b, inner)
            if isinstance(result, Unknown):
                result = last
        return result

    def bind_pattern(self, pat, subject: Ty, env: dict) -> None:
        """Give a pattern's names types derived from what is being matched."""
        node = pat
        while isinstance(node, Tree) and node.data == "pattern" and len(node.children) == 1 \
                and isinstance(node.children[0], Tree):
            node = node.children[0]
        toks = node.children if isinstance(node, Tree) else []
        head = str(toks[0]) if toks and isinstance(toks[0], Token) else None
        subject = resolve(subject, self.subst)
        arg = (subject.args if isinstance(subject, Con) else ()) or ()

        def bind(p, t):
            leaf = p
            while isinstance(leaf, Tree) and len(leaf.children) == 1:
                leaf = leaf.children[0]
            if isinstance(leaf, Token) and leaf.type == "IDENT":
                env[str(leaf)] = t

        if head in ("some", "ok") and len(toks) > 1:
            bind(toks[1], arg[0] if arg else UNKNOWN)
        elif head == "err" and len(toks) > 1:
            bind(toks[1], arg[1] if len(arg) > 1 else UNKNOWN)
        elif head == "pair" and len(toks) > 2:
            bind(toks[1], arg[0] if arg else UNKNOWN)
            bind(toks[2], arg[1] if len(arg) > 1 else UNKNOWN)
        elif head == "cons" and len(toks) > 2:
            bind(toks[1], arg[0] if arg else UNKNOWN)
            bind(toks[2], subject)
        elif head in self.s.enum_of:
            _, ptys, tvs = self.s.enum_of[head]
            sub = dict(zip(tvs, arg)) if tvs and arg else {}
            subs = [p for p in toks[1:] if isinstance(p, Tree)]
            for p, t in zip(subs, ptys):
                bind(p, resolve_named(t, sub))
        elif head is None:
            bind(node, subject)


def resolve_named(t: Ty, mapping: dict) -> Ty:
    if isinstance(t, Var) and t.name in mapping:
        return mapping[t.name]
    if isinstance(t, Con) and t.args:
        return Con(t.name, tuple(resolve_named(a, mapping) for a in t.args))
    return t


def unwrap(n):
    while isinstance(n, Tree) and n.data in ("expr", "literal") and len(n.children) == 1:
        n = n.children[0]
    return n
