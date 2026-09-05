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
        # In-memory RAM index for decoupled metadata tags (O(1) in <0.05ms)
        self.tag_index: Dict[str, List[Dict[str, Any]]] = {}
        self.node_index: Dict[str, List[Dict[str, Any]]] = {}

    def _index_document(self, uri: str, text: str) -> None:
        """Indexes all :tag and @tag annotations in document into RAM (@pcp:d-1eed)."""
        # Clear existing entries for this URI
        for tag_id, spans in list(self.tag_index.items()):
            self.tag_index[tag_id] = [s for s in spans if s.get("uri") != uri]
            if not self.tag_index[tag_id]:
                del self.tag_index[tag_id]
        self.node_index[uri] = []

        lines = text.splitlines()
        # Find all declarations
        decl_re = re.compile(r'\(((?:defun|def|df|defschema|schema|dfs|defenum|enum|dfe|module))\s+(?:!\s+)?(?:\{[^}]*\}\s+)?([a-zA-Z0-9_\-\/]+)', re.MULTILINE)
        for m in decl_re.finditer(text):
            kind = m.group(1)
            name = m.group(2)
            start_pos = m.start()
            start_line = text[:start_pos].count('\n')
            # Extract exact declaration snippet using balanced parentheses
            depth = 0
            end_pos = len(text)
            for i in range(start_pos, len(text)):
                if text[i] == '(':
                    depth += 1
                elif text[i] == ')':
                    depth -= 1
                    if depth == 0:
                        end_pos = i + 1
                        break
            snippet = text[start_pos:end_pos]
            end_line = text[:end_pos].count('\n')
            # Docstring (either :doc or :d)
            doc_m = re.search(r'(?::doc|:d)\s+"([^"\\]*(?:\\.[^"\\]*)*)"', snippet)
            doc_str = doc_m.group(1) if doc_m else ""

            # Extract tags inside this declaration
            tags_map: Dict[str, Any] = {}
            for tm in re.finditer(r'\((?::tag|@tag)\s+([^)]*)\)', snippet):
                raw = tm.group(1).strip()
                for kv in re.finditer(r':([a-zA-Z0-9_\-]+)\s+(?:"([^"\\]*(?:\\.[^"\\]*)*)"|([a-zA-Z0-9_\-\/]+))', raw):
                    k = kv.group(1)
                    v = kv.group(2) if kv.group(2) is not None else kv.group(3)
                    tags_map[k] = v
                for s in re.finditer(r'"([^"\\]*(?:\\.[^"\\]*)*)"', raw):
                    val = s.group(1)
                    if val not in tags_map.values():
                        tags_map.setdefault("id", val)

            end_line = min(len(lines) - 1, start_line + snippet.count('\n'))
            node_span = {
                "uri": uri,
                "name": name,
                "kind": kind,
                "range": {
                    "start": {"line": start_line, "character": 0},
                    "end": {"line": end_line, "character": len(lines[end_line]) if end_line < len(lines) else 0}
                },
                "doc": doc_str,
                "tags": tags_map
            }
            self.node_index[uri].append(node_span)

            # Index every tag identifier
            for tag_val in list(tags_map.values()):
                if isinstance(tag_val, str):
                    self.tag_index.setdefault(tag_val, []).append(node_span)
            for tag_k, tag_v in tags_map.items():
                if isinstance(tag_v, str):
                    self.tag_index.setdefault(f"{tag_k}:{tag_v}", []).append(node_span)

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
                        "virtualDocumentProvider": True,
                        "metadataIndexing": True
                    }
                },
                "serverInfo": {
                    "name": "agentscript-lsp",
                    "version": "0.3.0"
                }
            })

        elif method == "textDocument/didOpen":
            doc = params.get("textDocument", {})
            uri = doc.get("uri", "")
            text = doc.get("text", "")
            self.documents[uri] = text
            self._index_document(uri, text)
            return None

        elif method == "textDocument/didChange":
            doc = params.get("textDocument", {})
            uri = doc.get("uri", "")
            changes = params.get("contentChanges", [])
            if changes:
                text = changes[-1].get("text", "")
                self.documents[uri] = text
                self._index_document(uri, text)
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

        elif method in ("lsp/tag-lookup", "asl/tagLookup", "tagLookup"):
            # O(1) in-memory tag lookup (<0.05ms)
            tag = params.get("tag") or params.get("tag_id") or params.get("id", "")
            matches = self.tag_index.get(tag, [])
            return self._response(req_id, {"tag": tag, "results": matches, "count": len(matches)})

        elif method in ("lsp/node-meta", "asl/nodeMeta", "nodeMeta"):
            target_uri = params.get("uri") or params.get("file", "")
            line = params.get("line", 0)
            meta = self._compute_node_meta(target_uri, line)
            return self._response(req_id, meta)

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

    def _compute_node_meta(self, file_or_uri: str, line: int) -> Optional[Dict[str, Any]]:
        """Returns node metadata and decoupled tags for a given line."""
        for uri, nodes in self.node_index.items():
            if uri == file_or_uri or file_or_uri in uri:
                for node in nodes:
                    start_l = node["range"]["start"]["line"]
                    end_l = node["range"]["end"]["line"]
                    if start_l <= line <= end_l:
                        return node
        return None

    def _compute_hover(self, text: str, line: int, char: int) -> Optional[Dict[str, Any]]:
        lines = text.splitlines()
        if line >= len(lines):
            return None
        curr_line = lines[line]
        word = self._extract_word_at(curr_line, char)
        if not word:
            return None

        # Check if hovering on a tag identifier
        if word in self.tag_index:
            tag_nodes = self.tag_index[word]
            refs = [f"- `{n['name']}` ({n['kind']}) in `{n['uri'].split('/')[-1]}`:L{n['range']['start']['line']+1}" for n in tag_nodes[:5]]
            markdown = f"**Decoupled Semantic Tag `{word}`**\n\nImplemented/Referenced by:\n" + "\n".join(refs)
            return {"contents": {"kind": "markdown", "value": markdown}}

        pattern = rf'\((defun|def|df|defschema|schema|dfs|defenum|enum|dfe|module)\s+(?:!\s+)?(?:\{{[^}}]*\}}\s+)?{re.escape(word)}\b'
        match = re.search(pattern, text)
        if match:
            kind = match.group(1)
            snippet = text[match.end():match.end() + 1000]
            doc_match = re.search(r'(?::doc|:d)\s+"([^"\\]*(?:\\.[^"\\]*)*)"', snippet)
            doc_str = doc_match.group(1) if doc_match else "No docstring provided."

            # Extract tags in snippet
            tags_list = []
            for tm in re.finditer(r'\((?::tag|@tag)\s+([^)]*)\)', snippet):
                raw = tm.group(1).strip()
                for kv in re.finditer(r':([a-zA-Z0-9_\-]+)\s+(?:"([^"\\]*(?:\\.[^"\\]*)*)"|([a-zA-Z0-9_\-\/]+))', raw):
                    k = kv.group(1)
                    v = kv.group(2) if kv.group(2) is not None else kv.group(3)
                    tags_list.append(f"- `:{k}`: `\"{v}\"`")

            tags_section = f"\n\n**Metadata Tags:**\n" + "\n".join(tags_list) if tags_list else ""
            markdown = f"**AgentScript `{word}`** ({kind})\n\n{doc_str}{tags_section}"
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

        # Check if word is a tag id
        if word in self.tag_index and self.tag_index[word]:
            target_node = self.tag_index[word][0]
            return {
                "uri": target_node["uri"],
                "range": target_node["range"]
            }

        # Find line where (defun word ...) or (df word ...) appears
        for idx, l in enumerate(lines):
            if re.search(rf'\((?:defun|def|df|defschema|schema|dfs|defenum|enum|dfe|module)\s+(?:!\s+)?(?:\{{[^}}]*\}}\s+)?{re.escape(word)}\b', l):
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

        # The projection is a conversion, not a label: this returned the buffer
        # unchanged, so a Nano module previewed as Nano (@pcp:d-1eed). The
        # transcoder is handed text and never the file, so the preview cannot
        # mutate it (@pcp:r-8d8e).
        from tools.transcoder import NANO, VERBOSE, TranscodeError, transcode_text
        target = NANO if projection == NANO else VERBOSE
        try:
            return transcode_text(content, target, uri)
        except TranscodeError as exc:
            return f"; projection unavailable: {exc}\n\n{content}"

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
