#!/usr/bin/env bash
# Cycle the client through every Claude Code pane, across ALL sessions and
# windows, with wrap-around (Ghostty Cmd+Up / Cmd+Down -> prefix2 + u / v).
# If the current pane is not a Claude one, "next" goes to the first Claude
# pane and "prev" to the last.
#
# Usage: claude-cycle.sh next|prev [--print]
#   --print: print the target pane instead of jumping (for testing).

dir="${1:-next}"
print_only=0; [ "${2:-}" = "--print" ] && print_only=1

panes=()
while IFS=$'\t' read -r pid _; do panes+=("$pid"); done \
  < <("$HOME/.config/tmux/claude-panes.sh")

count=${#panes[@]}
if [ "$count" -eq 0 ]; then
  tmux display-message "No Claude sessions"
  exit 0
fi

current="$(tmux display-message -p '#{pane_id}')"
cur_idx=-1
for i in "${!panes[@]}"; do
  [ "${panes[$i]}" = "$current" ] && { cur_idx=$i; break; }
done

if [ "$cur_idx" -lt 0 ]; then
  # Not on a Claude pane: next -> first, prev -> last.
  [ "$dir" = "prev" ] && target_idx=$((count - 1)) || target_idx=0
elif [ "$dir" = "prev" ]; then
  target_idx=$(( (cur_idx - 1 + count) % count ))
else
  target_idx=$(( (cur_idx + 1) % count ))
fi
target="${panes[$target_idx]}"

if [ "$print_only" -eq 1 ]; then
  printf '%s\n' "$target"
  exit 0
fi

read -r sess_id win_id <<EOF
$(tmux display-message -p -t "$target" '#{session_id} #{window_id}')
EOF
tmux switch-client -t "$sess_id" 2>/dev/null
tmux select-window -t "$win_id" 2>/dev/null
tmux select-pane -t "$target" 2>/dev/null
