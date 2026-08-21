#!/usr/bin/env bash
# fzf picker over agent conversations, meant for a tmux popup (prefix+P /
# Ghostty Cmd+P). Two modes, toggled with ctrl-r (the fzf prompt string IS the
# mode state, read back via $FZF_PROMPT in transform bindings):
#
#   agents>  live panes (Claude Code, OpenCode) across all tmux sessions.
#            Line: "● topic   session · agent" (green=working, yellow=input,
#            dim=idle). Enter jumps to the pane. Auto-refreshes.
#   resume>  every past Claude Code conversation (~/.claude/projects JSONLs),
#            newest first, minus the ones currently live. Enter resumes it with
#            `claude --resume <id>` in yolo mode: a NEW WINDOW in the session
#            already rooted at the conversation's cwd if one exists, otherwise a
#            NEW tmux session in that cwd.
#   search>  (ctrl-f) same list, but the query greps the CONTENT of every
#            transcript (rg, live on each keystroke -- 474MB takes ~0.25s, no
#            index needed) instead of fzf filtering the visible titles. Terms
#            are ANDed per file and accent-insensitive both ways ("coleccion"
#            finds "colección" and vice versa; fzf's own latin normalization
#            only works plain->accented). Enter resumes, same as resume mode.
#
# The hidden first field disambiguates what Enter got: a %pane_id -> jump,
# a session uuid -> resume. claude-preview.sh branches on the same value.

PANES="$HOME/.config/tmux/claude-panes.sh"
PREVIEW="$HOME/.config/tmux/claude-preview.sh"
REFRESH_SECS=5
SEARCH_DEBOUNCE_SECS=0.4
HEADER_LIVE='enter: jump | ctrl-r: resume list | ctrl-f: content search | ctrl-u/d: scroll preview'
HEADER_RESUME='enter: resume in NEW session, yolo | ctrl-f: content search | ctrl-r: live agents'
HEADER_SEARCH='type 3+ chars: grep INSIDE all conversations | enter: resume (● live: jump) | ctrl-f: back'

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

expand_terms() {
  # One accent-insensitive rg pattern PER LINE from the words of $1: query is
  # lowercased (rg -i covers case anyway), regex-escaped, then every vowel/n --
  # plain or accented -- becomes a class matching both spellings, in a SINGLE
  # pass (sequential s/// would re-expand the inserted classes). perl -CS
  # decodes the STREAMS only; -Mutf8 is also needed so the accented literals
  # in the program text itself are characters, not byte pairs (without it the
  # classes come out as mojibake and accented queries match nothing).
  printf '%s' "$1" | perl -CS -Mutf8 -ne '
    BEGIN { %m = ("a","[aá]","á","[aá]","e","[eé]","é","[eé]","i","[ií]","í","[ií]",
                  "o","[oó]","ó","[oó]","u","[uúü]","ú","[uúü]","ü","[uúü]","n","[nñ]","ñ","[nñ]") }
    for my $t (split " ", lc $_) {
      $t = quotemeta $t;
      $t =~ s/\\?([aáeéiíoóuúünñ])/$m{$1}/g;
      print "$t\n";
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
  # rename-to-topic hook's headless haiku prompts). Args, if any, restrict the
  # scan to those transcript files (the search mode passes its rg matches).
  #
  # Live sessions are normally skipped (they belong to the agents view), but
  # with INCLUDE_LIVE=1 (search mode) a live match shows with a green dot and
  # its PANE id as the hidden key, so Enter jumps instead of resuming --
  # otherwise a content hit in a live conversation silently vanishes.
  local live="" panemap="" f pid sid tty pane
  local files=("$@")
  [ "${#files[@]}" -gt 0 ] || files=("$HOME"/.claude/projects/*/*.jsonl)
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -r "$f" ] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    sid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || continue
    live="$live $sid"
    if [ -n "${INCLUDE_LIVE:-}" ]; then
      # sid -> pane id, via the claude process's tty (headless sessions have
      # no pane and stay hidden even in search mode).
      tty="$(ps -o tty= -p "$pid" 2>/dev/null | awk 'NF {print $1; exit}')"
      [ -n "$tty" ] && [ "$tty" != "??" ] || continue
      pane="$(tmux list-panes -a -F '#{pane_tty} #{pane_id}' 2>/dev/null \
        | awk -v t="/dev/$tty" '$1 == t {print $2; exit}')"
      [ -n "$pane" ] && panemap="$panemap $sid=$pane"
    fi
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
    }' "${files[@]}" 2>/dev/null \
  | sort -rn \
  | LIVE="$live" PANEMAP="$panemap" perl -CS -F'\t' -lane '
      BEGIN {
        %alive = map { $_ => 1 } split " ", ($ENV{LIVE} // "");
        %pane  = map { split /=/ } split " ", ($ENV{PANEMAP} // "");
        $now = time;
      }
      next if $alive{$F[1]} && !$pane{$F[1]};
      my $t = length($F[3]) > 80 ? substr($F[3], 0, 79) . "\x{2026}" : $F[3];
      push @R, [@F]; push @T, $t;
      $w = length($t) if length($t) > $w;
      END {
        my ($g, $d, $r) = ("\e[32m", "\e[90m", "\e[0m");
        for my $i (0 .. $#R) {
          my ($m, $sid, $cwd) = @{$R[$i]};
          my $age = $now - $m;
          my $a = $age < 60 ? "now" : $age < 3600 ? int($age/60) . "m"
                : $age < 86400 ? int($age/3600) . "h" : int($age/86400) . "d";
          (my $proj = $cwd) =~ s{/+$}{}; $proj =~ s{.*/}{}; $proj = "?" if $proj eq "";
          my ($key, $dot) = $pane{$sid}
            ? ($pane{$sid}, "$g\x{25CF}$r") : ($sid, "$d\x{21BA}$r");
          printf "%s\t%s %s%s  %s%s \x{B7} %s%s\t%s\n",
            $key, $dot, $T[$i], " " x ($w - length($T[$i])), $d, $proj, $a, $r, $cwd;
        }
      }'
}

