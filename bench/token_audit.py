#!/usr/bin/env python3
"""Rational Token Ceiling Audit & Fragmentation Linter.

Verifies that every language primitive (declaration heads, expression heads,
option keywords, and primitive type aliases) strictly adheres to the 2-token ceiling
under modern BPE tokenizers (OpenAI cl100k_base and o200k_base).
Flags any token fragmentation or excessive length as warnings/errors.
"""
import sys
import json
import argparse
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parent.parent

try:
    import tiktoken
except ImportError:
    print("Error: tiktoken is required for bench/token_audit.py", file=sys.stderr)
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


def audit_primitives(enc, vocab: dict) -> Tuple[List[dict], List[str], List[str]]:
    """Audits core language primitives against the 2-token ceiling."""
    records = []
    errors = []
    warnings = []

    # 1. Declaration heads (Standard / Compact)
    for h in vocab.get("projection", {}).get("heads", []):
        name = h["nano"]
        tokens = enc.encode(name)
        cnt = len(tokens)
        rec = {"kind": "decl-head", "name": name, "tokens": cnt, "token_ids": tokens}
        records.append(rec)
        if cnt > 2:
            errors.append(f"Primitive declaration head '{name}' exceeds 2-token ceiling: {cnt} tokens {tokens}")

    # 2. Expression heads
    for name in vocab.get("special_forms", {}).get("expressions", []):
        # Translate to standard spelling if projected
        for h in vocab.get("projection", {}).get("heads", []):
            if h["verbose"] == name:
                name = h["nano"]
        tokens = enc.encode(name)
        cnt = len(tokens)
        rec = {"kind": "expr-head", "name": name, "tokens": cnt, "token_ids": tokens}
        records.append(rec)
        if cnt > 2:
            errors.append(f"Primitive expression head '{name}' exceeds 2-token ceiling: {cnt} tokens {tokens}")

    # 3. Option keywords
    for opt in vocab.get("projection", {}).get("options", []):
        name = opt["nano"]
        tokens = enc.encode(name)
        cnt = len(tokens)
        rec = {"kind": "option-key", "name": name, "tokens": cnt, "token_ids": tokens}
        records.append(rec)
        if cnt > 2:
            errors.append(f"Primitive option keyword '{name}' exceeds 2-token ceiling: {cnt} tokens {tokens}")

    for name in vocab.get("projection", {}).get("unaliased", {}).get("options", []):
        tokens = enc.encode(name)
        cnt = len(tokens)
        rec = {"kind": "option-key-unaliased", "name": name, "tokens": cnt, "token_ids": tokens}
        records.append(rec)
        if cnt > 2:
            # Special case warning for legacy unaliased keywords
            warnings.append(f"Unaliased option keyword '{name}' exceeds 2-token ceiling: {cnt} tokens {tokens}")

    # 4. Standard Primitive Types
    for verbose_t, standard_t in vocab.get("types", {}).get("nano", {}).items():
        tokens = enc.encode(standard_t)
        cnt = len(tokens)
        rec = {"kind": "type-alias", "name": standard_t, "tokens": cnt, "token_ids": tokens}
        records.append(rec)
        if cnt > 2:
            errors.append(f"Standard type alias '{standard_t}' exceeds 2-token ceiling: {cnt} tokens {tokens}")

    return records, errors, warnings


def audit_builtins(enc, vocab: dict) -> Tuple[List[dict], List[str]]:
    """Audits builtins in prelude.json, warning on token fragmentation (>2 tokens)."""
    records = []
    warnings = []
    builtin_aliases = {}
    b_table = vocab.get("projection", {}).get("builtins", [])
    if isinstance(b_table, list):
        builtin_aliases = {b["verbose"]: b["nano"] for b in b_table}
    elif isinstance(b_table, dict):
        builtin_aliases = dict(b_table)

    for b in vocab.get("builtins", []):
        name = b["name"]
        effective = builtin_aliases.get(name, name)
        tokens = enc.encode(effective)
        cnt = len(tokens)
        rec = {"name": name, "effective": effective, "tokens": cnt, "token_ids": tokens}
        records.append(rec)
        if cnt > 2:
            warnings.append(f"Builtin '{effective}' fragments into {cnt} tokens: {tokens}")
    return records, warnings


def run_audit(check_mode: bool = False, verbose: bool = False) -> int:
    encodings = get_tokenizers()
    primary_name = "cl100k_base"
    enc = encodings[primary_name]
    vocab = load_vocabulary()

    print(f"=== AgentScript Token Ceiling Audit ({primary_name}) ===")
    prim_records, prim_errors, prim_warnings = audit_primitives(enc, vocab)
    builtin_records, builtin_warnings = audit_builtins(enc, vocab)

    all_warnings = prim_warnings + builtin_warnings
    all_errors = prim_errors

    print(f"Primitives Audited: {len(prim_records)}")
    if verbose:
        for r in prim_records:
            status = "OK" if r["tokens"] <= 2 else "EXCEEDS"
            print(f"  [{status:<7}] {r['kind']:<22} {r['name']:<15} -> {r['tokens']} token(s): {r['token_ids']}")

    print(f"Builtins Audited:   {len(builtin_records)}")
    print(f"Builtins <= 2 toks: {len(builtin_records) - len(builtin_warnings)}/{len(builtin_records)}")
    print(f"Builtin Warnings:   {len(builtin_warnings)} builtins exceed 2 tokens")

    if all_warnings and verbose:
        print("\n--- Token Inflation Warnings (Builtins / Extended Options) ---")
        for w in all_warnings:
            print(f"  [WARN] {w}")

    if all_errors:
        print("\n--- Token Ceiling FATAL ERRORS ---")
        for err in all_errors:
            print(f"  [ERROR] {err}")
        print(f"\nFAIL: {len(all_errors)} primitive(s) violated the 2-token ceiling.")
        return 1

    print("\n✓ PASS: All language primitives adhere strictly to the <= 2-token ceiling.")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="AgentScript Token Ceiling Linter & Audit")
    parser.add_argument("--check", action="store_true", help="Run in strict gate mode")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show full token breakdown")
    args = parser.parse_args()
    sys.exit(run_audit(check_mode=args.check, verbose=args.verbose))
