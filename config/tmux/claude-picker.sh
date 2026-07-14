#!/usr/bin/env bash
# fzf picker over agent conversations, meant for a tmux popup (prefix+P /
# Ghostty Cmd+P). Two modes, toggled with ctrl-r (the fzf prompt string IS the
# mode state, read back via $FZF_PROMPT in transform bindings):
#
#   agents>  live panes (Claude Code, OpenCode) across all tmux sessions.
#            Line: "● topic   session · agent" (green=working, yellow=input,
#            dim=idle). Enter jumps to the pane. Auto-refreshes.
#   resume>  every past Claude Code conversation (~/.claude/projects JSONLs),
#            newest first, minus the ones currently live. Enter opens a NEW
#            tmux session in the conversation's cwd resuming it with
#            `claude --resume <id>` in yolo mode.
#
# The hidden first field disambiguates what Enter got: a %pane_id -> jump,
# a session uuid -> resume. claude-preview.sh branches on the same value.

PANES="$HOME/.config/tmux/claude-panes.sh"
PREVIEW="$HOME/.config/tmux/claude-preview.sh"
REFRESH_SECS=5
HEADER_LIVE='enter: jump | ctrl-r: resume list | ctrl-u/d: scroll preview'
HEADER_RESUME='enter: resume in NEW session, yolo | ctrl-r: live agents'

build_display() {
  # "● topic   session · agent": the conversation is the primary field (what
  # you scan for), padded into a column; session + provider follow dimmed --
  # the session stays because unnamed conversations are told apart by it. The
  # pane id stays as a hidden first field (fzf --with-nth 2).
  # perl -CS, NOT awk: padding must count CHARACTERS -- macOS awk counts bytes
  # and rejects octal byte classes, so accented titles shifted the metadata
  # column left. perl length() under -CS is character-based, end of story.
  "$PANES" | perl -CS -F'\t' -lane '
    my $t = length($F[2]) > 80 ? substr($F[2], 0, 79) . "\x{2026}" : $F[2];
    push @R, [@F]; push @T, $t;
    $w = length($t) if length($t) > $w;
    END {
      my ($g, $y, $d, $r) = ("\e[32m", "\e[33m", "\e[90m", "\e[0m");
      for my $i (0 .. $#R) {
        my ($pid, $sess, undef, $st, $ag) = @{$R[$i]};
        my $dot = ($st eq "working" ? $g : $st eq "input" ? $y : $d) . "\x{25CF}" . $r;
        printf "%s\t%s %s%s  %s%s \x{B7} %s%s\n",
          $pid, $dot, $T[$i], " " x ($w - length($T[$i])), $d, $sess, $ag, $r;
      }
    }'
}

