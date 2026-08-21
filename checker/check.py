#!/usr/bin/env python3
"""Semantic checker: the rules of AGENT_SPEC_CORE.md §9 that no grammar can hold.

Two independent grammars agree on shape and neither checks any of this. Located
evidence puts the great majority of failures in LLM-generated code at the type
level rather than the syntactic one (PCP `l-78ae`, `RESEARCH_REPORT.md` §5), so
this is where the leverage is, not in the parsers.

**Scope, stated so a clean report is not over-read.** Fourteen of §9's fifteen
rules are decided here; the fifteenth is delimiter balance, which the grammars
own. Rules 3 and 6 — the type rules — are checked by `typecheck.py` and **fail
open**: a construct it cannot type is silent rather than reported, because a
checker that fires on the programs the handbook teaches is worse than no checker.
Silence is not proof of well-typedness. `--rules` prints the whole split.

Diagnostics use one shape across every subcommand the toolchain will grow:
`{file, line, col, rule, message}`. `--json` emits it verbatim so an agent reads
one contract instead of parsing prose.

Exit code is the number of diagnostics.
"""
import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from lark import Lark, Token, Tree
from lark.exceptions import LarkError

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "backend"))
import modules  # noqa: E402  — the loader lives with the backends
import typecheck  # noqa: E402
PRELUDE = json.loads((ROOT / "prelude" / "prelude.json").read_text())

BUILTINS = {b["name"]: b for b in PRELUDE["builtins"]}
EFFECTFUL = {n: b["effects"][0] for n, b in BUILTINS.items() if b.get("effects")}
TARGETS = PRELUDE["targets"]
SPECIAL = {n for group in PRELUDE["special_forms"].values() for n in group}
PRIM_TYPES = set(PRELUDE["types"]["primitive"]) | set(PRELUDE["types"]["constructed"]) \
    | set(PRELUDE["types"]["aliases"]) | set(PRELUDE["types"]["records"])
RESERVED_PREFIX = "as-"

# Rules this file decides, and rules it deliberately does not. Printed by
# --rules so the untested surface stays visible instead of looking covered.
CHECKED = {
    2: "name resolution (module-local, plus the alias half of qualified names)",
    4: "match exhaustiveness over closed unions, Option and Result",
    5: "try only inside a Result-returning defun or defentry",
    7: "no identifier begins with the reserved prefix",
    8: "module :doc, and :doc on every exported defun",
    9: "a qualified name's alias is bound, and names a member the other module exports",
    10: "every type variable is bound in its declaration's { }",
    11: "no import cycles",
    12: "the specific effects reached, declared transitively (console/stdin/fs/env/proc)",
    13: ":target on every defextern",
    14: "no defopaque value is inspected",
    15: "at most one defentry per program",
    3: "declared parameter and return types are consistent with the bodies",
    6: "no numeric operation mixes types",
}
UNCHECKED = {
    1: "delimiter balance — the grammars decide it; a parse failure is reported instead",
}


@dataclass
class Diag:
    file: str
    line: int
    col: int
    rule: int
    message: str

    def text(self) -> str:
        return f"{self.file}:{self.line}:{self.col}: [rule {self.rule}] {self.message}"

    def as_dict(self) -> dict:
        return {"file": self.file, "line": self.line, "col": self.col,
                "rule": self.rule, "message": self.message}


def parser() -> Lark:
    return Lark((ROOT / "grammar" / "as-lang.lark").read_text(),
                start="start", parser="earley", ambiguity="resolve",
                propagate_positions=True)


# ---------- tree helpers ----------

