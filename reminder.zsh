# reminder.zsh
# Remote Reminder via API
# Supports units: seconds, minutes, hours, days
# Usage:
#   reminder                          # fzf picker -> unit + value + message + title
#   reminder --unit minutes --value 5 --message "stretch"
#   reminder --unit hours --value 2 --message "check oven" -T "Urgent"

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
  local cli_unit="" cli_value="" cli_msg="" cli_title=""
  while (( $# )); do
    case "$1" in
      --unit|-u) shift; cli_unit="${1:-}"; shift || true ;;
      --value|-v) shift; cli_value="${1:-}"; shift || true ;;
      --message|-M) shift; cli_msg="${1:-}"; shift || true ;;
      --title|-T) shift; cli_title="${1:-}"; shift || true ;;
      --help|-h)
        cat <<'__H__'
reminder:
  reminder                 -> pick unit + value with fzf, then enter message & optional title
  reminder -u minutes -v 5 -M "grab food"
  reminder -u hours -v 2 -M "drink water"
  reminder -u days -v 1 -M "check inbox" -T "Urgent"

Rules:
  - Units supported: seconds (0-60), minutes (0-60), hours (0-24), days (0-7)
  - Title is optional (defaults to "Reminder Notification" if left blank)
__H__
        return 0
        ;;
      '')
        shift ;;
      *)
        if [[ -z "$cli_msg" ]]; then
          cli_msg="$1"; shift
        else
          cli_msg="${cli_msg:+$cli_msg }$1"; shift
        fi
        ;;
    esac
  done

  # --- Pick unit if not provided ---
  local unit value choice
  if [[ -z "${cli_unit:-}" ]]; then
    if command -v fzf >/dev/null; then
      choice=$(printf "seconds\nminutes\nhours\ndays\n" \
        | fzf --prompt="Unit: " --height=20% --reverse --ansi) || return 1
      unit="$choice"
    else
      print "Unit (seconds, minutes, hours, days): "
      read -r unit || return 1
    fi
  else
    unit="$cli_unit"
  fi

  # --- Validate unit ---
  case "$unit" in
    seconds|minutes|hours|days) ;;
    *) print "❌ Invalid unit: $unit"; return 1 ;;
  esac

  # --- Pick value based on unit ---
  if [[ -z "${cli_value:-}" ]]; then
    local max
    case "$unit" in
      seconds) max=60 ;;
      minutes) max=60 ;;
      hours) max=24 ;;
      days) max=7 ;;
    esac
    if command -v fzf >/dev/null; then
      local -a opts
      for (( i=0; i<=max; i++ )); do
        opts+=("$i")
      done
      value=$(printf "%s\n" "${opts[@]}" \
        | fzf --prompt="Value ($unit): " --height=40% --reverse --ansi) || return 1
    else
      print "Enter value for $unit (0..$max): "
      read -r value || return 1
    fi
  else
    value="$cli_value"
  fi

  # --- Range check ---
  case "$unit" in
    seconds) (( value >=0 && value <=60 )) || { print "Invalid seconds"; return 1; } ;;
    minutes) (( value >=0 && value <=60 )) || { print "Invalid minutes"; return 1; } ;;
    hours)   (( value >=0 && value <=24 )) || { print "Invalid hours"; return 1; } ;;
    days)    (( value >=0 && value <=7 ))  || { print "Invalid days"; return 1; } ;;
  esac

  # --- Message ---
  local msg
  if [[ -n "${cli_msg:-}" ]]; then
    msg="$cli_msg"
  else
    vared -p "Reminder message: " -c msg
    [[ -z "$msg" ]] && msg="Time to focus"
  fi

  # --- Title (optional prompt) ---
  local title
  if [[ -n "${cli_title:-}" ]]; then
    title="$cli_title"
  else
    vared -p "Reminder title (leave blank for default): " -c title
    [[ -z "$title" ]] && title="Reminder Notification"
  fi

  # --- Build JSON payload ---
  local payload
  payload=$(jq -nc \
    --arg unit "$unit" \
    --argjson value "$value" \
    --arg title "$title" \
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
  print "[reminder] $ts_now -> scheduled in $value $unit : $msg"
  print "[API Response] $resp"
}

