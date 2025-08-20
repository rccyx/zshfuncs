# Open sites as native app windows using your Chrome "Default" profile.
# Usage:
#   webapp                    # fuzzy dropdown of predefined apps
#   webapp x                  # open by key (alias), e.g. x/gpt/ig/fb/...
#   webapp https://x.com      # open a custom URL
webapp() {
  emulate -L zsh
  setopt localoptions err_return no_unset

  local browser profile target sel
  browser=$(command -v google-chrome || command -v chromium || command -v chrome || true)
  if [[ -z $browser ]]; then
    print -P "%F{red}google-chrome or chromium not found%f"
    return 1
  fi

  profile=${WEBAPP_PROFILE:-Default}
  target=${1-}

  typeset -A APPS
  APPS=(
    gcal       "https://calendar.google.com"
    calendar   "https://calendar.google.com"
    chatgpt    "https://chatgpt.com"
    gpt        "https://chatgpt.com"
    x          "https://x.com"
    twitter    "https://x.com"
    icloud     "https://www.icloud.com"
    soundcloud "https://soundcloud.com"
    sc         "https://soundcloud.com"
    facebook   "https://facebook.com"
    fb         "https://facebook.com"
    instagram  "https://instagram.com"
    ig         "https://instagram.com"
    grok       "https://x.com/i/grok"
  )

  if [[ -z $target ]]; then
    local -a keys; keys=(${(ok)APPS})
    if command -v wofi >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY-} ]]; then
      sel=$(printf "%s\n" "${keys[@]}" | wofi --show dmenu -i -p "webapp")
    elif command -v fzf >/dev/null 2>&1; then
      sel=$(printf "%s\n" "${keys[@]}" | fzf --prompt="webapp> " --height=40% --border)
    else
      print "Select app:"; select sel in "${keys[@]}"; do [[ -n $sel ]] && break; done
    fi
    [[ -z $sel ]] && return 1
    target=${APPS[$sel]}
  else
    # allow alias keys or direct URLs
    if [[ -n ${APPS[$target]-} ]]; then
      target=${APPS[$target]}
    fi
  fi

  if [[ $target != http*://* ]]; then
    print -P "%F{red}Invalid or unknown app:%f $target"
    return 1
  fi

  nohup "$browser" --profile-directory="$profile" --app="$target" --new-window >/dev/null 2>&1 &
}

