#!/usr/bin/env bash
# tmux pane-title-changed hook: rename the window to Claude Code's session topic.
# Claude Code mirrors its conversation topic into the terminal title (pane_title),
# with a spinner glyph in front while it works. As soon as the topic shows up,
# the window takes that name, so the status bar says what each session is about.
# Manual renames win: a window you renamed yourself is never overridden again.
#
# The topic is shortened to a 1-2 word label ("Tmux", "HolaMundo") by a
# headless `claude -p` call; the window is renamed ONLY when that label
# arrives (no intermediate truncated name).
#   $1 = pane id (#{hook_pane})
pane="${1:-}"
[ -n "$pane" ] || exit 0

RETRY_SECS=90

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

# Respect deliberate names: on the first rename only touch auto-named windows
# (automatic-rename still on); afterwards, only keep following the topic while
# the name is still the one we set (@claude_topic). A Cmd+R rename ends both.
last="$(tmux show-option -wqv -t "$pane" @claude_topic 2>/dev/null)"
if [ -z "$last" ]; then
  [ "$autoren" = "1" ] || exit 0
else
  [ "$wname" = "$last" ] || exit 0
fi

# Topic already shortened by the LLM and the name is still ours -> nothing new.
lastfull="$(tmux show-option -wqv -t "$pane" @claude_topic_full 2>/dev/null)"
[ "$topic" = "$lastfull" ] && exit 0

# --- LLM shortening (the only rename; everything below may exit early) ---
CLAUDE_BIN="$HOME/.local/bin/claude"
[ -x "$CLAUDE_BIN" ] || CLAUDE_BIN="$(command -v claude 2>/dev/null)"
[ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ] || exit 0

# The hook fires constantly while Claude works (the spinner animates the title):
# retry the same topic at most every RETRY_SECS. Setting the marker BEFORE the
# request also keeps concurrent hook runs from stacking duplicate calls.
now="$(date +%s)"
try_topic="$(tmux show-option -wqv -t "$pane" @claude_topic_try 2>/dev/null)"
try_ts="$(tmux show-option -wqv -t "$pane" @claude_topic_try_ts 2>/dev/null)"
if [ "$try_topic" = "$topic" ] && [ -n "$try_ts" ] && [ $((now - try_ts)) -lt "$RETRY_SECS" ]; then
  exit 0
fi
tmux set-option -w -t "$pane" @claude_topic_try "$topic" 2>/dev/null
tmux set-option -w -t "$pane" @claude_topic_try_ts "$now" 2>/dev/null

prompt="Reply with ONLY a short label naming the main subject of this terminal-session topic: 1 word if possible, 2 words only if a single word would be ambiguous. Keep the topic's language. No punctuation, no quotes, no explanation.

Topic: $topic"

# Unset TMUX/TMUX_PANE so the headless call doesn't trip the Stop/SessionEnd
# hooks (they key off TMUX_PANE and would notify/flag this very window).
# perl's alarm is the watchdog (macOS has no stock `timeout`).
name="$(cd "$HOME" && env -u TMUX -u TMUX_PANE \
  perl -e 'alarm 90; exec @ARGV' -- "$CLAUDE_BIN" -p --model haiku "$prompt" 2>/dev/null \
  | awk 'NF {print; exit}' \
  | sed -E 's/^[[:space:]"'"'"'`]+//; s/[[:space:]".'"'"'`]+$//')"
[ -n "$name" ] || exit 0

# Enforce the 1-2 word contract even if the model rambles; keep it bar-sized.
name="$(printf '%s' "$name" | awk '{ if (NF > 2) print $1, $2; else print }')"
[ "${#name}" -le 25 ] || exit 0

# Re-check before applying: the user may have renamed meanwhile, or a newer
# topic may have superseded this one during the request. Same rules as above:
# with no name of ours in place yet, the window must still be auto-named.
IFS='|' read -r wname2 autoren2 <<EOF
$(tmux display-message -p -t "$pane" '#{window_name}|#{automatic-rename}' 2>/dev/null)
EOF
last2="$(tmux show-option -wqv -t "$pane" @claude_topic 2>/dev/null)"
try2="$(tmux show-option -wqv -t "$pane" @claude_topic_try 2>/dev/null)"
if [ -z "$last2" ]; then
  [ "$autoren2" = "1" ] || exit 0
else
  [ "$wname2" = "$last2" ] || exit 0
fi
[ "$try2" = "$topic" ] || exit 0

tmux rename-window -t "$pane" "$name" 2>/dev/null
tmux set-option -w -t "$pane" @claude_topic "$name" 2>/dev/null
tmux set-option -w -t "$pane" @claude_topic_full "$topic" 2>/dev/null
exit 0
