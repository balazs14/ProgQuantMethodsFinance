
# Polyglot launcher: valid as both a Windows batch script and a bash script.
# ":;" lines are no-op labels in cmd.exe but run as bash statements; bash exits
# before reaching the batch-only section below.
read -r -d '' ROBUST_LAUNCHER_TEMPLATE << 'EOF'
:; #!/usr/bin/env bash
:; set -uo pipefail
:; ASSIGNMENT="__ASSIGNMENT__"
:; DOWNLOADS="$HOME/Downloads"
:; alert() { osascript -e "display alert \"$1\" message \"$2\"" >/dev/null 2>&1; }
:; echo "Checking prerequisites..."
:; CODE_CMD=""
:; if command -v code >/dev/null 2>&1; then CODE_CMD="code"; elif [ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]; then CODE_CMD="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; fi
:; if [ -z "$CODE_CMD" ]; then alert "VS Code not found" "VS Code could not be found on this computer. Please install it from https://code.visualstudio.com/ and try again."; exit 1; fi
:; PYTHON_CMD=""
:; if command -v python3 >/dev/null 2>&1; then PYTHON_CMD="python3"; elif command -v python >/dev/null 2>&1; then PYTHON_CMD="python"; fi
:; if [ -z "$PYTHON_CMD" ]; then alert "Python not found" "Python could not be found on this computer. Please install it from https://www.python.org/downloads/ and try again."; exit 1; fi
:; echo "Installing required Python packages..."
:; PACKAGES="__PACKAGES__"
:; "$PYTHON_CMD" -m pip install --quiet --disable-pip-version-check --user $PACKAGES || alert "Package installation failed" "Could not install required Python packages ($PACKAGES). Please install them manually."
:; echo "Looking for downloaded assignment..."
:; SOURCE_DIR=""
:; if [ -d "$DOWNLOADS/$ASSIGNMENT" ]; then SOURCE_DIR="$DOWNLOADS/$ASSIGNMENT"; echo "Using already-extracted folder: $SOURCE_DIR"; fi
:; if [ -z "$SOURCE_DIR" ]; then shopt -s nullglob; candidates=("$DOWNLOADS/$ASSIGNMENT.zip" "$DOWNLOADS/$ASSIGNMENT "*.zip); shopt -u nullglob; ZIP_PATH=""; if [ ${#candidates[@]} -gt 0 ]; then ZIP_PATH=$(ls -t "${candidates[@]}" | head -n 1); fi; if [ -z "$ZIP_PATH" ]; then alert "Assignment not found" "Could not find $ASSIGNMENT.zip in Downloads."; exit 1; fi; echo "Using: $(basename "$ZIP_PATH")"; EXTRACT_ROOT="$DOWNLOADS/${ASSIGNMENT}_OPEN"; rm -rf "$EXTRACT_ROOT"; mkdir -p "$EXTRACT_ROOT"; unzip -q -o "$ZIP_PATH" -d "$EXTRACT_ROOT"; SOURCE_DIR="$EXTRACT_ROOT"; fi
:; echo "Finding project folder..."
:; VSCODE_DIR=$(find "$SOURCE_DIR" -type d -name ".vscode" -print -quit)
:; if [ -z "$VSCODE_DIR" ]; then alert "Project folder not found" "The assignment was extracted, but no .vscode folder was found."; open "$SOURCE_DIR"; exit 1; fi
:; PROJECT_DIR=$(dirname "$VSCODE_DIR")
:; echo "Opening: $PROJECT_DIR"
:; "$CODE_CMD" "$PROJECT_DIR"
:; exit 0

@echo off
setlocal

REM =========================================================
REM CHANGE ONLY THIS LINE FOR EACH MOODLE ASSIGNMENT
REM =========================================================
set "ASSIGNMENT=__ASSIGNMENT__"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $downloads = Join-Path $env:USERPROFILE 'Downloads'; Write-Host 'Checking prerequisites...'; $code = $null; $cmd = Get-Command code -ErrorAction SilentlyContinue; if ($cmd) { $code = $cmd.Source }; if (-not $code) { $locations = @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'), (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe')); $code = $locations | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1 }; if (-not $code) { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('VS Code could not be found on this computer. Please install it from https://code.visualstudio.com/ and try again.', 'VS Code not found'); exit 1 }; $python = Get-Command python -ErrorAction SilentlyContinue; if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }; if (-not $python) { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Python could not be found on this computer. Please install it from https://www.python.org/downloads/ and try again.', 'Python not found'); exit 1 }; Write-Host 'Installing required Python packages...'; $packages = '__PACKAGES__' -split ' '; & $python.Source -m pip install --quiet --disable-pip-version-check --user @packages; if ($LASTEXITCODE -ne 0) { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Could not install required Python packages (' + ($packages -join ', ') + '). Please install them manually.', 'Package installation failed') }; Write-Host 'Looking for downloaded assignment...'; $zip = Get-ChildItem -LiteralPath $downloads -File -Filter '*.zip' | Where-Object { $_.BaseName -eq '%ASSIGNMENT%' -or $_.BaseName -match '^%ASSIGNMENT% \(\d+\)$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if (-not $zip) { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Could not find %ASSIGNMENT%.zip in Downloads.', 'Assignment not found'); exit 1 }; Write-Host ('Using: ' + $zip.Name); $extractRoot = Join-Path $downloads ('%ASSIGNMENT%_OPEN'); if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }; New-Item -ItemType Directory -Path $extractRoot | Out-Null; Expand-Archive -LiteralPath $zip.FullName -DestinationPath $extractRoot -Force; Write-Host 'Finding project folder...'; $vscodeFolder = Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse -Force | Where-Object { $_.Name -eq '.vscode' } | Select-Object -First 1; if (-not $vscodeFolder) { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('The assignment was extracted, but no .vscode folder was found.', 'Project folder not found'); explorer.exe $extractRoot; exit 1 }; $project = $vscodeFolder.Parent.FullName; Write-Host ('Opening: ' + $project); Start-Process -FilePath $code -ArgumentList @($project)"

endlocal
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

    zipname="${tag}.zip"
    foldername="Workspace_${tag}"
    launchername="${tag}_launcher.bat"

    rm -fr "$foldername" "$zipname" && \
    mkdir -p "$foldername" &&  \
    cp -r $material  PQMF_$origin/.vscode  "$foldername/" && \
    zip -r "$zipname" "$foldername/" && \
    rm -fr "$foldername" && \
    cp "$zipname" ~/Downloads/ && \
    launcher_content="${ROBUST_LAUNCHER_TEMPLATE//__ASSIGNMENT__/${zipname%.zip}}" && \
    echo "${launcher_content//__PACKAGES__/$REQUIRED_PACKAGES}" > "$launchername" && \
    cp "$launchername" ~/Downloads/
}

make_workspace "01_BasicsVariablesStrings/BasicsVariablesStrings_quiz1.ipynb" C02 G01 exam
make_workspace "01_BasicsVariablesStrings/BasicsVariablesStrings_quiz2.ipynb" C02 G02 exam
make_workspace "02_NumbersTypesInputConditionals/NumbersTypesInputConditionals_class.ipynb" C02 ALL class

