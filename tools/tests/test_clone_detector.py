import pytest
import subprocess
import sys
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from clone_detector import AslCloneDetector


def test_detect_exact_and_structural_clones(tmp_path):
    f1 = tmp_path / "mod1.asl"
    f1.write_text("""(module test/mod1
  :doc "Module 1"
  :export [compute-a compute-b])

(defun compute-a [(x Int64) (y Int64)] -> Int64
  :doc "First implementation"
  (let [(result (* (+ x y) 2))]
    (+ result 10)))

(defun compute-b [(a Int64) (b Int64)] -> Int64
  :doc "Second implementation with renamed local variables"
  (let [(res (* (+ a b) 2))]
    (+ res 10)))
""")

    detector = AslCloneDetector(min_node_count=6, max_duplication_threshold=0.10)
    report = detector.analyze_paths([f1])

    assert report.total_nodes > 0
    assert report.duplicate_nodes > 0
    assert len(report.clusters) >= 1

    top_cluster = report.clusters[0]
    assert top_cluster.occurrences == 2
    assert top_cluster.clone_type == "structural-clone"
    assert report.duplication_ratio > 0.10
    assert report.is_excessive is True


def test_clean_different_logic(tmp_path):
    f2 = tmp_path / "mod2.asl"
    f2.write_text("""(module test/mod2
  :doc "Clean distinct logic"
  :export [f g])

(defun f [(x Int64)] -> Int64
  :doc "Function f"
  (+ x 1))

(defun g [(s String)] -> String
  :doc "Function g"
  (s/upper s))
""")

    detector = AslCloneDetector(min_node_count=6, max_duplication_threshold=0.15)
    report = detector.analyze_paths([f2])
    assert len(report.clusters) == 0
    assert report.duplicate_nodes == 0
    assert report.duplication_ratio == 0.0
    assert report.is_excessive is False


def test_cli_clone_check_command():
    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "agentscript"),
            "clone-check",
            "packages/asl-skyloom/src/core/skyloom.asl",
            "packages/asl-lint/src/core/lint.asl",
            "--threshold",
            "0.25",
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert "totalNodes" in data
    assert "duplicationRatio" in data
    assert data["isExcessive"] is False
