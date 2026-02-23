param (
    [Parameter(Mandatory=$true)]
    [string]$Tool,

    [Parameter(Mandatory=$true)]
    [string]$Mode,

    [int]$Runs = 5
)

# Check WSL availability
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "WSL is not installed or not in PATH."
    exit 1
}

Write-Host "Launching benchmark inside WSL..."
Write-Host "Tool: $Tool"
Write-Host "Mode: $Mode"
Write-Host "Runs: $Runs"

# Convert Windows path to WSL path
$ProjectPath = wsl wslpath -a (Get-Location)

# Execute inside WSL
wsl bash -c "
  cd '$ProjectPath' &&
  chmod +x scripts/run_multiple.sh &&
  ./scripts/run_multiple.sh --tool $Tool --mode $Mode --runs $Runs
"