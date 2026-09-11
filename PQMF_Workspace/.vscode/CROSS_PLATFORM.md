# Cross-Platform AI Disabling Setup

## Overview

This workspace implements AI feature disabling across **Windows**, **macOS**, and **Linux** at both the editor and terminal/CLI levels.

## Platform-Specific Components

### macOS / Linux (Unix-like)

**Editor-level:**

- Terminal profile: `bash (restricted)` defined in settings
- RC file: `.vscode/terminal-rc.sh`
- Shadows: `copilot` bash function

**Validator (Exam workspace only):**

- Validator script: `.vscode/extensions.sh` (shell script)
- Python detection: Checks `$workspace/.venv/bin/python`, `$workspace/venv/bin/python`, `python` (venv-aware), fallback to `python3`
- Execution: `sh .vscode/extensions.sh [check|--reset|--watch]`

### Windows

**Editor-level:**

- Terminal profile: `PowerShell (restricted)` defined in settings
- RC file: `.vscode/terminal-rc.ps1`
- Shadows: `copilot` PowerShell function

**Validator (Exam workspace only):**

- Validator script: `.vscode/extensions.ps1` (PowerShell script)
- Python detection: Checks `$workspace\.venv\Scripts\python.exe`, `$workspace\venv\Scripts\python.exe`, `python` (venv-aware), fallback to `python3`
- Execution: `pwsh -NoProfile -Command "& '.vscode\extensions.ps1' [check|reset|watch]"`

## Files Deployed

### Both Workspaces (PQMF_Workspace + PQMF_ExamWorkspace)

**Editor settings (base + generated):**

- `settings.base.json` — Immutable policy with terminal profiles for all platforms
- `settings.json` — Generated from base, applied on workspace open (validator regenerates on PQMF_ExamWorkspace)

**Terminal RC files:**

- `.vscode/terminal-rc.sh` — Unix/macOS/Linux terminal disabler
- `.vscode/terminal-rc.ps1` — Windows PowerShell terminal disabler

**Extension configuration:**

- `extensions.json` — Workspace extension recommendations/blacklist

### PQMF_ExamWorkspace Only

**Validator & tasks:**

- `.vscode/extensions.sh` — Unix/macOS/Linux validator (checks Python in venv first)
- `.vscode/extensions.ps1` — Windows PowerShell validator (checks Python in venv first)
- `.vscode/tasks.json` — Platform-aware tasks that invoke correct validator based on OS

## Settings Structure

### Terminal Profiles in settings.json

```json
{
  "terminal.integrated.profiles.osx": {
    "bash (restricted)": {
      "path": "/bin/bash",
      "args": ["--rcfile", "${workspaceFolder}/.vscode/terminal-rc.sh", "-i"]
    }
  },
  "terminal.integrated.profiles.linux": {
    "bash (restricted)": {
      "path": "/bin/bash",
      "args": ["--rcfile", "${workspaceFolder}/.vscode/terminal-rc.sh", "-i"]
    }
  },
  "terminal.integrated.profiles.windows": {
    "PowerShell (restricted)": {
      "path": "pwsh",
      "args": [
        "-NoProfile",
        "-Command",
        ". '${workspaceFolder}\\.vscode\\terminal-rc.ps1'"
      ],
      "overrideName": true
    }
  },
  "terminal.integrated.defaultProfile.osx": "bash (restricted)",
  "terminal.integrated.defaultProfile.linux": "bash (restricted)",
  "terminal.integrated.defaultProfile.windows": "PowerShell (restricted)"
}
```

## Python Interpreter Detection

Both validators (shell and PowerShell) check for Python in this order:

1. **Workspace virtual environment** (venv-aware)
   - Unix/Linux/macOS: `$workspace/.venv/bin/python` or `$workspace/venv/bin/python`
   - Windows: `$workspace\.venv\Scripts\python.exe` or `$workspace\venv\Scripts\python.exe`

2. **System Python** (respects activated venv)
   - `python` (uses PATH, which includes activated venv)

3. **Fallback** (for systems without `python` alias)
   - `python3`

This ensures the validator works correctly whether Python is:

- Installed system-wide
- Activated in a virtual environment
- Not explicitly activated (venv exists but not sourced)

## CLI Disabling Mechanism

Both Unix and Windows use the same principle but different implementation:

### Unix (bash function)

```bash
copilot() {
  echo "The 'copilot' command is disabled in this workspace." >&2
  return 1
}
```

- Bash checks function definitions before PATH
- Shadows any `copilot` executable in PATH

### Windows (PowerShell function)

```powershell
function copilot {
    Write-Error "The 'copilot' command is disabled in this workspace." -ErrorAction Stop
}
```

- PowerShell checks functions before aliases before PATH
- Shadows any `copilot.exe` or `copilot` in PATH

## Tasks (PQMF_ExamWorkspace)

Platform-aware tasks in `.vscode/tasks.json`:

- **"Restricted mode: check AI extensions"** — Runs on `folderOpen`
  - Windows: `pwsh -NoProfile -Command "& '.vscode\extensions.ps1' 'check'"`
  - Unix/macOS/Linux: `sh ".vscode/extensions.sh" check`

- **"Restricted mode: watch AI usage"** — Continuous monitoring (background)
  - Windows: `pwsh -NoProfile -Command "& '.vscode\extensions.ps1' 'watch'"`
  - Unix/macOS/Linux: `sh ".vscode/extensions.sh" --watch`

- **"Restricted mode: instructor reset"** — Manual recovery task
  - Windows: `pwsh -NoProfile -Command "& '.vscode\extensions.ps1' 'reset'"`
  - Unix/macOS/Linux: `sh ".vscode/extensions.sh" --reset`

## Behavior Differences

### PQMF_Workspace (Everyday / No Enforcement)

- AI disabled in editor settings
- Terminal CLI copilot shadowed
- **No validator** — students can modify settings if they bypass the workspace scope
- Trust-based approach

### PQMF_ExamWorkspace (Enforced / Exam Mode)

- AI disabled in editor settings
- Terminal CLI copilot shadowed
- **Validator runs on folder open** — regenerates settings.json from base, ensures AI settings intact
- If violation detected: workspace turns pink (statusBar/titleBar changed to `#ff1493`)
- Instructor can manually reset with "Restricted mode: instructor reset" task
- Enforced approach

## Testing Checklist

- [ ] macOS: Open bash terminal, try `copilot` command → should be rejected
- [ ] Linux: Open bash terminal, try `copilot` command → should be rejected
- [ ] Windows: Open PowerShell terminal, try `copilot` command → should be rejected
- [ ] PQMF_ExamWorkspace on any OS: Modify settings.json to enable AI → workspace turns pink on next open
- [ ] PQMF_ExamWorkspace: Run "Restricted mode: instructor reset" task → settings regenerated, colors normal
- [ ] All platforms: Verify `github.copilot.enable: {"*": false}` blocks inline suggestions in editor
