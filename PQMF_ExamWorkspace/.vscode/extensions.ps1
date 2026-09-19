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
    $venvPython = Join-Path $workspaceRoot ".venv" "Scripts" "python.exe"
    if (Test-Path $venvPython) {
        return $venvPython
    }
    
    $venvPython = Join-Path $workspaceRoot "venv" "Scripts" "python.exe"
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
    
    $pythonCode = @'
import sys, json

base_path, settings_path = sys.argv[1], sys.argv[2]
with open(base_path) as f:
    settings = json.load(f)

try:
    with open(settings_path) as f:
        previous_settings = json.load(f)
except Exception:
    previous_settings = {}

if "python.defaultInterpreterPath" in previous_settings:
    settings["python.defaultInterpreterPath"] = previous_settings["python.defaultInterpreterPath"]

settings["workbench.colorCustomizations"] = {
    "editor.background": "#183D2F",
    "notebook.editorBackground": "#183D2F",
    "notebook.cellEditorBackground": "#1e1e1e",
    "statusBar.background": "#1f2937",
    "statusBar.foreground": "#f9fafb",
    "titleBar.activeBackground": "#111827",
    "titleBar.activeForeground": "#f9fafb",
    "activityBar.background": "#1f2937",
    "activityBar.foreground": "#f9fafb"
}

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
'@

    & $pythonExe -c $pythonCode $baseSettings $settingsFile
    $logItem = Get-Item -LiteralPath $guardLog -Force -ErrorAction SilentlyContinue
    if ($logItem) { $logItem.IsReadOnly = $false }
    Add-Content -LiteralPath $guardLog -Value "$([DateTime]::UtcNow.ToString('o')) [script] RESET Legacy instructor reset restored settings and normal colors."
    Write-Host "✓ Workspace reset complete: AI features disabled and normal colors restored." -ForegroundColor Green
    exit 0
}

function Invoke-Check {
    $pythonCode = @'
import os, sys, json, time

base_path = sys.argv[1]
settings_path = sys.argv[2]
marker_path = sys.argv[3]
extension_heartbeat = sys.argv[4]
script_heartbeat = sys.argv[5]
mode = sys.argv[6]
watch_started = float(sys.argv[7])
log_path = sys.argv[8]

def log_event(level, message):
    entry = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    entry += f" [script] {level} {str(message).replace(chr(10), ' | ')}\n"
    try:
        with open(log_path, "a") as log_file:
            log_file.write(entry)
    except Exception:
        try:
            os.chmod(log_path, 0o644)
            with open(log_path, "a") as log_file:
                log_file.write(entry)
        except Exception:
            pass

try:
    with open(script_heartbeat, "w") as heartbeat_file:
        heartbeat_file.write(f"{time.time()}\n")
except Exception:
    try:
        os.chmod(script_heartbeat, 0o644)
        with open(script_heartbeat, "w") as heartbeat_file:
            heartbeat_file.write(f"{time.time()}\n")
    except Exception:
        pass

PINK_COLORS = {
    "statusBar.background": "#ff1493",
    "statusBar.foreground": "#ffffff",
    "titleBar.activeBackground": "#ff1493",
    "titleBar.activeForeground": "#ffffff",
    "activityBar.background": "#ff1493",
    "activityBar.foreground": "#ffffff",
    "sideBar.background": "#ffb6c1",
    "sideBar.foreground": "#000000"
}

NORMAL_COLORS = {
    "editor.background": "#183D2F",
    "notebook.editorBackground": "#183D2F",
    "notebook.cellEditorBackground": "#1e1e1e",
    "statusBar.background": "#1f2937",
    "statusBar.foreground": "#f9fafb",
    "titleBar.activeBackground": "#111827",
    "titleBar.activeForeground": "#f9fafb",
    "activityBar.background": "#1f2937",
    "activityBar.foreground": "#f9fafb"
}

try:
    with open(base_path) as f:
         base_settings = json.load(f)
except Exception:
    base_settings = {}

violation_detected = os.path.exists(marker_path)
violation_reason = None

current_settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path) as f:
            current_settings = json.load(f)
    except Exception:
        # settings.json exists but failed to parse - likely VS Code is mid-write.
        # Skip this cycle rather than treating it as empty, which would cause
        # us to force-overwrite (and erase) whatever edit is in progress.
        print("SKIP")
        sys.exit(0)

policy_keys = (
    "chat.disableAIFeatures",
    "chat.commandCenter.enabled",
    "github.copilot.enable",
    "github.copilot.inlineSuggest.enable",
    "github.copilot.nextEditSuggestions.enabled",
    "github.copilot.editor.enableCodeActions",
    "editor.inlineSuggest.enabled",
    "editor.inlineSuggest.suppressSuggestions",
    "extensions.allowed",
    "files.exclude",
    "search.exclude",
)
protected_defaults = base_settings.get("pqmfExamGuard.protectedSettings", {})

if not violation_detected and any(
    current_settings.get(key) != base_settings.get(key) for key in policy_keys
):
    violation_detected = True
    violation_reason = "Protected exam settings were changed."

if not violation_detected and any(
    current_settings.get(key) != value for key, value in protected_defaults.items()
):
    violation_detected = True
    violation_reason = "Protected exam settings were changed."

if not violation_detected and mode == "watch" and time.time() - watch_started >= 20:
    try:
        heartbeat_age = time.time() - os.path.getmtime(extension_heartbeat)
        if heartbeat_age > 20:
            violation_detected = True
            violation_reason = "Exam guard extension heartbeat is stale."
    except OSError:
        violation_detected = True
        violation_reason = "Exam guard extension heartbeat is missing."

if violation_detected:
    new_violation = not os.path.exists(marker_path)
    try:
        if new_violation:
            with open(marker_path, "w") as f:
                f.write((violation_reason or "Exam policy violation detected.") + "\n")
    except Exception:
        pass
    if new_violation:
        log_event("VIOLATION", violation_reason or "Exam policy violation detected.")

    target_settings = dict(base_settings)
    target_settings["workbench.colorCustomizations"] = PINK_COLORS

    if "python.defaultInterpreterPath" in current_settings:
        target_settings["python.defaultInterpreterPath"] = current_settings["python.defaultInterpreterPath"]

    if current_settings != target_settings:
        with open(settings_path, "w") as f:
            json.dump(target_settings, f, indent=2)
            f.write("\n")
    print("VIOLATION")
else:
    target_settings = dict(base_settings)
    target_settings["workbench.colorCustomizations"] = NORMAL_COLORS
    if "python.defaultInterpreterPath" in current_settings:
        target_settings["python.defaultInterpreterPath"] = current_settings["python.defaultInterpreterPath"]
    if current_settings != target_settings:
        with open(settings_path, "w") as f:
            json.dump(target_settings, f, indent=2)
            f.write("\n")
    print("OK")
'@

    $output = & $pythonExe -c $pythonCode $baseSettings $settingsFile $markerFile `
        $extensionHeartbeat $scriptHeartbeat $Mode $watchStarted $guardLog
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
        Write-Host "⚠️ AI usage detected! Workspace glowing pink until instructor reset task is run. See Output > PQMF Exam Guard." -ForegroundColor Red
    }
    elseif ($result -eq "SKIP") {
        Write-Host "… Settings file busy, retry the check in a moment." -ForegroundColor Yellow
    }
    else {
        Write-Host "✓ Workspace settings validated. AI features disabled." -ForegroundColor Green
    }
}
