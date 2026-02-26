param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("pip","poetry","uv")]
    [string]$Tool,

    [Parameter(Mandatory=$true)]
    [ValidateSet("cold","warm","lock")]
    [string]$Mode,

    [int]$Runs = 5,

    [int]$Cooldown = 60,

    [int]$Interval = 100,

    [string]$PythonBin = "python3.14"
)

# --------------------------------------------------
# Check WSL availability
# --------------------------------------------------
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "WSL is not installed or not available in PATH."
    exit 1
}

Write-Host "========================================"
Write-Host "Running benchmark inside WSL"
Write-Host "Tool:      $Tool"
Write-Host "Mode:      $Mode"
Write-Host "Runs:      $Runs"
Write-Host "Cooldown:  $Cooldown"
Write-Host "Interval:  $Interval"
Write-Host "Python:    $PythonBin"
Write-Host "========================================"

# --------------------------------------------------
# Convert current Windows path to WSL path
# --------------------------------------------------
$WindowsPath = (Get-Location).Path
$WSLPath = wsl wslpath -a "$WindowsPath"

if (-not $WSLPath) {
    Write-Error "Failed to convert Windows path to WSL path."
    exit 1
}

# --------------------------------------------------
# Execute inside WSL
# --------------------------------------------------
wsl bash -c "
    set -e
    cd '$WSLPath'
    chmod +x scripts/run_multiple.sh
    ./scripts/run_multiple.sh \
        --tool $Tool \
        --mode $Mode \
        --runs $Runs \
        --cooldown $Cooldown \
        --interval $Interval \
        --python $PythonBin
"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Benchmark failed inside WSL."
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "All runs completed successfully."
