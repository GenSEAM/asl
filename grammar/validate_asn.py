#!/usr/bin/env python3
"""Conformance gate for the ASN grammar.

Normative source: docs/ASN_SPEC.md.

Three checks, each of which has a failure mode the others cannot see:

  1. corpus/asn/valid must parse, corpus/asn/invalid must be rejected, and
     corpus/asn/semantic must PARSE — those fixtures violate rules that are not
     context-free (duplicate keys, `(:ref N)` resolution, table shape), and a
     grammar that rejected them would be over-tight. The other half of their
     verdict is packages/asl-codec's, which must reject each under the code its
     `; expect:` header names.

  2. Terminal drift. `asn.lark` carries a block copied from `agentscript.lark`,
     and ASN's entire claim to be "layered on Core's lexical structure" rests on
     that copy staying a copy. A hand-copied regex is exactly the thing that
     drifts silently, so the two texts are compared character for character.

  3. Every valid fixture carries a `; canonical:` header — the hand-written
     canonical rendering of its own body. This gate checks nothing about it;
     packages/asl-codec's driver asserts the writer reproduces it. It is checked
     for PRESENCE here so a fixture cannot be added without one and quietly skip
     the round-trip property.

  4. Every ```asn example in the three ASN documents. The previous version of
     docs/DATA_REPRESENTATION_MATRIX.md specified roughly a dozen constructs
     that parsed under neither grammar, for months, because nothing read them.
     Core blocks in those same files belong to tools/doc_examples.py; this gate
     only asserts that no ASN payload is hiding in a ```lisp fence, where that
     gate would grade it against the wrong language.

Exit code is the failure count, so CI can gate on it.
"""
import re
import sys
from pathlib import Path

from lark import Lark
from lark.exceptions import LarkError

ROOT = Path(__file__).parent
ASN_GRAMMAR = ROOT / "asn.lark"
CORE_GRAMMAR = ROOT / "agentscript.lark"
CORPUS = ROOT / "corpus" / "asn"

SHARED_BEGIN = "// BEGIN SHARED TERMINALS"
SHARED_END = "// END SHARED TERMINALS"

_parser: Lark | None = None


def parser() -> Lark:
    global _parser
    if _parser is None:
        _parser = Lark(ASN_GRAMMAR.read_text(), start="start", parser="earley",
                       ambiguity="resolve", propagate_positions=True)
    return _parser


def accepts(text: str) -> tuple[bool, str]:
    try:
        parser().parse(text)
        return True, ""
    except LarkError as exc:
        return False, str(exc).splitlines()[0]


def shared_terminals() -> list[str]:
    """The copied terminal definitions in asn.lark, as non-empty non-comment lines."""
    src = ASN_GRAMMAR.read_text()
    # From the end of the marker LINE: the marker carries a trailing comment that
    # would otherwise be read as the block's first terminal.
    start = src.index("\n", src.index(SHARED_BEGIN))
    end = src.index(SHARED_END)
    block = src[start:end]
    return [ln.strip() for ln in block.splitlines()
            if ln.strip() and not ln.strip().startswith("//")]


def terminal_drift() -> list[str]:
    """Each shared line must appear verbatim in agentscript.lark."""
    core = CORE_GRAMMAR.read_text().splitlines()
    core_lines = {ln.strip() for ln in core}
    problems = []
    lines = shared_terminals()
    print(f"\n{'shared terminal':<22} verdict")
    print("-" * 66)
    for line in lines:
        name = line.split(":", 1)[0].split(".", 1)[0]
        ok = line in core_lines
        print(f"{name:<22} {'ok' if ok else 'FAIL'}")
        if not ok:
            problems.append(f"terminal drift/{name}: not verbatim in agentscript.lark: {line}")
            print(f"{'':<22} -> {line}")
    if not lines:
        problems.append("terminal drift: the shared block is empty")
    return problems


DOCS = [
    ROOT.parent / "docs" / "ASN_SPEC.md",
    ROOT.parent / "docs" / "DATA_REPRESENTATION_MATRIX.md",
    ROOT.parent / "docs" / "CONTEXT_ECONOMY_GUIDELINES.md",
]

DECL_HEADS = {"module", "dfs", "dfe", "df", "defschema", "defenum", "defun",
              "schema", "enum", "def"}


def head_of(form: str) -> str:
    body = form[1:].lstrip()
    return body.split(None, 1)[0].rstrip(")]}") if body else ""


OPEN = "([{"
CLOSE = ")]}"

# tools/doc_examples.py grades every ```lisp and ```agentscript block as Core
# AgentScript. ASN payloads are fenced ```asn, which that gate ignores by design
# and this one owns: the tag says which language a block is in, so neither gate
# has to guess from a form's head and a mis-tagged block fails somewhere rather
# than passing everywhere.
ASN_FENCE = re.compile(r"^[ \t]*```asn\n(.*?)^[ \t]*```", re.M | re.S)
CORE_FENCE = re.compile(r"^[ \t]*```(?:lisp|agentscript)\n(.*?)^[ \t]*```", re.M | re.S)
OPT_OUT = re.compile(r"<!--\s*not-agentscript:\s*(.+?)\s*-->\s*$", re.M)


