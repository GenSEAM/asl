#!/usr/bin/env python3
"""The canonical printer for AgentScript: parse with the Lark grammar, print from the tree.

Printing from the tree rather than editing text is what makes the output canonical
and the delimiters balanced by construction — there is no path by which this
emits a program that does not parse, only one by which it refuses to start.

Comments are the one thing a tree does not carry: `grammar/as-lang.lark` ends with
`%ignore COMMENT`, and the corpus uses comments to carry the intent of a fixture.
They are recovered by a second, independent pass — a string-aware scan of the
source that records every comment with its position — and re-attached during
printing by position. A node whose source span contains a comment is therefore
never printed flat, because a comment has to end its line.

Diagnostics are the checker's `Diagnostic` (fields `code`, `message`, `line`, `col`,
`path`); the formatter's former `rule` field is the checker's `code: str`, so a parse
failure here reads the same as one from `checker/check.py`.
"""
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from lark import Lark, Token, Tree
from lark.exceptions import UnexpectedInput, LarkError

ROOT = Path(__file__).parent.parent.parent

# One parser: `grammar/parse.py` owns construction and `kids()`; the formatter
# reuses them rather than keeping a third copy of the Lark arguments, so a change
# to the parse configuration can never drift away from the rest of the toolchain.
sys.path.insert(0, str(ROOT / "grammar"))
from parse import parser as _grammar_parser, FORM_KW as _TOOLCHAIN_FORM_KW  # noqa: E402

# The diagnostic type is the checker's (`checker/resolve.Diagnostic`), not a local
# copy. `resolve.py` imports its siblings (`collect`, `types_`) flat, so its
# directory goes on the path the same way `checker/check.py` puts it there.
sys.path.insert(0, str(ROOT / "checker"))
from resolve import Diagnostic  # noqa: E402

# Soft target: a signature or a long atom overruns it rather than break. 80 is the
# column the corpus was written to — its three wrapped :export lists each break at
# the first name that would cross it — and it is the width with the least churn
# against the hand-written tree.
WIDTH = 80

# A signature gets a wider budget than a body: a parameter list is a table the
# reader scans in one go, and the corpus writes them past 80 as a matter of course —
# 95 columns is its widest unwrapped one, 114 the single one it chose to wrap.
SIGNATURE_WIDTH = 100

# Keyword tokens the grammar keeps in the child list. They are re-emitted from the
# rule's shape, so the printer drops them the way `kids()` does in the backends.
# BANG is excluded even though `parse.py` filters it: the printer must emit the `!`
# (an effect marker on `defun`/`fn`), so it cannot be pulled out of the child list.
FORM_KW = _TOOLCHAIN_FORM_KW - {"BANG"}

# Forms that break however short they are. A declaration's signature is the part a
# reader scans; `match` and `cond` are tables, and the corpus never puts one on a
# single line. `if` joins them because the language has no one-armed conditional —
# putting each of the three parts on its own line is how that reads on the page.
ALWAYS_BROKEN = {"module_decl", "defschema", "defenum", "defun", "defentry",
                 "defextern", "defopaque", "match_form", "cond_form", "if_form",
                 "let_form"}

# Keyword options whose payload is a bracketed list rather than a single value.
BRACKETED = {":export", ":import", ":extern", ":effects"}

# Pattern heads that are spelled with delimiters: `(none)`, `(cons h t)`. The rest
# of the pattern alternatives are bare.
DELIMITED_PATTERN_HEADS = {"OK", "ERR", "SOME", "NONE", "LIST", "CONS", "PAIR"}

# Rules whose source spelling opens with a delimiter, so the character one column left
# of their first token is their own opener. `type` and `pattern` are absent because
# each has both a delimited and a bare alternative; `delimited()` decides those, and
# everything else — `expr`, `module_opt`, `ctor_arg` — begins with a token of its own.
DELIMITED = {"module_decl", "import_spec", "extern_spec", "defschema", "field",
             "defun", "defentry", "defopaque", "defextern", "defenum", "enum_case",
             "param", "params", "type_params", "let_form", "binding", "if_form",
             "cond_form", "cond_clause", "else_clause", "match_form", "match_arm",
             "try_form", "fn_form", "ctor", "field_access", "call", "enum_pattern"}


def delimited(n) -> bool:
    """Whether `n`'s own opening delimiter sits one column left of its first token."""
    if not isinstance(n, Tree):
        return False
    if n.data in DELIMITED:
        return True
    if n.data == "type":
        return len(n.children) > 1
    if n.data == "pattern":
        head = n.children[0]
        return isinstance(head, Token) and head.type in DELIMITED_PATTERN_HEADS
    return False


class FormatError(Exception):
    def __init__(self, diag: Diagnostic):
        super().__init__(str(diag))
        self.diag = diag


