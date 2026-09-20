# PowerShell validator for Windows: ensures AI features remain disabled.
# Run on workspace open or manually via task.
param(
    [ValidateSet("check", "reset", "watch")]
    [string]$Mode = "check"
)

$ErrorActionPreference = "Stop"

$vscodeDir = Split-Path -Parent $PSCommandPath
$workspaceRoot = Split-Path -Parent $vscodeDir
$baseSettings = Join-Path $vscodeDir "settings.base.json"
$settingsFile = Join-Path $vscodeDir "settings.json"
$markerFile = Join-Path $vscodeDir ".ai-extension-detected"
$extensionHeartbeat = Join-Path $vscodeDir ".pqmf-exam-guard-extension-heartbeat"
$scriptHeartbeat = Join-Path $vscodeDir ".pqmf-exam-guard-script-heartbeat"
$guardLog = Join-Path $vscodeDir ".pqmf-exam-guard.log"
$watchStarted = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# Helper to find Python in venv or system
function Get-PythonExe {
    # Check if venv Python is available
    $venvPython = Join-Path $workspaceRoot ".venv\Scripts\python.exe"
    if (Test-Path $venvPython) {
        return $venvPython
    }
    
    $venvPython = Join-Path $workspaceRoot "venv\Scripts\python.exe"
    if (Test-Path $venvPython) {
        return $venvPython
    }
    
    # Fall back to system Python
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return "python"
    }
    
    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        return "python3"
    }
    
    throw "Python not found in venv or system PATH"
}

$pythonExe = Get-PythonExe

if ($Mode -eq "reset") {
    # Give the extension watchdog time to reconstruct any deleted protected
    # files before this legacy reset path clears the persistent marker.
    Start-Sleep -Seconds 10
    Remove-Item -Path $markerFile -ErrorAction SilentlyContinue
    
    & $pythonExe (Join-Path $vscodeDir 'guard-reset.py') $baseSettings $settingsFile
    $logItem = Get-Item -LiteralPath $guardLog -Force -ErrorAction SilentlyContinue
    if ($logItem) { $logItem.IsReadOnly = $false }
    Add-Content -LiteralPath $guardLog -Value "$([DateTime]::UtcNow.ToString('o')) [script] RESET Legacy instructor reset restored settings and normal colors."
    Write-Host "[OK] Workspace reset complete: AI features disabled and normal colors restored." -ForegroundColor Green
    exit 0
}

function Invoke-Check {
    $output = & $pythonExe (Join-Path $vscodeDir 'guard-check.py') $baseSettings $settingsFile $markerFile $extensionHeartbeat $scriptHeartbeat $Mode $watchStarted $guardLog
    return $output.Trim()
}

function Invoke-CheckLocked {
    $mutex = New-Object System.Threading.Mutex($false, "PQMFExamExtensionsCheck")
    $null = $mutex.WaitOne(20000)
    try {
        return Invoke-Check
    }
    finally {
        $mutex.ReleaseMutex()
    }
}

if ($Mode -eq "watch") {
    Write-Host "Starting AI prevention watcher loop..." -ForegroundColor Cyan
    while ($true) {
        Invoke-CheckLocked | Out-Null
        Start-Sleep -Seconds 1
    }
}
else {
    $result = Invoke-CheckLocked
    if ($result -eq "VIOLATION") {
        Write-Host "[!] AI usage detected! Workspace glowing pink until instructor reset task is run. See Output > PQMF Exam Guard." -ForegroundColor Red
    }
    elseif ($result -eq "SKIP") {
        Write-Host "... Settings file busy, retry the check in a moment." -ForegroundColor Yellow
    }
    else {
        Write-Host "[OK] Workspace settings validated. AI features disabled." -ForegroundColor Green
    }
}