def split_forms(block: str) -> list[str]:
    """A fenced block split into its top-level balanced forms.

    A block often shows two or three payloads under one fence, and each is its
    own document. String bodies and line comments are skipped so a bracket
    inside either cannot move the depth.
    """
    forms, depth, start, i = [], 0, None, 0
    in_string = False
    while i < len(block):
        c = block[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == ";":
            i = block.find("\n", i)
            if i == -1:
                break
            continue
        elif c in OPEN:
            if depth == 0:
                start = i
            depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth == 0 and start is not None:
                forms.append(block[start:i + 1])
                start = None
        i += 1
    return forms


def opted_out(text: str, fence_start: int) -> bool:
    """True when the line directly above the fence carries the opt-out marker."""
    before = text[:fence_start]
    line = before.rsplit("\n", 2)[-2] if before.count("\n") >= 2 else ""
    return bool(OPT_OUT.search(line))


def doc_examples() -> list[str]:
    """Every ASN example in the ASN documents parses under grammar/asn.lark.

    Core blocks in the same files are tools/doc_examples.py's, not this gate's:
    two parsers grading the same block is how they come to disagree about it.
    """
    problems = []
    print(f"\n{'document example':<38} {'asn':<6} {'core':<6} verdict")
    print("-" * 66)
    for doc in DOCS:
        if not doc.exists():
            problems.append(f"doc examples/{doc.name}: missing")
            continue
        text = doc.read_text()
        asn_forms = [f for m in ASN_FENCE.finditer(text) for f in split_forms(m.group(1))]
        core_blocks = [m for m in CORE_FENCE.finditer(text) if not opted_out(text, m.start())]
        bad = []
        for form in asn_forms:
            try:
                parser().parse(form)
            except LarkError as exc:
                bad.append(f"asn.lark: {form.splitlines()[0][:44]} -> "
                           f"{str(exc).splitlines()[0]}")
        # A payload fenced as Core would be graded by the wrong parser and pass
        # there for the wrong reason, so the ASN documents must not carry one.
        for m in core_blocks:
            for form in split_forms(m.group(1)):
                if head_of(form) not in DECL_HEADS:
                    bad.append(f"fenced ```lisp but is not a declaration, so it is "
                               f"an ASN payload in a Core fence: "
                               f"{form.splitlines()[0][:44]}")
        if not asn_forms:
            bad.append("no ```asn examples found")
        print(f"{doc.name:<38} {len(asn_forms):<6} {len(core_blocks):<6} "
              f"{'ok' if not bad else 'FAIL'}")
        for b in bad:
            problems.append(f"doc examples/{doc.name}: {b}")
            print(f"{'':<38} -> {b}")
    return problems


PROJECTION_LOCK = ROOT.parent / "bench" / "token_projection.lock"


def projection_claim() -> list[str]:
    """docs/CONTEXT_ECONOMY_GUIDELINES.md §2 rests on one number staying zero.

    The section argues that abbreviating an identifier saves no tokens. That
    claim is not this gate's to prove — bench/token_projection.py measures it —
    but a document asserting it must not outlive it. Only the invariant is
    checked: the totals move whenever a corpus fixture is edited, which is
    exactly why the prose quotes none of them.
    """
    if not PROJECTION_LOCK.exists():
        return ["projection claim: bench/token_projection.lock is missing"]
    import json
    pct = json.loads(PROJECTION_LOCK.read_text()).get("token_saving_pct")
    ok = pct == 0.0
    print(f"\n{'projection claim':<38} {'0.00%':<8} {'ok' if ok else 'FAIL'}")
    if ok:
        return []
    return [f"projection claim: token_saving_pct is {pct}, not 0.0 — "
            f"CONTEXT_ECONOMY_GUIDELINES.md §2 says abbreviation saves no tokens"]


def canonical_header(path: Path) -> str | None:
    m = re.search(r"^; canonical: (.*)$", path.read_text(), re.M)
    return m.group(1) if m else None


def expect_header(path: Path) -> str | None:
    m = re.search(r"^; expect: (\S+)\s*$", path.read_text(), re.M)
    return m.group(1) if m else None


def main() -> int:
    if not ASN_GRAMMAR.exists():
        print(f"ASN grammar not found at {ASN_GRAMMAR}", file=sys.stderr)
        return 1

    failures: list[str] = []

    cases = [(p, True) for p in sorted((CORPUS / "valid").glob("*.asn"))]
    cases += [(p, False) for p in sorted((CORPUS / "invalid").glob("*.asn"))]
    semantic = sorted((CORPUS / "semantic").glob("*.asn"))
    cases += [(p, True) for p in semantic]

    if not cases:
        print(f"no fixtures under {CORPUS}", file=sys.stderr)
        return 1

    print(f"{'fixture':<38} {'asn.lark':<10} verdict")
    print("-" * 66)

    for path, should_parse in cases:
        label = str(path.relative_to(CORPUS))
        ok, why = accepts(path.read_text())
        problems = []
        if ok != should_parse:
            problems.append("accepted invalid" if ok else why)

        # A valid fixture without its hand-written canonical rendering would
        # parse here and never have its round trip asserted anywhere.
        if path.parent.name == "valid" and canonical_header(path) is None:
            problems.append("missing `; canonical:` header")
        if path.parent.name == "semantic" and expect_header(path) is None:
            problems.append("missing `; expect:` header")

        if problems:
            failures.append(label)
        print(f"{label:<38} {('parse' if ok else 'reject'):<10} "
              f"{'ok' if not problems else 'FAIL'}")
        for p in problems:
            print(f"{'':<38} -> {p}")

    failures += terminal_drift()
    failures += doc_examples()
    failures += projection_claim()

    if semantic:
        print(f"\nsemantic-only fixtures (parse by design, rejected by "
              f"packages/asl-codec): "
              f"{', '.join(p.name for p in semantic)}")
    print(f"\n{len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