build_search_list() {
  # Content search: narrow the transcript set with one rg -li pass per term
  # (AND across terms within a file), then render the survivors through the
  # normal resume-list pipeline (title, project, age, newest first). Under 3
  # typed chars just show the full list -- same view as resume mode. $FZF_QUERY
  # comes from fzf's environment (the windowizer's {q}-quoting lesson: never
  # interpolate the query into an action string). Unquoted mapfile input is
  # safe: project dir encoding replaces every odd char with dashes, no spaces.
  local q="${FZF_QUERY:-}" typed="${FZF_QUERY:-}" pat
  typed="${typed// /}"
  if [ "${#typed}" -lt 3 ]; then INCLUDE_LIVE=1 build_resume_list; return; fi
  local files=("$HOME"/.claude/projects/*/*.jsonl)
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    mapfile -t files < <(rg -li --no-messages -e "$pat" "${files[@]}" 2>/dev/null)
    [ "${#files[@]}" -gt 0 ] || return 0
  done < <(expand_terms "$q")
  INCLUDE_LIVE=1 build_resume_list "${files[@]}"
}

case "${1:-}" in
  --list)        build_display; exit 0 ;;
  --resume-list) build_resume_list; exit 0 ;;
  --search-list) build_search_list; exit 0 ;;
  --pattern)
    # Alternation of all expanded terms, for the preview's match extraction.
    expand_terms "${FZF_QUERY:-}" | paste -sd'|' - | sed 's/^|*//;s/|*$//'
    exit 0
    ;;
  --search-change)
    # change transform: live regrep only in search mode (elsewhere the query
    # is fzf's own filter and reloading would fight it). The leading sleep is
    # the standard fzf debounce (its own ADVANCED.md ripgrep recipe): a new
    # keystroke kills the in-flight reload, so only the pause after the LAST
    # keystroke actually runs the grep -- typing stays smooth.
    case "${FZF_PROMPT:-}" in
      search*) printf 'reload-sync(sleep %s; %s --search-list)+refresh-preview' \
                 "$SEARCH_DEBOUNCE_SECS" "$0" ;;
    esac
    exit 0
    ;;
  --toggle-search)
    # ctrl-f transform: resume/agents -> search (fzf filtering off, keystrokes
    # feed the regrep), search -> resume (filtering back on).
    #
    # +toggle-track: fzf 0.74.1 DROPS typed keys while a reload is in flight
    # when --track is combined with --id-nth (either flag alone is fine) --
    # in search mode, where every keystroke reloads, typing "kiosco" landed
    # as "kc". Tracking only matters in the agents view (keep the cursor on
    # the same pane across auto-refreshes), so it goes OFF entering search>
    # and back ON leaving. Same invariant style as the sessionizer's try>
    # sort toggle: EVERY transition in/out of search> toggles exactly once
    # (entry here, exits here and in --toggle-mode's search branch).
    if [[ "${FZF_PROMPT:-}" == search* ]]; then
      printf 'change-prompt[resume> ]+change-header[%s]+enable-search+clear-query+toggle-track+reload[%s --resume-list]+first' "$HEADER_RESUME" "$0"
    else
      printf 'change-prompt[search> ]+change-header[%s]+disable-search+clear-query+toggle-track+reload-sync[%s --search-list]+first' "$HEADER_SEARCH" "$0"
    fi
    exit 0
    ;;
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
    elif [[ "${FZF_PROMPT:-}" == search* ]]; then
      # leaving search: re-enable fzf filtering, drop the content query (as a
      # title filter it would silently hide everything), re-enable tracking
      # (see --toggle-search's toggle-track invariant).
      printf 'change-prompt[agents> ]+change-header[%s]+enable-search+clear-query+toggle-track+reload-sync[%s --list]+first' "$HEADER_LIVE" "$0"
    else
      printf 'change-prompt[agents> ]+change-header[%s]+reload-sync[%s --list]+first' "$HEADER_LIVE" "$0"
    fi
    exit 0
    ;;