# ---------- comments ----------

@dataclass(frozen=True)
class Comment:
    line: int
    col: int
    text: str
    own_line: bool          # nothing but whitespace precedes it on its line


_STRING_OR_COMMENT = re.compile(r'"(?:[^"\\]|\\.)*"|;[^\n]*')


def scan_comments(src: str) -> list[Comment]:
    """Every comment, with its 1-based line and column.

    Run over the raw text rather than the tree because the tree does not have
    them. The alternation puts strings first so a `;` inside a string literal is
    consumed as part of the string and never mistaken for a comment.
    """
    starts = [0]
    for i, ch in enumerate(src):
        if ch == "\n":
            starts.append(i + 1)
    out = []
    for mt in _STRING_OR_COMMENT.finditer(src):
        if not mt.group().startswith(";"):
            continue
        line = _bisect_line(starts, mt.start())
        col = mt.start() - starts[line - 1] + 1
        own = src[starts[line - 1]:mt.start()].strip() == ""
        out.append(Comment(line, col, mt.group().rstrip(), own))
    return out


def _bisect_line(starts: list[int], off: int) -> int:
    lo, hi = 0, len(starts) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if starts[mid] <= off:
            lo = mid
        else:
            hi = mid - 1
    return lo + 1


# ---------- parsing ----------

def parser() -> Lark:
    return _grammar_parser()


def parse(src: str, path: str) -> Tree:
    # Balance is checked before the parser runs. Earley reports an unclosed `(` as an
    # unexpected end of input at line -1, which names the end of the file rather than
    # the delimiter that is actually wrong; the scan below names the delimiter.
    unbalanced = scan_delimiters(src, path)[0]
    if unbalanced is not None:
        raise FormatError(unbalanced)
    try:
        return parser().parse(src)
    except UnexpectedInput as exc:
        # Reported under the checker's `parse` code so a bad file reads the same
        # here as through `checker/resolve.check_file`.
        raise FormatError(Diagnostic("parse", f"does not parse: {_expectation(exc)}",
                                     max(exc.line, 1), max(exc.column, 1), path)) from None
    except LarkError as exc:
        first = str(exc).splitlines()[0]
        raise FormatError(Diagnostic("parse", f"does not parse: {first}",
                                     1, 1, path)) from None


def _expectation(exc: UnexpectedInput) -> str:
    got = getattr(exc, "token", None)
    if got is not None and str(got) == "":
        return "unexpected end of input"
    if got is not None:
        return f"unexpected `{got}`"
    ch = getattr(exc, "char", None)
    return f"unexpected `{ch}`" if ch else "unexpected input"


_OPEN = {"(": ")", "[": "]", "{": "}"}
_CLOSE = {v: k for k, v in _OPEN.items()}
_DELIM_SKIP = re.compile(r'"(?:[^"\\]|\\.)*"|;[^\n]*')


def scan_delimiters(src: str, path: str) -> tuple[Diagnostic | None, dict]:
    """(first imbalance, opener position -> position just past its closer).

    The map is what gives a form its true extent. Lark's `meta` ends a node at its
    last child, which is before the closing delimiter, so a comment written between
    the last child and the `)` looks as if it were outside the form; the printer would
    then hoist it out on the first pass and align differently on the second.
    """
    skip = [(m.start(), m.end()) for m in _DELIM_SKIP.finditer(src)]
    line, col, s, stack, ends = 1, 1, 0, [], {}
    i = 0
    while i < len(src):
        while s < len(skip) and skip[s][1] <= i:
            s += 1
        inside = s < len(skip) and skip[s][0] <= i < skip[s][1]
        ch = src[i]
        if not inside:
            if ch in _OPEN:
                stack.append((ch, line, col))
            elif ch in _CLOSE:
                if not stack:
                    return Diagnostic("parse", f"`{ch}` closes nothing that is open",
                                      line, col, path), ends
                op, ol, oc = stack.pop()
                if _OPEN[op] != ch:
                    return Diagnostic("parse",
                                      f"`{ch}` closes the `{op}` opened at {ol}:{oc}, "
                                      f"which wants `{_OPEN[op]}`", line, col, path), ends
                ends[(ol, oc)] = (line, col + 1)
        i += 1
        if ch == "\n":
            line, col = line + 1, 1
        else:
            col += 1
    if stack:
        op, ol, oc = stack[0]
        return Diagnostic("parse", f"`{op}` is never closed", ol, oc, path), ends
    return None, ends


def check_balance(src: str, path: str) -> Diagnostic | None:
    """The first unbalanced delimiter, named at its own position."""
    return scan_delimiters(src, path)[0]


# ---------- tree helpers ----------

