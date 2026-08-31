#!/usr/bin/env python3
"""AgentScript Model Context Protocol (MCP) stdio JSON-RPC 2.0 server.

Exposes high-level tools for AI coding agents:
- asex_check: semantic analysis and type checking
- asex_eval: in-memory / file execution via the reference interpreter
- asex_format: canonical S-expression formatting
- asex_compress_module: token-reducing interface extraction
- asex_ast_query: tree-sitter AST queries
"""
import io
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))
sys.path.insert(0, str(ROOT / "tools"))

from resolve import Diagnostic, check_file  # noqa: E402
from fmt import fmt  # noqa: E402
from tsutil import search_json, ast_json  # noqa: E402
from mcp.compressor import compress_module  # noqa: E402

MODULES_DIR = ROOT / "grammar" / "corpus" / "modules"
INTERP_BIN = ROOT / "target" / "debug" / "agentscript-interp"

TOOLS = [
    {
        "name": "asex_check",
        "description": "Run AgentScript semantic analysis and type checking on source code or files. Returns structured diagnostics with exact lines, columns, and error codes.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "source": {"type": "string", "description": "Optional in-memory AgentScript source code to check."},
                "paths": {"type": "array", "items": {"type": "string"}, "description": "Optional list of file paths to check."}
            }
        }
    },
    {
        "name": "asex_eval",
        "description": "Execute AgentScript code using the reference interpreter. Returns stdout, stderr, and exit code.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "source": {"type": "string", "description": "In-memory AgentScript code to execute."},
                "path": {"type": "string", "description": "Path to .agentscript file to execute."},
                "args": {"type": "array", "items": {"type": "string"}, "description": "CLI arguments passed to main."}
            }
        }
    },
    {
        "name": "asex_format",
        "description": "Format AgentScript S-expressions canonically according to language style rules.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "source": {"type": "string", "description": "AgentScript source code to format."}
            },
            "required": ["source"]
        }
    },
    {
        "name": "asex_compress_module",
        "description": "Compress an AgentScript module into an interface signature (keeping headers, types, and function signatures while omitting function bodies). Saves 70-85% tokens.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "source": {"type": "string", "description": "Full AgentScript module source to compress."}
            },
            "required": ["source"]
        }
    },
    {
        "name": "asex_ast_query",
        "description": "Run a Tree-sitter S-expression query over an AgentScript module and return node captures.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "source": {"type": "string", "description": "AgentScript source code."},
                "path": {"type": "string", "description": "File path."},
                "query": {"type": "string", "description": "Tree-sitter Scheme-style query string."}
            },
            "required": ["query"]
        }
    }
]


def ensure_interp_built() -> Path:
    if not INTERP_BIN.exists():
        subprocess.run(["rustup", "run", "stable", "cargo", "build",
                        "--manifest-path", str(ROOT / "Cargo.toml")],
                       check=True, cwd=ROOT, capture_output=True, text=True)
    return INTERP_BIN


def handle_check(args: dict) -> dict:
    source = args.get("source")
    paths = args.get("paths") or []
    roots = [MODULES_DIR]
    diags: list[Diagnostic] = []

    if source:
        with tempfile.NamedTemporaryFile(suffix=".agentscript", mode="w", delete=False) as tf:
            tf.write(source)
            tmp_path = Path(tf.name)
        try:
            diags += check_file(tmp_path, roots)
        finally:
            if tmp_path.exists():
                tmp_path.unlink()

    for p in paths:
        path_obj = Path(p)
        if path_obj.exists():
            diags += check_file(path_obj, roots)

    return {
        "valid": len(diags) == 0,
        "diagnostics": [
            {"file": d.path, "line": d.line, "col": d.col, "code": d.code, "message": d.message}
            for d in diags
        ]
    }


