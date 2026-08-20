#!/usr/bin/env python3
"""AgentS-Core -> Python transpiler.

Lowering rules for builtins are NOT written here: they come from
prelude/prelude.json, the single source of truth. This file owns only the
special forms, which are grammar productions rather than vocabulary.

Scope: the subset needed for a first end-to-end run — module, defschema,
defenum, defun, fn, let, if, cond, match, try, calls, field access, literals.
"""
import json
import re
import sys
from pathlib import Path

from lark import Lark, Tree, Token

ROOT = Path(__file__).parent.parent
PRELUDE = json.loads((ROOT / "prelude" / "prelude.json").read_text())
LOWER = {b["name"]: b["py"] for b in PRELUDE["builtins"]}


# Form heads are named terminals, so Lark keeps them as children. Filtering them
# centrally beats per-handler index arithmetic, which breaks the moment an
# optional child is added to a rule.
FORM_KW = {"DEFUN", "DEFSCHEMA", "DEFENUM", "MODULE", "IF", "COND", "MATCH",
           "TRY", "LET", "FN", "ARROW", "ELSE_KW", "CASE_KW", "FIELD_KW",
           "DOC_KW", "EXPORT_KW", "IMPORT_KW", "AS_KW", "DEFAULT_KW", "JSON_KW",
           "OK", "ERR", "SOME", "NONE", "LIST", "CONS", "PAIR"}


def mangle(name: str) -> str:
    """kebab-case -> snake_case, per AGENT_SPEC_CORE.md section 8."""
    if name.endswith("?"):
        name = "is-" + name[:-1]
    if name.endswith("!"):
        name = name[:-1] + "-mut"
    out = name.replace("-", "_")
    return out + "_" if out in ("None", "True", "False", "class", "def", "lambda") else out


