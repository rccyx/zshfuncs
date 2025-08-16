clock() { tty-clock -c -C 5 -s }
sound-animate()  { cava }

animations() {
  local choice
  choice=$(printf '%s\n' clock sound-animate | fzf --prompt="animations > ")
  [[ -n "$choice" ]] && eval "$choice"
}