def handle_eval(args: dict) -> dict:
    source = args.get("source")
    path_str = args.get("path")
    cli_args = args.get("args") or []
    roots = [MODULES_DIR]
    bin_path = ensure_interp_built()

    if source:
        with tempfile.NamedTemporaryFile(suffix=".agentscript", mode="w", delete=False) as tf:
            tf.write(source)
            target_path = Path(tf.name)
        cleanup = True
    elif path_str:
        target_path = Path(path_str)
        cleanup = False
    else:
        return {"stdout": "", "stderr": "No source or path provided", "exit_code": 1, "success": False}

    try:
        cmd = [str(bin_path)]
        for r in roots:
            cmd += ["--root", str(r)]
        cmd += [str(target_path)] + cli_args
        res = subprocess.run(cmd, capture_output=True, text=True)
        return {
            "stdout": res.stdout,
            "stderr": res.stderr,
            "exit_code": res.returncode,
            "success": res.returncode == 0
        }
    finally:
        if cleanup and target_path.exists():
            target_path.unlink()


def handle_format(args: dict) -> dict:
    source = args.get("source", "")
    try:
        formatted = fmt.format_source(source)
        changed = formatted != source
        return {
            "formatted": formatted,
            "changed": changed,
            "diagnostics": []
        }
    except fmt.FormatError as exc:
        d = exc.diag
        return {
            "formatted": source,
            "changed": False,
            "diagnostics": [
                {"file": d.path, "line": d.line, "col": d.col, "code": d.code, "message": d.message}
            ]
        }


def handle_compress(args: dict) -> dict:
    source = args.get("source", "")
    compressed = compress_module(source)
    return {"compressed": compressed}


def handle_ast_query(args: dict) -> dict:
    source = args.get("source")
    path_str = args.get("path")
    query = args.get("query", "")

    if source:
        with tempfile.NamedTemporaryFile(suffix=".agentscript", mode="w", delete=False) as tf:
            tf.write(source)
            target_path = Path(tf.name)
        cleanup = True
    elif path_str:
        target_path = Path(path_str)
        cleanup = False
    else:
        return {"captures": [], "error": "No source or path provided"}

    try:
        captures = search_json(target_path, query)
        return {"captures": captures}
    except Exception as exc:
        return {"captures": [], "error": str(exc)}
    finally:
        if cleanup and target_path.exists():
            target_path.unlink()


TOOL_HANDLERS = {
    "asex_check": handle_check,
    "asex_eval": handle_eval,
    "asex_format": handle_format,
    "asex_compress_module": handle_compress,
    "asex_ast_query": handle_ast_query,
}


def process_message(msg: dict) -> dict | None:
    msg_id = msg.get("id")
    method = msg.get("method")
    params = msg.get("params", {})

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "asex-mcp", "version": "1.0.0"}
            }
        }
    elif method == "notifications/initialized":
        return None
    elif method == "ping":
        return {"jsonrpc": "2.0", "id": msg_id, "result": {}}
    elif method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {"tools": TOOLS}
        }
    elif method == "tools/call":
        tool_name = params.get("name")
        tool_args = params.get("arguments", {})
        handler = TOOL_HANDLERS.get(tool_name)
        if not handler:
            return {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {"code": -32601, "message": f"Method '{tool_name}' not found"}
            }
        try:
            res = handler(tool_args)
            return {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(res, indent=2)}]
                }
            }
        except Exception as exc:
            return {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {"code": -32603, "message": str(exc)}
            }
    else:
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {"code": -32601, "message": f"Unknown method: {method}"}
        }


def run_stdio_server():
    input_stream = sys.stdin.buffer
    output_stream = sys.stdout.buffer

    while True:
        line = input_stream.readline()
        if not line:
            break
        line_str = line.decode("utf-8")
        if line_str.startswith("Content-Length:"):
            length = int(line_str.split(":", 1)[1].strip())
            # consume blank lines
            while True:
                header = input_stream.readline().decode("utf-8")
                if header in ("\r\n", "\n", ""):
                    break
            body = input_stream.read(length).decode("utf-8")
        else:
            body = line_str.strip()
            if not body:
                continue

        try:
            req = json.loads(body)
        except Exception as exc:
            err_resp = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": str(exc)}}
            out_bytes = json.dumps(err_resp).encode("utf-8") + b"\n"
            output_stream.write(out_bytes)
            output_stream.flush()
            continue

        resp = process_message(req)
        if resp is not None:
            out_bytes = json.dumps(resp).encode("utf-8") + b"\n"
            output_stream.write(out_bytes)
            output_stream.flush()


if __name__ == "__main__":
    run_stdio_server()
