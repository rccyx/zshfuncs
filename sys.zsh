ashgw() {
  emulate -L zsh
  setopt pipefail

  local r=$'\e[0m' g=$'\e[1;32m' m=$'\e[1;35m'

  # -------- flags --------
  local animate=0 anim="scan" frames="${AGFETCH_FRAMES:-48}" speed_ms="${AGFETCH_SPEED_MS:-45}"
  local opt
  while getopts ":aA:f:s:" opt; do
    case $opt in
      a) animate=1 ;;
      A) anim="$OPTARG" ;;      # scan | pulse
      f) [[ "$OPTARG" == <-> ]] && frames="$OPTARG" ;;
      s) [[ "$OPTARG" == <-> ]] && speed_ms="$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))

  # ---------- gather ----------
  local os kernel uptime term shell wm pkgs cpu gpu mem disk ip temp
  os=$(command -v lsb_release >/dev/null && lsb_release -ds || grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"')
  kernel=$(uname -r)
  uptime=$(uptime -p | sed 's/^up //')
  term=$([ -n "$TMUX" ] && echo tmux || echo "${TERM:-unknown}")
  shell=$(basename "$SHELL")
  wm=${XDG_CURRENT_DESKTOP:-$(wmctrl -m 2>/dev/null | awk -F: '/Name/{gsub(/^ /,"",$2);print $2}')}
  pkgs=$(command -v dpkg >/dev/null && dpkg -l 2>/dev/null | awk 'BEGIN{n=0} /^ii/{n++} END{print n}')
  cpu=$(lscpu | awk -F: '/Model name/{gsub(/^[ \t]+/,"",$2);print $2}')
  gpu=$(lspci | grep -E "VGA|3D|Display" | sed -E 's/.*: //; s/ Corporation//; s/ Integrated Graphics Controller/ iGPU/' | head -n1)
  mem=$(free -h | awk '/Mem:/ {printf "%s used of %s", $3, $2}')
  disk=$(df -h / | awk 'NR==2{printf "%s used of %s (%s)", $3, $2, $5}')
  ip=$(ip -brief addr | awk '!/lo/ && $3 ~ /\// {print $1": "$3}' | head -n1)
  temp=$(command -v sensors >/dev/null && sensors 2>/dev/null | awk '/Package id 0|Tctl|Tdie|CPU/ {t=$NF; gsub(/[()]/,"",t); print t; exit}')

  # ---------- logo ----------
  local -a logo_lines
  if command -v figlet >/dev/null; then
    logo_lines=("${(f)$(figlet -f slant "@ashgw")}")
  else
    logo_lines=("@ashgw  (install 'figlet' for big logo: sudo apt install figlet)")
  fi

  # ---------- right column (split into lines) ----------
  local info
  info="$(printf "%s\n" \
    "${g}OS      ${r}${os}" \
    "${g}Kernel  ${r}${kernel}" \
    "${g}Uptime  ${r}${uptime}" \
    "${g}WM      ${r}${wm:-unknown}" \
    "${g}TERM    ${r}${term}" \
    "${g}SHELL   ${r}${shell}" \
    "${g}PKG     ${r}${pkgs:-0}" \
    "${g}CPU     ${r}${cpu}" \
    "$( [ -n "$gpu" ] && printf "%s" "${g}GPU     ${r}${gpu}" )" \
    "${g}MEM     ${r}${mem}" \
    "${g}DISK    ${r}${disk}" \
    "$( [ -n "$temp" ] && printf "%s" "${g}TEMP    ${r}${temp}" )" \
    "${g}NET     ${r}${ip}" \
  )"
  local -a info_lines
  info_lines=("${(f)info}")

  # ---------- layout ----------
  local COL=${AGFETCH_COL:-36}              # width reserved for logo column
  local H=$(( ${#logo_lines[@]} > ${#info_lines[@]} ? ${#logo_lines[@]} : ${#info_lines[@]} ))

  # helpers
  local rev=$'\e[7m' nor=$'\e[27m'
  _pad() { printf "%-*s" "$2" "$1"; }                    # _pad "str" width
  _color_for() { local n=$(( $1 % 6 )); print -n -- $'\e[1;3'$((31+n))'m'; }  # bright 31..36

  _render_frame() {
    local tick="$1" i ll rr line color start band end left mid right
    local bandw="${AGFETCH_BAND:-3}"
    for ((i=1; i<=H; ++i)); do
      ll="${logo_lines[i]:-}"
      ll="$(_pad "$ll" "$COL")"
      rr="${info_lines[i]:-}"

      if (( animate )); then
        case "$anim" in
          scan)
            start=$(( (tick % (COL - bandw + 1)) + 1 ))
            end=$(( start + bandw - 1 ))
            (( end > COL )) && end="$COL"
            left="${ll[1,start-1]}"
            mid="${ll[start,end]}"
            right="${ll[end+1,-1]}"
            line="${m}${left}${rev}${mid}${nor}${right}${r}"
            ;;
          pulse)
            color="$(_color_for $((tick + i)))"
            line="${color}${ll}${r}"
            ;;
          *)
            line="${m}${ll}${r}"
            ;;
        esac
      else
        line="${m}${ll}${r}"
      fi

      printf "%s %s\n" "$line" "$rr"
    done
  }

  if (( animate )); then
    # hide cursor, restore on exit
    printf '\e[?25l'
    trap 'printf "\e[?25h"; return 130' INT TERM
    local f
    for ((f=0; f<frames; ++f)); do
      _render_frame "$f"
      printf "\e[%dA" "$H"
      sleep "$(printf "0.%03d" "$(( speed_ms ))")"
    done
    # final frame without moving cursor up
    _render_frame "$frames"
    printf '\e[?25h'
  else
    # single render, no animation
    _render_frame 0
  fi
}
diskusage() {
  if ! command -v dua >/dev/null 2>&1; then
    echo -e "\e[1;31m❌ dua not found.\e[0m"
    echo -e "👉 Install it with: \e[1;34mcargo install dua-cli\e[0m"
    return 1
  fi
  dua i /
}

