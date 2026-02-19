"""Tests for analyze.py"""

import csv
import io
import math
from pathlib import Path
from unittest.mock import patch

import pytest

from analyze import load_results, summarize, print_table, main


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def write_csv(tmp_path: Path, rows: list[dict]) -> Path:
    p = tmp_path / "results.csv"
    with p.open("w", newline="") as fh:
        if rows:
            writer = csv.DictWriter(fh, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)
    return p


SAMPLE_ROWS = [
    {
        "manager": "pip",
        "operation": "install",
        "packages": "requests numpy",
        "run": "1",
        "duration_seconds": "3.0",
        "energy_joules": "45.0",
        "energy_source": "rapl",
        "notes": "",
    },
    {
        "manager": "pip",
        "operation": "install",
        "packages": "requests numpy",
        "run": "2",
        "duration_seconds": "3.5",
        "energy_joules": "50.0",
        "energy_source": "rapl",
        "notes": "",
    },
    {
        "manager": "uv",
        "operation": "install",
        "packages": "requests numpy",
        "run": "1",
        "duration_seconds": "1.0",
        "energy_joules": "15.0",
        "energy_source": "rapl",
        "notes": "",
    },
]


# ---------------------------------------------------------------------------
# load_results
# ---------------------------------------------------------------------------


def test_load_results_returns_rows(tmp_path):
    p = write_csv(tmp_path, SAMPLE_ROWS)
    rows = load_results(p)
    assert len(rows) == 3
    assert rows[0]["manager"] == "pip"


# ---------------------------------------------------------------------------
# summarize
# ---------------------------------------------------------------------------


def test_summarize_groups_correctly():
    summary = summarize(SAMPLE_ROWS)
    assert ("pip", "install") in summary
    assert ("uv", "install") in summary
    assert summary[("pip", "install")]["n"] == 2
    assert summary[("uv", "install")]["n"] == 1


def test_summarize_computes_mean():
    summary = summarize(SAMPLE_ROWS)
    pip_stats = summary[("pip", "install")]
    assert pip_stats["duration_mean"] == pytest.approx(3.25)
    assert pip_stats["energy_mean"] == pytest.approx(47.5)


def test_summarize_computes_std():
    summary = summarize(SAMPLE_ROWS)
    pip_stats = summary[("pip", "install")]
    # std of [3.0, 3.5] = 0.5 / sqrt(1) using sample std
    expected_std = math.sqrt(((3.0 - 3.25) ** 2 + (3.5 - 3.25) ** 2) / (2 - 1))
    assert pip_stats["duration_std"] == pytest.approx(expected_std)


def test_summarize_single_entry_std_is_zero():
    summary = summarize(SAMPLE_ROWS)
    uv_stats = summary[("uv", "install")]
    assert uv_stats["duration_std"] == pytest.approx(0.0)


# ---------------------------------------------------------------------------
# print_table
# ---------------------------------------------------------------------------


def test_print_table_outputs_all_managers(capsys):
    summary = summarize(SAMPLE_ROWS)
    print_table(summary)
    captured = capsys.readouterr()
    assert "pip" in captured.out
    assert "uv" in captured.out
    assert "install" in captured.out


# ---------------------------------------------------------------------------
# main()
# ---------------------------------------------------------------------------


def test_main_missing_file(tmp_path):
    rc = main(["--input", str(tmp_path / "nonexistent.csv")])
    assert rc == 1


def test_main_success(tmp_path):
    p = write_csv(tmp_path, SAMPLE_ROWS)
    rc = main(["--input", str(p)])
    assert rc == 0


def test_main_empty_file(tmp_path):
    p = tmp_path / "empty.csv"
    p.write_text("")
    rc = main(["--input", str(p)])
    assert rc == 1
