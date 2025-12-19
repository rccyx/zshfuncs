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

# Sleep basically
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


health() {
  emulate -L zsh
  setopt localoptions err_return no_unset pipefail

  local rc=0

  local _pfx_ok="%F{green}ok%f"
  local _pfx_warn="%F{yellow}warn%f"
  local _pfx_bad="%F{red}bad%f"
  local _pfx_note="%F{cyan}::%f"

  local cache_gb="${HEALTH_CACHE_GB:-5}"
  local smart_warn_pct="${HEALTH_SMART_WARN_PCT:-80}"
  local smart_bad_pct="${HEALTH_SMART_BAD_PCT:-95}"

  print -P "$_pfx_note systemd"

  if command -v systemctl >/dev/null 2>&1; then
    local failed
    failed=$(systemctl --failed --no-legend 2>/dev/null | sed '/^[[:space:]]*$/d' || true)
    if [[ -n "$failed" ]]; then
      print -P "$_pfx_bad failed units:"
      print -r -- "$failed" | sed 's/^/  /'
      rc=1
    else
      print -P "$_pfx_ok no failed units"
    fi
  else
    print -P "$_pfx_warn systemctl not found"
  fi

  print -P "$_pfx_note ssd smart"

  if ! command -v smartctl >/dev/null 2>&1; then
    print -P "$_pfx_warn smartctl not found (smartmontools)"
  else
    local -a disks
    disks=("${(@f)$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')}")

    if [[ ${#disks[@]} -eq 0 ]]; then
      print -P "$_pfx_warn no disks found"
    else
      local d rot dev out try_sudo
      for d in "${disks[@]}"; do
        dev="/dev/$d"
        rot=""
        [[ -r "/sys/block/$d/queue/rotational" ]] && rot="$(<"/sys/block/$d/queue/rotational")"
        [[ "$rot" == "1" ]] && continue

        out=""
        if smartctl -a "$dev" >/dev/null 2>&1; then
          out="$(smartctl -a "$dev" 2>/dev/null || true)"
        elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
          out="$(sudo -n smartctl -a "$dev" 2>/dev/null || true)"
        fi

        if [[ -z "$out" ]]; then
          print -P "$_pfx_warn $dev: cannot read smart data (need perms?)"
          continue
        fi

        local pct_used crit reall pend uncor nvme_media nvme_errlog
        pct_used="$(print -r -- "$out" | awk -F: '/^[[:space:]]*Percentage Used:/{gsub(/[^0-9]/,"",$2);print $2;exit}')"
        crit="$(print -r -- "$out" | awk -F: '/^[[:space:]]*Critical Warning:/{gsub(/^[[:space:]]*/,"",$2);print $2;exit}')"
        nvme_media="$(print -r -- "$out" | awk -F: '/^[[:space:]]*Media and Data Integrity Errors:/{gsub(/[^0-9]/,"",$2);print $2;exit}')"
        nvme_errlog="$(print -r -- "$out" | awk -F: '/^[[:space:]]*Error Information Log Entries:/{gsub(/[^0-9]/,"",$2);print $2;exit}')"

        reall="$(print -r -- "$out" | awk '$2=="Reallocated_Sector_Ct"{print $10;exit}')"
        pend="$(print -r -- "$out" | awk '$2=="Current_Pending_Sector"{print $10;exit}')"
        uncor="$(print -r -- "$out" | awk '$2=="Offline_Uncorrectable"{print $10;exit}')"

        local bad=0 warn=0
        [[ -n "$pct_used" && "$pct_used" -ge "$smart_warn_pct" ]] && warn=1
        [[ -n "$pct_used" && "$pct_used" -ge "$smart_bad_pct" ]] && bad=1
        [[ -n "$reall" && "$reall" -gt 0 ]] && warn=1
        [[ -n "$pend" && "$pend" -gt 0 ]] && bad=1
        [[ -n "$uncor" && "$uncor" -gt 0 ]] && bad=1
        [[ -n "$nvme_media" && "$nvme_media" -gt 0 ]] && bad=1
        [[ -n "$nvme_errlog" && "$nvme_errlog" -gt 0 ]] && warn=1

        local summary=""
        [[ -n "$pct_used" ]] && summary+=" pct_used=${pct_used}%"
        [[ -n "$reall" ]] && summary+=" reallocated=$reall"
        [[ -n "$pend" ]] && summary+=" pending=$pend"
        [[ -n "$uncor" ]] && summary+=" uncorrectable=$uncor"
        [[ -n "$nvme_media" ]] && summary+=" media_err=$nvme_media"
        [[ -n "$nvme_errlog" ]] && summary+=" errlog=$nvme_errlog"
        [[ -n "$crit" ]] && summary+=" crit=${crit}"

        if (( bad )); then
          print -P "$_pfx_bad $dev:$summary"
          rc=1
        elif (( warn )); then
          print -P "$_pfx_warn $dev:$summary"
        else
          print -P "$_pfx_ok $dev:${summary:-" smart ok"}"
        fi
      done
    fi
  fi

  print -P "$_pfx_note caches"

  local -a paths
  paths=(
    "$HOME/.cache"
    "$HOME/.local/share/Trash"
    "$HOME/.npm"
    "$HOME/.pnpm-store"
    "$HOME/.cache/pip"
    "$HOME/.cache/yarn"
    "$HOME/.cache/go-build"
    "$HOME/.cargo/registry"
    "$HOME/.gradle/caches"
    "$HOME/.m2/repository"
    "/var/cache"
    "/var/log/journal"
  )

  local du_bytes_ok=0
  du -sb "$HOME" >/dev/null 2>&1 && du_bytes_ok=1

  local cache_bytes=$(( cache_gb * 1024 * 1024 * 1024 ))
  local -a lines
  lines=()

  local p sz
  for p in "${paths[@]}"; do
    [[ -e "$p" ]] || continue
    if (( du_bytes_ok )); then
      sz="$(du -sb "$p" 2>/dev/null | awk '{print $1}' || true)"
    else
      sz="$(du -sk "$p" 2>/dev/null | awk '{print $1*1024}' || true)"
    fi
    [[ -n "$sz" ]] || continue
    lines+=("${sz}\t${p}")
  done

  if [[ ${#lines[@]} -eq 0 ]]; then
    print -P "$_pfx_warn no cache dirs readable"
  else
    local fmt=0
    command -v numfmt >/dev/null 2>&1 && fmt=1

    local sorted
    sorted="$(print -r -- "${lines[@]}" | sort -nr -k1,1 | head -n 12)"

    local any_bloated=0
    while IFS=$'\t' read -r sz p; do
      [[ -n "$sz" && -n "$p" ]] || continue
      local h="$sz"
      (( fmt )) && h="$(numfmt --to=iec --suffix=B "$sz" 2>/dev/null || echo "$sz")"
      if [[ "$sz" -ge "$cache_bytes" ]]; then
        print -P "$_pfx_warn $h  $p"
        any_bloated=1
      else
        print -P "$_pfx_ok $h  $p"
      fi
    done <<< "$sorted"

    (( any_bloated )) && rc=1
  fi

  return "$rc"
}

bloat() {
  emulate -L zsh
  setopt localoptions err_return no_unset pipefail

  local days=30 n=50 allfs=0 root="/"

  local opt
  while getopts ":d:n:ah" opt; do
    case "$opt" in
      d) days="$OPTARG" ;;
      n) n="$OPTARG" ;;
      a) allfs=1 ;;
      h)
        cat <<'EOF'
bloat [-d days] [-n top] [-a] [path]

- finds largest files not modified in >days
- defaults: days=30, top=50, path=/
- -a scans across mountpoints (no -xdev)
EOF
        return 0
        ;;
      \?) echo "unknown option: -$OPTARG" >&2; return 1 ;;
      :)  echo "missing value for -$OPTARG" >&2; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))
  [[ -n ${1-} ]] && root="$1"

  command -v find >/dev/null 2>&1 || { echo "find not found" >&2; return 1; }

  local fmt=0
  command -v numfmt >/dev/null 2>&1 && fmt=1

  local -a prune
  prune=(
    -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp
    -o -path /var/run -o -path /var/tmp
  )

  local -a base
  base=()
  (( allfs )) || base+=(-xdev)

  local test_printf=0
  find "$root" -maxdepth 0 -printf "" >/dev/null 2>&1 && test_printf=1

  if (( test_printf )); then
    find "$root" "${base[@]}" \( "${prune[@]}" \) -prune -o \
      -type f -mtime +"$days" -printf '%s\t%TY-%Tm-%Td\t%p\n' 2>/dev/null \
      | sort -nr -k1,1 | head -n "$n" \
      | while IFS=$'\t' read -r sz dt p; do
          [[ -n "$sz" && -n "$p" ]] || continue
          local h="$sz"
          (( fmt )) && h="$(numfmt --to=iec --suffix=B "$sz" 2>/dev/null || echo "$sz")"
          printf "%-10s  %s  %s\n" "$h" "$dt" "$p"
        done
  else
    find "$root" "${base[@]}" \( "${prune[@]}" \) -prune -o \
      -type f -mtime +"$days" -print0 2>/dev/null \
      | xargs -0r stat -c '%s\t%y\t%n' 2>/dev/null \
      | sort -nr -k1,1 | head -n "$n" \
      | while IFS=$'\t' read -r sz dt p; do
          [[ -n "$sz" && -n "$p" ]] || continue
          dt="${dt%% *}"
          local h="$sz"
          (( fmt )) && h="$(numfmt --to=iec --suffix=B "$sz" 2>/dev/null || echo "$sz")"
          printf "%-10s  %s  %s\n" "$h" "$dt" "$p"
        done
  fi
}
