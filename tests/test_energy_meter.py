"""Tests for energy_meter.py"""

import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from energy_meter import (
    EnergyMeasurement,
    EnergyReading,
    _rapl_packages,
    _read_cpu_time,
    _read_rapl_uj,
    compute_energy,
    take_reading,
)


# ---------------------------------------------------------------------------
# _rapl_packages
# ---------------------------------------------------------------------------


def test_rapl_packages_missing_dir(tmp_path):
    """Returns empty list when RAPL base directory does not exist."""
    with patch("energy_meter.RAPL_BASE", tmp_path / "nonexistent"):
        result = _rapl_packages()
    assert result == []


def test_rapl_packages_finds_packages(tmp_path):
    """Detects intel-rapl package directories that contain energy_uj."""
    pkg = tmp_path / "intel-rapl:0"
    pkg.mkdir()
    (pkg / "energy_uj").write_text("1000000")

    with patch("energy_meter.RAPL_BASE", tmp_path):
        result = _rapl_packages()

    assert len(result) == 1
    assert result[0] == pkg


def test_rapl_packages_ignores_subdomains(tmp_path):
    """Sub-domain paths (intel-rapl:0:0) are excluded from the top-level list."""
    pkg = tmp_path / "intel-rapl:0"
    pkg.mkdir()
    (pkg / "energy_uj").write_text("500")
    sub = tmp_path / "intel-rapl:0:0"
    sub.mkdir()
    (sub / "energy_uj").write_text("200")

    with patch("energy_meter.RAPL_BASE", tmp_path):
        result = _rapl_packages()

    assert result == [pkg]


def test_rapl_packages_no_energy_file(tmp_path):
    """Directories without energy_uj are excluded."""
    pkg = tmp_path / "intel-rapl:0"
    pkg.mkdir()  # no energy_uj file

    with patch("energy_meter.RAPL_BASE", tmp_path):
        result = _rapl_packages()

    assert result == []


# ---------------------------------------------------------------------------
# _read_rapl_uj
# ---------------------------------------------------------------------------


def test_read_rapl_uj_sums_packages(tmp_path):
    pkg0 = tmp_path / "intel-rapl:0"
    pkg0.mkdir()
    (pkg0 / "energy_uj").write_text("1000000")
    pkg1 = tmp_path / "intel-rapl:1"
    pkg1.mkdir()
    (pkg1 / "energy_uj").write_text("2000000")

    result = _read_rapl_uj([pkg0, pkg1])
    assert result == pytest.approx(3_000_000)


def test_read_rapl_uj_empty_list():
    assert _read_rapl_uj([]) == pytest.approx(0.0)


def test_read_rapl_uj_missing_file(tmp_path):
    pkg = tmp_path / "intel-rapl:0"
    pkg.mkdir()
    # No energy_uj file
    assert _read_rapl_uj([pkg]) is None


# ---------------------------------------------------------------------------
# _read_cpu_time
# ---------------------------------------------------------------------------


def test_read_cpu_time_returns_float():
    result = _read_cpu_time()
    # psutil is installed, so we expect a non-negative float
    assert result is None or isinstance(result, float)
    if result is not None:
        assert result >= 0.0


# ---------------------------------------------------------------------------
# take_reading
# ---------------------------------------------------------------------------


def test_take_reading_returns_energy_reading():
    reading = take_reading()
    assert isinstance(reading, EnergyReading)
    assert reading.timestamp > 0
    # rapl_joules may be None in the test environment
    assert reading.rapl_joules is None or reading.rapl_joules >= 0.0


def test_take_reading_timestamp_increases():
    r1 = take_reading()
    time.sleep(0.01)
    r2 = take_reading()
    assert r2.timestamp > r1.timestamp


# ---------------------------------------------------------------------------
# compute_energy
# ---------------------------------------------------------------------------


def _make_reading(ts, rapl_j, cpu_t):
    return EnergyReading(timestamp=ts, rapl_joules=rapl_j, cpu_time_seconds=cpu_t)


def test_compute_energy_uses_rapl_when_available():
    start = _make_reading(0.0, 100.0, 1.0)
    end = _make_reading(5.0, 200.0, 3.0)
    m = compute_energy(start, end, tdp_watts=15.0)
    assert m.source == "rapl"
    assert m.energy_joules == pytest.approx(100.0)
    assert m.duration_seconds == pytest.approx(5.0)


def test_compute_energy_falls_back_to_cpu_time():
    start = _make_reading(0.0, None, 1.0)
    end = _make_reading(5.0, None, 3.0)
    m = compute_energy(start, end, tdp_watts=10.0)
    assert m.source == "cpu_time_estimate"
    # cpu_time_delta=2s × tdp=10W = 20J
    assert m.energy_joules == pytest.approx(20.0)


def test_compute_energy_falls_back_to_elapsed_time():
    start = _make_reading(0.0, None, None)
    end = _make_reading(4.0, None, None)
    m = compute_energy(start, end, tdp_watts=15.0)
    assert m.source == "elapsed_time_estimate"
    assert m.energy_joules == pytest.approx(60.0)


def test_compute_energy_rapl_wrap_around(tmp_path):
    """RAPL counter wrap-around produces a positive delta."""
    pkg = tmp_path / "intel-rapl:0"
    pkg.mkdir()
    (pkg / "energy_uj").write_text("100000")
    (pkg / "max_energy_range_uj").write_text("262143328850")

    start = _make_reading(0.0, 262143.0, None)
    end = _make_reading(5.0, 10.0, None)

    with patch("energy_meter._rapl_packages", return_value=[pkg]):
        m = compute_energy(start, end, tdp_watts=15.0)

    assert m.source == "rapl"
    assert m.energy_joules > 0


def test_compute_energy_duration():
    start = _make_reading(10.0, 0.0, 0.0)
    end = _make_reading(12.5, 50.0, 1.5)
    m = compute_energy(start, end)
    assert m.duration_seconds == pytest.approx(2.5)
