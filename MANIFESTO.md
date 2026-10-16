# ASL Manifesto

> **"LLM first."**

AgentSlang (ASL) is a language and toolset for software written by language models. The problem it is built against: **a model hallucinates when its attention is short or spread thin.** Noisy context, ambiguous structure, contradictory instructions and lost state all dilute attention. Each principle below removes one of those causes.

---

## 1. LLM first

The model is the main author and reader of the code, so the language is designed for it and measured on it.

- **Structure that cannot be misread.** Forms are balanced trees; the written form mirrors the tree, so a model never guesses where a form ends.
- **Measured, not assumed.** A keyword, marker or naming scheme stays only while models generate correct code better with it than without it. When a measurement refutes a choice, the choice goes.
- **Few tokens per idea.** Whole words the model already knows, no ceremony for human eyes, one notation (ASN) for code, data, messages and memory.
- **No silent failure.** No null, no exceptions, effects visible to the checker: the model learns it is wrong at the place it is wrong.

## 2. Infrastructure SEAM

One language to describe, build and run a whole system.

- SQL, JavaScript, HTML, CSS and other languages live inside ASL as checked blocks.
- The compiler is written in ASL, compiles itself, and targets native code and WebAssembly; source-to-source targets cover ecosystems that need source.
- A foreign-function interface (on the roadmap) makes any library or binary usable from ASL.
- Engineers govern from above the code with lenses (topology, coupling, complexity, effect boundaries, intent coverage) and gates that count only after they have failed on a seeded defect.

## 3. Non-restrictive harness

Constraints belong in the program and the environment, not in the prompt.

- **Enforce, don't instruct.** Permissions, sandboxes, file ownership, checkers and gates make the wrong action impossible or visible; a prompt full of prohibitions only competes with the task for attention.
- **No roles.** A persona is a bias, not a capability.
- **Intents, lenses and attractors** state what must become true, show the task from several sides, keep attention on the goal, and route each request to the model that fits it.

## 4. Agent-assistive tools

Tools built for how agents work and fail:

- read by symbol and slice, batch independent operations, stage edits and flush them as one transaction;
- typed, compact receipts that say what to do next;
- memory the model keeps for itself (notes, scratchpads, to-do lists, its own guidelines) and project memory in tiers, so focus survives long tasks and compaction;
- onboarding from a small index in one request;
- every claim tied to a check that ran.

---

Every figure the project publishes is a row in `bench/publishedClaims.asn` with its status; an unmeasured figure is not cited as a result.

*ASL is dual-licensed under MIT or Apache-2.0.*
