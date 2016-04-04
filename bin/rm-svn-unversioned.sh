svn status | grep ^\? | cut -c9- | xargs -d \\n rm -r
