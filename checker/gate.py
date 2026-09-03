#!/usr/bin/env python3
"""Semantic gate: the valid corpus checks clean, every semantic fixture is
rejected FOR THE REASON IT DECLARES.

A fixture that fails for the wrong reason is the failure mode this gate exists
to prevent: the reserved-prefix fixture once "passed" because an unrelated
lexical rule rejected it, which removed the pressure to write the real check
(PCP c-099a). So each fixture names its rule in a leading `"expect:"` note and the
gate asserts that code specifically, not merely that something was reported.
A fixture whose note is `"expect-only:"` asserts further that NOTHING else was
reported, which is what catches a rule that fires beside the resolution failure
its own fix was supposed to remove.

Exit code is the failure count.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from resolve import check_file  # noqa: E402

ROOT = Path(__file__).parent.parent
CORPUS = ROOT / "grammar" / "corpus"
ROOTS = [CORPUS / "modules"]
PACKAGES = ROOT / "packages"
# What `asl check` uses, so a package that passes the CLI passes the gate and a
# package that passes the gate is not resolving through some private path.
PACKAGE_ROOTS = [CORPUS / "modules", PACKAGES, ROOT]


def package_roots(path: Path) -> list[Path]:
    """Search roots for one package source.

    A package's own `src/` is on the path because that is what its imports are
    written against: `packages/asl-parser/tests/reader_test.asl` says
    `:i [(ast :a a)]`, and the module lives at `src/ast.asl`. The test harnesses
    already resolve it that way; the gate has to agree with them or it grades a
    different program than the one that runs."""
    try:
        pkg = PACKAGES / path.relative_to(PACKAGES).parts[0]
    except ValueError:
        pkg = None
    own = [pkg / "src", pkg / "src" / "core", pkg] if pkg is not None else []
    # Every other package's `src/` too: a module's declared name does not match
    # the path an importer writes for it, so `packages/asl-codec` reaches the
    # self-hosted lexer as a bare `lexer` rather than by any package-qualified
    # path. That divergence is a gap in its own right (ROADMAP §6); until it is
    # closed, resolving the way the harnesses and `asl check` already resolve is
    # what keeps this gate grading the program that actually runs.
    siblings = [d / "src" for d in sorted(PACKAGES.iterdir())
                if d.is_dir() and d != pkg and (d / "src").is_dir()]
    return own + siblings + PACKAGE_ROOTS + [path.parent, path.parent.parent]


def expected(path: Path) -> tuple[str | None, bool]:
    """The declared rule and whether it must be the ONLY code reported, read from
    the source text: the first line is a free-standing string note, and reading
    it as text is simpler than reaching into the parse tree.

    A leading `"expect:"` note asserts the code is among those reported, which
    lets a half-implemented rule pass with spurious company — a `rule-4` beside
    a `rule-2` from a resolution the fix forgot. A leading `"expect-only:"` note
    refuses that. It is opt-in because two fixtures predating it legitimately
    report two codes."""
    first = (path.read_text().splitlines() or [""])[0]
    inner = first[1:-1] if (first.startswith('"') and first.endswith('"')) else first
    for marker, exact in (("expect-only:", True), ("expect:", False)):
        if inner.startswith(marker):
            return inner[len(marker):].strip(), exact
    return None, False


def main() -> int:
    failures: list[str] = []
    print(f"{'fixture':<38} {'expected':<11} {'reported':<28} verdict")
    print("-" * 88)

    # Search-path modules are checked too: one that does not check clean would
    # make every rule 9 verdict resting on it worthless.
    clean = sorted((CORPUS / "valid").glob("*.agentscript")) + sorted((CORPUS / "modules").rglob("*.agentscript"))
    for path in clean:
        diags = check_file(path, ROOTS)
        label = str(path.relative_to(CORPUS))
        ok = not diags
        if not ok:
            failures.append(f"{label}: {'; '.join(str(d) for d in diags)}")
        print(f"{label:<38} {'clean':<10} {','.join(d.code for d in diags) or '-':<28} "
              f"{'ok' if ok else 'FAIL'}")

    for path in sorted((CORPUS / "semantic").rglob("*.agentscript")):
        label = str(path.relative_to(CORPUS))
        want, exact = expected(path)
        diags = check_file(path, ROOTS)
        codes = [d.code for d in diags]
        if want is None:
            failures.append(f'{label}: no "expect:" note')
            ok = False
        elif exact:
            ok = set(codes) == {want}
            if not ok:
                failures.append(f"{label}: expected only {want}, got {codes or 'nothing'}")
        else:
            ok = want in codes
            if not ok:
                failures.append(f"{label}: expected {want}, got {codes or 'nothing'}")
        print(f"{label:<38} {(want or '-') + ('!' if exact else ''):<11} "
              f"{','.join(codes) or '-':<28} {'ok' if ok else 'FAIL'}")

    # Everything the repository actually ships. The gate read the corpus alone,
    # so `packages/asl-mem` called `sqrt` and `list-zip-with` — neither of which
    # exists — through every green run the project ever had.
    sources = sorted(PACKAGES.rglob("*.asl")) if PACKAGES.is_dir() else []
    if sources:
        print()
        print(f"{'package source':<58} verdict")
        print("-" * 88)
    for path in sources:
        diags = check_file(path, package_roots(path))
        label = str(path.relative_to(ROOT))
        if diags:
            failures.append(f"{label}: {'; '.join(str(d) for d in diags)}")
        print(f"{label:<58} {'ok' if not diags else 'FAIL'}")

    print()
    for f in failures:
        print("  " + f)
    print(f"\n{len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
