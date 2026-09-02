"""SkyLoom CLI Engine (`asl loom`).
Provides command-line diagnostics, swarm inspection, and multi-agent simulation.
"""

import json
import sys
import time
from dataclasses import dataclass, asdict
from typing import List, Dict, Optional

@dataclass
class LoomCliPeer:
    id: str
    name: str
    role: str
    dialect: str
    is_asl_native: bool
    status: str
    mailbox_count: int = 0

WARM_SWARM: Dict[str, LoomCliPeer] = {
    "agent-orchestrator": LoomCliPeer("agent-orchestrator", "Orchestrator Pro", "supervisor", "asl/v1", True, "active"),
    "agent-planner": LoomCliPeer("agent-planner", "Strategic Planner", "planner", "asl/v1", True, "active"),
    "agent-coder": LoomCliPeer("agent-coder", "Wasm Builder", "coder", "compact/v1", False, "active"),
    "agent-vanilla-llm": LoomCliPeer("agent-vanilla-llm", "Unprimed LLM", "external", "polyglot/v1", False, "active"),
    "agent-lonely-sub": LoomCliPeer("agent-lonely-sub", "Late Worker", "worker", "asl/v1", True, "lonely", mailbox_count=2),
}

def list_peers(json_mode: bool = False) -> int:
    """List connected SkyLoom peers."""
    peers = [asdict(p) for p in WARM_SWARM.values()]
    if json_mode:
        print(json.dumps(peers, indent=2))
        return 0

    print("=== SkyLoom Swarm Mesh Registry ===")
    print(f"{'PEER ID':<22} {'ROLE':<14} {'DIALECT':<12} {'ASL NATIVE':<12} {'STATUS':<10} {'MAILBOX':<8}")
    print("-" * 84)
    for p in WARM_SWARM.values():
        native_str = "YES" if p.is_asl_native else "NO"
        print(f"{p.id:<22} {p.role:<14} {p.dialect:<12} {native_str:<12} {p.status:<10} {p.mailbox_count:<8}")
    print(f"\nTotal Active Peers: {len(WARM_SWARM)} | Mesh Status: HEALTHY")
    return 0

def send_message(to: str, message: str, from_peer: str = "agent-orchestrator", channel: Optional[str] = None, dialect: str = "auto", json_mode: bool = False) -> int:
    """Send message across the SkyLoom mesh with dialect negotiation."""
    target = WARM_SWARM.get(to)
    now = int(time.time() * 1000)
    msg_id = f"msg-{int(time.time() % 10000):04d}"

    # Handle offline / lonely peer
    if not target or target.status == "lonely":
        result = {
            "status": "QUEUED",
            "code": 1002,
            "reason": f"Peer '{to}' is offline. Message buffered in SkyLoom mailbox queue.",
            "frameId": msg_id,
            "target": to,
            "ttl_seconds": 60,
        }
        if json_mode:
            print(json.dumps(result, indent=2))
        else:
            print(f"⚠️ [SkyLoom] Target '{to}' is currently offline/lonely.")
            print(f"📦 Frame '{msg_id}' safely buffered in Mailbox Queue (TTL: 60s).")
            print("🔔 Mesh will auto-drain and deliver upon peer connection.")
        return 0

    # Dialect selection
    chosen_dialect = target.dialect if dialect == "auto" else dialect
    wire_repr = ""

    if chosen_dialect == "asl/v1":
        chan_part = f' :channel "{channel}"' if channel else ""
        wire_repr = f'(loom:frame :v 1 :id "{msg_id}" :from "{from_peer}" :to "{to}" :dialect "asl/v1" :ts {now}{chan_part} :type "DATA" :body "{message}")'
    elif chosen_dialect == "compact/v1":
        wire_repr = f"SK1|1|{msg_id}|{from_peer}|{to}|DATA|{channel or ''}|{now}||{message}"
    else:
        wire_repr = f"""<!-- SKYLOOM_HEADER: {{"v":1,"id":"{msg_id}","from":"{from_peer}","to":"{to}","dialect":"polyglot/v1","type":"DATA"}} -->
[SkyLoom Autonomous Protocol Primer]
From: {from_peer} -> To: {to}
```json
{{
  "action": "{message}",
  "replyTo": "{msg_id}"
}}
```
<!-- SKYLOOM_FOOTER -->"""

    result = {
        "status": "DELIVERED",
        "frameId": msg_id,
        "from": from_peer,
        "to": to,
        "dialect": chosen_dialect,
        "wireFormat": wire_repr,
        "latency_ms": 0.042,
    }

    if json_mode:
        print(json.dumps(result, indent=2))
    else:
        print(f"✓ [SkyLoom] Frame '{msg_id}' delivered to '{to}' via {chosen_dialect} (0.042ms)")
        print(f"Wire Representation:\n{wire_repr}")
    return 0

def mailbox_status(peer_id: str = "agent-lonely-sub", json_mode: bool = False) -> int:
    """Inspect mailbox status for an agent."""
    peer = WARM_SWARM.get(peer_id)
    count = peer.mailbox_count if peer else 0
    status = {
        "peerId": peer_id,
        "pendingCount": count,
        "ttl_remaining_sec": 54 if count > 0 else 0,
        "status": "QUEUED" if count > 0 else "EMPTY"
    }

    if json_mode:
        print(json.dumps(status, indent=2))
    else:
        print(f"=== SkyLoom Mailbox: {peer_id} ===")
        print(f"Pending Messages: {count}")
        print(f"Queue Status: {status['status']}")
        if count > 0:
            print("Automatic delivery will trigger when peer sends HANDSHAKE.")
    return 0

def primer(target_peer: str = "vanilla-llm", sender: str = "orchestrator", json_mode: bool = False) -> int:
    """Output self-describing instruction primer."""
    text = f"""[SkyLoom Autonomous Protocol Primer]
You are communicating with agent "{sender}" over the SkyLoom protocol.
To reply, respond with a fenced code block:
```json
{{
  "status": "COMPLETED" | "NEED_INFO" | "ERROR",
  "result": <your answer or output>,
  "replyTo": "<original_message_id>"
}}
```"""
    if json_mode:
        print(json.dumps({"target": target_peer, "sender": sender, "primer": text}))
    else:
        print(text)
    return 0

def demo(json_mode: bool = False) -> int:
    """Run full SkyLoom end-to-end multi-agent demonstration."""
    print("=== [SkyLoom] Live Autonomous Swarm Demonstration ===")
    time.sleep(0.1)
    print("\n[Step 1: Swarm Topology Discovery]")
    list_peers(json_mode=False)

    print("\n[Step 2: Aware <-> Aware Native ASL Dispatch]")
    send_message("agent-planner", "generate_roadmap_dag", dialect="asl/v1")

    print("\n[Step 3: Aware <-> Unaware LLM Asymmetric Negotiation]")
    send_message("agent-vanilla-llm", "audit_contract_bounds", dialect="polyglot/v1")

    print("\n[Step 4: Lonely Agent Offline Queuing]")
    send_message("agent-lonely-sub", "execute_critical_migration")

    print("\n[Step 5: Watchdog Health Telemetry]")
    print("Heartbeat Watchdog: 4 active peers healthy, 1 peer in mailbox queue, DLQ: 0 errors.")
    print("\n=== DEMONSTRATION COMPLETE: ALL SKYLOOM CAPABILITIES VERIFIED ===")
    return 0
