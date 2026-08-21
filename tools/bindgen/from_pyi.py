#!/usr/bin/env python3
"""Generate AgentScript foreign declarations from Python type stubs.

Why generated: a total boundary over an ecosystem is only worth having if
declaring it is mechanical. Runtime introspection of a host yields nothing
useful — signatures are erased — but the separately shipped stub corpus covers
the standard library broadly, and the declarations it implies are derivable.

Why the parser and not a regex: a regex prototype produced visible defects on
exactly the shapes that matter, nested generics and optional returns, because a
comma inside `dict[str, list[int]]` looks like an argument separator to anything
that is not tracking brackets. `ast` is in the standard library and tracks them.

What it deliberately does NOT do: invent a failure type. Every foreign call is
`(Result T String)` by the rule in AGENT_SPEC_CORE.md §11, so a stub that
carries no exception information — which is all of them — still yields a total
declaration.

  python3 tools/bindgen/from_pyi.py <stub.pyi> --module data/frames \\
      --package polars --alias pl --target py
"""
import argparse
import ast
import sys
from pathlib import Path

# Host scalar -> language scalar. Anything absent here becomes opaque, which is
# what keeps generation total instead of failing on the first unmodelled type.
SCALARS = {
    "str": "String",
    "int": "Int64",
    "float": "Float64",
    "bool": "Bool",
    "None": "Unit",
    "NoneType": "Unit",
    "bytes": None,          # no byte string in the language yet: opaque
}

CONTAINERS = {"list": "List", "set": "List", "sequence": "List", "iterable": "List",
              "dict": "Map", "mapping": "Map", "tuple": "Pair"}

# Names the language already owns. An opaque may never take one: `list` with no
# parameter used to become `(defopaque List)`, shadowing the built-in `List` with
# a host type — accepted by every gate, and meaning something else entirely.
BUILTIN_TYPE_NAMES = set(CONTAINERS.values()) | {
    "Option", "Result", "Pair", "Map", "List", "Bool", "Int32", "Int64",
    "Float64", "String", "Unit", "ProcessResult"}


class Unmapped(Exception):
    """A host type with no language counterpart. The caller turns it opaque."""


def kebab(name: str) -> str:
    """Host spelling -> a language identifier.

    §2 admits `[a-z][a-z0-9-]*`, so an underscore becomes a dash and a leading
    one is dropped; a name that cannot be spelled at all is rejected rather than
    silently mangled into a different name.
    """
    out = name.strip("_").replace("_", "-").lower()
    if not out or not out[0].isalpha():
        raise Unmapped(f"unspellable host name: {name!r}")
    return out


def snake(name: str) -> str:
    """The language identifier back to the host spelling §8 mangling produces."""
    return name.replace("-", "_")


def render(node, opaques: dict[str, str]) -> str:
    """One annotation as an AgentScript type. Records any opaque it invents."""
    if node is None:
        raise Unmapped("no annotation")

    # `X | None` and `Optional[X]` are the same thing and both mean (Option X).
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr):
        parts = _union_parts(node)
        non_none = [p for p in parts if not _is_none(p)]
        if len(non_none) != len(parts) and len(non_none) == 1:
            return f"(Option {render(non_none[0], opaques)})"
        raise Unmapped("union of more than one non-None type")

    if isinstance(node, ast.Constant) and node.value is None:
        return "Unit"

    if isinstance(node, ast.Subscript):
        head = _name_of(node.value).lower()
        args = _slice_args(node.slice)
        if head in ("optional",) and len(args) == 1:
            return f"(Option {render(args[0], opaques)})"
        if head in ("union",):
            non_none = [a for a in args if not _is_none(a)]
            if len(non_none) == 1 and len(non_none) != len(args):
                return f"(Option {render(non_none[0], opaques)})"
            raise Unmapped("union of more than one non-None type")
        if head in CONTAINERS:
            kind = CONTAINERS[head]
            want = 2 if kind in ("Map", "Pair") else 1
            if len(args) != want:
                raise Unmapped(f"{head} with {len(args)} parameters")
            return f"({kind} " + " ".join(render(a, opaques) for a in args) + ")"
        raise Unmapped(f"unmapped generic: {head}")

    name = _name_of(node)
    if name in SCALARS:
        mapped = SCALARS[name]
        if mapped is None:
            raise Unmapped(f"no language type for {name}")
        return mapped
    # An unparameterised container is not an opaque type — it is a container
    # whose element type the stub did not say. Guessing an opaque here produced
    # `(defopaque List)`, which shadows the built-in.
    if name.lower() in CONTAINERS:
        raise Unmapped(f"`{name}` with no element type")
    # A host class with no mapping becomes opaque rather than a failure.
    pascal = "".join(p[:1].upper() + p[1:] for p in name.replace(".", "_").split("_") if p)
    if not pascal or not pascal[0].isalpha():
        raise Unmapped(f"unspellable host type: {name!r}")
    if pascal in BUILTIN_TYPE_NAMES:
        raise Unmapped(f"host type `{name}` would shadow the built-in `{pascal}`")
    opaques.setdefault(pascal, name)
    return pascal


