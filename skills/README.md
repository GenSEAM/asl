# Official AgentScript (ASL) Agent Skills

Universal agent skills for Claude Code, Cursor, Antigravity, Windsurf, OpenDevin, and OpenAI Swarm.

## Installation
```bash
# Install the language reference into the local workspace (.skills/asl)
asl skill install asl

# Install into global harness config
asl skill --install global
```

## Available skills

`asl skill list` reads this directory, so the list below and the command cannot disagree.

- `asl` — the language reference: compact syntax, the closed vocabulary, the semantic rules, the
  CLI and the MCP tools. **Generated** from `prelude/prelude.json` by `prelude/generate.py`;
  editing `skills/asl/SKILL.md` by hand is work the `--check` gate will reject.
- `seambus` (`skyloom`) — the inter-agent protocol: frames, dialect negotiation, `pass`/`ret` delegations and the swarm mesh.

## License
Dual-licensed MIT or Apache-2.0, at your option. © GenSEAM Core Team
