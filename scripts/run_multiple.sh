#!/usr/bin/env bash
set -euo pipefail

TOOL=""
MODE=""
RUNS=5
COOLDOWN=60
INTERVAL=""

usage() {
  echo "Usage: $0 --tool <tool> --mode <mode> [--runs N] [--cooldown S] [--interval N]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --runs)
      RUNS="$2"
      shift 2
      ;;
    --cooldown)
      COOLDOWN="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$TOOL" || -z "$MODE" ]]; then
  usage
fi

echo "========================================"
echo "Tool:      $TOOL"
echo "Mode:      $MODE"
echo "Runs:      $RUNS"
echo "Cooldown:  ${COOLDOWN}s"
if [[ -n "$INTERVAL" ]]; then
  echo "Interval:  $INTERVAL"
fi
echo "========================================"

for ((i=1; i<=RUNS; i++)); do
  echo ""
  echo "▶ Run $i / $RUNS"
  echo "----------------------------------------"

  run_once_cmd=(./scripts/run_once.sh --tool "$TOOL" --mode "$MODE")
  if [[ -n "$INTERVAL" ]]; then
    run_once_cmd+=(--interval "$INTERVAL")
  fi
  "${run_once_cmd[@]}"

  if [[ "$i" -lt "$RUNS" ]]; then
    echo "Cooling down for ${COOLDOWN}s..."
    sleep "$COOLDOWN"
  fi
done

echo ""
echo "All runs completed."