esac

# Open even with zero live agents: fzf just shows an empty (0/0) list and
# ctrl-r still switches to the resume view of past conversations. build_display
# is piped directly so an empty result yields no lines (not one blank entry).
# --no-sort: keep input order (chronological in resume mode) even while a
# query is typed -- by default fzf re-ranks matches by score, which shuffled
# 21d entries above 4d ones. --exact to match: fuzzy matching over full lines
# (title + project + age) makes nearly everything a match, so filtering by
# substring is what you actually want ('-prefix a term to go fuzzy).
sel="$(build_display | fzf \
  --ansi --delimiter '\t' --with-nth 2 --track --id-nth 1 \
  --no-sort --exact \
  --prompt 'agents> ' \
  --header "$HEADER_LIVE" \
  --preview "$PREVIEW {1} {3}" \
  --preview-window 'right,40%,border-left,follow,wrap,~3' \
  --bind 'ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down' \
  --bind "every(${REFRESH_SECS}):transform:$0 --auto-refresh" \
  --bind "ctrl-r:transform:$0 --toggle-mode" \
  --bind "ctrl-f:transform:$0 --toggle-search" \
  --bind "change:transform:$0 --search-change" \
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
    # Past conversation -> resume it in yolo mode. If a tmux session is already
    # rooted at this cwd, open a NEW WINDOW in it instead of spawning a second
    # session with a "-2" suffix; only mint a fresh session when no existing
    # one shares the path. Match on #{session_path} (the dir the session was
    # started in), not the name -- two projects with the same basename should
    # stay separate sessions.
    [ -d "$cwd" ] || cwd="$HOME"
    existing=""
    while IFS=$'\t' read -r spath sname; do
      [ "$spath" = "$cwd" ] || continue
      existing="$sname"; break
    done < <(tmux list-sessions -F '#{session_path}'$'\t''#{session_name}' 2>/dev/null)

    if [ -n "$existing" ]; then
      # Reuse the matching session: new window there resuming the conversation.
      win="$(tmux new-window -d -t "=$existing" -c "$cwd" -P -F '#{window_id}' \
        "claude --dangerously-skip-permissions --resume $key" 2>/dev/null)"
      sleep 0.4
      if [ -n "$win" ] && \
         tmux list-windows -t "=$existing" -F '#{window_id}' 2>/dev/null | grep -qxF "$win"; then
        tmux switch-client -t "=$existing" 2>/dev/null
        tmux select-window -t "$win" 2>/dev/null
      else
        tmux display-message "resume failed: claude exited immediately ($key)"
      fi
    else
      # No session at this path yet -> mint a fresh one.
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
    fi
    ;;
esac
