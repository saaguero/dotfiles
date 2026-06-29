#!/usr/bin/env bash
# Fires the desktop notification + remembers the window. Called by Claude's Stop
# hook (claude-stop.sh). It does: (1) remember the window so Cmd+Shift+U can jump
# to it, (2) optional sound, (3) native Ghostty notification (OSC 777) for when
# you're in another app.
#   $1=session $2=index $3=name $4=command $5=window_id $6=pane_title
sesion="${1:-?}"; idx="${2:-?}"; nombre="${3:-?}"; cmd="${4:-}"; winid="${5:-}"; ptitle="${6:-}"

# (1) Remember the last window that alerted, so Cmd+Shift+U jumps there.
if [ -n "$winid" ]; then
  tmux set -g @last_bell_session "$sesion" 2>/dev/null
  tmux set -g @last_bell_window  "$winid"  2>/dev/null
fi

# (2) Sound: handled by macOS (Ghostty "Play sound" ON). Uncomment to force it:
# afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 &

# (3) Descriptor: the conversation TOPIC (pane_title, which Claude updates by itself),
#     stripping the leading spinner/decoration. Falls back to the window name.
tema="$(printf '%s' "$ptitle" | sed -E 's/^[^A-Za-z0-9]*//; s/[[:space:]]+$//')"
desc="${tema:-$nombre}"

hora="$(date +%H:%M:%S)"
titulo="🔔 ${desc}"
cuerpo="finished · session '${sesion}' · window ${idx} · ${hora}"

# OSC 777 written straight to each Ghostty client PTY (no passthrough needed).
tmux list-clients -F '#{client_tty}' 2>/dev/null | sort -u | while read -r tty; do
  [ -n "$tty" ] && printf '\033]777;notify;%s;%s\007' "$titulo" "$cuerpo" > "$tty" 2>/dev/null
done
