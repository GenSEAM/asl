#!/usr/bin/env python3
"""Read a source file into the summary the rules need.

The module header is deliberately readable without the body (AGENT_SPEC_CORE 4.0),
so an imported module is collected but never walked: rule 9 asks only what a
module exports, which is exactly what the header carries.
"""
import sys
from dataclasses import dataclass, field
from pathlib import Path

from lark import Token, Tree

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "grammar"))

from parse import kids, parse_file, tok  # noqa: E402


@dataclass
class Fun:
    name: str
    params: list[tuple[str, Tree]]
    ret: Tree
    typevars: set[str]
    doc: bool
    effect: bool
    node: Tree


@dataclass
class Schema:
    name: str
    typevars: set[str]
    fields: dict[str, tuple[Tree, bool]]        # name -> (type, has default)
    node: Tree
    # The default's literal, kept beside the flag: a default is a value of the
    # field's type, and nothing can check that from the flag alone.
    defaults: dict[str, Tree] = field(default_factory=dict)


@dataclass
class Enum:
    name: str
    typevars: set[str]
    cases: dict[str, list[tuple[str, Tree]]]    # case -> parameters
    node: Tree


@dataclass
class Module:
    path: Path
    name: str
    has_header: bool = False
    doc: bool = False
    exports: list[str] = field(default_factory=list)
    exported_types: list[str] = field(default_factory=list)
    imports: dict[str, str] = field(default_factory=dict)   # alias -> module path
    import_nodes: dict[str, Tree] = field(default_factory=dict)
    funs: dict[str, Fun] = field(default_factory=dict)
    schemas: dict[str, Schema] = field(default_factory=dict)
    enums: dict[str, Enum] = field(default_factory=dict)
    tree: Tree | None = None

    @property
    def case_owner(self) -> dict[str, str]:
        return {c: e.name for e in self.enums.values() for c in e.cases}

    # Exporting a type publishes its cases and its fields (AGENT_SPEC_CORE 4.0).
    # Both halves of that are defined here once, so every pass asking "is this
    # member publicly reachable" asks the same question.

    @property
    def exported_cases(self) -> dict[str, str]:
        exported = set(self.exported_types)
        return {c: e.name for e in self.enums.values() if e.name in exported
                for c in e.cases}

    @property
    def exported_fields(self) -> set[str]:
        exported = set(self.exported_types)
        return {f for s in self.schemas.values() if s.name in exported for f in s.fields}

    def case_params(self, case: str) -> list[tuple[str, Tree]] | None:
        for e in self.enums.values():
            if case in e.cases:
                return e.cases[case]
        return None


def marked(node: Tree) -> bool:
    """Whether a declaration carries the effect marker. It is filtered out of
    `kids`, so every index into the declaration is unaffected by its presence."""
    return any(isinstance(k, Token) and k.type == "BANG" for k in node.children)


def type_params(node: Tree) -> set[str]:
    for k in node.children:
        if isinstance(k, Tree) and k.data == "type_params":
            return {str(t) for t in k.children}
    return set()


def _params(node: Tree) -> list[tuple[str, Tree]]:
    out = []
    for k in node.children:
        if isinstance(k, Tree) and k.data == "param":
            out.append((tok(k.children[0]), k.children[1]))
    return out


def _string(node: Tree, terminal: str) -> str | None:
    for k in node.children:
        if isinstance(k, Token) and k.type == terminal:
            return str(k)
    return None


def collect(path: Path) -> Module:
    tree = parse_file(path)
    mod = Module(path=Path(path), name=Path(path).stem, tree=tree)

    for top in tree.children:
        decl = top.children[0]
        if decl.data == "module_decl":
            mod.has_header = True
            mod.name = tok(decl.children[1])
            for opt in decl.children[2:]:
                if not (isinstance(opt, Tree) and opt.children):
                    continue
                head = opt.children[0]
                if isinstance(head, Token) and head.type == "DOC_KW":
                    mod.doc = True
                elif isinstance(head, Token) and head.type == "EXPORT_KW":
                    # One list, and the entry's case decides its kind: type names
                    # are PascalCase and identifiers are not, so no keyword is
                    # needed and there is no second contract to disagree with.
                    for t in opt.children[1:]:
                        bucket = (mod.exported_types if t.type == "TYPE_NAME"
                                  else mod.exports)
                        bucket.append(str(t))
                elif isinstance(head, Token) and head.type == "IMPORT_KW":
                    for spec in opt.children[1:]:
                        alias = tok(spec.children[-1])
                        mod.imports[alias] = tok(spec.children[0])
                        mod.import_nodes[alias] = spec
        elif decl.data == "defun":
            body = kids(decl)
            name = tok(body[0]) if isinstance(body[0], Token) else tok(body[1])
            offset = 0 if isinstance(body[0], Token) else 1
            mod.funs[name] = Fun(
                name=name,
                params=_params(body[offset + 1]),
                ret=body[offset + 2],
                typevars=type_params(decl),
                doc=any(isinstance(k, Tree) and k.data == "doc_opt" for k in decl.children),
                effect=marked(decl),
                node=decl,
            )
        elif decl.data == "defschema":
            body = kids(decl)
            name = str(body[0]) if isinstance(body[0], Token) else str(body[1])
            fields, defaults = {}, {}
            for k in decl.children:
                if isinstance(k, Tree) and k.data == "field":
                    parts = kids(k)
                    fname = tok(parts[0])
                    for o in k.children:
                        if (isinstance(o, Tree) and o.data == "field_opt"
                                and o.children and isinstance(o.children[0], Token)
                                and o.children[0].type == "DEFAULT_KW"):
                            defaults[fname] = o.children[1]
                    fields[fname] = (parts[1], fname in defaults)
            mod.schemas[name] = Schema(name, type_params(decl), fields, decl, defaults)
        elif decl.data == "defenum":
            body = kids(decl)
            name = str(body[0]) if isinstance(body[0], Token) else str(body[1])
            cases = {}
            for k in decl.children:
                if isinstance(k, Tree) and k.data == "enum_case":
                    cases[tok(kids(k)[0])] = _params(k)
            mod.enums[name] = Enum(name, type_params(decl), cases, decl)
    return mod
