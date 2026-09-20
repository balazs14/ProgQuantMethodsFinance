#!/bin/sh
# Mac/Linux validator: ensures AI features remain disabled.
# Thin wrapper that delegates the policy logic to the shared, cross-platform
# guard-check.py / guard-reset.py (identical to the Windows path). Pure ASCII.
# Run on workspace open or manually via task.
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vscode_dir="$workspace_root/.vscode"
base_settings="$vscode_dir/settings.base.json"
settings_file="$vscode_dir/settings.json"
marker_file="$vscode_dir/.ai-extension-detected"
extension_heartbeat="$vscode_dir/.pqmf-exam-guard-extension-heartbeat"
script_heartbeat="$vscode_dir/.pqmf-exam-guard-script-heartbeat"
guard_log="$vscode_dir/.pqmf-exam-guard.log"

# Normalize mode to the same set the shared python expects: check | reset | watch.
raw_mode="${1:-check}"
case "$raw_mode" in
    --reset|reset) mode="reset" ;;
    --watch|watch) mode="watch" ;;
    *)             mode="check" ;;
esac

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

if [ "$mode" = "reset" ]; then
    # Give the extension watchdog time to reconstruct any deleted protected
    # files before this legacy reset path clears the persistent marker.
    sleep 10
    rm -f "$marker_file"
    "$python_exe" "$vscode_dir/guard-reset.py" "$base_settings" "$settings_file"
    chmod u+w "$guard_log" 2>/dev/null || true
    printf '%s [script] RESET Legacy instructor reset restored settings and normal colors.\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$guard_log" 2>/dev/null || true
    printf "[OK] Workspace reset complete: AI features disabled and normal colors restored.\n" >&2
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
    "$python_exe" "$vscode_dir/guard-check.py" "$base_settings" "$settings_file" \
        "$marker_file" "$extension_heartbeat" "$script_heartbeat" "$mode" \
        "$watch_started" "$guard_log"
}

if [ "$mode" = "watch" ]; then
    printf "Starting AI prevention watcher loop...\n" >&2
    while true; do
        with_lock run_check >/dev/null 2>&1 || true
        sleep 1
    done
else
    res=$(with_lock run_check)
    if [ "$res" = "VIOLATION" ]; then
        printf "[!] AI usage detected! Workspace glowing pink until instructor reset task is run. See Output > PQMF Exam Guard.\n" >&2
    elif [ "$res" = "SKIP" ]; then
        printf "... Settings file busy, retry the check in a moment.\n" >&2
    else
        printf "[OK] Workspace settings validated. AI features disabled.\n" >&2
    fi
fi
