# The Agent-Native Language & Dual-Projection Manifesto

> **"Code is for agents. Architecture, intent, and verifiable proofs are for humans."**

This is the rationale. The operative rules are `asl/grammar/rules.asn`; the principles behind them, each with its measurement or marked as adopted, are `.asl/mem/principles.asn`; its `:glossary` defines the terms used here. A figure in this document cites a principle id or a lock file, or it is not here.

---

## Executive Summary

Programming languages were built as human-to-machine interfaces, balancing human reading, keyboard ergonomics and machine instructions. When the main author and reader of code is a language model, that balance moves. Syntax that exists for human eyes costs context, ambiguous grammar costs correctness, and scattered tool calls cost both.

The response is **the Principle of Dual Projection**: one system, projected twice.

```
       ┌──────────────────────────────────────────────────────────────┐
       │                         HUMAN LAYER                          │
       │  Intent • Architecture • Decision records • Verifiable proofs │
       └──────────────────────────────┬───────────────────────────────┘
                                      │ steering down, proofs up
       ┌──────────────────────────────┴───────────────────────────────┐
       │                         AGENT LAYER                          │
       │  AgentScript (ASL) and ASN • code is its AST • batched forms  │
       │  staged in-memory edits • gates with observed exit codes      │
       └──────────────────────────────────────────────────────────────┘
```

---

## 1. The Problem

When agents work in languages designed for people, four costs appear:

1. **Ceremony tokens.** Punctuation, boilerplate and formatting take context that could hold the task. How much is a measurement question, answered per format in `asl/bench/asn_tokens.lock` and by `StructuralTaxIsNotOverhead`, not by a slogan.
2. **Ambiguous structure.** Irregular grammars make the model guess AST boundaries, which shows up as broken delimiters and malformed diffs.
3. **Fragmented tool loops.** Many serial shell round trips fill the context with echoes and pagination.
4. **Review that does not scale.** People reading thousands of generated lines miss what a failing check would have caught.

Long, noisy context degrades retrieval unevenly across models; the practice that follows is `ReadBySymbolAndSlice`.

---

## 2. The Principle of Dual Projection

### Plane A: the Agent Layer

- **Written and run by models** and by the verification harness.
- **Code is the AST.** ASL bodies are ASN S-expressions with balanced delimiters, so structure is never guessed; a function header is a bare column-0 line (`fn name a: T -> R`) with its body parenthesised below it. The goal is convergence on parens only.
- **Dense, not cryptic.** Whole words, camelCase, the measured cheapest name among those that carry the meaning (`MeasuredCostDecidesTheName`, `CompressStructureNeverSpelling`).
- **Transactional.** Edits are staged in memory, inspected with `(:diff)`, then flushed or discarded.

### Plane B: the Human Layer

- **Structure, not syntax.** People read topology, dependencies, state machines and decision records.
- **Intent as contract.** People state what must hold: inputs, outputs, invariants, error behaviour.
- **Trust from proof.** People trust the system because checks fail on seeded defects and pass on the change: `./bin/asl audit gates`, `./bin/asl audit consistency`, falsifiable suites, benchmark locks (`GroundTruthOverReport`, `AGateThatCannotFailIsNotAGate`).

---

## 3. Pillars, stated as goals

### I. Names that carry meaning at the lowest measured cost

Identifiers are whole words the model already knows. Abbreviation below the whole-word boundary loses the model prior and saves nothing (`CompressStructureNeverSpelling`, `RefutedStructuralRewrites`). Namespace carries the domain, so a symbol does not repeat its module. camelCase is kept because it is measurably cheaper than kebab-case across the corpus, by a small margin (`CamelCaseCorpusSaving`).

### II. Context spent on the task

Every primitive form is priced with a tokenizer: `asl/grammar/grammar.asn` lists the forms with their o200k token counts and records the tokenizer, method and date. Reads load symbols and bounded slices; independent operations share one batch; the invariant prefix stays byte-stable so it can be cached.

### III. Structure that cannot be misread

Balanced delimiters, a closed vocabulary of primitive forms, and a written form that mirrors the in-memory tree, so parse and print round-trip without loss.

### IV. Communication as contract

Requests and receipts are typed: preconditions, postconditions, the gate that decides. Receipts, commands and patches address code by path and symbol or content anchor. Skills are loaded on demand rather than living in one large prompt.

### V. One notation on the wire, on disk and in memory

ASN is the data format for tasks, messages and tool payloads, so nothing is translated between them. Several forms in one `asl` call run as one batch. Errors are typed (`ERR_NO_MATCH`, `ERR_FILE_NOT_FOUND`) so the next step inspects rather than retries.

### VI. ASL first

Packages and tools are written in ASL; host C stays at a floor of memory, syscalls and a few string primitives. Code that must run elsewhere is still reasoned about in ASL and lowered to the target (`CoreKnowsNoExtension`).

### VII. Falsifiable verification and separated duties

The writer does not grade its own work (`TheWriterDoesNotGrade`). A check counts after it has been seen to fail on a seeded violation. A suite with zero executed assertions, or with a declared assertion it never reaches, is a failure.

### VIII. Purpose over persona

Agents are defined by what they are responsible for, not by a character to play. Coordination runs through shared, tracked artifacts (intent, roadmap, tasks, receipts) rather than conversation. Within declared `:owns` an agent has full latitude; at a boundary breach, a repeated failure or an unplanned irreversible step it stops and escalates to the principal (`StakeOverCompliance`, `CheapestRefutationFirst`, `AdaptivePivoting`). Negative invariants are kept to what a checker enforces; everything else is a goal with a question that refutes it.

---

## 4. Projection to other ecosystems

ASN is the single source for data structures, pipeline stages and frames. Build tools project it into native types for other runtimes (structs, typed interfaces, schemas), so external code validates at the boundary instead of guessing. The same holds for skills: canonical ASN skill specifications are projected into `SKILL.md` files for third-party agents, and the rendered copies are checked against their source (`./scripts/install.sh --check-rules`).

## 5. Ledgers and observability

Durable state lives in tracked ledgers: `.asl/mem/intent.asn` (goals and attention points), `.asl/mem/roadmap.asn` (phases and waves), `.asl/mem/tasks/` (task DAGs with `:owns` and gates), `.asl/mem/decisions/` (decision records), `.asl/mem/receipts.asn` (executed checks). Session scratch state is local and ignored by git. What a command can reconstruct is not written down (`TheLedgerIsTheMemory`, `ReconstructibilityThreshold`).

---

## 6. The Division of Labour

| Aspect | Human | Agent |
|---|---|---|
| **Medium** | Architecture, decision records, intent contracts, metrics | ASL, ASN trees, batched forms |
| **Focus** | Why and what: goals, invariants, policy | How: implementation, refactoring, execution |
| **Inspection** | Topology, gate output, benchmark locks | Staged diffs, symbol graphs, AST slices |
| **Trust** | Gates seen to fail on seeded defects | Reproducible suites with executed assertions |
| **State** | Steering intent and roadmap | Executing tasks and emitting receipts |

---

## 7. Summary

Languages, instructions and wire formats built for models let them spend context on the task and never guess structure. Goals with refuting questions and checks with observed exit codes bound what they do. Architecture, contracts and proofs projected to people let people govern the system without reading every line.