diskspace() {
  local df_output=$(df -h $HOME | tail -n 1)
  local total=$(echo $df_output | awk '{print $2}')
  local used=$(echo $df_output | awk '{print $3}')
  local avail=$(echo $df_output | awk '{print $4}')
  local sentence="Your total disk space is $total, with $used used and $avail available."
  echo -e "\033[32m$sentence\033[0m"
}

storage(){
  sudo ncdu / --exclude /proc --exclude /sys
}


# Suspend the system (sleep)
suspend() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl suspend
  elif command -v pm-suspend >/dev/null 2>&1; then
    pm-suspend
  else
    echo "No suspend command found (systemctl/pm-suspend missing)."
    return 1
  fi
}

# Hibernate the system
hibernate() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl hibernate
  elif command -v pm-hibernate >/dev/null 2>&1; then
    pm-hibernate
  else
    echo "No hibernate command found (systemctl/pm-hibernate missing)."
    return 1
  fi
}
# =========================
# psf  → find processes and kill selected
# psf             pick and SIGTERM
# psf -9          pick and SIGKILL
# =========================
psf() {
  local sig="15"
  [[ "$1" =~ ^-?[0-9]+$ ]] && sig="${1#-}"
  if _has fzf; then
    local lines pids
    lines=$(ps -eo pid,user,pcpu,pmem,etime,comm --sort=-pcpu | awk 'NR==1 || $3>0.1' | fzf --multi --height 70% --border --prompt="kill [sig $sig] ⇢ " --preview="echo {}")
    [[ -z "$lines" ]] && return 1
    pids=$(echo "$lines" | awk 'NR>1{print $1}')
    echo "$pids" | xargs -r kill -"$sig"
  else
    ps aux | head
    echo "fzf not installed. Use kill manually or install fzf."
  fi
}

