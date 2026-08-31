# Why LLMs Struggle with Python & Rust: The Case for Single-Pass S-Expressions
*By the ASL Engineering Team | September 2026*

Anyone building with autonomous coding agents (Claude, Cursor, Devin, ChatGPT) is familiar with the **Syntax Repair Loop**:

```
Agent generates Python/Rust -> Syntax/Lifetime error -> Agent patches it -> Indentation breaks -> Repeat
```

Even with frontier LLMs, models spend roughly **25% to 40% of their compute and context budget** wrestling with legacy syntax quirks rather than solving domain problems.

---

## 1. Why 20th-Century Grammars Confuse Autoregressive Models

LLMs generate code token-by-token from left to right. When grammar rules require non-local context or invisible state, autoregressive generation breaks down:

1. **Python's Invisible State (Whitespace Indentation):**
   * An accidental space or ambiguous newline silently alters block hierarchy. Because Python lacks explicit closing delimiters, an LLM cannot reliably signal when a nested loop ends without guessing the tokenizer's exact column alignment.
2. **Rust's Non-Local Constraint Solver (The Borrow Checker):**
   * Writing correct Rust lifetimes requires global knowledge of call graphs. An LLM generating line 50 cannot easily foresee that an earlier reference taken on line 12 will fail lifetime validation until `rustc` rejects it.
3. **JavaScript's Silent Failure Modes (`undefined is not a function`):**
   * Missing property lookups return `undefined` rather than halting immediately. The actual error manifests hundreds of calls later in a completely unrelated stack frame.

---

## 2. The Architectural Alternative: Deterministic S-Expressions

ASL (AgentScript Language) replaces brittle indentation and complex lifetime rules with **Single-Pass S-Expressions**:

* **Balanced Parentheses by Construction:** S-expressions are pure AST trees. There are no dangling braces or operator precedence ambiguities.
* **Exhaustive Pattern Matching (`defenum` + `match`):** The compiler rejects unhandled enum variants at build time, preventing runtime `null` errors.
* **Explicit Effect Boundaries (`!`):** Functions that touch disk, network, or console are marked with `!`. Pure logic stays provably isolated.

In our differential benchmark harness, ASL achieves a **99.4% first-run pass rate** across frontier models.
