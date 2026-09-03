"""AgP frame-layer conformance: the codec must read every frame it writes, and
every example printed in docs/AGENTIC_PROTOCOL.md must decode."""

import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))

from tools.a2a_wire import (  # noqa: E402
    ERROR_CODES,
    KEY_RE,
    HANDSHAKE_ACK,
    HANDSHAKE_PROBE,
    PROTOCOL_VERSION,
    AgpWireSession,
    Keyword,
    Symbol,
    WireError,
    decode_frame,
    dump,
    encode_chunk,
    encode_end,
    encode_err,
    encode_frame,
    encode_ok,
    encode_query,
    read_all,
    read_one,
)

SPEC = ROOT / "docs" / "AGENTIC_PROTOCOL.md"
# Wire frames are fenced ```agp: they are the protocol's language, not Core
# AgentScript, so tools/doc_examples.py must not try to parse them as Core.
AGP_BLOCK = re.compile(r"^```agp\n(.*?)^```", re.MULTILINE | re.DOTALL)
SIGILS = ("?", "!", "~")


def spec_forms():
    """Every top-level form in every ```agp block of the specification."""
    text = SPEC.read_text(encoding="utf-8")
    blocks = AGP_BLOCK.findall(text)
    assert blocks, "specification contains no ```agp examples to check"
    forms = []
    for block in blocks:
        forms.extend((block, form) for form in read_all(block))
    return forms


def spec_frames():
    return [(b, f) for b, f in spec_forms() if isinstance(f, tuple) and f and f[0] in SIGILS]




@pytest.mark.parametrize("block,form", spec_forms(), ids=lambda v: None)
def test_every_spec_example_is_balanced(block, form):
    assert form is not None


def test_spec_contains_frames_of_every_kind():
    kinds = {decode_frame(dump(f))["type"] for _, f in spec_frames()}
    assert kinds == {"query", "response", "stream"}


@pytest.mark.parametrize("block,form", spec_frames(), ids=lambda v: None)
def test_every_spec_frame_decodes_and_round_trips(block, form):
    wire = dump(form)
    frame = decode_frame(wire)
    assert encode_frame(frame) == wire


def test_spec_handshake_frames_match_the_module_constants():
    text = SPEC.read_text(encoding="utf-8")
    assert HANDSHAKE_PROBE in text
    assert HANDSHAKE_ACK in text


def test_spec_error_table_matches_the_taxonomy():
    text = SPEC.read_text(encoding="utf-8")
    rows = dict(re.findall(r"^\| `:([a-z-]+)` \| (\d{4}) \|", text, re.MULTILINE))
    assert {k: int(v) for k, v in rows.items()} == ERROR_CODES


def test_spec_code_blocks_never_show_a_spaceless_sigil():
    text = SPEC.read_text(encoding="utf-8")
    for block in re.findall(r"^```[a-z]*\n(.*?)^```", text, re.MULTILINE | re.DOTALL):
        assert not re.search(r"\([?!~][A-Za-z]", block), block




def test_handshake_constants_decode():
    probe = decode_frame(HANDSHAKE_PROBE)
    assert probe == {
        "type": "query",
        "target": "agent",
        "verb": "probe",
        "params": {"proto": PROTOCOL_VERSION},
    }
    ack = decode_frame(HANDSHAKE_ACK)
    assert ack["type"] == "response" and ack["status"] == "ok"
    assert ack["payload"][0] == "proto"


def test_session_completes_a_handshake():
    alpha = AgpWireSession("agent-alpha")
    beta = AgpWireSession("agent-beta")

    ack = beta.accept_probe(alpha.probe())
    assert beta.handshake_complete
    assert decode_frame(ack)["source"] == "agent-beta"

    assert alpha.handle_ack(ack) is True
    assert alpha.handshake_complete
    assert alpha.peer_id == "agent-beta"
    assert alpha.compression_mode == "nano"


def test_session_accepts_its_own_module_constants():
    beta = AgpWireSession("agent-beta")
    assert beta.accept_probe(HANDSHAKE_PROBE) is not None
    assert AgpWireSession("agent-alpha").handle_ack(HANDSHAKE_ACK) is True


def test_probe_with_a_foreign_version_is_refused_in_band():
    beta = AgpWireSession("agent-beta")
    reply = beta.accept_probe('(? agent probe :proto "asl/9.9")')
    frame = decode_frame(reply)
    assert frame["status"] == "err"
    assert frame["code"] == "dialect-unsupported"
    assert beta.handshake_complete is False


