# Edit by Symbol, Not by Line Number: How the ASL Toolbelt Keeps Batch Patches Exact
*Published on September 11, 2026 · 4 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/zero-line-number-invariant*

When an agent sends a batch of operations to the `asl` toolbelt—`(:read :file "src/app.asl" :symbol "area")` followed by `(:edit :file "src/app.asl" :old "..." :new "...")` and `(:check ...)`—it addresses code by symbol name and exact content, never by line number. Whether an agent stages five edits in one call or several subagents work across the repository, every replacement either matches the exact target text and parses cleanly, or stops with a structured receipt (`ERR_NO_MATCH`, `ERR_AMBIGUOUS`).

## 1. Why Line Numbers Break Agent Batches

Conventional patch tools identify code by line and column. For an agent planning a multi-step batch, line coordinates are quicksand: one insertion near the top of a file shifts every line number below it, so the second or third edit in a batch lands on the wrong span.

## 2. Anchoring by Name and Content

The design rule for the `asl` toolbelt is that an agent addresses code by what it is, not where it sits. The operations an agent uses to navigate and change code take a path plus a name or a piece of text:

- `(:read :file "src/app.asl" :symbol "area")` returns the definition of `area`, wherever it currently is in the file. `:anchor "some text"` returns the slice around a substring instead.
- `(:query :text "area")` finds definitions and uses of a name across the repository.
- `(:edit :file "src/app.asl" :old "..." :new "...")` replaces an exact string. If the string is not there, the edit fails with `ERR_NO_MATCH`; if it occurs more than once, it fails with `ERR_AMBIGUOUS` unless `:all true` is given. An edit either hits exactly the text the agent saw or does nothing.

This is an invariant for agent commands, not a ban on line numbers everywhere. `(:read)` still accepts `:start` and `:end` line bounds for a plain slice, and diagnostics from the checker report `file:line:col`, because a person reading an error wants to jump to it.

## 3. Why It Removes Line-Drift Errors

A model that writes a diff against line numbers has to count lines correctly in its own context, and an off-by-one shifts the patch into the wrong block. Matching on exact content moves that failure from silent to loud: stale or miscounted text does not match, and the agent gets an error naming the problem instead of a corrupted file. The recovery is to re-read the symbol and try again with the text that is actually there.

## 4. Staging and Concurrent Agents

Edits are staged in a buffer outside the working tree (one per `ASL_SESSION`), inspected with `(:diff)`, then written with `(:flush)` or dropped with `(:discard)`. `(:flush)` refuses, with `ERR_STALE_BASE`, a file whose content on disk changed after the edit was staged, so an agent cannot overwrite another agent's change that it never saw. `(:txn :owns (...) ...)` goes further: it stages, checks and flushes a group of edits inside declared paths, and restores every touched file if a step fails.

Content anchoring does not make concurrent edits conflict-free; two agents changing the same function still collide. What it does is make the collision visible as a refused edit rather than a silently misplaced one.
