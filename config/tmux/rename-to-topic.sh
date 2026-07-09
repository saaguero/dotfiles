#!/usr/bin/env bash
# tmux pane-title-changed hook: label each Claude Code pane with its topic.
# Claude mirrors its conversation topic into the pane title (with a leading
# spinner); this shortens it to a 1-2 word label via an LLM and:
#   - stores it as a PER-PANE option @claude_topic, shown in the pane border
#     (pane-border-format) -- so several Claude panes in ONE window each show
#     their own topic instead of fighting over the single window name;
#   - if the pane is active, also sets the WINDOW name to that label (and an
#     after-select-pane hook re-points the window name when you switch panes;
#     focusing a non-Claude pane hands the name back to automatic-rename).
# A window you renamed yourself (Cmd+R) is never overridden.
#
# Backend: Claude Haiku (headless `claude -p`); on empty output (failure / rate
# limit / usage limit) it falls back to OpenRouter's free-models router. The hook
# fires ~10x/s per pane (spinner), so three guards stop process pile-up: a
# per-topic throttle, a global in-flight cap, and a per-pane single-flight lock.
#
# Usage:  rename-to-topic.sh <pane-id>          # pane-title-changed hook
#         rename-to-topic.sh --activate <pane>  # after-select-pane hook

RETRY_SECS=90     # per-topic: don't re-ask the LLM about the same topic within this
LLM_TIMEOUT=30    # hard cap per backend call (claude / curl): a hung call can't linger
STALE_SECS=90     # reclaim a lock if a run died holding it (> worst-case hold)
MAX_INFLIGHT=4    # global backstop: at most this many shortenings at once (all panes)
LOCKDIR="${TMPDIR:-/tmp}"
LOCKGLOB="$LOCKDIR/claude-rename-topic.*.lock"
OPENROUTER_KEYFILE="$HOME/.config/tmux/openrouter.key"   # mode-600, kept out of dotfiles
OPENROUTER_MODEL="openrouter/free"

# Set the WINDOW name of pane $1 to label $2. We track the name we set in the
# window option @claude_named:
#   - first time (no @claude_named): claim the window and name it;
#   - afterwards: keep updating unless the user renamed manually -- the name
#     differs from @claude_named AND automatic-rename is off (a manual Cmd+R
#     rename turns it off; if it is ON, the mismatch is just tmux's automatic
#     name after we reverted below, so the window can be re-claimed).
maybe_set_window_name() {
  local p="$1" nm="$2" auto cur named
  IFS='|' read -r auto cur <<EOF
$(tmux display-message -p -t "$p" '#{automatic-rename}|#{window_name}' 2>/dev/null)
EOF
  named="$(tmux show-option -wqv -t "$p" @claude_named 2>/dev/null)"
  [ -n "$named" ] && [ "$cur" != "$named" ] && [ "$auto" != "1" ] && return 0   # formats render the option as 1/0
  tmux rename-window -t "$p" "$nm" 2>/dev/null
  tmux set-option -w -t "$p" @claude_named "$nm" 2>/dev/null
}

# after-select-pane: point the window name at the now-active pane's label.
# If the focused pane is NOT a Claude one (no label), hand the name back to
# tmux (automatic-rename) so it tracks the pane's command again (vim, bash...).
if [ "${1:-}" = "--activate" ]; then
  ap="${2:-}"
  [ -n "$ap" ] || exit 0
  lbl="$(tmux show-option -pqv -t "$ap" @claude_topic 2>/dev/null)"
  if [ -n "$lbl" ]; then
    maybe_set_window_name "$ap" "$lbl"
    exit 0
  fi
  # Revert only while the name is still the one we set (respect manual renames).
  # @claude_named stays set: with automatic-rename back on, maybe_set_window_name
  # re-claims the window when a Claude pane gets focus again.
  named="$(tmux show-option -wqv -t "$ap" @claude_named 2>/dev/null)"
  [ -n "$named" ] || exit 0
  cur="$(tmux display-message -p -t "$ap" '#{window_name}' 2>/dev/null)"
  [ "$cur" = "$named" ] || exit 0
  tmux set-option -w -t "$ap" -u automatic-rename 2>/dev/null
  exit 0
