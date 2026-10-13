# @genseam/asl-agent (Agent: Sovereign Autonomous Coding Agent)

**Agent** is an autonomous, token-efficient coding agent, adaptive swarm orchestrator, and terminal TUI in pure AgentScript (ASL).

## Package Identification
- Binary CLI: `asl agent`
- Package: `@genseam/asl-agent`

## Features
- **Adaptive Intent Classification:** Fast zero-drift intent routing (<0.04ms) into execution tiers (Tier 0 Fast-Track, Tier 1 Specialist, Tier 2 Superposition deliberation).
- **Speculative Swarm Superposition:** Races parallel solution hypotheses and commits only mathematically verified code.
- **Circuit Breaker:** Automatic deadlock escape and git rollback on consecutive gate failures.
- **Pure AgentScript Runtime:** Zero foreign code, in-memory DAG task execution, and sub-millisecond dispatch.

## Package Dependency
Declare in your module's `manifest.asn`:
```asn
(:package my-app
  :dependencies ["asl-agent"])
```

## Self-Describing Usage
```asn
;; Classify and plan task route
(:agent-route
  :do "./bin/asl agent route \"Refactor vector cosine similarity in Wasm\""
  :summary "Classify task intent and resolve execution route across specialist tiers")

;; Run autonomous orchestrated swarm
(:agent-run
  :do "./bin/asl agent run \"Scrape documentation and build typed schema\""
  :summary "Orchestrate autonomous agent swarm execution under verification gates")

;; Execute agent test suite
(:agent-test
  :do "./bin/asl test asl/packages/asl-agent/tests/agentTest.asl"
  :summary "Verify intent classification, DAG dispatching, and circuit breaker")
```

## License
MIT
