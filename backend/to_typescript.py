#!/usr/bin/env python3
"""AgentScript Core -> TypeScript.

Lowering rules come from prelude/prelude.json, as for every backend. This file
owns only the special forms and the type mapping.

The target is TypeScript rather than JavaScript because a backend needs an
accept/reject oracle. `tsc --noEmit` is to this backend what `rustc` and
`swiftc` are to theirs; JavaScript has nothing to put in that column, which is
the hole that let the Python backend emit `s(/, concat, ...)` while the corpus
gate printed `ok`. JavaScript is not lost — `tsc` emits it.

Every AgentScript form is an expression and TypeScript's `const` and `if` are
statements, so `let` and `match` lower to an immediately-applied arrow function.
Unlike the Swift backend the closure needs no throwing annotation: `try` lowers
to a call that throws an `ASThrown`, which is ordinary control flow in
TypeScript and crosses a closure boundary without being declared. That also
means `if` and `cond` stay ternaries whether or not they contain a `try`.

A program's transitive imports are linked into one output file, prefixed by the
module path that defines them, exactly as in the Python backend: an alias is
module-local, so keying on it would give one definition as many names as its
importers invent. Qualified names resolve through the alias-to-prefix map.
"""
import argparse
import json
import sys
from pathlib import Path

from lark import Tree, Token

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "grammar"))

from modules import closure, declared_path, imports  # noqa: E402
from parse import FORM_KW, parser  # noqa: E402

sys.path.insert(0, str(ROOT / "prelude"))

from vocab import unions  # noqa: E402

PRELUDE = json.loads((ROOT / "prelude" / "prelude.json").read_text())
LOWER = {b["name"]: b["ts"] for b in PRELUDE["builtins"]}

# Int32 shares `bigint` with Int64: a JavaScript number is a double and loses
# integers past 2^53. The runtime enforces the Int64 bound; the narrower width is
# checked only by the typed backends, exactly as in the Python runtime.
PRIM = {"Bool": "boolean", "Int32": "bigint", "Int64": "bigint", "Int": "bigint",
        "Float64": "number", "String": "string", "Unit": "void"}

# Reserved words and the strict-mode reserved set. Spec §8 appends `_` on a
# collision, which keeps the emitted name a plain identifier in every position.
TS_KW = {"await", "break", "case", "catch", "class", "const", "continue",
         "debugger", "default", "delete", "do", "else", "enum", "export",
         "extends", "false", "finally", "for", "function", "if", "implements",
         "import", "in", "instanceof", "interface", "let", "new", "null",
         "package", "private", "protected", "public", "return", "static",
         "super", "switch", "this", "throw", "true", "try", "typeof", "var",
         "void", "while", "with", "yield"}


def mangle(n: str) -> str:
    """kebab-case -> camelCase, per AGENT_SPEC_CORE.md §8."""
    if n.endswith("?"):
        n = "is-" + n[:-1]
    if n.endswith("!"):
        n = n[:-1] + "-mut"
    parts = [p for p in n.split("-") if p]
    m = parts[0] + "".join(p.capitalize() for p in parts[1:])
    return m + "_" if m in TS_KW else m


def module_prefix(mod_path: str) -> str:
    """Derived from the module path that DEFINES a member, never from the alias
    reaching it: an alias is module-local, and keying on it would give one
    definition as many names as its importers invent."""
    return "_".join(mangle(seg) for seg in mod_path.split("/")) + "__"


def has_try(n) -> bool:
    if isinstance(n, Tree):
        return n.data == "try_form" or any(has_try(c) for c in n.children)
    return False


