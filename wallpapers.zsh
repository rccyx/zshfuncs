# Waypaper UI + swww backend. Also handles SDDM login wallpaper for the "debion" theme.

_have(){ command -v "$1" >/dev/null 2>&1; }
_asroot(){ [ "$EUID" -eq 0 ] && "$@" || sudo "$@"; }
_log(){ printf "[wallpaper] %s\n" "$*"; }

WPDIR="${WALLPAPER_DIR:-$HOME/.wallpapers}"
INI="$HOME/.config/waypaper/config.ini"

# SDDM theme paths
THEME_DIR="${DEBION_THEME_DIR:-/usr/share/sddm/themes/debion}"
THEME_CONF="$THEME_DIR/theme.conf"

# Scan depth for fzf listing
WALLPAPER_MAXDEPTH="${WALLPAPER_MAXDEPTH:-3}"

# Preview widths: outside tmux low res, inside tmux high res
WALLPAPER_PREVIEW_W_OUT="${WALLPAPER_PREVIEW_W_OUT:-960}"
WALLPAPER_PREVIEW_W_IN="${WALLPAPER_PREVIEW_W_IN:-1920}"

_debion_assets_dir(){
  if [ -d "$THEME_DIR/assets" ]; then
    printf "%s\n" "$THEME_DIR/assets"
  else
    printf "%s\n" "$THEME_DIR"
  fi
}

_start_daemon(){
  pgrep -x swww-daemon >/dev/null && return 0
  if _have nohup; then
    nohup swww-daemon >/dev/null 2>&1 &
  else
    setsid -f swww-daemon >/dev/null 2>&1 || { swww-daemon >/dev/null 2>&1 & }
  fi
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

# Fast, NUL safe lister
_wallpaper_list(){
  if command -v fd >/dev/null; then
    fd . "$WPDIR" -HI -tf -d "$WALLPAPER_MAXDEPTH" -0 \
      -e png -e jpg -e jpeg -e webp -e gif -e mp4 -e mov -e mkv -e webm
  else
    find "$WPDIR" -maxdepth "$WALLPAPER_MAXDEPTH" -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.webm' \) -print0
  fi
}

# Preview script with caching and tmux passthrough support.
# Outside tmux: downscaled thumbs for speed. Inside tmux: higher quality.
_ensure_preview_script(){
  local f="${XDG_CACHE_HOME:-$HOME/.cache}/fzf-img-preview.sh"
  [ -x "$f" ] && { printf "%s" "$f"; return; }
  mkdir -p "$(dirname "$f")"
  cat >"$f" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
path="${1:-}"
[ -n "$path" ] || exit 0

cols="${FZF_PREVIEW_COLUMNS:-120}"
lines="${FZF_PREVIEW_LINES:-40}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wpthumbs"
mkdir -p "$cache_dir"

kitty_ok=false
if command -v kitty >/dev/null && [ -n "${KITTY_WINDOW_ID:-}" ]; then
  if [ -z "${TMUX:-}" ]; then
    kitty_ok=true
  elif tmux show -gv allow-passthrough 2>/dev/null | grep -qi yes; then
    kitty_ok=true
  fi
fi

low_mode=false
[ -z "${TMUX:-}" ] && low_mode=true

w_out="${WALLPAPER_PREVIEW_W_OUT:-960}"
w_in="${WALLPAPER_PREVIEW_W_IN:-1920}"
target_w="$w_in"
$low_mode && target_w="$w_out"

lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
img="$path"

get_key(){
  local p="$1" mtime size
  if command -v stat >/dev/null; then
    mtime="$(stat -c %Y "$p" 2>/dev/null || stat -f %m "$p" 2>/dev/null || echo 0)"
    size="$(stat -c %s "$p" 2>/dev/null || stat -f %z "$p" 2>/dev/null || echo 0)"
  else
    mtime=0; size=0
  fi
  printf '%s' "$p|$mtime|$size|w=$target_w" | sha1sum | awk '{print $1}'
}

make_thumb(){
  local src="$1" key out
  key="$(get_key "$src")"
  out="$cache_dir/$key.jpg"
  if [ ! -s "$out" ] && command -v ffmpeg >/dev/null; then
    nice -n 15 timeout 2 ffmpeg -loglevel error -y -i "$src" \
      -frames:v 1 -vf "scale='min('"$target_w"',iw)':'-2'" "$out" 2>/dev/null || true
  fi
  [ -s "$out" ] && printf '%s' "$out" || printf '%s' "$src"
}

case "$lower" in
  *.mp4|*.mov|*.mkv|*.webm)
    img="$(make_thumb "$path")"
    ;;
  *.png|*.jpg|*.jpeg|*.webp|*.gif)
    if [ "$low_mode" = true ]; then
      img="$(make_thumb "$path")"
    fi
    ;;
esac

show_tui(){
  if command -v chafa >/dev/null; then
    chafa -s "${cols}x${lines}" "$1" 2>/dev/null || true
  elif command -v viu >/dev/null; then
    viu -w "$cols" -h "$lines" "$1" 2>/dev/null || true
  else
    file --brief --mime-type "$1"; echo "$1"
  fi
}

if $kitty_ok; then
  kitty +kitten icat --silent --clear 2>/dev/null || true
  kitty +kitten icat --silent --transfer-mode=file \
    --place "${cols}x${lines}@0x0" "$img" 2>/dev/null || show_tui "$img"
  echo
