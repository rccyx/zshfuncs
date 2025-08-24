# reminder with picker + CLI
# Usage:
#   notify                       # fzf picker -> prompt for message
#   notify --minutes 8 --message 'grab eggs'
#   notify -m 45 -M "check oven"
#   notify 3 "do some"           # positional
notify() {
  emulate -L zsh
  setopt localoptions errexit nounset pipefail

  # deps
  if ! command -v notify-send >/dev/null; then
    print -P "%F{red}❌ notify-send not found. Install libnotify-bin.%f"
    return 1
  fi
  local have_fzf=0
  command -v fzf >/dev/null && have_fzf=1

  # args
  local cli_minutes="" cli_msg="" arg
  while (( $# )); do
    case "$1" in
      --minutes|-m) shift; cli_minutes="${1:-}"; shift || true ;;
      --message|-M) shift; cli_msg="${1:-}"; shift || true ;;
      --help|-h)
        cat <<'__H__'
notify:
  notify                 → pick delay with fzf, then enter message
  notify -m 3 -M "grab food"
  notify 45 "drink water"

Rules:
  • Exact minutes are supported for 0..30
  • Minutes > 30 are rounded up to the nearest 15
__H__
        return 0
        ;;
      '' ) shift ;;
      *)
        if [[ -z "$cli_minutes" && "$1" == <-> ]]; then
          cli_minutes="$1"; shift
          [[ $# -gt 0 ]] && cli_msg="$*"
          break
        else
          cli_msg="${cli_msg:+$cli_msg }$1"; shift
        fi
        ;;
    esac
  done

  # picker if minutes not provided
  local mins choice
  if [[ -z "${cli_minutes:-}" ]]; then
    if (( have_fzf )); then
      # build options: 0..30 each minute, then 45..720 step 15
      local -a opts
      local i h m label
      for (( i=0; i<=30; i++ )); do
        if (( i == 0 )); then
          label="now"
        else
          label="${i} min"
        fi
        opts+=("${i}|${label}")
      done
      for (( i=45; i<=720; i+=15 )); do
        h=$(( i/60 )); m=$(( i%60 ))
        if (( h == 0 )); then
          label="${i} min"
        else
          label="${h} h"; (( m )) && label="${label} ${m} min"
        fi
        opts+=("${i}|${label}")
      done
      choice=$(printf "%s\n" "${opts[@]}" | sed 's/|/ → /' \
        | fzf --prompt="⏰ Remind me in: " --height=40% --reverse --ansi) || return 1
      mins=$(printf "%s" "$choice" | awk '{print $1}')
    else
      print -P "%F{yellow}fzf not found. Enter minutes (0..720).%f"
      read -r "mins?Minutes: " || return 1
    fi
  else
    mins="${cli_minutes}"
  fi

  # sanitize minutes: allow exact 0..30, else round up to nearest 15
  if ! [[ "$mins" == <-> ]]; then
    print -P "%F{red}❌ Invalid minutes: $mins%f"; return 1
  fi
  (( mins < 0 )) && mins=0
  (( mins > 720 )) && mins=720
  if (( mins > 30 )); then
    mins=$(( ((mins + 14) / 15) * 15 ))
  fi

  # message
  local msg title body
  title="⏰ Reminder"
  if [[ -n "${cli_msg:-}" ]]; then
    msg="$cli_msg"
  else
    vared -p "📝 Reminder message: " -c msg
    [[ -z "$msg" ]] && msg="Time to eat"
  fi
  if (( mins == 0 )); then
    body="Now: ${msg}"
  else
    body="After ${mins} minutes: ${msg}"
  fi

  # log
  local now; now=$(date "+%H:%M:%S")
  if (( mins == 0 )); then
    print -P "%F{33}[notify]%f %F{35}$now%f → %F{32}scheduled now%f : %F{36}$msg%f"
  else
    print -P "%F{33}[notify]%f %F{35}$now%f → %F{32}scheduled in $mins min%f : %F{36}$msg%f"
  fi

  # schedule
  if (( mins == 0 )); then
    /usr/bin/notify-send "$title" "$body" >/dev/null 2>&1
  else
    if command -v systemd-run >/dev/null; then
      systemd-run --user --quiet \
        --unit="notify-$(date +%s)-$RANDOM" \
        --timer-property=AccuracySec=1s \
        --on-active="${mins}m" \
        /usr/bin/notify-send "$title" "$body" >/dev/null 2>&1
    else
      nohup bash -lc "sleep $((mins*60)); exec notify-send \"$title\" \"$body\"" >/dev/null 2>&1 & disown
    fi
  fi

  print -P "%F{green}✓ Reminder set.%f"
}