def kids(node: Tree) -> list:
    return [k for k in node.children
            if not (isinstance(k, Token) and k.type in FORM_KW)]


def unwrap(n):
    """Strip the single-child `expr`/`toplevel` wrappers the grammar inserts."""
    while isinstance(n, Tree) and n.data in ("expr", "toplevel") and len(n.children) == 1:
        n = n.children[0]
    return n


def span(n) -> tuple[int, int, int, int] | None:
    """(start_line, start_col, end_line, end_col), 1-based, or None if unknown."""
    if isinstance(n, Token):
        if n.line is None:
            return None
        return (n.line, n.column, n.end_line, n.end_column)
    meta = n.meta
    if getattr(meta, "empty", True):
        marks = [span(c) for c in n.children]
        marks = [m for m in marks if m]
        if not marks:
            return None
        return (marks[0][0], marks[0][1], marks[-1][2], marks[-1][3])
    return (meta.line, meta.column, meta.end_line, meta.end_column)


# ---------- the printer ----------

class Printer:
    def __init__(self, comments: list[Comment], ends: dict, width: int = WIDTH):
        self.pending = sorted(comments, key=lambda c: (c.line, c.col))
        self.ends = ends
        self.width = width
        self.emitted = 0
        self._rigid_cache: dict[int, bool] = {}

    def extent(self, n) -> tuple[int, int] | None:
        """Where the form ends including its closing delimiter, when there is one.

        A node's opening delimiter sits one column left of its first kept token, so
        the scan's map is addressed from there. Everything between the last child and
        that closer — a comment, in practice — belongs to this form.
        """
        sp = span(n)
        if sp is None:
            return None
        if not delimited(n):
            return (sp[2], sp[3])
        return self.ends.get((sp[0], sp[1] - 1), (sp[2], sp[3]))

    # -- comment plumbing --

    def take_before(self, mark: tuple[int, int] | None) -> list[Comment]:
        """Comments positioned strictly before `mark`, removed from the queue."""
        if mark is None:
            return []
        out = []
        while self.pending and (self.pending[0].line, self.pending[0].col) < mark:
            out.append(self.pending.pop(0))
        self.emitted += len(out)
        return out

    def take_trailing(self, mark: tuple[int, int] | None,
                      limit: tuple[int, int] | None = None) -> list[Comment]:
        """Comments on `mark`'s line and after its column — a trailing comment.

        `limit` is where the next sibling starts. Without it a comment written after
        the *last* item of a filled line would be claimed by the *first*, and the two
        would swap places every time the file was formatted again.
        """
        if mark is None:
            return []
        out = []
        while self.pending and self.pending[0].line == mark[0] \
                and self.pending[0].col >= mark[1] and not self.pending[0].own_line \
                and (limit is None or (self.pending[0].line, self.pending[0].col) < limit):
            out.append(self.pending.pop(0))
        self.emitted += len(out)
        return out

    def holds_comment(self, n) -> bool:
        sp = span(n)
        if sp is None:
            return False
        lo, hi = (sp[0], sp[1]), self.extent(n)
        return any(lo < (c.line, c.col) < hi for c in self.pending)

    # -- layout primitives --

    def fits(self, n, col: int) -> bool:
        if self.rigid(n) or self.holds_comment(n):
            return False
        return col + len(self.flat(n)) <= self.width

    def rigid(self, n) -> bool:
        """Whether `n` encloses a form that always breaks.

        The test has to reach the whole subtree: a one-line `match` arm whose body
        is a `let` would otherwise flatten the `let` on its way past.
        """
        key = id(n)
        hit = self._rigid_cache.get(key)
        if hit is None:
            hit = isinstance(n, Tree) and (n.data in ALWAYS_BROKEN
                                           or any(self.rigid(c) for c in n.children))
            self._rigid_cache[key] = hit
        return hit

    def lines_before(self, mark, col: int) -> list[str]:
        return [" " * col + c.text for c in self.take_before(mark)]

    # -- flat rendering --

    def flat(self, n) -> str:
        if isinstance(n, Token):
            return str(n)
        d = n.data
        k = kids(n)
        if d == "expr" and len(n.children) == 1:
            return self.flat(n.children[0])
        if d in ("literal", "mod_path", "toplevel") and len(k) == 1:
            return self.flat(k[0])
        if d == "type_params":
            return "{" + " ".join(self.flat(t) for t in k) + "}"
        if d == "params":
            return "[" + " ".join(self.flat(p) for p in k) + "]"
        if d == "param":
            return "(" + " ".join(self.flat(x) for x in k) + ")"
        if d == "type":
            return self.flat(k[0]) if len(k) == 1 else \
                "(" + " ".join(self.flat(x) for x in k) + ")"
        if d == "module_decl":
            return "(module " + " ".join(self.flat(x) for x in k) + ")"
        if d == "module_opt":
            return self._flat_kw_opt(n)
        if d == "import_spec":
            return f"({self.flat(k[0])} :as {self.flat(k[1])})"
        if d == "extern_spec":
            return f"({self.flat(k[0])} {self.flat(k[1])} :as {self.flat(k[2])})"
        if d == "defschema":
            return "(defschema " + " ".join(self.flat(x) for x in k) + ")"
        if d == "field":
            return "(:field " + " ".join(self.flat(x) for x in k) + ")"
        if d == "field_opt":
            return self._flat_kw_opt(n)
        if d == "defun":
            return "(defun " + self._flat_signature(k) + ")"
        if d == "defentry":
            return "(defentry " + self._flat_signature(k) + ")"
        if d == "defextern":
            return "(defextern " + self._flat_signature(k) + ")"
        if d == "decl_opt" or d == "extern_opt":
            return self._flat_kw_opt(n)
        if d == "defopaque":
            return f"(defopaque {self.flat(k[0])} :doc {self.flat(k[1])})"
        if d == "defenum":
            return "(defenum " + " ".join(self.flat(x) for x in k) + ")"
        if d == "enum_case":
            name, ps, doc = k[0], k[1:-1], k[-1]
            return (f"(:case {self.flat(name)} "
                    f"[{' '.join(self.flat(p) for p in ps)}] {self.flat(doc)})")
        if d == "let_form":
            binds = [x for x in k if isinstance(x, Tree) and x.data == "binding"]
            body = [x for x in k if x not in binds]
            return ("(let [" + " ".join(self.flat(b) for b in binds) + "] "
                    + " ".join(self.flat(x) for x in body) + ")")
        if d == "binding":
            return f"({self.flat(k[0])} {self.flat(k[1])})"
        if d == "if_form":
            return "(if " + " ".join(self.flat(x) for x in k) + ")"
        if d == "cond_form":
            return "(cond " + " ".join(self.flat(x) for x in k) + ")"
        if d in ("cond_clause", "match_arm"):
            return "(" + " ".join(self.flat(x) for x in k) + ")"
        if d == "else_clause":
            return "(:else " + " ".join(self.flat(x) for x in k) + ")"
        if d == "match_form":
            return "(match " + " ".join(self.flat(x) for x in k) + ")"
        if d == "enum_pattern":
            return "(" + " ".join(self.flat(x) for x in k) + ")"
        if d == "pattern":
            return self._flat_pattern(n)
        if d == "try_form":
            return f"(try {self.flat(k[0])})"
        if d == "fn_form":
            return "(fn " + self._flat_signature(k) + ")"
        if d == "ctor":
            return "(" + " ".join(self.flat(x) for x in k) + ")"
        if d == "ctor_arg":
            return f"{self.flat(n.children[0])} {self.flat(n.children[1])}"
        if d == "field_access":
            return f"({self.flat(n.children[0])} {self.flat(n.children[1])})"
        if d == "call":
            return "(" + " ".join(self.flat(x) for x in n.children) + ")"
        if d == "fn_params":
            return "[" + " ".join(self.flat(x) for x in k) + "]"
        if d == "fn_param":
            # Bare `IDENT`, or the annotated `(IDENT type)` form.
            return self.flat(k[0]) if len(k) == 1 \
                else "(" + " ".join(self.flat(x) for x in k) + ")"
        if d == "doc_opt":
            return ":doc " + self.flat(k[0])
        raise FormatError(Diagnostic("internal", f"no printing rule for `{d}`", 0, 0, ""))

    def _flat_kw_opt(self, n: Tree) -> str:
        """`:doc "..."`, `:effects [a b]`, `:target :py` — a keyword and its payload."""
        head = str(n.children[0])
        rest = n.children[1:]
        if head in BRACKETED:
            return f"{head} [" + " ".join(self.flat(x) for x in rest) + "]"
        return f"{head} " + " ".join(self.flat(x) for x in rest)

    def _flat_signature(self, k: list) -> str:
        """`{T} name [params] -> Type ...` — the shared shape of every callable."""
        out = []
        for x in k:
            if isinstance(x, Tree) and x.data == "type":
                out.append("->")
            out.append(self.flat(x))
        return " ".join(out)

    def _flat_pattern(self, n: Tree) -> str:
        head = n.children[0]
        if isinstance(head, Token) and head.type in DELIMITED_PATTERN_HEADS:
            return "(" + " ".join(self.flat(x) for x in n.children) + ")"
        return self.flat(head)

    # -- broken rendering --

    def emit(self, n, col: int) -> str:
        """`n` rendered starting at column `col`; later lines carry their own indent."""
        if self.fits(n, col):
            return self.flat(n)
        n = unwrap(n)
        if isinstance(n, Token):
            return str(n)
        d, k = n.data, kids(n)
        handler = getattr(self, f"_break_{d}", None)
        if handler is None:
            return self.flat(n)
        return handler(n, k, col)

    def _stack(self, head: str, parts: list, col: int, indent: int,
               close_after: int = 0, node=None) -> str:
        """`head` on one line, then each part on its own line at `indent`.

        `close_after` is how many `)` follow the last part; the caller's own closer
        is included so a declaration never leaves a paren on a line of its own —
        unless a comment has claimed the end of that line, which is the one case
        where a paren of its own is the only spelling that still parses.
        """
        lines, sealed = [head], False
        for i, p in enumerate(parts):
            lines += self.lines_before(_start(p), indent)
            lines.append(" " * indent + self.emit(p, indent))
            sealed = False
            nxt = _start(parts[i + 1]) if i + 1 < len(parts) else None
            for c in self.take_trailing(self.extent(p), nxt):
                lines[-1] += " " + c.text
                sealed = True
        if node is not None:
            tail = self.lines_before(self.extent(node), indent)
            lines += tail
            sealed = sealed or bool(tail)
        return self._close("\n".join(lines), sealed, col, ")" * close_after)

    def _close(self, text: str, sealed: bool, col: int, closers: str) -> str:
        """Append closing delimiters, or start a line for them if a comment is in the way."""
        if not closers:
            return text
        return text + ("\n" + " " * col + closers if sealed else closers)

    def _fill(self, items: list, acol: int) -> tuple[str, bool]:
        """Items packed greedily onto lines, every continuation line starting at `acol`.

        Filling rather than one-item-per-line is what the corpus does with a long
        `(str ...)` or `:export [...]`, and it stays canonical because the packing
        depends on nothing but the tree, the column and the width. An item that
        cannot be flattened takes a line of its own, so a nested `fn` or `match`
        never has an unrelated argument trailing off its last line.

        The second half of the result says whether the last line ends in a comment,
        which the caller needs before it appends its closing delimiter.
        """
        lines: list[str] = []
        cur, sealed, blocked = "", False, False

        def flush():
            nonlocal cur
            lines.append(cur)
            cur = ""

        for i, it in enumerate(items):
            pre = [c.text for c in self.take_before(_start(it))]
            if pre:
                if cur:
                    flush()
                lines += pre
                sealed = False
            if cur and not sealed and not blocked and self.fits(it, acol + len(cur) + 1):
                cur += " " + self.flat(it)
            else:
                if cur:
                    flush()
                    sealed = False
                cur = self.emit(it, acol)
            nxt = _start(items[i + 1]) if i + 1 < len(items) else None
            trailing = self.take_trailing(self.extent(it), nxt)
            if trailing:
                cur += " " + " ".join(c.text for c in trailing)
                sealed = True
            if "\n" in cur:
                # One argument that spans lines puts the whole list in block mode:
                # packing the tail onto its last line hides where that argument ends.
                blocked = True
                flush()
        if cur:
            flush()
        return ("\n" + " " * acol).join(lines), sealed

    def _aligned(self, rows: list[list[str]], col: int, budget: int) -> list[str] | None:
        """One line per row with its leading cells padded to a common width.

        Returns None when any row would overrun, so the decision is a function of
        the tree alone and re-formatting cannot flip it.
        """
        if not rows:
            return None
        widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]) - 1)]
        out = []
        for r in rows:
            cells = [c.ljust(w) for c, w in zip(r[:-1], widths)] + [r[-1]]
            line = "(" + " ".join(cells).rstrip() + ")"
            if col + len(line) > budget:
                return None
            out.append(line)
        return out

    # declarations -------------------------------------------------------

    def _break_module_decl(self, n, k, col):
        return self._stack(f"(module {self.flat(k[0])}", k[1:], col, col + 2, 1, n)

    def _break_defschema(self, n, k, col):
        head, fields = _split_type_head("defschema", k, self)
        return self._table(head, fields, col, lambda f: _field_cells(f, self), n)

    def _break_defenum(self, n, k, col):
        head, cases = _split_type_head("defenum", k, self)
        return self._table(head, cases, col, lambda c: _case_cells(c, self), n)

    def _table(self, head: str, rows: list, col: int, cells, node) -> str:
        """A declaration whose members are printed as a padded column table.

        The table gets the signature budget, not the body one: a `:case` row that
        overran 80 would otherwise cost the whole declaration its columns, and a
        ragged table is harder to read than one long row.
        """
        indent = col + 2
        if not self.holds_comment(node):
            aligned = self._aligned([cells(r) for r in rows], indent, SIGNATURE_WIDTH)
            if aligned is not None:
                body = [" " * indent + line for line in aligned]
                return head + "\n" + "\n".join(body) + ")"
        return self._stack(head, rows, col, indent, 1, node)

    def _break_defun(self, n, k, col):
        return self._callable("defun", n, k, col)

    def _break_defentry(self, n, k, col):
        return self._callable("defentry", n, k, col)

    def _break_fn_form(self, n, k, col):
        return self._callable("fn", n, k, col)

    def _break_defextern(self, n, k, col):
        return self._callable("defextern", n, k, col)

    def _callable(self, word: str, n, k: list, col: int) -> str:
        sig, rest = _split_signature(k)
        return self._stack(self._signature_head(word, sig, col), rest,
                           col, col + 2, 1, n)

    def _signature_head(self, word: str, sig: list, col: int) -> str:
        """`(word {T} name [params] -> Type`, with the return type wrapped if it must be.

        The wrap sits deeper than the body so an overlong signature still reads as
        one unit rather than as a header followed by an expression.
        """
        head = f"({word} " + self._flat_signature(sig)
        if col + len(head) <= SIGNATURE_WIDTH or len(sig) < 2:
            return head
        return (f"({word} " + self._flat_signature(sig[:-1])
                + "\n" + " " * (col + 4) + f"-> {self.flat(sig[-1])}")

    def _break_defopaque(self, n, k, col):
        return f"(defopaque {self.flat(k[0])}\n" \
               + " " * (col + 2) + f":doc {self.flat(k[1])})"

    # expressions --------------------------------------------------------

    def _break_let_form(self, n, k, col):
        binds = [x for x in k if isinstance(x, Tree) and x.data == "binding"]
        body = [x for x in k if x not in binds]
        bcol = col + len("(let [")
        rows = []
        for b in binds:
            rows += [c.text for c in self.take_before(_start(b))]
            rows.append(self.emit(b, bcol))
        head = "(let [" + ("\n" + " " * bcol).join(rows) + "]"
        return self._stack(head, body, col, col + 2, 1, n)

    def _break_if_form(self, n, k, col):
        test, rest = k[0], k[1:]
        return self._stack(f"(if {self.emit(test, col + 4)}", rest, col, col + 2, 1, n)

    def _break_cond_form(self, n, k, col):
        return self._clauses("(cond", k, col, n)

    def _break_match_form(self, n, k, col):
        subj, arms = k[0], k[1:]
        return self._clauses(f"(match {self.emit(subj, col + 7)}", arms, col, n)

    def _clauses(self, head: str, arms: list, col: int, node) -> str:
        """`match` and `cond` share a shape: a head, then one clause per line.

        Bodies are aligned into a column only when every clause is a single-expression
        one-liner, which is the form the corpus aligns and the only one where a
        column reads as a table rather than an accident.
        """
        indent = col + 2
        if not self.holds_comment(node) \
                and all(self._alignable_clause(a, indent) for a in arms):
            aligned = self._aligned([_clause_cells(a, self) for a in arms],
                                    indent, self.width)
            if aligned is not None:
                body = [" " * indent + line for line in aligned]
                return head + "\n" + "\n".join(body) + ")"
        return self._stack(head, arms, col, indent, 1, node)

    def _alignable_clause(self, a, indent: int) -> bool:
        """A clause joins the aligned column only if it is one pattern and one flat body."""
        k = kids(a)
        if len(k) != (1 if a.data == "else_clause" else 2):
            return False
        return not self.holds_comment(a) and self.fits(k[-1], indent)

    def _break_match_arm(self, n, k, col):
        return self._clause_body(self.flat(k[0]), k[1:], col, n)

    def _break_cond_clause(self, n, k, col):
        return self._clause_body(self.flat(k[0]), k[1:], col, n)

    def _break_else_clause(self, n, k, col):
        return self._clause_body(":else", k, col, n)

    def _clause_body(self, head: str, body: list, col: int, node) -> str:
        """A body that fits stays on the head's line; anything else drops below it.

        The arm of a `match` reads as a table only while the body is on the pattern's
        line, so a short one stays there. A body that has to break must not: starting
        it past a long pattern walks the whole subtree rightwards, and a nested
        `match` in a nested `match` then runs out of page.
        """
        if len(body) == 1 and self.fits(body[0], col + len(head) + 2) \
                and not self.holds_comment(node):
            return "(" + head + " " + self.flat(body[0]) + ")"
        return self._stack("(" + head, body, col, col + 1, 1, node)

    def _break_binding(self, n, k, col):
        return self._application(k[0], k[1:], col)

    def _break_ctor_arg(self, n, k, col):
        kw = str(n.children[0])
        return f"{kw} " + self.emit(n.children[1], col + len(kw) + 1)

    def _break_try_form(self, n, k, col):
        return "(try " + self.emit(k[0], col + 5) + ")"

    def _break_field_access(self, n, k, col):
        ref = str(n.children[0])
        return f"({ref} " + self.emit(n.children[1], col + len(ref) + 2) + ")"

    def _break_call(self, n, k, col):
        return self._application(n.children[0], n.children[1:], col)

    def _break_ctor(self, n, k, col):
        return self._application(k[0], k[1:], col)

    def _break_module_opt(self, n, k, col):
        return self._kw_opt(n, col)

    def _break_decl_opt(self, n, k, col):
        return self._kw_opt(n, col)

    def _break_extern_opt(self, n, k, col):
        return self._kw_opt(n, col)

    def _kw_opt(self, n, col: int) -> str:
        """`:export [a b` with the names filled and aligned under the first."""
        head = str(n.children[0])
        rest = list(n.children[1:])
        if head not in BRACKETED or not rest:
            return self.flat(n)
        acol = col + len(head) + 2
        body, sealed = self._fill(rest, acol)
        return self._close(f"{head} [" + body, sealed, acol, "]")

    def _application(self, head, args, col: int) -> str:
        """`(head arg` then the remaining arguments aligned under the first.

        Aligning under the first argument is the corpus's habit and it keeps the
        head readable; it is abandoned when the head is itself broken, because
        there is then no column to align to.
        """
        if not args:
            return "(" + self.emit(head, col + 1) + ")"
        if not self.fits(head, col + 1):
            return self._stack("(" + self.emit(head, col + 1), list(args),
                               col, col + 2, 1)
        htxt = self.flat(head)
        acol = col + 1 + len(htxt) + 1
        body, sealed = self._fill(list(args), acol)
        return self._close("(" + htxt + " " + body, sealed, col, ")")


