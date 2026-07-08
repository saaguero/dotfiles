#!/bin/bash
# Load the shell dotfiles, and then some:
# * ~/.path can be used to extend `$PATH`.
# * ~/.extra can be used for other settings you don’t want to commit.

# If you want to troubleshoot (or simply profile) your bash scripts
# uncomment both "profiling start" & "profiling end" sections
# source: http://stackoverflow.com/a/5015179/854676

# profiling start
# date "+%s.%N"
# PS4='+ $(date "+%s.%N")\011 '
# exec 3>&2 2>/tmp/bashstart.$$.log

[ -z "$XDG_CONFIG_HOME" ] && export XDG_CONFIG_HOME=$HOME/.config

# rg doesn't suport XDG_CONFIG_HOME, but we can point it using its env var
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"

export BASH_SILENCE_DEPRECATION_WARNING=1

# Use ~/.extra for things you don't want to commit
for file in ~/.{bash_prompt,exports,functions,extra,aliases}; do
	[ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

# Deferred completions. The FIRST Tab on a command with no
# compspec fires the `complete -D` bootstrap, which loads everything and
# returns 124 so readline RETRIES the same Tab press (completion functions
# don't redraw the prompt, unlike the bind -x hook that caused the flash).
__load_completions() {
	[ -n "${__completions_loaded:-}" ] && return 0
	__completions_loaded=1
	source ~/.completions
	source ~/.complete_alias
	source /opt/homebrew/opt/fzf/shell/completion.bash
}
__load_completions_first_tab() {
	complete -r -D 2>/dev/null   # drop this bootstrap (bash-completion installs its own -D)
	__load_completions
	return 124                   # readline: retry the completion, specs now exist
}
complete -D -F __load_completions_first_tab
__load_completions_precmd() {
	if [ -z "${__completions_armed:-}" ]; then
		__completions_armed=1   # first prompt: skip, keep startup fast
		return
	fi
	__load_completions
}
PROMPT_COMMAND="__load_completions_precmd;${PROMPT_COMMAND:+$PROMPT_COMMAND}"

# fzf: key bindings (Ctrl-R etc.) eagerly from brew's static file (no fork)
source /opt/homebrew/opt/fzf/shell/key-bindings.bash
source ~/.local/bin/z.sh

# Case-insensitive globbing (used in pathname expansion)
shopt -s nocaseglob
# Autocorrect typos in path names when using `cd`
shopt -s cdspell

# disable ctrl-s "freeze" feature
stty -ixon

# profiling end
# set +x
# exec 2>&3 3>&-

# fzf: directly execute the command for history with CTRL_X+CTRL_R
bind "$(bind -s | grep '^"\\C-r"' | sed 's/"/"\\C-x/' | sed 's/"$/\\C-m"/')"
# bind c-f to open tmux-sessionizer
bind -x '"\C-f": tmux-sessionizer'

# Login shells (every tmux pane / Ghostty tab on macOS) read only this file;
# non-login interactive shells read only .bashrc — sourcing it here keeps both
# consistent. Kept AT THE END on purpose: .bashrc must run after .bash_prompt
# (its prompt setup — starship, when enabled — has to win) and its PATH
# entries (nvm node, opencode) should take precedence.
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
