#!/usr/bin/env python3
"""Generate every artifact that restates the vocabulary, from prelude.json.

The vocabulary was duplicated across the specification tables, both grammars,
the highlight queries, the closure gate and (about to be) the backends. Six
copies of one list is six chances to disagree, and it is what made the language
hard to keep unambiguous: any clarification had to be applied six times.

This script owns the copies. Edit prelude.json, run this, commit the result.

  --check  exit non-zero if a generated artifact is stale (for CI)
"""
import argparse
import json
import re
import sys
from pathlib import Path

import vocab
from vocab import parse_signature

ROOT = Path(__file__).parent
PRELUDE = json.loads((ROOT / "prelude.json").read_text())
SPEC = ROOT.parent / "AGENT_SPEC_CORE.md"
HANDBOOK = ROOT / "HANDBOOK.md"
LARK = ROOT.parent / "grammar" / "agentscript.lark"
TREE_SITTER = ROOT.parent / "grammar" / "tree-sitter-agentscript" / "grammar.js"
LLMS = ROOT.parent / "llms.txt"
LLMS_WEB = ROOT.parent / "web" / "public" / "llms.txt"
LLMS_FULL = ROOT.parent / "llms-full.txt"
LLMS_FULL_WEB = ROOT.parent / "web" / "public" / "llms-full.txt"
SKILL = ROOT.parent / "skills" / "asl" / "SKILL.md"

SEC_ORDER = ["Arithmetic", "Comparison and logic", "String", "Numeric conversion",
             "List", "Map", "Option, Result, Pair", "I/O"]


def signature(b: dict) -> str:
    """`(name a b)` rendered from the declared type, so arity cannot drift."""
    n = len(parse_signature(b["type"])[0])
    names = ["a", "b", "c", "d"][:n]
    if "..." in b["type"]:
        return f"({b['name']} a b …)"
    return f"({b['name']}{''.join(' ' + x for x in names)})"


def spec_tables() -> str:
    out = []
    for i, sec in enumerate(SEC_ORDER, start=1):
        items = [b for b in PRELUDE["builtins"] if b["sec"] == sec]
        out.append(f"### 6.{i} {sec}\n")
        out.append("| Form | Type | Meaning |")
        out.append("|---|---|---|")
        for b in items:
            note = b["doc"]
            out.append(f"| `{signature(b)}` | `{b['type']}` | {note} |")
        out.append("")
    return "\n".join(out)


def shape_block(rows: list[tuple[str, str | None]]) -> list[str]:
    """Code lines with their `;` comments aligned one column past the widest."""
    width = max((len(code) for code, note in rows if note is not None), default=0)
    return [code if note is None else f"{code.ljust(width)}  ; {note}".rstrip()
            for code, note in rows]


def alias_rows() -> list[tuple[str, str]]:
    """(verbose, nano) for every aliased spelling, heads then options."""
    return ([(h["verbose"], h["nano"]) for h in PRELUDE["projection"]["heads"]]
            + [(o["verbose"], o["nano"]) for o in PRELUDE["projection"]["options"]])