# ---------- shape helpers ----------

def _start(n) -> tuple[int, int] | None:
    sp = span(n)
    return (sp[0], sp[1]) if sp else None


def _end(n) -> tuple[int, int] | None:
    sp = span(n)
    return (sp[2], sp[3]) if sp else None


def _split_signature(k: list) -> tuple[list, list]:
    """Everything up to and including the return type, then the rest."""
    for i, x in enumerate(k):
        if isinstance(x, Tree) and x.data == "type":
            return k[:i + 1], k[i + 1:]
    return k, []


def _split_type_head(word: str, k: list, p: Printer) -> tuple[str, list]:
    head = [x for x in k if isinstance(x, Tree) and x.data == "type_params"]
    name = next(x for x in k if isinstance(x, Token) and x.type == "TYPE_NAME")
    rest = [x for x in k if x is not name and x not in head]
    prefix = f"({word} " + "".join(p.flat(h) + " " for h in head) + str(name)
    return prefix, rest


def _field_cells(f: Tree, p: Printer) -> list[str]:
    k = kids(f)
    name, ty, doc, opts = k[0], k[1], k[2], k[3:]
    tail = " ".join([p.flat(doc)] + [p.flat(o) for o in opts])
    return [":field", p.flat(name), p.flat(ty), tail]


