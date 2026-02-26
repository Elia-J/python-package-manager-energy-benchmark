#!/usr/bin/env bash
set -euo pipefail

# -------- Defaults --------
WORKDIR="workload"
RESULTS_DIR="results"
PYTHON_BIN="${PYTHON_BIN:-python3.14}"
INTERVAL=200
COOLDOWN=0
LOCK_WORKDIR=""
LOCK_PRIME_WORKDIR=""

TOOL=""
MODE=""

usage() {
  echo "Usage: ./scripts/run_once.sh --tool [pip|uv|poetry] --mode [cold|warm|lock] [--interval N]"
  echo "Env vars:"
  echo "  PYTHON_BIN=python3.14   (optional)"
  exit 1
}

# -------- Parse args --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --python) PYTHON_BIN="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --results) RESULTS_DIR="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --cooldown) COOLDOWN="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$TOOL" || -z "$MODE" ]] && usage

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 200 ]]; then
  echo "ERROR: --interval must be an integer >= 200"
  exit 1
fi

if ! [[ "$COOLDOWN" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --cooldown must be a non-negative integer"
  exit 1
fi

# -------- Paths --------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"

cleanup() {
  if [[ -n "$LOCK_WORKDIR" && -d "$LOCK_WORKDIR" ]]; then
    rm -rf "$LOCK_WORKDIR"
  fi
  if [[ -n "$LOCK_PRIME_WORKDIR" && -d "$LOCK_PRIME_WORKDIR" ]]; then
    rm -rf "$LOCK_PRIME_WORKDIR"
  fi
}
trap cleanup EXIT

# -------- Detect OS/arch --------
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;  # Git Bash/MSYS/Cygwin
    *) echo "unsupported" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64|amd64) echo "x86_64" ;;
    *) echo "unknown" ;;
  esac
}

OS="$(detect_os)"
ARCH="$(detect_arch)"

if [[ "$OS" == "unsupported" || "$ARCH" == "unknown" ]]; then
  echo "ERROR: Unsupported platform: $(uname -s) / $(uname -m)"
  exit 1
fi

# -------- Pick energibridge binary --------
ENERGIBRIDGE_BIN=""

if [[ "$OS" == "windows" ]]; then
  # Prefer .exe if present
  if [[ -x "$BIN_DIR/energibridge-windows-${ARCH}.exe" ]]; then
    ENERGIBRIDGE_BIN="$BIN_DIR/energibridge-windows-${ARCH}.exe"
  elif [[ -x "$BIN_DIR/energibridge-windows-${ARCH}" ]]; then
    ENERGIBRIDGE_BIN="$BIN_DIR/energibridge-windows-${ARCH}"
  fi
else
  if [[ -x "$BIN_DIR/energibridge-${OS}-${ARCH}" ]]; then
    ENERGIBRIDGE_BIN="$BIN_DIR/energibridge-${OS}-${ARCH}"
  fi
fi

if [[ -z "$ENERGIBRIDGE_BIN" ]]; then
  echo "ERROR: No energibridge binary found for ${OS}-${ARCH} in $BIN_DIR"
  echo "Expected one of:"
  echo "  $BIN_DIR/energibridge-${OS}-${ARCH}"
  echo "  $BIN_DIR/energibridge-windows-${ARCH}.exe   (on Windows)"
  exit 1
fi

# -------- Validation of tool availability --------
case "$TOOL" in
  pip) command -v pip >/dev/null 2>&1 || { echo "ERROR: pip not found"; exit 1; } ;;
  uv) command -v uv >/dev/null 2>&1 || { echo "ERROR: uv not found"; exit 1; } ;;
  poetry) command -v poetry >/dev/null 2>&1 || { echo "ERROR: poetry not found"; exit 1; } ;;
  *) echo "ERROR: unknown tool '$TOOL'"; exit 1 ;;
esac

case "$MODE" in
  cold|warm|lock) ;;
  *) echo "ERROR: unknown mode '$MODE'"; exit 1 ;;
esac

if [[ "$TOOL" == "pip" && "$MODE" == "lock" ]]; then
  command -v pip-compile >/dev/null 2>&1 || { echo "ERROR: pip-compile not found (pip-tools)"; exit 1; }
fi

# -------- Helper for venv bin paths --------
venv_python() {
  if [[ "$OS" == "windows" ]]; then
    echo ".venv/Scripts/python.exe"
  else
    echo ".venv/bin/python"
  fi
}

venv_pip() {
  if [[ "$OS" == "windows" ]]; then
    echo ".venv/Scripts/pip.exe"
  else
    echo ".venv/bin/pip"
  fi
}

# -------- Prep output --------
mkdir -p "$ROOT_DIR/$RESULTS_DIR"

timestamp="$(date +"%Y%m%d_%H%M%S")"
run_id="${TOOL}_${MODE}_${OS}_${ARCH}_${timestamp}"
outfile="$ROOT_DIR/$RESULTS_DIR/${run_id}.csv"
cmdlog="$ROOT_DIR/$RESULTS_DIR/${run_id}.cmd.log"
metafile="$ROOT_DIR/$RESULTS_DIR/${run_id}.meta.csv"

echo "Platform:     $OS/$ARCH"
echo "Energibridge: $ENERGIBRIDGE_BIN"
echo "Output:       $outfile"
echo "Interval:     $INTERVAL"

# -------- Workdir --------
cd "$ROOT_DIR/$WORKDIR"

# -------- Cleanup --------
if [[ "$MODE" == "cold" || "$MODE" == "warm" ]]; then
  rm -rf .venv
fi

