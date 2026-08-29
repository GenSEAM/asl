#!/usr/bin/env python3
"""One module resolver for every tool that follows an AgentS import.

The checker and both backends need the same two answers — which file a module
path names, and in what order a program's imports have to be processed — and
three copies of that would drift apart the way three copies of the parser once
did (see parse.py).
"""
from pathlib import Path

from lark import Token, Tree

from parse import parse_file, tok


def find(mod_path: str, roots) -> Path | None:
    """The file a module path names, over an ordered list of source roots."""
    for root in roots:
        candidate = Path(root) / (mod_path + ".agents")
        if candidate.exists():
            return candidate
    return None


def declared_path(tree: Tree) -> str | None:
    for top in tree.children:
        decl = top.children[0]
        if decl.data == "module_decl":
            return tok(decl.children[1])
    return None


def imports(tree: Tree) -> dict[str, str]:
    """alias -> module path, in header order."""
    out: dict[str, str] = {}
    for top in tree.children:
        decl = top.children[0]
        if decl.data != "module_decl":
            continue
        for opt in decl.children[2:]:
            head = opt.children[0]
            if isinstance(head, Token) and head.type == "IMPORT_KW":
                for spec in opt.children[1:]:
                    out[tok(spec.children[-1])] = tok(spec.children[0])
    return out


def closure(tree: Tree, roots) -> list[tuple[str, Tree]]:
    """Every module `tree` imports, transitively, dependencies first and the tree
    itself excluded. A module reached twice appears once, and a cycle is broken
    rather than diagnosed: rule 11 owns that verdict, and a backend handed a
    cyclic program must not recurse for ever."""
    order: list[tuple[str, Tree]] = []
    # The root is seeded, so a cycle back to it neither recurses nor emits the
    # root a second time under a dependency's prefix.
    seen: set[str] = {p for p in [declared_path(tree)] if p}

    def walk(node: Tree) -> None:
        for mod_path in imports(node).values():
            if mod_path in seen:
                continue
            seen.add(mod_path)
            found = find(mod_path, roots)
            if found is None:
                raise FileNotFoundError(f"no module {mod_path} on the search path")
            sub = parse_file(found)
            walk(sub)
            order.append((mod_path, sub))

    walk(tree)
    return order


def resolve(path, roots=()) -> list[tuple[str, Tree]]:
    """The whole compilation unit for a source file: every module it imports,
    dependencies first, and the file itself last. A file's own directory is
    always searched, as it is for the checker CLI."""
    path = Path(path)
    tree = parse_file(path)
    roots = [path.parent, *(Path(r) for r in roots)]
    return closure(tree, roots) + [(declared_path(tree) or path.stem, tree)]