FORM_KW = {"DEFUN", "DEFSCHEMA", "DEFENUM", "DEFENTRY", "DEFEXTERN", "DEFOPAQUE",
           "MODULE", "IF", "COND", "MATCH", "TRY", "LET", "FN", "ARROW", "ELSE_KW",
           "CASE_KW", "FIELD_KW", "DOC_KW", "EXPORT_KW", "IMPORT_KW", "EXTERN_KW",
           "AS_KW", "DEFAULT_KW", "JSON_KW", "EFFECTS_KW", "TARGET_KW", "SYMBOL_KW",
           "OK", "ERR", "SOME", "NONE", "LIST", "CONS", "PAIR"}


def kids(node) -> list:
    return [k for k in node.children
            if not (isinstance(k, Token) and k.type in FORM_KW)]


def tok(n) -> str:
    return str(n) if isinstance(n, Token) else str(n.children[0])


def pos(n) -> tuple[int, int]:
    while isinstance(n, Tree):
        if not n.children:
            return (0, 0)
        n = n.children[0]
    return (getattr(n, "line", 0) or 0, getattr(n, "column", 0) or 0)


def walk(n):
    yield n
    if isinstance(n, Tree):
        for c in n.children:
            yield from walk(c)


def find(n, name: str):
    return [x for x in walk(n) if isinstance(x, Tree) and x.data == name]


def type_names(node) -> list:
    """Every TYPE_NAME token inside a type expression."""
    return [t for t in walk(node) if isinstance(t, Token) and t.type == "TYPE_NAME"]


# ---------- the module model ----------

@dataclass
class Module:
    path: str = ""
    doc: str | None = None
    exports: list = field(default_factory=list)
    imports: dict = field(default_factory=dict)     # alias -> module path
    externs: dict = field(default_factory=dict)     # alias -> host package
    schemas: dict = field(default_factory=dict)     # name -> [field names]
    enums: dict = field(default_factory=dict)       # name -> {case: arity}
    opaques: set = field(default_factory=set)
    funs: dict = field(default_factory=dict)        # name -> node
    externals: dict = field(default_factory=dict)   # qualified -> node
    entries: list = field(default_factory=list)


