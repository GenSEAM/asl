#!/usr/bin/env python3
"""
AgP Wire Protocol — Reference Handshake & Frame Codec in Python
Runs over stdio, MCP, Unix Sockets, and SSE transports.
"""

import sys
import json
import re
from typing import Optional, Dict, Any

HANDSHAKE_PROBE = '(?agent/probe :proto "asl/1.0")'
HANDSHAKE_ACK = '(!agent/ack :proto "asl/1.0" :mode :nano)'

class AgpWireSession:
    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        self.handshake_complete = False
        self.compression_mode = "nano"

    def probe(self) -> str:
        return HANDSHAKE_PROBE

    def accept_probe(self, line: str) -> Optional[str]:
        if '?agent/probe' in line and 'asl/1.0' in line:
            self.handshake_complete = True
            return HANDSHAKE_ACK
        return None

    def handle_ack(self, line: str) -> bool:
        if '!agent/ack' in line and 'asl/1.0' in line:
            self.handshake_complete = True
            return True
        return False

    def encode_query(self, target: str, action: str, **kwargs) -> str:
        params = " ".join(f":{k} {json.dumps(v)}" for k, v in kwargs.items())
        return f"(? {target} {action} {params})".strip()

    def encode_response(self, ok_payload: Any = None, err_code: str = None, msg: str = None) -> str:
        if err_code:
            return f'(! {self.agent_id} :err "{err_code}" :msg "{msg or ""}")'
        return f'(! {self.agent_id} :ok {json.dumps(ok_payload)})'

    def decode_frame(self, line: str) -> Dict[str, Any]:
        line = line.strip()
        if line.startswith("(?"):
            m = re.match(r'\(\?\s+(\S+)\s+(\S+)(.*)\)', line)
            if m:
                target, action, rest = m.groups()
                return {"type": "query", "target": target, "action": action, "raw_params": rest.strip()}
        elif line.startswith("(!"):
            m = re.match(r'\(!\s+(\S+)\s+:(ok|err)\s+(.*)\)', line)
            if m:
                sender, status, payload = m.groups()
                return {"type": "response", "sender": sender, "status": status, "payload": payload.strip()}
        return {"type": "raw", "content": line}

if __name__ == "__main__":
    session = AgpWireSession("agent-orchestrator")
    query = session.encode_query("agent-coder", "synthesize", states=["idle", "active"], timeout=50)
    print(f"Sample AgP Query Frame: {query}")
    decoded = session.decode_frame(query)
    print(f"Decoded: {decoded}")