else
  show_tui "$img"
fi
SH
  chmod +x "$f"
  printf "%s" "$f"
}

_pick_from_wpdir(){
  local sel preview_sh
  preview_sh="$(_ensure_preview_script)"

  if [ -n "${1:-}" ]; then
    sel="$1"
  elif _have fzf; then
    sel="$(
      _wallpaper_list |
      fzf --read0 --print0 --height=85% \
          --no-sort --tiebreak=index \
          --prompt='pick login wallpaper > ' \
          --preview "$preview_sh {}" \
          --preview-window=right,60%,border-rounded,follow \
          --bind 'ctrl-p:toggle-preview,ctrl-l:clear-screen' |
      tr -d '\0'
    )"
  else
    printf "Enter path to file in %s: " "$WPDIR" 1>&2
    read -r sel
  fi
  [ -n "$sel" ] && [ -f "$sel" ] || return 1
  printf "%s\n" "$sel"
}

_set_login_wallpaper(){
  local src="$1"
  [ -f "$src" ] || { _log "source file not found"; return 1; }

  local dest_dir ext base dest_name dest_path rel_path
  [ -d "$THEME_DIR" ] || { _log "theme dir not found: $THEME_DIR"; return 1; }
  dest_dir="$(_debion_assets_dir)"
  ext="${src##*.}"; ext="$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')"
  base="background"
  dest_name="$base.$ext"
  dest_path="$dest_dir/$dest_name"

  [ -d "$dest_dir" ] || _asroot mkdir -p "$dest_dir"

  _asroot sh -c "rm -f \"$dest_dir/$base\".* 2>/dev/null || true"
  _asroot install -m 0644 "$src" "$dest_path" || { _log "copy failed"; return 1; }
  _asroot test -s "$dest_path" || { _log "copied file is empty"; return 1; }

  if [ "$dest_dir" = "$THEME_DIR" ]; then
    rel_path="$dest_name"
  else
    rel_path="$(basename "$dest_dir")/$dest_name"
  fi

  if [ ! -f "$THEME_CONF" ]; then
    _asroot install -m 0644 /dev/null "$THEME_CONF"
  fi

  if _asroot grep -qiE '^[[:space:]]*Background[[:space:]]*=' "$THEME_CONF" 2>/dev/null; then
    _asroot sed -i -E "s|^[[:space:]]*Background[[:space:]]*=.*|Background=\"$rel_path\"|I" "$THEME_CONF"
  else
    _asroot sh -c "printf '\nBackground=\"%s\"\n' \"$rel_path\" >> \"$THEME_CONF\""
  fi

  _log "login wallpaper set -> $rel_path"
  _log "theme.conf updated -> $THEME_CONF"
}

_menu(){
  local choice
  if _have fzf; then
    choice="$(printf "%s\n%s\n" "Desktop wallpaper" "Login wallpaper" | fzf --prompt='wallpaper > ' --height=20%)"
  else
    printf "1) Desktop wallpaper\n2) Login wallpaper\nPick: " 1>&2
    read -r choice
    case "$choice" in
      1) choice="Desktop wallpaper" ;;
      2) choice="Login wallpaper" ;;
      *) choice="" ;;
    esac
  fi

  case "$choice" in
    "Desktop wallpaper") wallpaper ui ;;
    "Login wallpaper")
      local pick
      pick="$(_pick_from_wpdir)" || { _log "no selection"; return 1; }
      _set_login_wallpaper "$pick"
      ;;
    *) _log "cancelled" ;;
  esac
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
    ""|menu)
      _menu
      ;;
    login)
      case "${2:-pick}" in
        pick)
          local pick
          pick="$(_pick_from_wpdir)" || { _log "no selection"; return 1; }
          _set_login_wallpaper "$pick"
          ;;
        set)
          shift 2
          [ -f "${1:-}" ] || { _log "pass an image or video file"; return 1; }
          _set_login_wallpaper "$1"
          ;;
        random)
          local rnd
          if shuf --help 2>&1 | grep -q '\-z'; then
            rnd="$(_wallpaper_list | shuf -z -n1 | tr -d '\0')"
          else
            rnd="$(_wallpaper_list | tr '\0' '\n' | shuf -n1)"
          fi
          [ -n "$rnd" ] || { _log "no files in $WPDIR"; return 1; }
          _set_login_wallpaper "$rnd"
          ;;
        status)
          _log "theme dir: $THEME_DIR"
          _log "assets dir: $(_debion_assets_dir)"
          _log "theme.conf:"
          _have bat && _asroot bat --style=plain --paging=never "$THEME_CONF" 2>/dev/null || _asroot sed -n '1,200p' "$THEME_CONF" 2>/dev/null || true
          ;;
        *)
          _log "usage: wallpaper login [pick|set <file>|random|status]"
          return 1
          ;;
      esac
      ;;
    ui)
      _start_daemon
      waypaper --backend swww --folder "$WPDIR" &
      ;;
    set)
      shift
      [ -f "${1:-}" ] || { _log "pass an image file"; return 1; }
      _start_daemon
      waypaper --backend swww --wallpaper "$1" || { _log "set failed"; return 1; }
      _log "set -> $1"
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
      _log "usage: wallpaper [setup|menu|login|ui|set <img>|random|restore|status|destroy]"
      return 1
      ;;
  esac
}

