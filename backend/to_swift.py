#!/usr/bin/env python3
"""AgentScript Core -> Swift.

Lowering rules come from prelude/prelude.json, as for every backend. This file
owns only the special forms and the type mapping.

Every AgentScript form is an expression, and Swift's are statements, so the forms that
cannot be written as one expression — `match`, and anything containing a binding
or a `try` — are lowered to an immediately-applied closure. Swift 5.7 infers the
result type of a multi-statement closure, which is what makes this work without a
type checker in front of it.

`try` uses typed throws: the runtime's unwrap throws `ASThrown<E>`, and a `defun`
whose body contains a `try` wraps that body in `do`/`catch`. The colouring stays
inside the function, so callers see an ordinary `ASResult` return.
"""
import json
import sys
from pathlib import Path

from lark import Lark, Tree, Token

import modules
from boundary import NotLowered, TargetMismatch, check_target
from modules import ModuleError

ROOT = Path(__file__).parent.parent
PRELUDE = json.loads((ROOT / "prelude" / "prelude.json").read_text())
LOWER = {b["name"]: b["sw"] for b in PRELUDE["builtins"]}

FORM_KW = {"DEFENTRY", "DEFEXTERN", "DEFOPAQUE", "EXTERN_KW", "EFFECTS_KW",
           "TARGET_KW", "SYMBOL_KW",
           "DEFUN", "DEFSCHEMA", "DEFENUM", "MODULE", "IF", "COND", "MATCH", "TRY",
           "LET", "FN", "ARROW", "ELSE_KW", "CASE_KW", "FIELD_KW", "DOC_KW",
           "EXPORT_KW", "IMPORT_KW", "AS_KW", "DEFAULT_KW", "JSON_KW",
           "OK", "ERR", "SOME", "NONE", "LIST", "CONS", "PAIR"}

PRIM = {"Bool": "Bool", "Int32": "Int32", "Int64": "Int64", "Int": "Int64",
        "Float64": "Double", "String": "String", "Unit": "Void"}

HASHABLE_PRIM = {"Bool", "Int32", "Int64", "Int", "Float64", "String"}
COMPARABLE_PRIM = {"Int32", "Int64", "Int", "Float64", "String"}

# Swift's reserved words that a mangled AgentScript name can collide with. Spec §8
# appends `_` rather than backticking, so the emitted name is still a plain
# identifier in every position.
SWIFT_KW = {"as", "associatedtype", "break", "case", "catch", "class", "continue",
            "default", "defer", "deinit", "do", "else", "enum", "extension",
            "fallthrough", "false", "fileprivate", "for", "func", "guard", "if",
            "import", "in", "init", "inout", "internal", "is", "let", "nil",
            "operator", "private", "protocol", "public", "repeat", "rethrows",
            "return", "self", "static", "struct", "subscript", "super", "switch",
            "throw", "throws", "true", "try", "typealias", "var", "where", "while"}


def mangle(n: str) -> str:
    """kebab-case -> camelCase, per AGENT_SPEC_CORE.md §8."""
    if "/" in n:
        # `alias/member` flattens to one name; see to_python.mangle.
        head, *rest = [mangle(part) for part in n.split("/")]
        return head + "".join(r[:1].upper() + r[1:] for r in rest)
    if n.endswith("?"):
        n = "is-" + n[:-1]
    if n.endswith("!"):
        n = n[:-1] + "-mut"
    parts = [p for p in n.split("-") if p]
    m = parts[0] + "".join(p.capitalize() for p in parts[1:])
    return m + "_" if m in SWIFT_KW else m


def has_try(n) -> bool:
    if isinstance(n, Tree):
        return n.data == "try_form" or any(has_try(c) for c in n.children)
    return False