class ToTypeScript:
    def __init__(self):
        self.parser = parser()
        # Prelude unions are seeded (as arity-0 cases) so a case of one, e.g.
        # `(err (not-found))`, is lowered by exactly the path a user `defenum`
        # case takes; nothing below distinguishes them. Without the seeding the
        # nested `(not-found)` pattern would drop its tag test and match every
        # `err`, and the fixtures would pass while wrong.
        self.enums: dict[str, tuple[str, int]] = {}
        for ename, cases in unions().items():
            for case in cases:
                self.enums[case] = (ename, 0)
        self.schemas: dict[str, list[str]] = {}    # emitted schema name -> field order
        self.tparams: set[str] = set()             # type parameters of the current declaration
        self.prefix = ""                           # emitted-name prefix of the current unit
        self.local: dict[str, str] = {}            # its top-level names -> emitted names
        self.alias_prefix: dict[str, str] = {}
        self.scope: list[set[str]] = []            # binder frames, innermost last
        self.tmp = 0

    def fresh(self) -> str:
        self.tmp += 1
        return f"t{self.tmp}"

    @staticmethod
    def kids(n):
        return [k for k in n.children if not (isinstance(k, Token) and k.type in FORM_KW)]

    @staticmethod
    def tok(n):
        return str(n) if isinstance(n, Token) else str(n.children[0])

    def push(self, names=()) -> None:
        """Every binding form opens a frame. A binder is emitted unprefixed while
        a top-level name is emitted prefixed, so an identifier that exists as both
        resolves to the wrong symbol unless scope is consulted first."""
        self.scope.append(set(names))

    def pop(self) -> None:
        self.scope.pop()

    def bound(self, name: str) -> bool:
        return any(name in frame for frame in self.scope)

    def resolve(self, name: str) -> str:
        return mangle(name) if self.bound(name) else self.local.get(name, mangle(name))

    def qual(self, text: str) -> str:
        alias, _, member = text.partition("/")
        return self.alias_prefix.get(alias, "") + mangle(member)

    # ---------- types ----------

    def ttype(self, n) -> str:
        if isinstance(n, Tree) and n.data == "type":
            n = n.children[0] if len(n.children) == 1 else n
        if isinstance(n, Token):
            if getattr(n, "type", None) == "QUALIFIED_TYPE":
                return self.qual(str(n))
            s = str(n)
            if s in PRIM:
                return PRIM[s]
            if s in self.tparams:
                return s
            if s in self.local:
                return self.local[s]
            return s
        head = self.tok(n.children[0])
        if isinstance(n.children[0], Token) and n.children[0].type == "QUALIFIED_TYPE":
            head = self.qual(head)
        elif head not in self.tparams and head in self.local:
            head = self.local[head]
        args = [self.ttype(a) for a in n.children[1:]]
        built = {
            "List": f"{args[0]}[]" if args else "void[]",
            "Option": f"ASOption<{args[0]}>" if args else "ASOption<void>",
            "Result": f"ASResult<{args[0]}, {args[1]}>" if len(args) > 1 else "ASResult<void, void>",
            "Pair": f"ASPair<{args[0]}, {args[1]}>" if len(args) > 1 else "ASPair<void, void>",
            "Map": f"ASMap<{args[0]}, {args[1]}>" if len(args) > 1 else "ASMap<void, void>",
        }.get(head)
        if built is not None:
            return built
        # A user declaration applied to arguments: `(Tree T)` is `Tree<T>`.
        return f"{head}<{', '.join(args)}>" if args else PRIM.get(head, head)

    @staticmethod
    def type_param_names(n) -> list[str]:
        tp = [x for x in n.children if isinstance(x, Tree) and x.data == "type_params"]
        if not tp:
            return []
        return [str(t) for t in tp[0].children if isinstance(t, Token)]

    @staticmethod
    def type_params(n) -> str:
        tp = [x for x in n.children if isinstance(x, Tree) and x.data == "type_params"]
        if not tp:
            return ""
        names = [str(t) for t in tp[0].children if isinstance(t, Token)]
        return f"<{', '.join(names)}>" if names else ""

    # ---------- entry ----------

    def transpile(self, src: str, *, path: Path | None = None, roots=()) -> str:
        """`path` and `roots` are what an import is resolved against. A call with
        neither keeps working and resolves no imports."""
        tree = self.parser.parse(src)
        out = ['import * as RT from "./rt";',
               'import type { ASMap, ASOption, ASPair, ASResult, IoError } from "./rt";',
               ""]
        for mod_path, unit, prefix in self.link(tree, path, roots):
            self.enter(unit, prefix)
            out += self.unit(unit)
        out += self.host_entry(tree)
        return "\n".join(out) + "\n"

    def link(self, tree, path, roots) -> list[tuple[str, Tree, str]]:
        search = [*([Path(path).parent] if path is not None else []),
                  *(Path(r) for r in roots)]
        deps = closure(tree, search) if search else []
        seen: dict[str, str] = {}
        for mod_path, _ in deps:
            claimed = seen.setdefault(module_prefix(mod_path), mod_path)
            if claimed != mod_path:
                raise ValueError(f"module paths {claimed} and {mod_path} mangle alike")
        return ([(m, t, module_prefix(m)) for m, t in deps]
                + [(declared_path(tree) or "", tree, "")])

    def enter(self, tree, prefix: str) -> None:
        self.prefix = prefix
        self.alias_prefix = {a: module_prefix(m) for a, m in imports(tree).items()}
        self.local = self.unit_names(tree, prefix)
        self.scope = []

    def unit_names(self, tree, prefix: str) -> dict[str, str]:
        """Every top-level name a unit defines, mapped to the name it is emitted
        under. The root unit's prefix is empty, so a single-module program is
        lowered exactly as it was before imports existed."""
        names: dict[str, str] = {}
        for top in tree.children:
            node = top.children[0]
            if node.data == "defun":
                names[self.decl_name(node)] = prefix + mangle(self.decl_name(node))
            elif node.data == "defschema":
                nm = self.decl_name(node)
                names[nm] = prefix + nm
            elif node.data == "defenum":
                names[self.decl_name(node)] = prefix + self.decl_name(node)
                for c in node.children:
                    if isinstance(c, Tree) and c.data == "enum_case":
                        case = self.tok(self.kids(c)[0])
                        names[case] = prefix + mangle(case)
        return names

    def decl_name(self, node) -> str:
        kids = [k for k in self.kids(node)
                if not (isinstance(k, Tree) and k.data in ("type_params", "doc_opt"))]
        return self.tok(kids[0])

    def unit(self, tree) -> list[str]:
        out: list[str] = []
        # enums first: their cases are constructors used by later definitions
        for top in tree.children:
            node = top.children[0]
            if node.data == "defenum":
                out += self.defenum(node)
        for top in tree.children:
            node = top.children[0]
            if node.data == "defschema":
                out += self.defschema(node)
            elif node.data == "defun":
                out += self.defun(node)
        return out

    def host_entry(self, tree) -> list[str]:
        """A module that declares `main` is a program, and only then does a host
        entry point exist; emitting one unconditionally would collide with the
        drivers that synthesise their own. The root unit defines `main` under an
        empty prefix, so the emitted name is always `main`."""
        for top in tree.children:
            node = top.children[0]
            if node.data != "defun":
                continue
            body = [k for k in self.kids(node)
                    if not (isinstance(k, Tree) and k.data in ("type_params", "doc_opt"))]
            if str(body[0]) == "main":
                return ["", "RT.mainExit(main(RT.args()));"]
        return []

    # ---------- declarations ----------

    def defschema(self, n) -> list[str]:
        self.tparams = set(self.type_param_names(n))
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        gen = self.type_params(n)
        fields = [f for f in n.children if isinstance(f, Tree) and f.data == "field"]
        names = [mangle(self.tok(self.kids(f)[0])) for f in fields]
        types = [self.ttype(self.kids(f)[1]) for f in fields]
        self.schemas[self.prefix + name] = names
        arg = "; ".join(f"{f}: {t}" for f, t in zip(names, types))
        lines = [f"export class {self.prefix}{name}{gen} {{"]
        lines += [f"    readonly {f}: {t};" for f, t in zip(names, types)]
        lines.append(f"    constructor(f: {{ {arg} }}) {{")
        lines += [f"        this.{f} = f.{f};" for f in names]
        return lines + ["    }", "}", ""]

    def defenum(self, n) -> list[str]:
        self.tparams = set(self.type_param_names(n))
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        gen = self.type_params(n)
        cases = [c for c in n.children if isinstance(c, Tree) and c.data == "enum_case"]
        arms, ctors = [], []
        for c in cases:
            case = self.tok(self.kids(c)[0])
            ps = [p for p in c.children if isinstance(p, Tree) and p.data == "param"]
            tys = [self.ttype(self.kids(p)[1]) for p in ps]
            self.enums[case] = (name, len(tys))
            slots = "".join(f"; readonly _{i}: {t}" for i, t in enumerate(tys))
            arms.append(f'  | {{ readonly tag: "{case}"{slots} }}')
            params = ", ".join(f"_{i}: {t}" for i, t in enumerate(tys))
            built = "".join(f", _{i}" for i in range(len(tys)))
            ctors += [f"export function {self.prefix}{mangle(case)}{gen}({params}): {self.prefix}{name}{gen} {{",
                      f'    return {{ tag: "{case}"{built} }};',
                      "}", ""]
        return [f"export type {self.prefix}{name}{gen} ="] + arms[:-1] + [arms[-1] + ";", ""] + ctors

    def defun(self, n) -> list[str]:
        self.tparams = set(self.type_param_names(n))
        k = [x for x in self.kids(n)
             if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt"))]
        name = mangle(self.tok(k[0]))
        gen = self.type_params(n)
        args = self.param_list(k[1])
        names = [self.tok(self.kids(p)[0]) for p in k[1].children
                 if isinstance(p, Tree) and p.data == "param"]
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret = self.ttype(k[ti])
        self.push(names)
        body = self.guarded(n, k[ti + 1:])
        self.pop()
        return [f"export function {self.prefix}{name}{gen}({args}): {ret} {{"] + body + ["}", ""]

    def param_list(self, params) -> str:
        ps = [p for p in params.children if isinstance(p, Tree) and p.data == "param"]
        return ", ".join(f"{mangle(self.tok(self.kids(p)[0]))}: {self.ttype(self.kids(p)[1])}"
                         for p in ps)

    def guarded(self, decl, body) -> list[str]:
        """A body holding a `try` runs inside a catch that turns the thrown `err`
        back into this function's own `err`. Anything else thrown is re-raised:
        an arithmetic trap is not a `Result` failure and must not become one."""
        if not has_try(decl):
            return self.block(body, 1)
        ret = next(x for x in self.kids(decl) if isinstance(x, Tree) and x.data == "type")
        e_ty = self._result_err(ret)
        cast = f" as {e_ty}" if e_ty else ""
        return (["    try {"] + self.block(body, 2)
                + ["    } catch (e) {",
                   f"        if (e instanceof RT.ASThrown) {{ return RT.err(e.value{cast}); }}",
                   "        throw e;",
                   "    }"])

    def _result_err(self, t) -> str | None:
        if isinstance(t, Tree) and t.data == "type":
            t = t.children[0] if len(t.children) == 1 else t
        if isinstance(t, Tree) and self.tok(t.children[0]) == "Result" and len(t.children) > 2:
            return self.ttype(t.children[2])
        return None

    # ---------- statement blocks ----------

    def block(self, exprs, ind: int) -> list[str]:
        """Lower a body to statements. A trailing `let` is flattened rather than
        wrapped in a closure — every AgentScript body is one, and the nesting
        would otherwise dominate the output. Binders are tracked so a name that
        shadows a prefixed top-level name resolves to the binding."""
        pad = "    " * ind
        self.push()
        lines: list[str] = []
        for e in exprs[:-1]:
            lines.append(f"{pad}void ({self.expr(e, ind)});")
        last = self.unwrap_expr(exprs[-1]) if exprs else None
        if isinstance(last, Tree) and last.data == "let_form":
            for b in self.kids(last):
                if isinstance(b, Tree) and b.data == "binding":
                    bk = self.kids(b)
                    nm = self.tok(bk[0])
                    lines.append(f"{pad}const {mangle(nm)} = {self.expr(bk[1], ind)};")
                    self.scope[-1].add(nm)
            inner = [x for x in self.kids(last) if not (isinstance(x, Tree) and x.data == "binding")]
            lines += self.block(inner, ind)
        elif exprs:
            lines.append(f"{pad}return {self.expr(last, ind)};")
        self.pop()
        return lines

    def iife(self, lines: list[str], ind: int) -> str:
        pad = "    " * ind
        return "(() => {\n" + "\n".join(lines) + f"\n{pad}}})()"

    @staticmethod
    def unwrap_expr(n):
        while isinstance(n, Tree) and n.data in ("expr", "literal") and len(n.children) == 1:
            n = n.children[0]
        return n

    # ---------- expressions ----------

    def expr(self, n, ind: int) -> str:
        n = self.unwrap_expr(n)
        if isinstance(n, Token):
            return self.atom(n)

        if n.data == "let_form":
            return self.iife(self.block([n], ind + 1), ind)

        if n.data == "if_form":
            c, a, b = self.kids(n)
            return f"({self.expr(c, ind)} ? {self.expr(a, ind)} : {self.expr(b, ind)})"

        if n.data == "cond_form":
            return self.cond(n, ind)

        if n.data == "match_form":
            return self.match(n, ind)

        if n.data == "try_form":
            return f"RT.unwrap({self.expr(self.kids(n)[0], ind)})"

        if n.data == "fn_form":
            return self.fn(n, ind)

        if n.data == "field_access":
            fld = self.tok(n.children[0])[2:]
            return f"{self.expr(n.children[1], ind)}.{mangle(fld)}"

        if n.data == "ctor":
            head = n.children[0]
            if isinstance(head, Token) and head.type == "QUALIFIED_TYPE":
                name = self.qual(str(head))
            else:
                name = self.resolve(str(head))
            given = {self.tok(a.children[0])[1:]: self.expr(a.children[1], ind)
                     for a in n.children[1:] if isinstance(a, Tree) and a.data == "ctor_arg"}
            order = self.schemas.get(name) or list(given)
            fields = ", ".join(f"{mangle(f)}: {given[f]}" for f in order if f in given)
            return f"new {name}({{ {fields} }})"

        if n.data == "call":
            return self.call(n, ind)

        raise NotImplementedError(f"form not lowered to TypeScript: {n.data}")

    def fn(self, n, ind: int) -> str:
        if has_try(n):
            raise NotImplementedError("`try` inside `fn` is not lowered to TypeScript: the "
                                      "throw would leave the closure at an unrelated frame")
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        params_node = k[0]
        # fn_params children are fn_param trees: bare IDENT or (IDENT type)
        fns = [p for p in params_node.children if isinstance(p, Tree) and p.data == "fn_param"]
        items = []
        names = []
        for p in fns:
            pk = self.kids(p)
            name = str(pk[0])
            names.append(name)
            if len(pk) > 1 and isinstance(pk[1], Tree) and pk[1].data == "type":
                items.append(f"{mangle(name)}: {self.ttype(pk[1])}")
            else:
                items.append(f"{mangle(name)}: any")
        params_str = ", ".join(items)
        # return type and body
        ret = "any"
        body_start = 1
        for i, x in enumerate(k[1:], start=1):
            if isinstance(x, Tree) and x.data == "type":
                ret = self.ttype(x)
                body_start = i + 1
                break
        self.push(names)
        body = self.block(k[body_start:], ind + 1)
        self.pop()
        pad = "    " * ind
        return f"(({params_str}): {ret} => {{\n" + "\n".join(body) + f"\n{pad}}})"

    def call(self, n, ind: int) -> str:
        head = self.unwrap_expr(n.children[0])
        args = [self.expr(a, ind) for a in n.children[1:]]
        name = str(head) if isinstance(head, Token) else None
        if name in LOWER:
            tpl = LOWER[name]
            return tpl.replace("{*}", ", ".join(args)) if "{*}" in tpl else tpl.format(*args)
        if name:
            if "/" in name:
                return f"{self.qual(name)}({', '.join(args)})"
            return f"{self.resolve(name)}({', '.join(args)})"
        return f"({self.expr(head, ind)})({', '.join(args)})"

    # ---------- match ----------

    def cond(self, n, ind: int) -> str:
        """A `cond` is an expression, so it lowers to an immediately-applied
        closure whose branches return. A clause body may hold more than one
        expression — the leading ones are effects — so each branch is a full
        statement block, not a ternary over the last expression."""
        pad = "    " * (ind + 1)
        lines: list[str] = []
        first = True
        for cl in [c for c in self.kids(n) if isinstance(c, Tree)]:
            ck = self.kids(cl)
            if cl.data == "cond_clause":
                cv = self.expr(ck[0], ind + 1)
                kw = "if" if first else "else if"
                lines.append(f"{pad}{kw} ({cv}) {{")
                lines += self.block(ck[1:], ind + 2)
                lines.append(f"{pad}}}")
                first = False
            else:
                lines.append(f"{pad}else {{")
                lines += self.block(ck, ind + 2)
                lines.append(f"{pad}}}")
        return self.iife(lines, ind)

    def match(self, n, ind: int) -> str:
        """One if/else chain over every pattern kind. The subject is bound to a
        `const` first so that testing `.tag` narrows it, which is what lets an arm
        read the payload without a cast."""
        mk = self.kids(n)
        arms = [a for a in mk[1:] if isinstance(a, Tree) and a.data == "match_arm"]
        pad = "    " * (ind + 1)
        s = self.fresh()
        lines = [f"{pad}const {s} = {self.expr(mk[0], ind + 1)};"]
        total = False
        for arm in arms:
            ak = self.kids(arm)
            cond, binds = self.pattern(ak[0], s)
            names = self.bound_names(binds)
            if cond is None:
                self.push(names)
                lines += [f"{pad}{b}" for b in binds]
                lines += self.block(ak[1:], ind + 1)
                self.pop()
                total = True
                break
            body_pad = "    " * (ind + 2)
            lines.append(f"{pad}if ({cond}) {{")
            self.push(names)
            lines += [f"{body_pad}{b}" for b in binds]
            lines += self.block(ak[1:], ind + 2)
            self.pop()
            lines.append(f"{pad}}}")
        if not total:
            lines.append(f"{pad}return RT.nonExhaustive();")
        return self.iife(lines, ind)

    @staticmethod
    def bound_names(binds: list[str]) -> list[str]:
        """The binder names a set of `const` statements introduce."""
        names = []
        for b in binds:
            if b.startswith("const "):
                ident = b[len("const "):].split(" ", 1)[0].split("=", 1)[0].strip()
                names.append(ident)
        return names

    def _leaf(self, p):
        """The token of a leaf pattern — a literal, a binding name or `_`."""
        while isinstance(p, Tree) and len(p.children) == 1 and p.data in ("pattern", "literal"):
            p = p.children[0]
        return p if isinstance(p, Token) else None

    def pattern(self, pat, subj) -> tuple[str | None, list[str]]:
        """A test against `subj` plus the `const`s its sub-patterns bind.

        A parenthesised sub-pattern recurses rather than being assumed to be a
        binder: reading `(err (not-found))` as a binder named `not-found`
        compiles, matches every error, and is wrong in a way no test that only
        checks the happy path can see. A *bare* identifier is the opposite case
        — it is always a binder, even where a nullary case of that name exists.
        """
        if isinstance(pat, Tree) and pat.data == "pattern":
            pat = pat.children[0] if len(pat.children) == 1 and isinstance(pat.children[0], Tree) else pat
        toks = [c for c in (pat.children if isinstance(pat, Tree) else [])]
        head = str(toks[0]) if toks and isinstance(toks[0], Token) else None
        applied = isinstance(pat, Tree) and pat.data == "enum_pattern"
        # The runtime tag stays the bare case name across a boundary: qualifying
        # it would change every existing fixture's output for a collision the
        # checker's nominal identity already makes unobservable.
        if head is not None and "/" in head:
            head = head.partition("/")[2]

        def conj(*parts: str | None) -> str | None:
            live = [p for p in parts if p is not None]
            return " && ".join(live) if live else None

        def nested(sub_pat, sub_subj):
            return self.pattern(sub_pat, sub_subj)

        if head in ("ok", "err", "some"):
            c, b = nested(toks[1], f"{subj}.value")
            return conj(f'{subj}.tag === "{head}"', c), b
        if head == "none":
            return f'{subj}.tag === "none"', []
        if head == "list":
            conds, binds = [], []
            for i, sub in enumerate(toks[1:]):
                c, b = nested(sub, f"{subj}[{i}]")
                conds.append(c)
                binds += b
            return conj(f"{subj}.length === {len(toks) - 1}", *conds), binds
        if head == "cons":
            c1, b1 = nested(toks[1], f"{subj}[0]")
            c2, b2 = nested(toks[2], f"{subj}.slice(1)")
            return conj(f"{subj}.length > 0", c1, c2), b1 + b2
        if head == "pair":
            c1, b1 = nested(toks[1], f"{subj}.first")
            c2, b2 = nested(toks[2], f"{subj}.second")
            return conj(c1, c2), b1 + b2
        if applied and head in self.enums:
            arity = self.enums[head][1]
            conds, binds = [f'{subj}.tag === "{head}"'], []
            for i, sub in enumerate(toks[1:arity + 1]):
                if not isinstance(sub, Tree):
                    continue
                c, b = nested(sub, f"{subj}._{i}")
                conds.append(c)
                binds += b
            return conj(*conds), binds
        if isinstance(pat, Token) and str(pat) == "_":
            return None, []
        tk = self._leaf(pat)
        if tk is None or tk.type == "WILDCARD":
            return None, []
        if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
            return f"RT.eq({subj}, {self.atom(tk)})", []
        return None, [f"const {mangle(str(tk))} = {subj};"]

    def atom(self, tok) -> str:
        s = str(tok)
        if tok.type == "UNIT":
            return "undefined"
        if tok.type in ("QUALIFIED", "QUALIFIED_TYPE"):
            return self.qual(s)
        if tok.type == "INT":
            return f"{s}n"
        if tok.type in ("BOOL", "FLOAT", "STRING"):
            return s
        return self.resolve(s)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--root", action="append", default=[],
                    help="source root for module resolution; repeatable. "
                         "A file's own directory is always searched.")
    args = ap.parse_args()
    source = Path(args.file)
    sys.stdout.write(ToTypeScript().transpile(source.read_text(), path=source,
                                              roots=[Path(r) for r in args.root]))
