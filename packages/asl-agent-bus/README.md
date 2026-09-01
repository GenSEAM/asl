# @genseam/asl-agent-bus

High-performance Inter-Agent Swarm Bus with MCP, Server-Sent Events (SSE), and Unix Domain Socket streaming for warm subagents.

## Key Features
- **Zero Cold-Start:** Subagents stay warm in-memory, listening on local SSE streams or sockets.
- **MCP Integration:** Out-of-the-box Model Context Protocol (MCP) JSON-RPC bridge.
- **-78% Token Wire Protocol:** Agents pass typed S-expression AST schemas rather than noisy JSON blobs.
- **Real-Time Mesh Visualizer:** Live streaming event feed (`agent:started`, `agent:thought`, `agent:tool_call`, `agent:done`).

## Installation
```bash
asl get github.com/GenSEAM/agent-bus
```

## CLI Usage
```bash
# Start local agent bus daemon on port 8765
asl bus serve --port 8765

# Broadcast message to warm agent
asl bus send agent-coder "Implement feature X in ASL"
```
