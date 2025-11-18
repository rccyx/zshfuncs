themes() {
  if ! command -v fzf >/dev/null 2>&1; then
    return 1
  fi

  local choice
  choice=$(
    printf '%s\n' \
      brown \
      catppuccin \
      green \
      indigo \
      red \
      swirl-rose \
      white \
    | fzf --prompt='theme > ' --height=40%
  ) || return 1

  local root="$HOME"
  local starship_file dircolors_file tmux_file hypr_theme_file wallpaper_file
  local hypr_conf="$root/.config/hypr/hyprland.conf"

  case "$choice" in
    brown)
      starship_file="$root/starship/starship-brown.toml"
      dircolors_file="$root/dircolors/brown"
      tmux_file="$root/tmux/brown.conf"
      hypr_theme_file="brown.conf"
      wallpaper_file="$root/.wallpapers/brown.png"
      ;;
    catppuccin)
      starship_file="$root/starship/starship-catppuccin.toml"
      dircolors_file="$root/dircolors/catppuccin-mocha"
      tmux_file="$root/tmux/catppuccin-mocha.conf"
      hypr_theme_file="catppuccin.conf"
      wallpaper_file="$root/.wallpapers/catppuccin.jpg"
      ;;
    green)
      starship_file="$root/starship/starship-green.toml"
      dircolors_file="$root/dircolors/green"
      tmux_file="$root/tmux/green.conf"
      hypr_theme_file="green.conf"
      wallpaper_file="$root/.wallpapers/green.png"
      ;;
    indigo)
      starship_file="$root/starship/starship-indigo.toml"
      dircolors_file="$root/dircolors/indigo"
      tmux_file="$root/tmux/indigo.conf"
      hypr_theme_file="indigo.conf"
      wallpaper_file="$root/.wallpapers/indigo.png"
      ;;
    red)
      starship_file="$root/starship/starship-red.toml"
      dircolors_file="$root/dircolors/red"
      tmux_file="$root/tmux/red.conf"
      hypr_theme_file="red.conf"
      wallpaper_file="$root/.wallpapers/red.jpg"
      ;;
    swirl-rose)
      starship_file="$root/starship/starship-swirl-rose.toml"
      dircolors_file="$root/dircolors/swirl-rose"
      tmux_file="$root/tmux/swirl-rose.conf"
      hypr_theme_file="swirl-rose.conf"
      wallpaper_file="$root/.wallpapers/swirl-rose.jpg"
      ;;
    white)
      starship_file="$root/starship/starship-white.toml"
      dircolors_file="$root/dircolors/white"
      tmux_file="$root/tmux/white-band.conf"
      hypr_theme_file="white.conf"
      wallpaper_file="$root/.wallpapers/white.webp"
      ;;
    *)
      return 1
      ;;
  esac

  if [[ -f "$starship_file" ]]; then
    export STARSHIP_CONFIG="$starship_file"
    if grep -q '^export STARSHIP_CONFIG=' "$root/.zshrc" 2>/dev/null; then
      sed -i "s|^export STARSHIP_CONFIG=.*$|export STARSHIP_CONFIG=$starship_file|" "$root/.zshrc"
    else
      printf '\nexport STARSHIP_CONFIG=%s\n' "$starship_file" >> "$root/.zshrc"
    fi
  fi

  if [[ -f "$dircolors_file" ]]; then
    ln -sf "$dircolors_file" "$root/.dircolors"
    eval "$(dircolors "$root/.dircolors" 2>/dev/null || true)" >/dev/null 2>&1
  fi

  if [[ -f "$tmux_file" ]]; then
    mkdir -p "$root/tmux"
    ln -sf "$tmux_file" "$root/tmux/current.conf"
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
      tmux source-file "$root/.tmux.conf" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -f "$hypr_conf" && -n "$hypr_theme_file" ]]; then
    sed -i "s|^source = ./themes/.*|source = ./themes/$hypr_theme_file|" "$hypr_conf"
    if command -v hyprctl >/dev/null 2>&1; then
      hyprctl reload >/dev/null 2>&1 || true
    fi
  fi

  if command -v wallpaper >/dev/null 2>&1 && [[ -f "$wallpaper_file" ]]; then
    wallpaper set "$wallpaper_file" >/dev/null 2>&1 || true
  fi
}