# heat: minimal, fast, quiet
# default → "59°C"
# flags:
#   -r    raw number only, e.g. "59"
#   -v    verbose line, e.g. "CPU 59°C GPU 47°C FAN 1200 rpm"
#   -g    try to include GPU (only used with -v)
#   -f    try to include FAN (only used with -v)
# env:
#   HEAT_CPU_PATH=/sys/class/hwmon/hwmonX/tempY_input
#   HEAT_GPU=auto|nvidia|amdgpu|off   (default auto)
#   HEAT_FAN=auto|off                 (default auto)
heat() {
  emulate -L zsh
  setopt pipefail null_glob nonomatch extended_glob
  unsetopt xtrace verbose  # kill any inherited tracing

  local cpu_hint="/sys/class/hwmon/hwmon5/temp1_input"
  local cpu_env="${HEAT_CPU_PATH:-}"
  local want_gpu="${HEAT_GPU:-auto}"
  local want_fan="${HEAT_FAN:-auto}"
  local raw=0 verbose=0 force_gpu=off force_fan=off

  while getopts ":rgfv" opt; do
    case $opt in
      r) raw=1 ;;
      v) verbose=1 ;;
      g) force_gpu=on ;;
      f) force_fan=on ;;
    esac
  done

  _read_temp_file() {
    local p="$1" v
    [[ -r "$p" ]] || return 1
    v=$(<"$p") || return 1
    [[ -n "$v" ]] || return 1
    if [[ "$v" -gt 200 ]]; then printf "%d" $(( v/1000 )); else printf "%d" "$v"; fi
  }

  _find_cpu_temp() {
    local v h l f
    [[ -n "$cpu_env" ]] && v=$(_read_temp_file "$cpu_env") && { print -r -- "$v"; return 0; }
    v=$(_read_temp_file "$cpu_hint") && { print -r -- "$v"; return 0; }
    local -a hmons; hmons=( /sys/class/hwmon/hwmon*(N) )
    for h in $hmons; do
      local -a labels; labels=( "$h"/temp*_label(N) )
      for l in $labels; do
        case "$(tr '[:upper:]' '[:lower:]' <"$l")" in
          *tctl*|*tdie*|*package*|*cpu*)
            f="${l/_label/_input}"
            v=$(_read_temp_file "$f") && { print -r -- "$v"; return 0; }
        esac
      done
      f="$h/temp1_input"
      v=$(_read_temp_file "$f") && { print -r -- "$v"; return 0; }
    done
    if command -v sensors >/dev/null 2>&1; then
      v=$(sensors 2>/dev/null | awk '/(Tctl|Tdie|Package id 0|CPU)/{match($0,/[0-9]+(\.[0-9])?/,m); if(m[0]!=""){printf "%.0f\n", m[0]; exit}}')
      [[ -n "$v" ]] && { print -r -- "$v"; return 0; }
    fi
    return 1
  }

  _find_fan() {
    local best=0 rpm
    local -a hmons; hmons=( /sys/class/hwmon/hwmon*(N) )
    local h
    for h in $hmons; do
      local -a fans; fans=( "$h"/fan*_input(N) )
      local f
      for f in $fans; do
        rpm=$(<"$f") || continue
        (( rpm > best )) && best="$rpm"
      done
    done
    if (( best == 0 )) && [[ -r /proc/acpi/ibm/fan ]]; then
      rpm=$(awk -F': *' '/speed:/{print $2}' /proc/acpi/ibm/fan 2>/dev/null)
      [[ -n "$rpm" ]] && best="$rpm"
    fi
    (( best > 0 )) && { print -r -- "$best"; return 0; }
    return 1
  }

  _find_gpu_temp() {
    local mode="$1" t
    [[ "$mode" == "off" ]] && return 1
    if command -v nvidia-smi >/dev/null 2>&1; then
      t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1)
      [[ -n "$t" ]] && { print -r -- "$t"; return 0; }
    fi
    # AMD paths
    local -a amds; amds=( /sys/class/hwmon/hwmon*/temp*_input(N) )
    local f
    for f in $amds; do
      if readlink -f "$f" | grep -qi amdgpu; then
        t=$(_read_temp_file "$f") && { print -r -- "$t"; return 0; }
      fi
    done
    local -a drm; drm=( /sys/class/drm/card*/device/hwmon/hwmon*/temp*_input(N) )
    for f in $drm; do
      t=$(_read_temp_file "$f") && { print -r -- "$t"; return 0; }
    done
    return 1
  }

  local cpu gpu fan
  cpu=$(_find_cpu_temp) || { print -ru2 -- "no temperature source found"; return 1; }

  if (( verbose )); then
    # include GPU/FAN only when asked
    [[ "$force_gpu" == "on" ]] && gpu=$(_find_gpu_temp "${HEAT_GPU:-auto}") || gpu=""
    [[ "$force_fan" == "on" ]] && fan=$(_find_fan) || fan=""
    local out="CPU ${cpu}°C"
    [[ -n "$gpu" ]] && out+="  GPU ${gpu}°C"
    [[ -n "$fan" ]] && out+="  FAN ${fan} rpm"
    print -r -- "$out"
  else
    (( raw )) && print -r -- "$cpu" || print -r -- "${cpu}°C"
  fi
}

