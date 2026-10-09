# The Context Tax: How AST Interface Extraction Stops Agent Working Memory Rot
*By GenSEAM | September 2026*

In multi-agent software engineering swarms, the limiting factor is rarely model intelligence. Frontier LLMs can reason through complex algorithms, synthesize tricky data structures, and resolve subtle edge cases.

The ceiling that makes agentic workflows collapse in multi-file codebases is **Context Rot**.

When a coordinator agent hands work to several subagents, the naive approach is to inject full source files into each prompt. Prompts grow quickly, the relevant interface becomes harder to find, and subagents begin calling private functions, misquoting type signatures, and rewriting untouched files.

This is the **Token Tax**: much of what a caller receives is implementation it does not need. How much depends on the repository, the tokenizer and the task, so this post measures one module below and states the scope of that number.

---

## 1. The Anatomy of Context Rot in Multi-Agent Swarms

When a model's context window is flooded with raw implementation details across many modules:

1. **Lost in the Middle:** Models attend most reliably to the beginning and the end of a long prompt; interface contracts defined in files placed in the middle are easier to overlook.
2. **Scope Leakage and Identifier Hallucination:** When an agent sees hundreds of lines of private helpers (`_internal_sort`, `_format_buffer`), it starts calling them instead of programming to the public API.
3. **Latency:** Prompt ingestion time grows with prompt length, and in a swarm where agents call one another, that overhead is paid on every hop.

The caller agent does not care *how* a module computes tax or serializes a buffer; it only needs to know *what* types it accepts, *what* it returns, and *what* guarantees it holds.

---

## 2. AST Interface Extraction: Compressing Implementation to Contract

An AgentScript (ASL) module declares its public surface in its header: `:x` lists the exported names. That makes the interface a property of the syntax tree rather than a convention.

Consider an order module (135 tokens under `cl100k_base`):

```agentscript
(module store/orders :d "Order management and tax calculations" :x [calculateTotal] :i [])

enum OrderStatus (pending) (completed txId: String)

schema Order
  id: Int64
  total: Float64

fn regionalTaxMultiplier rate: Float64 -> Float64
  (+ 1.0 (/ rate 100.0))

fn calculateTotal items: (List Order) taxRate: Float64 -> Float64
  (let [(subtotal (fold (fn [acc o] (+ acc (.-total o))) 0.0 items))
        (multiplier (regionalTaxMultiplier taxRate))]
    (* subtotal multiplier))
```

A peer subagent that only needs to build orders and ask for totals can receive the interface instead (73 tokens):

```agentscript
(module store/orders :d "Order management and tax calculations" :x [calculateTotal] :i [])

enum OrderStatus (pending) (completed txId: String)

schema Order
  id: Int64
  total: Float64

fn calculateTotal items: (List Order) taxRate: Float64 -> Float64
  0.0
```

Both files pass `asl-host check`. On this one module the interface is 45.9% smaller under `cl100k_base` (135 to 73 tokens; 134 to 73, 45.5%, under `o200k_base`), counted with tiktoken 0.12.0 on 2026-09-24. A single module is an illustration, not a repository-wide figure.

### Why Naive Stripping Fails: The Valid Stub Rule

Regex or header-only truncation often emits files that no longer parse. In ASL a function header is followed by an indented body, so an extractor that drops the body without replacing it leaves broken syntax that downstream tools cannot analyse.

An extractor that works on the syntax tree avoids this:
* It drops private top-level functions (here `regionalTaxMultiplier`, which is not in `:x`).
* For exported functions it keeps the name, the typed parameters, the return type (`-> Type`) and any `:d` docstring.
* It replaces each body with a type-satisfying default (`0.0` for `Float64`, `0` for `Int64`, `""` for `String`).

The result is not a text fragment but a module the checker accepts.

What exists today: the `(:intel :op outline :file "...")` operation returns each top-level item of a file with its kind, signature and export flag. The step that renders that outline back into a checkable stub module is what we are building next.

---

## 3. Measuring the Saving

The saving that matters is repository-wide: full-source handoffs against interface handoffs, over many modules, with the tokenizer, the task set and the date stated, plus a downstream measure of whether subagents call fewer private or nonexistent names. We have not run that benchmark yet, so this post quotes no repository-wide percentage, latency, or hallucination rate.

---

## 4. Keeping Semantics Under Composition

Token savings are worthless if they cause regressions. Three properties keep a subagent honest when it writes against a stub:

1. **Checked Names and Arity:** `asl-host check` rejects an unknown name (`ERR_UNKNOWN_SYMBOL`) and a call with the wrong number of arguments (`ERR_ARITY`) before anything runs. Parameter and return type annotations are not checked yet, so passing a `String` where an `Int64` is declared is not caught at check time today.
2. **Contract-Carrying Docstrings:** Keeping `:d` strings keeps units (for example a `:timeoutMs` field) and preconditions in front of the subagent.
3. **Hermetic Boundaries:** A private helper is absent from the stub, so a subagent cannot depend on it by reading about it.

### Summary

Context engineering is not about fitting bigger files into bigger windows. It is about the information density of every token sent. Making interface extraction a first-class operation on the syntax tree is how AgentScript intends to cut the token tax; the single-module figure above shows the mechanism, and the repository-wide benchmark will show its size.
