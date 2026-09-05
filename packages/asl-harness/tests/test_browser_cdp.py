"""
Unit and integration tests for AgentScript Chrome DevTools Protocol (CDP) Bridge
(@genseam/asl-harness / @pcp:d-596e)
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import os
import struct
from pathlib import Path
import sys
from typing import Any, Callable, Dict, List, Optional
import urllib.request

import pytest

BRIDGES_DIR = Path(__file__).resolve().parent.parent / "bridges"
if str(BRIDGES_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGES_DIR))

from browser_cdp import (
    AXNode,
    AsyncWebSocketTransport,
    CDPClient,
    CDPCommandError,
    CDPConnectionError,
    CDPElementNotFoundError,
    CDPTimeoutError,
    CDPTransport,
    SyncCDPClient,
    clean_attr,
    escape_asl,
    from_cdp_ax_tree,
    resolve_ws_url,
)
import functools


def async_test(coro_fn):
    @functools.wraps(coro_fn)
    def wrapper(*args, **kwargs):
        return asyncio.run(coro_fn(*args, **kwargs))
    return wrapper


# ============================================================================
# Mock Transport & Local Server Helpers
# ============================================================================


class MockTransport(CDPTransport):
    """Configurable mock transport for unit testing CDP client without Chrome."""

    def __init__(self):
        self.sent: List[Dict[str, Any]] = []
        self.queue: asyncio.Queue[str] = asyncio.Queue()
        self._closed = False
        self._responder: Optional[Callable[[Dict[str, Any]], Optional[Dict[str, Any]]]] = None

    def set_responder(self, responder: Callable[[Dict[str, Any]], Optional[Dict[str, Any]]]) -> None:
        self._responder = responder

    async def send(self, data: str) -> None:
        if self._closed:
            raise CDPConnectionError("Transport is closed")
        msg = json.loads(data)
        self.sent.append(msg)
        if self._responder:
            resp = self._responder(msg)
            if resp is not None:
                await self.queue.put(json.dumps(resp))

    async def recv(self) -> str:
        if self._closed and self.queue.empty():
            raise CDPConnectionError("Transport is closed")
        item = await self.queue.get()
        if not item and self._closed:
            raise CDPConnectionError("Transport is closed")
        return item

    async def push(self, msg: Dict[str, Any]) -> None:
        await self.queue.put(json.dumps(msg))

    async def close(self) -> None:
        self._closed = True
        await self.queue.put("")

    def is_closed(self) -> bool:
        return self._closed


# ============================================================================
# 1. Connection Lifecycle and Handshake Tests
# ============================================================================


def test_clean_attr_and_escape_asl():
    assert clean_attr("   Hello \n\t  World   ") == "Hello World"
    assert escape_asl('Quote "and" \\slash\nnewline') == 'Quote \\"and\\" \\\\slash newline'


def test_ws_url_resolution_direct():
    direct_url = "ws://localhost:9222/devtools/page/ABC123"
    assert resolve_ws_url(direct_url) == direct_url
    direct_wss = "wss://remote-chrome.internal/devtools/page/DEF456"
    assert resolve_ws_url(direct_wss) == direct_wss


def test_ws_url_resolution_http(monkeypatch):
    sample_version_json = json.dumps({
        "Browser": "Chrome/128.0.0.0",
        "webSocketDebuggerUrl": "ws://localhost:9222/devtools/browser/xyz-789"
    }).encode("utf-8")

    class MockResponse:
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass
        def read(self):
            return sample_version_json

    def mock_urlopen(req, timeout=5.0):
        url = req.full_url if hasattr(req, "full_url") else str(req)
        if "json/version" in url:
            return MockResponse()
        raise urllib.error.URLError("Not found")

    monkeypatch.setattr(urllib.request, "urlopen", mock_urlopen)

    resolved = resolve_ws_url("http://localhost:9222")
    assert resolved == "ws://localhost:9222/devtools/browser/xyz-789"

    resolved_full = resolve_ws_url("http://localhost:9222/json/version")
    assert resolved_full == "ws://localhost:9222/devtools/browser/xyz-789"


def test_ws_url_resolution_targets_fallback(monkeypatch):
    sample_targets_json = json.dumps([
        {"type": "background_page", "id": "bg1"},
        {"type": "page", "id": "p1", "webSocketDebuggerUrl": "ws://localhost:9222/devtools/page/page-001"}
    ]).encode("utf-8")

    class MockTargetsResponse:
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass
        def read(self):
            return sample_targets_json

    def mock_urlopen(req, timeout=5.0):
        url = req.full_url if hasattr(req, "full_url") else str(req)
        if "/json/version" in url:
            raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)
        if "/json" in url:
            return MockTargetsResponse()
        raise urllib.error.URLError("Failed")

    monkeypatch.setattr(urllib.request, "urlopen", mock_urlopen)

    resolved = resolve_ws_url("http://localhost:9222")
    assert resolved == "ws://localhost:9222/devtools/page/page-001"


def test_ws_url_resolution_failure(monkeypatch):
    def mock_urlopen(req, timeout=5.0):
        raise urllib.error.URLError("Connection refused")

    monkeypatch.setattr(urllib.request, "urlopen", mock_urlopen)

    with pytest.raises(CDPConnectionError):
        resolve_ws_url("http://127.0.0.1:9999")


@async_test
async def test_local_websocket_handshake_and_frames():
    """Tests the pure-Python RFC 6455 client handshake and framing against a real socket."""
    server_received_frames: List[bytes] = []

    async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        # Read handshake
        req_data = bytearray()
        while b"\r\n\r\n" not in req_data:
            chunk = await reader.read(1024)
            if not chunk:
                break
            req_data.extend(chunk)

        headers = {}
        for line in req_data.decode("iso-8859-1").split("\r\n")[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        key = headers["sec-websocket-key"]
        accept_val = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
        ).decode("ascii")

        resp = (
            f"HTTP/1.1 101 Switching Protocols\r\n"
            f"Upgrade: websocket\r\n"
            f"Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept_val}\r\n\r\n"
        )
        writer.write(resp.encode("ascii"))
        await writer.drain()

        # Read client frame (must be masked per RFC 6455)
        h = await reader.readexactly(2)
        b0, b1 = h[0], h[1]
        length = b1 & 0x7F
        mask = await reader.readexactly(4)
        payload_raw = await reader.readexactly(length)
        unmasked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload_raw))
        server_received_frames.append(unmasked)

        # Echo response back to client (unmasked server-to-client frame)
        resp_msg = json.dumps({"id": 1, "result": {"ack": True}}).encode("utf-8")
        resp_h = bytearray([0x81, len(resp_msg)])
        writer.write(resp_h + resp_msg)
        await writer.drain()

        # Clean close
        await reader.read(1024)
        writer.close()
        await writer.wait_closed()

    try:
        server = await asyncio.start_server(handle_client, "127.0.0.1", 0)
        port = server.sockets[0].getsockname()[1]
        ws_url = f"ws://127.0.0.1:{port}/devtools/test"

        client_transport = AsyncWebSocketTransport(ws_url, timeout=5.0)
        await client_transport.connect()
    except (PermissionError, CDPConnectionError, OSError) as e:
        pytest.skip(f"Loopback socket connections not permitted in sandbox: {e}")
    assert not client_transport.is_closed()

    # Send client message
    await client_transport.send(json.dumps({"id": 1, "method": "Test.ping"}))
    resp_text = await client_transport.recv()
    resp_data = json.loads(resp_text)

    assert resp_data["id"] == 1
    assert resp_data["result"]["ack"] is True
    assert len(server_received_frames) == 1
    assert b"Test.ping" in server_received_frames[0]

    await client_transport.close()
    server.close()
    await server.wait_closed()


@async_test
async def test_client_connection_retries(monkeypatch):
    attempt_count = 0

    def mock_resolve_ws_url(endpoint, timeout=5.0):
        nonlocal attempt_count
        attempt_count += 1
        if attempt_count < 3:
            raise CDPConnectionError("Temporary network unreachable")
        return "ws://127.0.0.1:9222/devtools/page/test"

    monkeypatch.setattr("browser_cdp.resolve_ws_url", mock_resolve_ws_url)

    mock_transport = MockTransport()
    client = CDPClient(
        endpoint="http://localhost:9222",
        max_retries=3,
        retry_delay=0.01,
        transport=mock_transport,
    )

    await client.connect()
    assert client.is_connected
    await client.close()


@async_test
async def test_client_context_manager():
    mock = MockTransport()
    async with CDPClient(transport=mock) as client:
        assert client.is_connected
    assert not client.is_connected


# ============================================================================
# 2. Page Navigation and Error Recovery Tests
# ============================================================================


@async_test
async def test_navigation_success():
    mock = MockTransport()

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Page.enable":
            return {"id": req_id, "result": {}}
        elif method == "Page.navigate":
            # Simulate navigation response and asynchronous load event
            asyncio.create_task(mock.push({"method": "Page.loadEventFired", "params": {"timestamp": 12345.678}}))
            return {"id": req_id, "result": {"frameId": "F1", "loaderId": "L1"}}
        return None

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    result = await client.navigate("https://aslang.dev", timeout=2.0)
    assert result["frameId"] == "F1"
    assert result["loaderId"] == "L1"

    sent_methods = [m["method"] for m in mock.sent]
    assert "Page.enable" in sent_methods
    assert "Page.navigate" in sent_methods

    await client.close()


@async_test
async def test_navigation_timeout():
    mock = MockTransport()

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Page.enable":
            return {"id": req_id, "result": {}}
        elif method == "Page.navigate":
            # Notice: Page.loadEventFired is intentionally omitted
            return {"id": req_id, "result": {"frameId": "F1"}}
        return None

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    with pytest.raises(CDPTimeoutError):
        await client.navigate("https://aslang.dev/slow", timeout=0.1)

    await client.close()


@async_test
async def test_navigation_command_error():
    mock = MockTransport()

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        if msg.get("method") == "Page.navigate":
            return {"id": msg["id"], "error": {"code": -32000, "message": "Cannot navigate to invalid URL"}}
        return {"id": msg["id"], "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    with pytest.raises(CDPCommandError) as exc_info:
        await client.navigate("invalid://path", timeout=1.0)

    assert "Cannot navigate to invalid URL" in str(exc_info.value)
    assert exc_info.value.code == -32000

    await client.close()


# ============================================================================
# 3. AXTree Retrieval and Transformation to ASL Tests
# ============================================================================


def test_cdp_axtree_transformation_hierarchy():
    cdp_nodes = [
        {
            "nodeId": "1",
            "role": {"type": "role", "value": "RootWebArea"},
            "name": {"type": "string", "value": "System Console"},
            "childIds": ["2", "3", "4"],
            "backendDOMNodeId": 101,
        },
        {
            "nodeId": "2",
            "role": {"type": "role", "value": "heading"},
            "name": {"type": "string", "value": "Cluster Status"},
            "childIds": [],
            "backendDOMNodeId": 102,
        },
        {
            "nodeId": "3",
            "role": {"type": "role", "value": "button"},
            "name": {"type": "string", "value": "Deploy Shard"},
            "description": {"type": "string", "value": "Triggers distributed deployment"},
            "disabled": {"type": "boolean", "value": False},
            "focused": {"type": "boolean", "value": True},
            "childIds": [],
            "backendDOMNodeId": 103,
        },
        {
            "nodeId": "4",
            "role": {"type": "role", "value": "generic"},
            "name": {"type": "string", "value": ""},
            "childIds": [],  # Uninformative generic node: should be pruned
            "backendDOMNodeId": 104,
        },
    ]

    root, ref_map = from_cdp_ax_tree(cdp_nodes)
    assert root is not None
    assert root.role == "RootWebArea"
    assert root.name == "System Console"
    assert root.ref == "@e1"

    assert len(root.children) == 2  # Generic empty node pruned
    heading = root.children[0]
    assert heading.role == "heading"
    assert heading.name == "Cluster Status"
    assert heading.ref == "@e2"

    button = root.children[1]
    assert button.role == "button"
    assert button.name == "Deploy Shard"
    assert button.ref == "@e3"
    assert button.description == "Triggers distributed deployment"
    assert button.focused is True
    assert button.backend_node_id == 103

    assert "@e1" in ref_map
    assert "@e2" in ref_map
    assert "@e3" in ref_map
    assert ref_map["@e3"] is button


def test_cdp_axtree_asl_serialization():
    leaf = AXNode(
        role="button",
        name="Confirm",
        ref="@e2",
        description="Submits changes",
        disabled=True,
    )
    parent = AXNode(
        role="dialog",
        name="Confirm Action",
        ref="@e1",
        children=[leaf],
    )

    asl_colon = parent.to_asl(colon_prefix=True)
    assert asl_colon.startswith("(:ax-node :role \"dialog\" :name \"Confirm Action\" :ref \"@e1\"")
    assert ":desc \"Submits changes\"" in asl_colon
    assert ":disabled true" in asl_colon
    assert "(:ax-node :role \"button\"" in asl_colon

    asl_plain = parent.to_asl(colon_prefix=False)
    assert asl_plain.startswith("(ax-node :role \"dialog\"")


def test_ax_node_search_helpers():
    btn1 = AXNode(role="button", name="OK", ref="@e2")
    btn2 = AXNode(role="button", name="Cancel", ref="@e3")
    txt = AXNode(role="textbox", name="Username", ref="@e4", value="admin")
    root = AXNode(role="RootWebArea", name="Login", ref="@e1", children=[btn1, btn2, txt])

    assert root.find_by_ref("@e3") is btn2
    assert root.find_by_ref("@e999") is None

    buttons = root.find_by_role("button")
    assert len(buttons) == 2
    assert btn1 in buttons
    assert btn2 in buttons


@async_test
async def test_get_axtree_client_flow():
    mock = MockTransport()
    sample_nodes = [
        {
            "nodeId": "1",
            "role": {"type": "role", "value": "RootWebArea"},
            "name": {"type": "string", "value": "Portal"},
            "childIds": ["2"],
            "backendDOMNodeId": 10,
        },
        {
            "nodeId": "2",
            "role": {"type": "role", "value": "button"},
            "name": {"type": "string", "value": "Enter"},
            "childIds": [],
            "backendDOMNodeId": 20,
        },
    ]

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        if method == "Accessibility.getFullAXTree":
            return {"id": msg["id"], "result": {"nodes": sample_nodes}}
        return {"id": msg["id"], "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    root = await client.get_axtree()
    assert root is not None
    assert root.name == "Portal"
    assert len(root.children) == 1
    assert root.children[0].name == "Enter"
    assert root.children[0].ref == "@e2"

    asl_str = await client.get_axtree_asl(colon_prefix=True)
    assert "(:ax-node :role \"RootWebArea\"" in asl_str
    assert "(:ax-node :role \"button\" :name \"Enter\" :ref \"@e2\")" in asl_str

    await client.close()


# ============================================================================
# 4. Action Dispatch (click, type_text, screenshot) Tests
# ============================================================================


@async_test
async def test_click_by_ref_call_function():
    mock = MockTransport()
    sample_nodes = [
        {
            "nodeId": "1",
            "role": {"type": "role", "value": "RootWebArea"},
            "name": {"type": "string", "value": "App"},
            "childIds": ["2"],
            "backendDOMNodeId": 10,
        },
        {
            "nodeId": "2",
            "role": {"type": "role", "value": "button"},
            "name": {"type": "string", "value": "Save"},
            "childIds": [],
            "backendDOMNodeId": 20,
        },
    ]

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Accessibility.getFullAXTree":
            return {"id": req_id, "result": {"nodes": sample_nodes}}
        elif method == "DOM.resolveNode":
            assert msg["params"]["backendNodeId"] == 20
            return {"id": req_id, "result": {"object": {"objectId": "obj-btn-20"}}}
        elif method == "Runtime.callFunctionOn":
            assert msg["params"]["objectId"] == "obj-btn-20"
            assert "this.click()" in msg["params"]["functionDeclaration"]
            return {"id": req_id, "result": {"value": {"clicked": True}}}
        return {"id": req_id, "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    # Pre-populate AXTree
    await client.get_axtree()

    click_res = await client.click("@e2")
    assert click_res["clicked"] is True
    assert click_res["ref"] == "@e2"
    assert click_res["method"] == "callFunctionOn"

    await client.close()


@async_test
async def test_click_by_ref_mouse_event():
    mock = MockTransport()
    sample_nodes = [
        {
            "nodeId": "1",
            "role": {"type": "role", "value": "RootWebArea"},
            "name": {"type": "string", "value": "Canvas"},
            "childIds": ["2"],
            "backendDOMNodeId": 10,
        },
        {
            "nodeId": "2",
            "role": {"type": "role", "value": "button"},
            "name": {"type": "string", "value": "Draw"},
            "childIds": [],
            "backendDOMNodeId": 25,
        },
    ]

    mouse_events: List[Dict[str, Any]] = []

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Accessibility.getFullAXTree":
            return {"id": req_id, "result": {"nodes": sample_nodes}}
        elif method == "DOM.resolveNode":
            return {"id": req_id, "result": {"object": {"objectId": "obj-25"}}}
        elif method == "DOM.getBoxModel":
            return {
                "id": req_id,
                "result": {
                    "model": {
                        "content": [100, 200, 200, 200, 200, 250, 100, 250]
                    }
                },
            }
        elif method == "Input.dispatchMouseEvent":
            mouse_events.append(msg["params"])
            return {"id": req_id, "result": {}}
        return {"id": req_id, "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()
    await client.get_axtree()

    click_res = await client.click("@e2", use_mouse_event=True)
    assert click_res["clicked"] is True
    assert click_res["method"] == "mouse_event"
    assert click_res["x"] == 150.0  # (100 + 200) / 2
    assert click_res["y"] == 225.0  # (200 + 250) / 2

    assert len(mouse_events) == 2
    assert mouse_events[0]["type"] == "mousePressed"
    assert mouse_events[1]["type"] == "mouseReleased"

    await client.close()


@async_test
async def test_click_by_selector():
    mock = MockTransport()

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Runtime.evaluate":
            expr = msg["params"]["expression"]
            assert "#submit-order" in expr
            return {"id": req_id, "result": {"value": {"clicked": True, "tag": "button"}}}
        return {"id": req_id, "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    res = await client.click("#submit-order")
    assert res["clicked"] is True
    assert res["selector"] == "#submit-order"
    assert res["method"] == "evaluate"

    await client.close()


@async_test
async def test_click_not_found():
    mock = MockTransport()

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Accessibility.getFullAXTree":
            return {"id": req_id, "result": {"nodes": []}}
        elif method == "Runtime.evaluate":
            return {
                "id": req_id,
                "result": {},
                "exceptionDetails": {"text": "Error: Element not found: #missing"},
            }
        return {"id": req_id, "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    with pytest.raises(CDPElementNotFoundError):
        await client.click("@e99")

    with pytest.raises(CDPElementNotFoundError):
        await client.click("#missing")

    await client.close()


@async_test
async def test_type_text_by_ref():
    mock = MockTransport()
    sample_nodes = [
        {
            "nodeId": "1",
            "role": {"type": "role", "value": "RootWebArea"},
            "name": {"type": "string", "value": "Form"},
            "childIds": ["2"],
            "backendDOMNodeId": 1,
        },
        {
            "nodeId": "2",
            "role": {"type": "role", "value": "textbox"},
            "name": {"type": "string", "value": "Email"},
            "childIds": [],
            "backendDOMNodeId": 50,
        },
    ]

    typed_calls: List[Dict[str, Any]] = []

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Accessibility.getFullAXTree":
            return {"id": req_id, "result": {"nodes": sample_nodes}}
        elif method == "DOM.resolveNode":
            return {"id": req_id, "result": {"object": {"objectId": "obj-input-50"}}}
        elif method == "Runtime.callFunctionOn":
            typed_calls.append(msg["params"])
            return {"id": req_id, "result": {"value": {"typed": True, "value": "user@example.com"}}}
        return {"id": req_id, "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()
    await client.get_axtree()

    res = await client.type_text("@e2", "user@example.com", clear_first=True)
    assert res["typed"] is True
    assert res["ref"] == "@e2"
    assert res["value"] == "user@example.com"
    assert len(typed_calls) == 1
    assert typed_calls[0]["arguments"][0]["value"] == "user@example.com"

    await client.close()


@async_test
async def test_type_text_by_selector():
    mock = MockTransport()

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Runtime.evaluate":
            expr = msg["params"]["expression"]
            assert "input[name='token']" in expr
            assert "secret_token_123" in expr
            return {"id": req_id, "result": {"value": {"typed": True, "value": "secret_token_123"}}}
        return {"id": req_id, "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    res = await client.type_text("input[name='token']", "secret_token_123")
    assert res["typed"] is True
    assert res["selector"] == "input[name='token']"
    assert res["value"] == "secret_token_123"

    await client.close()


@async_test
async def test_screenshot():
    mock = MockTransport()
    raw_png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDRtestdata"
    b64_png = base64.b64encode(raw_png).decode("ascii")

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Page.captureScreenshot":
            assert msg["params"]["format"] == "png"
            return {"id": req_id, "result": {"data": b64_png}}
        return {"id": req_id, "result": {}}

    mock.set_responder(responder)

    client = CDPClient(transport=mock)
    await client.connect()

    screenshot_bytes = await client.screenshot(format="png")
    assert screenshot_bytes == raw_png

    screenshot_b64 = await client.screenshot_base64(format="png")
    assert screenshot_b64 == b64_png

    await client.close()


# ============================================================================
# 5. Clean Disconnect and Graceful Error Handling Tests
# ============================================================================


@async_test
async def test_clean_disconnect_and_idempotence():
    mock = MockTransport()
    client = CDPClient(transport=mock)
    await client.connect()
    assert client.is_connected

    await client.close()
    assert not client.is_connected
    assert mock.is_closed()

    # Repeated close is harmless
    await client.close()
    assert not client.is_connected


@async_test
async def test_command_after_disconnect_raises():
    mock = MockTransport()
    client = CDPClient(transport=mock)
    await client.connect()
    await client.close()

    with pytest.raises(CDPConnectionError):
        await client.send_cdp("Runtime.evaluate", {"expression": "1+1"})


@async_test
async def test_event_listeners_dispatch_and_unregister():
    mock = MockTransport()
    client = CDPClient(transport=mock)
    await client.connect()

    events_received: List[Dict[str, Any]] = []

    def on_lifecycle(params: Dict[str, Any]):
        events_received.append(params)

    client.add_event_listener("Page.lifecycleEvent", on_lifecycle)

    # Push event through transport
    await mock.push({"method": "Page.lifecycleEvent", "params": {"name": "firstMeaningfulPaint"}})
    await asyncio.sleep(0.01)

    assert len(events_received) == 1
    assert events_received[0]["name"] == "firstMeaningfulPaint"

    # Unregister listener
    client.remove_event_listener("Page.lifecycleEvent", on_lifecycle)
    await mock.push({"method": "Page.lifecycleEvent", "params": {"name": "networkIdle"}})
    await asyncio.sleep(0.01)

    assert len(events_received) == 1  # Unregistered: no new events

    await client.close()


def test_sync_cdp_client_api():
    mock = MockTransport()
    sample_nodes = [
        {
            "nodeId": "1",
            "role": {"type": "role", "value": "RootWebArea"},
            "name": {"type": "string", "value": "Sync Dashboard"},
            "childIds": ["2"],
            "backendDOMNodeId": 10,
        },
        {
            "nodeId": "2",
            "role": {"type": "role", "value": "button"},
            "name": {"type": "string", "value": "Sync CTA"},
            "childIds": [],
            "backendDOMNodeId": 20,
        },
    ]

    raw_png = b"\x89PNGtest"
    b64_png = base64.b64encode(raw_png).decode("ascii")

    def responder(msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "Page.enable":
            return {"id": req_id, "result": {}}
        elif method == "Page.navigate":
            asyncio.create_task(mock.push({"method": "Page.loadEventFired", "params": {}}))
            return {"id": req_id, "result": {"frameId": "F-SYNC"}}
        elif method == "Accessibility.getFullAXTree":
            return {"id": req_id, "result": {"nodes": sample_nodes}}
        elif method == "DOM.resolveNode":
            return {"id": req_id, "result": {"object": {"objectId": "obj-sync"}}}
        elif method == "Runtime.callFunctionOn":
            return {"id": req_id, "result": {"value": {"clicked": True}}}
        elif method == "Page.captureScreenshot":
            return {"id": req_id, "result": {"data": b64_png}}
        return {"id": req_id, "result": {}}

    mock.set_responder(responder)

    with SyncCDPClient(transport=mock) as sync_client:
        nav = sync_client.navigate("https://aslang.dev")
        assert nav["frameId"] == "F-SYNC"

        ax = sync_client.get_axtree()
        assert ax is not None
        assert ax.name == "Sync Dashboard"

        asl = sync_client.get_axtree_asl()
        assert "(:ax-node :role \"RootWebArea\"" in asl

        click_res = sync_client.click("@e2")
        assert click_res["clicked"] is True

        png = sync_client.screenshot()
        assert png == raw_png
