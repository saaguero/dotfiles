#!/bin/bash
# Adapted from https://github.com/nicknisi/dotfiles

echo "creating symlinks"
linkables=$( find -H "." -maxdepth 3 -name '*.link' )
for file in $linkables ; do
    target="$HOME/.$( basename $file ".link" )"
    if [ -f "$target" ]; then
      mv "${target}" "${target}.bak"
    fi
    echo "creating symlink for $file"
    ln -s "${file}" "${target}"
done
