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
    Remove-Item -Path "$markerFile.outside-file" -ErrorAction SilentlyContinue
    
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
import glob
import re
import sqlite3
from urllib.parse import unquote, urlparse

base_path = sys.argv[1]
settings_path = sys.argv[2]
marker_path = sys.argv[3]

def outside_open_file(workspace_root):
    storage_root = os.path.join(os.environ.get("APPDATA", ""), "Code", "User", "workspaceStorage")
    workspace_root = os.path.realpath(workspace_root)
    for storage_dir in glob.glob(os.path.join(storage_root, "*")):
        workspace_file = os.path.join(storage_dir, "workspace.json")
        state_file = os.path.join(storage_dir, "state.vscdb")
        if not os.path.isfile(workspace_file) or not os.path.isfile(state_file):
            continue
        try:
            with open(workspace_file, encoding="utf-8") as file:
                folder = json.load(file).get("folder", "")
            if urlparse(folder).scheme == "file":
                folder = unquote(urlparse(folder).path)
            if os.path.realpath(folder) != workspace_root:
                continue
            connection = sqlite3.connect(state_file)
            rows = connection.execute("select value from ItemTable where key like 'memento/workbench.editor.%'")
            for (value,) in rows:
                text = value if isinstance(value, str) else json.dumps(value)
                for candidate in re.findall(r"file://([^\"]+)", text):
                    path = unquote(candidate.replace("\\\\", "\\"))
                    if path.startswith("/") and not os.path.realpath(path).startswith(workspace_root + os.sep):
                        connection.close()
                        return path
            connection.close()
        except Exception:
            continue
    return None

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

outside_path = outside_open_file(os.path.dirname(os.path.dirname(base_path)))
outside_marker_path = marker_path + ".outside-file"
if outside_path:
    try:
        with open(outside_marker_path, "w") as f:
            f.write(outside_path + "\n")
    except Exception:
        pass
violation_detected = os.path.exists(marker_path) or os.path.exists(outside_marker_path)

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
        if (Test-Path "$vscodeDir\.ai-extension-detected.outside-file") {
            Write-Host "⚠️ File outside the exam workspace was opened. Workspace glowing pink until instructor reset task is run." -ForegroundColor Red
        }
        else {
            Write-Host "⚠️ AI usage detected! Workspace glowing pink until instructor reset task is run." -ForegroundColor Red
        }
    }
    else {
        Write-Host "✓ Workspace settings validated. AI features disabled." -ForegroundColor Green
    }
}
