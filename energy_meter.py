"""
Energy measurement utilities using Intel RAPL (Linux) with psutil fallback.

Intel RAPL (Running Average Power Limit) provides hardware energy counters
accessible through /sys/class/powercap/ on Linux. When RAPL is unavailable,
energy is estimated from CPU time and a configurable TDP (thermal design power).
"""

import os
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


RAPL_BASE = Path("/sys/class/powercap")
# Conservative default TDP in watts used for CPU-time-based estimation
DEFAULT_TDP_WATTS = 15.0


@dataclass
class EnergyReading:
    """A snapshot of energy state at a point in time."""

    timestamp: float
    rapl_joules: Optional[float]  # None when RAPL is unavailable
    cpu_time_seconds: Optional[float]  # None when psutil is unavailable


@dataclass
class EnergyMeasurement:
    """Energy and timing result for one measurement interval."""

    duration_seconds: float
    energy_joules: float
    source: str  # "rapl" | "cpu_time_estimate"
    notes: str = ""


def _rapl_packages() -> list[Path]:
    """Return the RAPL package directories that expose energy_uj files."""
    if not RAPL_BASE.exists():
        return []
    return sorted(
        p for p in RAPL_BASE.iterdir()
        if p.name.startswith("intel-rapl:") and ":" not in p.name[len("intel-rapl:"):]
        and (p / "energy_uj").exists()
    )


def _read_rapl_uj(packages: list[Path]) -> Optional[float]:
    """Sum energy_uj across all RAPL packages. Returns None on any error."""
    total = 0.0
    for pkg in packages:
        try:
            total += float((pkg / "energy_uj").read_text().strip())
        except (OSError, ValueError):
            return None
    return total


def _read_cpu_time() -> Optional[float]:
    """Return total CPU time (user + system, including children) in seconds."""
    try:
        import psutil  # optional dependency
        proc = psutil.Process()
        times = proc.cpu_times()
        total = times.user + times.system
        # Include time spent in child processes when available (Linux)
        if hasattr(times, "children_user"):
            total += times.children_user + times.children_system
        return total
    except Exception:
        return None


def take_reading() -> EnergyReading:
    """Capture current energy state (RAPL counters + CPU time)."""
    packages = _rapl_packages()
    rapl_uj = _read_rapl_uj(packages) if packages else None
    cpu_time = _read_cpu_time()
    return EnergyReading(
        timestamp=time.monotonic(),
        rapl_joules=rapl_uj / 1_000_000 if rapl_uj is not None else None,
        cpu_time_seconds=cpu_time,
    )


def compute_energy(start: EnergyReading, end: EnergyReading, tdp_watts: float = DEFAULT_TDP_WATTS) -> EnergyMeasurement:
    """
    Compute energy consumed between two readings.

    Prefers RAPL when available. Falls back to estimating energy as
    ``cpu_time_delta * tdp_watts`` when RAPL data is absent.

    Parameters
    ----------
    start, end:
        Readings taken before and after the measured activity.
    tdp_watts:
        Assumed thermal design power used for the CPU-time estimate.
    """
    duration = end.timestamp - start.timestamp

    if start.rapl_joules is not None and end.rapl_joules is not None:
        delta = end.rapl_joules - start.rapl_joules
        # Handle RAPL counter wrap-around (counter resets after max_energy_range_uj)
        if delta < 0:
            packages = _rapl_packages()
            try:
                max_uj = sum(
                    float((p / "max_energy_range_uj").read_text().strip())
                    for p in packages
                    if (p / "max_energy_range_uj").exists()
                )
                delta += max_uj / 1_000_000
            except (OSError, ValueError):
                delta = abs(delta)
        return EnergyMeasurement(
            duration_seconds=duration,
            energy_joules=delta,
            source="rapl",
        )

    if start.cpu_time_seconds is not None and end.cpu_time_seconds is not None:
        cpu_delta = end.cpu_time_seconds - start.cpu_time_seconds
        estimated = cpu_delta * tdp_watts
        return EnergyMeasurement(
            duration_seconds=duration,
            energy_joules=estimated,
            source="cpu_time_estimate",
            notes=f"Estimated using cpu_time={cpu_delta:.3f}s × tdp={tdp_watts}W",
        )

    # Last resort: elapsed time × TDP (very rough upper bound)
    return EnergyMeasurement(
        duration_seconds=duration,
        energy_joules=duration * tdp_watts,
        source="elapsed_time_estimate",
        notes=f"Estimated using elapsed={duration:.3f}s × tdp={tdp_watts}W (no CPU time available)",
    )
