"""Unit tests for AgentScript Ultra-Nano syntax expansion & bidirectional transcoder (@pcp:d-1eed)."""

import pytest
from lark import Lark
from pathlib import Path
from tools.transcoder import to_ultra_nano, to_verbose

ROOT = Path(__file__).resolve().parent.parent.parent
LARK_PATH = ROOT / "grammar" / "agentscript.lark"


@pytest.fixture(scope="module")
def parser():
    return Lark.open(str(LARK_PATH), parser="earley")


def test_ultra_nano_schema_and_enum(parser):
    src = """(module test/u
  :d "Ultra nano test module"
  :x [Status User run]
  :i [(core/strings :a s)])

(dfe Status
  (:c active [] "Active status")
  (:c pending [] "Pending status"))

(dfs User
  (:f id Int64 "User ID")
  (:f name String "User name"))

(df run [(u User)] -> Int64
  :d "Runs calculation"
  (mt (.-id u)
    (1 100)
    (_ 0)))
"""
    tree = parser.parse(src)
    assert tree is not None
    assert tree.data == "start"


def test_bidirectional_transcoding(parser):
    verbose_src = """(module math/service
  :doc "Vector service"
  :export [Vec calc]
  :import [(core/strings :as s)])

(defschema Vec
  (:field x Int64 "X coordinate")
  (:field y Int64 "Y coordinate"))

(defun calc [(v Vec)] -> Int64
  :doc "Computes sum"
  (+ (.-x v) (.-y v)))
"""
    # 1. Compress to Ultra-Nano
    nano_out = to_ultra_nano(verbose_src)
    assert "(dfs Vec" in nano_out
    # Type aliases are part of the projection: `Int64` tightens to `I64`.
    assert "(:f x I64" in nano_out
    assert ":d \"Vector service\"" in nano_out
    assert ":x [Vec calc]" in nano_out
    assert "(df calc" in nano_out

    # 2. Verify Ultra-Nano parses in Lark
    tree_nano = parser.parse(nano_out)
    assert tree_nano is not None

    # 3. Expand back to Verbose
    expanded = to_verbose(nano_out)
    assert "(defschema Vec" in expanded
    assert "(:field x Int64" in expanded
    assert ":doc \"Vector service\"" in expanded
    assert ":export [Vec calc]" in expanded
    assert "(defun calc" in expanded

    # 4. Verify expanded parses in Lark
    tree_verbose = parser.parse(expanded)
    assert tree_verbose is not None


RECORD_KEY_MODULE = """"A comment naming :doc and defun, which the transcoder must leave alone."
(module t/keys
  :doc "A record whose field names are the six option letters."
  :export [P mk])

(defschema P
  (:field x Int64 "X")
  (:field d Int64 "D")
  (:field a Int64 "A")
  (:field i Int64 "I")
  (:field f Int64 "F")
  (:field c Int64 "C"))

(defun mk [] -> P
  :doc "Construct it."
  (P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6))
"""

RECORD_KEYS = "(P :x 1 :d 2 :a 3 :i 4 :f 5 :c 6)"


def test_record_keys_are_never_option_keywords(parser):
    """A Nano alias is significant in head and option position only (@pcp:d-1eed).

    The regex transcoder this replaced turned `(P :x 1 :d 2)` into
    `(P :export 1 :doc 2)`, so every field below it stopped resolving.
    """
    nano = to_ultra_nano(RECORD_KEY_MODULE)
    assert "(dfs P" in nano and "(df mk" in nano
    assert RECORD_KEYS in nano
    parser.parse(nano)

    back = to_verbose(nano)
    assert RECORD_KEYS in back
    assert ":export 1" not in back
    parser.parse(back)


def test_transcoding_is_reversible_and_idempotent():
    nano = to_ultra_nano(RECORD_KEY_MODULE)
    assert to_verbose(nano) == RECORD_KEY_MODULE
    assert to_ultra_nano(nano) == nano
    assert to_ultra_nano(to_verbose(nano)) == nano


def test_comments_and_prose_survive_transcoding():
    """Only token spans are replaced, so nothing outside the grammar can move."""
    nano = to_ultra_nano(RECORD_KEY_MODULE)
    assert nano.splitlines()[0] == RECORD_KEY_MODULE.splitlines()[0]
    assert len(nano.splitlines()) == len(RECORD_KEY_MODULE.splitlines())
