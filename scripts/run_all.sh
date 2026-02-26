#!/usr/bin/env bash
set -euo pipefail

# Run benchmarks for every tool x mode combination with run-level shuffling.

TOOLS="pip uv poetry"
MODES="cold warm lock"
RUNS=5
COOLDOWN=60
PAUSE=0      # extra seconds when switching tool/mode combos
INTERVAL=""
SEED=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --tools    <t1,t2,...>   Comma-separated tools to benchmark (default: pip,uv,poetry)
  --modes    <m1,m2,...>   Comma-separated modes to benchmark (default: cold,warm,lock)
  --runs     <N>           Number of repetitions per combination (default: 5)
  --cooldown <S>           Seconds between runs (default: 60)
  --pause    <S>           Extra seconds when switching tool/mode combos (default: 0)
  --interval <N>           EnergiBridge interval argument passed to run_once.sh
  --seed     <N>           Optional RNG seed for reproducible shuffle order
  --help                   Show this help message

Examples:
  $0                                        # all 9 combos, 5 runs each (shuffled)
  $0 --runs 30 --seed 42                    # reproducible run order
  $0 --tools pip,uv --modes cold,warm       # 4 combos only (shuffled)
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
    --interval) INTERVAL="$2";    shift 2 ;;
    --seed)     SEED="$2";        shift 2 ;;
    --help)     usage ;;
    *)          echo "Unknown option: $1"; usage ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_ONCE="$SCRIPT_DIR/run_once.sh"
RESULTS_DIR="$ROOT_DIR/results"

if [[ ! -x "$RUN_ONCE" ]]; then
  echo "ERROR: run_once.sh not found or not executable at $RUN_ONCE"
  exit 1
fi

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [[ "$RUNS" -le 0 ]]; then
  echo "ERROR: --runs must be a positive integer"
  exit 1
fi

if ! [[ "$COOLDOWN" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --cooldown must be a non-negative integer"
  exit 1
fi

if ! [[ "$PAUSE" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --pause must be a non-negative integer"
  exit 1
fi

if [[ -n "$INTERVAL" ]] && { ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -le 0 ]]; }; then
  echo "ERROR: --interval must be a positive integer"
  exit 1
fi

if [[ -n "$SEED" ]] && ! [[ "$SEED" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --seed must be a non-negative integer"
  exit 1
fi

combos=()
for tool in $TOOLS; do
  for mode in $MODES; do
    combos+=("$tool:$mode")
  done
done

total_combos=${#combos[@]}
total_runs=$((total_combos * RUNS))

# Build run-level schedule, then shuffle it.
schedule=()
for ((rep=1; rep<=RUNS; rep++)); do
  for combo in "${combos[@]}"; do
    schedule+=("$combo")
  done
done

if [[ -n "$SEED" ]]; then
  RANDOM="$SEED"
fi

for ((i=${#schedule[@]}-1; i>0; i--)); do
  j=$((RANDOM % (i + 1)))
  tmp="${schedule[$i]}"
  schedule[$i]="${schedule[$j]}"
  schedule[$j]="$tmp"
done

mkdir -p "$RESULTS_DIR"
schedule_timestamp="$(date +"%Y%m%d_%H%M%S")"
schedule_file="$RESULTS_DIR/schedule_${schedule_timestamp}.csv"
printf "run_index,tool,mode\n" > "$schedule_file"
for ((i=0; i<${#schedule[@]}; i++)); do
  IFS=":" read -r tool mode <<< "${schedule[$i]}"
  printf "%d,%s,%s\n" "$((i+1))" "$tool" "$mode" >> "$schedule_file"
done

echo ""
echo "========================================"
echo "FULL BENCHMARK SUITE (SHUFFLED):"
printf -- "- Tools:        %s\n" "$TOOLS"
printf -- "- Modes:        %s\n" "$MODES"
printf -- "- Runs/combo:   %s\n" "$RUNS"
printf -- "- Cooldown:     %ss\n" "$COOLDOWN"
printf -- "- Extra pause:  %ss (on combo switch)\n" "$PAUSE"
if [[ -n "$INTERVAL" ]]; then
  printf -- "- Interval arg: %s\n" "$INTERVAL"
fi
if [[ -n "$SEED" ]]; then
  printf -- "- Shuffle seed: %s\n" "$SEED"
fi
printf -- "- Total combos: %s\n" "$total_combos"
printf -- "- Total runs:   %s\n" "$total_runs"
printf -- "- Schedule:     %s\n" "$schedule_file"
echo "========================================"
echo ""

start_time=$SECONDS

for ((idx=0; idx<total_runs; idx++)); do
  IFS=":" read -r tool mode <<< "${schedule[$idx]}"
  num=$((idx + 1))

  echo ""
  echo "[$num/$total_runs] $tool x $mode"
  echo ""

  run_once_cmd=("$RUN_ONCE" --tool "$tool" --mode "$mode")
  if [[ -n "$INTERVAL" ]]; then
    run_once_cmd+=(--interval "$INTERVAL")
  fi
  "${run_once_cmd[@]}"

  if [[ "$num" -lt "$total_runs" ]]; then
    next_combo="${schedule[$idx+1]}"
    echo ""
    echo "Cooling down ${COOLDOWN}s before next run..."
    sleep "$COOLDOWN"
    if [[ "$PAUSE" -gt 0 ]] && [[ "$next_combo" != "${schedule[$idx]}" ]]; then
      echo "Applying extra combo-switch pause: ${PAUSE}s..."
      sleep "$PAUSE"
    fi
  fi
done

elapsed=$(( SECONDS - start_time ))
minutes=$(( elapsed / 60 ))
seconds=$(( elapsed % 60 ))

echo ""
echo "========================================"
echo "ALL SHUFFLED BENCHMARKS COMPLETE"
printf "Elapsed: %dm %ds%-29s\n" "$minutes" "$seconds" ""
