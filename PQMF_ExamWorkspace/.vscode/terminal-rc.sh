#!/bin/bash
# Sourced as the rcfile for the exam workspace's restricted terminal profile.
# This enforces no CLI access to copilot during the exam.
[ -f ~/.bashrc ] && source ~/.bashrc
[ -f ~/.bash_profile ] && source ~/.bash_profile

# Shadow the copilot CLI/TUI regardless of PATH (bash checks functions before PATH).
copilot() {
  echo "The 'copilot' command is disabled in this exam workspace." >&2
  return 1
}