build_resume_list() {
  # session_id <TAB> "↺ title   project · age" <TAB> cwd, newest first.
  # One perl pass over the first+last 32KB of every transcript: session id
  # from the filename, cwd, and the title Claude Code itself generated (the
  # "ai-title" record -- the same one the native /resume shows; the newest
  # occurrence wins since it gets re-generated as the conversation evolves).
  # Fallback title: the first real user prompt (skipping the "Caveat:"
  # preamble of previously-resumed sessions, slash-command records, and the
  # rename-to-topic hook's headless haiku prompts).
  local live="" f pid sid
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -r "$f" ] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    sid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && live="$live $sid"
  done

  perl -e '
    for my $f (@ARGV) {
      open my $fh, "<", $f or next;
      read $fh, my $buf, 32768;
      my $tailbuf = "";
      my $size = -s $f;
      if ($size > 32768) {
        seek $fh, $size - 32768, 0;
        read $fh, $tailbuf, 32768;
      }
      close $fh;
      my ($sid) = $f =~ m{([0-9a-f]{8}-[0-9a-f-]{27})\.jsonl$} or next;
      # rename-to-topic hook noise: headless sessions whose payload is the
      # label-shortening prompt (as queued op or user message in the head).
      next if $buf =~ /"content":"Give ONLY a [\d-]*\s*word label/;
      my ($cwd) = $buf =~ /"cwd":"((?:[^"\\]|\\.)*)"/;
      my $title = "";
      for my $b ($tailbuf, $buf) {           # tail first: newest ai-title wins
        while ($b =~ /"type":"ai-title","aiTitle":"((?:[^"\\]|\\.)*)"/g) { $title = $1 }
        last if $title ne "";
      }
      if ($title eq "") {
        while ($buf =~ /"type":"user","message":\{"role":"user","content":"((?:[^"\\]|\\.)*)"/g) {
          my $t = $1;
          next if $t =~ /^(Caveat: The messages below|<command-name>|<local-command)/;
          next if $t =~ /^Give ONLY a [\d-]*\s*word label/;   # rename-hook noise (all prompt versions)
          $title = $t; last;
        }
      }
      # no ai-title AND no real prompt -> slash-command-only session (junk:
      # /keybindings, /config...); nothing to resume, drop it.
      next if $title eq "";
      $title =~ s/\\[ntr]/ /g; $title =~ s/\\"/"/g; $title =~ s/\s+/ /g;
      $title = substr($title, 0, 120);
      $cwd //= ""; $cwd =~ s/\\\//\//g;
      my $m = (stat $f)[9] // 0;
      print "$m\t$sid\t$cwd\t$title\n";
    }' "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null \
  | sort -rn \
  | LIVE="$live" perl -CS -F'\t' -lane '
      BEGIN { %alive = map { $_ => 1 } split " ", ($ENV{LIVE} // ""); $now = time }
      next if $alive{$F[1]};
      my $t = length($F[3]) > 80 ? substr($F[3], 0, 79) . "\x{2026}" : $F[3];
      push @R, [@F]; push @T, $t;
      $w = length($t) if length($t) > $w;
      END {
        my ($d, $r) = ("\e[90m", "\e[0m");
        for my $i (0 .. $#R) {
          my ($m, $sid, $cwd) = @{$R[$i]};
          my $age = $now - $m;
          my $a = $age < 60 ? "now" : $age < 3600 ? int($age/60) . "m"
                : $age < 86400 ? int($age/3600) . "h" : int($age/86400) . "d";
          (my $proj = $cwd) =~ s{/+$}{}; $proj =~ s{.*/}{}; $proj = "?" if $proj eq "";
          printf "%s\t%s\x{21BA}%s %s%s  %s%s \x{B7} %s%s\t%s\n",
            $sid, $d, $r, $T[$i], " " x ($w - length($T[$i])), $d, $proj, $a, $r, $cwd;
        }
      }'
}

case "${1:-}" in
  --list)        build_display; exit 0 ;;
  --resume-list) build_resume_list; exit 0 ;;
  --auto-refresh)
    # every(N) transform: only the live view auto-reloads; the resume list is
    # static history and reloading it would also reset the cursor.
    case "${FZF_PROMPT:-}" in
      agents*) printf 'reload-sync(%s --list)+refresh-preview' "$0" ;;
    esac
    exit 0
    ;;
  --toggle-mode)
    # ctrl-r transform: flip between the two views (brackets as action arg
    # delimiters -- the header text contains parentheses-unsafe characters).
    if [[ "${FZF_PROMPT:-}" == agents* ]]; then
      printf 'change-prompt[resume> ]+change-header[%s]+reload[%s --resume-list]+first' "$HEADER_RESUME" "$0"
    else
      printf 'change-prompt[agents> ]+change-header[%s]+reload-sync[%s --list]+first' "$HEADER_LIVE" "$0"
    fi
    exit 0
    ;;
esac

# Open even with zero live agents: fzf just shows an empty (0/0) list and
# ctrl-r still switches to the resume view of past conversations. build_display
# is piped directly so an empty result yields no lines (not one blank entry).
sel="$(build_display | fzf \
  --ansi --delimiter '\t' --with-nth 2 --track --id-nth 1 \
  --prompt 'agents> ' \
  --header "$HEADER_LIVE" \
  --preview "$PREVIEW {1} {3}" \
  --preview-window 'right,40%,border-left,follow,wrap,~3' \
  --bind 'ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down' \
  --bind "every(${REFRESH_SECS}):transform:$0 --auto-refresh" \
  --bind "ctrl-r:transform:$0 --toggle-mode" \
)" || exit 0

IFS=$'\t' read -r key _ cwd <<EOF
$sel
EOF
[ -n "$key" ] || exit 0

case "$key" in
  %*)
    # Live pane -> jump to its session/window/pane.
    read -r sess_id win_id <<EOF2
$(tmux display-message -p -t "$key" '#{session_id} #{window_id}')
EOF2
    tmux switch-client -t "$sess_id" 2>/dev/null
    tmux select-window -t "$win_id" 2>/dev/null
    tmux select-pane -t "$key" 2>/dev/null
    ;;
  *)
    # Past conversation -> resume it in a NEW tmux session (yolo mode).
    [ -d "$cwd" ] || cwd="$HOME"
    name="${cwd##*/}"; name="${name//[.: ]/-}"; [ -n "$name" ] || name="resume"
    base="$name"; n=2
    while tmux has-session -t "=$name" 2>/dev/null; do
      name="$base-$n"; n=$((n + 1))
    done
    tmux new-session -d -s "$name" -c "$cwd" \
      "claude --dangerously-skip-permissions --resume $key" 2>/dev/null
    sleep 0.4
    if tmux has-session -t "=$name" 2>/dev/null; then
      tmux switch-client -t "=$name" 2>/dev/null
    else
      tmux display-message "resume failed: claude exited immediately ($key)"
    fi
    ;;
esac
