#!/usr/bin/env python3
"""AgentS-Core -> Python transpiler.

Lowering rules for builtins are NOT written here: they come from
prelude/prelude.json, the single source of truth. This file owns only the
special forms, which are grammar productions rather than vocabulary.

Scope: the subset needed for a first end-to-end run — module, defschema,
defenum, defun, fn, let, if, cond, match, try, calls, field access, literals.

A program's transitive imports are linked into this one output file, prefixed by
the module path that defines them. Per-module emission would need a build driver
and a link step before a single fixture could be gated; this keeps every gate
driving one artifact (AGENT_SPEC_CORE 8).
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
LOWER = {b["name"]: b["py"] for b in PRELUDE["builtins"]}


def mangle(name: str) -> str:
    """kebab-case -> snake_case, per AGENT_SPEC_CORE.md section 8."""
    if name.endswith("?"):
        name = "is-" + name[:-1]
    if name.endswith("!"):
        name = name[:-1] + "-mut"
    out = name.replace("-", "_")
    return out + "_" if out in ("None", "True", "False", "class", "def", "lambda") else out


def module_prefix(mod_path: str) -> str:
    """Derived from the module path that DEFINES a member, never from the alias
    reaching it: an alias is module-local, and keying on it would give one
    definition as many names as its importers invent."""
    return "_".join(mangle(seg) for seg in mod_path.split("/")) + "__"


class Transpiler:
    def __init__(self):
        self.parser = parser()
        # Prelude unions are seeded here so a case of one is lowered by exactly
        # the path a user `defenum` case takes; nothing below distinguishes them.
        self.enum_cases: dict[str, list[str]] = {
            case: [] for cases in unions().values() for case in cases}   # case -> field names
        self.prefix = ""                      # emitted-name prefix of the current unit
        self.local: dict[str, str] = {}       # its top-level names -> emitted names
        self.alias_prefix: dict[str, str] = {}
        self.scope: list[set[str]] = []       # binder frames, innermost last
        self.tmp = 0

    # ---------- helpers ----------

    def fresh(self) -> str:
        self.tmp += 1
        return f"_t{self.tmp}"

    @staticmethod
    def tok(n) -> str:
        return str(n) if isinstance(n, Token) else str(n.children[0])

    @staticmethod
    def kids(node) -> list:
        return [k for k in node.children
                if not (isinstance(k, Token) and k.type in FORM_KW)]

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

    # ---------- entry ----------

    def transpile(self, src: str, *, path: Path | None = None, roots=()) -> str:
        """`path` and `roots` are what an import is resolved against. A call with
        neither keeps working and resolves no imports, which is what the
        measurement harness needs: it transpiles generated text that has no file."""
        tree = self.parser.parse(src)
        out = ["import runtime as _as", ""]
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
                name = self.decl_name(node)
                names[name] = prefix + mangle(name)
            elif node.data == "defschema":
                names[self.decl_name(node)] = prefix + self.decl_name(node)
            elif node.data == "defenum":
                for c in node.children:
                    if isinstance(c, Tree) and c.data == "enum_case":
                        case = self.tok(self.kids(c)[0])
                        names[case] = prefix + mangle(case)
        return names

    def decl_name(self, node) -> str:
        kids = [k for k in self.kids(node)
                if not (isinstance(k, Tree) and k.data in ("type_params", "doc_opt"))]
        return self.tok(kids[0])

    def qual(self, text: str) -> str:
        alias, _, member = text.partition("/")
        return self.alias_prefix.get(alias, "") + mangle(member)

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
        drivers that synthesise their own."""
        for top in tree.children:
            node = top.children[0]
            if node.data != "defun":
                continue
            body = [k for k in self.kids(node) if not (isinstance(k, Tree) and k.data == "type_params")]
            if str(body[0]) == "main":
                return ["", 'if __name__ == "__main__":', "    import sys as _sys",
                        "    _sys.exit(_as.main_exit(main(_sys.argv[1:])))"]
        return []

    # ---------- declarations ----------

    def defschema(self, node) -> list[str]:
        kids = [k for k in self.kids(node) if not (isinstance(k, Tree) and k.data == "type_params")]
        name = self.tok(kids[0])
        fields = [self.tok(f.children[1]) for f in node.children if
                  isinstance(f, Tree) and f.data == "field"]
        args = ", ".join(mangle(f) for f in fields)
        body = ", ".join(f'"{f}": {mangle(f)}' for f in fields)
        return [f"def {self.prefix}{name}({args}):", f"    return {{{body}}}", ""]

    def defenum(self, node) -> list[str]:
        lines = []
        for c in node.children:
            if not (isinstance(c, Tree) and c.data == "enum_case"):
                continue
            case = self.tok(self.kids(c)[0])
            params = [self.tok(p.children[0]) for p in c.children
                      if isinstance(p, Tree) and p.data == "param"]
            self.enum_cases[case] = params
            args = ", ".join(mangle(p) for p in params)
            items = "".join(f", {mangle(p)}" for p in params)
            # Trailing comma is mandatory: ("point") is a string in Python, not a
            # one-tuple, so a zero-field case would silently stop matching.
            lines += [f"def {self.prefix}{mangle(case)}({args}):",
                      f'    return ("{case}"{items},)', ""]
        return lines

    def defun(self, node) -> list[str]:
        kids = [k for k in self.kids(node)
                if not (isinstance(k, Tree) and k.data in ("type_params", "doc_opt"))]
        name = self.tok(kids[0])
        names = [self.tok(p.children[0]) for p in kids[1].children
                 if isinstance(p, Tree) and p.data == "param"]
        params = [mangle(p) for p in names]
        # Body is everything after the return type. Indexing past the type by a
        # fixed offset breaks as soon as an optional child is filtered out.
        ti = next(i for i, k in enumerate(kids) if isinstance(k, Tree) and k.data == "type")
        stmts: list[str] = []
        self.push(names)
        last = self.sequence(kids[ti + 1:], stmts, 1)
        self.pop()
        head = f"def {self.prefix}{mangle(name)}({', '.join(params)}):"
        return [head] + stmts + [f"    return {last}", ""]

    # ---------- expressions ----------

    def sequence(self, body, stmts: list[str], indent: int) -> str:
        """A body's value is its last expression; every earlier one is evaluated
        for its effect. The discarded value still has to be emitted as a
        statement, or a lowering that is a pure expression disappears."""
        pad = "    " * indent
        last = None
        for i, b in enumerate(body):
            last = self.expr(b, stmts, indent)
            if i < len(body) - 1:
                stmts.append(f"{pad}{last}")
        return last

    def expr(self, node, stmts: list[str], indent: int) -> str:
        pad = "    " * indent
        if isinstance(node, Token):
            return self.atom(node)
        if node.data == "expr":
            return self.expr(node.children[0], stmts, indent)
        if node.data == "literal":
            return self.atom(node.children[0])

        if node.data == "let_form":
            self.push()
            for b in self.kids(node):
                if isinstance(b, Tree) and b.data == "binding":
                    v = self.expr(b.children[1], stmts, indent)
                    name = self.tok(b.children[0])
                    stmts.append(f"{pad}{mangle(name)} = {v}")
                    # after its own value: a binding's initialiser is outside it
                    self.scope[-1].add(name)
            body = [k for k in self.kids(node) if not (isinstance(k, Tree) and k.data == "binding")]
            value = self.sequence(body, stmts, indent)
            self.pop()
            return value

        if node.data == "if_form":
            c, a, b = self.kids(node)
            # a conditional is an expression, so both arms must be pure to inline
            sub_a, sub_b = [], []
            va = self.expr(a, sub_a, indent)
            vb = self.expr(b, sub_b, indent)
            cv = self.expr(c, stmts, indent)
            if not sub_a and not sub_b:
                return f"({va} if {cv} else {vb})"
            t = self.fresh()
            stmts.append(f"{pad}if {cv}:")
            stmts += ["    " + s for s in sub_a] or []
            stmts.append(f"{pad}    {t} = {va}")
            stmts.append(f"{pad}else:")
            stmts += ["    " + s for s in sub_b] or []
            stmts.append(f"{pad}    {t} = {vb}")
            return t

        if node.data == "cond_form":
            t = self.fresh()
            first = True
            for cl in self.kids(node):
                if not isinstance(cl, Tree):
                    continue
                if cl.data == "cond_clause":
                    cv = self.expr(self.kids(cl)[0], stmts, indent)
                    kw = "if" if first else "elif"
                    stmts.append(f"{pad}{kw} {cv}:")
                    inner: list[str] = []
                    v = self.sequence(self.kids(cl)[1:], inner, indent + 1)
                    stmts += inner
                    stmts.append(f"{pad}    {t} = {v}")
                    first = False
                elif cl.data == "else_clause":
                    stmts.append(f"{pad}else:")
                    inner = []
                    v = self.sequence(self.kids(cl), inner, indent + 1)
                    stmts += inner
                    stmts.append(f"{pad}    {t} = {v}")
            return t

        if node.data == "match_form":
            return self.match(node, stmts, indent)

        if node.data == "try_form":
            inner = self.expr(self.kids(node)[0], stmts, indent)
            t = self.fresh()
            stmts.append(f"{pad}{t} = {inner}")
            stmts.append(f'{pad}if {t}[0] == "err": return {t}')
            return f"{t}[1]"

        if node.data == "fn_form":
            kids = [k for k in self.kids(node) if not (isinstance(k, Tree) and k.data == "type_params")]
            names = [self.tok(self.kids(p)[0]) for p in kids[0].children
                     if isinstance(p, Tree) and p.data == "fn_param"]
            params = [mangle(p) for p in names]
            sub: list[str] = []
            # Both the annotations and the arrow are elidable, so the body starts
            # after an optional return type rather than at a fixed index.
            body = kids[1:]
            if body and isinstance(body[0], Tree) and body[0].data == "type":
                body = body[1:]
            self.push(names)
            v = self.sequence(body, sub, indent + 1)
            self.pop()
            if not sub:
                return f"(lambda {', '.join(params)}: {v})"
            # Python lambdas are expression-only, but an AgentS lambda body may
            # need statements (a match compiles to if/elif). Emit a nested def
            # and pass its name; semantically identical, and closures behave the
            # same way.
            fname = self.fresh()
            stmts.append(f"{pad}def {fname}({', '.join(params)}):")
            stmts += sub
            stmts.append(f"{pad}    return {v}")
            return fname

        if node.data == "field_access":
            fld = self.tok(node.children[0])[2:]
            tgt = self.expr(node.children[1], stmts, indent)
            if fld in ("first", "second"):
                return f"{tgt}[{1 if fld == 'first' else 2}]"
            return f'{tgt}["{fld}"]'

        if node.data == "ctor":
            head = node.children[0]
            name = (self.qual(str(head)) if head.type == "QUALIFIED_TYPE"
                    else self.local.get(str(head), str(head)))
            args = []
            for a in node.children[1:]:
                if isinstance(a, Tree) and a.data == "ctor_arg":
                    args.append(f"{mangle(self.tok(a.children[0])[1:])}={self.expr(a.children[1], stmts, indent)}")
            return f"{name}({', '.join(args)})"

        if node.data == "call":
            return self.call(node, stmts, indent)

        raise NotImplementedError(f"form not in the first subset: {node.data}")

    def call(self, node, stmts, indent) -> str:
        head = node.children[0]
        args = [self.expr(a, stmts, indent) for a in node.children[1:]]
        hname = None
        h = head.children[0] if isinstance(head, Tree) and head.data == "expr" else head
        if isinstance(h, Token):
            hname = str(h)
        if hname in LOWER:
            tpl = LOWER[hname]
            if "{*}" in tpl:
                return tpl.replace("{*}", ", ".join(args))
            return tpl.format(*args)
        if hname and "/" in hname:
            return f"{self.qual(hname)}({', '.join(args)})"
        if hname:
            return f"{self.resolve(hname)}({', '.join(args)})"
        return f"{self.expr(head, stmts, indent)}({', '.join(args)})"

    def match(self, node, stmts, indent) -> str:
        pad = "    " * indent
        mk = self.kids(node)
        subj = self.expr(mk[0], stmts, indent)
        s = self.fresh()
        stmts.append(f"{pad}{s} = {subj}")
        t = self.fresh()
        first = True
        for arm in mk[1:]:
            if not (isinstance(arm, Tree) and arm.data == "match_arm"):
                continue
            pat = arm.children[0]
            cond, binds = self.pattern(pat, s)
            kw = "if" if first else "elif"
            stmts.append(f"{pad}{kw} {cond}:")
            for name, src in binds:
                stmts.append(f"{pad}    {mangle(name)} = {src}")
            inner: list[str] = []
            self.push(name for name, _ in binds)
            v = self.sequence(
                [b for b in arm.children[1:] if isinstance(b, Tree) and b.data == "expr"],
                inner, indent + 1)
            self.pop()
            stmts += inner
            stmts.append(f"{pad}    {t} = {v}")
            first = False
        return t

    def pattern(self, pat, subj) -> tuple[str, list[tuple[str, str]]]:
        """A test against `subj` plus one (name, source) pair per binder.

        A parenthesised sub-pattern recurses rather than being assumed to be a
        binder: reading `(err (not-found))` as a binder named `not-found`
        compiles, matches every error, and is wrong in a way no test that only
        checks the happy path can see. A *bare* identifier is the opposite case
        — it is always a binder, even where a nullary case of that name exists.
        """
        if isinstance(pat, Tree) and pat.data == "pattern":
            pat = pat.children[0] if len(pat.children) == 1 and isinstance(pat.children[0], Tree) else pat
        # Lark keeps the alias for enum patterns; other pattern heads are terminals
        toks = [c for c in (pat.children if isinstance(pat, Tree) else [])]
        head = str(toks[0]) if toks and isinstance(toks[0], Token) else None
        applied = isinstance(pat, Tree) and pat.data == "enum_pattern"
        # The runtime tag stays the bare case name across a boundary: qualifying
        # it would change every existing fixture's output for a collision the
        # checker's nominal identity already makes unobservable.
        if head is not None and "/" in head:
            head = head.partition("/")[2]

        def conj(*parts: str) -> str:
            live = [p for p in parts if p != "True"]
            return " and ".join(live) if live else "True"

        def nested(sub_pat, sub_subj) -> tuple[str, list[tuple[str, str]]]:
            return self.pattern(sub_pat, sub_subj)

        if head in ("ok", "err", "some"):
            c, b = nested(toks[1], f"{subj}[1]")
            return conj(f'{subj}[0] == "{head}"', c), b
        if head == "none":
            return f'{subj}[0] == "none"', []
        if head == "list":
            return f"len({subj}) == 0", []
        if head == "cons":
            ch, cb = nested(toks[1], f"{subj}[0]")
            th, tb = nested(toks[2], f"list({subj}[1:])")
            return conj(f"len({subj}) > 0", ch, th), cb + tb
        if head == "pair":
            ah, ab = nested(toks[1], f"{subj}[1]")
            bh, bb = nested(toks[2], f"{subj}[2]")
            return conj(ah, bh), ab + bb
        if applied and head in self.enum_cases:
            conds, binds = [f'{subj}[0] == "{head}"'], []
            for i, sub in enumerate(toks[1:]):
                if not isinstance(sub, Tree):
                    continue
                c, b = nested(sub, f"{subj}[{i + 1}]")
                conds.append(c)
                binds += b
            return conj(*conds), binds
        if isinstance(pat, Token) and str(pat) == "_":
            return "True", []
        if isinstance(pat, Tree) and pat.children and isinstance(pat.children[0], Token):
            tk = pat.children[0]
            if tk.type == "WILDCARD":
                return "True", []
            if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
                return f"{subj} == {self.atom(tk)}", []
            return "True", [(str(tk), subj)]
        return "True", []

    def atom(self, tok) -> str:
        s = str(tok)
        if tok.type == "BOOL":
            return "True" if s == "true" else "False"
        if tok.type in ("INT", "FLOAT", "STRING"):
            return s
        if tok.type == "UNIT":
            return "None"
        if tok.type in ("QUALIFIED", "QUALIFIED_TYPE"):
            return self.qual(s)
        return self.resolve(s)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--root", action="append", default=[],
                    help="source root for module resolution; repeatable. "
                         "A file's own directory is always searched.")
    args = ap.parse_args()
    source = Path(args.file)
    # Written, not printed: the checked-in lowerings are compared against
    # `transpile` itself, and print's newline made the file differ from the
    # thing the drift gate calls.
    sys.stdout.write(Transpiler().transpile(source.read_text(), path=source,
                                            roots=[Path(r) for r in args.root]))
