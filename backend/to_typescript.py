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
LOWER = {b["name"]: b["ts"] for b in PRELUDE["builtins"]}

FORM_KW = {"DEFENTRY", "DEFEXTERN", "DEFOPAQUE", "EXTERN_KW", "EFFECTS_KW",
           "TARGET_KW", "SYMBOL_KW",
           "DEFUN", "DEFSCHEMA", "DEFENUM", "MODULE", "IF", "COND", "MATCH", "TRY",
           "LET", "FN", "ARROW", "ELSE_KW", "CASE_KW", "FIELD_KW", "DOC_KW",
           "EXPORT_KW", "IMPORT_KW", "AS_KW", "DEFAULT_KW", "JSON_KW",
           "OK", "ERR", "SOME", "NONE", "LIST", "CONS", "PAIR"}

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
    return m + "_" if m in TS_KW else m


def has_try(n) -> bool:
    if isinstance(n, Tree):
        return n.data == "try_form" or any(has_try(c) for c in n.children)
    return False


class ToTypeScript:
    def __init__(self):
        self.parser = Lark((ROOT / "grammar" / "as-lang.lark").read_text(),
                           start="start", parser="earley", ambiguity="resolve")
        self.enums: dict[str, tuple[str, int]] = {}        # case -> (enum, arity)
        self.schemas: dict[str, list[str]] = {}            # schema -> field order
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

    def ttype(self, n) -> str:
        if isinstance(n, Tree) and n.data == "type":
            n = n.children[0] if len(n.children) == 1 else n
        if isinstance(n, Token):
            return PRIM.get(str(n), str(n))
        head = self.tok(n.children[0])
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
    def type_params(n) -> str:
        tp = [x for x in n.children if isinstance(x, Tree) and x.data == "type_params"]
        if not tp:
            return ""
        names = [str(t) for t in tp[0].children if isinstance(t, Token)]
        return f"<{', '.join(names)}>" if names else ""

    # ---------- entry ----------

    # The foreign-boundary rule lives in backend/boundary.py. This backend does
    # not lower foreign declarations, so a module holding them is refused — as a
    # target mismatch when it names another ecosystem, and as an unimplemented
    # backend when it names this one. The two are not the same failure and must
    # not report as one.
    TARGET = "ts"

    def transpile(self, src: str) -> str:
        return self.transpile_program(modules.single(src, self.parser))

    def transpile_file(self, path) -> str:
        return self.transpile_program(modules.load(Path(path), p=self.parser))

    def transpile_program(self, prog) -> str:
        """One output file for the whole program, dependencies first."""
        out = ['import * as RT from "./rt";',
               'import type { ASMap, ASOption, ASPair, ASResult, ProcessResult } from "./rt";',
               ""]
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

        Only an imported module's top-level names are prefixed; the entry
        module's are the program's own surface.
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

    # ---------- declarations ----------

    def defentry(self, n) -> list[str]:
        """The entry point is named with the reserved `as-` prefix, which is what
        that prefix is reserved for: a compiler-internal name no user code owns."""
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "decl_opt")]
        args = self.param_list(k[0])
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret = self.ttype(k[ti])
        body = self.guarded(n, k[ti + 1:])
        return ([f"export function asEntry({args}): {ret} {{"] + body + ["}", ""]
                + ["function asMain(): void {",
                   "    const r = asEntry(RT.args());",
                   '    if (r.tag === "err") { RT.fail(r.value); }',
                   "}",
                   "asMain();", ""])

    def defschema(self, n) -> list[str]:
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        gen = self.type_params(n)
        fields = [f for f in n.children if isinstance(f, Tree) and f.data == "field"]
        names = [mangle(self.tok(self.kids(f)[0])) for f in fields]
        types = [self.ttype(self.kids(f)[1]) for f in fields]
        self.schemas[name] = names
        # A named-argument constructor, not a positional one: a missing or
        # misspelled field is then a type error rather than a silent reorder,
        # which is what `(Point :x 1 :y 2)` says at the call site.
        arg = "; ".join(f"{f}: {t}" for f, t in zip(names, types))
        lines = [f"export class {name}{gen} {{"]
        lines += [f"    readonly {f}: {t};" for f, t in zip(names, types)]
        lines.append(f"    constructor(f: {{ {arg} }}) {{")
        lines += [f"        this.{f} = f.{f};" for f in names]
        return lines + ["    }", "}", ""]

    def defenum(self, n) -> list[str]:
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
            # Payload slots are numbered, not named after the declared parameter:
            # a pattern binds them positionally, and a parameter spelled `tag`
            # would otherwise collide with the discriminant.
            slots = "".join(f"; readonly _{i}: {t}" for i, t in enumerate(tys))
            arms.append(f'  | {{ readonly tag: "{case}"{slots} }}')
            params = ", ".join(f"_{i}: {t}" for i, t in enumerate(tys))
            built = "".join(f", _{i}" for i in range(len(tys)))
            ctors += [f"export function {mangle(case)}{gen}({params}): {name}{gen} {{",
                      f'    return {{ tag: "{case}"{built} }};',
                      "}", ""]
        return [f"export type {name}{gen} ="] + arms[:-1] + [arms[-1] + ";", ""] + ctors

    def defun(self, n) -> list[str]:
        k = [x for x in self.kids(n)
             if not (isinstance(x, Tree) and x.data in ("type_params", "decl_opt"))]
        name = mangle(self.prefix + self.tok(k[0]))
        gen = self.type_params(n)
        args = self.param_list(k[1])
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret = self.ttype(k[ti])
        body = self.guarded(n, k[ti + 1:])
        return [f"export function {name}{gen}({args}): {ret} {{"] + body + ["}", ""]

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
        would otherwise dominate the output."""
        pad = "    " * ind
        lines: list[str] = []
        for e in exprs[:-1]:
            # `void` because an object literal at statement position parses as a
            # block, and the enum constructors emit object literals.
            lines.append(f"{pad}void ({self.expr(e, ind)});")
        last = self.unwrap_expr(exprs[-1])
        if isinstance(last, Tree) and last.data == "let_form":
            for b in self.kids(last):
                if isinstance(b, Tree) and b.data == "binding":
                    bk = self.kids(b)
                    lines.append(f"{pad}const {mangle(self.tok(bk[0]))} = {self.expr(bk[1], ind)};")
            inner = [x for x in self.kids(last) if not (isinstance(x, Tree) and x.data == "binding")]
            return lines + self.block(inner, ind)
        lines.append(f"{pad}return {self.expr(last, ind)};")
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
            out = None
            for cl in reversed([c for c in self.kids(n) if isinstance(c, Tree)]):
                ck = self.kids(cl)
                if cl.data == "cond_clause":
                    out = f"({self.expr(ck[0], ind)} ? {self.expr(ck[-1], ind)} : {out})"
                else:
                    out = self.expr(ck[-1], ind)
            return out

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
            name = self.tok(n.children[0])
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
        ps = self.param_list(k[0])
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret = self.ttype(k[ti])
        body = self.block(k[ti + 1:], ind + 1)
        pad = "    " * ind
        return f"(({ps}): {ret} => {{\n" + "\n".join(body) + f"\n{pad}}})"

    def call(self, n, ind: int) -> str:
        head = self.unwrap_expr(n.children[0])
        args = [self.expr(a, ind) for a in n.children[1:]]
        name = str(head) if isinstance(head, Token) else None
        if name in LOWER:
            tpl = LOWER[name]
            return tpl.replace("{*}", ", ".join(args)) if "{*}" in tpl else tpl.format(*args)
        if name:
            # An enum case reaches this path too: its constructor is emitted as an
            # ordinary top-level function, so there is nothing to special-case.
            return f"{self.gname(name)}({', '.join(args)})"
        return f"({self.expr(head, ind)})({', '.join(args)})"

    # ---------- match ----------

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
            cond, binds = self.arm(ak[0], s)
            if cond is None:
                lines += [f"{pad}{b}" for b in binds]
                lines += self.block(ak[1:], ind + 1)
                total = True
                break
            body_pad = "    " * (ind + 2)
            lines.append(f"{pad}if ({cond}) {{")
            lines += [f"{body_pad}{b}" for b in binds]
            lines += self.block(ak[1:], ind + 2)
            lines.append(f"{pad}}}")
        if not total:
            # TypeScript cannot see that the arms are exhaustive, and a closure
            # that falls off the end infers `| undefined` into the return type.
            lines.append(f"{pad}return RT.nonExhaustive();")
        return self.iife(lines, ind)

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

    def arm(self, pat, s: str) -> tuple[str | None, list[str]]:
        """A test for this arm, or None when it matches unconditionally, plus the
        `const`s its sub-patterns bind."""
        head = self._head(pat)
        node = pat.children[0] if (isinstance(pat, Tree) and pat.data == "pattern"
                                   and len(pat.children) == 1
                                   and isinstance(pat.children[0], Tree)) else pat
        subs = [p for p in node.children if isinstance(p, Tree)] if isinstance(node, Tree) else []

        if head in ("ok", "err", "some"):
            conds, binds = self._test(subs[0], f"{s}.value", [f'{s}.tag === "{head}"'], [])
            return " && ".join(conds), binds
        if head == "none":
            return f'{s}.tag === "none"', []
        if head in self.enums:
            _, arity = self.enums[head]
            conds, binds = [f'{s}.tag === "{head}"'], []
            for i, sub in enumerate(subs[:arity]):
                conds, binds = self._test(sub, f"{s}._{i}", conds, binds)
            return " && ".join(conds), binds
        if head == "list":
            conds = [f"{s}.length === {len(subs)}"]
            binds = []
            for i, sub in enumerate(subs):
                conds, binds = self._test(sub, f"{s}[{i}]", conds, binds)
            return " && ".join(conds), binds
        if head == "cons":
            conds, binds = self._test(subs[0], f"{s}[0]", [f"{s}.length > 0"], [])
            conds, binds = self._test(subs[1], f"{s}.slice(1)", conds, binds)
            return " && ".join(conds), binds
        if head == "pair":
            conds, binds = self._test(subs[0], f"{s}.first", [], [])
            conds, binds = self._test(subs[1], f"{s}.second", conds, binds)
            return (" && ".join(conds) or None), binds

        tk = self._leaf(pat)
        if tk is None or tk.type == "WILDCARD":
            return None, []
        if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
            return f"RT.eq({s}, {self.atom(tk)})", []
        return None, [f"const {mangle(str(tk))} = {s};"]

    def _test(self, sub, access: str, conds: list[str], binds: list[str]):
        """A sub-pattern either tests its slot or binds it. A test is appended
        after the tag test that precedes it, because `&&` narrows left to right
        and the slot does not exist until the tag has been checked."""
        tk = self._leaf(sub)
        if tk is None or tk.type == "WILDCARD":
            return conds, binds
        if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
            return conds + [f"RT.eq({access}, {self.atom(tk)})"], binds
        return conds, binds + [f"const {mangle(str(tk))} = {access};"]

    def atom(self, tok) -> str:
        s = str(tok)
        if tok.type == "UNIT":
            return "undefined"
        # An Int64 literal carries the `n` suffix: it is a bigint everywhere in
        # this backend, and `1` and `1n` are different values that never compare
        # equal.
        if tok.type == "INT":
            return f"{s}n"
        if tok.type in ("BOOL", "FLOAT", "STRING"):
            return s
        return self.gname(s)


if __name__ == "__main__":
    src = Path(sys.argv[1]).read_text()
    try:
        print(ToTypeScript().transpile_file(Path(sys.argv[1])))
    except (TargetMismatch, NotLowered, ModuleError) as exc:
        # A refusal is a result, not a crash: this is the path a module for
        # another ecosystem takes, and a stack trace would read as a defect.
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(2)
