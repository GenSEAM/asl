#!/usr/bin/env python3
"""Semantic gate: the valid corpus checks clean, every semantic fixture is
rejected FOR THE REASON IT DECLARES.

A fixture that fails for the wrong reason is the failure mode this gate exists
to prevent: the reserved-prefix fixture once "passed" because an unrelated
lexical rule rejected it, which removed the pressure to write the real check
(PCP c-099a). So each fixture names its rule in a `; expect:` header and the
gate asserts that code specifically, not merely that something was reported.
A fixture whose header is `; expect-only:` asserts further that NOTHING else was
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


def expected(path: Path) -> tuple[str | None, bool]:
    """The declared rule and whether it must be the ONLY code reported, read from
    the source text: comments do not survive parsing, so this cannot come off the
    tree.

    `; expect:` asserts the code is among those reported, which lets a
    half-implemented rule pass with spurious company — a `rule-4` beside a
    `rule-2` from a resolution the fix forgot. `; expect-only:` refuses that. It
    is opt-in because two fixtures predating it legitimately report two codes."""
    first = (path.read_text().splitlines() or [""])[0]
    for marker, exact in (("; expect-only:", True), ("; expect:", False)):
        if marker in first:
            return first.split(marker, 1)[1].strip(), exact
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
            failures.append(f"{label}: no `; expect:` header")
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

    print()
    for f in failures:
        print("  " + f)
    print(f"\n{len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
