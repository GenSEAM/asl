"""Unit tests for AgentScript LSP 3.17 server and virtual document provider."""

import pytest
from tools.lsp import AslLspServer


def test_lsp_initialize():
    server = AslLspServer()
    resp = server.handle_request({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
    assert resp["id"] == 1
    assert resp["result"]["capabilities"]["hoverProvider"] is True
    assert resp["result"]["capabilities"]["definitionProvider"] is True
    assert resp["result"]["capabilities"]["experimental"]["virtualDocumentProvider"] is True


def test_lsp_hover_and_definition():
    server = AslLspServer()
    doc_uri = "file:///workspace/test.asl"
    code = """(module test/math
  :doc "Math utilities")

(defschema Vector2D
  (:field x Int64 "X coordinate")
  (:field y Int64 "Y coordinate"))

(defun add-vec [(v Vector2D)] -> Int64
  :doc "Computes coordinate sum"
  (+ (.-x v) (.-y v)))
"""
    server.handle_request({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {"textDocument": {"uri": doc_uri, "text": code}}
    })

    # Hover over 'add-vec' on line 7
    hover_resp = server.handle_request({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/hover",
        "params": {
            "textDocument": {"uri": doc_uri},
            "position": {"line": 7, "character": 9}
        }
    })
    assert hover_resp["id"] == 2
    assert "Computes coordinate sum" in hover_resp["result"]["contents"]["value"]

    # Definition for 'Vector2D' on line 7
    def_resp = server.handle_request({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "textDocument/definition",
        "params": {
            "textDocument": {"uri": doc_uri},
            "position": {"line": 7, "character": 19}
        }
    })
    assert def_resp["id"] == 3
    assert def_resp["result"]["range"]["start"]["line"] == 3


def test_lsp_virtual_document_provider():
    server = AslLspServer()
    doc_uri = "file:///workspace/query.asl"
    query_code = '(select ["id" "name"] (from "users") (where (= "active" true)))'
    server.handle_request({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {"textDocument": {"uri": doc_uri, "text": query_code}}
    })

    resp = server.handle_request({
        "jsonrpc": "2.0",
        "id": 4,
        "method": "asl/virtualDocument",
        "params": {"uri": doc_uri, "projection": "sql", "dialect": "postgres"}
    })
    assert resp["id"] == 4
    content = resp["result"]["content"]
    assert "SELECT \"id\", \"name\" FROM \"users\"" in content
    assert "Live Virtual SQL Projection [POSTGRES]" in content