fi

pane="${1:-}"
[ -n "$pane" ] || exit 0
LOCK="$LOCKDIR/claude-rename-topic.$(printf '%s' "$pane" | tr -cd 'A-Za-z0-9').lock"

IFS='|' read -r cmd title <<EOF
$(tmux display-message -p -t "$pane" '#{pane_current_command}|#{pane_title}' 2>/dev/null)
EOF

# Only Claude Code panes. pane_current_command shows Claude as "claude", "node",
# or a bare version number (e.g. "2.1.204", the versioned binary) -- but
# "node"/version also match unrelated processes (dev servers, REPLs). For those,
# confirm via the pane tty (flag-agnostic: matches with or without --dangerously-*).
# This keeps the LLM -- and any token spend -- off shells and other commands.
case "$cmd" in
  claude*) ;;                         # the CLI itself -> definitely Claude
  node|[0-9]*.[0-9]*)                 # ambiguous -> verify via the pane's tty
    tty="$(tmux display-message -p -t "$pane" '#{pane_tty}' 2>/dev/null)"
    ps -t "${tty#/dev/}" -o command= 2>/dev/null | grep -qi 'claude' || exit 0
    ;;
  *) exit 0 ;;                        # plain shells / other commands -> never touch
esac

# Strip the leading spinner/decoration; bail if there's no real topic yet.
topic="$(printf '%s' "$title" | sed -E 's/^[^A-Za-z0-9]*//; s/[[:space:]]+$//')"
[ -n "$topic" ] || exit 0
[ "$topic" = "$cmd" ] && exit 0   # title is just the command name, no topic yet

# Already labeled this exact topic for THIS pane -> nothing new.
lastfull="$(tmux show-option -pqv -t "$pane" @claude_topic_full 2>/dev/null)"
[ "$topic" = "$lastfull" ] && exit 0

# --- backends: each prints the raw first non-empty reply line (or nothing) ---
# Claude Haiku, headless. Unset TMUX/TMUX_PANE so the call doesn't trip the
# Stop/SessionEnd hooks. perl's alarm is the watchdog (macOS has no `timeout`).
shorten_claude() {
  local bin="$HOME/.local/bin/claude"
  [ -x "$bin" ] || bin="$(command -v claude 2>/dev/null)"
  [ -n "$bin" ] && [ -x "$bin" ] || return 0
  cd "$HOME" && env -u TMUX -u TMUX_PANE \
    perl -e 'alarm shift; exec @ARGV' "$LLM_TIMEOUT" "$bin" -p --model haiku "$1" 2>/dev/null \
    | awk 'NF {print; exit}'
}

# OpenRouter free-models router, via curl. No jq / no key file -> skip.
shorten_openrouter() {
  local jq; jq="$(command -v jq)"
  [ -n "$jq" ] || return 0
  [ -r "$OPENROUTER_KEYFILE" ] || return 0
  local key; key="$(tr -d '[:space:]' < "$OPENROUTER_KEYFILE")"
  [ -n "$key" ] || return 0
  local body
  body="$("$jq" -nc --arg m "$OPENROUTER_MODEL" --arg c "$1" \
    '{model:$m, messages:[{role:"user",content:$c}]}')" || return 0
  curl -sS --max-time "$LLM_TIMEOUT" https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $key" \
    -H 'Content-Type: application/json' \
    -d "$body" 2>/dev/null \
    | "$jq" -r '.choices[0].message.content // empty' 2>/dev/null \
    | awk 'NF {print; exit}'
}

