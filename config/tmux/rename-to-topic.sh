#!/usr/bin/env bash
# tmux pane-title-changed hook: rename the window to Claude Code's session topic.
# Claude Code mirrors its conversation topic into the terminal title (pane_title),
# with a spinner glyph in front while it works. As soon as the topic shows up,
# the window takes that name, so the status bar says what each session is about.
# Manual renames win: a window you renamed yourself is never overridden again.
#   $1 = pane id (#{hook_pane})
pane="${1:-}"
[ -n "$pane" ] || exit 0

IFS='|' read -r cmd title wname autoren <<EOF
$(tmux display-message -p -t "$pane" \
  '#{pane_current_command}|#{pane_title}|#{window_name}|#{automatic-rename}' 2>/dev/null)
EOF

# Only panes running Claude Code: the CLI shows up as "claude" or as its bare
# version number (e.g. "2.1.198", the versioned binary). Skip plain shells.
case "$cmd" in
  claude*|node|[0-9]*.[0-9]*) ;;
  *) exit 0 ;;
esac

# Strip the leading spinner/decoration (same cleanup notify-bell.sh does).
topic="$(printf '%s' "$title" | sed -E 's/^[^A-Za-z0-9]*//; s/[[:space:]]+$//')"
[ -n "$topic" ] || exit 0
[ "$topic" = "$cmd" ] && exit 0   # title is just the command name, no topic yet

# Keep the status bar readable: cap at 25 chars (trim trailing space before "…").
if [ "${#topic}" -gt 25 ]; then
  topic="${topic:0:24}"
  topic="${topic%% }…"
fi
[ "$topic" = "$wname" ] && exit 0

# Respect deliberate names: on the first rename only touch auto-named windows
# (automatic-rename still on); afterwards, only keep following the topic while
# the name is still the one we set (@claude_topic). A Cmd+R rename ends both.
last="$(tmux show-option -wqv -t "$pane" @claude_topic 2>/dev/null)"
if [ -z "$last" ]; then
  [ "$autoren" = "1" ] || exit 0
else
  [ "$wname" = "$last" ] || exit 0
fi

tmux rename-window -t "$pane" "$topic" 2>/dev/null
tmux set-option -w -t "$pane" @claude_topic "$topic" 2>/dev/null
exit 0
