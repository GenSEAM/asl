# The Zero-Line-Number Invariant: Semantic Anchoring and AST Navigation in Autonomous Coding
*Published on September 11, 2026 · 4 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/zero-line-number-invariant*

## 1. The Fragility of Line Numbers

Conventional tools identify code by line and column. For a coding agent, those coordinates are volatile: one insertion near the top of a file shifts every reference below it, and an edit planned against yesterday's line 40 lands on whatever is at line 40 today. When several edits are planned from one read, or several agents work on one tree, each edit can invalidate the coordinates the next one relies on.

## 2. Anchoring by Name and Content

The design rule for the `asl` toolbelt is that an agent addresses code by what it is, not where it sits. The operations an agent uses to navigate and change code take a path plus a name or a piece of text:

- `(:read :file "src/app.asl" :symbol "area")` returns the definition of `area`, wherever it currently is in the file. `:anchor "some text"` returns the slice around a substring instead.
- `(:query :text "area")` finds definitions and uses of a name across the repository.
- `(:edit :file "src/app.asl" :old "..." :new "...")` replaces an exact string. If the string is not there, the edit fails with `ERR_NO_MATCH`; if it occurs more than once, it fails with `ERR_AMBIGUOUS` unless `:all true` is given. An edit either hits exactly the text the agent saw or does nothing.

This is an invariant for agent commands, not a ban on line numbers everywhere. `(:read)` still accepts `:start` and `:end` line bounds for a plain slice, and diagnostics from the host report `file:line:col`, because a person reading an error wants to jump to it.

## 3. Why It Removes Line-Drift Errors

A model that writes a diff against line numbers has to count lines correctly in its own context, and an off-by-one shifts the patch into the wrong block. Matching on exact content moves that failure from silent to loud: stale or miscounted text does not match, and the agent gets an error naming the problem instead of a corrupted file. The recovery is to re-read the symbol and try again with the text that is actually there.

## 4. Staging and Concurrent Agents

Edits are staged in a buffer outside the working tree (one per `ASL_SESSION`), inspected with `(:diff)`, then written with `(:flush)` or dropped with `(:discard)`. `(:flush)` refuses, with `ERR_STALE_BASE`, a file whose content on disk changed after the edit was staged, so an agent cannot overwrite another agent's change that it never saw. `(:txn :owns (...) ...)` goes further: it stages, checks and flushes a group of edits inside declared paths, and restores every touched file if a step fails.

Content anchoring does not make concurrent edits conflict-free; two agents changing the same function still collide. What it does is make the collision visible as a refused edit rather than a silently misplaced one.