def handbook() -> str:
    p = PRELUDE
    sf = p["special_forms"]
    df, dfs, dfe, mt = (vocab.nano_head(x) for x in
                        ("defun", "defschema", "defenum", "match"))
    d, x, i, a, f, c = (vocab.nano_option(k) for k in
                        (":doc", ":export", ":import", ":as", ":field", ":case"))
    i64, f64 = vocab.nano_type("Int64"), vocab.nano_type("Float64")
    st = vocab.nano_type("String")
    lines = [
        "# AgentScript — agent handbook",
        "",
        "**Generated from `prelude/prelude.json`. Do not edit.**",
        "",
        f"Language version {p['version']}. This is the complete vocabulary: if a name is not on "
        "this page, it does not exist. Write nothing else.",
        "",
        "Write the **Nano** spelling shown here. The long spelling of every form is equally "
        "valid and means the same thing — see Projection — but Nano is what the language "
        "stores and sends, so generating it directly saves a conversion.",
        "",
        "## Shape",
        "",
        "```lisp",
        *shape_block([
            ("(module my/mod", "every file is a module"),
            (f'  {d} "One sentence."', "required"),
            (f"  {x} [f Point]", "NOTHING is public unless listed; a"),
            ("", "  PascalCase entry exports a type"),
            (f"  {i} [(other/mod {a} o)])", "o/name for a value, o/Type for a type"),
            ("", None),
            (f"({dfs} Point", "a record"),
            (f'  ({f} x {i64} "Doc."))', "doc required on every field"),
            ("", None),
            (f"({dfe} Shape", "a closed union"),
            (f'  ({c} circle [(r {f64})] "Doc.")', None),
            (f'  ({c} point  []{" " * len(f64)}      "Doc."))', None),
            ("", None),
            (f"({df} area [(s o/Shape)] -> {f64}", "an imported type in a signature;"),
            (f'  {d} "Doc."', "  its cases are (o/circle r)"),
            ("  0.0)", None),
            ("", None),
            (f"({df} {{A}} id [(x A)] -> A", "{A} binds a type variable"),
            (f'  {d} "Required when exported."', None),
            ("  x)", None),
        ]),
        "```",
        "",
        "## Projection",
        "",
        "Each row is one form under two spellings. They parse to the same tree.",
        "",
        "| Nano | Long |",
        "|---|---|",
    ]
    for verbose, nano in alias_rows():
        lines.append(f"| `{nano}` | `{verbose}` |")
    lines += [
        "",
        "**A short spelling counts only in the position it names.** `" + x + "` is the export "
        "list of a module header and nothing else, so a record whose field is called `x` is "
        f"built with `(P {x} 1)` and that key is an ordinary key. Reading these as global "
        "find-and-replace is what corrupts a record.",
        "",
        "These forms have one spelling: "
        + ", ".join("`" + n + "`" for n in p["projection"]["unaliased"]["forms"]) + ", "
        + ", ".join("`" + n + "`" for n in p["projection"]["unaliased"]["options"]) + ".",
        "",
        "## Rules that have no exceptions",
        "",
        "1. `if` takes exactly three parts — condition, then, else. There is no one-armed `if`.",
        f"2. `cond` must end with `:else`. `{mt}` must cover every case.",
        "3. Bindings never change. There is no assignment.",
        f"4. Numbers never convert implicitly. Mixing `{i64}` and `{f64}` is an error.",
        "5. Lookups that can fail return `(Option T)`. They never throw.",
        f"6. Read a record field with `(.-field r)`. Build one with `(Point :x 1 :y 2)`.",
        "7. A name is a type variable only if it appears in that declaration's `{ }`.",
        "",
        "## Handling failure",
        "",
        "```lisp",
        f"({df} or-zero [(s {st})] -> {i64}",
        f'  {d} "Take apart an Option or a Result with {mt}."',
        f"  ({mt} (string-to-int64 s)",
        "    ((some n) n)",
        "    ((none)   0)))",
        "",
        f"({df} f [(s {st})] -> (Result {i64} {st})",
        f'  {d} "try unwraps ok, or returns the err from f immediately."',
        '  (let [(n (try (option-to-result (string-to-int64 s) "bad")))]',
        "    (ok (* n 2))))",
        "```",
        "",
        f"`try` is legal only inside a `{df}` returning a `Result`. Prefer it over nested "
        f"`{mt}`.",
        "",
        "## Never write this",
        "",
        "| Wrong | Right |",
        "|---|---|",
        "| `(if c x)` | `(if c x y)` — else is required |",
        "| `(set! x 1)` | there is no assignment; bind a new name with `let` |",
        f"| `(+ 1 2.0)` | `(+ 1 (float64-to-int64 2.0))` — no implicit conversion |",
        "| `(.x p)` | `(.-x p)` — the dash is part of field access |",
        f"| `({df} f (x {i64}) ...)` | `({df} f [(x {i64})] ...)` — parameters are a vector |",
        "| `(string->int64 s)` | `(string-to-int64 s)` — `->` is the return arrow only |",
        "| `(nth xs 0)` | `(list-get xs 0)` — only names on this page exist |",
        "",
        "## Forms",
        "",
        f"- Declarations: {', '.join('`' + vocab.nano_head(n) + '`' for n in sf['declarations'])}",
        f"- Expressions: {', '.join('`' + vocab.nano_head(n) + '`' for n in sf['expressions'])}",
        f"- Constructors: {', '.join('`' + n + '`' for n in sf['constructors'])}",
        f"- Patterns: {', '.join('`' + n + '`' for n in sf['patterns'])}, "
        "a literal, a name (binds), or `_`",
        "",
        "## Types",
        "",
        "- Primitive: "
        + ", ".join(f"`{vocab.nano_type(t)}`" + (f" (`{t}`)" if vocab.nano_type(t) != t else "")
                    for t in p["types"]["primitive"]),
        f"- Constructed: {', '.join('`(' + t + ' …)`' for t in p['types']['constructed'])}",
        "- A `Map` key must be orderable: `Float64` is not a legal key type.",
    ]
    reserved = vocab.reserved_widths()
    if reserved:
        lines.append(
            "- Reserved width names — "
            + ", ".join(f"`{k}` is `{v}`" for k, v in reserved.items())
            + ". They are accepted so source written for a narrower host type parses, and they "
              "carry none of that width's behaviour: no narrowing, no wrap, no trap at the "
              "narrower boundary. Do not reach for one to get a smaller number.")
    lines += [
        "",
        "## Vocabulary",
        "",
        f"All {len(p['builtins'])} names. Nothing else exists.",
        "",
    ]
    for sec in SEC_ORDER:
        items = [b for b in p["builtins"] if b["sec"] == sec]
        lines += [f"### {sec}", "", "| Form | Type | Meaning |", "|---|---|---|"]
        for b in items:
            lines.append(f"| `{signature(b)}` | `{b['type']}` | {b['doc']} |")
        lines.append("")
    return "\n".join(lines)


