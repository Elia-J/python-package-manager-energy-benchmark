#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────
# Run benchmarks for every tool × mode combination
# ────────────────────────────────────────────────────────────

TOOLS="pip uv poetry"
MODES="cold warm lock"
RUNS=5
COOLDOWN=5
PAUSE=10     # seconds between tool×mode combos

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --tools    <t1,t2,...>   Comma-separated tools to benchmark (default: pip,uv,poetry)
  --modes    <m1,m2,...>   Comma-separated modes to benchmark (default: cold,warm,lock)
  --runs     <N>           Number of repetitions per combination (default: 5)
  --cooldown <S>           Seconds between runs within a combination (default: 5)
  --pause    <S>           Seconds between tool x mode combinations (default: 10)
  --help                   Show this help message

Examples:
  $0                                        # all 9 combos, 5 runs each
  $0 --runs 30                              # all 9 combos, 30 runs each
  $0 --tools pip,uv --modes cold,warm       # 4 combos only
  $0 --tools poetry --modes lock --runs 10  # poetry lock x 10
EOF
  exit 0
}

# ────── Parse arguments ──────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools)    TOOLS="${2//,/ }"; shift 2 ;;
    --modes)    MODES="${2//,/ }"; shift 2 ;;
    --runs)     RUNS="$2";        shift 2 ;;
    --cooldown) COOLDOWN="$2";    shift 2 ;;
    --pause)    PAUSE="$2";       shift 2 ;;
    --help)     usage ;;
    *)          echo "Unknown option: $1"; usage ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_MULTIPLE="$SCRIPT_DIR/run_multiple.sh"

if [[ ! -x "$RUN_MULTIPLE" ]]; then
  echo "ERROR: run_multiple.sh not found or not executable at $RUN_MULTIPLE"
  exit 1
fi

# ────── Build combo list ──────
combos=()
for tool in $TOOLS; do
  for mode in $MODES; do
    combos+=("$tool:$mode")
  done
done

total=${#combos[@]}
echo ""
echo "========================================"
echo "FULL BENCHMARK SUITE:"
printf -- "- Tools:        %s\n" "$TOOLS"
printf -- "- Modes:        %s\n" "$MODES"
printf -- "- Runs/combo:   %s\n" "$RUNS"
printf -- "- Cooldown:     %ss\n" "$COOLDOWN"
printf -- "- Pause:        %ss\n" "$PAUSE"
printf -- "- Total combos: %s\n" "$total"
printf -- "- Total runs:   %s\n" "$((total * RUNS))"
echo "========================================"
echo ""

start_time=$SECONDS

for ((idx=0; idx<total; idx++)); do
  IFS=":" read -r tool mode <<< "${combos[$idx]}"
  num=$((idx + 1))

  echo ""
  echo "========================================"
  echo "  [$num/$total]  $tool x $mode  ($RUNS runs)"
  echo "========================================"
  echo ""

  "$RUN_MULTIPLE" --tool "$tool" --mode "$mode" --runs "$RUNS" --cooldown "$COOLDOWN"

  if [[ "$num" -lt "$total" ]]; then
    echo ""
    echo "Pausing ${PAUSE}s before next combination..."
    sleep "$PAUSE"
  fi
done

elapsed=$(( SECONDS - start_time ))
minutes=$(( elapsed / 60 ))
seconds=$(( elapsed % 60 ))

echo ""
echo "========================================"
echo "ALL BENCHMARKS COMPLETE"
printf "Elapsed: %dm %ds%-29s\n" "$minutes" "$seconds" ""
