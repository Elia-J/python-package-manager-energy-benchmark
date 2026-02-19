#!/usr/bin/env python3
"""
Benchmark energy consumption of Python package managers.

Usage
-----
    python benchmark.py [options]

Run ``python benchmark.py --help`` for a full option listing.

Each benchmark trial:
  1. Creates an isolated temporary virtual-environment / project.
  2. Installs the requested packages inside it.
  3. Measures wall-clock time and energy (RAPL or CPU-time estimate).
  4. Cleans up the environment.
  5. Appends one row to the results CSV.
"""

import argparse
import csv
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from energy_meter import compute_energy, take_reading

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Default configuration
# ---------------------------------------------------------------------------

DEFAULT_PACKAGES = ["requests", "numpy", "flask"]
DEFAULT_REPETITIONS = 3
DEFAULT_OUTPUT = "results/results.csv"

CSV_FIELDS = [
    "manager",
    "operation",
    "packages",
    "run",
    "duration_seconds",
    "energy_joules",
    "energy_source",
    "notes",
]


# ---------------------------------------------------------------------------
# Data containers
# ---------------------------------------------------------------------------


@dataclass
class BenchmarkResult:
    manager: str
    operation: str
    packages: list[str]
    run: int
    duration_seconds: float
    energy_joules: float
    energy_source: str
    notes: str = ""

    def as_row(self) -> dict:
        return {
            "manager": self.manager,
            "operation": self.operation,
            "packages": " ".join(self.packages),
            "run": self.run,
            "duration_seconds": round(self.duration_seconds, 4),
            "energy_joules": round(self.energy_joules, 4),
            "energy_source": self.energy_source,
            "notes": self.notes,
        }


# ---------------------------------------------------------------------------
# Package manager runners
# ---------------------------------------------------------------------------


def _run(cmd: list[str], cwd: Optional[Path] = None, timeout: int = 300) -> subprocess.CompletedProcess:
    """Run a command, raising RuntimeError on non-zero exit."""
    logger.debug("Running: %s", " ".join(cmd))
    result = subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(cmd)}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result


def _find_executable(name: str) -> Optional[str]:
    """Return the full path to *name* if it exists on PATH, else None."""
    return shutil.which(name)


class PipRunner:
    """Benchmark pip install inside a fresh virtualenv."""

    name = "pip"

    def is_available(self) -> bool:
        return _find_executable("pip") is not None or _find_executable("pip3") is not None

    def run_install(self, packages: list[str], tmp_dir: Path) -> None:
        venv_dir = tmp_dir / "venv"
        _run([sys.executable, "-m", "venv", str(venv_dir)])
        pip_bin = venv_dir / "bin" / "pip"
        _run([str(pip_bin), "install", "--no-cache-dir"] + packages)


class UvRunner:
    """Benchmark uv pip install inside a fresh virtual environment."""

    name = "uv"

    def is_available(self) -> bool:
        return _find_executable("uv") is not None

    def run_install(self, packages: list[str], tmp_dir: Path) -> None:
        venv_dir = tmp_dir / "venv"
        _run(["uv", "venv", str(venv_dir)])
        _run(["uv", "pip", "install", "--no-cache", "-p", str(venv_dir / "bin" / "python")] + packages)


class PoetryRunner:
    """Benchmark poetry add inside a fresh Poetry project."""

    name = "poetry"

    def is_available(self) -> bool:
        return _find_executable("poetry") is not None

    def run_install(self, packages: list[str], tmp_dir: Path) -> None:
        project_dir = tmp_dir / "project"
        project_dir.mkdir()
        # Initialise a minimal pyproject.toml so poetry add works
        (project_dir / "pyproject.toml").write_text(
            "[tool.poetry]\n"
            'name = "benchmark-project"\n'
            'version = "0.1.0"\n'
            'description = ""\n'
            'authors = []\n'
            "\n"
            "[tool.poetry.dependencies]\n"
            'python = "^3.10"\n'
            "\n"
            "[build-system]\n"
            'requires = ["poetry-core"]\n'
            'build-backend = "poetry.core.masonry.api"\n'
        )
        _run(
            ["poetry", "add", "--no-interaction"] + packages,
            cwd=project_dir,
        )


