#!/usr/bin/env python3
"""Readers for prelude.json, which every other consumer must go through.

The vocabulary previously came from regexing the specification's markdown, which
made the closure gate depend on prose formatting. It has one source; reading it
in more than one place is how a second source starts.
"""
import json
from pathlib import Path

PRELUDE = Path(__file__).parent / "prelude.json"


def _data() -> dict:
    return json.loads(PRELUDE.read_text())


def builtins() -> set[str]:
    return {b["name"] for b in _data()["builtins"]}


def signatures() -> dict[str, str]:
    """Name -> the declared type string, e.g. 'N N -> N'."""
    return {b["name"]: b["type"] for b in _data()["builtins"]}


def special_forms() -> set[str]:
    """Grammar productions, not calls; they never reach a `call` node."""
    return {n for group in _data()["special_forms"].values() for n in group}


def type_aliases() -> dict[str, str]:
    return dict(_data()["types"]["aliases"])


def type_names() -> set[str]:
    t = _data()["types"]
    return set(t["primitive"]) | set(t["constructed"]) | set(t["aliases"]) | set(t["unions"])


def unions() -> dict[str, list[str]]:
    """Closed unions the prelude itself declares, as type -> case names. A user
    `defenum` produces the same shape; nothing downstream should care which."""
    return {name: list(cases) for name, cases in _data()["types"]["unions"].items()}


def effectful() -> set[str]:
    """Builtins that touch the world. The marker on a declaration is checked
    against this set, so the vocabulary stays the one place it is recorded."""
    return {b["name"] for b in _data()["builtins"] if b.get("effect")}


# ---------- signature notation ----------
# The `type` field of a builtin is written for a reader ("N N -> N"). The type
# layer reads the same string, so the vocabulary keeps one source rather than
# growing a second, machine-only one beside it.

def _tokens(sig: str) -> list[str]:
    out, i = [], 0
    while i < len(sig):
        c = sig[i]
        if c.isspace():
            i += 1
        elif sig.startswith("->", i):
            out.append("->"); i += 2
        elif sig.startswith("...", i):
            out.append("..."); i += 3
        elif c in "()[]":
            out.append(c); i += 1
        else:
            j = i
            while j < len(sig) and not sig[j].isspace() and sig[j] not in "()[]" \
                    and not sig.startswith("->", j) and not sig.startswith("...", j):
                j += 1
            out.append(sig[i:j]); i = j
    return out


def is_type_var(name: str) -> bool:
    """A single uppercase letter is a variable; every declared type name is longer."""
    return len(name) == 1 and name.isupper()


def parse_signature(sig: str) -> tuple[list[dict], bool, dict]:
    """'(List T) Int64 -> (Option T)' -> (argument types, variadic, return type).

    Types are plain dicts: {"con": name, "args": [...]} or {"var": name} or
    {"fn": [params], "ret": type}.
    """
    toks = _tokens(sig)
    pos = 0

    def peek() -> str | None:
        return toks[pos] if pos < len(toks) else None

    def take() -> str:
        nonlocal pos
        pos += 1
        return toks[pos - 1]

    def one() -> dict:
        t = take()
        if t != "(":
            return {"var": t} if is_type_var(t) else {"con": t, "args": []}
        head = take()
        if head == "fn":
            take()                                  # [
            params = []
            while peek() != "]":
                params.append(one())
            take()                                  # ]
            take()                                  # ->
            ret = one()
            take()                                  # )
            return {"fn": params, "ret": ret}
        args = []
        while peek() != ")":
            args.append(one())
        take()
        return {"con": head, "args": args}

    args, variadic = [], False
    while peek() is not None and peek() != "->":
        args.append(one())
        if peek() == "...":
            take()
            variadic = True
    if peek() == "->":
        take()
    ret = one()
    return args, variadic, ret