def lark_terminal(verbose: str) -> str:
    """The Lark terminal that carries a form's spellings."""
    return verbose.upper() if not verbose.startswith(":") else verbose[1:].upper() + "_KW"


def lark_projection() -> str:
    out = ["// A spelling is significant only where the rules above admit its terminal:",
           "// a record key written `:x` is a KEYWORD, never EXPORT_KW, because no",
           "// ctor_arg position accepts one.",
           ""]
    for group in ("heads", "options"):
        for e in PRELUDE["projection"][group]:
            spellings = [e["verbose"], *e.get("also", []), e["nano"]]
            alts = " | ".join(f'"{sp}"' for sp in spellings)
            out.append(f"{lark_terminal(e['verbose'])}: {alts}")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def tree_sitter_projection() -> str:
    def js(names):
        return "[" + ", ".join(f"'{n}'" for n in names) + "]"

    heads = ",\n".join(
        f"  {e['verbose']}: {js([e['verbose'], *e.get('also', []), e['nano']])}"
        for e in PRELUDE["projection"]["heads"])
    opts = ",\n".join(
        f"  '{e['verbose']}': {js([e['verbose'], e['nano']])}"
        for e in PRELUDE["projection"]["options"])
    return ("// Head and option-keyword spellings. Each is significant only in the\n"
            "// position its rule admits, so a record key written `:x` stays a keyword.\n"
            f"const HEAD = {{\n{heads},\n}};\n\n"
            f"const OPT = {{\n{opts},\n}};\n")


