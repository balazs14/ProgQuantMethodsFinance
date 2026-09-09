#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
settings_file="$workspace_root/.vscode/settings.json"
marker_file="$workspace_root/.vscode_restricted/.ai-extension-detected"

ai_pattern='(github\.copilot|codeium|tabnine|continue|roo-cline|claude-dev|blackbox|amazon-q|geminicodeassist)'
installed=$(code --list-extensions 2>/dev/null || true)

mkdir -p "$workspace_root/.vscode"

if printf '%s\n' "$installed" | grep -Eiq "$ai_pattern"; then
  cat > "$settings_file" <<'JSON'
{
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#ff00aa",
    "titleBar.activeForeground": "#ffffff",
    "activityBar.background": "#ff00aa",
    "activityBar.foreground": "#ffffff",
    "statusBar.background": "#ff00aa",
    "statusBar.foreground": "#ffffff",
    "statusBarItem.prominentBackground": "#7a0052",
    "statusBarItem.prominentForeground": "#ffffff"
  }
}
JSON
  touch "$marker_file"
else
  rm -f "$marker_file"
fi
