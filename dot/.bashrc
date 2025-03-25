#!/bin/bash

if [ -z "$XDG_CONFIG_HOME" ]; then
    XDG_CONFIG_HOME=$HOME/.config
fi

[ -n "$PS1" ] && source ~/.bash_profile