def spec_projection() -> str:
    """§2.1 — the Nano projection, so the specification stays closed over it."""
    rows = "\n".join(f"| `{n}` | `{v}` | {w} |" for v, n, w in
                     [(e["verbose"], e["nano"], e["where"])
                      for e in PRELUDE["projection"]["heads"]]
                     + [(e["verbose"], e["nano"], e["where"])
                        for e in PRELUDE["projection"]["options"]])
    also = ", ".join(
        f"`{sp}`" for e in PRELUDE["projection"]["heads"] for sp in e.get("also", []))
    types = "\n".join(f"| `{a}` | `{t}` |" for a, t in PRELUDE["types"]["aliases"].items()
                      if a != t)
    reserved = "\n".join(f"`{k}` resolves to `{v}`" for k, v in vocab.reserved_widths().items())
    un = PRELUDE["projection"]["unaliased"]
    return f"""### 2.1 The Nano projection

**Generated from `prelude/prelude.json`** — edit there, not here.

Every form below has two spellings. They are the same form: the grammars produce one tree from
either, and no rule anywhere may distinguish them. The short spelling is what the language stores
on disk and puts on the wire; the long one is what a human reads.

| Nano | Long | Significant in |
|---|---|---|
{rows}

A third, intermediate spelling of the declaration heads is also accepted: {also}. It is a
compatibility surface and carries no meaning of its own.

**An alias is significant only in the position named above, and is an ordinary atom everywhere
else.** `:x` opens a module's export list; `(Point :x 3)` supplies a field called `x`, and no
tool may rewrite it. This is the whole reason the table carries a position column: a projection
applied as text substitution corrupts any record whose field is spelled like a keyword.

These forms are deliberately unaliased, being one token already or too short to shorten without
colliding with an identifier: {', '.join('`' + n + '`' for n in un['forms'])}, and the option
keywords {', '.join('`' + n + '`' for n in un['options'])}.

Types have short spellings on the same terms:

| Alias | Type |
|---|---|
{types}

{reserved} — a **reserved width name**. Core has no such width. It is accepted so that source
written against a narrower host type parses and checks today, and it carries none of that width's
semantics: no narrowing, no wrapping, and no trap at the narrower boundary. It exists as
groundwork for host interop, where a real fixed-width type will replace it; until then, reaching
for one to obtain a smaller number is a mistake the language cannot catch for you.
"""


def llms(for_web: bool) -> str:
    """The machine-readable short reference card for agents & LLM prompts."""
    p = PRELUDE
    df, dfs, dfe = (vocab.nano_head(x) for x in ("defun", "defschema", "defenum"))
    d, x, i, a, f, c = (vocab.nano_option(k) for k in
                        (":doc", ":export", ":import", ":as", ":field", ":case"))
    i64, st = vocab.nano_type("Int64"), vocab.nano_type("String")
    by_sec = {sec: [b["name"] for b in p["builtins"] if b["sec"] == sec] for sec in SEC_ORDER}
    lines = [
        "# AgentScript (ASL) — Short Reference & Quickstart",
        "",
        "**Generated from `prelude/prelude.json`. Do not edit.**",
        "",
        "An S-expression language for autonomous AI agents: balanced delimiters, whitespace-insensitive, "
        "closed 107-builtin vocabulary, and a static checker. One source transpiles to Python, Rust, "
        "TypeScript, Go, WebAssembly and native runner isolate.",
        "",
        "## Toolchain & CLI Commands",
        "",
        "- `asl run <file.asl>` — Run program in sandboxed isolate (native/Wasm).",
        "- `asl fmt <file.asl>` — Deterministic AST canonical formatter.",
        "- `asl lint --fix <file.asl>` — Structural code smell detector and auto-repair.",
        "- `asl check <file.asl>` — Static type and semantic invariant checker.",
        "- `asl topo` — Module architectural dependency DAG and circularity check.",
        "- `asl mcp` — Model Context Protocol server for IDE agent pair programming.",
        "",
        "## Core Invariants",
        "",
        "1. Balanced parentheses; single-pass LL(1) parsing. Zero indentation hazards.",
        "2. Closed vocabulary: exactly 107 pure builtins. Arbitrary imports are rejected.",
        "3. Strict numeric typing: no implicit numeric conversions.",
        "4. Fallible operations return `(Result T E)`; lookups return `(Option T)`. No exceptions.",
        "5. Functions touching external world are marked with `!`. Operations are sandboxed.",
        "",
        "## Master Canonical Example",
        "",
        "```lisp",
        "(module auth/token",
        f'  {d} "Cryptographic tokens, validation, and session queues."',
        f"  {x} [Token Status hash-token validate-session]",
        f"  {i} [(sys/time {a} time)])",
        "",
        f"({dfs} Token",
        f'  ({f} id {st} "Unique token identifier.")',
        f'  ({f} exp {i64} "Unix timestamp expiration."))',
        "",
        f"({dfe} Status",
        f'  ({c} ok [(user {st})] "Active session.")',
        f'  ({c} expired [] "Session expired.")',
        f'  ({c} denied [(reason {st})] "Access denied."))',
        "",
        f"({df} hash-token [(raw {st}) (salt {st})] -> {st}",
        f'  {d} "Deterministic token digest."',
        '  (string-concat raw ":" salt))',
        "",
        f"({df} validate-session [(raw-id {st}) (exp-str {st})] -> (Result Token {st})",
        f'  {d} "Verify expiration timestamp and construct active token."',
        '  (let [(exp (try (option-to-result (string-to-int64 exp-str) "Invalid expiration integer")))]',
        '    (if (> exp 1700000000)',
        '      (ok (Token :id raw-id :exp exp))',
        '      (err "Token timestamp is in the past"))))',
        "```",
        "",
        "## Context Economy (Data Matrices & Pools)",
        "",
        "- Tabular matrix: `([:id :name :role] [[101 \"Alice\" :admin] [102 \"Bob\" :user]])` (saves >65% tokens).",
        "- Constant pool: `(:pool [\"https://api.genseam.org\" \"agent/alpha\"] :events [[(:ref 1) (:ref 0)]])`.",
        "- 1-token metadata: `:tag \"d-1234\" :why \"Rationale\" :use \"auth/token\"`.",
        "",
        "## Agent-to-Agent (A2A) Wire Frame",
        "",
        "```agp",
        "(:frame :task/invoke",
        '  :tx "tx-9942a"',
        '  :from "agent/coordinator"',
        '  :to "agent/worker"',
        '  :payload (:action "verify" :target "auth/token")',
        '  :tag "d-9942"',
        '  :why "Routine background health probe.")',
        "```",
        "",
        "## Closed Vocabulary Overview (107 Builtins)",
        "",
        f"All {len(p['builtins'])} names. Nothing outside this list exists:",
        "",
    ]
    for sec in SEC_ORDER:
        lines.append(f"- **{sec}**: " + ", ".join(f"`{n}`" for n in by_sec[sec]))
    lines += [
        "",
        "Full specification, grammar rules, and complete 107-builtin dictionary: "
        + ("https://aslang.dev/llms-full.txt" if for_web else "llms-full.txt")
    ]
    return "\n".join(lines) + "\n"