def _case_cells(c: Tree, p: Printer) -> list[str]:
    k = kids(c)
    name, params, doc = k[0], k[1:-1], k[-1]
    plist = "[" + " ".join(p.flat(x) for x in params) + "]"
    return [":case", p.flat(name), plist, p.flat(doc)]


def _clause_cells(a: Tree, p: Printer) -> list[str]:
    return [_clause_head(a, p), p.flat(_clause_exprs(a)[0])]


def _clause_head(a: Tree, p: Printer) -> str:
    """The pattern of a `match` arm, the test of a `cond` clause, or `:else`."""
    return ":else" if a.data == "else_clause" else p.flat(kids(a)[0])


def _clause_exprs(a: Tree) -> list:
    return kids(a) if a.data == "else_clause" else kids(a)[1:]


# ---------- the document ----------

def format_source(src: str, path: str = "<stdin>", width: int = WIDTH) -> str:
    """One AgentScript module, canonically printed. Raises FormatError on bad input.

    The result is re-parsed and compared before it is returned. A printer writes over
    a person's file, so a layout bug must surface as a refusal and not as a corrupted
    module; this turned a real one — a trailing comment swallowing the closing parens
    — from silent damage into an error.
    """
    tree = parse(src, path)
    comments = scan_comments(src)
    p = Printer(comments, scan_delimiters(src, path)[1], width)
    total = len(comments)

    # Top-level items are separated by a blank line, except where the source had a
    # comment block sitting directly on a declaration: that adjacency is the comment
    # saying which declaration it is about, and losing it would rewrite its meaning.
    blocks: list[tuple[str, bool]] = []
    prev_line: int | None = None

    def add(text: str, first: int, last: int) -> None:
        nonlocal prev_line
        blocks.append((text, prev_line is not None and first == prev_line + 1))
        prev_line = last

    for top in tree.children:
        node = unwrap(top)
        for group in _group_comments(p.take_before(_start(node))):
            add("\n".join(c.text for c in group), group[0].line, group[-1].line)
        text = p.emit(node, 0)
        sp, ext = span(node), p.extent(node)
        for c in p.take_trailing(ext):
            text += " " + c.text
        add(text, sp[0] if sp else 0, ext[0] if ext else 0)

    trailing = p.pending
    p.pending, p.emitted = [], p.emitted + len(trailing)
    for group in _group_comments(trailing):
        add("\n".join(c.text for c in group), group[0].line, group[-1].line)

    if p.emitted != total:
        raise FormatError(Diagnostic("internal",
                                     f"{total - p.emitted} comment(s) would be dropped",
                                     1, 1, path))
    if not blocks:
        return ""
    out = blocks[0][0]
    for text, tight in blocks[1:]:
        out += ("\n" if tight else "\n\n") + text
    out += "\n"
    _verify(src, out, tree, path)
    return out


