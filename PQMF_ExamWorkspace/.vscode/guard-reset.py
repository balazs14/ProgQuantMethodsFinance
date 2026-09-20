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
