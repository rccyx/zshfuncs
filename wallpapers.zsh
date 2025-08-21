# ~/.zsh/wallpaper.zsh
# Waypaper UI + swww backend. Persistent.

_have(){ command -v "$1" >/dev/null 2>&1; }
_asroot(){ [ "$EUID" -eq 0 ] && "$@" || sudo "$@"; }
_log(){ printf "[wallpaper] %s\n" "$*"; }

WPDIR="${WALLPAPER_DIR:-$HOME/.wallpapers}"
INI="$HOME/.config/waypaper/config.ini"

_start_daemon(){
  pgrep -x swww-daemon >/dev/null || swww-daemon & disown
}

_write_ini(){
  mkdir -p "$(dirname "$INI")" "$WPDIR"
  cat >"$INI" <<EOF
[Settings]
folder = $WPDIR
backend = swww
fill = Fill
monitors = All
subfolders = False
all_subfolders = False
show_hidden = False
post_command =
swww_transition_type = any
swww_transition_step = 90
swww_transition_angle = 0
swww_transition_duration = 2
swww_transition_fps = 60
EOF
}

wallpaper(){
  case "${1:-}" in
    setup)
      _log "installing swww if missing"
      _asroot apt-get update -y
      _asroot apt-get install -y swww || { _log "apt install swww failed"; return 1; }
      if ! _have waypaper; then
        _log "installing Waypaper via pipx"
        _asroot apt-get install -y pipx python3-gi gir1.2-gtk-4.0 libadwaita-1-0 || true
        pipx install --quiet waypaper || true
      fi
      _write_ini
      _log "setup done. Add the two Hyprland lines from the instructions, then relogin."
      ;;
    ui|"")
      _start_daemon
      waypaper --backend swww --folder "$WPDIR" &
      ;;
    set)
      shift
      [ -f "${1:-}" ] || { _log "pass an image file"; return 1; }
      _start_daemon
      waypaper --backend swww --wallpaper "$1" || { _log "set failed"; return 1; }
      _log "set → $1"
      ;;
    random)
      _start_daemon
      waypaper --backend swww --folder "$WPDIR" --random || { _log "random failed"; return 1; }
      _log "random pick applied"
      ;;
    restore)
      _start_daemon
      waypaper --backend swww --restore || { _log "restore failed"; return 1; }
      _log "restored last pick"
      ;;
    status)
      _have swww && swww query || true
      _have waypaper && waypaper --list 2>/dev/null || true
      ;;
    destroy)
      _log "manual cleanup only. remove the Hyprland exec-once lines and uninstall if you want"
      ;;
    *)
      _log "usage: wallpaper [setup|ui|set <img>|random|restore|status|destroy]"
      return 1
      ;;
  esac
}

