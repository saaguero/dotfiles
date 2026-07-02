#!/usr/bin/env bash
# Claude Code SessionEnd hook: give the window name back to tmux.
# rename-to-topic.sh names the window after the session topic, and tmux's
# rename-window turns automatic-rename OFF for that window. When the Claude
# session ends, re-enable it so the name goes back to tracking the running
# command (bash, ssh, ...) like any other window.
[ -z "$TMUX_PANE" ] && exit 0          # only when running inside tmux

topic="$(tmux show-option -wqv -t "$TMUX_PANE" @claude_topic 2>/dev/null)"
[ -n "$topic" ] || exit 0              # we never renamed this window -> hands off

wname="$(tmux display-message -p -t "$TMUX_PANE" '#{window_name}' 2>/dev/null)"
[ "$wname" = "$topic" ] || exit 0      # user renamed manually since -> leave it

tmux set-option -w -t "$TMUX_PANE" -u @claude_topic 2>/dev/null
# Unset the window-level option so it inherits the global default (on) and the
# window resumes tracking the running command.
tmux set-option -w -t "$TMUX_PANE" -u automatic-rename 2>/dev/null
exit 0
