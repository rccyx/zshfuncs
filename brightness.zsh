# detect tools
_b_have(){ command -v "$1" >/dev/null 2>&1; }

# pick a sysfs backlight path if present
_b_sysfs_path(){ ls -d /sys/class/backlight/* 2>/dev/null | head -n1; }

# choose backend in this order: brightnessctl, light, xbacklight, ddcutil, sysfs
_b_cmd(){
  if   _b_have brightnessctl; then echo brightnessctl
  elif _b_have light;         then echo light
  elif _b_have xbacklight;    then echo xbacklight
  elif _b_have ddcutil;       then echo ddcutil
  elif [[ -n "$(_b_sysfs_path)" ]]; then echo sysfs
  else return 1
  fi
}

_b_bar(){ local p=${1:-0} w=${2:-20} f=$(( (p*w + 50)/100 )); local o=""; for ((i=1;i<=w;i++)); do ((i<=f)) && o+="█" || o+="░"; done; printf "%s\n" "$o"; }

# read percent for any backend
_b_read_pct(){
  local b=$(_b_cmd) || return 1
  case $b in
    brightnessctl) brightnessctl -m | grep -oE '[0-9]+%' | head -n1 | tr -d '%' ;;
    light)         light -G | awk '{printf "%.0f",$1}' ;;
    xbacklight)    xbacklight -get | awk '{printf "%.0f",$1}' ;;
    ddcutil)       ddcutil getvcp 10 2>/dev/null | awk -F'[=, ]+' '/current value/ {printf "%.0f", ($5*100)/$9}' ;;
    sysfs)         local p=$(_b_sysfs_path); [[ -n $p ]] || return 1
                   local c=$(<"$p/brightness") m=$(<"$p/max_brightness")
                   awk -v c="$c" -v m="$m" 'BEGIN{printf "%.0f", (c*100)/m}' ;;
  esac
}

# set percent for any backend (clamped 1..100)
_b_set_pct(){
  local target=$1; (( target<1 )) && target=1; (( target>100 )) && target=100
  local b=$(_b_cmd) || return 1
  case $b in
    brightnessctl) brightnessctl set "${target}%";;
    light)         light -S "$target";;
    xbacklight)    xbacklight -set "$target";;
    ddcutil)       # map percent to VCP 0x10 absolute value
                   local m cur max v
                   m=$(ddcutil getvcp 10 2>/dev/null | awk -F'[=, ]+' '/max value/ {print $9}')
                   [[ -n $m ]] || return 1
                   v=$(( (target*m + 50)/100 ))
                   ddcutil setvcp 10 "$v";;
    sysfs)         local p=$(_b_sysfs_path); [[ -n $p ]] || return 1
                   local m=$(<"$p/max_brightness")
                   local v=$(( (target*m + 50)/100 ))
                   if [[ -w "$p/brightness" ]]; then
                     printf "%s" "$v" > "$p/brightness"
                   else
                     printf "%s" "$v" | sudo tee "$p/brightness" >/dev/null
                   fi;;
  esac
}

br_info(){ emulate -L zsh; setopt pipefail err_return
  local p; p=$(_b_read_pct) || { print -ru2 -- "no brightness backend found"; return 1; }
  printf "brightness %s%%  %s\n" "$p" "$(_b_bar "$p" 20)"
}

br_set(){ emulate -L zsh; setopt pipefail err_return
  local v=$1
  [[ -n $v ]] || { print -ru2 -- "usage: br_set <percent>"; return 2; }
  _b_set_pct "$v" || { print -ru2 -- "failed to set brightness"; return 1; }
  br_info
}

br_up(){ emulate -L zsh; setopt pipefail err_return
  local step=${1:-5} cur=$(_b_read_pct) || { print -ru2 -- "no brightness backend"; return 1; }
  _b_set_pct $(( cur + step )) && br_info
}

br_down(){ emulate -L zsh; setopt pipefail err_return
  local step=${1:-5} cur=$(_b_read_pct) || { print -ru2 -- "no brightness backend"; return 1; }
  _b_set_pct $(( cur - step )) && br_info
}
# ==== end patch ====
