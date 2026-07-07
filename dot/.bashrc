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

. "$HOME/.local/bin/env"

export NVM_DIR="$HOME/.config/nvm"
# nvm: lazy-loaded (the real load costs ~150ms at every shell startup).
# The default version's bin dir goes straight on PATH so node/npm/npx work
# immediately; the `nvm` command itself loads the real nvm on first use.
if [ -s "$NVM_DIR/nvm.sh" ]; then
    if [ -r "$NVM_DIR/alias/default" ]; then
        _nvm_default=$(<"$NVM_DIR/alias/default")
        [ -d "$NVM_DIR/versions/node/v${_nvm_default#v}/bin" ] && \
            PATH="$NVM_DIR/versions/node/v${_nvm_default#v}/bin:$PATH"
        unset _nvm_default
    fi
    nvm() {
        unset -f nvm
        \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        nvm "$@"
    }
fi
