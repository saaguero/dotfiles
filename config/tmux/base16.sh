# Base1 Styling Guidelines:

base00=default   # - Default
base01='#151515' # - Lighter Background (Used for status bars)
base02='#202020' # - Selection Background
base03='#909090' # - Comments, Invisibles, Line Highlighting
base04='#505050' # - Dark Foreground (Used for status bars)
base05='#D0D0D0' # - Default Foreground, Caret, Delimiters, Operators
base06='#E0E0E0' # - Light Foreground (Not often used)
base07='#F5F5F5' # - Light Background (Not often used)
base08='#AC4142' # - Variables, XML Tags, Markup Link Text, Markup Lists, Diff Deleted
base09='#D28445' # - Integers, Boolean, Constants, XML Attributes, Markup Link Url
base0A='#F4BF75' # - Classes, Markup Bold, Search Text Background
base0B='#90A959' # - Strings, Inherited Class, Markup Code, Diff Inserted
base0C='#75B5AA' # - Support, Regular Expressions, Escape Characters, Markup Quotes
base0D='#6A9FB5' # - Functions, Methods, Attribute IDs, Headings
base0E='#AA759F' # - Keywords, Storage, Selector, Markup Italic, Diff Changed
base0F='#8F5536' # - Deprecated, Opening/Closing Embedded Language Tags, e.g. <? php ?>

set -g status-left-length 32
set -g status-right-length 150
set -g status-interval 5

# default statusbar colors — solid background so the bar reads apart from
# the app below (single line, no separator needed; HolaMundo/omarchy style)
set-option -g status-style fg=$base05,bg=$base01

set-window-option -g window-status-style fg=$base03,bg=$base01
set-window-option -g window-status-format " #I:#W "

# active window = bright accent text (the block goes on the session name)
set-window-option -g window-status-current-style fg=$base0D,bg=$base01,bold
set-window-option -g window-status-current-format " #I:#W "

# pane border colors
set-window-option -g pane-active-border-style fg=$base0C
set-window-option -g pane-border-style fg=$base03

# message text
set-option -g message-style bg=$base00,fg=$base0C

# pane number display
set-option -g display-panes-active-colour $base0C
set-option -g display-panes-colour $base01

# clock
set-window-option -g clock-mode-colour $base0C

# session name = accent block on the left (like HolaMundo's "Work" tab)
tm_session_name="#[fg=$base01,bg=$base0D,bold] #S #[default]"
set -g status-left "$tm_session_name "

tm_date="#[fg=$base0C] %R "
# kube-tmux, with long EKS context ARNs trimmed down to "cluster:namespace"
tm_kube="#(/bin/bash $XDG_CONFIG_HOME/tmux/plugins/kube-tmux/kube.tmux 250 red cyan | sed -E 's|arn:aws:eks:[^:]+:[0-9]+:cluster/||')"
set -g status-right "$tm_kube #[fg=$base04]│$tm_date"
set -g status on

