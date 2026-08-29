#!/usr/bin/env python3
"""The semantic rules of AGENT_SPEC_CORE.md 9, plus the construction rules 4.1
states normatively but the 9 checklist omits.

Diagnostic codes are the rule numbers themselves where §9 has one, and a name
where it does not: `arity`, `ctor`, `type`, `annotation`, `unresolved-import`,
`parse`. Naming them after the normative list keeps the trace to the
specification direct, and makes a fixture able to declare which rule it is
supposed to violate.

Exhaustiveness here is pattern-driven, not scrutinee-driven: knowing that
(match (map-get m w) ...) scrutinises an Option needs the builtin's return type,
which arrives with the type layer. So this pass asks only whether the arms cover
the union they name, and a match whose arms are coherent but wrong for the
scrutinee is left to that layer.
"""
import sys
from dataclasses import dataclass
from pathlib import Path

from lark import Token, Tree
from lark.exceptions import LarkError

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "prelude"))

from collect import Module, collect, marked  # noqa: E402
from modules import find  # noqa: E402
from parse import kids, position, tok  # noqa: E402
from vocab import (builtins, effectful, parse_signature, signatures,  # noqa: E402
                   special_forms, type_aliases, type_names, unions)

RESERVED = "agents-"

# Arity of the built-in union tags, which are constructors and patterns both.
TAGS = {"some": 1, "none": 0, "ok": 1, "err": 1, "list": 0, "cons": 2, "pair": 2}
UNIONS = {"Option": {"some", "none"}, "Result": {"ok", "err"}, "List": {"list", "cons"}}
UNIONS.update({name: set(cases) for name, cases in unions().items()})
TAGS.update({case: 0 for cases in unions().values() for case in cases})
PAIR_FIELDS = {"first", "second"}
TYPE_ALIASES = type_aliases()


def _constructor_arity() -> dict[str, int]:
    """Built-in type name -> how many arguments §3 writes it with, read off the
    builtin signatures. The vocabulary records the arities only by using them, so
    deriving beats restating: a second table would be free to drift from §3."""
    out: dict[str, int] = {}

    def walk(spec: dict) -> None:
        if "con" in spec:
            out.setdefault(spec["con"], len(spec["args"]))
            for a in spec["args"]:
                walk(a)
        elif "fn" in spec:
            for p in spec["fn"]:
                walk(p)
            walk(spec["ret"])

    for sig in signatures().values():
        args, _, ret = parse_signature(sig)
        for a in args:
            walk(a)
        walk(ret)
    for name in type_names():
        out.setdefault(name, 0)
    return out


CONSTRUCTOR_ARITY = _constructor_arity()


@dataclass(frozen=True)
class Diagnostic:
    code: str
    message: str
    line: int
    col: int
    path: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}:{self.col}: {self.code}: {self.message}"


def fn_parts(body, check_type=None, typevars=None):
    """A lambda's parameter names and its body, with the optional annotations
    checked in passing. Both the types and the arrow are elidable, so neither
    position can be addressed by index."""
    names = set()
    for p in body[0].children:
        if isinstance(p, Tree) and p.data == "fn_param":
            parts = kids(p)
            names.add(tok(parts[0]))
            if len(parts) > 1 and check_type is not None:
                check_type(parts[1], typevars, "a lambda parameter")
    rest = list(body[1:])
    if rest and isinstance(rest[0], Tree) and rest[0].data == "type":
        if check_type is not None:
            check_type(rest[0], typevars, "a lambda return")
        rest = rest[1:]
    return names, rest


class Loader:
    """Module path -> module summary, over an ordered list of source roots."""

    def __init__(self, roots: list[Path]):
        self.roots = [Path(r) for r in roots]
        self._cache: dict[str, Module | None] = {}

    def load(self, mod_path: str) -> Module | None:
        if mod_path not in self._cache:
            found = find(mod_path, self.roots)
            self._cache[mod_path] = collect(found) if found is not None else None
        return self._cache[mod_path]


