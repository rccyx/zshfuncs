pspick() {
  emulate -L zsh
  ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem \
    | fzf --prompt="⚙ pick process ⇢ " --reverse --height 70% \
    | awk '{print $1}'
}

pstreef() { pstree -pa $(pspick) | less; }
pstop()   { local pid=$(pspick) || return; sudo kill -9 "$pid"; }