# The hook fires constantly while Claude works (the spinner animates the title).
# Three guards keep this cheap and stop process pile-up WITHOUT hurting several
# simultaneous conversations:
#   1) per-topic throttle: don't re-ask about the same topic within RETRY_SECS.
#   2) global backstop: never more than MAX_INFLIGHT shortenings running at once.
#   3) per-pane single-flight lock: one in-flight rename PER PANE -- different
#      panes/conversations run in parallel; a single pane's spinner burst
#      serializes. Contending runs exit instantly (cheap failed mkdir, no fork).
now="$(date +%s)"

# (1) throttle -- most repeat fires exit right here, before touching any lock.
try_topic="$(tmux show-option -pqv -t "$pane" @claude_topic_try 2>/dev/null)"
try_ts="$(tmux show-option -pqv -t "$pane" @claude_topic_try_ts 2>/dev/null)"
if [ "$try_topic" = "$topic" ] && [ -n "$try_ts" ] && [ $((now - try_ts)) -lt "$RETRY_SECS" ]; then
  exit 0
fi

# Reclaim stale locks (runs killed before their EXIT trap fired) so a dead lock
# neither blocks its pane nor inflates the in-flight count below. perl for the
# mtime: portable across BSD stat (-f %m) and GNU stat (-c %Y), which differ.
for d in $LOCKGLOB; do
  [ -d "$d" ] || continue
  m="$(perl -e 'print((stat($ARGV[0]))[9] // 0)' "$d" 2>/dev/null)"
  [ "${m:-0}" -gt 0 ] && [ $((now - m)) -ge "$STALE_SECS" ] && rmdir "$d" 2>/dev/null
done

# (2) global backstop.
inflight=0
for d in $LOCKGLOB; do [ -d "$d" ] && inflight=$((inflight+1)); done
[ "$inflight" -ge "$MAX_INFLIGHT" ] && exit 0

# (3) per-pane single-flight lock (mkdir is atomic).
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# Mark this topic attempted now (holding the lock) so repeat fires throttle.
tmux set-option -p -t "$pane" @claude_topic_try "$topic" 2>/dev/null
tmux set-option -p -t "$pane" @claude_topic_try_ts "$now" 2>/dev/null

prompt="Give ONLY a 1-2 word label for the main SUBJECT of this terminal-session topic: the specific thing it is about -- a proper noun, work, tool, project or concept. NOT the action: never answer with a generic verb like write/make/fix/debug/create/analyze (or their equivalents in any language). Pick the most recognizable noun; use 2 words only when they identify it better. Keep the topic's language. No punctuation, no quotes, no explanation.

Examples (name the subject, not the verb):
Topic: write about a novel -> novel
Topic: fix the login bug -> login
Topic: migrate the database to a new host -> database
Topic: set up the CI pipeline -> CI pipeline

Topic: $topic"

# Claude Haiku first; fall back to OpenRouter if it comes back empty.
raw="$(shorten_claude "$prompt")"
[ -n "$raw" ] || raw="$(shorten_openrouter "$prompt")"
name="$(printf '%s' "$raw" \
  | sed -E 's/^[[:space:]"'"'"'`]+//; s/[[:space:]".,:;!?'"'"'`]+$//')"
[ -n "$name" ] || exit 0

# Enforce the 1-2 word contract even if the model rambles; keep it bar-sized.
name="$(printf '%s' "$name" | awk '{ if (NF > 2) print $1, $2; else print }')"
[ "${#name}" -le 25 ] || exit 0

# Store the per-pane label -> the pane border shows it (pane-border-format).
tmux set-option -p -t "$pane" @claude_topic "$name" 2>/dev/null
tmux set-option -p -t "$pane" @claude_topic_full "$topic" 2>/dev/null

# If this pane is the active one, also drive the window name (the after-select-pane
# hook re-points it when you switch panes). Single-pane windows behave as before.
active="$(tmux display-message -p -t "$pane" '#{pane_active}' 2>/dev/null)"
[ "$active" = "1" ] && maybe_set_window_name "$pane" "$name"
exit 0
