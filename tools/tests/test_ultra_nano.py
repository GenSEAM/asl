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
    assert "(:f x Int64" in nano_out
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