class ToSwift:
    def __init__(self):
        self.parser = Lark((ROOT / "grammar" / "as-lang.lark").read_text(),
                           start="start", parser="earley", ambiguity="resolve")
        self.enums: dict[str, tuple[str, int]] = {}        # case -> (enum, arity)
        # Whether an enum carries associated values, which decides what Swift can
        # synthesize for it (see _traits).
        self.enum_payloads: dict[str, bool] = {}
        self.schemas: dict[str, list[str]] = {}            # schema -> field order
        self.err_ty: str | None = None                     # E of the enclosing defun
        self.tmp = 0
        # Naming context; replaced per module by enter(). A single-module
        # program leaves the prefix empty, which is the common case.
        self.prefix = ""
        self.aliases: dict[str, str] = {}
        self.local_tops: set[str] = set()

    def fresh(self) -> str:
        self.tmp += 1
        return f"t{self.tmp}"

    @staticmethod
    def kids(n):
        return [k for k in n.children if not (isinstance(k, Token) and k.type in FORM_KW)]

    @staticmethod
    def tok(n):
        return str(n) if isinstance(n, Token) else str(n.children[0])

    # ---------- types ----------

    def stype(self, n) -> str:
        if isinstance(n, Tree) and n.data == "type":
            n = n.children[0] if len(n.children) == 1 else n
        if isinstance(n, Token):
            return PRIM.get(str(n), str(n))
        head = self.tok(n.children[0])
        args = [self.stype(a) for a in n.children[1:]]
        return {
            "List": f"[{args[0]}]" if args else "[Void]",
            "Option": f"{args[0]}?" if args else "Void?",
            "Result": f"ASResult<{args[0]}, {args[1]}>" if len(args) > 1 else "ASResult<Void, Void>",
            "Pair": f"ASPair<{args[0]}, {args[1]}>" if len(args) > 1 else "ASPair<Void, Void>",
            "Map": f"[{args[0]}: {args[1]}]" if len(args) > 1 else "[Void: Void]",
        }.get(head, PRIM.get(head, head))

    def _traits(self, n, prim: set[str], containers: bool, payload_enums: bool = True) -> bool:
        """Whether a conformance can be synthesized for this type.

        `payload_enums` is False for Comparable: Swift synthesizes Equatable and
        Hashable for an enum that carries associated values, but Comparable only
        for one that carries none. Treating the two alike emitted a record whose
        `<` compared two enum payloads that have no `<`.
        """
        if isinstance(n, Tree) and n.data == "type":
            n = n.children[0] if len(n.children) == 1 else n
        if isinstance(n, Token):
            name = str(n)
            if name in {e for e, _ in self.enums.values()}:
                return payload_enums or not self.enum_payloads.get(name, False)
            return name in prim or name in self.schemas
        head = self.tok(n.children[0])
        if not containers or head == "Result":
            return False
        return all(self._traits(a, prim, containers, payload_enums) for a in n.children[1:])

    def conformances(self, types: list) -> str:
        """`Result` has no Hashable conformance and Void has neither, so a type
        holding one gets no synthesized conformance rather than a broken one."""
        out = []
        if all(self._traits(t, HASHABLE_PRIM, True) for t in types):
            out = ["Equatable", "Hashable"]
        if types and all(self._traits(t, COMPARABLE_PRIM, False, payload_enums=False)
                         for t in types):
            out.append("Comparable")
        return (": " + ", ".join(out)) if out else ""

    @staticmethod
    def type_params(n) -> str:
        tp = [x for x in n.children if isinstance(x, Tree) and x.data == "type_params"]
        if not tp:
            return ""
        names = [str(t) for t in tp[0].children if isinstance(t, Token)]
        return f"<{', '.join(names)}>" if names else ""

    # ---------- entry ----------

    def transpile(self, src: str) -> str:
        return self.transpile_program(modules.single(src, self.parser))

    def transpile_file(self, path) -> str:
        return self.transpile_program(modules.load(Path(path), p=self.parser))

    def transpile_program(self, prog) -> str:
        """One output file for the whole program, dependencies first."""
        out: list[str] = []
        for mod in prog.modules:
            check_target(mod.tops, self.TARGET, lowers_foreign=False)
        for mod in prog.modules:
            self.enter(mod)
            tops = mod.tops
            for n in tops:
                if n.data == "defenum":
                    out += self.defenum(n)
            for n in tops:
                if n.data == "defschema":
                    out += self.defschema(n)
            for n in tops:
                if n.data == "defun":
                    out += self.defun(n)
            for n in tops:
                if n.data == "defentry":
                    out += self.defentry(n)
        return "\n".join(out) + "\n"

    def enter(self, mod) -> None:
        """Emit in the naming context of one module.

        Only an imported module's top-level names are prefixed. The entry
        module's are the program's own surface, and prefixing them would rename
        every function the tests and the differential harness call by name.
        """
        self.prefix = mod.prefix()
        self.aliases = mod.imports
        self.local_tops = set(modules.top_level_names(mod.tops))

    def gname(self, name: str) -> str:
        """A name as written in this module -> the whole program's name for it."""
        if "/" in name:
            alias, member = name.split("/", 1)
            target = self.aliases.get(alias)
            if target is None:
                raise NotImplementedError(f"unbound alias in `{name}`")
            return mangle(f"{target}/{member}")
        if name in self.local_tops:
            return mangle(self.prefix + name)
        return mangle(name)

    # The foreign-boundary rule lives in backend/boundary.py. This backend does
    # not lower foreign declarations, so a module holding them is refused —
    # as a target mismatch when it names another ecosystem, and as an
    # unimplemented backend when it names this one. The two are not the same
    # failure and must not report as one.
    TARGET = "sw"

    def defentry(self, n) -> list[str]:
        """The entry point is named with the reserved `as-` prefix, which is what
        that prefix is reserved for: a compiler-internal name no user code owns."""
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "decl_opt")]
        ps = [p for p in k[0].children if isinstance(p, Tree) and p.data == "param"]
        args = ", ".join(f"_ {mangle(self.tok(self.kids(p)[0]))}: {self.stype(self.kids(p)[1])}"
                         for p in ps)
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret_node = k[ti]
        self.err_ty = self._result_err(ret_node)
        lines = self.block(k[ti + 1:], 2 if has_try(n) else 1)
        if has_try(n):
            lines = ["    do {"] + lines + ["    } catch {",
                                            "        return .err(error.value)",
                                            "    }"]
        self.err_ty = None
        return ([f"public func asEntry({args}) -> {self.stype(ret_node)} {{"]
                + lines + ["}", ""]
                + ["@main",
                   "struct ASMain {",
                   "    static func main() {",
                   "        if case .err(let e) = asEntry(RT.args()) { RT.fail(e) }",
                   "    }",
                   "}", ""])

    def defschema(self, n) -> list[str]:
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        gen = self.type_params(n)
        fields = [f for f in n.children if isinstance(f, Tree) and f.data == "field"]
        names = [mangle(self.tok(self.kids(f)[0])) for f in fields]
        types = [self.kids(f)[1] for f in fields]
        self.schemas[name] = names
        conf = self.conformances(types) if not gen else ""
        lines = [f"public struct {name}{gen}{conf} {{"]
        for fname, t in zip(names, types):
            lines.append(f"    public let {fname}: {self.stype(t)}")
        args = ", ".join(f"{f}: {self.stype(t)}" for f, t in zip(names, types))
        body = "; ".join(f"self.{f} = {f}" for f in names)
        lines += [f"    public init({args}) {{ {body} }}"]
        if "Comparable" in conf:
            # One statement per line. Joining them with spaces produced valid
            # Swift only while a record had two fields; at three the parser
            # rejects consecutive statements on one line.
            lines.append("    public static func < (l: Self, r: Self) -> Bool {")
            lines += [f"        if l.{f} != r.{f} {{ return l.{f} < r.{f} }}"
                      for f in names[:-1]]
            lines += [f"        return l.{names[-1]} < r.{names[-1]}", "    }"]
        return [x for x in lines if x != ""] + ["}", ""]

    def defenum(self, n) -> list[str]:
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        gen = self.type_params(n)
        cases = [c for c in n.children if isinstance(c, Tree) and c.data == "enum_case"]
        payloads, decls = [], []
        for c in cases:
            case = self.tok(self.kids(c)[0])
            ps = [p for p in c.children if isinstance(p, Tree) and p.data == "param"]
            tys = [self.kids(p)[1] for p in ps]
            self.enums[case] = (name, len(tys))
            payloads += tys
            rendered = ", ".join(self.stype(t) for t in tys)
            decls.append(f"    case {mangle(case)}" + (f"({rendered})" if tys else ""))
        # `indirect` is what makes a recursive union expressible; Swift rejects it
        # on an enum that carries nothing, so it is applied only where it is legal.
        self.enum_payloads[name] = bool(payloads)
        kw = "indirect enum" if payloads else "enum"
        conf = self.conformances(payloads) if (payloads and not gen) else ""
        return [f"public {kw} {name}{gen}{conf} {{"] + decls + ["}", ""]

    def defun(self, n) -> list[str]:
        k = [x for x in self.kids(n)
             if not (isinstance(x, Tree) and x.data in ("type_params", "decl_opt"))]
        name = mangle(self.prefix + self.tok(k[0]))
        gen = self.type_params(n)
        ps = [p for p in k[1].children if isinstance(p, Tree) and p.data == "param"]
        args = ", ".join(f"_ {mangle(self.tok(self.kids(p)[0]))}: {self.stype(self.kids(p)[1])}"
                         for p in ps)
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret_node = k[ti]
        ret = self.stype(ret_node)
        self.err_ty = self._result_err(ret_node)
        body = k[ti + 1:]
        lines = self.block(body, 2 if has_try(n) else 1)
        if has_try(n):
            lines = ["    do {"] + lines + ["    } catch {",
                                            "        return .err(error.value)",
                                            "    }"]
        self.err_ty = None
        return [f"public func {name}{gen}({args}) -> {ret} {{"] + lines + ["}", ""]

    def _result_err(self, t) -> str | None:
        if isinstance(t, Tree) and t.data == "type":
            t = t.children[0] if len(t.children) == 1 else t
        if isinstance(t, Tree) and self.tok(t.children[0]) == "Result" and len(t.children) > 2:
            return self.stype(t.children[2])
        return None

    # ---------- statement blocks ----------

    def block(self, exprs, ind: int) -> list[str]:
        """Lower a body to statements. A trailing `let` is flattened rather than
        wrapped in a closure — every AgentScript body is one, and the nesting would
        otherwise dominate the output."""
        pad = "    " * ind
        lines: list[str] = []
        for e in exprs[:-1]:
            lines.append(f"{pad}_ = {self.expr(e, ind)}")
        last = self.unwrap_expr(exprs[-1])
        if isinstance(last, Tree) and last.data == "let_form":
            for b in self.kids(last):
                if isinstance(b, Tree) and b.data == "binding":
                    bk = self.kids(b)
                    lines.append(f"{pad}let {mangle(self.tok(bk[0]))} = {self.expr(bk[1], ind)}")
            inner = [x for x in self.kids(last) if not (isinstance(x, Tree) and x.data == "binding")]
            return lines + self.block(inner, ind)
        lines.append(f"{pad}return {self.expr(last, ind)}")
        return lines

    def iife(self, lines: list[str], ind: int, throwing: bool) -> str:
        pad = "    " * ind
        ann = f"() throws(ASThrown<{self.err_ty}>) in" if (throwing and self.err_ty) else "() in"
        head = ("try " if throwing else "") + "{ " + ann
        return head + "\n" + "\n".join(lines) + f"\n{pad}}}()"

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
            return self.iife(self.block([n], ind + 1), ind, has_try(n))

        if n.data == "if_form":
            c, a, b = self.kids(n)
            if has_try(n):
                pad = "    " * (ind + 1)
                lines = [f"{pad}if {self.expr(c, ind + 1)} {{"]
                lines += self.block([a], ind + 2) + [f"{pad}}} else {{"]
                lines += self.block([b], ind + 2) + [f"{pad}}}"]
                return self.iife(lines, ind, True)
            return f"({self.expr(c, ind)} ? {self.expr(a, ind)} : {self.expr(b, ind)})"

        if n.data == "cond_form":
            return self.cond(n, ind)

        if n.data == "match_form":
            return self.match(n, ind)

        if n.data == "try_form":
            return f"try RT.unwrap({self.expr(self.kids(n)[0], ind)})"

        if n.data == "fn_form":
            return self.fn(n, ind)

        if n.data == "field_access":
            fld = self.tok(n.children[0])[2:]
            return f"{self.expr(n.children[1], ind)}.{mangle(fld)}"

        if n.data == "ctor":
            name = self.tok(n.children[0])
            given = {self.tok(a.children[0])[1:]: self.expr(a.children[1], ind)
                     for a in n.children[1:] if isinstance(a, Tree) and a.data == "ctor_arg"}
            order = self.schemas.get(name) or list(given)
            fields = ", ".join(f"{f}: {given[f]}" for f in order if f in given)
            return f"{name}({fields})"

        if n.data == "call":
            return self.call(n, ind)

        raise NotImplementedError(f"form not lowered to Swift: {n.data}")

    def cond(self, n, ind: int) -> str:
        clauses = [c for c in self.kids(n) if isinstance(c, Tree)]
        if not has_try(n):
            out = None
            for cl in reversed(clauses):
                ck = self.kids(cl)
                if cl.data == "cond_clause":
                    out = f"({self.expr(ck[0], ind)} ? {self.expr(ck[-1], ind)} : {out})"
                else:
                    out = self.expr(ck[-1], ind)
            return out
        pad = "    " * (ind + 1)
        lines: list[str] = []
        for cl in clauses:
            ck = self.kids(cl)
            if cl.data == "cond_clause":
                lines.append(f"{pad}if {self.expr(ck[0], ind + 1)} {{")
                lines += self.block(ck[1:], ind + 2) + [f"{pad}}}"]
            else:
                lines += self.block(ck, ind + 1)
        return self.iife(lines, ind, True)

    def fn(self, n, ind: int) -> str:
        if has_try(n):
            raise NotImplementedError("`try` inside `fn` is not lowered to Swift: the closure "
                                      "would have to carry the throwing signature")
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        ps = ", ".join(f"{mangle(self.tok(self.kids(p)[0]))}: {self.stype(self.kids(p)[1])}"
                       for p in k[0].children if isinstance(p, Tree) and p.data == "param")
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret = self.stype(k[ti])
        body = self.block(k[ti + 1:], ind + 1)
        pad = "    " * ind
        return "{ (" + ps + f") -> {ret} in\n" + "\n".join(body) + f"\n{pad}}}"

    def call(self, n, ind: int) -> str:
        head = self.unwrap_expr(n.children[0])
        args = [self.expr(a, ind) for a in n.children[1:]]
        name = str(head) if isinstance(head, Token) else None
        if name in LOWER:
            tpl = LOWER[name]
            return tpl.replace("{*}", ", ".join(args)) if "{*}" in tpl else tpl.format(*args)
        if name in self.enums:
            en, arity = self.enums[name]
            return f"{en}.{mangle(name)}" + (f"({', '.join(args)})" if arity else "")
        if name:
            return f"{self.gname(name)}({', '.join(args)})"
        return f"({self.expr(head, ind)})({', '.join(args)})"

    # ---------- match ----------

    def match(self, n, ind: int) -> str:
        mk = self.kids(n)
        arms = [a for a in mk[1:] if isinstance(a, Tree) and a.data == "match_arm"]
        subj = self.expr(mk[0], ind)
        structural = any(self._head(self.kids(a)[0]) in ("list", "cons", "pair") for a in arms)
        return self.match_if(subj, arms, ind) if structural else self.match_switch(subj, arms, ind)

    def _head(self, pat):
        pat = pat.children[0] if (isinstance(pat, Tree) and pat.data == "pattern"
                                  and len(pat.children) == 1
                                  and isinstance(pat.children[0], Tree)) else pat
        toks = pat.children if isinstance(pat, Tree) else []
        return str(toks[0]) if toks and isinstance(toks[0], Token) else None

    @staticmethod
    def _leaf(p):
        """The token of a leaf pattern — a literal, a binding name or `_`."""
        while isinstance(p, Tree) and len(p.children) == 1 and p.data in ("pattern", "literal"):
            p = p.children[0]
        return p if isinstance(p, Token) else None

    def _frag(self, p) -> str:
        """A sub-pattern as it appears inside a Swift case pattern."""
        tk = self._leaf(p)
        if tk is None or tk.type == "WILDCARD":
            return "_"
        return self.atom(tk) if tk.type in ("INT", "FLOAT", "STRING", "BOOL") else f"let {mangle(str(tk))}"

    def match_switch(self, subj: str, arms, ind: int) -> str:
        pad = "    " * (ind + 1)
        throwing = any(has_try(a) for a in arms)
        lines = [f"{pad}switch {subj} {{"]
        for arm in arms:
            ak = self.kids(arm)
            lines.append(f"{pad}{self.case_pattern(ak[0])}")
            lines += self.block(ak[1:], ind + 2)
        lines.append(f"{pad}}}")
        return self.iife(lines, ind, throwing)

    def case_pattern(self, pat) -> str:
        head = self._head(pat)
        inner = [p for p in (pat.children[0] if (isinstance(pat, Tree) and pat.data == "pattern"
                                                 and len(pat.children) == 1
                                                 and isinstance(pat.children[0], Tree))
                             else pat).children if isinstance(p, Tree)]

        def binds(ps):
            return ", ".join(self._frag(p) for p in ps)

        if head in ("ok", "err", "some"):
            return f"case .{head}({binds(inner)}):"
        if head == "none":
            return "case .none:"
        if head in self.enums:
            en, arity = self.enums[head]
            return f"case .{mangle(head)}" + (f"({binds(inner)}):" if arity else ":")
        tk = self._leaf(pat)
        if tk is None or tk.type == "WILDCARD":
            return "default:"
        if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
            return f"case {self.atom(tk)}:"
        return f"case let {mangle(str(tk))}:"

    def match_if(self, subj: str, arms, ind: int) -> str:
        """List, cons and pair patterns: Swift has no slice pattern and cannot
        destructure a struct in a `switch`, so these lower to a guarded chain."""
        pad = "    " * (ind + 1)
        s = self.fresh()
        lines = [f"{pad}let {s} = {subj}"]
        total = False
        for arm in arms:
            ak = self.kids(arm)
            cond, binds = self.structural_pattern(ak[0], s)
            body_ind = ind + 1 if cond is None else ind + 2
            body_pad = "    " * body_ind
            if cond is None:
                lines += [f"{body_pad}{b}" for b in binds]
                lines += self.block(ak[1:], body_ind)
                total = True
                break
            lines.append(f"{pad}if {cond} {{")
            lines += [f"{body_pad}{b}" for b in binds]
            lines += self.block(ak[1:], body_ind) + [f"{pad}}}"]
        if not total:
            lines.append(f'{pad}fatalError("non-exhaustive match")')
        return self.iife(lines, ind, any(has_try(a) for a in arms))

    def structural_pattern(self, pat, s: str) -> tuple[str | None, list[str]]:
        head = self._head(pat)
        node = pat.children[0] if (isinstance(pat, Tree) and pat.data == "pattern"
                                   and len(pat.children) == 1
                                   and isinstance(pat.children[0], Tree)) else pat
        subs = [p for p in node.children if isinstance(p, Tree)] if isinstance(node, Tree) else []
        if head == "list":
            conds = [f"{s}.isEmpty"] if not subs else [f"{s}.count == {len(subs)}"]
            binds = []
            for i, sub in enumerate(subs):
                conds, binds = self._destructure(sub, f"{s}[{i}]", conds, binds)
            return " && ".join(conds), binds
        if head == "cons":
            conds, binds = self._destructure(subs[0], f"{s}[0]", [f"!{s}.isEmpty"], [])
            conds, binds = self._destructure(subs[1], f"Array({s}.dropFirst())", conds, binds)
            return " && ".join(conds), binds
        if head == "pair":
            conds, binds = self._destructure(subs[0], f"{s}.first", [], [])
            conds, binds = self._destructure(subs[1], f"{s}.second", conds, binds)
            return (" && ".join(conds) or None), binds
        tk = self._leaf(pat)
        if tk is None or tk.type == "WILDCARD":
            return None, []
        if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
            return f"{s} == {self.atom(tk)}", []
        return None, [f"let {mangle(str(tk))} = {s}"]

    def _destructure(self, sub, access: str, conds: list[str], binds: list[str]):
        """A sub-pattern of a structural pattern either tests or binds its slot."""
        tk = self._leaf(sub)
        if tk is None or tk.type == "WILDCARD":
            return conds, binds
        if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
            return conds + [f"{access} == {self.atom(tk)}"], binds
        return conds, binds + [f"let {mangle(str(tk))} = {access}"]

    def atom(self, tok) -> str:
        s = str(tok)
        if tok.type == "UNIT":
            return "()"
        if tok.type in ("BOOL", "INT", "FLOAT", "STRING"):
            return s
        return self.gname(s)


if __name__ == "__main__":
    try:
        print(ToSwift().transpile_file(Path(sys.argv[1])))
    except (TargetMismatch, NotLowered, ModuleError) as exc:
        # A refusal is a result, not a crash: this is the path a module for
        # another ecosystem takes, and a stack trace would read as a defect.
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(2)