def _verify(src: str, out: str, tree: Tree, path: str) -> None:
    """Refuse to hand back output that does not mean what the input meant."""
    try:
        printed = parse(out, path)
    except FormatError as exc:
        raise FormatError(Diagnostic(
            "internal",
            f"the printer produced output that does not parse "
            f"({exc.diag.message}); the file is unchanged",
            exc.diag.line, exc.diag.col, path)) from None
    if _shape(printed) != _shape(tree):
        raise FormatError(Diagnostic(
            "internal", "the printer produced a different program; "
            "the file is unchanged", 1, 1, path))
    lost = len(scan_comments(src)) - len(scan_comments(out))
    if lost:
        raise FormatError(Diagnostic(
            "internal", f"{lost} comment(s) would be dropped", 1, 1, path))


def _shape(n):
    if isinstance(n, Token):
        return (n.type, str(n))
    return (n.data, tuple(_shape(c) for c in n.children))


def _group_comments(cs: list[Comment]) -> list[list[Comment]]:
    """Runs of comments on consecutive lines; a blank line starts a new block."""
    out: list[list[Comment]] = []
    for c in cs:
        if out and out[-1][-1].line + 1 == c.line:
            out[-1].append(c)
        else:
            out.append([c])
    return out


def format_file(path: Path, write: bool, width: int = WIDTH) -> tuple[bool, list[Diagnostic]]:
    """(changed, diagnostics). `write` decides whether a change is applied or reported."""
    try:
        src = path.read_text()
    except OSError as exc:
        return False, [Diagnostic("internal", exc.strerror or "cannot be read",
                                  1, 1, str(path))]
    try:
        out = format_source(src, str(path), width)
    except FormatError as exc:
        d = exc.diag
        return False, [Diagnostic(d.code, d.message, d.line, d.col, str(path))]
    if out == src:
        return False, []
    if write:
        path.write_text(out)
        return True, []
    return True, [Diagnostic("fmt", "is not canonically formatted", 1, 1, str(path))]


