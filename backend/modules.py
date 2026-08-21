#!/usr/bin/env python3
"""Resolving `:import` to files, and linking modules into one program.

Nothing did this before. `imports` was read only by the checker, for the cycle
graph and alias binding, so a module path resolved to nothing and no signature
crossed a boundary — `06-module.as` named `core/strings` for two versions while
no such file existed, and every backend skipped the fixture rather than fail.

**Whole-program compilation, not separate compilation.** An entry module pulls in
its imports transitively and the backends emit one output file. Separate
compilation would need a per-target module system in each of four backends and
buys nothing here, where a program is a handful of modules built at once.

**Modules are indexed by their declared header, not by filename.** The corpus
puts module `text/casing` in `06-module.as`, and requiring the two to match would
mean renaming fixtures to satisfy the loader rather than the other way round.
Indexing the header also makes a duplicate module path detectable, which a
filename convention gets for free and this does not.
"""
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from lark import Lark, Token, Tree

ROOT = Path(__file__).parent.parent

# The index reads headers with a regex rather than a parse. A line beginning with
# `(module` cannot be anything else — a comment starts with `;` — and parsing
# every file in the tree to build an index would be paid on every one of the
# transpiler invocations the corpus gate makes.
HEADER = re.compile(r"^\(module\s+([a-z][a-z0-9-]*(?:/[a-z][a-z0-9-]*)*)", re.M)


class ModuleError(Exception):
    """A module could not be resolved, or the module graph is malformed."""


@dataclass
class Loaded:
    path: str                       # declared module path, "" when headerless
    file: Path
    tops: list
    exports: set = field(default_factory=set)
    imports: dict = field(default_factory=dict)     # alias -> module path
    is_entry: bool = False

    def prefix(self) -> str:
        """What a top-level name is qualified by when this module is emitted.

        The entry module keeps its names bare: they are the program's own
        surface, and prefixing them would rename every function the tests and
        the differential harness call by name.
        """
        return "" if self.is_entry or not self.path else self.path + "/"


@dataclass
class Program:
    modules: list                   # dependency order, entry last
    by_path: dict

    @property
    def entry(self) -> Loaded:
        return self.modules[-1]


def parser() -> Lark:
    return Lark((ROOT / "grammar" / "as-lang.lark").read_text(),
                start="start", parser="earley", ambiguity="resolve",
                propagate_positions=True)


def index(roots: list[Path]) -> dict:
    """Declared module path -> file, over every `.as` under the given roots."""
    out: dict[str, Path] = {}
    for r in roots:
        if not r.exists():
            continue
        for f in sorted(r.rglob("*.as")):
            m = HEADER.search(f.read_text())
            if not m:
                continue
            name = m.group(1)
            if name in out and out[name] != f:
                raise ModuleError(
                    f"module `{name}` is declared by two files: {out[name]} and {f}")
            out[name] = f
    return out


def _header(tops) -> tuple[str, set, dict]:
    """(module path, exports, alias -> module path) from a parsed file."""
    for n in tops:
        if not (isinstance(n, Tree) and n.data == "module_decl"):
            continue
        kids = [k for k in n.children
                if not (isinstance(k, Token) and k.type == "MODULE")]
        path = str(kids[0].children[0]) if isinstance(kids[0], Tree) else str(kids[0])
        exports, imports = set(), {}
        for o in n.children:
            if not (isinstance(o, Tree) and o.data == "module_opt"):
                continue
            head = str(o.children[0])
            if head == ":export":
                exports = {str(x) for x in o.children[1:]}
            elif head == ":import":
                for sp in o.children:
                    if isinstance(sp, Tree) and sp.data == "import_spec":
                        sk = [k for k in sp.children
                              if not (isinstance(k, Token) and k.type == "AS_KW")]
                        mod = sk[0].children[0] if isinstance(sk[0], Tree) else sk[0]
                        imports[str(sk[1])] = str(mod)
        return path, exports, imports
    return "", set(), {}


def load(entry: Path, roots: list[Path] | None = None, p: Lark | None = None) -> Program:
    """Load an entry module and everything it imports, in dependency order."""
    p = p or parser()
    roots = roots or default_roots(entry)
    table = index(roots)

    seen: dict[str, Loaded] = {}
    order: list[Loaded] = []
    visiting: list[str] = []

    def visit(path: str, file: Path, is_entry: bool) -> Loaded:
        tops = [t.children[0] for t in p.parse(file.read_text()).children]
        name, exports, imports = _header(tops)
        if not is_entry and name != path:
            raise ModuleError(f"{file} declares module `{name}`, imported as `{path}`")
        mod = Loaded(name, file, tops, exports, imports, is_entry)
        seen[name or str(file)] = mod
        visiting.append(name)
        for alias, dep in sorted(imports.items()):
            # `visiting` is tested before `seen`: a module is recorded in `seen`
            # as soon as it is entered, so checking that first made every cycle
            # look like an already-loaded dependency and the check never fired.
            if dep in visiting:
                raise ModuleError("import cycle: "
                                  + " -> ".join(visiting[visiting.index(dep):] + [dep]))
            if dep in seen:
                continue
            if dep not in table:
                raise ModuleError(
                    f"{file} imports `{dep}` as `{alias}`, which no file under "
                    f"{', '.join(str(r) for r in roots)} declares")
            visit(dep, table[dep], False)
        visiting.pop()
        order.append(mod)                 # after its dependencies
        return mod

    entry_name = _header([t.children[0] for t in p.parse(entry.read_text()).children])[0]
    visit(entry_name, entry, True)
    check_collisions(order)
    return Program(order, {m.path: m for m in order if m.path})


