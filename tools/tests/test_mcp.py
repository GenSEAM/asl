import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SERVER = ROOT / "tools" / "mcp" / "server.py"


def send_mcp_request(req: dict) -> dict:
    proc = subprocess.Popen(
        [sys.executable, str(SERVER)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=ROOT
    )
    payload = json.dumps(req).encode("utf-8") + b"\n"
    out, err = proc.communicate(input=payload, timeout=10)
    assert proc.returncode == 0, f"Server crashed with stderr: {err.decode()}"
    return json.loads(out.decode("utf-8").strip())


def test_mcp_initialize_and_tools_list():
    # 1. initialize
    init_res = send_mcp_request({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
    assert init_res["id"] == 1
    assert init_res["result"]["serverInfo"]["name"] == "asex-mcp"
    assert "protocolVersion" in init_res["result"]

    # 2. tools/list
    tools_res = send_mcp_request({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    assert tools_res["id"] == 2
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    assert "asex_check" in tool_names
    assert "asex_eval" in tool_names
    assert "asex_format" in tool_names
    assert "asex_compress_module" in tool_names
    assert "asex_ast_query" in tool_names


def test_mcp_asex_check():
    # Clean code check
    clean_src = """(module test-mod :doc "doc" :export [f])
(defun f [(x Int64)] -> Int64
  :doc "fn"
  (+ x 1))"""
    res = send_mcp_request({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "asex_check",
            "arguments": {"source": clean_src}
        }
    })
    data = json.loads(res["result"]["content"][0]["text"])
    assert data["valid"] is True
    assert len(data["diagnostics"]) == 0

    # Type error check
    bad_src = """(module bad-mod :doc "doc" :export [f])
(defun f [(x Int64)] -> String
  :doc "fn"
  (+ x 1))"""
    res2 = send_mcp_request({
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {
            "name": "asex_check",
            "arguments": {"source": bad_src}
        }
    })
    data2 = json.loads(res2["result"]["content"][0]["text"])
    assert data2["valid"] is False
    assert len(data2["diagnostics"]) > 0


def test_mcp_asex_eval():
    src = """(module eval-demo :doc "test" :export [main])
(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Entry"
  (println "mcp-eval-success"))"""
    res = send_mcp_request({
        "jsonrpc": "2.0",
        "id": 5,
        "method": "tools/call",
        "params": {
            "name": "asex_eval",
            "arguments": {"source": src}
        }
    })
    data = json.loads(res["result"]["content"][0]["text"])
    assert data["success"] is True
    assert "mcp-eval-success" in data["stdout"]


def test_mcp_asex_format():
    unformatted = '(module fmt-test :doc "doc" :export [f])\n(defun f [(x Int64)] -> Int64 :doc "fn" (+ x 1))'
    res = send_mcp_request({
        "jsonrpc": "2.0",
        "id": 6,
        "method": "tools/call",
        "params": {
            "name": "asex_format",
            "arguments": {"source": unformatted}
        }
    })
    data = json.loads(res["result"]["content"][0]["text"])
    assert data["changed"] is True
    assert "\n  :doc \"fn\"" in data["formatted"]


def test_mcp_asex_compress_module():
    full_module = """(module math-lib
  :doc "Math utilities."
  :export [calculate ComplexNumber])

(defschema ComplexNumber
  (:field r Float64 "Real part")
  (:field i Float64 "Imaginary part"))

(defun calculate [(a Int64) (b Int64)] -> Int64
  :doc "Performs complex calculation."
  (let [(temp (* a 2))]
    (+ temp b)))"""
    res = send_mcp_request({
        "jsonrpc": "2.0",
        "id": 7,
        "method": "tools/call",
        "params": {
            "name": "asex_compress_module",
            "arguments": {"source": full_module}
        }
    })
    data = json.loads(res["result"]["content"][0]["text"])
    comp = data["compressed"]
    assert "(module math-lib" in comp
    assert "(defschema ComplexNumber" in comp
    assert "(defun calculate [(a Int64) (b Int64)] -> Int64" in comp
    # The stub is a call to the declaration itself; `panic` is in no vocabulary,
    # so the old stub made the compressed module unparseable.
    assert "(calculate a b)" in comp
    assert "panic" not in comp
    assert "let [(temp" not in comp  # body expressions omitted