if [[ "$MODE" == "cold" ]]; then
  if [[ "$TOOL" == "pip" ]]; then
    pip cache purge || true
  elif [[ "$TOOL" == "uv" ]]; then
    uv cache clean || uv cache clear || true
  elif [[ "$TOOL" == "poetry" ]]; then
    poetry cache clear pypi --all --no-interaction || poetry cache clear PyPI --all --no-interaction || true
  fi
fi

# -------- Select command --------
CMD=""
PRIME_CMD=""

if [[ "$MODE" == "lock" ]]; then
  LOCK_PRIME_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/pm-lock-prime-XXXXXX")"
  LOCK_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/pm-lock-XXXXXX")"

  if [[ "$TOOL" == "pip" ]]; then
    [[ -f "requirements.in" ]] || { echo "ERROR: workload/requirements.in missing"; exit 1; }
    cp requirements.in "$LOCK_PRIME_WORKDIR/"
    cp requirements.in "$LOCK_WORKDIR/"
    PRIME_CMD="cd \"$LOCK_PRIME_WORKDIR\" && pip-compile requirements.in --strip-extras --output-file requirements.lock"
    CMD="cd \"$LOCK_WORKDIR\" && pip-compile requirements.in --strip-extras --output-file requirements.lock"
  elif [[ "$TOOL" == "uv" ]]; then
    [[ -f "pyproject.toml" ]] || { echo "ERROR: workload/pyproject.toml missing"; exit 1; }
    cp pyproject.toml "$LOCK_PRIME_WORKDIR/"
    cp pyproject.toml "$LOCK_WORKDIR/"
    PRIME_CMD="cd \"$LOCK_PRIME_WORKDIR\" && uv lock"
    CMD="cd \"$LOCK_WORKDIR\" && uv lock"
  elif [[ "$TOOL" == "poetry" ]]; then
    [[ -f "pyproject.toml" ]] || { echo "ERROR: workload/pyproject.toml missing"; exit 1; }
    cp pyproject.toml "$LOCK_PRIME_WORKDIR/"
    cp pyproject.toml "$LOCK_WORKDIR/"
    PRIME_CMD="cd \"$LOCK_PRIME_WORKDIR\" && poetry lock"
    CMD="cd \"$LOCK_WORKDIR\" && poetry lock"
  fi
else
  "$PYTHON_BIN" -m venv .venv

  if [[ "$TOOL" == "pip" ]]; then
    [[ -f "requirements.txt" ]] || { echo "ERROR: workload/requirements.txt missing"; exit 1; }
    CMD="$(venv_pip) install -r requirements.txt"
  elif [[ "$TOOL" == "uv" ]]; then
    [[ -f "requirements.txt" ]] || { echo "ERROR: workload/requirements.txt missing"; exit 1; }
    CMD="uv pip install --python $(venv_python) -r requirements.txt"
  elif [[ "$TOOL" == "poetry" ]]; then
    poetry config virtualenvs.in-project true >/dev/null 2>&1 || true
    poetry env use "$PYTHON_BIN"
    CMD="poetry install --no-root"
  fi
fi

# -------- Warm metadata-cache priming for lock mode (unmeasured) --------
if [[ "$MODE" == "lock" ]]; then
  echo "Priming metadata cache for lock run (unmeasured)..."
  set +e
  eval "$PRIME_CMD"
  prime_exit=$?
  set -e
  if [[ "$prime_exit" -ne 0 ]]; then
    echo "ERROR: lock-mode priming failed with exit code $prime_exit"
    exit "$prime_exit"
  fi
fi

# -------- Warm-cache priming (unmeasured) --------
# To keep warm runs independent from shuffled ordering, every warm run primes the
# tool cache first, then removes .venv so the measured command still performs an install.
if [[ "$MODE" == "warm" ]]; then
  echo "Priming cache for warm run (unmeasured)..."
  set +e
  eval "$CMD"
  prime_exit=$?
  set -e
  if [[ "$prime_exit" -ne 0 ]]; then
    echo "ERROR: warm-cache priming failed with exit code $prime_exit"
    exit "$prime_exit"
  fi
  rm -rf .venv
  "$PYTHON_BIN" -m venv .venv
fi

echo "Running: $CMD"

run_start_s="$(date +%s)"

# Use an explicit shell path on Windows so EnergiBridge does not resolve to
# the WSL launcher (C:\Windows\System32\bash.exe).
SHELL_BIN="bash"
if [[ "$OS" == "windows" ]]; then
  command -v bash >/dev/null 2>&1 || { echo "ERROR: bash not found in PATH"; exit 1; }
  if command -v cygpath >/dev/null 2>&1; then
    SHELL_BIN="$(cygpath -w "$(command -v bash)")"
  else
    SHELL_BIN="$(command -v bash)"
  fi
fi

set +e
"$ENERGIBRIDGE_BIN" \
  -i "$INTERVAL" \
  -c "$cmdlog" \
  -- "$SHELL_BIN" -lc "$CMD" \
  > "$outfile"
command_exit=$?
set -e

run_end_s="$(date +%s)"
wall_clock_s=$((run_end_s - run_start_s))

printf "tool,mode,os,arch,timestamp,interval_arg,wall_clock_s,exit_code,csv_file,cmdlog_file\n" > "$metafile"
printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
  "$TOOL" \
  "$MODE" \
  "$OS" \
  "$ARCH" \
  "$timestamp" \
  "$INTERVAL" \
  "$wall_clock_s" \
  "$command_exit" \
  "$(basename "$outfile")" \
  "$(basename "$cmdlog")" >> "$metafile"

if [[ "$command_exit" -ne 0 ]]; then
  echo "ERROR: benchmark command failed with exit code $command_exit"
  exit "$command_exit"
fi

if [[ "$COOLDOWN" -gt 0 ]]; then
  echo "Run complete. Cooling down ${COOLDOWN}s..."
  sleep "$COOLDOWN"
else
  echo "Run complete."
fi
