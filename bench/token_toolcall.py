#!/usr/bin/env python3
"""Token counts for tool calling: JSON vs ASL S-Expression.

Compares standard OpenAI/Anthropic function call format against
native AgentScript S-expression tool invocations.
"""
import argparse
import json
import sys
from pathlib import Path

LOCK = Path(__file__).with_name("token_toolcall.lock")
ENCODING = "cl100k_base"

TOOL_CALLS = {
    "json-tool-call": """{
  "type": "function",
  "function": {
    "name": "search_ecosystem",
    "arguments": "{\"query\": \"cryptography\", \"ecosystem\": \"crates\", \"limit\": 10}"
  }
}""",
    "asl-keyed-call": "(call :tool search-ecosystem :query \"cryptography\" :ecosystem \"crates\" :limit 10)",
    "asl-positional-call": "(call search-ecosystem \"cryptography\" \"crates\" 10)",
}

def counts() -> dict[str, int]:
    try:
        import tiktoken
        enc = tiktoken.get_encoding(ENCODING)
        return {name: len(enc.encode(text)) for name, text in TOOL_CALLS.items()}
    except ImportError:
        return {name: max(1, len(text.split())) for name, text in TOOL_CALLS.items()}

def main() -> int:
    got = counts()
    json_count = got["json-tool-call"]
    asl_keyed = got["asl-keyed-call"]
    asl_pos = got["asl-positional-call"]
    saving_keyed = round((1 - asl_keyed / json_count) * 100, 1)
    saving_pos = round((1 - asl_pos / json_count) * 100, 1)

    print(f"{chr(61)*60}")
    print(f"{chr(32)*15}TOOL CALLING TOKEN BENCHMARK")
    print(f"{chr(61)*60}")
    print(f"Format                 Tokens   Reduction vs JSON")
    print(f"{chr(45)*60}")
    print(f"Standard JSON Tool     {json_count:<8} baseline")
    print(f"ASL Keyed Call         {asl_keyed:<8} -{saving_keyed}%")
    print(f"ASL Positional Call    {asl_pos:<8} -{saving_pos}%")
    print(f"{chr(61)*60}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
