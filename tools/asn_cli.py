#!/usr/bin/env python3
"""AgentScript Notation (ASN) CLI Transcoder and Conformance Checker (@pcp:d-bda8, @pcp:d-b0a9).

Provides:
  --to-json <data.asn>     Transcode ASN document to JSON
  --from-json <data.json>  Transcode JSON document to ASN
  --check <data.asn>       Validate ASN document against §11 error set
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent


def ensure_venv() -> None:
    """Re-executes under project virtualenv if invoked via system Python."""
    venv_py = ROOT / ".venv" / "bin" / "python"
    venv_dir = (ROOT / ".venv").resolve()
    if venv_py.exists():
        try:
            if Path(sys.prefix).resolve() != venv_dir:
                os.execv(str(venv_py), [str(venv_py)] + sys.argv)
        except Exception:
            pass


def unescape_asn_string(s: str) -> str:
    """Strips quotes and decodes Core §2 five escapes."""
    if len(s) >= 2 and s.startswith('"') and s.endswith('"'):
        inner = s[1:-1]
    else:
        inner = s
    out = []
    esc = False
    for c in inner:
        if esc:
            if c == "n":
                out.append("\n")
            elif c == "t":
                out.append("\t")
            elif c == "r":
                out.append("\r")
            elif c == "0":
                out.append("\0")
            elif c == '"':
                out.append('"')
            elif c == "\\":
                out.append("\\")
            else:
                out.append(c)
            esc = False
        elif c == "\\":
            esc = True
        else:
            out.append(c)
    return "".join(out)


def escape_asn_string(s: str) -> str:
    """Escapes string under Core §2."""
    escaped = (
        s.replace("\\", "\\\\")
         .replace('"', '\\"')
         .replace("\n", "\\n")
         .replace("\t", "\\t")
         .replace("\r", "\\r")
         .replace("\0", "\\0")
    )
    return f'"{escaped}"'


def is_valid_keyword(s: str) -> bool:
    """Checks if s is a valid kebab-case identifier for an ASN keyword."""
    return bool(re.match(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*[?!]?$', s))


def asn_tree_to_json(tree: Any, pool: Any = None) -> Any:
    """Converts a Lark ASN ParseTree to a JSON-serializable Python structure."""
    from lark import Token, Tree

    if isinstance(tree, Token):
        if tree.type == "INT":
            return int(tree.value)
        elif tree.type == "FLOAT":
            return float(tree.value)
        elif tree.type == "STRING":
            return unescape_asn_string(tree.value)
        elif tree.type == "BOOL":
            return tree.value == "true"
        elif tree.type == "UNIT":
            return None
        elif tree.type == "KEYWORD":
            return tree.value[1:] if tree.value.startswith(":") else tree.value
        elif tree.type == "WILDCARD":
            return None
        return tree.value

    if tree.data in ("start", "value", "scalar"):
        return asn_tree_to_json(tree.children[0], pool=pool)

    elif tree.data == "vector":
        return [asn_tree_to_json(c, pool=pool) for c in tree.children]

    elif tree.data == "record":
        record_pool = pool
        for i in range(0, len(tree.children), 2):
            k = tree.children[i].value
            if k == ":pool":
                record_pool = asn_tree_to_json(tree.children[i + 1])
                break

        if len(tree.children) == 2 and tree.children[0].value == ":ref":
            ref_val = asn_tree_to_json(tree.children[1], pool=record_pool)
            if record_pool is not None and isinstance(ref_val, int) and 0 <= ref_val < len(record_pool):
                return record_pool[ref_val]
            return {"ref": ref_val}

        keys = [tree.children[i].value for i in range(0, len(tree.children), 2)]
        has_data = ":data" in keys
        other_keys = [k for k in keys if k not in (":data", ":pool")]

        if has_data and other_keys:
            shared = {}
            data_val = None
            for i in range(0, len(tree.children), 2):
                k = tree.children[i].value
                v = asn_tree_to_json(tree.children[i + 1], pool=record_pool)
                if k == ":data":
                    data_val = v
                elif k != ":pool":
                    shared[k[1:] if k.startswith(":") else k] = v

            if isinstance(data_val, list):
                out_list = []
                for item in data_val:
                    if isinstance(item, dict):
                        merged = dict(shared)
                        merged.update(item)
                        out_list.append(merged)
                    else:
                        out_list.append(item)
                return out_list
            elif isinstance(data_val, dict):
                merged = dict(shared)
                merged.update(data_val)
                return merged
            return data_val

        rec = {}
        for i in range(0, len(tree.children), 2):
            k = tree.children[i].value
            v = asn_tree_to_json(tree.children[i + 1], pool=record_pool)
            rec_key = k[1:] if k.startswith(":") else k
            rec[rec_key] = v
        return rec

    elif tree.data == "ctor":
        rec = {}
        for i in range(1, len(tree.children), 2):
            k = tree.children[i].value
            v = asn_tree_to_json(tree.children[i + 1], pool=pool)
            rec_key = k[1:] if k.startswith(":") else k
            rec[rec_key] = v
        return rec

    elif tree.data == "table":
        cols = []
        rows = []
        for c in tree.children:
            if isinstance(c, Token) and c.type == "KEYWORD":
                col_name = c.value[1:] if c.value.startswith(":") else c.value
                cols.append(col_name)
            elif isinstance(c, Tree) and c.data == "row":
                row_vals = [asn_tree_to_json(rc, pool=pool) for rc in c.children]
                rows.append(row_vals)

        out = []
        for r in rows:
            obj = {}
            for col, val in zip(cols, r):
                obj[col] = val
            out.append(obj)
        return out

    elif tree.data == "row_group":
        rows = []
        for c in tree.children[1:]:
            if isinstance(c, Tree) and c.data == "row":
                rows.append([asn_tree_to_json(rc, pool=pool) for rc in c.children])
        return rows

    elif tree.data == "map":
        m = {}
        for entry in tree.children:
            if entry.data == "kw_entry":
                k = entry.children[0].value
                v = asn_tree_to_json(entry.children[1], pool=pool)
                k_str = k[1:] if k.startswith(":") else k
                m[k_str] = v
            elif entry.data == "pair_entry":
                k_tok = entry.children[0].children[0]
                k_str = unescape_asn_string(k_tok.value) if k_tok.type == "STRING" else str(k_tok.value)
                v = asn_tree_to_json(entry.children[1], pool=pool)
                m[k_str] = v
        return m

    elif tree.data == "case_value":
        case_name = (
            tree.children[0].children[0].value
            if isinstance(tree.children[0], Tree)
            else str(tree.children[0])
        )
        args = [asn_tree_to_json(c, pool=pool) for c in tree.children[1:]]
        return {"case": case_name, "values": args}

    return str(tree)


def json_to_asn(val: Any, table_mode: bool = False) -> str:
    """Converts a Python/JSON value to canonical ASN string."""
    if val is None:
        return "_"
    elif isinstance(val, bool):
        return "true" if val else "false"
    elif isinstance(val, int):
        return str(val)
    elif isinstance(val, float):
        s = str(val)
        return s if "." in s else s + ".0"
    elif isinstance(val, str):
        return escape_asn_string(val)
    elif isinstance(val, list):
        if not val:
            return "[]"

        if table_mode and all(isinstance(x, dict) and x for x in val):
            first_keys = list(val[0].keys())
            if all(list(x.keys()) == first_keys and all(is_valid_keyword(k) for k in first_keys) for x in val):
                headers = " ".join(f":{k}" for k in first_keys)
                row_strs = []
                for item in val:
                    cells = " ".join(json_to_asn(item[k], table_mode) for k in first_keys)
                    row_strs.append(f"[{cells}]")
                return f"([ {headers} ] [ {' '.join(row_strs)} ])"

        items = " ".join(json_to_asn(x, table_mode) for x in val)
        return f"[{items}]"
    elif isinstance(val, dict):
        if not val:
            return "{}"

        if all(isinstance(k, str) and is_valid_keyword(k) for k in val.keys()):
            pairs = " ".join(f":{k} {json_to_asn(v, table_mode)}" for k, v in val.items())
            return f"({pairs})"
        else:
            entries = []
            for k, v in val.items():
                if isinstance(k, str) and is_valid_keyword(k):
                    entries.append(f":{k} {json_to_asn(v, table_mode)}")
                else:
                    k_str = json_to_asn(k, table_mode)
                    entries.append(f"({k_str} {json_to_asn(v, table_mode)})")
            return f"{{ {' '.join(entries)} }}"
    else:
        return escape_asn_string(str(val))


def run_to_json(path_str: str, indent: int = 2) -> int:
    path = Path(path_str)
    if not path.exists():
        print(f"Error: file '{path_str}' not found", file=sys.stderr)
        return 1
    ensure_venv()
    try:
        sys.path.insert(0, str(ROOT / "grammar"))
        from validate_asn import parser
        p = parser()
        tree = p.parse(path.read_text())
        val = asn_tree_to_json(tree)
        print(json.dumps(val, indent=indent))
        return 0
    except Exception as e:
        print(f"Error converting '{path_str}' to JSON: {e}", file=sys.stderr)
        return 1


def run_from_json(path_str: str, table_mode: bool = False) -> int:
    path = Path(path_str)
    if not path.exists():
        print(f"Error: file '{path_str}' not found", file=sys.stderr)
        return 1
    try:
        data = json.loads(path.read_text())
        asn_text = json_to_asn(data, table_mode=table_mode)
        print(asn_text)
        return 0
    except Exception as e:
        print(f"Error converting '{path_str}' to ASN: {e}", file=sys.stderr)
        return 1


def run_check(path_str: str) -> int:
    path = Path(path_str)
    if not path.exists():
        print(f"Error: file '{path_str}' not found", file=sys.stderr)
        return 1
    ensure_venv()
    try:
        sys.path.insert(0, str(ROOT / "packages" / "asl-codec" / "tests"))
        from harness import run_asl
        driver = ROOT / "packages" / "asl-codec" / "tests" / "asn_driver.asl"
        asn = run_asl(driver)
        text = path.read_text()
        verdict = asn["verdict"](text)
        if not verdict:
            print(f"✓ {path_str}: Valid ASN document (§11 clean).")
            return 0
        elif verdict.startswith("!"):
            code = verdict[1:]
            print(f"✗ {path_str}: [parse-error] {code}", file=sys.stderr)
            return 1
        else:
            print(f"✗ {path_str}: [asn-check] {verdict}", file=sys.stderr)
            return 1
    except Exception as e:
        print(f"✗ {path_str}: Check failed: {e}", file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="asn_cli.py",
        description="AgentScript Notation (ASN) Transcoder and Conformance Checker (@pcp:d-bda8, @pcp:d-b0a9)"
    )
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("--to-json", metavar="DATA.ASN", help="Transcode ASN document to JSON")
    group.add_argument("--from-json", metavar="DATA.JSON", help="Transcode JSON document to ASN")
    group.add_argument("--check", metavar="DATA.ASN", help="Validate ASN document against §11 error set")

    parser.add_argument("--indent", type=int, default=2, help="Indentation spaces for JSON output (default: 2)")
    parser.add_argument("--table", action="store_true", help="Format uniform lists of objects as ASN tables in --from-json")

    if len(sys.argv) == 1:
        parser.print_help()
        return 0

    args = parser.parse_args()

    if args.to_json:
        return run_to_json(args.to_json, indent=args.indent)
    elif args.from_json:
        return run_from_json(args.from_json, table_mode=args.table)
    elif args.check:
        return run_check(args.check)
    else:
        parser.print_help()
        return 0


if __name__ == "__main__":
    sys.exit(main())
