#!/usr/bin/env bash
# List every pane running a coding agent (Claude Code, OpenCode) across ALL
# sessions, one per line:
#   pane_id <TAB> session_name <TAB> label <TAB> status <TAB> agent
# Panes come out grouped by session (tmux lists sessions in name order).
# Shared by claude-cycle.sh (Cmd+Up/Down) and claude-picker.sh (fzf popup).
#
# Detection mirrors rename-to-topic.sh: pane_current_command shows Claude as
# "claude", "node" or a bare version number (the versioned binary), OpenCode
# as "opencode"; the ambiguous ones are confirmed by looking for the agent in
# the pane tty's process list.
#
# The label is the FULL conversation topic as published in the pane title
# (spinner stripped); fallbacks: the LLM-shortened @claude_topic, then the
# pane's directory name.
#
# status is one of working/input/idle, detected by scanning the pane's bottom
# lines for Claude Code's UI markers: the spinner status line while working
# ("esc to interrupt" in older CC, "Word… (3m 52s · ...)" in current CC) and
# "esc to cancel" on a permission/question prompt. OpenCode markers are not
# mapped yet -- its panes read as idle.
#
# pane_title is free text and may contain "|", so it goes LAST in the format
# and `read` folds the remainder into it.

# bash matching with nocasematch, NOT grep/tr: `grep` here can be ugrep and
# `tr` is GNU coreutils (gnubin) -- byte-oriented, it corrupts the multibyte
# "·" in the spinner line. Same family of trap as the GNU stat note in
# rename-to-topic.sh.
shopt -s nocasematch
WORKING_RE='… \([0-9]+m? ?[0-9]*s( ·|\))'

tmux list-panes -a \
  -F '#{pane_id}|#{session_name}|#{pane_current_command}|#{pane_tty}|#{pane_current_path}|#{@claude_topic}|#{pane_title}' \
  2>/dev/null |
while IFS='|' read -r pid sess cmd tty path topic title; do
  agent=""
  case "$cmd" in
    claude*)   agent="claude" ;;          # the CLI itself -> definitely Claude
    opencode*) agent="opencode" ;;
    node|[0-9]*.[0-9]*)                   # ambiguous -> verify via the pane's tty
      procs="$(ps -t "${tty#/dev/}" -o command= 2>/dev/null)"
      if [[ "$procs" == *claude* ]]; then agent="claude"
      elif [[ "$procs" == *opencode* ]]; then agent="opencode"
      fi
      ;;
  esac
  [ -n "$agent" ] || continue            # plain shells / other commands -> never

  label="$(printf '%s' "$title" | sed -E 's/^[^A-Za-z0-9]*//; s/[[:space:]]+$//')"
  [ "$label" = "$cmd" ] && label=""      # title is just the command name
  [ -n "$label" ] || label="$topic"
  [ -n "$label" ] || label="${path##*/}"
  [ -n "$label" ] || label="(no topic)"

  bottom="$(tmux capture-pane -p -t "$pid" 2>/dev/null | awk 'NF' | tail -8)"
  if [[ "$bottom" == *"esc to interrupt"* || "$bottom" =~ $WORKING_RE ]]; then
    status="working"
  elif [[ "$bottom" == *"esc to cancel"* ]]; then
    status="input"
  else
    status="idle"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$sess" "$label" "$status" "$agent"
done
