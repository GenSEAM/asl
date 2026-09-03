#!/usr/bin/env python3
"""
AgP frame layer — reference reader, codec and session for the wire specification
in docs/AGENTIC_PROTOCOL.md Part I.

The wire is AgentScript s-expressions, not JSON: this module reads and writes
AgentScript literals so that a frame it emits is a frame it can read back.
"""

import re
import sys
from typing import Any, Dict, List, Optional, Tuple

PROTOCOL_VERSION = "asl/1.0"

# Reserved peer identifier, used before a peer has told you its real id.
UNKNOWN_PEER = "agent"

HANDSHAKE_PROBE = f'(? {UNKNOWN_PEER} probe :proto "{PROTOCOL_VERSION}")'
HANDSHAKE_ACK = f'(! {UNKNOWN_PEER} :ok (proto :v "{PROTOCOL_VERSION}" :mode :nano))'

# The one error taxonomy. The keyword is what travels in a frame-layer `:err`;
# the integer is the same failure as a SkyLoom NACK code.
ERROR_CODES: Dict[str, int] = {
    "peer-unreachable": 1001,
    "lonely-queued": 1002,
    "dialect-unsupported": 1003,
    "decode-failed": 1004,
    "type-mismatch": 1005,
    "timeout": 1006,
    "stalled": 1007,
    "dead-letter": 1008,
    "scope-violation": 1009,
    "handoff-rejected": 1010,
}

KEY_RE = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")


class WireError(ValueError):
    """Raised for anything the frame grammar does not admit."""


class Symbol(str):
    """A bare identifier such as `agent-coder`; distinct from a String literal."""

    __slots__ = ()


class Keyword(str):
    """A `:name` token, carried without its leading colon."""

    __slots__ = ()



_TOKEN = re.compile(
    r"""
      (?P<ws>\s+)
    | (?P<comment>;[^\n]*)
    | (?P<open>[(\[])
    | (?P<close>[)\]])
    | (?P<string>"(?:[^"\\]|\\.)*")
    | (?P<atom>[^\s,()\[\]";]+)
    """,
    re.VERBOSE,
)

_INT = re.compile(r"^[+-]?[0-9]+$")
_FLOAT = re.compile(r"^[+-]?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?$")

_STR_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}


def _unescape(literal: str) -> str:
    out: List[str] = []
    i = 1
    end = len(literal) - 1
    while i < end:
        ch = literal[i]
        if ch == "\\":
            i += 1
            if i >= end:
                raise WireError("string ends inside an escape sequence")
            esc = literal[i]
            if esc not in _STR_ESCAPES:
                raise WireError(f"unknown string escape \\{esc}")
            out.append(_STR_ESCAPES[esc])
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def _escape(text: str) -> str:
    out = ['"']
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _atom(text: str) -> Any:
    if text.startswith(":"):
        name = text[1:]
        if not name:
            raise WireError("bare `:` is not a keyword")
        return Keyword(name)
    if text == "true":
        return True
    if text == "false":
        return False
    if _INT.match(text):
        return int(text)
    if _FLOAT.match(text):
        return float(text)
    return Symbol(text)


def _tokenize(source: str) -> List[Tuple[str, str]]:
    tokens: List[Tuple[str, str]] = []
    pos = 0
    while pos < len(source):
        m = _TOKEN.match(source, pos)
        if not m:
            raise WireError(
                f"character {source[pos]!r} at offset {pos} is not in the frame grammar"
            )
        kind = m.lastgroup or ""
        if kind not in ("ws", "comment"):
            tokens.append((kind, m.group()))
        pos = m.end()
    return tokens


def read_all(source: str) -> List[Any]:
    """Read every top-level form in `source` into Python data."""
    tokens = _tokenize(source)
    forms: List[Any] = []
    stack: List[Tuple[str, List[Any]]] = []

    for kind, text in tokens:
        if kind == "open":
            stack.append((text, []))
            continue
        if kind == "close":
            if not stack:
                raise WireError(f"unbalanced `{text}` with no open form")
            opener, items = stack.pop()
            expected = ")" if opener == "(" else "]"
            if text != expected:
                raise WireError(f"`{opener}` closed by `{text}`, expected `{expected}`")
            node: Any = tuple(items) if opener == "(" else items
            (stack[-1][1] if stack else forms).append(node)
            continue
        value = _unescape(text) if kind == "string" else _atom(text)
        (stack[-1][1] if stack else forms).append(value)

    if stack:
        raise WireError(f"{len(stack)} form(s) left open at end of input")
    return forms


def read_one(source: str) -> Any:
    forms = read_all(source)
    if len(forms) != 1:
        raise WireError(f"expected exactly one form, read {len(forms)}")
    return forms[0]


