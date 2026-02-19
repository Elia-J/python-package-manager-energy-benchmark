# Python Package Manager Energy Benchmark

Benchmark and compare the energy consumption of Python package managers
(**pip**, **uv**, **poetry**) for sustainable software engineering research.

---

## Overview

Each benchmark trial:

1. Creates an isolated temporary environment (virtualenv or Poetry project).
2. Installs a configurable set of packages using the chosen manager.
3. Measures **wall-clock time** and **energy consumption** (Intel RAPL when
   available; CPU-time × TDP estimation otherwise).
4. Appends one row to a CSV results file.

After collecting data you can run the analysis script to print a summary
table and (optionally) generate bar charts.

---

## Requirements

- Python 3.10+
- One or more of: **pip** (built-in), **uv**, **poetry**
- Optional: Intel RAPL support (`/sys/class/powercap/intel-rapl*`) for
  hardware-level energy readings

Install Python dependencies:

```bash
pip install -r requirements.txt
```

---

## Usage

### 1. Run the benchmark

```bash
python benchmark.py
```

Common options:

| Option | Default | Description |
|---|---|---|
| `--packages PKG …` | `requests numpy flask` | Packages to install per trial |
| `--repetitions N` | `3` | Number of repeated trials per manager |
| `--output FILE` | `results/results.csv` | CSV file to append results to |
| `--managers MGR …` | all available | Limit to `pip`, `uv`, and/or `poetry` |
| `--tdp-watts W` | `15.0` | Assumed CPU TDP (W) for energy estimation |
| `--verbose` | off | Enable debug logging |

Example – benchmark only pip and uv, 5 repetitions, verbose output:

```bash
python benchmark.py --managers pip uv --repetitions 5 --verbose
```

### 2. Analyse results

```bash
python analyze.py
```

Options:

| Option | Default | Description |
|---|---|---|
| `--input FILE` | `results/results.csv` | Results CSV produced by benchmark.py |
| `--plots DIR` | (none) | Save comparison charts to this directory |

Example with plots (requires `matplotlib`):

```bash
python analyze.py --plots plots/
```

---

## Energy measurement

| Source | When used |
|---|---|
| **Intel RAPL** (`/sys/class/powercap/`) | Linux systems with RAPL support |
| **CPU-time estimate** | RAPL unavailable; `psutil` reports CPU times |
| **Elapsed-time estimate** | Neither RAPL nor psutil available |

The `energy_source` column in the CSV records which method was used for each
trial so you can filter or weight results accordingly in your analysis.

---

## Project structure

```
.
├── benchmark.py        # Main benchmark script
├── energy_meter.py     # Energy measurement (RAPL + fallbacks)
├── analyze.py          # Results analysis and visualisation
├── requirements.txt    # Python dependencies
└── tests/
    ├── test_benchmark.py
    ├── test_energy_meter.py
    └── test_analyze.py
```

---

## Running tests

```bash
pip install pytest
python -m pytest tests/ -v
```
