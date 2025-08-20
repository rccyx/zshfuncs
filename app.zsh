# Open sites as native Chrome app windows using "Default" profile.
# Usage:
#   app                    # fzf picker
#   app x                  # alias key
#   app https://x.com      # direct URL
app() {
  emulate -L zsh
  setopt localoptions err_return no_unset

  local browser profile target sel key
  browser=$(command -v google-chrome || command -v chromium || true)
  if [[ -z ${browser-} ]]; then
    print -P "%F{red}google-chrome or chromium not found%f"
    return 1
  fi

  profile=${WEBAPP_PROFILE:-Default}
  typeset -gA WEBAPPS
  WEBAPPS=(
    gcal       https://calendar.google.com
    calendar   https://calendar.google.com
    chatgpt    https://chatgpt.com
    gpt        https://chatgpt.com
    x          https://x.com
    twitter    https://x.com
    icloud     https://www.icloud.com
    soundcloud https://soundcloud.com
    sc         https://soundcloud.com
    facebook   https://facebook.com
    fb         https://facebook.com
    instagram  https://instagram.com
    ig         https://instagram.com
    grok       https://x.com/i/grok
  )

  if [[ -n ${1-} ]]; then
    target=$1
    [[ -n ${WEBAPPS[$target]-} ]] && target=${WEBAPPS[$target]}
  else
    if command -v fzf >/dev/null 2>&1 && [[ -t 0 || -t 1 ]]; then
      local -a keys; keys=(${(ok)WEBAPPS})
      sel=$(
        for k in "${keys[@]}"; do
          printf "%-12s %s\n" "$k" "${WEBAPPS[$k]}"
        done | fzf --prompt="app> " --height=40% --border --reverse
      )
      [[ -z ${sel-} ]] && return 1
      key=${sel%%[[:space:]]*}
      target=${WEBAPPS[$key]}
    else
      print -P "%F{yellow}No TTY for fzf. Run from a terminal, or bind your key to launch a terminal (e.g. kitty -e zsh -ic app).%f"
      return 1
    fi
  fi

  if [[ ${target} != http*://* ]]; then
    print -P "%F{red}Invalid or unknown app:%f ${target}"
    return 1
  fi

  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$browser" --profile-directory="$profile" --app="$target" --new-window >/dev/null 2>&1
  else
    nohup "$browser" --profile-directory="$profile" --app="$target" --new-window >/dev/null 2>&1 &
  fi
}

