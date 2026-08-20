#!/usr/bin/env python3
"""AgentS-Core -> Rust.

Lowering rules come from prelude/prelude.json, as for every backend. This file
owns only the special forms and the type mapping.

Ownership strategy for this first pass: values are passed and returned by value,
and cloned at each use site where a binding is read more than once. That is the
conservative choice recorded as pending in PCP l-880d — it is measurably wasteful
and it is correct, which is the right order to do them in.
"""
import json
import re
import sys
from pathlib import Path

from lark import Lark, Tree, Token

ROOT = Path(__file__).parent.parent
PRELUDE = json.loads((ROOT / "prelude" / "prelude.json").read_text())
LOWER = {b["name"]: b["rs"] for b in PRELUDE["builtins"]}

FORM_KW = {"DEFUN", "DEFSCHEMA", "DEFENUM", "MODULE", "IF", "COND", "MATCH", "TRY",
           "LET", "FN", "ARROW", "ELSE_KW", "CASE_KW", "FIELD_KW", "DOC_KW",
           "EXPORT_KW", "IMPORT_KW", "AS_KW", "DEFAULT_KW", "JSON_KW",
           "OK", "ERR", "SOME", "NONE", "LIST", "CONS", "PAIR"}

PRIM = {"Bool": "bool", "Int32": "i32", "Int64": "i64", "Int": "i64",
        "Float64": "f64", "String": "String", "Unit": "()"}


def mangle(n: str) -> str:
    if n.endswith("?"):
        n = "is-" + n[:-1]
    if n.endswith("!"):
        n = n[:-1] + "-mut"
    m = n.replace("-", "_")
    return m + "_" if m in {"type", "match", "fn", "let", "loop", "move", "ref", "impl"} else m


def pascal(n: str) -> str:
    return "".join(p.capitalize() for p in n.replace("_", "-").split("-"))


