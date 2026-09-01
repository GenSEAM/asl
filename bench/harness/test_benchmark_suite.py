"""
Unit tests for Autonomous Benchmark Suite
"""
from pathlib import Path
from bench.harness.benchmark_suite import AutonomousBenchmarkSuite, BenchmarkSummary

ROOT = Path(__file__).resolve().parent.parent.parent


def test_benchmark_suite_task_loading():
    suite = AutonomousBenchmarkSuite()
    tasks = suite.load_tasks()
    assert len(tasks) >= 2
    task_ids = [t.get("id", t.get("name")) for t in tasks]
    assert "histogram" in task_ids or "io_demo" in task_ids


def test_benchmark_suite_dry_run():
    suite = AutonomousBenchmarkSuite()
    results, summary = suite.run_dry_benchmark()
    assert isinstance(summary, BenchmarkSummary)
    assert summary.total_tasks > 0
    assert summary.passed_tasks == summary.total_tasks
    assert summary.pass_rate_pct == 100.0
    assert summary.avg_compression_pct >= 70.0
    assert len(summary.targets_evaluated) == 6
    assert all(r.passed for r in results)