RUNNERS = [PipRunner(), UvRunner(), PoetryRunner()]


# ---------------------------------------------------------------------------
# Core benchmark logic
# ---------------------------------------------------------------------------


def benchmark_manager(
    runner,
    packages: list[str],
    run_index: int,
    tdp_watts: float,
) -> BenchmarkResult:
    """
    Run one install trial for *runner* and return the measured result.

    A fresh temporary directory is created before the trial and removed
    afterward so that successive runs start from the same state.
    """
    with tempfile.TemporaryDirectory(prefix="pkgbench_") as tmp:
        tmp_path = Path(tmp)

        start = take_reading()
        try:
            runner.run_install(packages, tmp_path)
        except RuntimeError as exc:
            logger.warning("Install failed for %s (run %d): %s", runner.name, run_index, exc)
            raise
        end = take_reading()

    measurement = compute_energy(start, end, tdp_watts=tdp_watts)

    return BenchmarkResult(
        manager=runner.name,
        operation="install",
        packages=packages,
        run=run_index,
        duration_seconds=measurement.duration_seconds,
        energy_joules=measurement.energy_joules,
        energy_source=measurement.source,
        notes=measurement.notes,
    )


# ---------------------------------------------------------------------------
# CSV I/O
# ---------------------------------------------------------------------------


def append_result(result: BenchmarkResult, output_path: Path) -> None:
    """Append one result row to *output_path*, creating the file if needed."""
    write_header = not output_path.exists()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "a", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
        if write_header:
            writer.writeheader()
        writer.writerow(result.as_row())


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--packages",
        nargs="+",
        default=DEFAULT_PACKAGES,
        metavar="PKG",
        help=f"Packages to install in each trial (default: {DEFAULT_PACKAGES})",
    )
    parser.add_argument(
        "--repetitions",
        type=int,
        default=DEFAULT_REPETITIONS,
        metavar="N",
        help=f"Number of repeated trials per manager (default: {DEFAULT_REPETITIONS})",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        metavar="FILE",
        help=f"CSV file to append results to (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--managers",
        nargs="+",
        choices=["pip", "uv", "poetry"],
        default=None,
        metavar="MGR",
        help="Limit benchmark to specific managers (default: all available)",
    )
    parser.add_argument(
        "--tdp-watts",
        type=float,
        default=15.0,
        metavar="W",
        help="Assumed CPU TDP in watts for energy estimation fallback (default: 15.0)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    output_path = Path(args.output)
    selected_names = set(args.managers) if args.managers else None

    runners = [
        r for r in RUNNERS
        if (selected_names is None or r.name in selected_names)
        and r.is_available()
    ]

    if not runners:
        logger.error(
            "No package managers available. Install pip, uv, or poetry and try again."
        )
        return 1

    unavailable = [
        r.name for r in RUNNERS
        if (selected_names is None or r.name in selected_names)
        and not r.is_available()
    ]
    if unavailable:
        logger.warning("Skipping unavailable managers: %s", ", ".join(unavailable))

    logger.info(
        "Benchmarking %s × %d repetitions × packages: %s",
        [r.name for r in runners],
        args.repetitions,
        args.packages,
    )

    total = len(runners) * args.repetitions
    completed = 0

    for runner in runners:
        for run_idx in range(1, args.repetitions + 1):
            logger.info(
                "[%d/%d] %s install run %d/%d …",
                completed + 1, total, runner.name, run_idx, args.repetitions,
            )
            try:
                result = benchmark_manager(
                    runner,
                    args.packages,
                    run_idx,
                    tdp_watts=args.tdp_watts,
                )
                append_result(result, output_path)
                logger.info(
                    "  → %.2f s, %.4f J (%s)",
                    result.duration_seconds,
                    result.energy_joules,
                    result.energy_source,
                )
            except Exception as exc:
                logger.error("  → FAILED: %s", exc)
            completed += 1

    logger.info("Results written to %s", output_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