class ToRust:
    def __init__(self):
        self.parser = Lark((ROOT / "grammar" / "agents.lark").read_text(),
                           start="start", parser="earley", ambiguity="resolve")
        self.enums: dict[str, tuple[str, list[str]]] = {}   # case -> (enum, field types)
        self.slice_match = False
        self.cons_tail = None
        self.tmp = 0

    def fresh(self):
        self.tmp += 1
        return f"t{self.tmp}"

    @staticmethod
    def kids(n):
        return [k for k in n.children if not (isinstance(k, Token) and k.type in FORM_KW)]

    @staticmethod
    def tok(n):
        return str(n) if isinstance(n, Token) else str(n.children[0])

    # ---------- types ----------

    def rtype(self, n) -> str:
        if isinstance(n, Tree) and n.data == "type":
            n = n.children[0] if len(n.children) == 1 else n
        if isinstance(n, Token):
            return PRIM.get(str(n), str(n))
        head = self.tok(n.children[0])
        args = [self.rtype(a) for a in n.children[1:]]
        return {
            "List": f"Vec<{args[0]}>" if args else "Vec<()>",
            "Option": f"Option<{args[0]}>" if args else "Option<()>",
            "Result": f"Result<{args[0]}, {args[1]}>" if len(args) > 1 else "Result<(),()>",
            "Pair": f"({args[0]}, {args[1]})" if len(args) > 1 else "((),())",
            "Map": f"std::collections::BTreeMap<{args[0]}, {args[1]}>" if len(args) > 1 else "()",
        }.get(head, PRIM.get(head, head))

    # ---------- entry ----------

    def transpile(self, src: str) -> str:
        tree = self.parser.parse(src)
        out = ["#![allow(dead_code, unused_variables, unused_mut, unused_parens)]",
               "mod rt;", ""]   # inner attributes must precede any item
        tops = [t.children[0] for t in tree.children]
        for n in tops:
            if n.data == "defenum":
                out += self.defenum(n)
        for n in tops:
            if n.data == "defschema":
                out += self.defschema(n)
        for n in tops:
            if n.data == "defun":
                out += self.defun(n)
        return "\n".join(out) + "\n"

    def defschema(self, n) -> list[str]:
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        fields = [f for f in n.children if isinstance(f, Tree) and f.data == "field"]
        lines = ["#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]", f"pub struct {name} {{"]
        for f in fields:
            fk = self.kids(f)
            lines.append(f"    pub {mangle(self.tok(fk[0]))}: {self.rtype(fk[1])},")
        return lines + ["}", ""]

    def defenum(self, n) -> list[str]:
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        lines = ["#[derive(Debug, Clone, PartialEq)]", f"pub enum {name} {{"]
        for c in n.children:
            if not (isinstance(c, Tree) and c.data == "enum_case"):
                continue
            ck = self.kids(c)
            case = self.tok(ck[0])
            ps = [p for p in c.children if isinstance(p, Tree) and p.data == "param"]
            tys = [self.rtype(self.kids(p)[1]) for p in ps]
            self.enums[case] = (name, tys)
            lines.append(f"    {pascal(case)}" + (f"({', '.join(tys)})," if tys else ","))
        return lines + ["}", ""]

    def defun(self, n) -> list[str]:
        k = [x for x in self.kids(n)
             if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt"))]
        name = mangle(self.tok(k[0]))
        ps = [p for p in k[1].children if isinstance(p, Tree) and p.data == "param"]
        args = ", ".join(f"{mangle(self.tok(self.kids(p)[0]))}: {self.rtype(self.kids(p)[1])}"
                         for p in ps)
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret = self.rtype(k[ti])
        body, stmts, last = k[ti + 1:], [], None
        for b in body:
            last = self.expr(b, stmts, 1)
        return [f"pub fn {name}({args}) -> {ret} {{"] + stmts + [f"    {last}", "}", ""]

    # ---------- expressions ----------

    def expr(self, n, stmts, ind) -> str:
        pad = "    " * ind
        if isinstance(n, Token):
            return self.atom(n)
        if n.data in ("expr", "literal"):
            return self.expr(n.children[0], stmts, ind)

        if n.data == "let_form":
            for b in self.kids(n):
                if isinstance(b, Tree) and b.data == "binding":
                    bk = self.kids(b)
                    v = self.expr(bk[1], stmts, ind)
                    stmts.append(f"{pad}let {mangle(self.tok(bk[0]))} = {v};")
            res = None
            for b in [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "binding")]:
                res = self.expr(b, stmts, ind)
            return res

        if n.data == "if_form":
            c, a, b = self.kids(n)
            sa, sb = [], []
            va = self.expr(a, sa, ind + 1)
            vb = self.expr(b, sb, ind + 1)
            cv = self.expr(c, stmts, ind)
            if not sa and not sb:
                return f"if {cv} {{ {va} }} else {{ {vb} }}"
            t = self.fresh()
            stmts.append(f"{pad}let {t} = if {cv} {{")
            stmts += sa + [f"{pad}    {va}", f"{pad}}} else {{"] + sb + [f"{pad}    {vb}", f"{pad}}};"]
            return t

        if n.data == "cond_form":
            t = self.fresh()
            parts, first = [], True
            for cl in self.kids(n):
                if not isinstance(cl, Tree):
                    continue
                inner: list[str] = []
                if cl.data == "cond_clause":
                    ck = self.kids(cl)
                    cv = self.expr(ck[0], stmts, ind)
                    v = None
                    for b in ck[1:]:
                        v = self.expr(b, inner, ind + 1)
                    parts.append(("if " if first else "} else if ") + f"{cv} {{")
                    parts += inner + [f"    {v}"]
                    first = False
                else:
                    v = None
                    for b in self.kids(cl):
                        v = self.expr(b, inner, ind + 1)
                    parts.append("} else {")
                    parts += inner + [f"    {v}"]
            stmts.append(f"{pad}let {t} = " + parts[0])
            for p in parts[1:]:
                stmts.append(pad + p)
            stmts.append(f"{pad}}};")
            return t

        if n.data == "match_form":
            return self.match(n, stmts, ind)

        if n.data == "try_form":
            return f"({self.expr(self.kids(n)[0], stmts, ind)})?"

        if n.data == "fn_form":
            k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
            # Rust cannot infer a closure parameter's type here, and AgentS
            # already declares it. Emitting it is free; discarding it was the bug.
            ps = [f"{mangle(self.tok(self.kids(p)[0]))}: {self.rtype(self.kids(p)[1])}"
                  for p in k[0].children if isinstance(p, Tree) and p.data == "param"]
            ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
            sub: list[str] = []
            v = None
            for b in k[ti + 1:]:
                v = self.expr(b, sub, ind + 1)
            if not sub:
                return f"|{', '.join(ps)}| {v}"
            body = "\n".join(sub + [f"{pad}    {v}"])
            return f"|{', '.join(ps)}| {{\n{body}\n{pad}}}"

        if n.data == "field_access":
            fld = self.tok(n.children[0])[2:]
            tgt = self.expr(n.children[1], stmts, ind)
            if fld in ("first", "second"):
                return f"{tgt}.{0 if fld == 'first' else 1}.clone()"
            return f"{tgt}.{mangle(fld)}.clone()"

        if n.data == "ctor":
            name = self.tok(n.children[0])
            fs = [f"{mangle(self.tok(a.children[0])[1:])}: {self.expr(a.children[1], stmts, ind)}"
                  for a in n.children[1:] if isinstance(a, Tree) and a.data == "ctor_arg"]
            return f"{name} {{ {', '.join(fs)} }}"

        if n.data == "call":
            return self.call(n, stmts, ind)

        raise NotImplementedError(f"form not lowered to Rust: {n.data}")

    def call(self, n, stmts, ind) -> str:
        head = n.children[0]
        h = head.children[0] if isinstance(head, Tree) and head.data == "expr" else head
        # Conservative ownership: a bare binding used as an argument is cloned.
        # A binding can appear twice in one call (moved into one parameter while
        # borrowed by another), which the borrow checker rejects. Cloning is
        # wasteful and correct; the cost is what PCP l-880d is for measuring.
        args = []
        for a in n.children[1:]:
            v = self.expr(a, stmts, ind)
            if re.fullmatch(r"[a-z_][a-z0-9_]*", v):
                v += ".clone()"
            args.append(v)
        name = str(h) if isinstance(h, Token) else None
        if name in LOWER:
            tpl = LOWER[name]
            return tpl.replace("{*}", ", ".join(args)) if "{*}" in tpl else tpl.format(*args)
        if name in self.enums:
            en, _ = self.enums[name]
            return f"{en}::{pascal(name)}" + (f"({', '.join(args)})" if args else "")
        if name:
            return f"{mangle(name)}({', '.join(args)})"
        return f"({self.expr(head, stmts, ind)})({', '.join(args)})"

    def match(self, n, stmts, ind) -> str:
        pad = "    " * ind
        mk = self.kids(n)
        subj = self.expr(mk[0], stmts, ind)
        t = self.fresh()
        # Rust destructures a list only through a slice pattern, so a match
        # containing list arms must scrutinise a slice rather than the Vec.
        arms = [a for a in mk[1:] if isinstance(a, Tree) and a.data == "match_arm"]
        self.slice_match = any(self._is_list_pat(self.kids(a)[0]) for a in arms)
        scrut = f"{subj}.as_slice()" if self.slice_match else subj
        stmts.append(f"{pad}let {t} = match {scrut} {{")
        for arm in mk[1:]:
            if not (isinstance(arm, Tree) and arm.data == "match_arm"):
                continue
            ak = self.kids(arm)
            pat = self.pattern(ak[0])
            inner: list[str] = []
            v = None
            for b in ak[1:]:
                v = self.expr(b, inner, ind + 2)
            pre = []
            if getattr(self, "cons_tail", None) and "@ .." in pat:
                pre = [f"{pad}        let {self.cons_tail} = {self.cons_tail}.to_vec();"]
                self.cons_tail = None
            if inner or pre:
                body = "\n".join(pre + inner + [f"{pad}        {v}"])
                stmts.append(f"{pad}    {pat} => {{\n{body}\n{pad}    }},")
            else:
                stmts.append(f"{pad}    {pat} => {v},")
        if self.slice_match:
            stmts.append(f"{pad}    _ => unreachable!(),")
        stmts.append(f"{pad}}};")
        return t

    def _is_list_pat(self, pat) -> bool:
        if isinstance(pat, Tree) and pat.data == "pattern" and len(pat.children) == 1 \
                and isinstance(pat.children[0], Tree):
            pat = pat.children[0]
        toks = pat.children if isinstance(pat, Tree) else []
        return bool(toks) and isinstance(toks[0], Token) and str(toks[0]) in ("list", "cons")

    def pattern(self, pat) -> str:
        if isinstance(pat, Tree) and pat.data == "pattern" and len(pat.children) == 1 \
                and isinstance(pat.children[0], Tree):
            pat = pat.children[0]
        toks = pat.children if isinstance(pat, Tree) else []
        head = str(toks[0]) if toks and isinstance(toks[0], Token) else None

        def sub(p):
            if isinstance(p, Tree) and p.children and isinstance(p.children[0], Token):
                tk = p.children[0]
                return "_" if tk.type == "WILDCARD" else mangle(str(tk))
            return "_"

        if head in ("ok", "err", "some"):
            return {"ok": "Ok", "err": "Err", "some": "Some"}[head] + f"({sub(toks[1])})"
        if head == "none":
            return "None"
        if head == "list":
            return "[]"
        if head == "cons":
            h, rest = sub(toks[1]), sub(toks[2])
            # The tail is bound as a slice; the body expects an owned list, so it
            # is materialised at the top of the arm (see match()).
            self.cons_tail = rest
            return f"[{h}, {rest} @ ..]"
        if head == "pair":
            return f"({sub(toks[1])}, {sub(toks[2])})"
        if head in self.enums:
            en, tys = self.enums[head]
            inner = ", ".join(sub(p) for p in toks[1:] if isinstance(p, Tree))
            return f"{en}::{pascal(head)}" + (f"({inner})" if tys else "")
        if isinstance(pat, Tree) and pat.children and isinstance(pat.children[0], Token):
            tk = pat.children[0]
            if tk.type == "WILDCARD":
                return "_"
            if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
                return self.atom(tk)
            return mangle(str(tk))
        return "_"

    @staticmethod
    def atom(tok) -> str:
        s = str(tok)
        if tok.type == "BOOL":
            return "true" if s == "true" else "false"
        if tok.type == "STRING":
            return f"{s}.to_string()"
        if tok.type in ("INT", "FLOAT"):
            return s
        if tok.type == "UNIT":
            return "()"
        return mangle(s)


if __name__ == "__main__":
    print(ToRust().transpile(Path(sys.argv[1]).read_text()))
