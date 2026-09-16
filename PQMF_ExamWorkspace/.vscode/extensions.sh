#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vscode_dir="$workspace_root/.vscode"
base_settings="$vscode_dir/settings.base.json"
settings_file="$vscode_dir/settings.json"
marker_file="$vscode_dir/.ai-extension-detected"

mode="${1:-check}"

# Detect Python executable: prefer venv, then 'python', then 'python3'
python_exe="python3"
if [ -f "$workspace_root/.venv/bin/python" ]; then
    python_exe="$workspace_root/.venv/bin/python"
elif [ -f "$workspace_root/venv/bin/python" ]; then
    python_exe="$workspace_root/venv/bin/python"
elif command -v python >/dev/null 2>&1; then
    python_exe="python"
fi

if [ "$mode" = "--reset" ] || [ "$mode" = "reset" ]; then
    rm -f "$marker_file"
    "$python_exe" - "$base_settings" "$settings_file" <<'PY'
import sys, json

base_path, settings_path = sys.argv[1], sys.argv[2]
with open(base_path) as f:
    settings = json.load(f)

settings["workbench.colorCustomizations"] = {
    "editor.background": "#0f2747",
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
PY
    printf "✓ Workspace reset complete: AI features disabled and normal colors restored.\n" >&2
    exit 0
fi

run_check() {
    "$python_exe" - "$base_settings" "$settings_file" "$marker_file" <<'PY'
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
    "editor.background": "#0f2747",
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

    if current_settings != target_settings:
        with open(settings_path, "w") as f:
            json.dump(target_settings, f, indent=2)
            f.write("\n")
    print("VIOLATION")
else:
    target_settings = dict(base_settings)
    target_settings["workbench.colorCustomizations"] = NORMAL_COLORS
    if current_settings != target_settings:
        with open(settings_path, "w") as f:
            json.dump(target_settings, f, indent=2)
            f.write("\n")
    print("OK")
PY
}

if [ "$mode" = "--watch" ] || [ "$mode" = "watch" ]; then
    printf "Starting AI prevention watcher loop...\n" >&2
    while true; do
        run_check >/dev/null 2>&1 || true
        sleep 1
    done
else
    res=$(run_check)
    if [ "$res" = "VIOLATION" ]; then
        printf "⚠️ AI usage detected! Workspace glowing pink until instructor reset task is run.\n" >&2
    else
        printf "✓ Workspace settings validated. AI features disabled.\n" >&2
    fi
fi