def default_roots(entry: Path) -> list[Path]:
    """Where imports are looked for: the entry's own directory, and `lib/`."""
    return [entry.resolve().parent, ROOT / "lib"]


def qualify(mod: Loaded, member: str) -> str:
    """A top-level name as the whole program sees it.

    Returned in the language's own spelling so each backend's existing §8
    mangling produces it: `core/strings` + `concat` becomes `core/strings/concat`,
    which mangles to `core_strings_concat` and `coreStringsConcat` with no new
    rule anywhere.
    """
    return mod.prefix() + member


def check_collisions(modules: list) -> None:
    """§8 requires an error, never a silent rename, when two names collide.

    Flattening a module path into one identifier can collide — module `core` with
    member `strings-concat` flattens the same as module `core/strings` with
    member `concat`. Rare, and silent if unchecked.
    """
    from_flat: dict[str, str] = {}
    for m in modules:
        for name in top_level_names(m.tops):
            flat = qualify(m, name).replace("-", "_").replace("/", "_")
            owner = f"{m.path or m.file.name}/{name}"
            if flat in from_flat and from_flat[flat] != owner:
                raise ModuleError(
                    f"`{owner}` and `{from_flat[flat]}` both mangle to `{flat}`")
            from_flat[flat] = owner
    check_unprefixed(modules)


def check_unprefixed(modules: list) -> None:
    """Record types and enum cases are emitted without the module prefix.

    A `TYPE_NAME` cannot be qualified and an enum case is matched by bare name,
    so neither has a cross-module spelling and every backend emits them
    unprefixed. Two modules each declaring `Point` therefore emit one definition
    twice into one output: the typed backends reject the redefinition, and the
    Python backend silently kept the last one, so the other module's constructor
    call failed at run time with an argument it had never heard of. Detected here
    because §8 requires an error, not a silent rename.
    """
    owners: dict[str, str] = {}
    for m in modules:
        for kind, name in flat_emitted_names(m.tops):
            where = m.path or m.file.name
            if name in owners and owners[name] != where:
                raise ModuleError(
                    f"modules `{owners[name]}` and `{where}` both declare {kind} "
                    f"`{name}`, which is emitted unqualified and would collide")
            owners[name] = where


def flat_emitted_names(tops) -> list:
    """(kind, name) for every declaration a backend emits without a prefix."""
    out = []
    for n in tops:
        if not isinstance(n, Tree):
            continue
        if n.data in ("defschema", "defenum", "defopaque"):
            for c in n.children:
                if isinstance(c, Token) and c.type == "TYPE_NAME":
                    out.append(("type", str(c)))
                    break
        if n.data == "defenum":
            for c in n.children:
                if isinstance(c, Tree) and c.data == "enum_case":
                    for t in c.children:
                        if isinstance(t, Token) and t.type == "IDENT":
                            out.append(("enum case", str(t)))
                            break
    return out


def top_level_names(tops) -> list:
    out = []
    for n in tops:
        if not isinstance(n, Tree) or n.data not in ("defun", "defschema", "defenum",
                                                     "defopaque", "defextern"):
            continue
        for c in n.children:
            if isinstance(c, Token) and c.type in ("IDENT", "TYPE_NAME", "QUALIFIED"):
                out.append(str(c))
                break
    return out


def single(src: str, p: Lark | None = None) -> Program:
    """A program of one module, for callers that have source and no file."""
    p = p or parser()
    tops = [t.children[0] for t in p.parse(src).children]
    name, exports, imports = _header(tops)
    if imports:
        raise ModuleError("this source imports; load it from a file so imports resolve")
    mod = Loaded(name, Path("<source>"), tops, exports, imports, is_entry=True)
    return Program([mod], {name: mod} if name else {})


if __name__ == "__main__":
    prog = load(Path(sys.argv[1]))
    for m in prog.modules:
        kind = "entry" if m.is_entry else "dep"
        print(f"{kind:<6} {m.path or '<headerless>':<24} {m.file}")
