#!/usr/bin/env bash
# fzf preview for claude-picker.sh: a one-line stats header (status, model,
# context tokens, last activity, git branch, cwd) above the live tail of the
# pane. Stats come from the same sources recon (github.com/gavraz/recon) used:
#   - pane bottom lines            -> status (working / input / idle)
#   - ~/.claude/sessions/{PID}.json -> session id + cwd (written by Claude Code)
#   - the session's JSONL transcript -> model, context tokens, last activity
# Everything degrades to "?" if a source is missing; the pane tail always shows.

pane="${1:-}"
[ -n "$pane" ] || exit 0

C_RESET=$'\033[0m'; C_DIM=$'\033[90m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'

# Resume entries (picker's ctrl-r view) pass a session uuid instead of a
# %pane_id: render the transcript tail instead of a live pane. $2 is the
# conversation's cwd. Same 3 header lines so the picker's '~3' pin fits.
if [[ "$pane" != %* ]]; then
  sid="$pane"; cwd="${2:-}"
  jsonl=""
  for f in "$HOME/.claude/projects/"*/"$sid".jsonl; do
    [ -r "$f" ] && { jsonl="$f"; break; }
  done
  [ -n "$jsonl" ] || { echo "transcript not found: $sid"; exit 0; }
  ago="?"
  mtime="$(perl -e 'print((stat($ARGV[0]))[9] // 0)' "$jsonl" 2>/dev/null)"
  if [ "${mtime:-0}" -gt 0 ]; then
    d=$(( $(date +%s) - mtime ))
    if   [ "$d" -lt 60 ];    then ago="now"
    elif [ "$d" -lt 3600 ];  then ago="$((d / 60))m ago"
    elif [ "$d" -lt 86400 ]; then ago="$((d / 3600))h ago"
    else                          ago="$((d / 86400))d ago"
    fi
  fi
  branch=""
  [ -d "$cwd" ] && branch="$(git -C "$cwd" branch --show-current 2>/dev/null)"
  printf '↺ resume · %s%s\n' "$ago" "${branch:+ · $branch}"
  printf '%s%s%s\n' "$C_DIM" "${cwd/#$HOME/\~}" "$C_RESET"
  printf '%s────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
  # Conversation tail: user prompts prefixed with ❯, assistant text plain.
  # jq -R + fromjson? skips malformed/huge lines instead of aborting.
  tail -200 "$jsonl" | jq -Rr '
    fromjson?
    | select(.type == "user" or .type == "assistant")
    | select(.isSidechain != true)
    | (.message.role // .type) as $r
    | (.message.content
       | if type == "string" then .
         else ([.[]? | select(.type == "text") | .text] | join(" "))
         end) as $t
    | select($t != null and $t != "")
    | (if $r == "user" then "❯ " else "" end) + ($t | gsub("\\s+"; " ") | .[0:500]) + "\n"
  ' 2>/dev/null | tail -60
  exit 0
fi

# Status: same heuristics as claude-panes.sh (spinner status line = working,
# permission/question prompt = input). bash matching with nocasematch, NOT
# grep/tr: `grep` here can be ugrep and `tr` is GNU coreutils (gnubin),
# byte-oriented -- it corrupts the multibyte "·" in the spinner line.
shopt -s nocasematch
working_re='… \([0-9]+m? ?[0-9]*s( ·|\))'
bottom="$(tmux capture-pane -p -t "$pane" 2>/dev/null | awk 'NF' | tail -8)"
if [[ "$bottom" == *"esc to interrupt"* || "$bottom" =~ $working_re ]]; then
  status="working"; dot="${C_GREEN}●${C_RESET}"
elif [[ "$bottom" == *"esc to cancel"* ]]; then
  status="input";   dot="${C_YELLOW}●${C_RESET}"
else
  status="idle";    dot="${C_DIM}●${C_RESET}"
fi

model="?"; ctx="?"; ago="?"; branch=""; cwd=""

# Agent kind: OpenCode panes have no Claude metadata -- short header + tail.
tty="$(tmux display-message -p -t "$pane" '#{pane_tty}' 2>/dev/null)"
procs="$(ps -t "${tty#/dev/}" -o command= 2>/dev/null)"
if [[ "$procs" != *claude* && "$procs" == *opencode* ]]; then
  cwd="$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null)"
  branch="$(git -C "$cwd" branch --show-current 2>/dev/null)"
  printf '%s %s · opencode%s\n' "$dot" "$status" "${branch:+ · $branch}"
  printf '%s%s%s\n' "$C_DIM" "${cwd/#$HOME/\~}" "$C_RESET"
  printf '%s────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
  tmux capture-pane -e -p -S -200 -t "$pane"
  exit 0
fi

# Claude's PID via the pane tty (works when claude was started from a shell,
# where #{pane_pid} would be the shell). Its {PID}.json links to the JSONL.
cpid="$(ps -t "${tty#/dev/}" -o pid=,command= 2>/dev/null | awk '/claude/ {print $1; exit}')"
meta="$HOME/.claude/sessions/${cpid:-none}.json"
if [ -r "$meta" ] && command -v jq >/dev/null 2>&1; then
  sid="$(jq -r '.sessionId // empty' "$meta" 2>/dev/null)"
  cwd="$(jq -r '.cwd // empty' "$meta" 2>/dev/null)"
  jsonl=""
  if [ -n "$sid" ]; then
    # Session ids are unique: glob across project dirs instead of re-deriving
    # Claude's cwd -> directory-name encoding.
    for f in "$HOME/.claude/projects/"*/"$sid".jsonl; do
      [ -r "$f" ] && { jsonl="$f"; break; }
    done
  fi
  if [ -n "$jsonl" ]; then
    tail_data="$(tail -c 300000 "$jsonl" 2>/dev/null)"
    m="$(printf '%s' "$tail_data" | grep -o '"model":"[^"]*"' | tail -1 | cut -d'"' -f4)"
    [ -n "$m" ] && model="${m#claude-}"
    # Context = input + cache tokens of the most recent usage entry.
    toks="$(printf '%s' "$tail_data" | grep '"usage"' | tail -1 \
      | jq -r '.message.usage | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))' 2>/dev/null)"
    case "$toks" in
      ''|*[!0-9]*) ;;
      *) if [ "$toks" -ge 1000 ]; then ctx="$((toks / 1000))k"; else ctx="$toks"; fi ;;
    esac
    # Last activity = the transcript's mtime. perl for portability: plain
    # `stat` on this machine is GNU coreutils (gnubin), not BSD.
    mtime="$(perl -e 'print((stat($ARGV[0]))[9] // 0)' "$jsonl" 2>/dev/null)"
    if [ "${mtime:-0}" -gt 0 ]; then
      d=$(( $(date +%s) - mtime ))
      if   [ "$d" -lt 60 ];    then ago="now"
      elif [ "$d" -lt 3600 ];  then ago="$((d / 60))m ago"
      elif [ "$d" -lt 86400 ]; then ago="$((d / 3600))h ago"
      else                          ago="$((d / 86400))d ago"
      fi
    fi
  fi
fi
[ -n "$cwd" ] && branch="$(git -C "$cwd" branch --show-current 2>/dev/null)"

# Exactly 3 header lines (stats / cwd / separator): the picker pins them with
# --preview-window '~3' while `follow` keeps the live bottom of the capture in
# view; 200 lines of scrollback give ctrl-u/d something to scroll through.
printf '%s %s · %s · ctx %s · %s%s\n' \
  "$dot" "$status" "$model" "$ctx" "$ago" "${branch:+ · $branch}"
printf '%s%s%s\n' "$C_DIM" "${cwd/#$HOME/\~}" "$C_RESET"
printf '%s────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
tmux capture-pane -e -p -S -200 -t "$pane"