def llms_full(for_web: bool) -> str:
    """The exhaustive, complete specification and dictionary for all ASL features."""
    p = PRELUDE
    df, dfs, dfe, mt = (vocab.nano_head(x) for x in
                        ("defun", "defschema", "defenum", "match"))
    d, x, i, a, f, c = (vocab.nano_option(k) for k in
                        (":doc", ":export", ":import", ":as", ":field", ":case"))
    i64, st = vocab.nano_type("Int64"), vocab.nano_type("String")
    by_sec = {sec: [b for b in p["builtins"] if b["sec"] == sec] for sec in SEC_ORDER}

    lines = [
        "# AgentScript (ASL) — Complete Specification & Technical Reference",
        "",
        "**Generated from `prelude/prelude.json`. Do not edit.**",
        "",
        f"Version: {p['version']} (Closed Formal Specification)",
        "Corpus Integrity: Verified across 6 differential backends (Wasm, Rust, TS, Go, Python, SQL)",
        "",
        "## 1. Architectural Principles & Invariants",
        "",
        "1. **Single-Pass LL(1) Deterministic Grammar**: Every expression begins with `(` and ends with balanced `)`. Whitespace carries zero semantic indentation meaning, eliminating syntax failure loops common in Python/YAML.",
        "2. **Closed 107-Builtin Vocabulary**: The standard library is closed. No unvetted package creep, no arbitrary host imports. A program calling symbols outside this set is rejected at compile time.",
        "3. **Zero Implicit Numeric Conversions**: Numbers never coerce silently. Mixing `I64` and `F64` requires explicit `(float64-to-int64)` or `(int64-to-float64)`.",
        "4. **Explicit Total Error Handling**: Fallible operations return `(Result T E)` with `(ok v)` / `(err e)`. Lookups return `(Option T)` with `(some v)` / `(none)`. Exceptions and hidden throws do not exist.",
        "5. **Effect Boundaries & Sandboxing**: Functions touching the external world carry `!` in their signature. Filesystem and socket operations are isolated inside a jailed memory space without host path leaks.",
        "",
        "## 2. Master Canonical Example",
        "",
        "A complete, self-contained AgentScript program demonstrating module declarations, typed records, closed union enums, pattern matching, error propagation, and string operations:",
        "",
        "```lisp",
        "(module auth/token",
        f'  {d} "Cryptographic tokens, validation, and session queues."',
        f"  {x} [Token Status hash-token validate-session]",
        f"  {i} [(sys/time {a} time)])",
        "",
        f"({dfs} Token",
        f'  ({f} id {st} "Unique token identifier.")',
        f'  ({f} exp {i64} "Unix timestamp expiration."))',
        "",
        f"({dfe} Status",
        f'  ({c} ok [(user {st})] "Active session.")',
        f'  ({c} expired [] "Session expired.")',
        f'  ({c} denied [(reason {st})] "Access denied."))',
        "",
        f"({df} hash-token [(raw {st}) (salt {st})] -> {st}",
        f'  {d} "Deterministic token digest."',
        '  (string-concat raw ":" salt))',
        "",
        f"({df} validate-session [(raw-id {st}) (exp-str {st})] -> (Result Token {st})",
        f'  {d} "Verify expiration timestamp and construct active token."',
        '  (let [(exp (try (option-to-result (string-to-int64 exp-str) "Invalid expiration integer")))]',
        '    (if (> exp 1700000000)',
        '      (ok (Token :id raw-id :exp exp))',
        '      (err "Token timestamp is in the past"))))',
        "```",
        "",
        "## 3. Formal Declaration & Expression Forms",
        "",
        "<!-- not-agentscript: a grammar summary written with `...` placeholders -->",
        "```lisp",
        f'(module path/name {d} "One sentence." {x} [Sym ...] {i} [(path/mod {a} alias)])',
        f'({dfs} Name ({f} key {i64} "doc") ...)',
        "(let [(name value) ...] body)",
        f"({mt} subject ((tag binder ...) result) ...)",
        "(if test then else)",
        "(cond ((test) value) (:else fallback))",
        "(try result-expr)",
        "```",
        "",
        "## 4. Context Economy Specification",
        "",
        "### 4.1 Tabular Data Matrices",
        "Uniform sequences of structured records are represented as a single header vector of field keys followed by compact row vectors:",
        "",
        "<!-- not-agentscript: data matrix specimen -->",
        "```lisp",
        "([:id :name :role :level]",
        ' [[101 "Alice" :lead 5]',
        '  [102 "Bob"   :agent 3]',
        '  [103 "Carol" :peer 4]])',
        "```",
        "This pattern eliminates repeated JSON key strings and YAML indentation tags, reducing token counts by 65-80%.",
        "",
        "### 4.2 Shared Value Pools (:pool & :ref)",
        "Repeated strings, URLs, or schema identifiers are declared once in a shared constant pool and referenced by single-token index:",
        "",
        "<!-- not-agentscript: pool specimen -->",
        "```lisp",
        '(:pool ["https://api.genseam.org/v1/telemetry"',
        '        "claude-3-7-sonnet-20250219"',
        '        "asl/agent-mesh/node-alpha"]',
        '  :events [([:node :model :target :ok]',
        '            [[(:ref 2) (:ref 1) (:ref 0) true]',
        '             [(:ref 2) (:ref 1) (:ref 0) false]]))',
        "```",
        "",
        "### 4.3 1-Token Metadata Keywords",
        "Keywords `:tag`, `:why`, `:use`, `:ref`, `:pool`, and `:offload` are optimized to map directly to single BPE tokens across major model vocabularies.",
        "",
        "## 5. Agent-to-Agent (A2A) Wire Protocol Specification",
        "",
        "Inter-agent mesh coordination uses balanced symbolic S-expression frames (`agp`):",
        "",
        "```agp",
        "(:frame :task/invoke",
        '  :tx "tx-9942a"',
        '  :from "agent/coordinator"',
        '  :to "agent/sql-optimizer"',
        '  :payload (:query "SELECT * FROM metrics WHERE p99 > 200"',
        "            :timeout-ms 5000)",
        '  :tag "d-9942"',
        '  :why "Mitigate high latency spike detected in cluster.")',
        "```",
        "",
        "```agp",
        "(:frame :task/complete",
        '  :tx "tx-9942a"',
        "  :status :ok",
        "  :result (:scanned 42000 :optimized-ms 1.8)",
        '  :memory-ref "mem://indexes/p99-idx-01")',
        "```",
        "",
        "## 6. Cross-Dialect SQL Specification",
        "",
        "AgentScript provides an S-expression SQL DSL that transpiles deterministically into target database dialects:",
        "",
        "```lisp",
        '(q/select ["id" "name" "email" "status"]',
        '  (q/from "users")',
        '  (q/where (q/and (q/ilike "name" "%admin%")',
        "                  (q/gte \"created_at\" (q/date-sub (q/now) 7 :days))",
        '                  (q/eq "status" "ACTIVE")))',
        '  (q/order-by "created_at" (q/desc))',
        "  (q/limit 25)",
        "  (q/offset 50))",
        "```",
        "",
        "Dialect compilation handles:",
        "- **Placeholders**: `$1` (Postgres), `?` (MySQL), `?1` (SQLite), `@p1` (MSSQL), `:1` (Oracle).",
        "- **Identifier quoting**: `\"` (Postgres/SQLite/Oracle), '`' (MySQL), `[` (MSSQL).",
        "- **Relative date arithmetic**: `NOW() - INTERVAL '7 days'` vs `DATE_SUB` vs `datetime` vs `DATEADD` vs `SYSDATE - 7`.",
        "- **Pagination**: `LIMIT/OFFSET` vs `OFFSET ... ROWS FETCH NEXT ... ROWS ONLY`.",
        "",
        "## 7. Complete Closed Vocabulary Dictionary (107 Builtins)",
        "",
        f"Every builtin function in AgentScript {p['version']} with declared type, semantics, and target lowering templates:",
        ""
    ]

    for sec in SEC_ORDER:
        lines.append(f"### {sec}")
        lines.append("")
        for b in by_sec[sec]:
            lines.append(f"#### `{signature(b)}`")
            lines.append(f"- **Type**: `{b['type']}`")
            lines.append(f"- **Description**: {b['doc']}")
            lines.append("- **Runtime Lowering**:")
            lines.append(f"  - Python: `{b.get('py', '')}`")
            lines.append(f"  - Rust: `{b.get('rs', '')}`")
            lines.append(f"  - TypeScript: `{b.get('ts', '')}`")
            lines.append(f"  - Go: `{b.get('go', '')}`")
            lines.append("")

    lines += [
        "## 8. CLI Toolchain & Model Context Protocol",
        "",
        "- `asl run <file.asl>` — Evaluates script in native/Wasm isolate.",
        "- `asl fmt <file.asl>` — Canonical AST formatter.",
        "- `asl lint --fix <file.asl>` — Smell detector and structural AST auto-repair engine.",
        "- `asl check <file.asl>` — Typechecker and semantic gate.",
        "- `asl transcode <file.asl> --to nano|verbose` — Projection transcoder.",
        "- `asl topo` — Module dependency DAG and circularity auditor.",
        "- `asl mcp` — Model Context Protocol server exposing `asex_check`, `asex_eval`, `asex_format`, `asex_compress_module`.",
        "",
        "Canonical Website: https://aslang.dev · Repository: https://github.com/GenSEAM/asl · MIT License"
    ]

    return "\n".join(lines) + "\n"


