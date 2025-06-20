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
for file in ~/.{bash_prompt,exports,functions,extra,completions,complete_alias,aliases}; do
	[ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

# Case-insensitive globbing (used in pathname expansion)
shopt -s nocaseglob
# Append to the Bash history file, rather than overwriting it
shopt -s histappend
# Append to history immediately
PROMPT_COMMAND="history -a;$PROMPT_COMMAND"
# Autocorrect typos in path names when using `cd`
shopt -s cdspell

eval "$(fzf --bash)"
source ~/.local/bin/z.sh

# disable ctrl-s "freeze" feature
stty -ixon

# profiling end
# set +x
# exec 2>&3 3>&-

# fzf: directly execute the command for history with CTRL_X+CTRL_R
bind "$(bind -s | grep '^"\\C-r"' | sed 's/"/"\\C-x/' | sed 's/"$/\\C-m"/')"
# bind c-f to open tmux-sessionizer
bind -x '"\C-f": tmux-sessionizer'

# TODO: Is this a good place to source form?
[ -f $HOME/.bashrc ] && source $HOME/.bashrc
