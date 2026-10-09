# AgentScript (ASL)

> Generated from asl/grammar/llmsEntry.md and asl/grammar/tools.asn by scripts/install.sh --render-rules; scripts/install.sh --check-rules fails when this file differs from that render.

AgentScript is two things.

- ASL, the language: source files (.asl) and data files (.asn) are S-expressions with balanced parentheses. `asl check <file>` checks delimiter balance, `asl test <file>` runs a test suite, and `asl help` lists the shell commands; the language section below says which engine enforces what.
- asl, the toolbelt: `asl '<form> <form> ...'` runs file operations on the git repository that holds the working directory; the forms of one call run as one batch.

## The language

{{LANGUAGE}}

## Concepts

- Form: one parenthesised operation, such as `(:read :file "src/app.py" :symbol "greet")`.
- Staging: (:edit) and (:write) stage changes in a buffer on disk outside the working tree, under .asl/vfs, or ~/.cache/asl/vfs/<hash> for a workspace without .asl; each ASL_SESSION has its own buffer. Staged changes persist across calls until (:flush) writes them or (:discard) drops them, and (:diff), (:check) and (:test) see staged content.
- Transaction: (:txn :owns (<path> ...) <form> ...) stages, gates and flushes in one call, and restores every touched file when a nested step fails.
- Receipt: every form answers with an ASN S-expression; asl exits 0 on success, 1 on rejected forms and 2 on syntax or balance errors.
- Names: user and builtin names are camelCase whole words and predicates end in ?, such as stringLower and listEmpty?.

## Registry and help

- `asl '(:tools)'` prints the live operation registry.
- `asl '(:help :op read)'` shows an op's form, parameters, defaults, errors and related ops.
- `asl '(:help :topic staging)'` explains a topic; topics: {{TOPICS}}.

## Operations

{{OPS}}
