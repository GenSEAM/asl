#!/usr/bin/env python3
"""One escaping of a source string literal, shared by every backend.

The grammar admits a raw newline inside quotes -- `STRING: /"([^"\\]|\\.)*"/`
-- and now that a comment is spelled as a free-standing string, a note running
to a second line is ordinary source. Each backend passed the token through
verbatim, so the raw newline landed between the target's quotes: Rust takes a
multi-line literal and Python, TypeScript and Go reject one, which meant three
of four emitted source their own compiler refused.

Only the raw control characters the grammar let through are rewritten, and only
the three all four targets spell identically. Anything below them diverges per
target (`\\x08` against `\\u{8}`), so a shared helper cannot honestly claim it.
"""

# A backslash escape already in the source is target spelling and passes through;
# these are the characters that reached the quotes as themselves.
RAW = {"\n": "\\n", "\r": "\\r", "\t": "\\t"}


def string_literal(text: str) -> str:
    """A STRING token's source text, safe to paste between any target's quotes."""
    return "".join(RAW.get(ch, ch) for ch in text)
