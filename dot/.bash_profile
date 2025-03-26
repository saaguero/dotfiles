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

export DEV_ENV_HOME="$HOME/dotfiles"

[ -z "$XDG_CONFIG_HOME" ] && export XDG_CONFIG_HOME=$HOME/.config


export BASH_SILENCE_DEPRECATION_WARNING=1

for file in ~/.{path,bash_prompt,exports,aliases,functions,extra,completions}; do
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

[ -f ~/.fzf.bash ] && source ~/.fzf.bash
[ -f ~/dotfiles/bin/z.sh ] && source ~/dotfiles/bin/z.sh

# disable ctrl-s "freeze" feature
stty -ixon

# profiling end
# set +x
# exec 2>&3 3>&-

alias assume=". assume"

# Directly execute the command for history with (CTRL_X CTRL_R)
bind "$(bind -s | grep '^"\\C-r"' | sed 's/"/"\\C-x/' | sed 's/"$/\\C-m"/')"
# bind c-f to open tmux-sessionizer
bind -x '"\C-f": tmux-sessionizer'

# TODO: Is this a good place to source form?
[ -f $HOME/.bashrc ] && source $HOME/.bashrc
