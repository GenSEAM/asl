# @genseam/asl-agent-bus

High-performance Inter-Agent Swarm Bus with Server-Sent Events (SSE) and Unix Domain Socket streaming for warm subagents.

## Key Features
- **Zero Cold-Start:** Subagents stay warm in-memory, listening on local SSE streams or sockets.
- **-78% Token Wire Protocol:** Agents pass typed S-expression AST schemas rather than noisy JSON blobs.
- **Real-Time Mesh Visualizer:** Live streaming event feed (`agent:started`, `agent:thought`, `agent:tool_call`, `agent:done`).

## Package Dependency
Declare in your module's `manifest.asn`:
```asn
(:package my-app
  :dependencies ["agent-bus"])
```

## Self-Describing Usage
```asn
;; Start local agent bus daemon on port 8765
(:bus-serve
  :do "./bin/asl bus serve --port 8765"
  :summary "Launch high-performance inter-agent message broker daemon")

;; Broadcast typed task frame to warm in-memory subagent
(:bus-send
  :do "./bin/asl bus send agent-coder \"Implement feature X in ASL\""
  :summary "Send zero-leak AST task frame to listening subagent")

;; Verify agent bus communication and wire framing
(:test-bus
  :do "./bin/asl test asl/packages/asl-agent-bus/tests/busTest.asl"
  :summary "Execute inter-agent event bus and wire frame assertion suite")
```
