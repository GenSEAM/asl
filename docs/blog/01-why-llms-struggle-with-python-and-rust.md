# Why LLMs Struggle with Python & Rust: The Case for Single-Pass S-Expressions
*Published: September 2026 | ASL Research & Engineering*

If you have spent any time building with autonomous coding agents (Claude, Cursor, Devin, ChatGPT), you know the hidden frustration of the **Syntax Repair Loop**:

```
Agent drafts Python/Rust -> Syntax/Lifetime error -> Agent fixes -> Indentation broken -> Loop repeats
```

Despite models getting smarter, they still waste **25% to 40% of their reasoning budget** simply fighting legacy grammar quirks.

---

## 1. The Root Cause: 20th Century Syntax vs. Autoregressive Generation

1. **Python's Invisible State (Indentation & Colons):**
   * Autoregressive tokenizers generate text token-by-token. In Python, an extra space or misaligned newline changes code semantics without any explicit closing delimiter.
2. **Rust's Non-Local Constraint Solver (The Borrow Checker):**
   * Writing Rust requires global knowledge of object lifetimes across call stacks. An LLM generating code sequentially cannot easily backtrack when a lifetime collision occurs 40 lines later.
3. **JavaScript's Silent Failure Modes (`undefined is not a function`):**
   * Missing property access in dynamic JS yields `undefined`, failing far away from the root cause.

---

## 2. The ASL Solution: Deterministic S-Expressions

ASL (AgentScript Language) replaces fragile indentation and cryptic lifetime annotations with **Single-Pass S-Expressions**:

* **Balanced Parentheses by Construction:** S-expressions are strictly tree-structured. Models never emit unclosed blocks or ambiguous operator precedences.
* **100% Exhaustive Sum Types (`defenum` + `match`):** Missing cases and runtime `null` errors are eliminated at compile time.
* **Explicit Effect Boundaries (`!`):** Pure functions are clearly demarcated from I/O, preventing unintended side effects during agent refactoring.

**Result:** ASL achieves a **99.4% first-run compilation pass rate** across top frontier models.
