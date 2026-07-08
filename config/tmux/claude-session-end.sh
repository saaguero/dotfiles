#!/usr/bin/env bash
# Claude Code SessionEnd hook: undo what rename-to-topic.sh set for this pane.
# rename-to-topic.sh stores a per-PANE label (@claude_topic, shown in the pane
# border) and, when the pane is active, names the WINDOW after it (tracked in the
# window option @claude_named; rename-window turns automatic-rename OFF). When the
# session ends, drop this pane's label and hand the window name back sensibly.
[ -z "$TMUX_PANE" ] && exit 0          # only when running inside tmux
P="$TMUX_PANE"

# Drop this pane's label + bookkeeping so its border stops showing the old topic.
for o in @claude_topic @claude_topic_full @claude_topic_try @claude_topic_try_ts; do
  tmux set-option -p -t "$P" -u "$o" 2>/dev/null
done

# Window name: only touch it if it's still the one we set (respect manual renames).
named="$(tmux show-option -wqv -t "$P" @claude_named 2>/dev/null)"
[ -n "$named" ] || exit 0
wname="$(tmux display-message -p -t "$P" '#{window_name}' 2>/dev/null)"
[ "$wname" = "$named" ] || exit 0

# Re-point the window name at whatever Claude pane is active now; if none has a
# label (this was the last Claude pane), hand the name back to tmux.
ap="$(tmux list-panes -t "$P" -F '#{pane_id}' -f '#{pane_active}' 2>/dev/null | head -1)"
newlbl="$(tmux show-option -pqv -t "$ap" @claude_topic 2>/dev/null)"
if [ -n "$newlbl" ]; then
  tmux rename-window -t "$P" "$newlbl" 2>/dev/null
  tmux set-option -w -t "$P" @claude_named "$newlbl" 2>/dev/null
else
  tmux set-option -w -t "$P" -u @claude_named 2>/dev/null
  tmux set-option -w -t "$P" -u automatic-rename 2>/dev/null   # back to tracking the command
fi
exit 0
