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
    Write-Host "✓ Workspace reset complete: AI features disabled and normal colors restored." -ForegroundColor Green
    exit 0
}

function Invoke-Check {
    $pythonCode = @'
import os, sys, json

base_path = sys.argv[1]
settings_path = sys.argv[2]
marker_path = sys.argv[3]

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

current_settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path) as f:
            current_settings = json.load(f)
    except Exception:
        pass

if not violation_detected:
    if current_settings.get("chat.disableAIFeatures") is False:
        violation_detected = True
    elif current_settings.get("editor.inlineSuggest.enabled") is True:
        violation_detected = True
    elif current_settings.get("github.copilot.inlineSuggest.enable") is True:
        violation_detected = True
    elif current_settings.get("github.copilot.nextEditSuggestions.enabled") is True:
        violation_detected = True
    elif current_settings.get("github.copilot.editor.enableCodeActions") is True:
        violation_detected = True
    elif isinstance(current_settings.get("github.copilot.enable"), dict) and any(current_settings.get("github.copilot.enable").values()):
        violation_detected = True
    elif isinstance(current_settings.get("extensions.allowed"), dict) and any(val is True for k, val in current_settings.get("extensions.allowed").items() if k != "*"):
        violation_detected = True

if violation_detected:
    try:
        with open(marker_path, "w") as f:
            f.write("AI usage detected in workspace\n")
    except Exception:
        pass

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

    $output = & $pythonExe -c $pythonCode $baseSettings $settingsFile $markerFile
    return $output.Trim()
}

if ($Mode -eq "watch") {
    Write-Host "Starting AI prevention watcher loop..." -ForegroundColor Cyan
    while ($true) {
        Invoke-Check | Out-Null
        Start-Sleep -Seconds 1
    }
}
else {
    $result = Invoke-Check
    if ($result -eq "VIOLATION") {
        Write-Host "⚠️ AI usage detected! Workspace glowing pink until instructor reset task is run." -ForegroundColor Red
    }
    else {
        Write-Host "✓ Workspace settings validated. AI features disabled." -ForegroundColor Green
    }
}
