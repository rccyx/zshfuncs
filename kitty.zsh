
kittytheme() {
  local theme="$1"
  kitty @ set-colors -a "$HOME/.config/kitty/themes/${theme}.conf"
}