def test_accept_probe_ignores_non_probe_traffic():
    beta = AgpWireSession("agent-beta")
    assert beta.accept_probe("hello there") is None
    assert beta.accept_probe("(? agent-x compile :target \"wasm\")") is None




def test_query_round_trip():
    wire = encode_query("agent-coder", "synthesize-fsm",
                        states=["idle", "active", "error"], timeout_ms=50)
    assert wire == '(? agent-coder synthesize-fsm :states ["idle" "active" "error"] :timeout-ms 50)'
    frame = decode_frame(wire)
    assert frame["params"] == {"states": ["idle", "active", "error"], "timeout-ms": 50}
    assert encode_frame(frame) == wire


def test_ok_round_trip():
    payload = (Symbol("fsm"), Keyword("states"), 3, Keyword("file"), "state.asl")
    wire = encode_ok("agent-coder", payload)
    assert wire == '(! agent-coder :ok (fsm :states 3 :file "state.asl"))'
    frame = decode_frame(wire)
    assert frame["payload"] == payload
    assert encode_frame(frame) == wire


def test_err_round_trip_carries_the_numeric_code():
    wire = encode_err("agent-coder", "scope-violation", 'path "/etc/shadow" is jailed', retry=False)
    frame = decode_frame(wire)
    assert frame["code"] == "scope-violation"
    assert frame["numeric"] == 1009
    assert frame["msg"] == 'path "/etc/shadow" is jailed'
    assert frame["retry"] is False
    assert encode_frame(frame) == wire


def test_err_round_trip_without_retry():
    wire = encode_err("agent-coder", "timeout", "no ack in 5000ms")
    frame = decode_frame(wire)
    assert frame["retry"] is None
    assert encode_frame(frame) == wire


@pytest.mark.parametrize("code,numeric", sorted(ERROR_CODES.items()))
def test_every_error_code_round_trips(code, numeric):
    frame = decode_frame(encode_err("agent-x", code, "detail"))
    assert (frame["code"], frame["numeric"]) == (code, numeric)


def test_stream_chunk_and_end_round_trip():
    chunk = encode_chunk("stream-7", 1, (Symbol("reading"), 22.4))
    assert chunk == "(~ stream-7 :seq 1 :chunk (reading 22.4))"
    assert encode_frame(decode_frame(chunk)) == chunk

    end = encode_end("stream-7", 2)
    assert end == "(~ stream-7 :seq 2 :end true)"
    assert decode_frame(end)["end"] is True
    assert encode_frame(decode_frame(end)) == end


def test_session_response_helpers_round_trip():
    session = AgpWireSession("agent-orchestrator")
    ok = session.encode_response(payload=[1, 2, 3])
    assert session.decode_frame(ok)["payload"] == [1, 2, 3]
    bad = session.encode_response(err_code="dead-letter", msg="gave up after 5 tries", retry=False)
    assert session.decode_frame(bad)["numeric"] == 1008




def test_reader_distinguishes_lists_from_forms():
    assert read_one("(a [b c])") == (Symbol("a"), [Symbol("b"), Symbol("c")])


def test_reader_reads_every_scalar_kind():
    assert read_all('"s" 42 -7 3.5 true false :kw sym') == [
        "s", 42, -7, 3.5, True, False, Keyword("kw"), Symbol("sym"),
    ]


def test_reader_skips_comments():
    assert read_all(";; a note\n(a) ; trailing\n(b)") == [(Symbol("a"),), (Symbol("b"),)]


def test_string_escapes_survive_a_round_trip():
    original = 'quote " backslash \\ newline \n tab \t'
    assert read_one(dump(original)) == original


@pytest.mark.parametrize("source", [
    "(a",                      # unclosed
    "a)",                      # unbalanced close
    "(a]",                     # mismatched bracket
    '(a "unterminated)',       # unterminated string
])
def test_reader_rejects_malformed_input(source):
    with pytest.raises(WireError):
        read_all(source)


def test_json_commas_are_a_decode_error():
    with pytest.raises(WireError):
        decode_frame('(? agent-coder run :states ["idle", "active"])')


def test_dump_refuses_types_with_no_literal_form():
    with pytest.raises(WireError):
        dump({"a": 1})




def test_spaceless_sigil_is_not_a_frame():
    with pytest.raises(WireError):
        decode_frame('(?agent/probe :proto "asl/1.0")')
    with pytest.raises(WireError):
        decode_frame('(!agent/ack :proto "asl/1.0" :mode :nano)')


