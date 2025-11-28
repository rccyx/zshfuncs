lockscreen() {
  # Require fzf
  if ! command -v fzf >/dev/null 2>&1; then
    echo "lockscreen: fzf not found" >&2
    return 1
  fi

  # Find current SDDM theme name from /etc/sddm.conf or /etc/sddm.conf.d/*.conf
  local sddm_conf theme_name
  for sddm_conf in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
    [[ -r "$sddm_conf" ]] || continue
    theme_name=${$(grep -E '^\s*Current=' "$sddm_conf" | tail -n 1)#*=}
    theme_name=${theme_name// /}  # strip spaces
    [[ -n "$theme_name" ]] && break
  done

  # Fallback if nothing found (you can change this default if needed)
  [[ -z "$theme_name" ]] && theme_name="thyx"

  local theme_root="/usr/share/sddm/themes/$theme_name"
  local themes_dir="$theme_root/themes"
  local main_conf="$theme_root/theme.conf"

  if [[ ! -d "$theme_root" ]]; then
    echo "lockscreen: theme root not found: $theme_root" >&2
    return 1
  fi

  if [[ ! -d "$themes_dir" ]]; then
    echo "lockscreen: themes directory not found: $themes_dir" >&2
    return 1
  fi

  # Build list of available subthemes from actual files in themes/
  local -a theme_names
  theme_names=("${(@f)$(ls -1 "$themes_dir" 2>/dev/null | sed -n 's/^\(.*\)\.conf$/\1/p')}")

  if (( ${#theme_names} == 0 )); then
    echo "lockscreen: no *.conf subthemes found in $themes_dir" >&2
    return 1
  fi

  # FZF selection from real themes only
  local choice
  choice=$(
    printf '%s\n' "${theme_names[@]}" \
    | fzf --prompt="lockscreen ($theme_name) > " --height=40%
  ) || return 1

  local src="$themes_dir/$choice.conf"

  if [[ ! -f "$src" ]]; then
    echo "lockscreen: selected theme file not found: $src" >&2
    return 1
  fi

  # Copy chosen subtheme into main theme.conf (sudo if needed)
  if [[ -w "$main_conf" ]]; then
    cp "$src" "$main_conf"
  else
    sudo cp "$src" "$main_conf"
  fi

  echo "SDDM theme '$theme_name' set to subtheme: $choice"
  echo "  $src  ->  $main_conf"
}

