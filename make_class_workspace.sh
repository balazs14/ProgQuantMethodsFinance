
# Polyglot launcher: valid as both a Windows batch script and a bash script.
# ":;" lines are no-op labels in cmd.exe but run as bash statements; bash exits
# before reaching the batch-only section below. The workspace contents are
# embedded as base64 payloads after marker lines, so a single downloaded file
# can install the exam guard (for exam workspaces), extract, and open itself.
read -r -d '' ROBUST_LAUNCHER_TEMPLATE << 'EOF'
:; #!/usr/bin/env bash
:; set -euo pipefail
:; ASSIGNMENT="__ASSIGNMENT__"
:; alert() { osascript -e "display alert \"$1\" message \"$2\"" >/dev/null 2>&1; }
:; echo "Checking prerequisites..."
:; CODE_CMD=""
:; if command -v code >/dev/null 2>&1; then CODE_CMD="code"; elif [ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]; then CODE_CMD="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; fi
:; if [ -z "$CODE_CMD" ]; then alert "VS Code not found" "VS Code could not be found on this computer. Please install it from https://code.visualstudio.com/ and try again."; exit 1; fi
:; PYTHON_CMD=""
:; if command -v python3 >/dev/null 2>&1; then PYTHON_CMD="python3"; elif command -v python >/dev/null 2>&1; then PYTHON_CMD="python"; fi
:; if [ -z "$PYTHON_CMD" ]; then alert "Python not found" "Python could not be found on this computer. Please install it from https://www.python.org/downloads/ and try again."; exit 1; fi
:; PYTHON_PATH=$(command -v "$PYTHON_CMD")
:; PACKAGES="__PACKAGES__"
:; if "$PYTHON_CMD" -c "import ${PACKAGES// /, }" >/dev/null 2>&1; then echo "Required Python packages already available."; else echo "Installing required Python packages..."; if ! "$PYTHON_CMD" -m pip install --quiet --disable-pip-version-check --user $PACKAGES; then alert "Package installation failed" "Could not install required Python packages ($PACKAGES). Please install them manually."; exit 1; fi; fi
:; if ! "$PYTHON_CMD" -m ipykernel install --user --name pqmf-python --display-name "Python (PQMF)" >/dev/null; then alert "Kernel setup failed" "Could not configure the Python notebook kernel."; exit 1; fi
:; echo "Setting up workspace..."
:; SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
:; SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
:; GUARD_MARKER_LINE=$(grep -n '^__EXAM_GUARD_PAYLOAD_BELOW__$' "$SCRIPT_PATH" | head -n 1 | cut -d: -f1)
:; WORKSPACE_MARKER_LINE=$(grep -n '^__WORKSPACE_PAYLOAD_BELOW__$' "$SCRIPT_PATH" | head -n 1 | cut -d: -f1)
:; if [ -z "$GUARD_MARKER_LINE" ] || [ -z "$WORKSPACE_MARKER_LINE" ]; then alert "Workspace data missing" "Could not find the embedded payload markers in this launcher file."; exit 1; fi
:; WORKDIR=$(mktemp -d)
:; TMP_ZIP="$WORKDIR/payload.zip"
:; TMP_VSIX="$WORKDIR/pqmf-exam-guard.vsix"
:; sed -n "$((GUARD_MARKER_LINE + 1)),$((WORKSPACE_MARKER_LINE - 1))p" "$SCRIPT_PATH" | tr -d '\r\n' > "$WORKDIR/exam-guard.b64"
:; tail -n +$((WORKSPACE_MARKER_LINE + 1)) "$SCRIPT_PATH" > "$WORKDIR/payload.b64"
:; if [ "$(uname)" = "Darwin" ]; then base64 -D -i "$WORKDIR/payload.b64" -o "$TMP_ZIP"; else base64 -d "$WORKDIR/payload.b64" > "$TMP_ZIP"; fi
:; EXTRACT_DIR="$SCRIPT_DIR/${ASSIGNMENT}_OPEN"
:; mkdir -p "$EXTRACT_DIR"
:; SETUP_PROJECT=""
:; SETUP_HAD_VIOLATION=0
:; CONTENT_ACTION="fresh"
:; if [ -s "$WORKDIR/exam-guard.b64" ]; then EXISTING_VSCODE=$(find "$EXTRACT_DIR" -type d -name ".vscode" -print -quit); if [ -n "$EXISTING_VSCODE" ]; then SETUP_PROJECT=$(dirname "$EXISTING_VSCODE"); SETUP_CHOICE=$(osascript -e 'button returned of (display dialog "An exam workspace already exists. Keep its current Python/notebook work, or replace it with fresh packaged copies? The guard configuration will be repaired either way." with title "Existing exam workspace" buttons {"Overwrite With Fresh Copies", "Keep Existing"} default button "Keep Existing" cancel button "Keep Existing" with icon caution)' 2>/dev/null || printf 'Keep Existing'); if [ "$SETUP_CHOICE" = "Overwrite With Fresh Copies" ]; then CONTENT_ACTION="overwrite"; else CONTENT_ACTION="keep"; fi; if [ -f "$EXISTING_VSCODE/.pqmf-exam-guard.log" ]; then tail -c 1048576 "$EXISTING_VSCODE/.pqmf-exam-guard.log" > "$WORKDIR/preserved-guard.log"; fi; if [ -f "$EXISTING_VSCODE/.ai-extension-detected" ]; then SETUP_HAD_VIOLATION=1; cp "$EXISTING_VSCODE/.ai-extension-detected" "$WORKDIR/preserved-violation"; fi; date +%s > "$SETUP_PROJECT/.pqmf-exam-guard-setup"; if [ "$CONTENT_ACTION" = "keep" ]; then mkdir -p "$WORKDIR/preserved-content"; find "$SETUP_PROJECT" \( -path "$SETUP_PROJECT/.venv" -o -path "$SETUP_PROJECT/venv" -o -path "$SETUP_PROJECT/.vscode" \) -prune -o -type f \( -name "*.py" -o -name "*.ipynb" \) -print0 | while IFS= read -r -d '' CONTENT_FILE; do CONTENT_REL=${CONTENT_FILE#"$SETUP_PROJECT/"}; mkdir -p "$WORKDIR/preserved-content/$(dirname "$CONTENT_REL")"; cp "$CONTENT_FILE" "$WORKDIR/preserved-content/$CONTENT_REL"; done; fi; find "$SETUP_PROJECT" \( -path "$SETUP_PROJECT/.venv" -o -path "$SETUP_PROJECT/venv" -o -path "$SETUP_PROJECT/.vscode" \) -prune -o -type f \( -name "*.py" -o -name "*.ipynb" \) -exec chmod u+w {} +; find "$SETUP_PROJECT" \( -path "$SETUP_PROJECT/.venv" -o -path "$SETUP_PROJECT/venv" -o -path "$SETUP_PROJECT/.vscode" \) -prune -o -type f \( -name "*.py" -o -name "*.ipynb" \) -delete; chmod -R u+w "$EXISTING_VSCODE" 2>/dev/null || true; rm -rf "$EXISTING_VSCODE"; fi; fi
:; unzip -q -o "$TMP_ZIP" -d "$EXTRACT_DIR"
:; echo "Finding project folder..."
:; VSCODE_DIR=$(find "$EXTRACT_DIR" -type d -name ".vscode" -print -quit)
:; if [ -z "$VSCODE_DIR" ]; then alert "Project folder not found" "The workspace was extracted, but no .vscode folder was found."; open "$EXTRACT_DIR"; exit 1; fi
:; PROJECT_DIR=$(dirname "$VSCODE_DIR")
:; if [ -f "$WORKDIR/preserved-guard.log" ]; then cp "$WORKDIR/preserved-guard.log" "$PROJECT_DIR/.vscode/.pqmf-exam-guard.log"; fi
:; if [ -f "$WORKDIR/preserved-violation" ]; then cp "$WORKDIR/preserved-violation" "$PROJECT_DIR/.vscode/.ai-extension-detected"; fi
:; if [ "$CONTENT_ACTION" = "keep" ]; then find "$PROJECT_DIR" \( -path "$PROJECT_DIR/.venv" -o -path "$PROJECT_DIR/venv" -o -path "$PROJECT_DIR/.vscode" \) -prune -o -type f \( -name "*.py" -o -name "*.ipynb" \) -delete; cp -R "$WORKDIR/preserved-content/." "$PROJECT_DIR/"; fi
:; printf '%s [launcher] SESSION Workspace refreshed; content choice: %s.\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$CONTENT_ACTION" >> "$PROJECT_DIR/.vscode/.pqmf-exam-guard.log"
:; find "$PROJECT_DIR" -type f -name "*.ipynb" -exec "$PYTHON_CMD" -c "import hashlib,json,sys; p=sys.argv[1]; d=json.load(open(p)); d.setdefault('metadata', dict())['vscode'] = {'interpreter': {'hash': hashlib.sha256(sys.argv[2].encode()).hexdigest()}}; json.dump(d, open(p, 'w'), indent=1)" {} "$PYTHON_PATH" \;
:; if [ -f "$PROJECT_DIR/.vscode/settings.json" ]; then "$PYTHON_CMD" -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['python.defaultInterpreterPath']=sys.argv[2]; json.dump(d, open(p,'w'), indent=2)" "$PROJECT_DIR/.vscode/settings.json" "$PYTHON_PATH"; fi
:; if [ -s "$WORKDIR/exam-guard.b64" ]; then echo "Installing exam guard extension..."; if [ "$(uname)" = "Darwin" ]; then base64 -D -i "$WORKDIR/exam-guard.b64" -o "$TMP_VSIX"; else base64 -d "$WORKDIR/exam-guard.b64" > "$TMP_VSIX"; fi; if ! "$CODE_CMD" --install-extension "$TMP_VSIX" --force >/dev/null 2>&1; then rm -rf "$WORKDIR"; alert "Extension setup failed" "Could not install the bundled exam guard extension. The exam workspace will not be opened."; exit 1; fi; fi
:; if [ -s "$WORKDIR/exam-guard.b64" ]; then rm -f "$PROJECT_DIR/.vscode/.pqmf-exam-guard-extension-heartbeat" "$PROJECT_DIR/.vscode/.pqmf-exam-guard-script-heartbeat"; rm -rf "$PROJECT_DIR/.vscode/.extensions-check.lock"; find "$PROJECT_DIR/.vscode" -type f ! -name "settings.json" ! -name ".ai-extension-detected" ! -name ".ai-extension-detected.outside-file" ! -name ".pqmf-exam-guard-extension-heartbeat" ! -name ".pqmf-exam-guard-script-heartbeat" ! -name ".pqmf-exam-guard.log" -exec chmod a-w {} +; if [ "$(uname)" = "Darwin" ]; then chflags hidden "$PROJECT_DIR/.vscode"; fi; fi
:; if [ -n "$SETUP_PROJECT" ]; then rm -f "$SETUP_PROJECT/.pqmf-exam-guard-setup"; if [ "$SETUP_HAD_VIOLATION" -eq 0 ] && [ -f "$PROJECT_DIR/.vscode/.ai-extension-detected" ]; then SETUP_REASON=$(head -n 1 "$PROJECT_DIR/.vscode/.ai-extension-detected"); case "$SETUP_REASON" in "Protected exam file "*|"Protected exam settings were changed.") rm -f "$PROJECT_DIR/.vscode/.ai-extension-detected" ;; esac; fi; fi
:; rm -rf "$WORKDIR"
:; echo "Opening: $PROJECT_DIR"
:; "$CODE_CMD" --disable-workspace-trust --reuse-window "$PROJECT_DIR"
:; if [ "$(uname)" = "Darwin" ]; then osascript -e "tell application \"Terminal\" to close (every window whose selected tab's tty is \"$(tty)\")" >/dev/null 2>&1 || true; fi
:; exit 0