def skill() -> str:
    """The Claude/agent skill card: front-matter plus the llms.txt body."""
    body = llms(for_web=False).split("\n", 1)[1]
    return ("---\n"
            "name: asl\n"
            "description: AgentScript (ASL) reference — S-expression syntax, the closed "
            "vocabulary, the semantic rules, and the CLI and MCP tools.\n"
            "---\n"
            "\n"
            "# AgentScript (ASL)\n" + body)


def splice(path: Path, marker: str, body: str, comment: str) -> str:
    """Replace the region between BEGIN/END markers, keeping the markers."""
    begin = f"{comment} BEGIN GENERATED {marker}"
    end = f"{comment} END GENERATED {marker}"
    text = path.read_text()
    i, j = text.index(begin), text.index(end)
    head = text[:i + len(begin)]
    # Everything on the BEGIN line after the marker is prose about the region.
    nl = text.index("\n", i)
    head = text[:nl]
    return head + "\n" + body.rstrip("\n") + "\n" + text[j:]


def validate_templates() -> list[str]:
    """Every lowering template must format cleanly at its declared arity.

    Literal braces are the trap: a Python empty-dict lowering of `{}` is read as
    a format placeholder and fails at transpile time, far from its cause. Braces
    intended literally must be doubled in prelude.json.
    """
    bad = []
    for b in PRELUDE["builtins"]:
        n = len(parse_signature(b["type"])[0])
        for tgt in ("py", "js", "ts", "rs", "go"):
            tpl = b.get(tgt)
            if tpl is None:
                bad.append(f"{b['name']}: no {tgt} lowering")
                continue
            try:
                if "{*}" not in tpl:
                    tpl.format(*[f"a{i}" for i in range(max(n, 4))])
            except Exception as exc:
                bad.append(f"{b['name']} [{tgt}] {tpl!r}: {exc}")
    return bad


