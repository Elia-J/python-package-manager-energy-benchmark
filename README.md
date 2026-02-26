# Python Package Manager Energy Benchmark

> Measure and compare the **energy consumption** of Python package managers ( **pip**, **uv**, and **poetry** ) during dependency installation and lock-file resolution.

python version 3.14.2
pip version 25.3

---

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Scripts Reference](#scripts-reference)
  - [run_once.sh](#run_oncesh)
  - [run_multiple.sh](#run_multiplesh)
  - [run_all.sh](#run_allsh)
  - [WSL Scripts (Windows)](#wsl-scripts-windows)
- [Benchmark Modes](#benchmark-modes)
- [Output Format](#output-format)
- [Supported Platforms](#supported-platforms)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project benchmarks the energy usage of three Python package managers by installing a realistic, heavy workload ([Apache Airflow with Celery](workload/requirements.in) — ~500 transitive dependencies) while sampling hardware telemetry (CPU frequency, temperature, usage, system power, memory) via [EnergiBridge](https://github.com/tdurieux/EnergiBridge).

The goal is to provide reproducible, quantitative data on how much energy each tool consumes across different scenarios (cold install, warm install, lock-file resolution).

---

## Repository Structure

```
.
├── bin/                          # Pre-built EnergiBridge binaries
│   ├── energibridge-darwin-arm64
│   ├── energibridge-darwin-x86_64
│   ├── energibridge-linux-x86_64
│   └── energibridge-windows-x86_64.exe
├── results/                      # Benchmark CSV output
├── scripts/
│   ├── run_once.sh               # Single benchmark run (macOS / Linux)
│   ├── run_multiple.sh           # Repeated benchmark runs (macOS / Linux)
│   ├── run_all.sh                # Full suite: all tools × all modes (macOS / Linux)
│   ├── run_once_wsl.ps1          # Single run via WSL (Windows PowerShell)
│   └── run_multiple_wsl.ps1      # Repeated runs via WSL (Windows PowerShell)
├── workload/
│   ├── pyproject.toml             # Project metadata + Poetry config
│   ├── requirements.in           # Top-level dependency (Apache Airflow)
│   └── requirements.txt          # Fully pinned lock file (pip-compile output)
└── README.md
```

---

## How It Works

1. **Prepare the environment** — depending on the mode, the script creates a fresh virtual environment and/or purges caches. For `warm`, it performs one unmeasured install first to pre-fill cache, then recreates `.venv` before the measured run. For `lock`, it performs one unmeasured lock run in a temporary workspace to warm metadata caches, then measures lock in a fresh temporary workspace.
2. **Wrap with EnergiBridge** — the package-manager command runs inside EnergiBridge, which samples hardware sensors at a configurable interval (default: 200 ms).
3. **Collect results** — a timestamped CSV is written to `results/` with columns for power, CPU metrics, memory, etc. A companion `.cmd.log` captures the command's stdout/stderr.
4. **Cool down** — the script waits (default: 60 s between repeated runs) to let the system return to baseline before the next run.

---

## Prerequisites

| Requirement       | Notes                                                                                   |
| ----------------- | --------------------------------------------------------------------------------------- |
| **Python 3.14.x** | With `venv` module support                                                              |
| **pip**           | Comes with Python; needed for `--tool pip`                                              |
| **uv**            | Install via `curl -LsSf https://astral.sh/uv/install.sh \| sh` — needed for `--tool uv` |
| **poetry**        | Install via `pipx install poetry` — needed for `--tool poetry`                          |
| **pip-tools**     | Install via `pip install pip-tools` — needed for `--tool pip --mode lock`               |
| **bash**          | Available by default on macOS and Linux                                                 |
| **WSL**           | Required on Windows (the PowerShell scripts delegate to WSL)                            |

> **macOS note**: EnergiBridge may require elevated permissions to read power counters. If you get permission errors, run with `sudo`.

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Elia-J/python-package-manager-energy-benchmark.git
cd python-package-manager-energy-benchmark

# Run a single warm pip benchmark
./scripts/run_once.sh --tool pip --mode warm

# Run 5 cold uv benchmarks
./scripts/run_multiple.sh --tool uv --mode cold --runs 5

# Run the full benchmark suite (all tools × all modes, 5 runs each)
./scripts/run_all.sh

# Results are saved in results/
ls results/
```

---

## Scripts Reference

### `run_once.sh`

Executes a **single** benchmark run.

```
Usage: ./scripts/run_once.sh --tool <tool> --mode <mode> [options]
```

| Flag         | Required | Default      | Description                                                                          |
| ------------ | -------- | ------------ | ------------------------------------------------------------------------------------ |
| `--tool`     | Yes      | —            | Package manager to benchmark: `pip`, `uv`, or `poetry`                               |
| `--mode`     | Yes      | —            | Benchmark mode: `cold`, `warm`, or `lock`                                            |
| `--python`   | No       | `python3.14` | Python binary to use (e.g. `python3.14`)                                             |
| `--workdir`  | No       | `workload`   | Directory containing `requirements.txt` / `requirements.in`                          |
| `--results`  | No       | `results`    | Directory for output CSVs                                                            |
| `--interval` | No       | `200`        | EnergiBridge `-i` interval argument (recommended starting point: `200` milliseconds) |
| `--cooldown` | No       | `0`          | Optional seconds to wait after the run completes                                     |

**Examples:**

```bash
# Warm pip install
./scripts/run_once.sh --tool pip --mode warm

# Cold uv install with Python 3.14 and explicit interval
./scripts/run_once.sh --tool uv --mode cold --python python3.14 --interval 200

# Poetry lock resolution
./scripts/run_once.sh --tool poetry --mode lock
```

You can also set the Python binary via environment variable:

```bash
PYTHON_BIN=python3.14 ./scripts/run_once.sh --tool pip --mode warm
```

---

### `run_multiple.sh`

Runs `run_once.sh` **multiple times** in sequence with a cooldown between each run.

```
Usage: ./scripts/run_multiple.sh --tool <tool> --mode <mode> [options]
```

| Flag         | Required | Default      | Description                                |
| ------------ | -------- | ------------ | ------------------------------------------ |
| `--tool`     | Yes      | —            | Package manager: `pip`, `uv`, or `poetry`  |
| `--mode`     | Yes      | —            | Benchmark mode: `cold`, `warm`, or `lock`  |
| `--runs`     | No       | `5`          | Number of repetitions                      |
| `--cooldown` | No       | `60`         | Seconds between runs                       |
| `--interval` | No       | unset        | Passed through to `run_once.sh --interval` |
| `--python`   | No       | `python3.14` | Passed through to `run_once.sh --python`   |

**Examples:**

```bash
# 10 warm pip runs with 15s cooldown
./scripts/run_multiple.sh --tool pip --mode warm --runs 10 --cooldown 15

# 10 warm pip runs with explicit interval
./scripts/run_multiple.sh --tool pip --mode warm --runs 10 --interval 200 --python python3.14

# 5 cold poetry installs (defaults)
./scripts/run_multiple.sh --tool poetry --mode cold
```

---

### `run_all.sh`

Runs `run_once.sh` for **every tool x mode combination** (9 combos by default: `pip`, `uv`, `poetry` x `cold`, `warm`, `lock`) with a **globally shuffled run order**. This avoids long contiguous blocks of the same tool/mode and improves experimental independence.

```
Usage: ./scripts/run_all.sh [options]
```

| Flag         | Required | Default          | Description                                |
| ------------ | -------- | ---------------- | ------------------------------------------ |
| `--tools`    | No       | `pip,uv,poetry`  | Comma-separated list of tools to benchmark |
| `--modes`    | No       | `cold,warm,lock` | Comma-separated list of modes to benchmark |
| `--runs`     | No       | `5`              | Number of repetitions per combination      |
| `--cooldown` | No       | `60`             | Seconds between runs                       |
| `--pause`    | No       | `0`              | Extra seconds when switching tool/mode     |
| `--interval` | No       | unset            | Passed through to `run_once.sh --interval` |
| `--seed`     | No       | unset            | Reproducible shuffle seed                  |
| `--python`   | No       | `python3.14`     | Passed through to `run_once.sh --python`   |

**Examples:**

```bash
# Run all 9 combinations with 5 runs each (defaults)
./scripts/run_all.sh

# 30 runs per combination with reproducible shuffling
./scripts/run_all.sh --runs 30 --seed 42 --python python3.14

# Only pip and uv, cold and warm modes
./scripts/run_all.sh --tools pip,uv --modes cold,warm

# Just poetry lock × 10 runs
./scripts/run_all.sh --tools poetry --modes lock --runs 10
```

---

### WSL Scripts (Windows)

For Windows users, PowerShell wrapper scripts delegate execution to WSL.

**`run_once_wsl.ps1`**

```powershell
.\scripts\run_once_wsl.ps1 -Tool pip -Mode warm -Interval 200 -Cooldown 0 -PythonBin python3.14
```

`run_once_wsl.ps1` parameters:

| Parameter    | Required | Default      | Description                         |
| ------------ | -------- | ------------ | ----------------------------------- |
| `-Tool`      | Yes      | -            | `pip`, `uv`, or `poetry`            |
| `-Mode`      | Yes      | -            | `cold`, `warm`, or `lock`           |
| `-Interval`  | No       | `200`        | EnergiBridge interval argument      |
| `-Cooldown`  | No       | `0`          | Optional post-run wait (seconds)    |
| `-PythonBin` | No       | `python3.14` | Python interpreter inside WSL       |

**`run_multiple_wsl.ps1`**

```powershell
.\scripts\run_multiple_wsl.ps1 -Tool uv -Mode cold -Runs 10 -Cooldown 10 -PythonBin python3.14
```

`run_multiple_wsl.ps1` parameters:

| Parameter    | Required | Default      | Description                      |
| ------------ | -------- | ------------ | -------------------------------- |
| `-Tool`      | Yes      | -            | `pip`, `uv`, or `poetry`         |
| `-Mode`      | Yes      | -            | `cold`, `warm`, or `lock`        |
| `-Runs`      | No       | `5`          | Number of repetitions            |
| `-Cooldown`  | No       | `60`         | Seconds between runs             |
| `-Interval`  | No       | `200`        | EnergiBridge interval argument   |
| `-PythonBin` | No       | `python3.14` | Python interpreter inside WSL    |

---

## Benchmark Modes

| Mode       | What happens                                                                                                                      | Measures                                                |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| **`cold`** | Purges package cache + deletes `.venv` → full download and install from scratch                                                   | Worst-case energy: network + resolve + build + install  |
| **`warm`** | Deletes `.venv`, runs one **unmeasured** install to pre-fill cache, deletes `.venv` again, then measures install from local cache | Install-only energy with stable warm-cache precondition |
| **`lock`** | Performs one **unmeasured** lock to warm resolver metadata caches, then measures lock-file generation in a fresh temporary workspace (`pip-compile`, `uv lock`, `poetry lock`) | Warm-cache dependency resolution energy                 |

---

## Output Format

Each run produces three files in `results/`:

1. **`<tool>_<mode>_<os>_<arch>_<timestamp>.csv`** — EnergiBridge telemetry samples with columns:

   | Column                     | Description                                |
   | -------------------------- | ------------------------------------------ |
   | `Delta`                    | Elapsed time since previous sample (milliseconds in this dataset) |
   | `Time`                     | Unix timestamp (milliseconds in this dataset) |
   | `CPU_FREQUENCY_0..N`       | Per-core CPU frequency (MHz)               |
   | `CPU_TEMP_0..N`            | Per-core CPU temperature (°C)              |
   | `CPU_USAGE_0..N`           | Per-core CPU usage (%)                     |
   | `SYSTEM_POWER (Watts)`     | System-wide power draw                     |
   | `TOTAL_MEMORY`             | Total system RAM (bytes)                   |
   | `USED_MEMORY`              | Used RAM (bytes)                           |
   | `TOTAL_SWAP` / `USED_SWAP` | Swap usage (bytes)                         |

2. **`<tool>_<mode>_<os>_<arch>_<timestamp>.cmd.log`** — stdout/stderr of the package-manager command.

3. **`<tool>_<mode>_<os>_<arch>_<timestamp>.meta.csv`** — per-run metadata (`wall_clock_s`, `exit_code`, and filenames) for analysis and validation.

When using `run_all.sh`, an additional schedule file is emitted:

4. **`schedule_<timestamp>.csv`** — shuffled run order (`run_index`, `tool`, `mode`) for reproducibility and audit trails.

---

## Supported Platforms

| Platform                    | Binary                            | Script                                      |
| --------------------------- | --------------------------------- | ------------------------------------------- |
| macOS Apple Silicon (arm64) | `energibridge-darwin-arm64`       | `run_once.sh` / `run_multiple.sh`           |
| macOS Intel (x86_64)        | `energibridge-darwin-x86_64`      | `run_once.sh` / `run_multiple.sh`           |
| Linux x86_64                | `energibridge-linux-x86_64`       | `run_once.sh` / `run_multiple.sh`           |
| Windows x86_64 (via WSL)    | `energibridge-linux-x86_64`       | `run_once_wsl.ps1` / `run_multiple_wsl.ps1` |

The scripts auto-detect your OS and architecture and select the correct binary. WSL runs use the Linux binary.

---

## Troubleshooting

| Problem                                                      | Solution                                                                                                           |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `ERROR: pip not found` / `uv not found` / `poetry not found` | Install the tool first and make sure it's on your `PATH`                                                           |
| `ERROR: pip-compile not found`                               | Install pip-tools: `pip install pip-tools` (needed for `--tool pip --mode lock`)                                   |
| `ERROR: No energibridge binary found`                        | Your platform may not have a pre-built binary in `bin/`. Build EnergiBridge from source.                           |
| WSL script fails on Windows                                  | Ensure WSL is installed (`wsl --install`) and a Linux distro is set up                                             |
| `execvpe(/bin/bash) failed` in Windows runs                  | Run from Git Bash (or PowerShell launching Git Bash); the scripts now force Git Bash for EnergiBridge subcommands. |
| Results look wrong or empty                                  | Check the `.cmd.log` file for errors from the package manager itself                                               |