def _union_parts(node) -> list:
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr):
        return _union_parts(node.left) + _union_parts(node.right)
    return [node]


def _is_none(node) -> bool:
    """Whether this union member is the None arm.

    Answers False for anything it cannot read rather than raising: a `dict[...]`
    arm is not None, and letting the probe fail there discarded the whole
    declaration — which is the optional-return case the regex prototype also
    got wrong.
    """
    if isinstance(node, ast.Constant):
        return node.value is None
    try:
        return _name_of(node) in ("None", "NoneType")
    except Unmapped:
        return False


def _slice_args(sl) -> list:
    if isinstance(sl, ast.Tuple):
        return list(sl.elts)
    return [sl]


def _name_of(node) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value          # a forward reference, written as a string
    if isinstance(node, ast.Constant) and node.value is None:
        return "None"
    raise Unmapped(f"unreadable annotation: {ast.dump(node)[:60]}")


def declarations(stub: str, alias: str, target: str):
    """(declaration blocks, opaque type names, skipped functions with reasons)."""
    tree = ast.parse(stub)
    opaques: dict[str, str] = {}
    blocks: list[str] = []
    skipped: list[tuple[str, str]] = []
    for node in tree.body:
        if not isinstance(node, ast.FunctionDef) or node.name.startswith("_"):
            continue
        a = node.args
        if a.vararg or a.kwarg or a.kwonlyargs:
            skipped.append((node.name, "variadic or keyword-only parameters"))
            continue
        try:
            name = kebab(node.name)
            params = [(kebab(p.arg), render(p.annotation, opaques)) for p in a.args]
            ret = render(node.returns, opaques)
        except Unmapped as exc:
            skipped.append((node.name, str(exc)))
            continue
        doc = (ast.get_docstring(node) or "").strip().splitlines()
        doc = doc[0] if doc else f"Host function {node.name}."
        ps = " ".join(f"({pn} {pt})" for pn, pt in params)
        lines = [f"(defextern {alias}/{name} [{ps}] -> {ret}",
                 f'  :doc "{doc.replace(chr(34), chr(39))}"',
                 f"  :target :{target}"]
        # §8 mangling cannot reproduce every host spelling, so :symbol is emitted
        # exactly when the round trip fails rather than always or never.
        if snake(name) != node.name:
            lines.append(f'  :symbol "{node.name}"')
        blocks.append("\n".join(lines) + ")")
    return blocks, opaques, skipped


def module_text(module: str, package: str, alias: str, target: str,
                blocks, opaques, skipped) -> str:
    exports = " ".join(sorted(o.lower() for o in ()))   # nothing is re-exported
    head = [f"; Generated by tools/bindgen/from_pyi.py. Do not edit by hand.",
            f"; Every declaration below is total: the type shown is the SUCCESS",
            f"; type, and each call site sees (Result T String).",
            "",
            f"(module {module}",
            f'  :doc "Generated foreign declarations for the {package} host package."',
            f"  :export []",
            f'  :extern [({target} "{package}" :as {alias})])',
            ""]
    body = []
    for pascal, host in sorted(opaques.items()):
        body += [f"(defopaque {pascal}",
                 f'  :doc "Host type {host}: passed across the boundary, never inspected here.")',
                 ""]
    for b in blocks:
        body += [b, ""]
    tail = []
    if skipped:
        # Silence here would read as full coverage of the stub.
        tail = ["; Not generated, and why:"] + \
               [f";   {n} - {why}" for n, why in skipped]
    return "\n".join(head + body + tail).rstrip("\n") + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("stub", type=Path)
    ap.add_argument("--module", required=True, help="AgentScript module path")
    ap.add_argument("--package", required=True, help="host package name")
    ap.add_argument("--alias", required=True, help="alias used in call sites")
    ap.add_argument("--target", default="py")
    args = ap.parse_args()

    blocks, opaques, skipped = declarations(
        args.stub.read_text(), args.alias, args.target)
    if not blocks:
        print("no declarations generated", file=sys.stderr)
        return 1
    sys.stdout.write(module_text(args.module, args.package, args.alias,
                                 args.target, blocks, opaques, skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main())
