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

# Desktop notification (OSC 777 written straight to the Ghostty client PTY) + remember window.
"$HOME/.config/tmux/notify-bell.sh" "$s" "$i" "$n" "$c" "$w" "$p"

# Red flag: ask Claude to emit a BEL on our behalf. Hooks have NO controlling terminal
# (can't write /dev/tty), so the BEL must go through the `terminalSequence` output field;
# Claude emits it into the pane and tmux paints the window red. Needs Claude Code v2.1.141+.
printf '{"terminalSequence":"\\u0007"}'
exit 0