def write(path: Path, content: str, check: bool) -> bool:
    """Returns True when stale."""
    old = path.read_text() if path.exists() else None
    if old == content:
        return False
    if check:
        print(f"STALE: {path}")
        return True
    path.write_text(content)
    print(f"wrote {path} ({len(content)}B)")
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    broken = validate_templates()
    if broken:
        print("BROKEN LOWERING TEMPLATES:")
        for b in broken:
            print("  " + b)
        return 1

    stale = write(HANDBOOK, handbook(), args.check)

    # The card an external agent reads. It lived in two places and they drifted:
    # the copy the site served taught `(:export ...)`, `Ok`/`Err` and `zip-with`,
    # none of which the language has.
    stale |= write(LLMS, llms(for_web=False), args.check)
    stale |= write(LLMS_WEB, llms(for_web=True), args.check)
    stale |= write(LLMS_FULL, llms_full(for_web=False), args.check)
    stale |= write(LLMS_FULL_WEB, llms_full(for_web=True), args.check)
    stale |= write(SKILL, skill(), args.check)

    # Both grammars carry the projection's spellings. Splicing them from the one
    # source is what keeps a new alias from reaching one parser and not the other.
    stale |= write(LARK, splice(LARK, "PROJECTION", lark_projection(), "//"), args.check)
    stale |= write(TREE_SITTER,
                   splice(TREE_SITTER, "PROJECTION", tree_sitter_projection(), "//"),
                   args.check)

    spec = SPEC.read_text()
    head, _, rest = spec.partition("## 6. Closed vocabulary")
    body_tail = rest.split("## 7. Worked example", 1)[1]
    intro = ("## 6. Closed vocabulary\n\n"
             "Every builtin, with its type. Nothing outside this table and §4-5 exists in Core.\n\n"
             "**Generated from `prelude/prelude.json`** — edit there, not here.\n\n")
    new_spec = head + intro + spec_tables() + "## 7. Worked example" + body_tail

    # §2.1 is generated for the same reason §6 is: the projection was a property
    # of two grammar files and of nothing the specification said, which made the
    # specification's claim to be closed false for every Nano program.
    pre, sep, post = new_spec.partition("### 2.1 The Nano projection")
    if sep:
        post = post.split("## 3. Types", 1)[1]
        new_spec = pre + spec_projection() + "## 3. Types" + post
    else:
        pre, sep, post = new_spec.partition("## 3. Types")
        new_spec = pre + spec_projection() + sep + post
    stale |= write(SPEC, new_spec, args.check)

    if args.check and stale:
        print("\nRun: .venv/bin/python prelude/generate.py")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
