#!/usr/bin/env python3
"""AgentScript -> Rust.

Lowering rules come from prelude/prelude.json, as for every backend. This file
owns only the special forms and the type mapping.

Ownership strategy for this first pass: values are passed and returned by value,
and cloned at each use site where a binding is read more than once. That is the
conservative choice recorded as pending in PCP l-880d — it is measurably wasteful
and it is correct, which is the right order to do them in.

A program's transitive imports are linked into this one output file, each as a
nested `pub mod` named after the module path that defines it. Per-module emission
would need a build driver, a package layout and a link step before a single
fixture could be gated; this keeps every gate driving one artifact.
"""
import argparse
import json
import re
import sys
from pathlib import Path

from lark import Tree, Token

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "grammar"))

from modules import closure, declared_path, imports  # noqa: E402
from _literals import string_literal  # noqa: E402
from parse import FORM_KW, parser  # noqa: E402

sys.path.insert(0, str(ROOT / "prelude"))

from vocab import resolve_type, unions  # noqa: E402

PRELUDE = json.loads((ROOT / "prelude" / "prelude.json").read_text())
LOWER = {b["name"]: b["rs"] for b in PRELUDE["builtins"]}

# Keyed by Core names only. A Nano alias is resolved before it gets here;
# a second spelling in this table is a second alias map, which is the defect.
PRIM = {"Bool": "bool", "Int32": "i32", "Int64": "i64",
        "Float64": "f64", "String": "String", "Unit": "()",
        "IoError": "rt::IoError"}

# f64 implements neither Eq nor Ord and rt::IoError implements none of the four
# order traits, so a declaration reachable from either cannot derive them: the
# derive fails at the declaration, not at a use site.
NO_TOTAL_ORDER = {"Float64", "IoError"}
# f64 *is* PartialOrd, so the two questions are not the same one and bundling
# them cost a Float64-bearing record every comparison it was entitled to:
# `list-sort` over it failed rustc's PartialOrd bound while the language
# specifies its order (section 3.2, NaN last). rt::sort takes PartialOrd, not
# Ord, precisely so that order is expressible.
NO_PARTIAL_ORDER = {"IoError"}


def mangle(n: str) -> str:
    if n.endswith("?"):
        n = "is-" + n[:-1]
    if n.endswith("!"):
        n = n[:-1] + "-mut"
    m = n.replace("-", "_")
    # `main` is not a keyword but it is the crate's entry symbol, and the host
    # entry this backend emits would collide with a user function of that name.
    return m + "_" if m in {"type", "match", "fn", "let", "loop", "move", "ref",
                            "impl", "main"} else m


def pascal(n: str) -> str:
    return "".join(p.capitalize() for p in n.replace("_", "-").split("-"))


def rust_mod(mod_path: str) -> str:
    """Derived from the module path that DEFINES a member, never from the alias
    reaching it: an alias is module-local, and keying on it would give one
    definition as many names as its importers invent."""
    return "_".join(mangle(seg) for seg in mod_path.split("/"))