def dump(value: Any) -> str:
    """Render Python data as an AgentScript literal."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, Keyword):
        return f":{value}"
    if isinstance(value, Symbol):
        return str(value)
    if isinstance(value, str):
        return _escape(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, tuple):
        return "(" + " ".join(dump(v) for v in value) + ")"
    if isinstance(value, list):
        return "[" + " ".join(dump(v) for v in value) + "]"
    raise WireError(f"{type(value).__name__} has no AgentScript literal form")




def _check_key(key: str) -> str:
    if not KEY_RE.match(key):
        raise WireError(
            f"parameter key {key!r} is not kebab-case; the wire admits `timeout-ms`, "
            "never `timeout_ms`, `t_out` or `timeoutMs`"
        )
    return key


def _pairs(items: Tuple[Any, ...], context: str) -> Dict[str, Any]:
    params: Dict[str, Any] = {}
    i = 0
    while i < len(items):
        key = items[i]
        if not isinstance(key, Keyword):
            raise WireError(f"{context}: expected a `:key`, found {dump(key)}")
        if i + 1 >= len(items):
            raise WireError(f"{context}: `:{key}` has no value")
        params[_check_key(str(key))] = items[i + 1]
        i += 2
    return params


def _name(value: Any, context: str) -> str:
    if not isinstance(value, (Symbol, str)) or isinstance(value, Keyword):
        raise WireError(f"{context}: expected an identifier, found {dump(value)}")
    return str(value)


def encode_query(target: str, verb: str, **params: Any) -> str:
    """`(? <target> <verb> [:key <value> ...])`. Underscores in kwargs become hyphens."""
    parts = [f"(? {target} {verb}"]
    for key, value in params.items():
        parts.append(f" :{_check_key(key.replace('_', '-'))} {dump(value)}")
    return "".join(parts) + ")"


def encode_ok(source: str, payload: Any) -> str:
    """`(! <source> :ok <payload>)`."""
    return f"(! {source} :ok {dump(payload)})"


def encode_err(source: str, code: str, msg: str, retry: Optional[bool] = None) -> str:
    """`(! <source> :err <code> :msg "<detail>" [:retry <bool>])`."""
    if code not in ERROR_CODES:
        raise WireError(f"{code!r} is not in the AgP error taxonomy")
    tail = "" if retry is None else f" :retry {dump(retry)}"
    return f"(! {source} :err :{code} :msg {_escape(msg)}{tail})"


def encode_chunk(stream_id: str, seq: int, chunk: Any) -> str:
    """`(~ <stream-id> :seq <n> :chunk <payload>)`."""
    return f"(~ {stream_id} :seq {seq} :chunk {dump(chunk)})"


def encode_end(stream_id: str, seq: int) -> str:
    """`(~ <stream-id> :seq <n> :end true)` — the frame that closes a stream."""
    return f"(~ {stream_id} :seq {seq} :end true)"


def decode_frame(line: str) -> Dict[str, Any]:
    """Read one AgP frame into a dict. Raises WireError on anything else."""
    form = read_one(line)
    if not isinstance(form, tuple) or not form:
        raise WireError(f"not a frame: {line.strip()!r}")

    head, rest = form[0], form[1:]
    if not isinstance(head, Symbol):
        raise WireError(f"frame head {dump(head)} is not a sigil")

    if head == "?":
        if len(rest) < 2:
            raise WireError("query frame needs a target and a verb")
        return {
            "type": "query",
            "target": _name(rest[0], "query target"),
            "verb": _name(rest[1], "query verb"),
            "params": _pairs(rest[2:], "query"),
        }

    if head == "!":
        if len(rest) < 2:
            raise WireError("response frame needs a source and a status")
        source = _name(rest[0], "response source")
        status = rest[1]
        if not isinstance(status, Keyword):
            raise WireError(f"response status {dump(status)} is not `:ok` or `:err`")
        if status == "ok":
            if len(rest) != 3:
                raise WireError("`:ok` carries exactly one payload")
            return {"type": "response", "source": source, "status": "ok", "payload": rest[2]}
        if status == "err":
            if len(rest) < 2 or not isinstance(rest[2], Keyword):
                raise WireError("`:err` must be followed by an error keyword")
            code = str(rest[2])
            if code not in ERROR_CODES:
                raise WireError(f"{code!r} is not in the AgP error taxonomy")
            fields = _pairs(rest[3:], "error frame")
            unknown = set(fields) - {"msg", "retry"}
            if unknown:
                raise WireError(f"error frame carries unknown key(s): {sorted(unknown)}")
            if "msg" not in fields:
                raise WireError("`:err` frame is missing `:msg`")
            return {
                "type": "response",
                "source": source,
                "status": "err",
                "code": code,
                "numeric": ERROR_CODES[code],
                "msg": fields["msg"],
                "retry": fields.get("retry"),
            }
        raise WireError(f"unknown response status `:{status}`")

    if head == "~":
        if len(rest) < 1:
            raise WireError("stream frame needs a stream id")
        stream = _name(rest[0], "stream id")
        fields = _pairs(rest[1:], "stream frame")
        if "seq" not in fields:
            raise WireError("stream frame is missing `:seq`")
        if ("chunk" in fields) == ("end" in fields):
            raise WireError("stream frame carries exactly one of `:chunk` or `:end`")
        out: Dict[str, Any] = {"type": "stream", "stream": stream, "seq": fields["seq"]}
        if "end" in fields:
            out["end"] = fields["end"]
        else:
            out["chunk"] = fields["chunk"]
        return out

    raise WireError(f"`{head}` is not an AgP sigil; expected `?`, `!` or `~`")


def encode_frame(frame: Dict[str, Any]) -> str:
    """Inverse of decode_frame, so a decoded frame can be put back on the wire."""
    kind = frame.get("type")
    if kind == "query":
        return encode_query(frame["target"], frame["verb"], **frame.get("params", {}))
    if kind == "response":
        if frame["status"] == "ok":
            return encode_ok(frame["source"], frame["payload"])
        return encode_err(frame["source"], frame["code"], frame["msg"], frame.get("retry"))
    if kind == "stream":
        if frame.get("end"):
            return encode_end(frame["stream"], frame["seq"])
        return encode_chunk(frame["stream"], frame["seq"], frame["chunk"])
    raise WireError(f"cannot encode frame of type {kind!r}")


class AgpWireSession:
    """One peer's side of an AgP conversation."""

    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        self.peer_id: Optional[str] = None
        self.handshake_complete = False
        self.compression_mode = "nano"

    def probe(self) -> str:
        return encode_query(UNKNOWN_PEER, "probe", proto=PROTOCOL_VERSION)

    def accept_probe(self, line: str) -> Optional[str]:
        """Answer a probe with an ack, or return None if the line is not a probe."""
        try:
            frame = decode_frame(line)
        except WireError:
            return None
        if frame["type"] != "query" or frame["verb"] != "probe":
            return None
        if frame["params"].get("proto") != PROTOCOL_VERSION:
            return encode_err(
                self.agent_id,
                "dialect-unsupported",
                f"this peer speaks {PROTOCOL_VERSION}",
                retry=False,
            )
        self.handshake_complete = True
        return encode_ok(
            self.agent_id,
            (Symbol("proto"), Keyword("v"), PROTOCOL_VERSION, Keyword("mode"), Keyword(self.compression_mode)),
        )

    def handle_ack(self, line: str) -> bool:
        try:
            frame = decode_frame(line)
        except WireError:
            return False
        if frame["type"] != "response" or frame["status"] != "ok":
            return False
        payload = frame["payload"]
        if not isinstance(payload, tuple) or not payload or payload[0] != "proto":
            return False
        fields = _pairs(payload[1:], "ack payload")
        if fields.get("v") != PROTOCOL_VERSION:
            return False
        self.peer_id = frame["source"]
        self.compression_mode = str(fields.get("mode", "nano"))
        self.handshake_complete = True
        return True

    def encode_query(self, target: str, verb: str, **params: Any) -> str:
        return encode_query(target, verb, **params)

    def encode_response(self, payload: Any = None, err_code: Optional[str] = None,
                        msg: str = "", retry: Optional[bool] = None) -> str:
        if err_code:
            return encode_err(self.agent_id, err_code, msg, retry)
        return encode_ok(self.agent_id, payload)

    def decode_frame(self, line: str) -> Dict[str, Any]:
        return decode_frame(line)


if __name__ == "__main__":
    session = AgpWireSession("agent-orchestrator")
    for frame in (
        session.probe(),
        session.accept_probe(HANDSHAKE_PROBE) or "",
        session.encode_query("agent-coder", "synthesize-fsm",
                             states=["idle", "active", "error"], timeout_ms=50),
        session.encode_response(payload=(Symbol("fsm"), Keyword("states"), 3,
                                         Keyword("file"), "state.asl")),
        session.encode_response(err_code="scope-violation",
                                msg="path '/etc/shadow' is outside the jailed workspace",
                                retry=False),
        encode_chunk("stream-7", 1, (Symbol("reading"), 22.4)),
        encode_end("stream-7", 2),
    ):
        print(frame)
        print(f"  -> {decode_frame(frame)}", file=sys.stderr)
