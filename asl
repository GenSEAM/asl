#!/bin/sh
# ASL (AgentScript Language) CLI Wrapper
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$ROOT/.venv/bin/python" ]; then
    PY="$ROOT/.venv/bin/python"
elif [ -x "$ROOT/.venv/bin/python3" ]; then
    PY="$ROOT/.venv/bin/python3"
else
    PY="python3"
fi
exec "$PY" "$ROOT/agentscript" "$@"