@echo off
setlocal

REM =========================================================
REM CHANGE ONLY THIS LINE FOR EACH MOODLE ASSIGNMENT
REM =========================================================
set "ASSIGNMENT=__ASSIGNMENT__"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$python = Get-Command python -ErrorAction SilentlyContinue; if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }; if (-not $python) { exit 1 }; & $python.Source -c 'import ipykernel' 2>$null; if ($LASTEXITCODE -ne 0) { & $python.Source -m pip install --quiet --disable-pip-version-check --user ipykernel; if ($LASTEXITCODE -ne 0) { exit 1 } }; & $python.Source -m ipykernel install --user --name pqmf-python --display-name 'Python (PQMF)'; exit $LASTEXITCODE"
if errorlevel 1 (
    echo Could not configure the Python notebook kernel.
    pause
    exit /b 1
)

if errorlevel 1 exit /b 1

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; if ('%ASSIGNMENT%' -like '*_exam') {$extractRoot=Join-Path (Split-Path -Parent '%~f0') ('%ASSIGNMENT%_OPEN'); $existingVscode=Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue|Where-Object {$_.Name -eq '.vscode'}|Select-Object -First 1; if ($existingVscode) {$project=$existingVscode.Parent.FullName; $contentChoice='keep'; try {Add-Type -AssemblyName PresentationFramework; $choice=[System.Windows.MessageBox]::Show('An exam workspace already exists. Choose Yes to overwrite its Python and notebook files with fresh packaged copies. Choose No to keep the existing files. The guard configuration will be repaired either way.','Existing exam workspace',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning,[System.Windows.MessageBoxResult]::No); if ($choice -eq [System.Windows.MessageBoxResult]::Yes) {$contentChoice='overwrite'}} catch {$contentChoice='keep'}; $choicePath=Join-Path $project '.pqmf-exam-guard-content-choice'; Set-Content -LiteralPath $choicePath -Value $contentChoice; $log=Join-Path $existingVscode.FullName '.pqmf-exam-guard.log'; $preservedLog=Join-Path $project '.pqmf-exam-guard-preserved-log'; if (Test-Path -LiteralPath $log) {$bytes=[IO.File]::ReadAllBytes($log); $start=[Math]::Max(0,$bytes.Length-1048576); $kept=New-Object byte[] ($bytes.Length-$start); [Array]::Copy($bytes,$start,$kept,0,$kept.Length); [IO.File]::WriteAllBytes($preservedLog,$kept)} else {Remove-Item -LiteralPath $preservedLog -Force -ErrorAction SilentlyContinue}; $marker=Join-Path $existingVscode.FullName '.ai-extension-detected'; $preservedViolation=Join-Path $project '.pqmf-exam-guard-preserved-violation'; if (Test-Path -LiteralPath $marker) {Copy-Item -LiteralPath $marker -Destination $preservedViolation -Force} else {Remove-Item -LiteralPath $preservedViolation -Force -ErrorAction SilentlyContinue}; Set-Content -LiteralPath (Join-Path $project '.pqmf-exam-guard-setup') -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()); $preservedContent=Join-Path $project '.pqmf-exam-guard-preserved-content'; Remove-Item -LiteralPath $preservedContent -Recurse -Force -ErrorAction SilentlyContinue; $contentFiles=@(Get-ChildItem -LiteralPath $project -File -Recurse -Force -Include '*.py','*.ipynb'|Where-Object {$_.FullName -notlike (Join-Path $project '.venv\*') -and $_.FullName -notlike (Join-Path $project 'venv\*') -and $_.FullName -notlike (Join-Path $project '.vscode\*')}); if ($contentChoice -eq 'keep') {New-Item -ItemType Directory -Path $preservedContent -Force|Out-Null; foreach ($file in $contentFiles) {$relative=$file.FullName.Substring($project.Length).TrimStart([char]92,[char]47); $destination=Join-Path $preservedContent $relative; New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null; Copy-Item -LiteralPath $file.FullName -Destination $destination -Force}}; foreach ($file in $contentFiles) {$file.IsReadOnly=$false; Remove-Item -LiteralPath $file.FullName -Force}; Get-ChildItem -LiteralPath $existingVscode.FullName -Force -Recurse -ErrorAction SilentlyContinue|Where-Object {-not $_.PSIsContainer}|ForEach-Object {$_.IsReadOnly=$false}; Remove-Item -LiteralPath $existingVscode.FullName -Recurse -Force}}"
if errorlevel 1 exit /b 1

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $selfPath='%~f0'; $scriptDir=Split-Path -Parent $selfPath; $python=Get-Command python -ErrorAction SilentlyContinue; if (-not $python) {$python=Get-Command python3 -ErrorAction SilentlyContinue}; if (-not $python) {exit 1}; $packages='__PACKAGES__' -split ' '; $missing=@($packages | Where-Object { try { & $python.Source -c "import $_" 2>$null; $LASTEXITCODE -ne 0 } catch { $true } }); if ($missing.Count -gt 0) { & $python.Source -m pip install --quiet --disable-pip-version-check --user @missing; if ($LASTEXITCODE -ne 0) {exit 1} }; $code=Get-Command code -ErrorAction SilentlyContinue; if (-not $code) {$locations=@((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),(Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe')); $code=$locations|Where-Object {$_ -and (Test-Path -LiteralPath $_)}|Select-Object -First 1}; if (-not $code) {exit 1}; if ($code -is [System.Management.Automation.CommandInfo]) {$codePath=$code.Source} else {$codePath=[string]$code}; $lines=Get-Content -LiteralPath $selfPath; $guardMarker=($lines|Select-String -Pattern '^__EXAM_GUARD_PAYLOAD_BELOW__$'|Select-Object -First 1).LineNumber; $workspaceMarker=($lines|Select-String -Pattern '^__WORKSPACE_PAYLOAD_BELOW__$'|Select-Object -First 1).LineNumber; if (-not $guardMarker -or -not $workspaceMarker) {exit 1}; $guardPayload=''; if ($workspaceMarker -gt ($guardMarker+1)) {$guardPayload=-join $lines[$guardMarker..($workspaceMarker-2)]}; $payload=-join $lines[$workspaceMarker..($lines.Count-1)]; $tmpRoot=Join-Path $env:TEMP ('pqmf_'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $tmpRoot|Out-Null; $tmpZip=Join-Path $tmpRoot 'payload.zip'; [IO.File]::WriteAllBytes($tmpZip,[Convert]::FromBase64String($payload)); $extractRoot=Join-Path $scriptDir ('%ASSIGNMENT%_OPEN'); if (-not (Test-Path -LiteralPath $extractRoot)) { New-Item -ItemType Directory -Path $extractRoot|Out-Null }; Expand-Archive -LiteralPath $tmpZip -DestinationPath $extractRoot -Force; $project=(Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse|Where-Object {$_.Name -eq '.vscode'}|Select-Object -First 1).Parent.FullName; Get-ChildItem -LiteralPath $project -Filter *.ipynb -File -Recurse|Where-Object {$_.FullName -notlike (Join-Path $project '.pqmf-exam-guard-preserved-content\*')}|ForEach-Object {& $python.Source -c \"import hashlib,json,sys; p=sys.argv[1]; d=json.load(open(p)); d.setdefault('metadata', dict())['vscode']={'interpreter':{'hash':hashlib.sha256(sys.argv[2].encode()).hexdigest()}}; json.dump(d,open(p,'w'),indent=1)\" $_.FullName $python.Source}; $settings=Join-Path $project '.vscode\settings.json'; if (Test-Path $settings) {$d=Get-Content $settings -Raw|ConvertFrom-Json; $d|Add-Member -NotePropertyName 'python.defaultInterpreterPath' -NotePropertyValue $python.Source -Force; $d|ConvertTo-Json -Depth 20|Set-Content $settings}; if ($guardPayload) {$tmpVsix=Join-Path $tmpRoot 'pqmf-exam-guard.vsix'; [IO.File]::WriteAllBytes($tmpVsix,[Convert]::FromBase64String($guardPayload)); & $codePath --install-extension $tmpVsix --force | Out-Null; if ($LASTEXITCODE -ne 0) {Remove-Item $tmpRoot -Recurse -Force; Write-Error 'Could not install the bundled exam guard extension. The exam workspace will not be opened.'; exit 1}; $vscodePath=Join-Path $project '.vscode'; Get-ChildItem -LiteralPath $vscodePath -File|Where-Object {$_.Name -ne 'settings.json'}|ForEach-Object {$_.IsReadOnly=$true}; $vscodeItem=Get-Item -LiteralPath $vscodePath -Force; $vscodeItem.Attributes=$vscodeItem.Attributes -bor [IO.FileAttributes]::Hidden}; Remove-Item $tmpRoot -Recurse -Force"
if errorlevel 1 (
    echo Could not set up the workspace. The workspace was not opened.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $extractRoot=Join-Path (Split-Path -Parent '%~f0') ('%ASSIGNMENT%_OPEN'); $vscodePath=(Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse -Force|Where-Object {$_.Name -eq '.vscode'}|Select-Object -First 1).FullName; if (-not $vscodePath) {exit 1}; $project=Split-Path -Parent $vscodePath; if ('%ASSIGNMENT%' -like '*_exam') {$preservedLog=Join-Path $project '.pqmf-exam-guard-preserved-log'; $preservedViolation=Join-Path $project '.pqmf-exam-guard-preserved-violation'; $preservedContent=Join-Path $project '.pqmf-exam-guard-preserved-content'; $choicePath=Join-Path $project '.pqmf-exam-guard-content-choice'; $contentChoice='fresh'; if (Test-Path -LiteralPath $choicePath) {$contentChoice=(Get-Content -LiteralPath $choicePath -TotalCount 1).Trim(); if ($contentChoice -notin @('keep','overwrite')) {$contentChoice='keep'}}; if ($contentChoice -eq 'keep' -and (Test-Path -LiteralPath $preservedContent)) {$freshFiles=@(Get-ChildItem -LiteralPath $project -File -Recurse -Force -Include '*.py','*.ipynb'|Where-Object {$_.FullName -notlike (Join-Path $project '.venv\*') -and $_.FullName -notlike (Join-Path $project 'venv\*') -and $_.FullName -notlike (Join-Path $project '.vscode\*') -and $_.FullName -notlike (Join-Path $preservedContent '*')}); foreach ($file in $freshFiles) {$file.IsReadOnly=$false; Remove-Item -LiteralPath $file.FullName -Force}; Get-ChildItem -LiteralPath $preservedContent -Force|Copy-Item -Destination $project -Recurse -Force}; $python=Get-Command python -ErrorAction SilentlyContinue; if (-not $python) {$python=Get-Command python3 -ErrorAction SilentlyContinue}; if ($python) {Get-ChildItem -LiteralPath $project -Filter *.ipynb -File -Recurse|Where-Object {$_.FullName -notlike (Join-Path $preservedContent '*')}|ForEach-Object {& $python.Source -c \"import hashlib,json,sys; p=sys.argv[1]; d=json.load(open(p)); d.setdefault('metadata', dict())['vscode']={'interpreter':{'hash':hashlib.sha256(sys.argv[2].encode()).hexdigest()}}; json.dump(d,open(p,'w'),indent=1)\" $_.FullName $python.Source}}; $hadPreexisting=Test-Path -LiteralPath $preservedViolation; if (Test-Path -LiteralPath $preservedLog) {Move-Item -LiteralPath $preservedLog -Destination (Join-Path $vscodePath '.pqmf-exam-guard.log') -Force}; if ($hadPreexisting) {Move-Item -LiteralPath $preservedViolation -Destination (Join-Path $vscodePath '.ai-extension-detected') -Force}; Add-Content -LiteralPath (Join-Path $vscodePath '.pqmf-exam-guard.log') -Value "$([DateTime]::UtcNow.ToString('o')) [launcher] SESSION Workspace refreshed; content choice: $contentChoice."; $runtimeNames=@('settings.json','.ai-extension-detected','.ai-extension-detected.outside-file','.pqmf-exam-guard-extension-heartbeat','.pqmf-exam-guard-script-heartbeat','.pqmf-exam-guard.log'); foreach ($name in $runtimeNames) {$item=Get-Item -LiteralPath (Join-Path $vscodePath $name) -Force -ErrorAction SilentlyContinue; if ($item) {$item.IsReadOnly=$false}}; foreach ($name in @('.pqmf-exam-guard-extension-heartbeat','.pqmf-exam-guard-script-heartbeat')) {Remove-Item -LiteralPath (Join-Path $vscodePath $name) -Force -ErrorAction SilentlyContinue}; Remove-Item -LiteralPath (Join-Path $vscodePath '.extensions-check.lock') -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath (Join-Path $project '.pqmf-exam-guard-setup') -Force -ErrorAction SilentlyContinue; if (-not $hadPreexisting) {$marker=Join-Path $vscodePath '.ai-extension-detected'; if (Test-Path -LiteralPath $marker) {$reason=Get-Content -LiteralPath $marker -TotalCount 1; if ($reason -like 'Protected exam file *' -or $reason -eq 'Protected exam settings were changed.') {$markerItem=Get-Item -LiteralPath $marker -Force; $markerItem.IsReadOnly=$false; Remove-Item -LiteralPath $marker -Force}}}; Remove-Item -LiteralPath $preservedLog,$preservedViolation,$choicePath -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $preservedContent -Recurse -Force -ErrorAction SilentlyContinue}; $code=Get-Command code -ErrorAction SilentlyContinue; if (-not $code) {$locations=@((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),(Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe')); $code=$locations|Where-Object {$_ -and (Test-Path -LiteralPath $_)}|Select-Object -First 1}; if (-not $code) {exit 1}; if ($code -is [System.Management.Automation.CommandInfo]) {$codePath=$code.Source} else {$codePath=[string]$code}; Start-Process -FilePath $codePath -ArgumentList @('--disable-workspace-trust','--reuse-window',$project)"
if errorlevel 1 (
    echo Could not set up the workspace. The workspace was not opened.
    pause
    exit /b 1
)

endlocal
exit /b 0
__EXAM_GUARD_PAYLOAD_BELOW__
__EXAM_GUARD_PAYLOAD__
__WORKSPACE_PAYLOAD_BELOW__
EOF

REQUIRED_PACKAGES="ipykernel numpy pandas matplotlib"
EXAM_GUARD_SOURCE_DIR="tools/pqmf-exam-guard"
EXAM_GUARD_STAGE_DIR="tools/pqmf-exam-guard-vsix"
EXAM_GUARD_VSIX="PQMF_ExamWorkspace/.vscode/pqmf-exam-guard.vsix"

function build_exam_guard_vsix() {
    workspace_template=${1:-PQMF_ExamWorkspace}
    echo "==> Building exam guard VSIX"
    cp "$EXAM_GUARD_SOURCE_DIR/extension.js" \
        "$EXAM_GUARD_STAGE_DIR/extension/extension.js" || return 1
    cp "$EXAM_GUARD_SOURCE_DIR/package.json" \
        "$EXAM_GUARD_STAGE_DIR/extension/package.json" || return 1

    python3 - "$EXAM_GUARD_STAGE_DIR" "$workspace_template" <<'PY' || return 1
import hashlib
import json
import pathlib
import re
import shutil
import stat
import sys

stage = pathlib.Path(sys.argv[1])
workspace_template = pathlib.Path(sys.argv[2])
snapshot_root = stage / "extension" / "workspace-snapshot"
if snapshot_root.exists():
    shutil.rmtree(snapshot_root)
snapshot_root.mkdir(parents=True)

excluded_names = {
    "settings.json",
    "pqmf-exam-guard.vsix",
    ".ai-extension-detected",
    ".ai-extension-detected.outside-file",
    ".pqmf-exam-guard-extension-heartbeat",
    ".pqmf-exam-guard-script-heartbeat",
    ".pqmf-exam-guard.log",
    ".DS_Store",
}
protected_files = []
for source in (workspace_template / ".vscode").rglob("*"):
    if not source.is_file() or source.name in excluded_names:
        continue
    if ".extensions-check.lock" in source.parts:
        continue
    relative_path = source.relative_to(workspace_template).as_posix()
    protected_mode = stat.S_IMODE(source.stat().st_mode) & ~0o222
    target = snapshot_root / relative_path
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    target.chmod(protected_mode)
    protected_files.append((relative_path, protected_mode))

manifest = {
    "files": {
        relative_path: {
            "sha256": hashlib.sha256(
                (workspace_template / relative_path).read_bytes()
            ).hexdigest(),
            "mode": protected_mode,
        }
        for relative_path, protected_mode in protected_files
    }
}
(stage / "extension" / "guard-manifest.json").write_text(
    json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
)

package = json.loads((stage / "extension" / "package.json").read_text())
vsix_manifest_path = stage / "extension.vsixmanifest"
vsix_manifest = vsix_manifest_path.read_text(encoding="utf-8")
vsix_manifest = re.sub(
    r'(<Identity\b[^>]*\bVersion=")[^"]+("[^>]*>)',
    rf'\g<1>{package["version"]}\g<2>',
    vsix_manifest,
    count=1,
)
vsix_manifest_path.write_text(vsix_manifest, encoding="utf-8")
PY

    vsix_workdir=$(mktemp -d)
    tmp_vsix="$vsix_workdir/pqmf-exam-guard.vsix"
    (cd "$EXAM_GUARD_STAGE_DIR" && \
        zip -X -rq "$tmp_vsix" '[Content_Types].xml' extension.vsixmanifest extension) || return 1
    mv "$tmp_vsix" "$EXAM_GUARD_VSIX" || return 1
    rm -rf "$vsix_workdir"
}

function make_workspace() {
    material="$1"
    classnum=$2
    group=$3
    examclass=$4
    extratag=${5:-}
    protected_defaults_json=${6:-}

    case "$examclass" in
        exam) origin=ExamWorkspace ;;
        class) origin=Workspace ;;
        *) echo "make_workspace: examclass must be 'exam' or 'class', got '$examclass'" >&2; return 1 ;;
    esac

    tag="${classnum}"
    [[ -n "$group" ]] && tag="${tag}_${group}"
    tag="${tag}_${examclass}"
    if [[ -n "$extratag" ]]; then
        case "$extratag" in
            _*) tag="${tag}${extratag}" ;;
            *) tag="${tag}_${extratag}" ;;
        esac
    fi

    foldername="Workspace_${tag}"
    launchername="${tag}_launcher_win.bat"
    commandname="${tag}_launcher_mac.command"
    workdir=$(mktemp -d)
    tmpzip="$workdir/${tag}.zip"

    echo "==> Building workspace $tag"

    rm -fr "$foldername" || { echo "FAILED: cleanup of $foldername"; return 1; }
    mkdir -p "$foldername" || { echo "FAILED: mkdir $foldername"; return 1; }
    cp -r $material  PQMF_$origin/.vscode  "$foldername/" || { echo "FAILED: copying material/.vscode into $foldername"; return 1; }
    # The guard VSIX is carried by the launcher, not exposed in the workspace.
    # Never ship a stray violation marker left over from local testing either.
    rm -f "$foldername/.vscode/pqmf-exam-guard.vsix" \
        "$foldername/.vscode/.ai-extension-detected" \
        "$foldername/.vscode/.ai-extension-detected.outside-file" \
        "$foldername/.vscode/.pqmf-exam-guard-extension-heartbeat" \
        "$foldername/.vscode/.pqmf-exam-guard-script-heartbeat" \
        "$foldername/.vscode/.pqmf-exam-guard.log"
    rm -rf "$foldername/.vscode/.extensions-check.lock"
    if [[ -n "$protected_defaults_json" && "$protected_defaults_json" != "{}" ]]; then
        python3 - "$foldername" "$protected_defaults_json" <<'PY' || { echo "FAILED: injecting protected default settings"; return 1; }
import json
import pathlib
import sys

folder = pathlib.Path(sys.argv[1])
json_text = sys.argv[2].strip() or '{}'
try:
    defaults = json.loads(json_text)
except json.JSONDecodeError as exc:
    raise SystemExit(f"Invalid JSON for protected defaults: {exc}")

base_settings_path = folder / ".vscode" / "settings.base.json"
if not base_settings_path.exists():
    raise SystemExit(f"Missing settings base file: {base_settings_path}")

for settings_path in [base_settings_path, folder / ".vscode" / "settings.json"]:
    if not settings_path.exists():
        raise SystemExit(f"Missing settings file: {settings_path}")
    with settings_path.open("r", encoding="utf-8") as handle:
        settings = json.load(handle)
    settings.update(defaults)
    settings["pqmfExamGuard.protectedSettings"] = defaults
    with settings_path.open("w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")
PY
    fi

    python3 - "$foldername" <<'PY' || { echo "FAILED: setting notebook kernel metadata"; return 1; }
import json
import pathlib
import re
import sys


def convert_notebook(notebook_path):
    source = notebook_path.read_text(encoding="utf-8")
    try:
        notebook = json.loads(source)
    except json.JSONDecodeError:
        cells = []
        pattern = re.compile(
            r"<VSCode\.Cell\b(?P<attributes>[^>]*)>(?P<content>.*?)"
            r"</VSCode\.Cell>",
            re.DOTALL,
        )
        for match in pattern.finditer(source):
            attributes = dict(
                re.findall(r'(\w+)\s*=\s*["\']([^"\']*)["\']', match["attributes"])
            )
            language = attributes.get("language", "markdown")
            cell_data = {
                "cell_type": "code" if language == "python" else "markdown",
                "metadata": {"language": language},
                "source": match["content"].lstrip("\n"),
            }
            if "id" in attributes:
                cell_data["metadata"]["id"] = attributes["id"]
            if cell_data["cell_type"] == "code":
                cell_data["execution_count"] = None
                cell_data["outputs"] = []
            cells.append(cell_data)
        if not cells:
            raise ValueError(f"{notebook_path} is empty or not a supported notebook format")
        notebook = {
            "cells": cells,
            "metadata": {},
            "nbformat": 4,
            "nbformat_minor": 5,
        }
    return notebook

for notebook_path in pathlib.Path(sys.argv[1]).rglob("*.ipynb"):
    notebook = convert_notebook(notebook_path)
    notebook.setdefault("metadata", {})["kernelspec"] = {
        "display_name": "Python (PQMF)",
        "language": "python",
        "name": "pqmf-python",
    }
    with notebook_path.open("w", encoding="utf-8") as notebook_file:
        json.dump(notebook, notebook_file, ensure_ascii=False, indent=1)
        notebook_file.write("\n")
PY
    if [[ "$examclass" == "exam" ]]; then
        build_exam_guard_vsix "$foldername" || { echo "FAILED: building exam guard VSIX"; return 1; }
    fi
    echo "    zipping workspace contents..."
    zip -rq "$tmpzip" "$foldername/" || { echo "FAILED: zip $tmpzip"; return 1; }
    rm -fr "$foldername"
    echo "    encoding payload..."
    payload_b64="$(base64 < "$tmpzip")" || { echo "FAILED: base64 encode $tmpzip"; return 1; }
    guard_b64=""
    if [[ "$examclass" == "exam" ]]; then
        guard_vsix="PQMF_ExamWorkspace/.vscode/pqmf-exam-guard.vsix"
        [[ -f "$guard_vsix" ]] || { echo "FAILED: missing $guard_vsix"; return 1; }
        guard_b64="$(base64 < "$guard_vsix")" || { echo "FAILED: base64 encode $guard_vsix"; return 1; }
    fi
    rm -rf "$workdir"

    launcher_content="${ROBUST_LAUNCHER_TEMPLATE//__ASSIGNMENT__/${tag}}"
    launcher_content="${launcher_content//__PACKAGES__/$REQUIRED_PACKAGES}"
    launcher_content="${launcher_content//__EXAM_GUARD_PAYLOAD__/$guard_b64}"

    echo "    writing $launchername"
    printf '%s
%s
' "$launcher_content" "$payload_b64" > "$launchername" || { echo "FAILED: writing $launchername"; return 1; }
    cp "$launchername" ~/Downloads/ || { echo "FAILED: copying $launchername to ~/Downloads"; return 1; }

    echo "    writing $commandname"
    { printf '%s
' "$launcher_content" | sed -n 's/^:; //p'; printf '__EXAM_GUARD_PAYLOAD_BELOW__
%s
__WORKSPACE_PAYLOAD_BELOW__
%s
' "$guard_b64" "$payload_b64"; } > "$commandname" || { echo "FAILED: writing $commandname"; return 1; }
    chmod +x "$commandname"
    cp "$commandname" ~/Downloads/ || { echo "FAILED: copying $commandname to ~/Downloads"; return 1; }

    echo "    done: ~/Downloads/$launchername and ~/Downloads/$commandname"
}

#make_workspace "01_BasicsVariablesStrings/BasicsVariablesStrings_quiz1.ipynb" C02 G01 exam
#make_workspace "01_BasicsVariablesStrings/BasicsVariablesStrings_quiz2.ipynb" C02 G02 exam
#make_workspace "02_NumbersTypesInputConditionals/NumbersTypesInputConditionals_class.ipynb" C02 ALL class

make_workspace "00_CourseLevelDocuments/hello_world.*" ALL ALL class "" "{}"
disable_outside_workspace_check=false
make_workspace "00_CourseLevelDocuments/hello_world.*" ALL ALL exam "" "{\"pqmfExamGuard.disableOutOfFocusCheck\": true, \"pqmfExamGuard.disableOutsideWorkspaceCheck\": $disable_outside_workspace_check}"
