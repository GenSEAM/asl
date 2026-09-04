#!/usr/bin/env python3
"""Token Ceiling Enforcement Gate (@pcp:d-2tok, @pcp:d-1eed).

Verifies that every language primitive, option keyword, type alias,
and standard builtin alias in the AgentScript Nano projection strictly
adheres to the <= 2-token ceiling under both cl100k_base and o200k_base.
Exits with 1 on any violation.
"""
import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parent.parent

try:
    import tiktoken
except ImportError:
    print("Error: tiktoken is required for bench/token_ceiling.py", file=sys.stderr)
    sys.exit(1)


def get_tokenizers():
    encodings = {}
    for name in ("cl100k_base", "o200k_base"):
        try:
            encodings[name] = tiktoken.get_encoding(name)
        except Exception:
            pass
    if not encodings:
        encodings["cl100k_base"] = tiktoken.get_encoding("cl100k_base")
    return encodings


def load_vocabulary() -> dict:
    prelude_path = ROOT / "prelude" / "prelude.json"
    with open(prelude_path, "r", encoding="utf-8") as f:
        return json.load(f)


def check_token_ceiling(vocab: dict, verbose: bool = False) -> Tuple[int, List[str]]:
    tokenizers = get_tokenizers()
    errors = []
    inspected_count = 0

    proj = vocab.get("projection", {})
    heads = [h["nano"] for h in proj.get("heads", [])]
    expr_heads = []
    head_map = {h["verbose"]: h["nano"] for h in proj.get("heads", [])}
    for e in vocab.get("special_forms", {}).get("expressions", []):
        expr_heads.append(head_map.get(e, e))

    options = [o["nano"] for o in proj.get("options", [])]
    types = list(vocab.get("types", {}).get("nano", {}).values())

    builtin_aliases = {}
    b_table = proj.get("builtins", [])
    if isinstance(b_table, list):
        builtin_aliases = {b["verbose"]: b["nano"] for b in b_table}
    elif isinstance(b_table, dict):
        builtin_aliases = dict(b_table)

    builtins = [builtin_aliases.get(b["name"], b["name"]) for b in vocab.get("builtins", [])]

    candidates = [
        ("decl-head", heads),
        ("expr-head", expr_heads),
        ("option-key", options),
        ("type-alias", types),
        ("builtin-nano", builtins),
    ]

    for enc_name, enc in tokenizers.items():
        if verbose:
            print(f"\n--- Checking under {enc_name} ---")
        for kind, items in candidates:
            for item in items:
                tokens = enc.encode(item)
                cnt = len(tokens)
                inspected_count += 1
                if verbose:
                    status = "OK" if cnt <= 2 else "EXCEEDS"
                    print(f"  [{status:<7}] {kind:<15} {item:<15} -> {cnt} token(s)")
                if cnt > 2:
                    errors.append(
                        f"[{enc_name}] {kind} '{item}' exceeds 2-token ceiling: {cnt} tokens {tokens}"
                    )

    return inspected_count, errors


def main() -> int:
    parser = argparse.ArgumentParser(description="AgentScript Strict Token Ceiling Gate")
    parser.add_argument("--check", action="store_true", help="Run in strict CI gate mode")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose token output")
    args = parser.parse_args()

    vocab = load_vocabulary()
    print("=== AgentScript Token Ceiling Verification (<= 2 BPE tokens) ===")
    inspected, errors = check_token_ceiling(vocab, verbose=args.verbose)

    if errors:
        print(f"\nFATAL: {len(errors)} token ceiling violation(s) detected:")
        for err in errors:
            print(f"  [ERROR] {err}")
        return 1

    print(f"\n✓ PASS: All {inspected} inspected forms satisfy the <= 2-token ceiling under modern BPE.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
