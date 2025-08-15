# kb: set keyboard layout fast across Wayland/X11/TTY and persist it
# Usage:
#   kb fr            # French AZERTY
#   kb us            # English US QWERTY
#   kb us-intl       # US International
#   kb fr-bepo       # French Bépo
#   kb gb            # UK
#   kb de            # German
#   kb es            # Spanish
kb() {
  local arg="${1:-}"
  if [[ -z "$arg" ]]; then
    echo "Usage: kb <fr|us|us-intl|fr-bepo|gb|de|es>"; return 1
  fi

  # Map friendly names to xkb layout and variant
  local layout="" variant=""
  case "$arg" in
    fr|french|azerty) layout="fr"; variant="";;
    fr-azerty)        layout="fr"; variant="";;
    fr-bepo|bepo)     layout="fr"; variant="bepo";;
    us|english|qwerty)layout="us"; variant="";;
    us-intl|intl)     layout="us"; variant="intl";;
    gb|uk)            layout="gb"; variant="";;
    de|german)        layout="de"; variant="";;
    es|spanish)       layout="es"; variant="";;
    *) echo "Unknown layout: $arg"; return 1;;
  esac

  # Detect environments
  local on_hypr="" on_wayland="" on_x11="" on_tty=""
  [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]] && command -v hyprctl >/dev/null && on_hypr=1
  [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && on_wayland=1
  [[ -n "${DISPLAY:-}" ]] && on_x11=1
  [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]] && on_tty=1

  # Apply live settings
  if [[ -n "$on_hypr" ]]; then
    hyprctl keyword input:kb_layout "$layout" >/dev/null
    hyprctl keyword input:kb_variant "$variant" >/dev/null
    echo "Hyprland live: layout=$layout variant=${variant:-none}"
  fi
  if [[ -n "$on_x11" || -n "$on_wayland" ]]; then
    setxkbmap -layout "$layout" ${variant:+-variant "$variant"} 2>/dev/null
    echo "XKB live: layout=$layout variant=${variant:-none}"
  fi
  if [[ -n "$on_tty" ]]; then
    # Console keymap uses different names sometimes. Try direct, then fall back.
    if loadkeys "$layout" 2>/dev/null; then
      echo "TTY live: keymap=$layout"
    else
      # common fallbacks
      case "$arg" in
        fr|fr-azerty|french|azerty) loadkeys fr 2>/dev/null && echo "TTY live: keymap=fr";;
        us|english|qwerty|us-intl|intl) loadkeys us 2>/dev/null && echo "TTY live: keymap=us";;
      esac
    fi
  fi

  # Persist with systemd if available
  if command -v localectl >/dev/null; then
    # Persist for X11
    sudo localectl set-x11-keymap "$layout" "" "" "${variant:-}" >/dev/null 2>&1 \
      && echo "Persisted X11: $layout ${variant:+($variant)}"
    # Persist for console
    # Use closest console keymap
    local console_map="$layout"
    [[ "$arg" == "us-intl" || "$arg" == "intl" ]] && console_map="us"
    sudo localectl set-keymap "$console_map" >/dev/null 2>&1 \
      && echo "Persisted console: $console_map"
  else
    echo "Tip: install systemd localectl to persist across reboots."
  fi

  # Hyprland config hint so it survives restarts without relying on runtime keyword
  if [[ -n "$on_hypr" ]]; then
    echo "Note: add to your Hyprland config for permanence:"
    echo "  input { kb_layout = $layout; kb_variant = ${variant:-} }"
  fi
}