def _corpus_files(path: Path) -> list[Path]:
    """Every `*.agentscript` fixture under `path`; a bare file is its own set.

    The `invalid/` directory is excluded: those fixtures are non-parseable by
    design (the grammar gate asserts rejection), so there is no canonical form to
    check idempotence against.
    """
    if path.is_file():
        return [path] if path.suffix == ".agentscript" else []
    return sorted(p for p in path.rglob("*.agentscript")
                  if "invalid" not in p.parts)


def check_idempotence(path: Path) -> str:
    """One fixture: format, format again, and return a per-file verdict.

    Idempotence is the property that makes formatted output usable as an identity:
    the second pass must be a no-op. A formatter that is deterministic but changes
    nothing (or rewrites every time) fails here.
    """
    src = path.read_text()
    once = format_source(src, str(path))
    twice = format_source(once, str(path))
    if once == twice:
        return f"{path}: ok (idempotent)"
    return f"{path}: FAIL (pass 2 differs from pass 1)"


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    check = "--check" in args
    if check:
        args.remove("--check")
    if not args:
        sys.stderr.write("usage: fmt.py [--check] <file-or-dir>...\n")
        return 2
    if check:
        failures = 0
        for given in args:
            for path in _corpus_files(Path(given)):
                try:
                    print(check_idempotence(path))
                except FormatError as exc:
                    print(f"{path}: ERROR {exc.diag}")
                    failures += 1
        return 1 if failures else 0
    for given in args:
        for path in _corpus_files(Path(given)):
            changed, diags = format_file(path, write=True)
            for d in diags:
                sys.stderr.write(str(d) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
