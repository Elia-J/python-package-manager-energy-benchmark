#!/usr/bin/env bash
set -euo pipefail

# -------- Defaults --------
WORKDIR="workload"
RESULTS_DIR="results"
PYTHON_BIN="${PYTHON_BIN:-python}"
INTERVAL_US=100000   # energibridge -i is microseconds; 100000us = 100ms
COOLDOWN=10

TOOL=""
MODE=""

usage() {
  echo "Usage: ./scripts/run_once.sh --tool [pip|uv|poetry] --mode [cold|warm|lock]"
  echo "Env vars:"
  echo "  PYTHON_BIN=python3.11   (optional)"
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
    --interval-us) INTERVAL_US="$2"; shift 2 ;;
    --cooldown) COOLDOWN="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$TOOL" || -z "$MODE" ]] && usage

# -------- Paths --------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"

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
    arm64) echo "arm64" ;;
    aarch64) echo "aarch64" ;;
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
outfile="$ROOT_DIR/$RESULTS_DIR/${TOOL}_${MODE}_${OS}_${ARCH}_${timestamp}.csv"

echo "Platform:     $OS/$ARCH"
echo "Energibridge: $ENERGIBRIDGE_BIN"
echo "Output:       $outfile"

# -------- Workdir --------
cd "$ROOT_DIR/$WORKDIR"

# -------- Cleanup --------
if [[ "$MODE" == "cold" || "$MODE" == "warm" ]]; then
  rm -rf .venv
fi

if [[ "$MODE" == "lock" ]]; then
  rm -f poetry.lock uv.lock requirements.lock
fi

if [[ "$MODE" == "cold" ]]; then
  if [[ "$TOOL" == "pip" ]]; then
    pip cache purge || true
  elif [[ "$TOOL" == "uv" ]]; then
    uv cache clean || uv cache clear || true
  elif [[ "$TOOL" == "poetry" ]]; then
    poetry cache clear pypi --all || poetry cache clear PyPI --all || true
  fi
fi

# -------- Select command --------
CMD=""

if [[ "$MODE" == "lock" ]]; then
  if [[ "$TOOL" == "pip" ]]; then
    [[ -f "requirements.in" ]] || { echo "ERROR: workload/requirements.in missing"; exit 1; }
    CMD="pip-compile requirements.in --output-file requirements.lock"
  elif [[ "$TOOL" == "uv" ]]; then
    CMD="uv lock"
  elif [[ "$TOOL" == "poetry" ]]; then
    CMD="poetry lock"
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

echo "Running: $CMD"

cmdlog="$ROOT_DIR/$RESULTS_DIR/${TOOL}_${MODE}_${OS}_${ARCH}_${timestamp}.cmd.log"

"$ENERGIBRIDGE_BIN" \
  -i "$INTERVAL_US" \
  -c "$cmdlog" \
  -- bash -c "$CMD" \
  > "$outfile"

echo "Run complete. Cooling down ${COOLDOWN}s..."
sleep "$COOLDOWN"