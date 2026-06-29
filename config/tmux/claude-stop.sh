#!/usr/bin/env bash
# Claude Code "Stop" hook: when Claude finishes, notify + mark the window (red) +
# remember the window (for Cmd+Shift+U). Unless you're looking at it (Ghostty
# focused AND its window active), so it won't disturb you while actively chatting.
[ -z "$TMUX_PANE" ] && exit 0          # only when running inside tmux

focused="$(tmux show-option -gqv @ghostty_focused)"
cw="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)"
aw="$(tmux display-message -p '#{window_id}' 2>/dev/null)"
if [ "$focused" = "1" ] && [ "$cw" = "$aw" ]; then
  exit 0                                # you're looking at it -> don't disturb
fi

IFS='|' read -r s i n c w p < <(tmux display-message -p -t "$TMUX_PANE" \
  '#{session_name}|#{window_index}|#{window_name}|#{pane_current_command}|#{window_id}|#{pane_title}')

# Desktop notification (OSC 777) + remember the window in @last_bell.
"$HOME/.config/tmux/notify-bell.sh" "$s" "$i" "$n" "$c" "$w" "$p"

# Bell -> paints the window RED in the status bar. alert-bell is OFF, so this only
# marks (it does not fire a notification, so it cannot loop).
printf '\a' > /dev/tty 2>/dev/null
exit 0