def model(tops) -> Module:
    m = Module()
    for n in tops:
        if n.data == "module_decl":
            k = kids(n)
            m.path = tok(k[0])
            for o in n.children:
                if not (isinstance(o, Tree) and o.data == "module_opt"):
                    continue
                head = str(o.children[0])
                if head == ":doc":
                    m.doc = str(o.children[1])
                elif head == ":export":
                    m.exports = [str(x) for x in o.children[1:]]
                elif head == ":import":
                    for sp in o.children:
                        if isinstance(sp, Tree) and sp.data == "import_spec":
                            sk = kids(sp)
                            m.imports[tok(sk[1])] = tok(sk[0])
                elif head == ":extern":
                    for sp in o.children:
                        if isinstance(sp, Tree) and sp.data == "extern_spec":
                            sk = kids(sp)
                            m.externs[tok(sk[2])] = tok(sk[1]).strip('"')
        elif n.data == "defschema":
            k = [x for x in kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
            m.schemas[tok(k[0])] = [tok(kids(f)[0]) for f in find(n, "field")]
        elif n.data == "defenum":
            k = [x for x in kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
            cases = {}
            for c in find(n, "enum_case"):
                cases[tok(kids(c)[0])] = len([p for p in c.children
                                              if isinstance(p, Tree) and p.data == "param"])
            m.enums[tok(k[0])] = cases
        elif n.data == "defopaque":
            m.opaques.add(tok(kids(n)[0]))
        elif n.data == "defun":
            k = [x for x in kids(n) if not (isinstance(x, Tree) and x.data in
                                            ("type_params", "decl_opt"))]
            m.funs[tok(k[0])] = n
        elif n.data == "defextern":
            m.externals[tok(kids(n)[0])] = n
        elif n.data == "defentry":
            m.entries.append(n)
    return m


def decl_opts(node) -> tuple[str | None, list]:
    """(:doc, :effects) off a defun or defentry."""
    doc, effects = None, []
    for o in node.children:
        if isinstance(o, Tree) and o.data == "decl_opt":
            head = str(o.children[0])
            if head == ":doc":
                doc = str(o.children[1])
            elif head == ":effects":
                effects = [str(x) for x in o.children[1:]]
    return doc, effects


def return_type(node):
    """The declared return type of a defun / defentry / defextern."""
    ks = [x for x in kids(node)
          if not (isinstance(x, Tree) and x.data in ("type_params", "decl_opt", "extern_opt"))]
    for i, x in enumerate(ks):
        if isinstance(x, Tree) and x.data == "type":
            return x
    return None


def is_result(t) -> bool:
    if t is None:
        return False
    names = type_names(t)
    return bool(names) and str(names[0]) == "Result"


def bound_typevars(node) -> set:
    tp = [x for x in node.children if isinstance(x, Tree) and x.data == "type_params"]
    return {str(t) for x in tp for t in type_names(x)}


def body_of(node) -> list:
    """Everything after the declared return type."""
    ks = [x for x in kids(node)
          if not (isinstance(x, Tree) and x.data in ("type_params", "decl_opt"))]
    for i, x in enumerate(ks):
        if isinstance(x, Tree) and x.data == "type":
            return ks[i + 1:]
    return []


# ---------- rules ----------

class Checker:
    _surfaces: dict = {}

    def __init__(self, path: Path, tops, m: Module):
        self.path, self.tops, self.m = str(path), tops, m
        self.out: list[Diag] = []

    def add(self, node, rule: int, message: str) -> None:
        line, col = pos(node)
        self.out.append(Diag(self.path, line, col, rule, message))

    def run(self) -> list[Diag]:
        for name in ("reserved_prefix", "docs", "entries", "extern_targets",
                     "typevars", "aliases", "names", "try_sites", "foreign_results",
                     "exhaustive", "effects", "opaque_use", "typecheck"):
            getattr(self, name)()
        self.out.sort(key=lambda d: (d.line, d.col, d.rule))
        return self.out

    # rule 7
    def reserved_prefix(self) -> None:
        for n in walk_tops(self.tops):
            if isinstance(n, Token) and n.type in ("IDENT", "QUALIFIED") \
                    and str(n).startswith(RESERVED_PREFIX):
                self.add(n, 7, f"`{n}` uses the reserved `{RESERVED_PREFIX}` prefix, "
                               f"which belongs to the compiler")

    # rule 8
    def docs(self) -> None:
        if self.m.path and self.m.doc is None:
            self.add(self.tops[0], 8, "the module header has no :doc")
        for name in self.m.exports:
            node = self.m.funs.get(name)
            if node is None:
                continue
            doc, _ = decl_opts(node)
            if doc is None:
                self.add(node, 8, f"`{name}` is exported but has no :doc")

    # rule 15
    def entries(self) -> None:
        for extra in self.m.entries[1:]:
            self.add(extra, 15, "a second defentry; a program has at most one entry point")

    # rule 13
    def extern_targets(self) -> None:
        for name, node in self.m.externals.items():
            targets = [o for o in node.children
                       if isinstance(o, Tree) and o.data == "extern_opt"
                       and str(o.children[0]) == ":target"]
            if not targets:
                self.add(node, 13, f"`{name}` has no :target, so it names no ecosystem")

    # rule 10
    def typevars(self) -> None:
        known = PRIM_TYPES | set(self.m.schemas) | set(self.m.enums) | self.m.opaques
        for node in list(self.m.funs.values()) + list(self.m.externals.values()) + self.m.entries:
            bound = bound_typevars(node)
            for t in signature_types(node):
                name = str(t)
                if name not in known and name not in bound:
                    self.add(t, 10, f"type `{name}` is neither declared nor bound in a "
                                    f"{{ }} binder on this declaration")
        for kind, table in (("defschema", self.m.schemas), ("defenum", self.m.enums)):
            for decl in self.tops:
                if decl.data != kind:
                    continue
                bound = bound_typevars(decl)
                for t in type_names(decl):
                    name = str(t)
                    if name == declared_type_name(decl) or name in known or name in bound:
                        continue
                    self.add(t, 10, f"type `{name}` is neither declared nor bound in a "
                                    f"{{ }} binder on this declaration")

    # rule 9 (the half that does not need the other module on disk)
    def aliases(self) -> None:
        """Both halves of rule 9.

        The second — that the member is exported by the module the alias names —
        needed a loader that could find the other module on disk, which did not
        exist until cross-module linking landed. It is the half that catches a
        call into a private helper.
        """
        known = set(self.m.imports) | set(self.m.externs)
        for n in walk_tops(self.tops):
            if not (isinstance(n, Token) and n.type == "QUALIFIED"):
                continue
            alias, member = str(n).split("/", 1)
            if alias not in known:
                self.add(n, 9, f"`{n}` uses alias `{alias}`, which no :import "
                               f"or :extern binds")
                continue
            if alias in self.m.externs:
                continue                  # a foreign member; §11's :target owns it
            surface = self.exported_by(self.m.imports[alias])
            if surface is None:
                continue                  # unresolvable here; the loader reports it
            defined, exported = surface
            if member not in defined:
                self.add(n, 9, f"`{n}` names `{member}`, which module "
                               f"`{self.m.imports[alias]}` does not define")
            elif member not in exported:
                self.add(n, 9, f"`{n}` names `{member}`, which module "
                               f"`{self.m.imports[alias]}` defines but does not export")

    def exported_by(self, module_path: str):
        """(defined names, exported names) of another module, or None."""
        cache = Checker._surfaces
        if module_path in cache:
            return cache[module_path]
        table = modules.index(modules.default_roots(Path(self.path)))
        file = table.get(module_path)
        if file is None:
            cache[module_path] = None
            return None
        tops = [t.children[0] for t in parser().parse(file.read_text()).children]
        _, exports, _ = modules._header(tops)
        cache[module_path] = (set(modules.top_level_names(tops)), exports)
        return cache[module_path]

    # rule 2
    def names(self) -> None:
        known_types = PRIM_TYPES | set(self.m.schemas) | set(self.m.enums) | self.m.opaques
        enum_cases = {c for cases in self.m.enums.values() for c in cases}
        top = (set(BUILTINS) | SPECIAL | set(self.m.funs) | enum_cases
               | set(self.m.externals) | known_types)
        for node in list(self.m.funs.values()) + self.m.entries:
            self.check_scope(node, top | params_of(node))

    def check_scope(self, node, bound: set) -> None:
        for expr in body_of(node):
            self.resolve(expr, bound)

    def resolve(self, n, bound: set) -> None:
        if isinstance(n, Token):
            if n.type == "IDENT" and str(n) not in bound:
                self.add(n, 2, f"`{n}` is not defined: not a builtin, not declared here, "
                               f"and not bound by a parameter or let")
            return
        if n.data == "let_form":
            inner = set(bound)
            for b in n.children:
                if isinstance(b, Tree) and b.data == "binding":
                    bk = kids(b)
                    self.resolve(bk[1], inner)
                    inner.add(tok(bk[0]))
            for x in kids(n):
                if not (isinstance(x, Tree) and x.data == "binding"):
                    self.resolve(x, inner)
            return
        if n.data == "fn_form":
            self.check_scope_fn(n, bound | params_of(n))
            return
        if n.data == "match_form":
            mk = kids(n)
            self.resolve(mk[0], bound)
            for arm in mk[1:]:
                if isinstance(arm, Tree) and arm.data == "match_arm":
                    ak = kids(arm)
                    inner = bound | pattern_binds(ak[0])
                    for b in ak[1:]:
                        self.resolve(b, inner)
            return
        if n.data == "field_access":
            self.resolve(n.children[1], bound)
            return
        if n.data == "ctor":
            for a in n.children[1:]:
                if isinstance(a, Tree) and a.data == "ctor_arg":
                    self.resolve(a.children[1], bound)
            return
        for c in n.children:
            if isinstance(c, Token) and c.type in ("QUALIFIED", "OPERATOR", "TYPE_NAME"):
                continue                      # rule 9 and rule 10 own these
            if isinstance(c, Tree) and c.data == "type":
                continue
            self.resolve(c, bound)

    def check_scope_fn(self, n, bound: set) -> None:
        ks = [x for x in kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        for i, x in enumerate(ks):
            if isinstance(x, Tree) and x.data == "type":
                for b in ks[i + 1:]:
                    self.resolve(b, bound)
                return

    # rule 5
    def try_sites(self) -> None:
        for node in list(self.m.funs.values()) + self.m.entries:
            if is_result(return_type(node)):
                continue
            name = tok(kids(node)[0]) if node.data == "defun" else "the entry point"
            for t in find(node, "try_form"):
                self.add(t, 5, f"`try` inside `{name}`, which does not return a Result, "
                               f"so there is nowhere for the failure to go")

    # rules 3 and 6
    def typecheck(self) -> None:
        """The type layer. Anything it cannot type is silent, never an error."""
        surface = typecheck.surface_of(self.tops)
        imported = {}
        for alias, path in self.m.imports.items():
            table = modules.index(modules.default_roots(Path(self.path)))
            f = table.get(path)
            if f is None:
                continue
            tops = [t.children[0] for t in parser().parse(f.read_text()).children]
            imported[alias] = typecheck.surface_of(tops)
        w = typecheck.Walk(surface, imported, self.m.path or "m")
        for n in self.tops:
            if isinstance(n, Tree) and n.data in ("defun", "defentry"):
                w.declaration(n)
        for f in w.out:
            self.add(f.node, f.rule, f.message)

    # rule 5, over §11
    def foreign_results(self) -> None:
        """A foreign call yields `(Result T String)`, never a bare `T`.

        Decided structurally rather than by inference: a foreign call passed
        straight to another call is being used as its success type, because
        nothing has eliminated the Result yet. `try`, a `match` subject and a
        `let` binding all leave it intact, so none of them trips this.
        """
        if not self.m.externals:
            return
        for c in [x for n in self.tops for x in find(n, "call")]:
            for a in c.children[1:]:
                inner = a
                while isinstance(inner, Tree) and inner.data in ("expr", "literal") \
                        and len(inner.children) == 1:
                    inner = inner.children[0]
                if not (isinstance(inner, Tree) and inner.data == "call"):
                    continue
                head = inner.children[0]
                while isinstance(head, Tree) and head.data == "expr" \
                        and len(head.children) == 1:
                    head = head.children[0]
                if isinstance(head, Token) and str(head) in self.m.externals:
                    self.add(inner, 5, f"`{head}` yields (Result _ String), but its value is "
                                       f"passed straight on; eliminate it with `try` or `match`")

    # rule 4
    def exhaustive(self) -> None:
        for mt in [x for n in self.tops for x in find(n, "match_form")]:
            arms = [a for a in kids(mt)[1:] if isinstance(a, Tree) and a.data == "match_arm"]
            heads, catch_all = [], False
            for a in arms:
                h = pattern_head(kids(a)[0])
                if h is None:
                    catch_all = True
                else:
                    heads.append(h)
            if catch_all or not heads:
                continue
            for owner, cases in self.m.enums.items():
                if heads[0] in cases:
                    missing = [c for c in cases if c not in heads]
                    if missing:
                        self.add(mt, 4, f"match over `{owner}` does not cover "
                                        f"{', '.join('`' + c + '`' for c in missing)}")
                    break
            else:
                for label, need in (("Option", {"some", "none"}), ("Result", {"ok", "err"})):
                    if heads[0] in need:
                        missing = sorted(need - set(heads))
                        if missing:
                            self.add(mt, 4, f"match over `{label}` does not cover "
                                            f"{', '.join('`' + c + '`' for c in missing)}")
                        break

    # rule 12
    def effects(self) -> None:
        """Effects are transitive, which is the whole point of declaring them.

        A function that only calls an effectful function is effectful too; a rule
        that stopped at direct calls would be satisfied by one wrapper.
        """
        direct: dict[str, set] = {}
        calls: dict[str, set] = {}
        for name, node in self.m.funs.items():
            direct[name], calls[name] = self.reached(node)
        for i, node in enumerate(self.m.entries):
            direct[f"\0entry{i}"], calls[f"\0entry{i}"] = self.reached(node)

        # Least fixed point over the module-local call graph. The set propagated
        # is the set of effect NAMES, not a boolean: a caller inherits exactly
        # what its callees reach, which is what makes a finer vocabulary useful.
        reach = {n: set(e) for n, e in direct.items()}
        changed = True
        while changed:
            changed = False
            for n, callees in calls.items():
                grown = reach[n] | set().union(*(reach[c] for c in callees if c in reach)) \
                    if callees else reach[n]
                if grown != reach[n]:
                    reach[n] = grown
                    changed = True

        # An effect name the vocabulary does not declare is a typo that would
        # otherwise satisfy the rule by naming nothing.
        legal = set(PRELUDE["effects"])
        for name, node in list(self.m.funs.items()) + \
                [(f"\0entry{i}", n) for i, n in enumerate(self.m.entries)]:
            _, declared = decl_opts(node)
            for e in declared:
                if e not in legal:
                    label = name if not name.startswith("\0") else "the entry point"
                    self.add(node, 12, f"`{label}` declares effect `{e}`, which is not one of "
                                       f"{', '.join(sorted(legal))}")

        for name in sorted(reach):
            if not reach[name]:
                continue
            node = (self.m.funs[name] if not name.startswith("\0")
                    else self.m.entries[int(name[6:])])
            _, declared = decl_opts(node)
            missing = sorted(reach[name] - set(declared))
            if not missing:
                continue
            label = name if not name.startswith("\0") else "the entry point"
            self.add(node, 12, f"`{label}` reaches "
                               f"{', '.join('`' + e + '`' for e in missing)} but declares "
                               f"{('only ' + ', '.join('`' + d + '`' for d in declared)) if declared else 'no effects'}")
        self.reach = reach

    def reached(self, node) -> tuple[set, set]:
        """(effects reached directly, module-local functions called)."""
        eff, local = set(), set()
        for c in find(node, "call"):
            head = c.children[0]
            while isinstance(head, Tree) and head.data == "expr" and len(head.children) == 1:
                head = head.children[0]
            if not isinstance(head, Token):
                continue
            name = str(head)
            if name in EFFECTFUL:
                eff.add(EFFECTFUL[name])
            elif name in self.m.funs:
                local.add(name)
            elif name in self.m.externals:
                # A foreign call is effectful by construction; which capability it
                # needs is the host's business, so it is attributed to the
                # ecosystem gate (:target) rather than to one of these names.
                pass
        # `(args)` and friends parse as a bare ident when they take no arguments.
        for t in walk(node):
            if isinstance(t, Token) and t.type == "IDENT" and str(t) in EFFECTFUL:
                eff.add(EFFECTFUL[str(t)])
        return eff, local

    # rule 14
    def opaque_use(self) -> None:
        """An opaque value crosses the boundary; it is never taken apart.

        Tracked by declared parameter type rather than inferred: that is enough
        for the shapes a host value actually arrives in, and it needs no type
        system.
        """
        if not self.m.opaques:
            return
        for node in list(self.m.funs.values()) + self.m.entries:
            opaque_params = {name for name, ty in typed_params(node)
                             if ty in self.m.opaques}
            if not opaque_params:
                continue
            for fa in find(node, "field_access"):
                target = unwrap(fa.children[1])
                if isinstance(target, Token) and str(target) in opaque_params:
                    self.add(fa, 14, f"`{tok(fa.children[0])}` reads a field off opaque "
                                     f"`{target}`, whose shape this language does not model")
            for c in find(node, "call"):
                head = c.children[0]
                while isinstance(head, Tree) and head.data == "expr" and len(head.children) == 1:
                    head = head.children[0]
                if not (isinstance(head, Token) and head.type == "OPERATOR"
                        and str(head) in ("=", "!=", "<", "<=", ">", ">=")):
                    continue
                for a in c.children[1:]:
                    t = unwrap(a)
                    if isinstance(t, Token) and str(t) in opaque_params:
                        self.add(c, 14, f"`{head}` compares opaque `{t}`, which has no "
                                        f"equality this language can know about")
                        break


# ---------- helpers the rules lean on ----------

def unwrap(n):
    """Strip the single-child `expr`/`literal` wrappers the grammar inserts."""
    while isinstance(n, Tree) and n.data in ("expr", "literal") and len(n.children) == 1:
        n = n.children[0]
    return n


def walk_tops(tops):
    for t in tops:
        yield from walk(t)


def declared_type_name(decl) -> str:
    k = [x for x in kids(decl) if not (isinstance(x, Tree) and x.data == "type_params")]
    return tok(k[0])


def signature_types(node) -> list:
    """Every TYPE_NAME in a declaration's parameters and return type."""
    out = []
    for p in find(node, "param"):
        out += type_names(kids(p)[1])
    rt = return_type(node)
    if rt is not None:
        out += type_names(rt)
    return out


def typed_params(node) -> list:
    out = []
    for p in find(node, "param"):
        pk = kids(p)
        names = type_names(pk[1])
        out.append((tok(pk[0]), str(names[0]) if names else ""))
    return out


def params_of(node) -> set:
    """Parameter names bound by this declaration, including nested `fn` params.

    Nested params are included because rule 2 walks a whole body at once; the
    finer scoping belongs to a type checker, and being generous here keeps this
    rule from reporting a name that is genuinely bound.
    """
    return {tok(kids(p)[0]) for p in find(node, "param")}


def pattern_binds(pat) -> set:
    out = set()
    for t in walk(pat):
        if isinstance(t, Token) and t.type == "IDENT":
            out.add(str(t))
    return out


def pattern_head(pat) -> str | None:
    """The constructor a pattern matches, or None for a catch-all."""
    node = pat
    while isinstance(node, Tree) and node.data == "pattern" and len(node.children) == 1 \
            and isinstance(node.children[0], Tree):
        node = node.children[0]
    if isinstance(node, Tree):
        head = node.children[0] if node.children else None
        if isinstance(head, Token) and head.type in ("IDENT", "OK", "ERR", "SOME",
                                                     "NONE", "LIST", "CONS", "PAIR"):
            return str(head)
        if isinstance(head, Token) and head.type == "WILDCARD":
            return None
        if len(node.children) == 1 and isinstance(node.children[0], Token):
            t = node.children[0]
            return None if t.type in ("WILDCARD", "IDENT") else str(t)
    if isinstance(node, Token):
        return None if node.type in ("WILDCARD", "IDENT") else str(node)
    return None


def import_cycles(models: dict) -> list[Diag]:
    """Rule 11, over whatever set of modules was handed to this run."""
    graph = {m.path: set(m.imports.values()) for m in models.values() if m.path}
    out, colour = [], {}

    def visit(node, stack):
        colour[node] = 1
        for nxt in sorted(graph.get(node, ())):
            if nxt not in graph:
                continue                      # not in this run; nothing to say
            if colour.get(nxt) == 1:
                cycle = " -> ".join(stack[stack.index(nxt):] + [nxt])
                src = next(p for p, m in models.items() if m.path == node)
                out.append(Diag(src, 1, 1, 11, f"import cycle: {cycle}"))
            elif colour.get(nxt, 0) == 0:
                visit(nxt, stack + [nxt])
        colour[node] = 2

    for node in sorted(graph):
        if colour.get(node, 0) == 0:
            visit(node, [node])
    return out


# ---------- driver ----------

def target_capabilities(models: dict, target: str) -> list[Diag]:
    """Refuse a module whose declared effects the target cannot provide.

    A browser has console output and no filesystem, environment or subprocesses,
    yet `rustc --target wasm32-unknown-unknown` compiles a module that reads
    files without complaint — it links, ships, and fails at run time. Declared
    effects make that decidable before the build, which is the reason the
    vocabulary is finer than one `io`.
    """
    have = set(TARGETS[target]["effects"])
    out = []
    for src, m in models.items():
        for name, node in list(m.funs.items()) + [("the entry point", n) for n in m.entries]:
            _, declared = decl_opts(node)
            missing = sorted(set(declared) - have)
            if missing:
                line, col = pos(node)
                out.append(Diag(src, line, col, 12,
                                f"`{name}` needs {', '.join('`' + e + '`' for e in missing)}, "
                                f"which the {target} target does not provide "
                                f"({TARGETS[target]['note']})"))
    return out


def check_file(p: Lark, path: Path):
    try:
        tree = p.parse(path.read_text())
    except LarkError as exc:
        first = str(exc).splitlines()[0]
        return None, [Diag(str(path), 0, 0, 1, f"does not parse: {first}")]
    tops = [t.children[0] for t in tree.children]
    m = model(tops)
    return m, Checker(path, tops, m).run()


def main() -> int:
    ap = argparse.ArgumentParser(description="AgentScript semantic checker (§9)")
    ap.add_argument("paths", nargs="*", type=Path)
    ap.add_argument("--json", action="store_true", help="emit diagnostics as JSON")
    ap.add_argument("--rules", action="store_true", help="print what is and is not checked")
    ap.add_argument("--target", choices=sorted(TARGETS),
                    help="also refuse modules whose effects this target cannot provide")
    args = ap.parse_args()

    if args.rules:
        print("TARGETS:")
        for t, v in sorted(TARGETS.items()):
            print(f"  {t:<5} {', '.join(v['effects']):<38} {v['note']}")
        print("CHECKED:")
        for k in sorted(CHECKED):
            print(f"  {k:>2}. {CHECKED[k]}")
        print("NOT CHECKED:")
        for k in sorted(UNCHECKED):
            print(f"  {k:>2}. {UNCHECKED[k]}")
        print()
        print("Rules 3 and 6 FAIL OPEN. The type layer reports only what it can type;")
        print("a construct it cannot type is silent rather than an error, because a")
        print("checker that fires on valid code is worse than none. Silence is")
        print("therefore not proof that a module is well-typed — the target compilers")
        print("remain the stronger signal.")
        return 0

    files = []
    for path in args.paths:
        files += sorted(path.rglob("*.as")) if path.is_dir() else [path]
    if not files:
        print("no .as files given", file=sys.stderr)
        return 1

    p, diags, models = parser(), [], {}
    for f in files:
        m, ds = check_file(p, f)
        diags += ds
        if m is not None:
            models[str(f)] = m
    diags += import_cycles(models)
    if args.target:
        diags += target_capabilities(models, args.target)
    diags.sort(key=lambda d: (d.file, d.line, d.col, d.rule))

    if args.json:
        print(json.dumps([d.as_dict() for d in diags], indent=1))
    else:
        for d in diags:
            print(d.text())
        print(f"\n{len(diags)} diagnostic(s) across {len(files)} file(s)")
    return len(diags)


if __name__ == "__main__":
    sys.exit(main())
