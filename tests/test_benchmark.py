"""Tests for benchmark.py"""

import csv
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

import benchmark as bm
from benchmark import (
    BenchmarkResult,
    PipRunner,
    PoetryRunner,
    UvRunner,
    append_result,
    benchmark_manager,
    parse_args,
)


# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------


def test_parse_args_defaults():
    args = parse_args([])
    assert args.packages == bm.DEFAULT_PACKAGES
    assert args.repetitions == bm.DEFAULT_REPETITIONS
    assert args.output == bm.DEFAULT_OUTPUT
    assert args.managers is None
    assert args.tdp_watts == 15.0
    assert args.verbose is False


def test_parse_args_custom_packages():
    args = parse_args(["--packages", "django", "celery"])
    assert args.packages == ["django", "celery"]


def test_parse_args_custom_repetitions():
    args = parse_args(["--repetitions", "5"])
    assert args.repetitions == 5


def test_parse_args_managers():
    args = parse_args(["--managers", "pip", "uv"])
    assert args.managers == ["pip", "uv"]


# ---------------------------------------------------------------------------
# BenchmarkResult
# ---------------------------------------------------------------------------


def test_benchmark_result_as_row():
    result = BenchmarkResult(
        manager="pip",
        operation="install",
        packages=["requests", "numpy"],
        run=1,
        duration_seconds=3.5,
        energy_joules=52.5,
        energy_source="rapl",
        notes="",
    )
    row = result.as_row()
    assert row["manager"] == "pip"
    assert row["packages"] == "requests numpy"
    assert row["duration_seconds"] == pytest.approx(3.5)
    assert row["energy_joules"] == pytest.approx(52.5)


# ---------------------------------------------------------------------------
# append_result
# ---------------------------------------------------------------------------


def test_append_result_creates_file(tmp_path):
    out = tmp_path / "results.csv"
    result = BenchmarkResult("pip", "install", ["requests"], 1, 2.0, 30.0, "rapl")
    append_result(result, out)
    assert out.exists()
    rows = list(csv.DictReader(out.open()))
    assert len(rows) == 1
    assert rows[0]["manager"] == "pip"


def test_append_result_appends_rows(tmp_path):
    out = tmp_path / "results.csv"
    for i in range(3):
        r = BenchmarkResult("pip", "install", ["requests"], i + 1, float(i), float(i * 10), "rapl")
        append_result(r, out)
    rows = list(csv.DictReader(out.open()))
    assert len(rows) == 3


def test_append_result_creates_parent_dirs(tmp_path):
    out = tmp_path / "nested" / "dir" / "results.csv"
    r = BenchmarkResult("uv", "install", ["flask"], 1, 1.0, 10.0, "cpu_time_estimate")
    append_result(r, out)
    assert out.exists()


# ---------------------------------------------------------------------------
# Runner availability
# ---------------------------------------------------------------------------


def test_pip_runner_available_when_pip_on_path():
    runner = PipRunner()
    with patch("benchmark._find_executable", return_value="/usr/bin/pip"):
        assert runner.is_available() is True


def test_uv_runner_unavailable_when_not_on_path():
    runner = UvRunner()
    with patch("benchmark._find_executable", return_value=None):
        assert runner.is_available() is False


def test_poetry_runner_unavailable_when_not_on_path():
    runner = PoetryRunner()
    with patch("benchmark._find_executable", return_value=None):
        assert runner.is_available() is False


# ---------------------------------------------------------------------------
# benchmark_manager
# ---------------------------------------------------------------------------


def test_benchmark_manager_returns_result():
    mock_runner = MagicMock()
    mock_runner.name = "mock"
    mock_runner.run_install = MagicMock()

    result = benchmark_manager(mock_runner, ["requests"], run_index=1, tdp_watts=15.0)

    assert result.manager == "mock"
    assert result.operation == "install"
    assert result.packages == ["requests"]
    assert result.run == 1
    assert result.duration_seconds >= 0
    assert result.energy_joules >= 0


def test_benchmark_manager_propagates_error():
    mock_runner = MagicMock()
    mock_runner.name = "failing"
    mock_runner.run_install = MagicMock(side_effect=RuntimeError("install failed"))

    with pytest.raises(RuntimeError, match="install failed"):
        benchmark_manager(mock_runner, ["pkg"], run_index=1, tdp_watts=15.0)


# ---------------------------------------------------------------------------
# main()
# ---------------------------------------------------------------------------


def test_main_no_managers_available(tmp_path):
    out = tmp_path / "out.csv"
    with patch("benchmark.RUNNERS", []):
        rc = bm.main(["--output", str(out)])
    assert rc == 1


def test_main_runs_available_manager(tmp_path):
    out = tmp_path / "results.csv"

    mock_runner = MagicMock()
    mock_runner.name = "mock"
    mock_runner.is_available.return_value = True
    mock_runner.run_install = MagicMock()

    with patch("benchmark.RUNNERS", [mock_runner]):
        rc = bm.main(["--output", str(out), "--repetitions", "2", "--packages", "requests"])

    assert rc == 0
    assert out.exists()
    rows = list(csv.DictReader(out.open()))
    assert len(rows) == 2
