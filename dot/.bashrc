#!/bin/bash

# This is sourced from ~/.bash_profile

# History settings must live in .bashrc too because many terminal integrations
# start non-login interactive shells that do not read .bash_profile.
# Only continue in interactive shells; skip for scripts/non-interactive runs.
case "$-" in
	*i*) ;;
	*) return ;;
esac

# Append to the bash history file, rather than overwriting it
shopt -s histappend
# Handle multi-line commands correctly in bash history
shopt -s lithist
# Append to history immediately
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
