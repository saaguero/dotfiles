#!/usr/bin/env bash
# Jump to the last window/session that "rang the bell" (left a pending alert).
# Usage: goto-last-bell.sh [auto]
#   no arg -> manual mode (Cmd+Shift+U): if nothing is pending, say so.
#   "auto" -> silent if nothing is pending (kept for possible hook use).
mode="${1:-manual}"
sess="$(tmux show-option -gqv @last_bell_session)"
win="$(tmux show-option -gqv @last_bell_window)"

if [ -z "$win" ]; then
  [ "$mode" != "auto" ] && tmux display-message "No pending alerts"
  exit 0
fi

# Clear FIRST (avoids re-triggers: the jump itself emits another focus event).
tmux set -gu @last_bell_session 2>/dev/null
tmux set -gu @last_bell_window  2>/dev/null

tmux switch-client -t "$sess" 2>/dev/null
tmux select-window -t "$win" 2>/dev/null
