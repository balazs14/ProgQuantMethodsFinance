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

# Startup settle grace: right after the workspace opens, VS Code, the launcher, and
# the guard extension may all be writing settings.json, so a single read can look
# like tampering. Skip settings-tamper detection until the session has settled; the
# guard extension enforces settings during this window, so there is no gap.
# Match the extension's grace: pause settings-tamper detection while the launcher's
# setup marker (.pqmf-exam-guard-setup at the project root) is fresh (< 60s). This
# covers the startup settle window when VS Code, the launcher, and the extension are
# all writing settings.json, without leaving a gap (the extension enforces meanwhile).
project_root = os.path.dirname(os.path.dirname(os.path.abspath(settings_path)))
setup_marker = os.path.join(project_root, ".pqmf-exam-guard-setup")
try:
    setup_in_progress = (time.time() - os.path.getmtime(setup_marker)) <= 60
except OSError:
    setup_in_progress = False
settled = not setup_in_progress

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

if not violation_detected and settled and any(
    current_settings.get(key) != base_settings.get(key) for key in policy_keys
):
    violation_detected = True
    violation_reason = "Protected exam settings were changed."

if not violation_detected and settled and any(
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
