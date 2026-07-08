set -g status-interval 5
set -g status-left-length 30
set -g status-right-length 150
set -g window-status-separator ""

set -g status-style "bg=default,fg=default"
set -g status-left "#[fg=black,bg=blue,bold] #S #[bg=default] "

# Reset styles an older theme may have left set on a live tmux server
setw -g window-status-style default
setw -g window-status-current-style default

# Bell flag: pink bold window name. Styled IN the format because the format's
# hardcoded fg=brightblack always beats window-status-bell-style (a bg there
# rendered as unreadable gray-on-pink).
set -g window-status-format "#{?window_bell_flag,#[fg=colour211]#[bold],#[fg=brightblack]} #I:#W "
set -g window-status-current-format "#[fg=blue,bold] #I:#W "

set -g pane-border-style "fg=brightblack"
set -g pane-active-border-style "fg=blue"
set -g message-style "bg=default,fg=blue"
set -g message-command-style "bg=default,fg=blue"
set -g mode-style "bg=blue,fg=black"
setw -g clock-mode-colour blue
set -g display-panes-active-colour blue
set -g display-panes-colour brightblack

# Kube context in pink (red was unreadable) + clock. The seds shorten
# provider-prefixed contexts to the bare cluster name: EKS ARNs (any partition)
# and GKE's gke_<project>_<location>_<cluster>; AKS & friends are already plain names.
tm_kube="#(KUBE_TMUX_SYMBOL_ENABLE=false /bin/bash $XDG_CONFIG_HOME/tmux/plugins/kube-tmux/kube.tmux 250 colour211 cyan | sed -E -e 's|arn:aws[^:]*:eks:[^:]+:[0-9]+:cluster/||' -e 's|\]gke_[^_]+_[^_]+_|]|')"
set -g status-right "$tm_kube #[fg=brightblack]│#[fg=cyan] %R "
