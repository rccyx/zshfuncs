# reminder.zsh
# Remote Reminder via API
# Usage:
#   reminder                          # fzf picker -> prompt for message
#   reminder --minutes 5 --message "stretch"
#   reminder 10 "check oven"          # positional
#   reminder -m 3 -M "grab food" -T "Urgent"

reminder() {
  emulate -L zsh
  setopt localoptions errexit nounset pipefail

  # --- Check API token ---
  if [[ -z "${X_API_TOKEN:-}" ]]; then
    print "❌ X_API_TOKEN not set in environment. Export it first."
    return 1
  fi

  local ENDPOINT="https://ashgw.me/api/v1/reminder"

  # --- Parse CLI args ---
  local cli_minutes="" cli_msg="" cli_title="Reminder Notification"
  while (( $# )); do
    case "$1" in
      --minutes|-m) shift; cli_minutes="${1:-}"; shift || true ;;
      --message|-M) shift; cli_msg="${1:-}"; shift || true ;;
      --title|-T) shift; cli_title="${1:-Reminder Notification}"; shift || true ;;
      --help|-h)
        cat <<'__H__'
reminder:
  reminder                 -> pick delay with fzf, then enter message
  reminder -m 3 -M "grab food"
  reminder 45 "drink water"
  reminder -m 10 -M "urgent check" -T "Urgent"

Rules:
  - Exact minutes supported for 0..30
  - > 30 minutes rounds up to nearest 15
  - Title is optional (defaults to "Reminder Notification")
__H__
        return 0
        ;;
      '')
        shift ;;
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

  # --- Picker if minutes not provided ---
  local mins choice
  if [[ -z "${cli_minutes:-}" ]]; then
    if command -v fzf >/dev/null; then
      local -a opts
      local i h m label
      for (( i=0; i<=30; i++ )); do
        label=$(( i==0 ? 0 : i ))" min"
        (( i==0 )) && label="now"
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
      choice=$(printf "%s\n" "${opts[@]}" | sed 's/|/ -> /' \
        | fzf --prompt="Remind in: " --height=40% --reverse --ansi) || return 1
      mins=$(printf "%s" "$choice" | awk '{print $1}')
    else
      print "fzf not found. Enter minutes (0..720)."
      read -r "mins?Minutes: " || return 1
    fi
  else
    mins="${cli_minutes}"
  fi

  # --- Sanitize minutes ---
  if ! [[ "$mins" == <-> ]]; then
    print "Invalid minutes: $mins"; return 1
  fi
  (( mins < 0 )) && mins=0
  (( mins > 720 )) && mins=720
  if (( mins > 30 )); then
    mins=$(( ((mins + 14) / 15) * 15 ))
  fi

  # --- Message ---
  local msg
  if [[ -n "${cli_msg:-}" ]]; then
    msg="$cli_msg"
  else
    vared -p "Reminder message: " -c msg
    [[ -z "$msg" ]] && msg="Time to focus"
  fi

  # --- Build JSON payload ---
  local payload
  payload=$(jq -nc \
    --arg unit "minutes" \
    --argjson value "$mins" \
    --arg title "$cli_title" \
    --arg message "$msg" \
    '{
      schedule: {
        kind: "delay",
        delay: { unit: $unit, value: $value },
        notification: {
          type: "REMINDER",
          title: $title,
          message: $message
        }
      }
    }'
  )

  # --- Send request ---
  local resp
  resp=$(curl -sS -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "X-API-TOKEN: $X_API_TOKEN" \
    -d "$payload")

  # --- Log result ---
  local ts_now
  ts_now="$(date '+%H:%M:%S')"
  print "[reminder] $ts_now -> scheduled in $mins min : $msg"
  print "[API Response] $resp"
}

