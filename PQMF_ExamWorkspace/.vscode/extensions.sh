#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vscode_dir="$workspace_root/.vscode"
base_settings="$vscode_dir/settings.base.json"
settings_file="$vscode_dir/settings.json"
marker_file="$vscode_dir/.ai-extension-detected"
extension_heartbeat="$vscode_dir/.pqmf-exam-guard-extension-heartbeat"
script_heartbeat="$vscode_dir/.pqmf-exam-guard-script-heartbeat"
guard_log="$vscode_dir/.pqmf-exam-guard.log"

mode="${1:-check}"
watch_started=$(date +%s)

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
    # Give the extension watchdog time to reconstruct any deleted protected
    # files before this legacy reset path clears the persistent marker.
    sleep 10
    rm -f "$marker_file"
    "$python_exe" - "$base_settings" "$settings_file" <<'PY'
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
PY
    chmod u+w "$guard_log" 2>/dev/null || true
    printf '%s [script] RESET Legacy instructor reset restored settings and normal colors.\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$guard_log" 2>/dev/null || true
    printf "✓ Workspace reset complete: AI features disabled and normal colors restored.\n" >&2
    exit 0
fi

# The "check" task and the "watch" loop both run on folderOpen; serialize their
# access to settings.json so they can never interleave writes and corrupt it.
lock_dir="$vscode_dir/.extensions-check.lock"
with_lock() {
    tries=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
        tries=$((tries + 1))
        if [ "$tries" -ge 200 ]; then
            rm -rf "$lock_dir"
        fi
        sleep 0.1
    done
    "$@"
    rc=$?
    rmdir "$lock_dir" 2>/dev/null
    return $rc
}

run_check() {
    "$python_exe" - "$base_settings" "$settings_file" "$marker_file" \
        "$extension_heartbeat" "$script_heartbeat" "$mode" "$watch_started" \
        "$guard_log" <<'PY'
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

if not violation_detected and mode in ("watch", "--watch") and time.time() - watch_started >= 20:
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
PY
}

if [ "$mode" = "--watch" ] || [ "$mode" = "watch" ]; then
    printf "Starting AI prevention watcher loop...\n" >&2
    while true; do
        with_lock run_check >/dev/null 2>&1 || true
        sleep 1
    done
else
    res=$(with_lock run_check)
    if [ "$res" = "VIOLATION" ]; then
        printf "⚠️ AI usage detected! Workspace glowing pink until instructor reset task is run. See Output > PQMF Exam Guard.\n" >&2
    elif [ "$res" = "SKIP" ]; then
        printf "… Settings file busy, retry the check in a moment.\n" >&2
    else
        printf "✓ Workspace settings validated. AI features disabled.\n" >&2
    fi
fi