class Checker:
    def __init__(self, mod: Module, loader: Loader):
        self.mod = mod
        self.loader = loader
        self.diags: list[Diagnostic] = []
        self.globals = (builtins() | special_forms() | set(mod.funs)
                        | set(mod.case_owner) | set(TAGS))
        self.known_types = type_names() | set(mod.schemas) | set(mod.enums)
        self.effectful = effectful() | {n for n, f in mod.funs.items() if f.effect}
        # True while the walk is inside a declaration that carries the marker.
        self.effect_ok: list[bool] = [True]
        self.field_names = ({f for s in mod.schemas.values() for f in s.fields}
                            | PAIR_FIELDS | self.imported_fields())

    def imported_fields(self) -> set[str]:
        """Exporting a record publishes its fields, so `.-field` reaches across a
        boundary as §4.0 promises."""
        out: set[str] = set()
        for mod_path in self.mod.imports.values():
            target = self.loader.load(mod_path)
            if target is not None:
                out |= target.exported_fields
        return out

    # ---------- reporting ----------

    def report(self, code: str, message: str, node) -> None:
        line, col = position(node)
        self.diags.append(Diagnostic(code, message, line, col, str(self.mod.path)))

    # ---------- module-level rules ----------

    def module_rules(self) -> None:
        if self.mod.has_header and not self.mod.doc:
            self.report("rule-8", f"module {self.mod.name} has no :doc", self.mod.tree)
        for name in self.mod.exports:
            if name in self.mod.funs:
                if not self.mod.funs[name].doc:
                    self.report("rule-8", f"exported function {name} has no :doc",
                                self.mod.funs[name].node)
            else:
                # A case name is not a declaration: cases travel with their type
                # (AGENT_SPEC_CORE 4.0), so the entry names nothing.
                self.report("rule-2", f"{name} is exported but not defined in this module",
                            self.mod.tree)
        for name in self.mod.exported_types:
            if name not in self.mod.schemas and name not in self.mod.enums:
                self.report("rule-2", f"{name} is exported but not defined in this module",
                            self.mod.tree)

    def reserved_names(self) -> None:
        for token in self.mod.tree.scan_values(
                lambda t: isinstance(t, Token)
                and t.type in ("IDENT", "QUALIFIED", "QUALIFIED_TYPE")):
            if str(token).startswith(RESERVED) or "/" + RESERVED in str(token):
                self.report("rule-7", f"{token} uses the reserved {RESERVED} prefix", token)

    def imports_and_cycles(self) -> None:
        for alias, mod_path in self.mod.imports.items():
            if self.loader.load(mod_path) is None:
                self.report("unresolved-import",
                            f"no module {mod_path} on the search path",
                            self.mod.import_nodes[alias])

        stack: list[str] = []
        done: set[str] = set()

        def visit(mod: Module) -> None:
            stack.append(mod.name)
            for alias, mod_path in mod.imports.items():
                target = self.loader.load(mod_path)
                if target is None:
                    continue
                if target.name in stack:
                    path = " -> ".join(stack[stack.index(target.name):] + [target.name])
                    self.report("rule-11", f"import cycle: {path}",
                                mod.import_nodes[alias] if mod is self.mod else self.mod.tree)
                elif target.name not in done:
                    visit(target)
            stack.pop()
            done.add(mod.name)

        visit(self.mod)

    def qualified_names(self) -> None:
        for token in self.mod.tree.scan_values(
                lambda t: isinstance(t, Token) and t.type == "QUALIFIED"):
            alias, _, member = str(token).partition("/")
            if alias not in self.mod.imports:
                self.report("rule-9", f"{token}: alias {alias} is not imported", token)
                continue
            target = self.loader.load(self.mod.imports[alias])
            if target is None:
                continue                      # already reported as unresolved-import
            if member not in target.exports and member not in target.exported_cases:
                self.report("rule-9", f"{member} is not exported by {target.name}", token)

    def qualified_types(self) -> None:
        """Rule 9 in type position. A QUALIFIED_TYPE is one terminal, so the name
        after the slash is never a TYPE_NAME token and never reaches check_type;
        this is where it is reached instead."""
        for token in self.mod.tree.scan_values(
                lambda t: isinstance(t, Token) and t.type == "QUALIFIED_TYPE"):
            alias, _, member = str(token).partition("/")
            if alias not in self.mod.imports:
                self.report("rule-9", f"{token}: alias {alias} is not imported", token)
                continue
            target = self.loader.load(self.mod.imports[alias])
            if target is None:
                continue                      # already reported as unresolved-import
            if member not in target.exported_types:
                self.report("rule-9", f"{member} is not an exported type of {target.name}",
                            token)

    # ---------- the export closure (rule 13) ----------

    def export_closure(self) -> None:
        """Rule 13: every type in an exported signature is itself public. A
        signature over a private type is not a contract — no importer can write
        the type of what it receives."""
        for name in self.mod.exports:
            fun = self.mod.funs.get(name)
            if fun is None:
                continue
            for _, ty in fun.params:
                self.public_type(ty, fun.typevars, f"exported function {name}")
            self.public_type(fun.ret, fun.typevars, f"exported function {name}")
        for name in self.mod.exported_types:
            if (schema := self.mod.schemas.get(name)) is not None:
                for fname, (ty, _) in schema.fields.items():
                    self.public_type(ty, schema.typevars, f"exported field {name}.{fname}")
            if (enum := self.mod.enums.get(name)) is not None:
                for case, params in enum.cases.items():
                    for _, ty in params:
                        self.public_type(ty, enum.typevars, f"case {case} of exported {name}")

    def public_type(self, node: Tree, bound: set[str], where: str) -> None:
        """Only locally declared names are reported. Whether the DEFINING module
        publishes an alias-qualified type is the identical question rule 9 asks
        at the same token, and answering it twice would give one defect two
        codes."""
        exported = set(self.mod.exported_types)
        for token in node.scan_values(lambda t: isinstance(t, Token) and t.type == "TYPE_NAME"):
            name = str(token)
            if name in bound or name in exported:
                continue
            if name in self.mod.schemas or name in self.mod.enums:
                self.report("rule-13", f"{name} in {where} is declared here and not exported",
                            token)

    # ---------- type variables (rule 10) ----------

    def type_var_rules(self) -> None:
        for fun in self.mod.funs.values():
            bound = fun.typevars
            for _, ty in fun.params:
                self.check_type(ty, bound, f"function {fun.name}")
            self.check_type(fun.ret, bound, f"function {fun.name}")
        for schema in self.mod.schemas.values():
            for fname, (ty, _) in schema.fields.items():
                self.check_type(ty, schema.typevars, f"field {schema.name}.{fname}")
        for enum in self.mod.enums.values():
            for case, params in enum.cases.items():
                for _, ty in params:
                    self.check_type(ty, enum.typevars, f"case {case}")

    def check_type(self, node: Tree, bound: set[str], where: str) -> None:
        # Local names only: an alias-qualified type is a single terminal and is
        # resolved by qualified_types(), against the module that defines it.
        for token in node.scan_values(lambda t: isinstance(t, Token) and t.type == "TYPE_NAME"):
            name = str(token)
            if name not in self.known_types and name not in bound:
                self.report("rule-10",
                            f"{name} in {where} is neither a known type nor bound in {{ }}",
                            token)
        self.type_arity(node, bound, where)

    def type_arity(self, node: Tree, bound: set[str], where: str) -> None:
        """§3 writes every constructed type applied — `(List T)`, `(Result T E)`.
        An unapplied one names no type, and the layers downstream index the
        arguments it does not have, so it is refused here rather than reaching
        them as a crash."""
        for arg in node.children[1:]:
            self.type_arity(arg, bound, where)
        head = node.children[0]
        given = len(node.children) - 1
        if head.type == "QUALIFIED_TYPE":
            expected = self.imported_arity(head)
        elif str(head) in bound:
            expected = 0                      # a type variable is not a constructor
        else:
            expected = self.local_arity(str(head))
        if expected is not None and expected != given:
            self.report("type-arity",
                        f"{head} in {where} takes {expected} type argument(s), given {given}",
                        head)

    def local_arity(self, name: str) -> int | None:
        name = TYPE_ALIASES.get(name, name)
        if (schema := self.mod.schemas.get(name)) is not None:
            return len(schema.typevars)
        if (enum := self.mod.enums.get(name)) is not None:
            return len(enum.typevars)
        return CONSTRUCTOR_ARITY.get(name)    # None: rule 10 owns an unknown name

    def imported_arity(self, token: Token) -> int | None:
        alias, _, member = str(token).partition("/")
        target = self.loader.load(self.mod.imports.get(alias, ""))
        if target is None:
            return None                       # rule 9 owns an unbound alias
        declared = target.schemas.get(member) or target.enums.get(member)
        return None if declared is None else len(declared.typevars)

    # ---------- bodies ----------

    def bodies(self) -> None:
        for fun in self.mod.funs.values():
            scope = {name for name, _ in fun.params}
            self.effect_ok.append(fun.effect)
            for child in kids(fun.node):
                if isinstance(child, Tree) and child.data == "expr":
                    self.expr(child, scope)
            self.effect_ok.pop()

    def expr(self, node: Tree, scope: set[str]) -> None:
        child = node.children[0]
        if isinstance(child, Token):
            self.name(child, scope)
            return
        getattr(self, f"_{child.data}", self._recurse)(child, scope)

    def _recurse(self, node: Tree, scope: set[str]) -> None:
        """Descends through intermediate trees, not only through expressions:
        `cond`'s children are clauses, so an expression-only descent walked past
        every clause body and reported nothing rather than reporting a defect. A
        form that BINDS names still needs a handler of its own; this reaches the
        ones that only nest."""
        for k in node.children:
            if isinstance(k, Tree):
                (self.expr if k.data == "expr" else self._recurse)(k, scope)

    def name(self, token: Token, scope: set[str]) -> None:
        text = str(token)
        if token.type == "QUALIFIED" or text.startswith(RESERVED):
            return                            # rules 9 and 7 own these
        if token.type in ("IDENT", "OPERATOR") and text not in scope | self.globals:
            self.report("rule-2", f"{text} is not defined", token)

    # -- forms --

    def _literal(self, node: Tree, scope: set[str]) -> None:
        return

    def _call(self, node: Tree, scope: set[str]) -> None:
        head, *args = [k for k in node.children if isinstance(k, Tree) and k.data == "expr"]
        for a in args:
            self.expr(a, scope)
        inner = head.children[0]
        self.effect_rule(inner, args, node)
        if not (isinstance(inner, Token) and inner.type in ("IDENT", "QUALIFIED")):
            self.expr(head, scope)
            return
        self.name(inner, scope)
        callee = str(inner)
        if callee in scope:
            return                            # a lambda in a binding; arity is a type-layer fact
        expected = self.callee_arity(callee)
        if expected is not None and expected != len(args):
            self.report("arity", f"{callee} takes {expected} argument(s), given {len(args)}",
                        inner)

    def callee_arity(self, callee: str) -> int | None:
        """The declared parameter count of a call's head, local or alias-qualified.
        A module boundary does not make arity unknowable: the import table carries
        the callee's parameters, and rule 9 has already established the member is
        public.

        Builtin arity is deliberately absent here: `list` is variadic as a
        constructor and nullary as a pattern, and telling them apart needs the
        real signatures the type layer reads."""
        alias, sep, member = callee.partition("/")
        if sep:
            target = self.loader.load(self.mod.imports.get(alias, ""))
            if target is None:
                return None                   # rule 9 owns an unbound alias
            if member in target.funs:
                return len(target.funs[member].params)
            if member in target.exported_cases:
                return len(target.enums[target.exported_cases[member]].cases[member])
            return None
        if callee in self.mod.funs:
            return len(self.mod.funs[callee].params)
        params = self.mod.case_params(callee)
        return None if params is None else len(params)

    def effect_rule(self, inner, args, node: Tree) -> None:
        """A call is effectful when its callee is, or when an effectful lambda is
        handed to it — the combinators all apply what they are given, so colouring
        the call is what lets one `map` serve both kinds. It over-approximates: a
        marked lambda that is passed and never applied colours its caller anyway.
        That is the price of not carrying effects in the type, and the seam where
        a real effect system would go."""
        effect = isinstance(inner, Token) and self.callee_effect(str(inner))
        for a in args:
            child = a.children[0]
            if isinstance(child, Tree) and child.data == "fn_form" and marked(child):
                effect = True
        if effect and not self.effect_ok[-1]:
            self.report("rule-12", "effectful call inside a declaration not marked !", node)

    def callee_effect(self, name: str) -> bool:
        if "/" in name:
            alias, _, member = name.partition("/")
            target = self.loader.load(self.mod.imports.get(alias, ""))
            return target is not None and member in target.funs and target.funs[member].effect
        return name in self.effectful

    def _let_form(self, node: Tree, scope: set[str]) -> None:
        inner = set(scope)
        for k in node.children:
            if isinstance(k, Tree) and k.data == "binding":
                self.expr(k.children[1], inner)     # let* : sequential, sees earlier bindings
                inner.add(tok(k.children[0]))       # shadowing is permitted (5.1)
            elif isinstance(k, Tree) and k.data == "expr":
                self.expr(k, inner)

    def _fn_form(self, node: Tree, scope: set[str]) -> None:
        body = kids(node)
        names, rest = fn_parts(body, self.check_type, self.enclosing_typevars())
        inner = scope | names
        self.effect_ok.append(marked(node))
        for k in rest:
            if isinstance(k, Tree) and k.data == "expr":
                self.expr(k, inner)
        self.effect_ok.pop()

    def enclosing_typevars(self) -> set[str]:
        # A lambda cannot bind type variables of its own, so every variable it
        # names must already be bound by some declaration in this module.
        return {v for f in self.mod.funs.values() for v in f.typevars}

    def imported_schema(self, token: Token):
        """The record an alias-qualified ctor head names, resolved in the module
        that DEFINES it: §4.1's construction rules do not change at a boundary,
        but visibility does."""
        alias, _, member = str(token).partition("/")
        target = self.loader.load(self.mod.imports.get(alias, ""))
        if target is None:
            return None                       # rule 9 owns an unbound alias
        if member not in target.exported_types:
            self.report("rule-9", f"{member} is not an exported type of {target.name}", token)
            return None
        schema = target.schemas.get(member)
        if schema is None:
            self.report("rule-2", f"{member} is not a record type in {target.name}", token)
        return schema

    def _ctor(self, node: Tree, scope: set[str]) -> None:
        type_token = node.children[0]
        name = str(type_token)
        if type_token.type == "QUALIFIED_TYPE":
            schema = self.imported_schema(type_token)
        else:
            schema = self.mod.schemas.get(name)
            if schema is None:
                self.report("rule-2", f"{name} is not a record type in this module", type_token)
        given = []
        for arg in node.children[1:]:
            key = str(arg.children[0])[1:]
            self.expr(arg.children[1], scope)
            if schema is not None:
                if key not in schema.fields:
                    self.report("ctor", f"{name} has no field {key}", arg.children[0])
                elif key in given:
                    self.report("ctor", f"{name}: duplicate key {key}", arg.children[0])
            given.append(key)
        if schema is not None:
            missing = [f for f, (_, has_default) in schema.fields.items()
                       if f not in given and not has_default]
            if missing:
                self.report("ctor", f"{name} is missing {', '.join(missing)}", type_token)

    def _field_access(self, node: Tree, scope: set[str]) -> None:
        ref = node.children[0]
        field = str(ref)[2:]
        if field not in self.field_names:
            self.report("rule-2", f"no record in this module has a field {field}", ref)
        self.expr(node.children[1], scope)

    def _match_form(self, node: Tree, scope: set[str]) -> None:
        body = kids(node)
        self.expr(body[0], scope)
        heads, catchall = [], False
        for arm in body[1:]:
            pattern = arm.children[0]
            bound, head = self.pattern(pattern, scope)
            if head is None:
                catchall = catchall or bound is not None
            else:
                heads.append(head)
            inner = scope | (bound or set())
            for k in arm.children[1:]:
                if isinstance(k, Tree) and k.data == "expr":
                    self.expr(k, inner)
        if not catchall:
            self.exhaustive(heads, node)

    def pattern(self, node: Tree, scope: set[str]) -> tuple[set[str] | None, str | None]:
        """Returns (names bound, constructor head). A head of None with a bound
        set is a catch-all; None/None is a literal, which closes nothing."""
        if node.data == "enum_pattern":
            parts = kids(node)
            head = tok(parts[0])
            arity = TAGS.get(head)
            source = self.case_source(head)
            if source is not None:
                arity = len(source[1])
            elif arity is None:
                self.report("rule-2", f"{head} is not a case of any union", parts[0])
            subs = [p for p in parts[1:] if isinstance(p, Tree) and p.data in ("pattern", "enum_pattern")]
            if arity is not None and arity != len(subs):
                self.report("arity", f"pattern {head} takes {arity} argument(s), given {len(subs)}",
                            parts[0])
            bound: set[str] = set()
            for sub in subs:
                names, _ = self.pattern(sub, scope)
                bound |= names or set()
            return bound, head
        child = node.children[0]
        if isinstance(child, Token) and child.type == "IDENT":
            return {str(child)}, None
        if isinstance(child, Token) and child.type == "WILDCARD":
            return set(), None
        if isinstance(child, Tree) and child.data == "enum_pattern":
            return self.pattern(child, scope)
        return None, None                     # a literal pattern

    def case_source(self, head: str):
        """(owning union, this case's parameters, all its cases) for a pattern
        head, local or alias-qualified. The union is keyed by the module that
        DEFINES it, so a local Shape and an imported one stay apart instead of
        collapsing to one string."""
        alias, sep, member = head.partition("/")
        if sep:
            target = self.loader.load(self.mod.imports.get(alias, ""))
            if target is None or member not in target.exported_cases:
                return None
            enum = target.enums[target.exported_cases[member]]
        else:
            member, target = head, self.mod
            if head not in self.mod.case_owner:
                return None
            enum = self.mod.enums[self.mod.case_owner[head]]
        return f"{target.name}/{enum.name}", enum.cases[member], set(enum.cases)

    def exhaustive(self, heads: list[str], node: Tree) -> None:
        if not heads:
            return
        sources = [self.case_source(h) for h in heads]
        if all(s is not None for s in sources):
            enums = {s[0] for s in sources}
            if len(enums) > 1:
                self.report("rule-4", f"arms mix unions: {', '.join(sorted(enums))}", node)
                return
            full = sources[0][2]
            # An imported case is written alias/case-name, and the alias is this
            # module's business; the union is covered by member name.
            heads = [h.partition("/")[2] or h for h in heads]
        else:
            for full in UNIONS.values():
                if set(heads) & full:
                    break
            else:
                return                        # heads unresolvable; rule 2 has reported them
        missing = sorted(full - set(heads))
        if missing:
            self.report("rule-4", f"match is not exhaustive: {', '.join(missing)} unhandled", node)

    # ---------- entry ----------

    def run(self) -> list[Diagnostic]:
        from types_ import Types

        self.module_rules()
        self.reserved_names()
        self.imports_and_cycles()
        self.qualified_names()
        self.qualified_types()
        self.type_var_rules()
        self.export_closure()
        self.bodies()
        # The type layer runs last and only on a resolvable module: typing an
        # unbound name reports the same defect twice in different words.
        if not self.diags:
            Types(self.mod, self.report, self.loader).check_module()
        return sorted(self.diags, key=lambda d: (d.line, d.col, d.code))


def check_file(path: Path, roots: list[Path]) -> list[Diagnostic]:
    """A file gets diagnostics, never a traceback: the measurement harness feeds
    this generated code, where malformed input is an expected outcome to
    classify rather than a crash.

    A checker bug reaching here is still a checker bug — `internal` is a code no
    fixture declares, so the gate reports it as a failure instead of absorbing
    it, which is what keeps the net from becoming a place for defects to hide."""
    path = Path(path)
    try:
        mod = collect(path)
    except LarkError as exc:
        return [Diagnostic("parse", str(exc).splitlines()[0], 0, 0, str(path))]
    try:
        return Checker(mod, Loader([path.parent, *roots])).run()
    except Exception as exc:
        return [Diagnostic("internal", f"{type(exc).__name__}: {exc}", 0, 0, str(path))]
