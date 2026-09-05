import sys
import json
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from site_claims_gate import (
    extract_claims_from_text,
    clean_line_for_claims,
    load_lockfile,
    harvest_benchmark_sources,
    check_claims,
    write_lockfile,
    DEFAULT_LOCKFILE,
    DEFAULT_WEB_DIR,
)


def test_extract_claims_from_text():
    sample = """
    We achieved -64.7% token reduction against JSON and 57%–65% structural compaction.
    MCP interface compression reaches 78% while SeamBus delegation slashes 83.4%.
    Under benchmark/run.js: cold start is <100ms with <=24MB RSS ceiling and -72.7% tool calling savings.
    Every language primitive obeys the strict <=2 tokens ceiling under BPE.
    Vocabulary coverage stands at 107/107 and Wasm sandbox boots in 0.038ms.
    """
    results = extract_claims_from_text(sample)
    found_keys = {norm for _, norm, _, _ in results}

    assert "-64.7%" in found_keys
    assert "57%–65%" in found_keys
    assert "78%" in found_keys
    assert "83.4%" in found_keys
    assert "<100ms" in found_keys
    assert "<=24MB" in found_keys
    assert "-72.7%" in found_keys
    assert "<=2 tokens" in found_keys
    assert "107/107" in found_keys
    assert "0.038ms" in found_keys


def test_clean_line_ignores_svg_and_styles():
    svg_line = '<filter id="ambient" x="-30%" y="-30%" width="160%" height="160%">'
    gradient_line = '<linearGradient x1="15%" y1="10%" x2="85%" y2="90%">'
    stop_line = '<stop offset="100%" stopColor="#818cf8" />'
    style_line = "style={{ top: '20%', left: '50%' }}"
    tailwind_line = '<div className="bg-purple-500/10 shadow-purple-500/20 text-signal/15">'
    comment_line = "// 50% split for tabs"

    assert extract_claims_from_text(svg_line) == []
    assert extract_claims_from_text(gradient_line) == []
    assert extract_claims_from_text(stop_line) == []
    assert extract_claims_from_text(style_line) == []
    assert extract_claims_from_text(tailwind_line) == []
    assert extract_claims_from_text(comment_line) == []


def test_published_claims_lockfile_integrity():
    assert DEFAULT_LOCKFILE.exists(), f"Lockfile missing at {DEFAULT_LOCKFILE}"
    lock_data = load_lockfile(DEFAULT_LOCKFILE)

    assert lock_data.get("version") == "1.0"
    claims = lock_data.get("claims", {})
    assert len(claims) >= 30

    required_benchmarks = [
        "-64.7%",
        "57%–65%",
        "78%",
        "83.4%",
        "<100ms",
        "24MB",
        "-72.7%",
        "<=2 tokens",
        "107/107",
        "0.038ms",
    ]

    for req in required_benchmarks:
        assert req in claims, f"Mandatory claim figure '{req}' not found in lockfile"
        entry = claims[req]
        assert entry.get("verified") is True, f"Claim '{req}' is not marked verified"
        assert len(entry.get("source", "")) > 0, f"Claim '{req}' has no benchmark source"


def test_check_claims_passes_on_repo():
    code = check_claims(DEFAULT_WEB_DIR, DEFAULT_LOCKFILE, verbose=False)
    assert code == 0, "Site claims verification gate failed on repository"


def test_check_claims_fails_on_ungrounded_claims(tmp_path):
    # Valid lockfile
    lock_path = tmp_path / "test.lock"
    write_lockfile(lock_path)

    # Web dir with fake claims
    web_dir = tmp_path / "src"
    web_dir.mkdir(parents=True)

    fake_file = web_dir / "UnverifiedComponent.tsx"
    fake_file.write_text("""
    import React from 'react';
    export const Fake = () => (
      <div>
        <span>Quantum speedup of 99.9% with 0.0001ms latency and 9999MB memory</span>
      </div>
    );
    """)

    code = check_claims(web_dir, lock_path, verbose=False)
    assert code == 1, "Gate should have rejected ungrounded claims"


def test_write_mode_harvests_valid_lock(tmp_path):
    harvested = harvest_benchmark_sources()
    assert "-64.7%" in harvested
    assert "78%" in harvested
    assert "83.4%" in harvested
    assert "<100ms" in harvested
    assert "<=2 tokens" in harvested
    assert "107/107" in harvested
    assert "0.038ms" in harvested

    test_lock = tmp_path / "harvested.lock"
    ret = write_lockfile(test_lock)
    assert ret == 0
    assert test_lock.exists()

    loaded = load_lockfile(test_lock)
    assert len(loaded["claims"]) >= 30
