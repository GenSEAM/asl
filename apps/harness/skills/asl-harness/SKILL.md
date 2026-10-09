---
name: asl-harness
description: >-
  Autonomous Agent Coding Harness with in-memory deterministic execution routing, hallucination normalization, batch RPC execution, and system prompt representation policies.
---

# asl-harness: Native Tooling & Verification Guide

> [!IMPORTANT]
> Deterministically compiled from canonical ASN specification (`asl/.agents/skills/asl-harness/skill.asn`).

## Rules of Engagement & Invariants

- **[representation-policy]**: Standardized System Prompt Representation Policy: Enforce minimal syntax, unquoted atoms, atomic null (_), integer-basis fixed point, delta streams, and Adjacency DSL.
- **[mandatory]**: Route deterministic tools (fs-read, fs-list, ast-search, git-status) directly to local execution tier via batch RPC: asl rpc '(:batch ...)'.
- **[mandatory]**: Enforce strict offline sandboxing (ASL_AIRGAP=1) and sliding 10s idle timeout during benchmark evaluations and continuous execution.
- **[package-closure]**: Package Manifest Closure: Every newly created source module in a package MUST be declared in manifest.asn under :modules before claiming completion. Unregistered modules violate package integrity.
- **[anti-stalling]**: Autonomous Execution & Anti-Stalling: Never pause or ask user permission for standard lifecycle completion steps (such as registering manifests, writing unit tests, or running gates). Execute full Definition of Done autonomously.
- **[workflow]**: Auto-normalize LLM syntax drift, snake_case mapping, and unclosed parentheses via hallucination normalizer.
- **[execution]**: Enforce continuous action-observation loops: persistent session, non-interactive stdin redirection (< /dev/null), and PAGER=cat.
- **[separation]**: Strict separation of duties: orchestrator dispatches, planner plans, implementer codes, reviewer audits. Agent never reviews its own work.
- **[vlm-grounding]**: Multimodal VLM Grounding & Spatial ASN: When interacting with vision-language models, project screenshots, DOM trees, and visual coordinates strictly into dense ASN S-expressions (:box :x .. :y .. :w .. :h ..) via asl-svg and asl-codec, eliminating ungrounded visual coordinates.
- **[esh-grounding]**: Execution Simulation Hallucination (ESH) Hardware Grounding: Never claim task completion without a verified gate execution receipt. Unverified completion claims without recorded exit-0 execution are blocked.

## Tool Suite Reference

```asn
(:tool :name "asl-form-batch"
  :action "form-batch"
  :summary "Single-roundtrip batch pipeline for search, AST outlines, edits, diffs, and verification gates"
  :do "./bin/asl '(:op1 ...) (:op2 ...)'")

(:tool :name "asl-test-harness"
  :action "test-harness"
  :summary "Execute native ASL coding tool execution test suite"
  :do "./bin/asl test harness/tests/coding-test.asl")

(:tool :name "asl-verify-esh"
  :action "verify-esh"
  :summary "Verify in-harness ESH grounding and gate validation engine"
  :do "./bin/asl test harness/tests/in-harness-verifier-test.asl")

(:tool :name "asl-eval-airgap"
  :action "eval-airgap"
  :summary "Execute airgap offline model evaluation harness"
  :env (:airgap true)
  :do "./bin/asl run harness/benchmarks/runners/eval-models.mjs --dry-run")

(:tool :name "asl-gate"
  :action "verify-all-gates"
  :summary "Execute native verification gate across all packages, manifests, and skills"
  :do "./bin/asl audit gates")
```

## Supported Agent Harnesses

- `claude-code`
- `factory-droid`
- `antigravity`
- `cursor`
- `windsurf`
- `universal-agents`
