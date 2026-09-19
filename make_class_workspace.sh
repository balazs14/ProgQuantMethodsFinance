
# Polyglot launcher: valid as both a Windows batch script and a bash script.
# ":;" lines are no-op labels in cmd.exe but run as bash statements; bash exits
# before reaching the batch-only section below. The workspace contents are
# embedded as a base64 zip payload after the __PAYLOAD_BELOW__ marker, so a
# single downloaded file can extract and open itself with no separate zip.
read -r -d '' ROBUST_LAUNCHER_TEMPLATE << 'EOF'
:; #!/usr/bin/env bash
:; set -uo pipefail
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
:; MARKER_LINE=$(grep -n '^__PAYLOAD_BELOW__$' "$SCRIPT_PATH" | head -n 1 | cut -d: -f1)
:; if [ -z "$MARKER_LINE" ]; then alert "Workspace data missing" "Could not find the embedded workspace data in this launcher file."; exit 1; fi
:; WORKDIR=$(mktemp -d)
:; TMP_ZIP="$WORKDIR/payload.zip"
:; tail -n +$((MARKER_LINE + 1)) "$SCRIPT_PATH" > "$WORKDIR/payload.b64"
:; if [ "$(uname)" = "Darwin" ]; then base64 -D -i "$WORKDIR/payload.b64" -o "$TMP_ZIP"; else base64 -d "$WORKDIR/payload.b64" > "$TMP_ZIP"; fi
:; EXTRACT_DIR="$SCRIPT_DIR/${ASSIGNMENT}_OPEN"
:; mkdir -p "$EXTRACT_DIR"
:; unzip -q -o "$TMP_ZIP" -d "$EXTRACT_DIR"
:; rm -rf "$WORKDIR"
:; echo "Finding project folder..."
:; VSCODE_DIR=$(find "$EXTRACT_DIR" -type d -name ".vscode" -print -quit)
:; if [ -z "$VSCODE_DIR" ]; then alert "Project folder not found" "The workspace was extracted, but no .vscode folder was found."; open "$EXTRACT_DIR"; exit 1; fi
:; PROJECT_DIR=$(dirname "$VSCODE_DIR")
:; find "$PROJECT_DIR" -type f -name "*.ipynb" -exec "$PYTHON_CMD" -c "import hashlib,json,sys; p=sys.argv[1]; d=json.load(open(p)); d.setdefault('metadata', {})['vscode'] = {'interpreter': {'hash': hashlib.sha256(sys.argv[2].encode()).hexdigest()}}; json.dump(d, open(p, 'w'), indent=1)" {} "$PYTHON_PATH" \;
:; if [ -f "$PROJECT_DIR/.vscode/settings.json" ]; then "$PYTHON_CMD" -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['python.defaultInterpreterPath']=sys.argv[2]; json.dump(d, open(p,'w'), indent=2)" "$PROJECT_DIR/.vscode/settings.json" "$PYTHON_PATH"; fi
:; echo "Opening: $PROJECT_DIR"
:; "$CODE_CMD" --disable-workspace-trust --reuse-window "$PROJECT_DIR"
:; if [ "$(uname)" = "Darwin" ]; then osascript -e "tell application \"Terminal\" to close (every window whose selected tab's tty is \"$(tty)\")" >/dev/null 2>&1; fi
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

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $selfPath='%~f0'; $scriptDir=Split-Path -Parent $selfPath; $python=Get-Command python -ErrorAction SilentlyContinue; if (-not $python) {$python=Get-Command python3 -ErrorAction SilentlyContinue}; if (-not $python) {exit 1}; $packages='__PACKAGES__' -split ' '; $missing=@($packages | Where-Object { try { & $python.Source -c "import $_" 2>$null; $LASTEXITCODE -ne 0 } catch { $true } }); if ($missing.Count -gt 0) { & $python.Source -m pip install --quiet --disable-pip-version-check --user @missing; if ($LASTEXITCODE -ne 0) {exit 1} }; $code=Get-Command code -ErrorAction SilentlyContinue; if (-not $code) {$locations=@((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),(Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe')); $code=$locations|Where-Object {$_ -and (Test-Path -LiteralPath $_)}|Select-Object -First 1}; if (-not $code) {exit 1}; $lines=Get-Content -LiteralPath $selfPath; $marker=($lines|Select-String -Pattern '^__PAYLOAD_BELOW__$'|Select-Object -First 1).LineNumber; $payload=-join $lines[$marker..($lines.Count-1)]; $tmpZip=Join-Path $env:TEMP 'pqmf_payload.zip'; [IO.File]::WriteAllBytes($tmpZip,[Convert]::FromBase64String($payload)); $extractRoot=Join-Path $scriptDir ('%ASSIGNMENT%_OPEN'); if (-not (Test-Path -LiteralPath $extractRoot)) { New-Item -ItemType Directory -Path $extractRoot|Out-Null }; Expand-Archive -LiteralPath $tmpZip -DestinationPath $extractRoot -Force; Remove-Item $tmpZip -Force; $project=(Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse|Where-Object {$_.Name -eq '.vscode'}|Select-Object -First 1).Parent.FullName; Get-ChildItem -LiteralPath $project -Filter *.ipynb -File -Recurse|ForEach-Object {& $python.Source -c \"import hashlib,json,sys; p=sys.argv[1]; d=json.load(open(p)); d.setdefault('metadata', {})['vscode']={'interpreter':{'hash':hashlib.sha256(sys.argv[2].encode()).hexdigest()}}; json.dump(d,open(p,'w'),indent=1)\" $_.FullName $python.Source}; $settings=Join-Path $project '.vscode\settings.json'; if (Test-Path $settings) {$d=Get-Content $settings -Raw|ConvertFrom-Json -AsHashtable; $d['python.defaultInterpreterPath']=$python.Source; $d|ConvertTo-Json -Depth 20|Set-Content $settings}; Start-Process -FilePath $code -ArgumentList @('--disable-workspace-trust','--reuse-window',$project)"

endlocal
exit /b 0
__PAYLOAD_BELOW__
EOF

REQUIRED_PACKAGES="ipykernel numpy pandas matplotlib"

function make_workspace() {
    material="$1"
    classnum=$2
    group=$3
    examclass=$4
    extratag=${5:-}

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
    launchername="${tag}_launcher.bat"
    commandname="${tag}_launcher.command"
    workdir=$(mktemp -d)
    tmpzip="$workdir/${tag}.zip"

    echo "==> Building workspace $tag"

    rm -fr "$foldername" || { echo "FAILED: cleanup of $foldername"; return 1; }
    mkdir -p "$foldername" || { echo "FAILED: mkdir $foldername"; return 1; }
    cp -r $material  PQMF_$origin/.vscode  "$foldername/" || { echo "FAILED: copying material/.vscode into $foldername"; return 1; }
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
    echo "    zipping workspace contents..."
    zip -rq "$tmpzip" "$foldername/" || { echo "FAILED: zip $tmpzip"; return 1; }
    rm -fr "$foldername"
    echo "    encoding payload..."
    payload_b64="$(base64 < "$tmpzip")" || { echo "FAILED: base64 encode $tmpzip"; return 1; }
    rm -rf "$workdir"

    launcher_content="${ROBUST_LAUNCHER_TEMPLATE//__ASSIGNMENT__/${tag}}"
    launcher_content="${launcher_content//__PACKAGES__/$REQUIRED_PACKAGES}"

    echo "    writing $launchername"
    printf '%s
%s
' "$launcher_content" "$payload_b64" > "$launchername" || { echo "FAILED: writing $launchername"; return 1; }
    cp "$launchername" ~/Downloads/ || { echo "FAILED: copying $launchername to ~/Downloads"; return 1; }

    echo "    writing $commandname"
    { printf '%s
' "$launcher_content" | sed -n 's/^:; //p'; printf '__PAYLOAD_BELOW__
%s
' "$payload_b64"; } > "$commandname" || { echo "FAILED: writing $commandname"; return 1; }
    chmod +x "$commandname"
    cp "$commandname" ~/Downloads/ || { echo "FAILED: copying $commandname to ~/Downloads"; return 1; }

    echo "    done: ~/Downloads/$launchername and ~/Downloads/$commandname"
}

make_workspace "01_BasicsVariablesStrings/BasicsVariablesStrings_quiz1.ipynb" C02 G01 exam
make_workspace "01_BasicsVariablesStrings/BasicsVariablesStrings_quiz2.ipynb" C02 G02 exam
make_workspace "02_NumbersTypesInputConditionals/NumbersTypesInputConditionals_class.ipynb" C02 ALL class

