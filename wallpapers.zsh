# ===============================
#  Universal wallpaper helpers
#  deps: feh or imv or sxiv optional, gsettings/qdbus/xfconf when present
# ===============================

_have(){ command -v "$1" >/dev/null 2>&1; }

# Detect desktop and session type
_de_id(){
  local de="$(printf "%s%s" "$XDG_CURRENT_DESKTOP" "$DESKTOP_SESSION" | tr '[:upper:]' '[:lower:]')"
  local st="${XDG_SESSION_TYPE:-}"
  printf "%s|%s" "$de" "$st"
}

# Persist wallpaper in the current environment
_persist_wall(){
  local file="$1"
  local de st; IFS='|' read -r de st <<< "$(_de_id)"

  case "$de" in
    *gnome*|*budgie*|*cinnamon*|*pantheon*)
      # GNOME family via gsettings
      if _have gsettings; then
        local uri="file://$file"
        gsettings set org.gnome.desktop.background picture-uri "$uri" >/dev/null 2>&1
        gsettings set org.gnome.desktop.background picture-uri-dark "$uri" >/dev/null 2>&1
        gsettings set org.gnome.desktop.background picture-options 'zoom' >/dev/null 2>&1
        return 0
      fi
      ;;
    *kde*|*plasma*)
      # KDE Plasma
      if _have plasma-apply-wallpaperimage; then
        plasma-apply-wallpaperimage "$file" >/dev/null 2>&1 && return 0
      elif _have qdbus || _have qdbus-qt5; then
        ${$(command -v qdbus):-qdbus-qt5} org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
          "var d=desktops(); for (i=0;i<d.length;i++){ d[i].wallpaperPlugin='org.kde.image'; d[i].currentConfigGroup=['Wallpaper','org.kde.image','General']; d[i].writeConfig('Image','file://$file') }" >/dev/null 2>&1 && return 0
      fi
      ;;
    *xfce*)
      # XFCE
      if _have xfconf-query; then
        xfconf-query -c xfce4-desktop -l | grep -E 'last-image$' | \
          xargs -I{} xfconf-query -c xfce4-desktop -p {} -s "$file" >/dev/null 2>&1 && return 0
      fi
      ;;
    *mate*)
      # MATE
      if _have gsettings; then
        gsettings set org.mate.background picture-filename "$file" >/dev/null 2>&1
        gsettings set org.mate.background picture-options zoom >/dev/null 2>&1
        return 0
      fi
      ;;
    *lxqt*|*lxde*)
      # LXQt or LXDE
      if _have pcmanfm-qt; then
        pcmanfm-qt --set-wallpaper "$file" --wallpaper-mode=fit >/dev/null 2>&1 && return 0
      elif _have pcmanfm; then
        pcmanfm --set-wallpaper "$file" >/dev/null 2>&1 && return 0
      fi
      ;;
    *sway*)
      # Sway Wayland
      if _have swww; then
        swww img "$file" --transition-type any >/dev/null 2>&1 && return 0
      elif _have swaymsg; then
        pkill -x swaybg >/dev/null 2>&1 || true
        nohup swaybg -i "$file" -m fill >/dev/null 2>&1 &
        return 0
      fi
      ;;
    *hypr*|*hyprland*)
      # Hyprland
      if _have hyprctl; then
        hyprctl hyprpaper preload "$file" >/dev/null 2>&1
        hyprctl hyprpaper wallpaper ",$file" >/dev/null 2>&1 && return 0
      fi
      if _have swww; then
        swww img "$file" >/dev/null 2>&1 && return 0
      fi
      ;;
  esac

  # Fallbacks
  if [[ -n "$DISPLAY" && -z "$WAYLAND_DISPLAY" ]] && _have feh; then
    feh --bg-fill "$file" >/dev/null 2>&1
    # user can autostart ~/.fehbg on X11 WMs to persist across restarts
    return 0
  fi

  return 1
}

# Public API

# Set an exact image. Works everywhere. Persists when possible.
wpset(){
  local f="$1"
  [[ -f "$f" ]] || { echo "pass an image file"; return 1; }
  if ! _persist_wall "$f"; then
    echo "set temporary background. install feh on X11 or swww/swaybg on Wayland for persistence"
  fi
  echo "wallpaper set → $f"
}

# Random from a folder
wprand(){
  local dir="${1:-$HOME/Pictures/Wallpapers}"
  [[ -d "$dir" ]] || { echo "dir not found: $dir"; return 1; }
  local img
  img="$(find "$dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.heic' \) | shuf -n1)"
  [[ -z "$img" ]] && { echo "no images in $dir"; return 1; }
  wpset "$img"
}

# Cycle on an interval. Stop with wpstop.
wpcycle(){
  local dir="${1:-$HOME/Pictures/Wallpapers}" sec="${2:-600}"
  [[ -d "$dir" ]] || { echo "dir not found: $dir"; return 1; }
  mkdir -p "$HOME/.cache"
  local pidfile="$HOME/.cache/wpcycle.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "already cycling (pid $(cat "$pidfile"))"; return 0
  fi
  {
    while :; do
      wprand "$dir"
      sleep "$sec" || exit 0
    done
  } >/dev/null 2>&1 &
  echo $! > "$pidfile"
  echo "cycle every ${sec}s (pid $(cat "$pidfile"))"
}

# Stop the cycle
wpstop(){
  local p="$HOME/.cache/wpcycle.pid"
  if [[ -f "$p" ]] && kill -0 "$(cat "$p")" 2>/dev/null; then
    kill "$(cat "$p")" && rm -f "$p" && echo "cycle stopped"
  else
    echo "no cycle running"
  fi
}

# Grid picker thumbnails if available, else clean fallbacks
# 1) sxiv -to prints marked file paths. Mark with m, quit with q.
# 2) feh thumbnails with --action calling wpset.
# 3) last resort browse one by one with imv.
wppick(){
  local dir="${1:-$HOME/Pictures/Wallpapers}"
  [[ -d "$dir" ]] || { echo "dir not found: $dir"; return 1; }

  if _have sxiv; then
    local pick; pick="$(sxiv -to "$dir" 2>/dev/null | head -n1)"
    [[ -z "$pick" ]] && { echo "no selection. mark with m then q"; return 1; }
    wpset "$pick"; return
  fi

  if _have feh; then
    feh --scale-down --auto-zoom --thumbnails --index-info '%n/%m' \
        --action "zsh -c 'wpset %F'" "$dir"
    return
  fi

  if _have imv; then
    imv -f "$dir"
    return
  fi

  echo "install sxiv or feh or imv for visual picking"
}

# One by one viewer no grid
wpbrowse(){
  local dir="${1:-$HOME/Pictures/Wallpapers}"
  [[ -d "$dir" ]] || { echo "dir not found: $dir"; return 1; }
  if _have imv; then
    imv -f "$dir"
  elif _have feh; then
    feh --auto-zoom "$dir"
  else
    echo "install imv or feh"
  fi
}