class Transpiler:
    def __init__(self):
        self.parser = Lark((ROOT / "grammar" / "agents.lark").read_text(),
                           start="start", parser="earley", ambiguity="resolve")
        self.enum_cases: dict[str, list[str]] = {}   # case name -> field names
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

    # ---------- entry ----------

    def transpile(self, src: str) -> str:
        tree = self.parser.parse(src)
        out = ["import runtime as _as", ""]
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
        return "\n".join(out) + "\n"

    # ---------- declarations ----------

    def defschema(self, node) -> list[str]:
        kids = [k for k in self.kids(node) if not (isinstance(k, Tree) and k.data == "type_params")]
        name = self.tok(kids[0])
        fields = [self.tok(f.children[1]) for f in node.children if
                  isinstance(f, Tree) and f.data == "field"]
        args = ", ".join(mangle(f) for f in fields)
        body = ", ".join(f'"{f}": {mangle(f)}' for f in fields)
        return [f"def {name}({args}):", f"    return {{{body}}}", ""]

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
            lines += [f"def {mangle(case)}({args}):",
                      f'    return ("{case}"{items},)', ""]
        return lines

    def defun(self, node) -> list[str]:
        kids = [k for k in self.kids(node)
                if not (isinstance(k, Tree) and k.data in ("type_params", "doc_opt"))]
        name = self.tok(kids[0])
        params = [mangle(self.tok(p.children[0])) for p in kids[1].children
                  if isinstance(p, Tree) and p.data == "param"]
        # Body is everything after the return type. Indexing past the type by a
        # fixed offset breaks as soon as an optional child is filtered out.
        ti = next(i for i, k in enumerate(kids) if isinstance(k, Tree) and k.data == "type")
        body = kids[ti + 1:]
        stmts, last = [], None
        for i, b in enumerate(body):
            if i == len(body) - 1:
                last = self.expr(b, stmts, indent=1)
            else:
                self.expr(b, stmts, indent=1)
        head = f"def {mangle(name)}({', '.join(params)}):"
        return [head] + stmts + [f"    return {last}", ""]

    # ---------- expressions ----------

    def expr(self, node, stmts: list[str], indent: int) -> str:
        pad = "    " * indent
        if isinstance(node, Token):
            return self.atom(node)
        if node.data == "expr":
            return self.expr(node.children[0], stmts, indent)
        if node.data == "literal":
            return self.atom(node.children[0])

        if node.data == "let_form":
            for b in self.kids(node):
                if isinstance(b, Tree) and b.data == "binding":
                    v = self.expr(b.children[1], stmts, indent)
                    stmts.append(f"{pad}{mangle(self.tok(b.children[0]))} = {v}")
            body = [k for k in self.kids(node) if not (isinstance(k, Tree) and k.data == "binding")]
            res = None
            for b in body:
                res = self.expr(b, stmts, indent)
            return res

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
                    v = None
                    for b in self.kids(cl)[1:]:
                        v = self.expr(b, inner, indent + 1)
                    stmts += inner
                    stmts.append(f"{pad}    {t} = {v}")
                    first = False
                elif cl.data == "else_clause":
                    stmts.append(f"{pad}else:")
                    inner = []
                    v = None
                    for b in self.kids(cl):
                        v = self.expr(b, inner, indent + 1)
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
            params = [mangle(self.tok(p.children[0])) for p in kids[0].children
                      if isinstance(p, Tree) and p.data == "param"]
            sub: list[str] = []
            ti = next(i for i, k in enumerate(kids) if isinstance(k, Tree) and k.data == "type")
            body = kids[ti + 1:]
            v = None
            for b in body:
                v = self.expr(b, sub, indent + 1)
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
            name = self.tok(node.children[0])
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
        if hname in self.enum_cases:
            return f"{mangle(hname)}({', '.join(args)})"
        if hname:
            return f"{mangle(hname)}({', '.join(args)})"
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
            for b in binds:
                stmts.append(f"{pad}    {b}")
            inner: list[str] = []
            v = None
            for b in arm.children[1:]:
                v = self.expr(b, inner, indent + 1)
            stmts += inner
            stmts.append(f"{pad}    {t} = {v}")
            first = False
        return t

    def pattern(self, pat, subj) -> tuple[str, list[str]]:
        if isinstance(pat, Tree) and pat.data == "pattern":
            pat = pat.children[0] if len(pat.children) == 1 and isinstance(pat.children[0], Tree) else pat
        # Lark keeps the alias for enum patterns; other pattern heads are terminals
        toks = [c for c in (pat.children if isinstance(pat, Tree) else [])]
        head = str(toks[0]) if toks and isinstance(toks[0], Token) else None

        if head in ("ok", "err", "some"):
            inner = toks[1]
            binds = []
            if isinstance(inner, Tree) and inner.children and isinstance(inner.children[0], Token):
                binds = [f"{mangle(str(inner.children[0]))} = {subj}[1]"]
            return f'{subj}[0] == "{head}"', binds
        if head == "none":
            return f'{subj}[0] == "none"', []
        if head == "list":
            return f"len({subj}) == 0", []
        if head == "cons":
            h, t = toks[1], toks[2]
            return f"len({subj}) > 0", [
                f"{mangle(str(h.children[0]))} = {subj}[0]",
                f"{mangle(str(t.children[0]))} = list({subj}[1:])",
            ]
        if head == "pair":
            a, b = toks[1], toks[2]
            return "True", [
                f"{mangle(str(a.children[0]))} = {subj}[1]",
                f"{mangle(str(b.children[0]))} = {subj}[2]",
            ]
        if head in self.enum_cases:
            binds = [f"{mangle(str(p.children[0]))} = {subj}[{i+1}]"
                     for i, p in enumerate(toks[1:])
                     if isinstance(p, Tree) and p.children and isinstance(p.children[0], Token)]
            return f'{subj}[0] == "{head}"', binds
        if isinstance(pat, Token) and str(pat) == "_":
            return "True", []
        if isinstance(pat, Tree) and pat.children and isinstance(pat.children[0], Token):
            tk = pat.children[0]
            if tk.type == "WILDCARD":
                return "True", []
            if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
                return f"{subj} == {self.atom(tk)}", []
            return "True", [f"{mangle(str(tk))} = {subj}"]
        return "True", []

    @staticmethod
    def atom(tok) -> str:
        s = str(tok)
        if tok.type == "BOOL":
            return "True" if s == "true" else "False"
        if tok.type in ("INT", "FLOAT", "STRING"):
            return s
        if tok.type == "UNIT":
            return "None"
        return mangle(s)


if __name__ == "__main__":
    src = Path(sys.argv[1]).read_text()
    print(Transpiler().transpile(src))
