param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("pip","poetry","uv")]
    [string]$Tool,

    [Parameter(Mandatory=$true)]
    [ValidateSet("cold","warm","lock")]
    [string]$Mode,

    [int]$Interval = 100,

    [int]$Cooldown = 0,

    [string]$PythonBin = "python3.14"
)

# Check WSL availability
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "WSL is not installed or not in PATH."
    exit 1
}

Write-Host "Launching benchmark inside WSL..."
Write-Host "Tool: $Tool"
Write-Host "Mode: $Mode"
Write-Host "Interval: $Interval"
Write-Host "Cooldown: $Cooldown"
Write-Host "Python: $PythonBin"

# Convert Windows path to WSL path
$ProjectPath = wsl wslpath -a (Get-Location)

# Execute inside WSL
wsl bash -c "
  set -e
  cd '$ProjectPath'
  chmod +x scripts/run_once.sh
  ./scripts/run_once.sh --tool $Tool --mode $Mode --python $PythonBin --interval $Interval --cooldown $Cooldown
"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Benchmark failed inside WSL."
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Run completed successfully."
