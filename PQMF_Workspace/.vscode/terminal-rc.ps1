# PowerShell profile sourced for the workspace's restricted terminal profile on Windows.
# This disables CLI access to copilot in the everyday workspace.

# Shadow the copilot command: PowerShell checks functions before aliases before PATH.
function copilot {
    Write-Error "The 'copilot' command is disabled in this workspace." -ErrorAction Stop
}
