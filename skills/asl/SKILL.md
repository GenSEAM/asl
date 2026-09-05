---
name: asl
description: AgentScript (ASL) reference — S-expression syntax, the closed vocabulary, the semantic rules, and the CLI and MCP tools.
---

# AgentScript (ASL)

**Generated from `prelude/prelude.json`. Do not edit.**

An S-expression language for autonomous AI agents: balanced delimiters, whitespace-insensitive, closed 107-builtin vocabulary, and a static checker. One source transpiles to Python, Rust, TypeScript, WebAssembly and native runner isolate.

## Toolchain & CLI Commands

- `asl run <file.asl>` — Run program in sandboxed isolate (native/Wasm).
- `asl fmt <file.asl>` — Deterministic AST canonical formatter.
- `asl lint <file.asl>` — Structural quality & best-practice file sizing inspector.
- `asl check <file.asl>` — Static type and semantic invariant checker.
- `asl graph --callers <sym>` — Code intelligence: callers and references across modules.
- `asl graph --impact <sym>` — Code intelligence: transitive change impact radius.
- `asl graph --node <sym>` — Code intelligence: symbol definition and location.
- `asl registry <pkg>` — Universal package and dependency inspector across ecosystems.
- `asl gate` — Pure native verification gate runner.
- `asl mcp` — Model Context Protocol server for IDE agent pair programming.

## Core Invariants

1. Balanced parentheses; single-pass LL(1) parsing. Zero indentation hazards.
2. Closed vocabulary: exactly 107 pure builtins. Arbitrary imports are rejected.
3. Strict numeric typing: no implicit numeric conversions.
4. Fallible operations return `(Result T E)`; lookups return `(Option T)`. No exceptions.
5. Functions touching external world are marked with `!`. Operations are sandboxed.

## Master Canonical Example

```lisp
(module auth/token
  :d "Cryptographic tokens, validation, and session queues."
  :x [Token Status hash-token validate-session]
  :i [(sys/time :a time)])

(dfs Token
  (:f id Str "Unique token identifier.")
  (:f exp I64 "Unix timestamp expiration."))

(dfe Status
  (:c ok [(user Str)] "Active session.")
  (:c expired [] "Session expired.")
  (:c denied [(reason Str)] "Access denied."))

(df hash-token [(raw Str) (salt Str)] -> Str
  :d "Deterministic token digest."
  (string-concat raw ":" salt))

(df validate-session [(raw-id Str) (exp-str Str)] -> (Result Token Str)
  :d "Verify expiration timestamp and construct active token."
  (let [(exp (try (option-to-result (string-to-int64 exp-str) "Invalid expiration integer")))]
    (if (> exp 1700000000)
      (ok (Token :id raw-id :exp exp))
      (err "Token timestamp is in the past"))))
```

## Context Economy (Data Matrices & Pools)

- Tabular matrix: `([:id :name :role] [[101 "Alice" :admin] [102 "Bob" :user]])` (saves >65% tokens).
- Constant pool: `(:pool ["https://api.genseam.org" "agent/alpha"] :events [[(:ref 1) (:ref 0)]])`.
- Symbolic anchors: `@d-1234` or `@auth/token` linking to external ledgers with zero in-band token bloat.

## Agent-to-Agent (A2A) Wire Frame

```agp
(:frame :task/invoke
  :tx "tx-9942a"
  :from "agent/coordinator"
  :to "agent/worker"
  :ref @d-9942
  :payload (:action "verify" :target "auth/token"))
```

## Closed Vocabulary Overview (107 Builtins)

All 107 names. Nothing outside this list exists:

- **Arithmetic**: `+`, `-`, `*`, `/`, `mod`, `checked-div`, `checked-mod`, `neg`, `abs`, `min`, `max`
- **Comparison and logic**: `=`, `!=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not`
- **String**: `string-length`, `string-empty?`, `str`, `string-slice`, `string-index-of`, `string-contains?`, `string-starts-with?`, `string-ends-with?`, `string-split`, `string-join`, `string-upper`, `string-lower`, `string-trim`, `string-reverse`, `string-replace`, `string-chars`, `string-from-int64`, `string-from-float64`, `string-to-int64`, `string-to-float64`
- **Numeric conversion**: `int32-to-int64`, `int64-to-int32`, `int64-to-float64`, `float64-to-int64`
- **List**: `list`, `list-empty?`, `list-length`, `list-get`, `list-head`, `list-tail`, `list-cons`, `list-append`, `list-reverse`, `list-slice`, `list-contains?`, `list-index-of`, `list-sort`, `list-sort-by`, `map`, `filter`, `fold`, `range`, `zip`, `list-sum`, `list-min`, `list-max`
- **Map**: `map-empty`, `map-get`, `map-set`, `map-remove`, `map-has?`, `map-size`, `map-keys`, `map-values`, `map-pairs`, `map-from-pairs`
- **Option, Result, Pair**: `some`, `none`, `ok`, `err`, `is-some?`, `is-none?`, `is-ok?`, `is-err?`, `option-or`, `result-or`, `option-map`, `result-map`, `result-map-err`, `option-to-result`, `result-to-option`, `pair`
- **I/O**: `not-found`, `permission-denied`, `already-exists`, `invalid-path`, `interrupted`, `other`, `read-line`, `read-all`, `print`, `println`, `eprintln`, `file-read`, `file-write`, `file-append`, `file-exists?`

Full specification, grammar rules, and complete 107-builtin dictionary: llms-full.txt
