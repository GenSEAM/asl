"""The foreign-boundary rule, in one place.

Three transpilers have to agree on which modules they may emit, and three copies
of that rule are three chances to disagree — the same argument
`prelude/generate.py` makes about the vocabulary. It had already started: two
backends refused any `defopaque` outright with a message saying the module was
for another target, which would be the wrong reason for a module that named
theirs.

Two conditions live here, and they are deliberately distinct:

* **`TargetMismatch`** — the module names an ecosystem this backend does not
  emit. Nothing is missing; the module is simply not for this target, and
  refusing it is correct behaviour that `backend/check_corpus.py` asserts.
* **`NotLowered`** — the module names *this* ecosystem, and the backend cannot
  emit it yet. That is a gap in the backend, not a property of the module.

Collapsing them would report an unimplemented backend as a well-formed refusal.
"""
from lark import Token, Tree


class TargetMismatch(Exception):
    """The module's foreign declarations name another ecosystem."""


class NotLowered(Exception):
    """The declarations are for this target, and this backend cannot emit them."""


def declared_name(node) -> str:
    """The name a `defextern` or `defopaque` declares.

    Found by token type rather than by child index: the head keyword and the
    option list both sit in `children`, and an index would move the next time the
    form grows an optional part.
    """
    for c in node.children:
        if isinstance(c, Token) and c.type in ("QUALIFIED", "TYPE_NAME"):
            return str(c)
    return "<unnamed>"


def extern_target(node) -> str | None:
    """The `:target` of a `defextern`, or None when it declares none."""
    for o in node.children:
        if isinstance(o, Tree) and o.data == "extern_opt" and str(o.children[0]) == ":target":
            return str(o.children[1])[1:]
    return None


def extern_symbol(node) -> str | None:
    """The `:symbol` override, for a host name §8 mangling cannot reproduce."""
    for o in node.children:
        if isinstance(o, Tree) and o.data == "extern_opt" and str(o.children[0]) == ":symbol":
            return str(o.children[1]).strip('"')
    return None


def foreign_decls(tops) -> list:
    """Every declaration that makes a module belong to one ecosystem."""
    return [n for n in tops if n.data in ("defextern", "defopaque")]


def check_target(tops, target: str, *, lowers_foreign: bool) -> None:
    """Refuse a module this backend must not or cannot emit.

    `lowers_foreign` says whether this backend can emit foreign declarations at
    all. A backend that cannot still has to distinguish "not mine" from "mine but
    unimplemented", because only the first is a correct refusal.
    """
    externs = [n for n in tops if n.data == "defextern"]
    for n in externs:
        name = declared_name(n)
        want = extern_target(n)
        if want is None:
            raise TargetMismatch(f"{name} declares no :target, so it names no ecosystem")
        if want != target:
            raise TargetMismatch(
                f"{name} is declared :target :{want}; this backend emits {target}")

    if not lowers_foreign and foreign_decls(tops):
        kind = "defextern" if externs else "defopaque"
        raise NotLowered(
            f"this module's {kind} declarations are for :{target}, "
            f"which this backend does not lower yet")
