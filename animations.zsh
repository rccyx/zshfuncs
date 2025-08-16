clock() { tty-clock -c -C 5 -s }
cava()  { cava }

animations() {
  local choice
  choice=$(printf '%s\n' clock cava | fzf --prompt="animations > ")
  [[ -n "$choice" ]] && eval "$choice"
}

