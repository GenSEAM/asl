"""Unit tests for ASL Architecture Topology & Graph Inspector."""

import pytest
from pathlib import Path
from tools.module_graph import build_module_graph, extract_module_info, ROOT


def test_extract_sql_module_info():
    sql_file = ROOT / "packages" / "asl-sql" / "src" / "core" / "sql.asl"
    info = extract_module_info(sql_file)
    assert info["module"] == "asl-sql/core"
    assert "SqlDialect" in info["enums"]
    assert "SelectQuery" in info["schemas"]
    assert "render-select" in info["exports"]
    assert "SQL/Database" in info["tags"]
    assert info["quality_score"] == 100


def test_build_packages_graph():
    packages_dir = ROOT / "packages"
    graph = build_module_graph([packages_dir])
    assert graph["modules_count"] >= 20
    assert "asl-sql/core" in graph["modules"]
    assert "asl-lint/core" in graph["modules"]
    assert "asl-skyloom/core" in graph["modules"]
