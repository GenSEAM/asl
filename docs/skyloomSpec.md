# SkyLoom — moved

SkyLoom is the session layer of the AgentScript wire protocol, and it is specified in
**[`AGENTIC_PROTOCOL.md`](AGENTIC_PROTOCOL.md) Part II**.

This file used to carry a second, drifting copy of that specification: three dialects where the
implementation has four, `HEARTBEAT_PING` where the implementation says `PING`, eight error codes
where there are ten, and header types (`U16`, `UUID`, `U32`) that AgentScript does not have. It is
now a pointer so that each fact has exactly one home.

| Looking for | Go to |
|---|---|
| Sigils, frame grammar, value syntax, protocol version, error taxonomy | `AGENTIC_PROTOCOL.md` Part I |
| Dialects, frame types, frame structure, negotiation, heartbeat, handoff | `AGENTIC_PROTOCOL.md` Part II |
| The language itself | `AGENT_SPEC_CORE.md` |
| How payload data is written | `docs/ASN_SPEC.md` |
| Day-to-day agent usage | `skills/skyloom/SKILL.md` |

Implementation: `packages/asl-skyloom/src/` (TypeScript), `packages/asl-skyloom/src/core/skyloom.asl`
(protocol algebra), `tools/a2a_wire.py` (frame-layer reference codec).
