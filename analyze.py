#!/usr/bin/env python3
"""
Analyze benchmark results and generate comparison charts.

Usage
-----
    python analyze.py [options]

Reads the CSV produced by benchmark.py and prints a summary table plus
(optionally) saves comparison plots to a directory.
"""

import argparse
import sys
from pathlib import Path


def load_results(csv_path: Path):
    """Load results CSV. Returns a list of dicts."""
    import csv

    with open(csv_path, newline="") as fh:
        return list(csv.DictReader(fh))


def summarize(rows: list[dict]) -> dict:
    """
    Compute mean ± std for duration and energy per (manager, operation).

    Returns a dict keyed by (manager, operation) with summary stats.
    """
    from collections import defaultdict
    import math

    groups: dict[tuple, list] = defaultdict(list)
    for row in rows:
        key = (row["manager"], row["operation"])
        groups[key].append(
            {
                "duration": float(row["duration_seconds"]),
                "energy": float(row["energy_joules"]),
                "source": row["energy_source"],
            }
        )

    summary = {}
    for key, entries in groups.items():
        durations = [e["duration"] for e in entries]
        energies = [e["energy"] for e in entries]
        sources = list({e["source"] for e in entries})

        def _mean(xs):
            return sum(xs) / len(xs)

        def _std(xs):
            if len(xs) < 2:
                return 0.0
            m = _mean(xs)
            return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))

        summary[key] = {
            "n": len(entries),
            "duration_mean": _mean(durations),
            "duration_std": _std(durations),
            "energy_mean": _mean(energies),
            "energy_std": _std(energies),
            "sources": sources,
        }
    return summary


def print_table(summary: dict) -> None:
    """Print a formatted summary table to stdout."""
    header = f"{'Manager':<12} {'Operation':<12} {'N':>3}  {'Duration (s)':>14}  {'Energy (J)':>14}  {'Source'}"
    print(header)
    print("-" * len(header))
    for (manager, operation), stats in sorted(summary.items()):
        dur = f"{stats['duration_mean']:.2f} ± {stats['duration_std']:.2f}"
        eng = f"{stats['energy_mean']:.4f} ± {stats['energy_std']:.4f}"
        sources = ", ".join(stats["sources"])
        print(f"{manager:<12} {operation:<12} {stats['n']:>3}  {dur:>14}  {eng:>14}  {sources}")


def plot_results(summary: dict, output_dir: Path) -> None:
    """Save bar charts comparing managers for duration and energy."""
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib not installed – skipping plots. Run: pip install matplotlib", file=sys.stderr)
        return

    output_dir.mkdir(parents=True, exist_ok=True)

    operations = sorted({op for (_, op) in summary})
    for operation in operations:
        subset = {mgr: stats for (mgr, op), stats in summary.items() if op == operation}
        if not subset:
            continue

        managers = sorted(subset)

        for mean_key, std_key, output_metric in [
            ("duration_mean", "duration_std", "duration_seconds"),
            ("energy_mean", "energy_std", "energy_joules"),
        ]:
            values = [subset[m][mean_key] for m in managers]
            errors = [subset[m][std_key] for m in managers]

            fig, ax = plt.subplots()
            bars = ax.bar(managers, values, yerr=errors, capsize=5, color=["#4c72b0", "#dd8452", "#55a868"])
            ax.set_xlabel("Package Manager")
            y_label = "Duration (s)" if output_metric == "duration_seconds" else "Energy (J)"
            ax.set_ylabel(y_label)
            ax.set_title(f"{operation.capitalize()} – {y_label}")
            ax.bar_label(bars, fmt="%.2f", padding=3)
            fig.tight_layout()

            out_file = output_dir / f"{operation}_{output_metric}.png"
            fig.savefig(out_file, dpi=150)
            plt.close(fig)
            print(f"Saved: {out_file}")


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--input",
        default="results/results.csv",
        metavar="FILE",
        help="CSV results file produced by benchmark.py (default: results/results.csv)",
    )
    parser.add_argument(
        "--plots",
        metavar="DIR",
        default=None,
        help="Save comparison plots to this directory (requires matplotlib)",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    csv_path = Path(args.input)

    if not csv_path.exists():
        print(f"Error: results file not found: {csv_path}", file=sys.stderr)
        print("Run benchmark.py first to generate results.", file=sys.stderr)
        return 1

    rows = load_results(csv_path)
    if not rows:
        print("Error: results file is empty.", file=sys.stderr)
        return 1

    summary = summarize(rows)
    print_table(summary)

    if args.plots:
        plot_results(summary, Path(args.plots))

    return 0


if __name__ == "__main__":
    sys.exit(main())
