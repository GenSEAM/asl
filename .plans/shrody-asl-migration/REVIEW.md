# Gap & Consistency Review: `asl-shrody-migration-v1`

> **Review Target:** [`asex/.plans/shrody-asl-migration/PLAN.md`](file:///Users/purplelephant/projects/asex/.plans/shrody-asl-migration/PLAN.md)  
> **Source Reference:** [`shrody`](file:///Users/purplelephant/projects/shrody) (`main` @ `68414612635eee46705206760bdfb6fa619f6c68`)  
> **Target Repository:** [`asex`](file:///Users/purplelephant/projects/asex) (`packages/asl-shrody`)  
> **Reviewer Protocol:** [Gap Skill](file:///Users/purplelephant/.gemini/config/skills/gap/SKILL.md) & [Steps Review](file:///Users/purplelephant/.gemini/config/skills/steps-review/SKILL.md)  
> **Verdict:** `approve-with-amendments`

---

## 1. Executive Summary

The plan in `asex/.plans/shrody-asl-migration/PLAN.md` directly targets the root architectural defects of Shrody:
- Spawning 1.5GB Node/V8 child processes (`sessions.js`) causing Out-Of-Memory (OOM) crashes.
- Permission prompt spam on workspace and `/tmp` paths.
- Brittle regex triage splitting related question aspects (`@pcp:d-374e`).

However, applying the **Critic filter (Ponytail)** and **Gap completeness analysis** reveals opportunities to cut code and eliminate omission risks:
1. **Critical Reuse Opportunity (YAGNI):** `asex` already contains `@genseam/asl-toolcall` (`packages/asl-toolcall`) and `@genseam/voice` (`packages/asl-voice`). Item 5 and Item 6 in the plan should NOT reinvent custom S-expression tool calling or audio PCM streaming, but rather import and extend these existing packages.
2. **Audio Barge-in & Cancellation Gap:** The FFI contract in Item 1 lacks an explicit cancellation/interruption signal (`audio/interrupt`), which Shrody relies on (`src/mouth.js`, `src/volunteer.js`) when a user speaks while the agent is answering.
3. **LLM Recovery & Tool Fallback:** Item 5 needs explicit handling for unknown tool names and malformed arguments, delegating validation to `asl-toolcall`.

---

## 2. Gap Analysis (Completeness & Edge Cases)

### GAP-1: Audio Stream Barge-In & Cancellation (`src/ffi.asl`, `host_bridge.js`)
- **Defect:** In Shrody, voice interactivity requires immediate audio cutoff when the user starts speaking (barge-in / VAD trigger). The proposed FFI capability `audio (speak, vad_status)` only supports initiating speech, but lacks `audio/interrupt` or `audio/cancel`.
- **Amendment:** Add `audio/interrupt` to Item 1 FFI capability specification. When the host VAD detects user speech, it triggers an interrupt signal canceling current synthesis immediately.

### GAP-2: Subtask Failure Propagation in DAG (`src/dag.asl`)
- **Defect:** In Item 4, `dag.asl` defines execution waves, but does not specify behavior when an upstream dependency fails (`FAILED` state). In Shrody, downstream tasks can either fail-fast or attempt graceful degradation.
- **Amendment:** Explicitly define dependent cancellation: if task $A$ fails, all downstream tasks depending on $A$ transition to `CANCELLED_UPSTREAM`, preventing wasted LLM calls.

### GAP-3: Workspace Ambiguity on Multi-Repository Worktrees
- **Defect:** `src/policy.asl` verifies paths against `manifest.workspace_root`. In Shrody, git worktrees (`worktrees/eddie-...`) are created outside the primary repository directory.
- **Amendment:** Allow `manifest.worktree_roots` list in `policy.asl` so task-specific git worktrees are auto-authorized without permission prompts.

---

## 3. Consistency Analysis (Architectural Invariants & Standards)

### CONS-1: ASL Syntax & Branding Alignment
- **Status:** PASS. The plan strictly conforms to iteration `2026-09-04-asl-syntax-branding-cleanup`: it avoids the obsolete "Nano" terminology and frames standard ASL as the compact S-expression default.

### CONS-2: PCP Shortcode Traceability
- **Status:** PASS. The plan explicitly preserves Shrody's shortcodes:
  - `@pcp:d-374e` (multi-query question collapse into single task frame).
  - `@pcp:d-1a1a` (setup commands routed to general workspace setup).
  - `@pcp:d-fe29` (frontline classification invariants).

### CONS-3: Closed 107-Builtin Vocabulary Conformance
- **Status:** PASS. All proposed S-expressions utilize standard ASL builtins (`Result`, `ok`, `err`, `list`, `map`, `str`).

---

## 4. Adequacy & Anti-Overengineering (Critic Filter / Ponytail)

### Finding AO-1: Reuse Existing `packages/asl-toolcall` instead of Custom Parser
- **Current Plan (Item 6):** Proposes building custom S-expression tool parsing and ASN formatting in `src/format.asl`.
- **Overengineering Risk:** `packages/asl-toolcall` already provides:
  - Dense S-expression tool definitions (`call :tool name :arg val`).
  - Zero-JSON pure ASL parser with argument validation.
  - Standardized result envelope `(result :tool name :ok true :out "...")`.
  - 76.5% token reduction over JSON Schema.
- **Proposed Adjustment:** Depend on `@genseam/asl-toolcall` directly in `packages/asl-shrody/package.json`. Reduce Item 6 to domain-specific formatting (e.g. git status, task status tables).

### Finding AO-2: Reuse `packages/asl-voice` Audio Bridge
- **Current Plan (Item 1):** Scaffolding a new audio bridge from scratch in `host_bridge.js`.
- **Proposed Adjustment:** Import `@genseam/voice` (`packages/asl-voice/bridges/`), which already implements 16kHz PCM audio streaming, sub-millisecond voice intent routing, and audio device integration.

---

## 5. Amendments to Incorporate into `PLAN.md`

1. **Amendment 1 (FFI & Audio Interrupt):**  
   Add `audio/interrupt` to `packages/asl-shrody/src/ffi.asl` to handle conversational barge-in without audio delay.
2. **Amendment 2 (Package Dependencies):**  
   Declare dependencies on internal packages `packages/asl-toolcall` and `packages/asl-voice` in `packages/asl-shrody/package.json`.
3. **Amendment 3 (Worktree Sandboxing):**  
   Support `manifest.worktree_roots` in `packages/asl-shrody/src/policy.asl` for seamless git worktree isolation without user prompts.
4. **Amendment 4 (DAG Cascade Cancellation):**  
   Specify upstream failure cascading (`CANCELLED_UPSTREAM`) in `packages/asl-shrody/src/dag.asl`.

---

## 6. Verdict

**`approve-with-amendments`**  
The plan is architecturally sound and directly resolves Shrody's operational bottlenecks. Incorporating the 4 amendments above prevents code duplication and closes real-time conversational edge cases.
