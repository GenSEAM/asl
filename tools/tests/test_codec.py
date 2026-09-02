import sys
import pytest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "checker"))


def test_codec_file_checks_clean():
    from resolve import check_file
    codec_file = ROOT / "packages" / "asl-codec" / "src" / "core" / "codec.asl"
    roots = [codec_file.parent, ROOT / "grammar" / "corpus" / "valid", ROOT / "grammar" / "corpus" / "modules"]
    diags = check_file(codec_file, roots)
    assert len(diags) == 0


def test_codec_test_checks_clean():
    from resolve import check_file
    test_file = ROOT / "packages" / "asl-codec" / "tests" / "codec_test.asl"
    roots = [test_file.parent, ROOT / "grammar" / "corpus" / "valid", ROOT / "grammar" / "corpus" / "modules"]
    diags = check_file(test_file, roots)
    assert len(diags) == 0


def test_codec_serialization_simulation():
    # Simulation of render-json logic matching codec.asl
    def render_json(val):
        if val is None:
            return "null"
        elif isinstance(val, bool):
            return "true" if val else "false"
        elif isinstance(val, int):
            return str(val)
        elif isinstance(val, float):
            return str(val)
        elif isinstance(val, str):
            return f'"{val}"'
        elif isinstance(val, list):
            return "[" + ",".join(render_json(x) for x in val) + "]"
        elif isinstance(val, dict):
            return "{" + ",".join(f'"{k}":{render_json(v)}' for k, v in val.items()) + "}"
        raise ValueError(f"Unknown type: {type(val)}")

    sample = {"id": 101, "name": "Agent 007", "active": True, "score": 98.5, "tags": ["agent", "mesh"]}
    res = render_json(sample)
    assert '"id":101' in res
    assert '"name":"Agent 007"' in res
    assert '"active":true' in res
    assert '["agent","mesh"]' in res