def test_encode_normalises_python_kwargs_to_kebab_case():
    # Python cannot spell `timeout-ms=`, so the encoder converts and the wire never
    # carries an underscore.
    wire = encode_query("agent-x", "run", **{"timeout_ms": 5})
    assert wire == "(? agent-x run :timeout-ms 5)"
    assert decode_frame(wire)["params"] == {"timeout-ms": 5}


def test_snake_case_keys_are_refused_on_decode():
    with pytest.raises(WireError):
        decode_frame("(? agent-x run :timeout_ms 5)")


def test_camel_case_keys_are_refused_on_decode():
    with pytest.raises(WireError):
        decode_frame("(? agent-x run :timeoutMs 5)")


def test_unknown_error_keyword_is_refused():
    with pytest.raises(WireError):
        encode_err("agent-x", "kaboom", "detail")
    with pytest.raises(WireError):
        decode_frame('(! agent-x :err :kaboom :msg "detail")')


def test_error_frame_requires_a_message():
    with pytest.raises(WireError):
        decode_frame("(! agent-x :err :timeout)")


def test_ok_carries_exactly_one_payload():
    with pytest.raises(WireError):
        decode_frame("(! agent-x :ok 1 2)")


def test_stream_frame_needs_exactly_one_of_chunk_or_end():
    with pytest.raises(WireError):
        decode_frame("(~ s :seq 1)")
    with pytest.raises(WireError):
        decode_frame("(~ s :seq 1 :chunk 2 :end true)")


def test_non_agp_form_is_not_a_frame():
    with pytest.raises(WireError):
        decode_frame('(loom:frame :v 1 :id "x")')



SKILL = ROOT / "skills" / "skyloom" / "SKILL.md"
LOOM_HEADS = ("loom:frame", "loom:handoff", "loom:yield", "loom:coord")
REQUIRED_KEYS = {
    "loom:handoff": {"v", "id", "from", "to", "ts", "task", "cwd"},
    "loom:yield": {"v", "id", "reply-to", "from", "to", "ts", "status"},
}


def loom_examples():
    """Every `(loom:...)` example printed in an agp block of the spec or the skill."""
    found = []
    for path in (SPEC, SKILL):
        text = path.read_text(encoding="utf-8")
        for block in AGP_BLOCK.findall(text):
            for form in read_all(block):
                if isinstance(form, tuple) and form and form[0] in LOOM_HEADS:
                    found.append((path.name, form))
    assert found, "no session-layer examples found to check"
    return found


@pytest.mark.parametrize("origin,form", loom_examples(), ids=lambda v: None)
def test_loom_example_keys_are_kebab_case(origin, form):
    keys = [str(v) for v in form[1:] if isinstance(v, Keyword)]
    assert keys, f"{origin}: {form[0]} example carries no keys"
    for key in keys:
        assert KEY_RE.match(key), f"{origin}: `:{key}` is not kebab-case"


@pytest.mark.parametrize("origin,form", loom_examples(), ids=lambda v: None)
def test_loom_example_carries_the_required_header(origin, form):
    required = REQUIRED_KEYS.get(str(form[0]))
    if required is None:
        pytest.skip(f"{form[0]} has no fixed key set")
    present = {str(v) for v in form[1:] if isinstance(v, Keyword)}
    assert required <= present, f"{origin}: {form[0]} is missing {sorted(required - present)}"


def test_no_document_spells_the_timeout_key_four_ways():
    for path in (SPEC, SKILL, ROOT / "docs" / "SKYLOOM_SPEC.md"):
        text = path.read_text(encoding="utf-8")
        for block in re.findall(r"^```[a-z]*\n(.*?)^```", text, re.MULTILINE | re.DOTALL):
            for wrong in (":timeout ", ":t-out", ":timeout_ms", ":timeoutMs", '"timeout_ms"'):
                assert wrong not in block, f"{path.name}: {wrong!r} should be `timeout-ms`"


def test_wire_frames_are_never_fenced_as_core_agentscript():
    # tools/doc_examples.py parses ```lisp and ```agentscript as Core AgentScript.
    # A wire frame is the protocol's language, not Core, so it belongs in ```agp.
    for path in (SPEC, SKILL, ROOT / "docs" / "SKYLOOM_SPEC.md"):
        text = path.read_text(encoding="utf-8")
        for block in re.findall(r"^```(?:lisp|agentscript)\n(.*?)^```", text,
                                re.MULTILINE | re.DOTALL):
            for form in read_all(block):
                head = form[0] if isinstance(form, tuple) and form else None
                assert head not in SIGILS and head not in LOOM_HEADS, (
                    f"{path.name}: `{head}` frame is fenced as Core AgentScript; use ```agp"
                )