class ToRust:
    def __init__(self):
        self.parser = parser()
        # Prelude unions are seeded here so a case of one lowers by exactly the
        # path a user `defenum` case takes.
        self.prelude_enums: dict[str, tuple[str, list[str], list[bool]]] = {
            case: ("rt::IoError", [], []) for cases in unions().values() for case in cases
        }   # case -> (enum path, field types, which of them are boxed)
        self.enums = dict(self.prelude_enums)
        self.cases: dict[str, tuple] = {}     # the current unit's own cases
        self.prefix = ""                      # emitted-path prefix of the current unit
        self.local: dict[str, str] = {}       # its functions and cases -> emitted paths
        self.types: dict[str, str] = {}       # its type names -> emitted paths
        self.alias_mod: dict[str, str] = {}   # its aliases -> module paths
        self.unit_enums: dict[str, dict] = {}
        self.unit_types: dict[str, dict] = {}
        self.unit_aliases: dict[str, dict] = {}
        # A cons arm may bind more than one head or tail, so these accumulate
        # rather than holding the last one written.
        self.cons_heads: list[str] = []
        self.cons_tails: list[str] = []
        self.box_binds: list[str] = []
        self.pat_binds: list[str] = []
        self.scope: list[set[str]] = []       # binder frames, innermost last
        self.field_box: dict[str, set[str]] = {}   # schema path -> boxed fields
        self.boxed_fields: set[str] = set()
        self.orderable: set[str] = set()
        self.comparable: set[str] = set()
        self.tmp = 0

    def fresh(self):
        self.tmp += 1
        return f"t{self.tmp}"

    @staticmethod
    def kids(n):
        return [k for k in n.children if not (isinstance(k, Token) and k.type in FORM_KW)]

    def push(self, names=()) -> None:
        """Every binding form opens a frame. A binder is emitted bare while a
        top-level name is emitted under its module path, so an identifier that
        exists as both reaches the wrong symbol unless scope is consulted."""
        self.scope.append(set(names))

    def pop(self) -> None:
        self.scope.pop()

    def bound(self, name) -> bool:
        return name is not None and any(name in frame for frame in self.scope)

    def resolve(self, name: str) -> str:
        return mangle(name) if self.bound(name) else self.local.get(name, mangle(name))

    @staticmethod
    def tok(n):
        return str(n) if isinstance(n, Token) else str(n.children[0])

    @staticmethod
    def type_params(n) -> list[str]:
        for k in n.children:
            if isinstance(k, Tree) and k.data == "type_params":
                return [str(t) for t in k.children]
        return []

    @staticmethod
    def type_names_in(n) -> set[str]:
        return {str(t) for t in n.scan_values(
            lambda t: isinstance(t, Token) and t.type == "TYPE_NAME")}

    @staticmethod
    def qual_type_names_in(n) -> set[str]:
        return {str(t) for t in n.scan_values(
            lambda t: isinstance(t, Token) and t.type == "QUALIFIED_TYPE")}

    @staticmethod
    def decl_name(n) -> str:
        k = [x for x in ToRust.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        return ToRust.tok(k[0])

    @staticmethod
    def member_types(n) -> list:
        """The field types of a defschema, or every case-parameter type of a defenum."""
        out = []
        for c in n.children:
            if isinstance(c, Tree) and c.data == "field":
                out.append(ToRust.kids(c)[1])
            elif isinstance(c, Tree) and c.data == "enum_case":
                out += [ToRust.kids(p)[1] for p in c.children
                        if isinstance(p, Tree) and p.data == "param"]
        return out

    # ---------- types ----------

    def tname(self, s: str) -> str:
        """A type name in the scope of the unit being emitted. A qualified one
        resolves through the module it names, so two aliases for one module land
        on one Rust path."""
        if "/" in s:
            alias, _, member = s.partition("/")
            target = self.alias_mod.get(alias, "")
            return self.unit_types.get(target, {}).get(member, member)
        s = resolve_type(s)
        return PRIM[s] if s in PRIM else self.types.get(s, s)

    def rtype(self, n) -> str:
        if isinstance(n, Tree) and n.data == "type":
            n = n.children[0] if len(n.children) == 1 else n
        if isinstance(n, Token):
            return self.tname(str(n))
        head = resolve_type(self.tok(n.children[0]))
        args = [self.rtype(a) for a in n.children[1:]]
        return {
            "List": f"Vec<{args[0]}>" if args else "Vec<()>",
            "Option": f"Option<{args[0]}>" if args else "Option<()>",
            "Result": f"Result<{args[0]}, {args[1]}>" if len(args) > 1 else "Result<(),()>",
            "Pair": f"({args[0]}, {args[1]})" if len(args) > 1 else "((),())",
            "Map": f"std::collections::BTreeMap<{args[0]}, {args[1]}>" if len(args) > 1 else "()",
        }.get(head, f"{self.tname(head)}<{', '.join(args)}>" if args else self.tname(head))

    def boxed(self, node, decl: str) -> str:
        """A member whose type mentions the declaration it belongs to has no
        statically known size. Fully qualified because a user schema may be
        named Box, and one in the corpus is."""
        ty = self.rtype(node)
        return f"::std::boxed::Box<{ty}>" if decl in self.type_names_in(node) else ty

    @staticmethod
    def generics(params: list[str], bound: str = "") -> str:
        if not params:
            return ""
        suffix = f": {bound}" if bound else ""
        return "<" + ", ".join(p + suffix for p in params) + ">"

    def derives(self, name: str) -> str:
        extra = ", PartialOrd" if name in self.comparable else ""
        extra += ", Eq, Ord" if name in self.orderable else ""
        return f"#[derive(Debug, Clone, PartialEq{extra})]"

    def plan_derives(self, units) -> None:
        """Which declarations may derive a partial order, and which a total one,
        computed over every linked module before anything is emitted: a case
        parameter may name a type the emitter has not reached yet — in this
        module or another — and the answer must not depend on the order it
        reaches them."""
        mentions: dict[str, set[str]] = {}
        for mod_path, tree, prefix, _ in units:
            for top in tree.children:
                n = top.children[0]
                if n.data not in ("defenum", "defschema"):
                    continue
                seen: set[str] = set()
                for t in self.member_types(n):
                    for s in self.type_names_in(t):
                        s = resolve_type(s)
                        seen.add(self.unit_types[mod_path].get(s, s))
                    for s in self.qual_type_names_in(t):
                        alias, _, member = s.partition("/")
                        target = self.unit_aliases[mod_path].get(alias, "")
                        seen.add(self.unit_types.get(target, {}).get(member, member))
                mentions[prefix + self.decl_name(n)] = seen
        def reachable(seeds: set[str]) -> set[str]:
            tainted = {n for n, seen in mentions.items() if seen & seeds}
            while True:
                grown = {n for n, seen in mentions.items()
                         if n not in tainted and seen & tainted}
                if not grown:
                    break
                tainted |= grown
            return tainted

        self.orderable = set(mentions) - reachable(NO_TOTAL_ORDER)
        self.comparable = set(mentions) - reachable(NO_PARTIAL_ORDER)

    # ---------- entry ----------

    def transpile(self, src: str, *, path: Path | None = None, roots=()) -> str:
        """`path` and `roots` are what an import is resolved against. A call with
        neither keeps working and resolves no imports, which is what the
        measurement harness needs: it transpiles generated text that has no file."""
        tree = self.parser.parse(src)
        units = self.link(tree, path, roots)
        self.plan_derives(units)
        out = ["#![allow(dead_code, unused_variables, unused_mut, unused_parens)]",
               "mod rt;", ""]   # inner attributes must precede any item
        for mod_path, unit, prefix, modname in units:
            self.enter(mod_path, unit, prefix)
            body = self.unit(unit)
            if modname is None:
                out += body
            else:
                out += [f"pub mod {modname} {{",
                        "    #![allow(dead_code, unused_variables, unused_mut, unused_parens)]",
                        "    #[allow(unused_imports)]",
                        "    use super::rt;", ""]
                out += [("    " + line if line else line) for line in body]
                out += ["}", ""]
        out += self.host_entry([t.children[0] for t in tree.children])
        return "\n".join(out) + "\n"

    def link(self, tree, path, roots) -> list[tuple[str, Tree, str, str | None]]:
        search = [*([Path(path).parent] if path is not None else []),
                  *(Path(r) for r in roots)]
        deps = closure(tree, search) if search else []
        units: list[tuple[str, Tree, str, str | None]] = []
        claimed: dict[str, str] = {}
        for mod_path, sub in deps:
            name = rust_mod(mod_path)
            if claimed.setdefault(name, mod_path) != mod_path:
                raise ValueError(f"module paths {claimed[name]} and {mod_path} mangle alike")
            units.append((mod_path, sub, f"crate::{name}::", name))
        units.append((declared_path(tree) or "", tree, "", None))
        for mod_path, sub, prefix, _ in units:
            self.unit_aliases[mod_path] = imports(sub)
            self.unit_types[mod_path] = {
                self.decl_name(t.children[0]): prefix + self.decl_name(t.children[0])
                for t in sub.children if t.children[0].data in ("defenum", "defschema")}
            self.unit_enums.setdefault(mod_path, {})
        return units

    def enter(self, mod_path: str, tree, prefix: str) -> None:
        self.prefix = prefix
        self.alias_mod = self.unit_aliases[mod_path]
        self.types = self.unit_types[mod_path]
        self.cases = self.unit_enums[mod_path]
        self.enums = dict(self.prelude_enums)
        self.enums.update(self.cases)
        self.local = self.unit_names(tree, prefix)
        self.scope = []

    def unit_names(self, tree, prefix: str) -> dict[str, str]:
        """Every function a unit defines, mapped to the path it is emitted under.
        The root unit's prefix is empty, so a single-module program is lowered
        exactly as it was before imports existed."""
        return {self.fun_name(t.children[0]): prefix + mangle(self.fun_name(t.children[0]))
                for t in tree.children if t.children[0].data == "defun"}

    def fun_name(self, n) -> str:
        k = [x for x in self.kids(n)
             if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt", "tag_node"))]
        return self.tok(k[0])

    def qual(self, text: str) -> str:
        alias, _, member = text.partition("/")
        target = self.alias_mod.get(alias, "")
        return f"crate::{rust_mod(target)}::{mangle(member)}" if target else mangle(member)

    def qualified_case(self, text: str):
        alias, _, member = text.partition("/")
        return self.unit_enums.get(self.alias_mod.get(alias, ""), {}).get(member)

    def unit(self, tree) -> list[str]:
        tops = [t.children[0] for t in tree.children]
        out: list[str] = []
        for n in tops:
            if n.data == "defenum":
                out += self.defenum(n)
        for n in tops:
            if n.data == "defschema":
                out += self.defschema(n)
        for n in tops:
            if n.data == "defun":
                out += self.defun(n)
        return out

    def host_entry(self, tops) -> list[str]:
        """Only a module declaring `main` is a program; the drivers synthesise
        their own entry for the rest, and two would collide."""
        for n in tops:
            if n.data == "defun" and self.tok(
                    [x for x in self.kids(n)
                     if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt", "tag_node"))][0]) == "main":
                return ["", "fn main() {",
                        "    let args: Vec<String> = std::env::args().skip(1).collect();",
                        "    std::process::exit(rt::main_exit(main_(args)));", "}"]
        return []

    def defschema(self, n) -> list[str]:
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt", "tag_node"))]
        name = self.tok(k[0])
        fields = [f for f in n.children if isinstance(f, Tree) and f.data == "field"]
        gen = self.generics(self.type_params(n))
        lines = [self.derives(self.prefix + name), f"pub struct {name}{gen} {{"]
        boxes: set[str] = set()
        for f in fields:
            fk = self.kids(f)
            fname = mangle(self.tok(fk[0]))
            ty = self.boxed(fk[1], name)
            if name in self.type_names_in(fk[1]):
                boxes.add(fname)
            lines.append(f"    pub {fname}: {ty},")
        self.field_box[self.prefix + name] = boxes
        self.boxed_fields |= boxes
        return lines + ["}", ""]

    def defenum(self, n) -> list[str]:
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt", "tag_node"))]
        name = self.tok(k[0])
        gen = self.generics(self.type_params(n))
        path = self.prefix + name
        lines = [self.derives(path), f"pub enum {name}{gen} {{"]
        for c in n.children:
            if not (isinstance(c, Tree) and c.data == "enum_case"):
                continue
            ck = self.kids(c)
            case = self.tok(ck[0])
            ps = [self.kids(p)[1] for p in c.children
                  if isinstance(p, Tree) and p.data == "param"]
            tys = [self.boxed(t, name) for t in ps]
            box = [name in self.type_names_in(t) for t in ps]
            self.enums[case] = self.cases[case] = (path, tys, box)
            lines.append(f"    {pascal(case)}" + (f"({', '.join(tys)})," if tys else ","))
        return lines + ["}", ""]

    def defun(self, n) -> list[str]:
        k = [x for x in self.kids(n)
             if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt", "tag_node"))]
        name = mangle(self.tok(k[0]))
        ps = [p for p in k[1].children if isinstance(p, Tree) and p.data == "param"]
        args = ", ".join(f"{mangle(self.tok(self.kids(p)[0]))}: {self.rtype(self.kids(p)[1])}"
                         for p in ps)
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret = self.rtype(k[ti])
        stmts: list[str] = []
        self.push(self.tok(self.kids(p)[0]) for p in ps)
        last = self.sequence(k[ti + 1:], stmts, 1)
        self.pop()
        # Clone, because the ownership strategy above clones at every use site and
        # a bare type parameter offers no method to clone with.
        gen = self.generics(self.type_params(n), bound="Clone")
        return [f"pub fn {name}{gen}({args}) -> {ret} {{"] + stmts + [f"    {last}", "}", ""]

    # ---------- expressions ----------

    def sequence(self, body, stmts, ind) -> str:
        """A body's value is its last expression; every earlier one is evaluated
        for its effect. The discarded value still has to be emitted as a
        statement, or a lowering that is a pure expression — `(println(x))?` —
        vanishes from the output entirely."""
        pad = "    " * ind
        last = None
        body = [b for b in body if not (isinstance(b, Tree) and b.data == "tag_node")]
        for i, b in enumerate(body):
            last = self.expr(b, stmts, ind)
            if i < len(body) - 1:
                stmts.append(f"{pad}{last};")
        return last

    def expr(self, n, stmts, ind) -> str:
        pad = "    " * ind
        if isinstance(n, Token):
            return self.atom(n)
        if n.data == "tag_node":
            return '""'
        if n.data in ("expr", "literal"):
            return self.expr(n.children[0], stmts, ind)

        if n.data == "let_form":
            self.push()
            for b in self.kids(n):
                if isinstance(b, Tree) and b.data == "binding":
                    bk = self.kids(b)
                    v = self.expr(bk[1], stmts, ind)
                    name = self.tok(bk[0])
                    stmts.append(f"{pad}let {mangle(name)} = {v};")
                    # after its own value: a binding's initialiser is outside it
                    self.scope[-1].add(name)
            value = self.sequence(
                [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "binding")],
                stmts, ind)
            self.pop()
            return value

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
                    v = self.sequence(ck[1:], inner, ind + 1)
                    parts.append(("if " if first else "} else if ") + f"{cv} {{")
                    parts += inner + [f"    {v}"]
                    first = False
                else:
                    v = self.sequence(self.kids(cl), inner, ind + 1)
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
            # An annotation is emitted where the source carries one: discarding a
            # declared type was the bug. Where it was elided, the closure goes out
            # bare and rustc infers it from the call it is passed to, which is the
            # same information the checker used to accept the elision.
            ps, names = [], []
            for p in k[0].children:
                if not (isinstance(p, Tree) and p.data == "fn_param"):
                    continue
                parts = self.kids(p)
                names.append(self.tok(parts[0]))
                name = mangle(names[-1])
                ps.append(f"{name}: {self.rtype(parts[1])}" if len(parts) > 1 else name)
            body = k[1:]
            if body and isinstance(body[0], Tree) and body[0].data == "type":
                body = body[1:]
            sub: list[str] = []
            self.push(names)
            v = self.sequence(body, sub, ind + 1)
            self.pop()
            if not sub:
                return f"|{', '.join(ps)}| {v}"
            body = "\n".join(sub + [f"{pad}    {v}"])
            return f"|{', '.join(ps)}| {{\n{body}\n{pad}}}"

        if n.data == "field_access":
            fld = self.tok(n.children[0])[2:]
            tgt = self.expr(n.children[1], stmts, ind)
            if fld in ("first", "second"):
                return f"{tgt}.{0 if fld == 'first' else 1}.clone()"
            # A field access carries no type here, so the field NAME is what
            # decides: a self-referential declaration boxes it, and the body
            # expects the value the source declared, not the box around it.
            if mangle(fld) in self.boxed_fields:
                return f"(*{tgt}.{mangle(fld)}).clone()"
            return f"{tgt}.{mangle(fld)}.clone()"

        if n.data == "ctor":
            name = self.tname(self.tok(n.children[0]))
            boxes = self.field_box.get(name, set())
            fs = []
            for a in n.children[1:]:
                if not (isinstance(a, Tree) and a.data == "ctor_arg"):
                    continue
                f = mangle(self.tok(a.children[0])[1:])
                v = self.expr(a.children[1], stmts, ind)
                fs.append(f"{f}: " + (f"::std::boxed::Box::new({v})" if f in boxes else v))
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
        found = None if self.bound(name) else (
            self.qualified_case(name) if name and "/" in name else self.enums.get(name))
        if found is not None:
            en, _, box = found
            case = name.partition("/")[2] or name
            args = [f"::std::boxed::Box::new({a})" if i < len(box) and box[i] else a
                    for i, a in enumerate(args)]
            return f"{en}::{pascal(case)}" + (f"({', '.join(args)})" if args else "")
        if name and "/" in name:
            return f"{self.qual(name)}({', '.join(args)})"
        if name:
            return f"{self.resolve(name)}({', '.join(args)})"
        return f"({self.expr(head, stmts, ind)})({', '.join(args)})"

    def match(self, n, stmts, ind) -> str:
        pad = "    " * ind
        mk = self.kids(n)
        subj = self.expr(mk[0], stmts, ind)
        # Same conservative ownership as `call`: destructuring a bare binding
        # moves out of it, and the arms of one match are not the only reader.
        if re.fullmatch(r"[a-z_][a-z0-9_]*", subj):
            subj += ".clone()"
        t = self.fresh()
        # Rust destructures a list only through a slice pattern, so a match
        # containing list arms must scrutinise a slice rather than the Vec.
        arms = [a for a in mk[1:] if isinstance(a, Tree) and a.data == "match_arm"]
        # Read back after the arm bodies are built, and a body may contain
        # another match that overwrites the shared slot: capture it locally.
        slice_match = any(self._is_list_pat(self.kids(a)[0]) for a in arms)
        scrut = f"{subj}.as_slice()" if slice_match else subj
        stmts.append(f"{pad}let {t} = match {scrut} {{")
        for arm in arms:
            ak = self.kids(arm)
            self.box_binds, self.pat_binds = [], []
            self.cons_heads, self.cons_tails = [], []
            pat = self.pattern(ak[0])
            heads, self.cons_heads = self.cons_heads, []
            tails, self.cons_tails = self.cons_tails, []
            boxes, self.box_binds = self.box_binds, []
            names, self.pat_binds = self.pat_binds, []
            inner: list[str] = []
            self.push(names)
            v = self.sequence(ak[1:], inner, ind + 2)
            self.pop()
            pre = [f"{pad}        let {b} = *{b};" for b in boxes]
            # A slice pattern binds into the scrutinee, so both ends of a cons
            # arrive as references while the body was written against values.
            pre += [f"{pad}        let {b} = {b}.clone();" for b in heads]
            pre += [f"{pad}        let {b} = {b}.to_vec();" for b in tails]
            if inner or pre:
                body = "\n".join(pre + inner + [f"{pad}        {v}"])
                stmts.append(f"{pad}    {pat} => {{\n{body}\n{pad}    }},")
            else:
                stmts.append(f"{pad}    {pat} => {v},")
        if slice_match:
            stmts.append(f"{pad}    _ => unreachable!(),")
        stmts.append(f"{pad}}};")
        return t

    @staticmethod
    def _unwrap(pat):
        """A parenthesised sub-pattern arrives inside one extra `pattern` node."""
        if isinstance(pat, Tree) and pat.data == "pattern" and len(pat.children) == 1 \
                and isinstance(pat.children[0], Tree):
            return pat.children[0]
        return pat

    @staticmethod
    def _pat_head(pat):
        toks = pat.children if isinstance(pat, Tree) else []
        return str(toks[0]) if toks and isinstance(toks[0], Token) else None

    def _is_list_pat(self, pat) -> bool:
        return self._pat_head(self._unwrap(pat)) in ("list", "cons")

    def pattern(self, pat) -> str:
        pat = self._unwrap(pat)
        toks = pat.children if isinstance(pat, Tree) else []
        head = self._pat_head(pat)

        def binder(name: str) -> str:
            self.pat_binds.append(name)
            return mangle(name)

        def sub(p):
            # A constructor sub-pattern recurses. Treating it as a binder is not
            # a lost check but a wrong one: `Err(not_found)` compiles and matches
            # every error.
            if isinstance(p, Tree) and p.data == "enum_pattern":
                return self.pattern(p)
            if isinstance(p, Tree) and len(p.children) == 1 \
                    and isinstance(p.children[0], Tree):
                return self.pattern(p.children[0])
            if isinstance(p, Tree) and p.children and isinstance(p.children[0], Token):
                tk = p.children[0]
                if tk.type == "WILDCARD":
                    return "_"
                if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
                    return self.atom(tk)
                return binder(str(tk))
            return "_"

        if head in ("ok", "err", "some"):
            return {"ok": "Ok", "err": "Err", "some": "Some"}[head] + f"({sub(toks[1])})"
        if head == "none":
            return "None"
        if head == "list":
            return "[]"
        if head == "cons":
            # A cons spine is one slice pattern, not a pattern nested in a
            # pattern: Rust binds the rest of a slice once, and `x @ ..` accepts
            # only a binding on its left.
            heads, node = [], pat
            while self._pat_head(node) == "cons":
                h = sub(node.children[1])
                if h != "_" and re.fullmatch(r"[a-z_][a-z0-9_]*", h):
                    self.cons_heads.append(h)
                heads.append(h)
                node = self._unwrap(node.children[2])
            if self._pat_head(node) == "list":
                return f"[{', '.join(heads)}]"
            rest = sub(node)
            if rest == "_" or not re.fullmatch(r"[a-z_][a-z0-9_]*", rest):
                return f"[{', '.join(heads)}, ..]"
            # The tail is bound as a slice; the body expects an owned list, so it
            # is materialised at the top of the arm (see match()).
            self.cons_tails.append(rest)
            return f"[{', '.join(heads)}, {rest} @ ..]"
        if head == "pair":
            return f"({sub(toks[1])}, {sub(toks[2])})"
        found = self.qualified_case(head) if head and "/" in head else self.enums.get(head)
        if found is not None:
            en, tys, box = found
            head = head.partition("/")[2] or head
            parts = []
            for i, p in enumerate(p for p in toks[1:] if isinstance(p, Tree)):
                s = sub(p)
                if i < len(box) and box[i] and re.fullmatch(r"[a-z_][a-z0-9_]*", s):
                    self.box_binds.append(s)
                parts.append(s)
            return f"{en}::{pascal(head)}" + (f"({', '.join(parts)})" if tys else "")
        if isinstance(pat, Tree) and pat.children and isinstance(pat.children[0], Token):
            tk = pat.children[0]
            if tk.type == "WILDCARD":
                return "_"
            if tk.type in ("INT", "FLOAT", "STRING", "BOOL"):
                return self.atom(tk)
            return binder(str(tk))
        return "_"

    def atom(self, tok) -> str:
        s = str(tok)
        if tok.type == "BOOL":
            return "true" if s == "true" else "false"
        if tok.type == "STRING":
            return f"{string_literal(s)}.to_string()"
        if tok.type in ("INT", "FLOAT"):
            # Rust's `-1` is a unary operation, not a primary, and a method
            # binds tighter than the sign: any template that suffixes onto its
            # argument reads -(1.to_string()) without these. The header already
            # allows unused_parens.
            return f"({s})" if s.startswith("-") else s
        if tok.type == "UNIT":
            return "()"
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
    sys.stdout.write(ToRust().transpile(source.read_text(), path=source,
                                        roots=[Path(r) for r in args.root]))
