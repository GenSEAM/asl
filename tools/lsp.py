#!/usr/bin/env python3
"""Language Server Protocol (LSP 3.17) Engine with Virtual Projections for AgentScript (@pcp:r-8d8e)."""

import sys
import json
import re
from pathlib import Path
from typing import Dict, Any, Optional, List

ROOT = Path(__file__).resolve().parent.parent


class AslLspServer:
    """Stdlib-only JSON-RPC 2.0 LSP Server for AgentScript."""

    def __init__(self):
        self.documents: Dict[str, str] = {}
        self.root_path: Path = ROOT

    def handle_request(self, request: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Dispatches JSON-RPC request to appropriate LSP handler."""
        req_id = request.get("id")
        method = request.get("method", "")
        params = request.get("params", {})

        if method == "initialize":
            return self._response(req_id, {
                "capabilities": {
                    "textDocumentSync": 1,  # Full sync
                    "hoverProvider": True,
                    "definitionProvider": True,
                    "documentSymbolProvider": True,
                    "experimental": {
                        "virtualDocumentProvider": True
                    }
                },
                "serverInfo": {
                    "name": "agentscript-lsp",
                    "version": "1.0.0"
                }
            })

        elif method == "textDocument/didOpen":
            doc = params.get("textDocument", {})
            uri = doc.get("uri", "")
            text = doc.get("text", "")
            self.documents[uri] = text
            return None

        elif method == "textDocument/didChange":
            doc = params.get("textDocument", {})
            uri = doc.get("uri", "")
            changes = params.get("contentChanges", [])
            if changes:
                self.documents[uri] = changes[-1].get("text", "")
            return None

        elif method == "textDocument/hover":
            uri = params.get("textDocument", {}).get("uri", "")
            pos = params.get("position", {})
            line_idx = pos.get("line", 0)
            char_idx = pos.get("character", 0)
            text = self.documents.get(uri, "")
            hover_content = self._compute_hover(text, line_idx, char_idx)
            return self._response(req_id, hover_content)

        elif method == "textDocument/definition":
            uri = params.get("textDocument", {}).get("uri", "")
            pos = params.get("position", {})
            text = self.documents.get(uri, "")
            loc = self._compute_definition(uri, text, pos.get("line", 0), pos.get("character", 0))
            return self._response(req_id, loc)

        elif method in ("asl/virtualDocument", "asl/preview"):
            # Non-mutating virtual document provider (@pcp:r-8d8e)
            target_uri = params.get("uri", "")
            scheme = params.get("projection", "verbose")
            dialect = params.get("dialect", "postgres")
            content = self._compute_virtual_document(target_uri, scheme, dialect)
            return self._response(req_id, {"content": content})

        elif method == "shutdown":
            return self._response(req_id, None)

        elif method == "exit":
            return None

        # Unknown method
        if req_id is not None:
            return self._response(req_id, None)
        return None

    def _response(self, req_id: Any, result: Any) -> Dict[str, Any]:
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": result
        }

    def _compute_hover(self, text: str, line: int, char: int) -> Optional[Dict[str, Any]]:
        lines = text.splitlines()
        if line >= len(lines):
            return None
        curr_line = lines[line]
        word = self._extract_word_at(curr_line, char)
        if not word:
            return None

        pattern = rf'\((defun|defschema|defenum)\s+{re.escape(word)}\b'
        match = re.search(pattern, text)
        if match:
            kind = match.group(1)
            snippet = text[match.end():match.end() + 500]
            doc_match = re.search(r':doc\s+"([^"]+)"', snippet)
            doc_str = doc_match.group(1) if doc_match else "No docstring provided."
            markdown = f"**AgentScript `{word}`** ({kind})\n\n{doc_str}"
            return {"contents": {"kind": "markdown", "value": markdown}}

        # Check standard prelude
        if word in ("map", "filter", "fold", "str", "string-join", "try", "match", "let"):
            markdown = f"**AgentScript Builtin `{word}`**\n\nStandard sound prelude form."
            return {"contents": {"kind": "markdown", "value": markdown}}

        return None

    def _compute_definition(self, uri: str, text: str, line: int, char: int) -> Optional[Dict[str, Any]]:
        lines = text.splitlines()
        if line >= len(lines):
            return None
        word = self._extract_word_at(lines[line], char)
        if not word:
            return None

        # Find line where (defun word ...) or (defschema word ...) appears
        for idx, l in enumerate(lines):
            if re.search(rf'\((defun|defschema|defenum)\s+{re.escape(word)}\b', l):
                return {
                    "uri": uri,
                    "range": {
                        "start": {"line": idx, "character": 0},
                        "end": {"line": idx, "character": len(l)}
                    }
                }
        return None

    def _compute_virtual_document(self, uri: str, projection: str, dialect: str) -> str:
        """Computes virtual projection without touching disk files (@pcp:r-8d8e)."""
        content = self.documents.get(uri, "")
        if not content and uri.startswith("file://"):
            p = Path(uri[7:])
            if p.exists():
                content = p.read_text(encoding="utf-8")

        if projection == "sql" or "sql" in uri:
            from tools.sql_cli import parse_sql_sexpr, AslSqlRenderer
            try:
                tree = parse_sql_sexpr(content)
                renderer = AslSqlRenderer(dialect=dialect)
                sql, params = renderer.render_query_tree(tree)
                return f"-- Live Virtual SQL Projection [{dialect.upper()}]\n-- Bound Parameters: {params}\n\n{sql}"
            except Exception as e:
                return f"-- SQL AST Parsing Error: {e}\n\n{content}"

        # Verbose ASL projection
        return content

    def _extract_word_at(self, line: str, char: int) -> str:
        if not line or char >= len(line):
            return ""
        # Delimiters in Lisp: spaces, parentheses, brackets, quotes
        delims = " ()[]{}\"'"
        start = char
        while start > 0 and line[start - 1] not in delims:
            start -= 1
        end = char
        while end < len(line) and line[end] not in delims:
            end += 1
        return line[start:end]

    def run_stdio(self):
        """Runs the JSON-RPC stdio event loop."""
        while True:
            line = sys.stdin.readline()
            if not line:
                break
            line = line.strip()
            if not line.startswith("Content-Length:"):
                continue
            length = int(line.split(":")[1].strip())
            # Skip empty separator line
            sys.stdin.readline()
            body_bytes = sys.stdin.read(length)
            try:
                request = json.loads(body_bytes)
                response = self.handle_request(request)
                if response is not None:
                    res_body = json.dumps(response)
                    sys.stdout.write(f"Content-Length: {len(res_body)}\r\n\r\n{res_body}")
                    sys.stdout.flush()
            except Exception as e:
                pass


def run_lsp_cli(args) -> int:
    """Entry point for asl lsp."""
    server = AslLspServer()
    server.run_stdio()
    return 0


if __name__ == "__main__":
    server = AslLspServer()
    server.run_stdio()
