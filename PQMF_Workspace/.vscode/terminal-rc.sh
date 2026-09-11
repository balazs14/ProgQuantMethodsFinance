#!/bin/bash
# Sourced as the rcfile for the workspace's restricted terminal profile.
[ -f ~/.bashrc ] && source ~/.bashrc
[ -f ~/.bash_profile ] && source ~/.bash_profile

# Shadow the copilot CLI/TUI regardless of PATH (bash checks functions before PATH).
copilot() {
  echo "The 'copilot' command is disabled in this workspace." >&2
  return 1
}
