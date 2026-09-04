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


def test_lsp_metadata_tag_indexing():
    server = AslLspServer()
    doc_uri = "file:///workspace/auth/jwt.asl"
    code = """(module auth/jwt
  :d "JWT authentication module"
  (:tag :arch "d-1eed" :spec "sec-08" :doc "m-auth-jwt")
  :x [verify-token])

(df verify-token [(token Str) (pubkey Key)] -> (Result Claims AuthErr)
  :d "Verify a JWT against a public key."
  (:tag :inv "constant-time" :perf "p-120us" :doc "fn-verify-jwt")
  (ok (Claims :sub "u1")))
"""
    server.handle_request({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {"textDocument": {"uri": doc_uri, "text": code}}
    })

    # Test tag lookup for 'd-1eed'
    lookup_resp = server.handle_request({
        "jsonrpc": "2.0",
        "id": 5,
        "method": "lsp/tag-lookup",
        "params": {"tag": "d-1eed"}
    })
    assert lookup_resp["id"] == 5
    assert lookup_resp["result"]["count"] == 1
    assert lookup_resp["result"]["results"][0]["name"] == "auth/jwt"

    # Test tag lookup for 'constant-time'
    lookup_resp2 = server.handle_request({
        "jsonrpc": "2.0",
        "id": 6,
        "method": "lsp/tag-lookup",
        "params": {"tag": "constant-time"}
    })
    assert lookup_resp2["id"] == 6
    assert lookup_resp2["result"]["count"] == 1
    assert lookup_resp2["result"]["results"][0]["name"] == "verify-token"

    # Test node metadata lookup on line 7 (inside verify-token)
    meta_resp = server.handle_request({
        "jsonrpc": "2.0",
        "id": 7,
        "method": "lsp/node-meta",
        "params": {"uri": doc_uri, "line": 7}
    })
    assert meta_resp["id"] == 7
    node = meta_resp["result"]
    assert node["name"] == "verify-token"
    assert node["tags"]["inv"] == "constant-time"
    assert node["tags"]["perf"] == "p-120us"

    # Test hover shows metadata tags
    hover_resp = server.handle_request({
        "jsonrpc": "2.0",
        "id": 8,
        "method": "textDocument/hover",
        "params": {
            "textDocument": {"uri": doc_uri},
            "position": {"line": 5, "character": 7}
        }
    })
    assert hover_resp["id"] == 8
    val = hover_resp["result"]["contents"]["value"]
    assert "constant-time" in val
    assert "p-120us" in val

