"""
AgentScript Chrome DevTools Protocol (CDP) Bridge (@genseam/asl-harness)
Provides a lightweight, zero-dependency async/sync CDP client for ASL agents
to interact with Chromium instances, navigate pages, extract compact AXTree
S-expressions conforming to asl-vdom, click elements, fill forms, and capture screenshots.
(@pcp:d-596e)
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import logging
import os
import ssl
import struct
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable, Dict, List, Optional, Set, Tuple, Union

logger = logging.getLogger("asl.bridges.browser_cdp")

INTERACTIVE_ROLES: Set[str] = {
    "button",
    "link",
    "checkbox",
    "radio",
    "combobox",
    "textbox",
    "searchbox",
    "menuitem",
    "tab",
}


# ============================================================================
# Exceptions
# ============================================================================


class CDPError(Exception):
    """Base exception for Chrome DevTools Protocol errors."""
    pass


class CDPConnectionError(CDPError):
    """Raised when connection or handshake with CDP endpoint fails."""
    pass


class CDPTimeoutError(CDPError):
    """Raised when an operation or response exceeds timeout deadline."""
    pass


class CDPCommandError(CDPError):
    """Raised when CDP server returns an error response."""

    def __init__(self, message: str, code: Optional[int] = None, data: Any = None):
        super().__init__(message)
        self.code = code
        self.data = data


class CDPElementNotFoundError(CDPError):
    """Raised when an element ref or selector cannot be located."""
    pass


# ============================================================================
# AXTree Data Structures & Compaction (asl-vdom conforming)
# ============================================================================


def clean_attr(val: str) -> str:
    """Normalizes whitespace in attribute values."""
    return " ".join(val.split()).strip()


def escape_asl(val: str) -> str:
    """Escapes characters for ASL S-expression string literals."""
    return val.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


class AXNode:
    """
    Hierarchical accessibility node representation conforming to asl-vdom (§AXNode).
    Serializes to compact ASL S-expression frame: (:ax-node :role ... :name ... :ref ...)
    """

    def __init__(
        self,
        role: str,
        name: str = "",
        ref: str = "",
        description: Optional[str] = None,
        disabled: Optional[bool] = None,
        focused: Optional[bool] = None,
        value: Optional[str] = None,
        children: Optional[List[AXNode]] = None,
        backend_node_id: Optional[int] = None,
        node_id: Optional[str] = None,
    ):
        self.role = role
        self.name = name
        self.ref = ref
        self.description = description
        self.disabled = disabled
        self.focused = focused
        self.value = value
        self.children: List[AXNode] = children or []
        self.backend_node_id = backend_node_id
        self.node_id = node_id

    def to_asl(self, colon_prefix: bool = True) -> str:
        """
        Serializes the node into compact ASL S-expression frame:
        e.g. (:ax-node :role "button" :name "Submit" :ref "@e1")
        """
        head = ":ax-node" if colon_prefix else "ax-node"
        parts = [head, f':role "{escape_asl(self.role)}"']

        if self.name:
            parts.append(f':name "{escape_asl(self.name)}"')
        if self.ref:
            parts.append(f':ref "{escape_asl(self.ref)}"')
        if self.description:
            parts.append(f':desc "{escape_asl(self.description)}"')
        if self.disabled:
            parts.append(":disabled true")
        if self.focused:
            parts.append(":focused true")
        if self.value:
            parts.append(f':value "{escape_asl(self.value)}"')

        if self.children:
            child_frames = " ".join(c.to_asl(colon_prefix=colon_prefix) for c in self.children)
            parts.append(child_frames)

        return f"({' '.join(parts)})"

    def find_by_ref(self, target_ref: str) -> Optional[AXNode]:
        """Recursively finds an AXNode by reference tag (e.g. '@e1')."""
        if self.ref == target_ref:
            return self
        for ch in self.children:
            found = ch.find_by_ref(target_ref)
            if found:
                return found
        return None

    def find_by_role(self, target_role: str) -> List[AXNode]:
        """Recursively finds all AXNodes matching the given ARIA role."""
        results: List[AXNode] = []
        if self.role == target_role:
            results.append(self)
        for ch in self.children:
            results.extend(ch.find_by_role(target_role))
        return results

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "role": self.role,
            "name": self.name,
            "ref": self.ref,
        }
        if self.description:
            d["description"] = self.description
        if self.disabled is not None:
            d["disabled"] = self.disabled
        if self.focused is not None:
            d["focused"] = self.focused
        if self.value is not None:
            d["value"] = self.value
        if self.backend_node_id is not None:
            d["backend_node_id"] = self.backend_node_id
        if self.node_id is not None:
            d["node_id"] = self.node_id
        if self.children:
            d["children"] = [c.to_dict() for c in self.children]
        return d

    def __repr__(self) -> str:
        return f"<AXNode {self.role} '{self.name}' {self.ref}>"


def _extract_val(field: Any) -> Any:
    """Extracts scalar value from CDP AX property structure."""
    if isinstance(field, dict) and "value" in field:
        return field["value"]
    return field


def from_cdp_ax_tree(nodes: List[Dict[str, Any]]) -> Tuple[Optional[AXNode], Dict[str, AXNode]]:
    """
    Converts CDP Accessibility nodes into hierarchical AXNode tree.
    Returns (root_node, ref_map) where ref_map maps '@e1', '@e2' -> AXNode.
    """
    if not nodes:
        return None, {}

    node_map: Dict[str, Dict[str, Any]] = {}
    for n in nodes:
        nid = str(n.get("nodeId", ""))
        if nid:
            node_map[nid] = n

    root_raw = None
    for n in nodes:
        role_val = str(_extract_val(n.get("role")) or "")
        if role_val in ("RootWebArea", "WebArea"):
            root_raw = n
            break
    if root_raw is None:
        root_raw = nodes[0]

    ref_counter = 1
    ref_map: Dict[str, AXNode] = {}

    def build_node(n: Dict[str, Any]) -> Optional[AXNode]:
        nonlocal ref_counter
        if n.get("ignored"):
            return None

        role = str(_extract_val(n.get("role")) or "generic")
        raw_name = str(_extract_val(n.get("name")) or "")
        name = clean_attr(raw_name)

        desc_raw = _extract_val(n.get("description"))
        desc = clean_attr(str(desc_raw)) if desc_raw else None

        val_raw = _extract_val(n.get("value"))
        val = str(val_raw) if val_raw is not None else None

        dis_raw = _extract_val(n.get("disabled"))
        disabled = bool(dis_raw) if dis_raw else None

        foc_raw = _extract_val(n.get("focused"))
        focused = bool(foc_raw) if foc_raw else None

        backend_id = n.get("backendDOMNodeId")
        node_id = str(n.get("nodeId", ""))

        is_interactive = role in INTERACTIVE_ROLES
        has_local_info = len(name) > 0 or is_interactive

        ref = ""
        if has_local_info:
            ref = f"@e{ref_counter}"
            ref_counter += 1

        raw_child_ids = n.get("childIds", [])
        children: List[AXNode] = []
        for cid in raw_child_ids:
            child_cdp = node_map.get(str(cid))
            if child_cdp:
                built = build_node(child_cdp)
                if built:
                    children.append(built)

        if not has_local_info and len(children) == 0 and role == "generic":
            return None

        ax = AXNode(
            role=role,
            name=name,
            ref=ref,
            description=desc,
            disabled=disabled,
            focused=focused,
            value=val,
            children=children if children else None,
            backend_node_id=backend_id,
            node_id=node_id,
        )
        if ref:
            ref_map[ref] = ax
        return ax

    root = build_node(root_raw)
    return root, ref_map


# ============================================================================
# Minimal RFC 6455 WebSocket Client Transport (Zero Dependencies)
# ============================================================================


class CDPTransport:
    """Abstract interface for CDP message transports."""

    async def send(self, data: str) -> None:
        raise NotImplementedError

    async def recv(self) -> str:
        raise NotImplementedError

    async def close(self) -> None:
        raise NotImplementedError

    def is_closed(self) -> bool:
        raise NotImplementedError


class AsyncWebSocketTransport(CDPTransport):
    """
    Pure Python RFC 6455 WebSocket client transport using asyncio streams.
    Zero third-party dependencies.
    """

    def __init__(self, url: str, timeout: float = 30.0):
        self.url = url
        self.timeout = timeout
        self.reader: Optional[asyncio.StreamReader] = None
        self.writer: Optional[asyncio.StreamWriter] = None
        self._recv_buf = bytearray()
        self._closed = False
        self._close_sent = False

    async def connect(self) -> None:
        parsed = urllib.parse.urlparse(self.url)
        scheme = parsed.scheme.lower()
        if scheme not in ("ws", "wss"):
            raise CDPConnectionError(f"Invalid WebSocket scheme: {scheme}")

        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or (443 if scheme == "wss" else 80)
        path = (parsed.path or "/") + (("?" + parsed.query) if parsed.query else "")

        ssl_ctx = ssl.create_default_context() if scheme == "wss" else None

        try:
            self.reader, self.writer = await asyncio.wait_for(
                asyncio.open_connection(host, port, ssl=ssl_ctx),
                timeout=self.timeout,
            )
        except Exception as e:
            raise CDPConnectionError(f"Failed to connect to {host}:{port} - {e}") from e

        # RFC 6455 Handshake
        sec_key = base64.b64encode(os.urandom(16)).decode("ascii")
        headers = [
            f"GET {path} HTTP/1.1",
            f"Host: {host}:{port}",
            "Upgrade: websocket",
            "Connection: Upgrade",
            f"Sec-WebSocket-Key: {sec_key}",
            "Sec-WebSocket-Version: 13",
            "\r\n",
        ]
        handshake_req = "\r\n".join(headers).encode("ascii")
        self.writer.write(handshake_req)
        await self.writer.drain()

        # Read handshake response
        resp_data = bytearray()
        while b"\r\n\r\n" not in resp_data:
            chunk = await asyncio.wait_for(self.reader.read(4096), timeout=self.timeout)
            if not chunk:
                raise CDPConnectionError("Connection closed by server during WebSocket handshake")
            resp_data.extend(chunk)

        header_bytes, trailing = resp_data.split(b"\r\n\r\n", 1)
        if trailing:
            self._recv_buf.extend(trailing)

        status_lines = header_bytes.decode("iso-8859-1").split("\r\n")
        status_line = status_lines[0]
        if " 101 " not in status_line:
            raise CDPConnectionError(f"WebSocket handshake rejected by server: {status_line}")

        resp_headers: Dict[str, str] = {}
        for line in status_lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                resp_headers[k.strip().lower()] = v.strip()

        # Verify Sec-WebSocket-Accept
        expected_accept = base64.b64encode(
            hashlib.sha1((sec_key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
        ).decode("ascii")
        if resp_headers.get("sec-websocket-accept") != expected_accept:
            raise CDPConnectionError("Sec-WebSocket-Accept header validation failed")

    async def _read_exact(self, n: int) -> bytes:
        if self._closed or not self.reader:
            raise EOFError("WebSocket is closed")
        while len(self._recv_buf) < n:
            chunk = await self.reader.read(4096)
            if not chunk:
                raise EOFError("WebSocket stream disconnected")
            self._recv_buf.extend(chunk)
        data = bytes(self._recv_buf[:n])
        del self._recv_buf[:n]
        return data

    async def _send_frame(self, opcode: int, payload: bytes) -> None:
        if self._closed or not self.writer:
            raise CDPConnectionError("Cannot send on closed WebSocket transport")

        b0 = 0x80 | (opcode & 0x0F)
        length = len(payload)
        mask = os.urandom(4)

        if length <= 125:
            header = bytearray([b0, 0x80 | length])
        elif length <= 0xFFFF:
            header = bytearray([b0, 0x80 | 126]) + struct.pack("!H", length)
        else:
            header = bytearray([b0, 0x80 | 127]) + struct.pack("!Q", length)

        masked_payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.writer.write(header + mask + masked_payload)
        await self.writer.drain()

    async def send(self, data: str) -> None:
        await self._send_frame(0x1, data.encode("utf-8"))

    async def recv(self) -> str:
        while not self._closed:
            h = await self._read_exact(2)
            b0, b1 = h[0], h[1]
            fin = bool(b0 & 0x80)
            opcode = b0 & 0x0F
            masked = bool(b1 & 0x80)
            length = b1 & 0x7F

            if length == 126:
                length = struct.unpack("!H", await self._read_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", await self._read_exact(8))[0]

            if masked:
                mask = await self._read_exact(4)
                raw = await self._read_exact(length)
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(raw))
            else:
                payload = await self._read_exact(length)

            if opcode == 0x8:  # CLOSE
                if not self._close_sent:
                    try:
                        await self._send_frame(0x8, payload[:2] if len(payload) >= 2 else b"")
                    except Exception:
                        pass
                await self.close()
                raise CDPConnectionError("WebSocket connection closed by peer")

            elif opcode == 0x9:  # PING
                await self._send_frame(0xA, payload)
                continue

            elif opcode == 0xA:  # PONG
                continue

            elif opcode == 0x1:  # TEXT
                fragments = [payload]
                while not fin:
                    # Continuation frames
                    ch = await self._read_exact(2)
                    cb0, cb1 = ch[0], ch[1]
                    fin = bool(cb0 & 0x80)
                    c_opcode = cb0 & 0x0F
                    c_masked = bool(cb1 & 0x80)
                    c_len = cb1 & 0x7F
                    if c_len == 126:
                        c_len = struct.unpack("!H", await self._read_exact(2))[0]
                    elif c_len == 127:
                        c_len = struct.unpack("!Q", await self._read_exact(8))[0]

                    if c_masked:
                        c_mask = await self._read_exact(4)
                        c_raw = await self._read_exact(c_len)
                        fragments.append(bytes(b ^ c_mask[i % 4] for i, b in enumerate(c_raw)))
                    else:
                        fragments.append(await self._read_exact(c_len))

                return b"".join(fragments).decode("utf-8")

            elif opcode == 0x2:  # BINARY
                return payload.decode("utf-8", errors="replace")

        raise CDPConnectionError("WebSocket is closed")

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        if self.writer:
            try:
                if not self._close_sent:
                    self._close_sent = True
                    await self._send_frame(0x8, struct.pack("!H", 1000))
            except Exception:
                pass
            try:
                self.writer.close()
                await self.writer.wait_closed()
            except Exception:
                pass

    def is_closed(self) -> bool:
        return self._closed


# ============================================================================
# Endpoint URL Discovery
# ============================================================================


def resolve_ws_url(endpoint: str, timeout: float = 5.0) -> str:
    """
    Resolves WebSocket URL from an endpoint string.
    If endpoint starts with 'ws://' or 'wss://', returns it directly.
    If endpoint starts with 'http://' or 'https://':
      - Queries /json/version or /json to locate 'webSocketDebuggerUrl'.
    """
    if endpoint.startswith("ws://") or endpoint.startswith("wss://"):
        return endpoint

    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme not in ("http", "https"):
        raise CDPConnectionError(f"Unsupported endpoint scheme: {endpoint}")

    base_url = f"{parsed.scheme}://{parsed.netloc}"
    version_url = endpoint if "/json/version" in endpoint else f"{base_url}/json/version"

    try:
        req = urllib.request.Request(version_url, headers={"User-Agent": "ASL-CDPClient"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            ws_url = data.get("webSocketDebuggerUrl")
            if ws_url:
                return str(ws_url)
    except Exception as e:
        logger.debug(f"Failed /json/version resolution at {version_url}: {e}")

    # Fallback to /json list
    targets_url = f"{base_url}/json"
    try:
        req = urllib.request.Request(targets_url, headers={"User-Agent": "ASL-CDPClient"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            targets = json.loads(resp.read().decode("utf-8"))
            if isinstance(targets, list):
                for target in targets:
                    if target.get("type") == "page" and target.get("webSocketDebuggerUrl"):
                        return str(target["webSocketDebuggerUrl"])
                for target in targets:
                    if target.get("webSocketDebuggerUrl"):
                        return str(target["webSocketDebuggerUrl"])
    except Exception as e:
        logger.debug(f"Failed /json targets resolution at {targets_url}: {e}")

    raise CDPConnectionError(f"Could not discover webSocketDebuggerUrl from {endpoint}")


# ============================================================================
# CDP Client (Async Core)
# ============================================================================


class CDPClient:
    """
    Chrome DevTools Protocol (CDP) client for autonomous AgentScript agents.
    Provides page navigation, AXTree perception, click, type, and screenshot actions.
    """

    def __init__(
        self,
        endpoint: str = "http://localhost:9222",
        timeout: float = 30.0,
        max_retries: int = 3,
        retry_delay: float = 0.5,
        transport: Optional[CDPTransport] = None,
    ):
        self.endpoint = endpoint
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_delay = retry_delay

        self._custom_transport = transport
        self.transport: Optional[CDPTransport] = None
        self._req_id = 0
        self._pending: Dict[int, asyncio.Future[Dict[str, Any]]] = {}
        self._event_listeners: Dict[str, List[Callable[[Dict[str, Any]], Any]]] = {}
        self._event_waiters: Dict[str, List[asyncio.Future[Dict[str, Any]]]] = {}
        self._reader_task: Optional[asyncio.Task] = None
        self._connected = False

        self._ref_map: Dict[str, AXNode] = {}
        self._root_ax: Optional[AXNode] = None

    @property
    def is_connected(self) -> bool:
        return self._connected and bool(self.transport and not self.transport.is_closed())

    async def connect(self) -> CDPClient:
        """Establishes connection to Chromium DevTools WebSocket endpoint with retries."""
        if self.is_connected:
            return self

        if self._custom_transport is not None:
            self.transport = self._custom_transport
            self._connected = True
            self._reader_task = asyncio.create_task(self._read_loop())
            return self

        last_err: Optional[Exception] = None
        for attempt in range(1, self.max_retries + 1):
            try:
                ws_url = resolve_ws_url(self.endpoint, timeout=min(5.0, self.timeout))
                ws_transport = AsyncWebSocketTransport(ws_url, timeout=self.timeout)
                await ws_transport.connect()
                self.transport = ws_transport
                self._connected = True
                self._reader_task = asyncio.create_task(self._read_loop())
                return self
            except Exception as e:
                last_err = e
                if attempt < self.max_retries:
                    await asyncio.sleep(self.retry_delay * attempt)

        raise CDPConnectionError(
            f"Failed to connect to CDP endpoint {self.endpoint} after {self.max_retries} attempts: {last_err}"
        ) from last_err

    async def close(self) -> None:
        """Cleanly terminates the CDP session and background tasks."""
        if not self._connected:
            return

        self._connected = False
        if self._reader_task and not self._reader_task.done():
            self._reader_task.cancel()
            try:
                await self._reader_task
            except (asyncio.CancelledError, Exception):
                pass
            self._reader_task = None

        if self.transport:
            try:
                await self.transport.close()
            except Exception:
                pass
            self.transport = None

        # Terminate pending request futures
        for req_id, fut in list(self._pending.items()):
            if not fut.done():
                fut.set_exception(CDPConnectionError("CDP connection closed"))
        self._pending.clear()

        # Terminate pending event waiters
        for event_name, waiters in list(self._event_waiters.items()):
            for w in waiters:
                if not w.done():
                    w.cancel()
        self._event_waiters.clear()
        self._ref_map.clear()
        self._root_ax = None

    async def __aenter__(self) -> CDPClient:
        await self.connect()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        await self.close()

    async def _read_loop(self) -> None:
        """Continuously reads incoming frames from transport and routes to futures/callbacks."""
        try:
            while self._connected and self.transport and not self.transport.is_closed():
                raw_text = await self.transport.recv()
                if not raw_text:
                    break

                try:
                    msg = json.loads(raw_text)
                except Exception:
                    continue

                # Response frame
                if "id" in msg:
                    req_id = msg["id"]
                    fut = self._pending.pop(req_id, None)
                    if fut and not fut.done():
                        if "error" in msg:
                            err_info = msg["error"]
                            fut.set_exception(
                                CDPCommandError(
                                    err_info.get("message", "CDP command failed"),
                                    code=err_info.get("code"),
                                    data=err_info.get("data"),
                                )
                            )
                        else:
                            res_obj = msg.get("result", {})
                            if isinstance(res_obj, dict) and "exceptionDetails" in msg and "exceptionDetails" not in res_obj:
                                res_obj["exceptionDetails"] = msg["exceptionDetails"]
                            fut.set_result(res_obj)

                # Event frame
                if "method" in msg:
                    method = msg["method"]
                    params = msg.get("params", {})

                    waiters = self._event_waiters.pop(method, [])
                    for w in waiters:
                        if not w.done():
                            w.set_result(params)

                    listeners = list(self._event_listeners.get(method, []))
                    for cb in listeners:
                        try:
                            res = cb(params)
                            if asyncio.iscoroutine(res):
                                asyncio.create_task(res)
                        except Exception as e:
                            logger.error(f"Error in CDP event listener for {method}: {e}")

        except (asyncio.CancelledError, EOFError, CDPConnectionError):
            pass
        finally:
            for req_id, fut in list(self._pending.items()):
                if not fut.done():
                    fut.set_exception(CDPConnectionError("CDP transport disconnected"))
            self._pending.clear()

    async def send_cdp(
        self, method: str, params: Optional[Dict[str, Any]] = None, timeout: Optional[float] = None
    ) -> Dict[str, Any]:
        """Dispatches a low-level CDP method request and awaits the result."""
        if not self._connected or not self.transport:
            raise CDPConnectionError("Cannot send CDP command: client is not connected")

        self._req_id += 1
        req_id = self._req_id
        fut: asyncio.Future[Dict[str, Any]] = asyncio.get_running_loop().create_future()
        self._pending[req_id] = fut

        payload = {
            "id": req_id,
            "method": method,
            "params": params or {},
        }
        await self.transport.send(json.dumps(payload))

        deadline = timeout if timeout is not None else self.timeout
        try:
            return await asyncio.wait_for(fut, timeout=deadline)
        except asyncio.TimeoutError:
            self._pending.pop(req_id, None)
            raise CDPTimeoutError(f"Timed out waiting for CDP response to '{method}' (id={req_id})")

    def add_event_listener(self, event: str, callback: Callable[[Dict[str, Any]], Any]) -> None:
        """Registers a callback for a specific CDP event (e.g. 'Page.loadEventFired')."""
        self._event_listeners.setdefault(event, []).append(callback)

    def remove_event_listener(self, event: str, callback: Callable[[Dict[str, Any]], Any]) -> None:
        """Unregisters an event callback."""
        if event in self._event_listeners and callback in self._event_listeners[event]:
            self._event_listeners[event].remove(callback)

    async def wait_for_event(self, event: str, timeout: Optional[float] = None) -> Dict[str, Any]:
        """Awaits the next occurrence of a CDP event."""
        fut: asyncio.Future[Dict[str, Any]] = asyncio.get_running_loop().create_future()
        self._event_waiters.setdefault(event, []).append(fut)
        deadline = timeout if timeout is not None else self.timeout
        try:
            return await asyncio.wait_for(fut, timeout=deadline)
        except asyncio.TimeoutError:
            if fut in self._event_waiters.get(event, []):
                self._event_waiters[event].remove(fut)
            raise CDPTimeoutError(f"Timed out waiting for CDP event '{event}'")

    # ========================================================================
    # High-Level Actions
    # ========================================================================

    async def navigate(
        self, url: str, wait_until: str = "load", timeout: Optional[float] = None
    ) -> Dict[str, Any]:
        """
        Navigates the page to the target URL and awaits Page.loadEventFired.
        """
        deadline = timeout if timeout is not None else self.timeout
        await self.send_cdp("Page.enable", timeout=deadline)

        load_fut: asyncio.Future[Dict[str, Any]] = asyncio.get_running_loop().create_future()
        self._event_waiters.setdefault("Page.loadEventFired", []).append(load_fut)

        try:
            nav_result = await self.send_cdp("Page.navigate", {"url": url}, timeout=deadline)
            await asyncio.wait_for(load_fut, timeout=deadline)
            return nav_result
        except asyncio.TimeoutError:
            if load_fut in self._event_waiters.get("Page.loadEventFired", []):
                self._event_waiters["Page.loadEventFired"].remove(load_fut)
            raise CDPTimeoutError(f"Navigation to '{url}' timed out waiting for load event")

    async def get_axtree(self, timeout: Optional[float] = None) -> Optional[AXNode]:
        """
        Fetches the full accessibility tree via Accessibility.getFullAXTree,
        downsamples/compacts it, and caches ref mappings.
        """
        deadline = timeout if timeout is not None else self.timeout
        try:
            await self.send_cdp("Accessibility.enable", timeout=deadline)
        except Exception:
            pass

        res = await self.send_cdp("Accessibility.getFullAXTree", timeout=deadline)
        raw_nodes = res.get("nodes", [])
        root, ref_map = from_cdp_ax_tree(raw_nodes)

        self._root_ax = root
        self._ref_map = ref_map
        return root

    async def get_axtree_asl(self, timeout: Optional[float] = None, colon_prefix: bool = True) -> str:
        """Fetches the AXTree and returns it formatted as a compact ASL S-expression frame."""
        root = await self.get_axtree(timeout=timeout)
        if not root:
            return "()"
        return root.to_asl(colon_prefix=colon_prefix)

    async def click(
        self, ref_or_selector: str, use_mouse_event: bool = False, timeout: Optional[float] = None
    ) -> Dict[str, Any]:
        """
        Clicks an element by @eN ref or CSS selector.
        Uses Runtime.callFunctionOn / Runtime.evaluate or Input.dispatchMouseEvent.
        """
        deadline = timeout if timeout is not None else self.timeout

        if ref_or_selector.startswith("@e"):
            # Ref resolution
            node = self._ref_map.get(ref_or_selector)
            if not node:
                await self.get_axtree(timeout=deadline)
                node = self._ref_map.get(ref_or_selector)

            if not node:
                raise CDPElementNotFoundError(f"Element ref '{ref_or_selector}' not found in accessibility tree")

            if node.backend_node_id is not None:
                res = await self.send_cdp(
                    "DOM.resolveNode", {"backendNodeId": node.backend_node_id}, timeout=deadline
                )
                object_id = res.get("object", {}).get("objectId")
                if not object_id:
                    raise CDPElementNotFoundError(f"Could not resolve DOM node for ref '{ref_or_selector}'")

                if use_mouse_event:
                    box = await self.send_cdp(
                        "DOM.getBoxModel", {"backendNodeId": node.backend_node_id}, timeout=deadline
                    )
                    content = box.get("model", {}).get("content", [0, 0, 0, 0, 0, 0, 0, 0])
                    cx = (content[0] + content[4]) / 2.0
                    cy = (content[1] + content[5]) / 2.0

                    await self.send_cdp(
                        "Input.dispatchMouseEvent",
                        {"type": "mousePressed", "x": cx, "y": cy, "button": "left", "clickCount": 1},
                        timeout=deadline,
                    )
                    await self.send_cdp(
                        "Input.dispatchMouseEvent",
                        {"type": "mouseReleased", "x": cx, "y": cy, "button": "left", "clickCount": 1},
                        timeout=deadline,
                    )
                    return {"clicked": True, "ref": ref_or_selector, "method": "mouse_event", "x": cx, "y": cy}
                else:
                    fn = """function() {
                        this.scrollIntoView({block: 'center', inline: 'center'});
                        this.click();
                        return {clicked: true};
                    }"""
                    call_res = await self.send_cdp(
                        "Runtime.callFunctionOn",
                        {"objectId": object_id, "functionDeclaration": fn, "returnByValue": True},
                        timeout=deadline,
                    )
                    return {
                        "clicked": True,
                        "ref": ref_or_selector,
                        "method": "callFunctionOn",
                        "result": call_res.get("result", {}).get("value"),
                    }
            else:
                # Fallback to evaluation by name and role
                fn_eval = f"""(() => {{
                    const els = Array.from(document.querySelectorAll('*'));
                    const el = els.find(e => (e.getAttribute('role') === '{escape_asl(node.role)}' || e.tagName.toLowerCase() === '{escape_asl(node.role)}') && (e.innerText?.trim() === '{escape_asl(node.name)}' || e.getAttribute('aria-label') === '{escape_asl(node.name)}'));
                    if (!el) throw new Error('Ref {ref_or_selector} not located');
                    el.scrollIntoView({{block: 'center'}});
                    el.click();
                    return {{clicked: true}};
                }})()"""
                res = await self.send_cdp(
                    "Runtime.evaluate", {"expression": fn_eval, "returnByValue": True}, timeout=deadline
                )
                if res.get("exceptionDetails"):
                    raise CDPElementNotFoundError(f"Failed to click ref '{ref_or_selector}': {res['exceptionDetails']}")
                return {"clicked": True, "ref": ref_or_selector, "method": "evaluate"}

        else:
            # Selector resolution
            if use_mouse_event:
                expr = f"""(() => {{
                    const el = document.querySelector('{escape_asl(ref_or_selector)}');
                    if (!el) throw new Error('Selector not found: {escape_asl(ref_or_selector)}');
                    el.scrollIntoView({{block: 'center', inline: 'center'}});
                    const r = el.getBoundingClientRect();
                    return {{x: r.x + r.width / 2, y: r.y + r.height / 2}};
                }})()"""
                res = await self.send_cdp(
                    "Runtime.evaluate", {"expression": expr, "returnByValue": True}, timeout=deadline
                )
                if res.get("exceptionDetails"):
                    raise CDPElementNotFoundError(f"Selector '{ref_or_selector}' not found on page")
                coords = res.get("result", {}).get("value", {})
                cx, cy = coords.get("x", 0), coords.get("y", 0)

                await self.send_cdp(
                    "Input.dispatchMouseEvent",
                    {"type": "mousePressed", "x": cx, "y": cy, "button": "left", "clickCount": 1},
                    timeout=deadline,
                )
                await self.send_cdp(
                    "Input.dispatchMouseEvent",
                    {"type": "mouseReleased", "x": cx, "y": cy, "button": "left", "clickCount": 1},
                    timeout=deadline,
                )
                return {"clicked": True, "selector": ref_or_selector, "method": "mouse_event", "x": cx, "y": cy}
            else:
                expr = f"""(() => {{
                    const el = document.querySelector('{escape_asl(ref_or_selector)}');
                    if (!el) throw new Error('Selector not found: {escape_asl(ref_or_selector)}');
                    el.scrollIntoView({{block: 'center', inline: 'center'}});
                    el.click();
                    return {{clicked: true, tag: el.tagName.toLowerCase()}};
                }})()"""
                res = await self.send_cdp(
                    "Runtime.evaluate", {"expression": expr, "returnByValue": True}, timeout=deadline
                )
                if res.get("exceptionDetails"):
                    raise CDPElementNotFoundError(f"Selector '{ref_or_selector}' not found on page")
                return {
                    "clicked": True,
                    "selector": ref_or_selector,
                    "method": "evaluate",
                    "result": res.get("result", {}).get("value"),
                }

    async def type_text(
        self,
        ref_or_selector: str,
        text: str,
        clear_first: bool = True,
        timeout: Optional[float] = None,
    ) -> Dict[str, Any]:
        """
        Fills an input/form element located by @eN ref or CSS selector.
        Dispatches input and change DOM events.
        """
        deadline = timeout if timeout is not None else self.timeout

        if ref_or_selector.startswith("@e"):
            node = self._ref_map.get(ref_or_selector)
            if not node:
                await self.get_axtree(timeout=deadline)
                node = self._ref_map.get(ref_or_selector)

            if not node:
                raise CDPElementNotFoundError(f"Element ref '{ref_or_selector}' not found in accessibility tree")

            if node.backend_node_id is not None:
                res = await self.send_cdp(
                    "DOM.resolveNode", {"backendNodeId": node.backend_node_id}, timeout=deadline
                )
                object_id = res.get("object", {}).get("objectId")
                if not object_id:
                    raise CDPElementNotFoundError(f"Could not resolve DOM node for ref '{ref_or_selector}'")

                fn = """function(val, clear) {
                    this.focus();
                    if (clear) this.value = '';
                    this.value = (clear ? '' : this.value) + val;
                    this.dispatchEvent(new Event('input', {bubbles: true}));
                    this.dispatchEvent(new Event('change', {bubbles: true}));
                    return {typed: true, value: this.value};
                }"""
                await self.send_cdp(
                    "Runtime.callFunctionOn",
                    {
                        "objectId": object_id,
                        "functionDeclaration": fn,
                        "arguments": [{"value": text}, {"value": clear_first}],
                        "returnByValue": True,
                    },
                    timeout=deadline,
                )
                return {"typed": True, "ref": ref_or_selector, "value": text}
            else:
                # Fallback to evaluate
                expr = f"""(() => {{
                    const els = Array.from(document.querySelectorAll('input, textarea, [contenteditable="true"]'));
                    const el = els.find(e => e.getAttribute('aria-label') === '{escape_asl(node.name)}' || e.placeholder === '{escape_asl(node.name)}');
                    if (!el) throw new Error('Ref {ref_or_selector} not located for typing');
                    el.focus();
                    if ({'true' if clear_first else 'false'}) el.value = '';
                    el.value = ({'true' if clear_first else 'false'} ? '' : el.value) + '{escape_asl(text)}';
                    el.dispatchEvent(new Event('input', {{bubbles: true}}));
                    el.dispatchEvent(new Event('change', {{bubbles: true}}));
                    return {{typed: true, value: el.value}};
                }})()"""
                res = await self.send_cdp(
                    "Runtime.evaluate", {"expression": expr, "returnByValue": True}, timeout=deadline
                )
                if res.get("exceptionDetails"):
                    raise CDPElementNotFoundError(f"Could not type into ref '{ref_or_selector}': {res['exceptionDetails']}")
                return {"typed": True, "ref": ref_or_selector, "value": text}

        else:
            expr = f"""(() => {{
                const el = document.querySelector('{escape_asl(ref_or_selector)}');
                if (!el) throw new Error('Selector not found: {escape_asl(ref_or_selector)}');
                el.focus();
                if ({'true' if clear_first else 'false'}) el.value = '';
                el.value = ({'true' if clear_first else 'false'} ? '' : el.value) + '{escape_asl(text)}';
                el.dispatchEvent(new Event('input', {{bubbles: true}}));
                el.dispatchEvent(new Event('change', {{bubbles: true}}));
                return {{typed: true, value: el.value}};
            }})()"""
            res = await self.send_cdp(
                "Runtime.evaluate", {"expression": expr, "returnByValue": True}, timeout=deadline
            )
            if res.get("exceptionDetails"):
                raise CDPElementNotFoundError(f"Selector '{ref_or_selector}' not found on page")
            return {"typed": True, "selector": ref_or_selector, "value": text}

    async def screenshot(
        self,
        format: str = "png",
        quality: Optional[int] = None,
        clip: Optional[Dict[str, Any]] = None,
        timeout: Optional[float] = None,
    ) -> bytes:
        """Captures page screenshot and returns decoded bytes."""
        deadline = timeout if timeout is not None else self.timeout
        params: Dict[str, Any] = {"format": format}
        if quality is not None:
            params["quality"] = quality
        if clip is not None:
            params["clip"] = clip

        res = await self.send_cdp("Page.captureScreenshot", params, timeout=deadline)
        b64_data = res.get("data", "")
        return base64.b64decode(b64_data)

    async def screenshot_base64(
        self,
        format: str = "png",
        quality: Optional[int] = None,
        clip: Optional[Dict[str, Any]] = None,
        timeout: Optional[float] = None,
    ) -> str:
        """Captures page screenshot and returns base64 encoded string."""
        deadline = timeout if timeout is not None else self.timeout
        params: Dict[str, Any] = {"format": format}
        if quality is not None:
            params["quality"] = quality
        if clip is not None:
            params["clip"] = clip

        res = await self.send_cdp("Page.captureScreenshot", params, timeout=deadline)
        return str(res.get("data", ""))


# ============================================================================
# Synchronous Wrapper Client
# ============================================================================


class SyncCDPClient:
    """
    Synchronous wrapper for CDPClient for legacy or non-async agent environments.
    """

    def __init__(self, endpoint: str = "http://localhost:9222", **kwargs: Any):
        self._client = CDPClient(endpoint=endpoint, **kwargs)
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._owns_loop = False

    def _get_loop(self) -> asyncio.AbstractEventLoop:
        try:
            loop = asyncio.get_running_loop()
            return loop
        except RuntimeError:
            if self._loop is None or self._loop.is_closed():
                self._loop = asyncio.new_event_loop()
                self._owns_loop = True
            return self._loop

    def _run(self, coro: Any) -> Any:
        loop = self._get_loop()
        if loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
                return executor.submit(asyncio.run, coro).result()
        else:
            return loop.run_until_complete(coro)

    def connect(self) -> SyncCDPClient:
        self._run(self._client.connect())
        return self

    def close(self) -> None:
        self._run(self._client.close())
        if self._owns_loop and self._loop and not self._loop.is_closed():
            self._loop.close()

    def navigate(self, url: str, timeout: Optional[float] = None) -> Dict[str, Any]:
        return self._run(self._client.navigate(url, timeout=timeout))

    def get_axtree(self, timeout: Optional[float] = None) -> Optional[AXNode]:
        return self._run(self._client.get_axtree(timeout=timeout))

    def get_axtree_asl(self, timeout: Optional[float] = None, colon_prefix: bool = True) -> str:
        return self._run(self._client.get_axtree_asl(timeout=timeout, colon_prefix=colon_prefix))

    def click(
        self, ref_or_selector: str, use_mouse_event: bool = False, timeout: Optional[float] = None
    ) -> Dict[str, Any]:
        return self._run(
            self._client.click(ref_or_selector, use_mouse_event=use_mouse_event, timeout=timeout)
        )

    def type_text(
        self,
        ref_or_selector: str,
        text: str,
        clear_first: bool = True,
        timeout: Optional[float] = None,
    ) -> Dict[str, Any]:
        return self._run(
            self._client.type_text(ref_or_selector, text, clear_first=clear_first, timeout=timeout)
        )

    def screenshot(
        self,
        format: str = "png",
        quality: Optional[int] = None,
        clip: Optional[Dict[str, Any]] = None,
        timeout: Optional[float] = None,
    ) -> bytes:
        return self._run(
            self._client.screenshot(format=format, quality=quality, clip=clip, timeout=timeout)
        )

    def screenshot_base64(
        self,
        format: str = "png",
        quality: Optional[int] = None,
        clip: Optional[Dict[str, Any]] = None,
        timeout: Optional[float] = None,
    ) -> str:
        return self._run(
            self._client.screenshot_base64(format=format, quality=quality, clip=clip, timeout=timeout)
        )

    def send_cdp(
        self, method: str, params: Optional[Dict[str, Any]] = None, timeout: Optional[float] = None
    ) -> Dict[str, Any]:
        return self._run(self._client.send_cdp(method, params=params, timeout=timeout))

    def __enter__(self) -> SyncCDPClient:
        return self.connect()

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()
