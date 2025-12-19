persist() {
  emulate -L zsh
  setopt pipefail no_unset null_glob
  unsetopt xtrace verbose

  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}/seckit"
  local dir="$state_root/persist"
  local init=0 full=0 compare="last"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --init) init=1; shift ;;
      --full) full=1; shift ;;
      --baseline) compare="baseline"; shift ;;
      --state-dir)
        [[ -n "${2-}" ]] || { print -ru2 -- "persist: --state-dir requires a value"; return 2; }
        dir="$2"; shift 2
        ;;
      -h|--help)
        cat <<'EOF'
persist [--init] [--baseline] [--full] [--state-dir DIR]

default: diff current snapshot vs last snapshot
--init: force-create baseline + last from current snapshot
--baseline: diff vs baseline instead of last
--full: print current snapshot (still updates last)
EOF
        return 0
        ;;
      *)
        print -ru2 -- "persist: unknown arg: $1"
        return 2
        ;;
    esac
  done

  mkdir -p "$dir" || { print -ru2 -- "persist: cannot mkdir: $dir"; return 2; }
  chmod 700 "$dir" 2>/dev/null || true

  local ts current last baseline ref
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  current="$dir/snap.$ts.txt"
  last="$dir/last.txt"
  baseline="$dir/baseline.txt"

  _p_section() { print -r -- $'\n'"== $1 =="; }
  _p_have() { command -v "$1" >/dev/null 2>&1; }

  _p_tree_stat() {
    local root="$1"
    [[ -d "$root" ]] || { print -r -- "(missing dir) $root"; return 0; }
    if find "$root" -maxdepth 0 -printf "" >/dev/null 2>&1; then
      LC_ALL=C find "$root" -type f -printf '%p\t%Y\t%s\t%m\t%u\t%g\n' 2>/dev/null | LC_ALL=C sort || true
    else
      LC_ALL=C find "$root" -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
        stat -c '%n\t%Y\t%s\t%a\t%U\t%G' "$p" 2>/dev/null || print -r -- "$p\t(stat_failed)"
      done || true
    fi
    return 0
  }

  _p_tree_sha() {
    local root="$1"
    [[ -d "$root" ]] || { print -r -- "(missing dir) $root"; return 0; }
    LC_ALL=C find "$root" -type f -print0 2>/dev/null \
      | LC_ALL=C sort -z \
      | xargs -0r sha256sum 2>/dev/null \
      | LC_ALL=C sort -k2,2 || true
    return 0
  }

  _p_file_stat() {
    local f="$1"
    [[ -e "$f" ]] || { print -r -- "(missing file) $f"; return 0; }
    stat -c '%n\t%Y\t%s\t%a\t%U\t%G' "$f" 2>/dev/null || print -r -- "$f\t(stat_failed)"
    return 0
  }

  _p_file_sha() {
    local f="$1"
    [[ -e "$f" ]] || { print -r -- "(missing file) $f"; return 0; }
    sha256sum "$f" 2>/dev/null || print -r -- "(sha_failed) $f"
    return 0
  }

  _p_snap() {
    print -r -- "persist_snapshot_version=1"
    print -r -- "ts_utc=$ts"
    print -r -- "user=$USER"
    print -r -- "host=$(hostname 2>/dev/null || echo unknown)"
    print -r -- "kernel=$(uname -r 2>/dev/null || echo unknown)"
    print -r -- "path=$PATH"

    _p_section "systemd system unit files"
    if _p_have systemctl; then
      systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null \
        | awk '{print $1 "\t" $2}' | LC_ALL=C sort || true
      _p_section "systemd system timers (unit files)"
      systemctl list-unit-files --type=timer --no-legend --no-pager 2>/dev/null \
        | awk '{print $1 "\t" $2}' | LC_ALL=C sort || true
      _p_section "systemd system timers (scheduled)"
      systemctl list-timers --all --no-legend --no-pager 2>/dev/null \
        | sed 's/[[:space:]]\+/ /g' | LC_ALL=C sort || true
    else
      print -r -- "(systemctl not found)"
    fi

    _p_section "/etc/systemd/system stat"
    _p_tree_stat "/etc/systemd/system"
    _p_section "/etc/systemd/system sha256"
    _p_tree_sha "/etc/systemd/system"

    _p_section "systemd user unit files"
    if _p_have systemctl; then
      systemctl --user list-unit-files --type=service --no-legend --no-pager 2>/dev/null \
        | awk '{print $1 "\t" $2}' | LC_ALL=C sort || true
      _p_section "systemd user timers (unit files)"
      systemctl --user list-unit-files --type=timer --no-legend --no-pager 2>/dev/null \
        | awk '{print $1 "\t" $2}' | LC_ALL=C sort || true
      _p_section "systemd user timers (scheduled)"
      systemctl --user list-timers --all --no-legend --no-pager 2>/dev/null \
        | sed 's/[[:space:]]\+/ /g' | LC_ALL=C sort || true
    else
      print -r -- "(systemctl not found)"
    fi

    _p_section "~/.config/systemd/user stat"
    _p_tree_stat "$HOME/.config/systemd/user"
    _p_section "~/.config/systemd/user sha256"
    _p_tree_sha "$HOME/.config/systemd/user"

    _p_section "cron system files stat"
    _p_file_stat "/etc/crontab"
    _p_file_stat "/etc/anacrontab"
    _p_tree_stat "/etc/cron.d"
    _p_tree_stat "/etc/cron.hourly"
    _p_tree_stat "/etc/cron.daily"
    _p_tree_stat "/etc/cron.weekly"
    _p_tree_stat "/etc/cron.monthly"

    _p_section "cron system files sha256"
    _p_file_sha "/etc/crontab"
    _p_file_sha "/etc/anacrontab"
    _p_tree_sha "/etc/cron.d"
    _p_tree_sha "/etc/cron.hourly"
    _p_tree_sha "/etc/cron.daily"
    _p_tree_sha "/etc/cron.weekly"
    _p_tree_sha "/etc/cron.monthly"

    _p_section "user crontab (content)"
    if _p_have crontab; then
      crontab -l 2>/dev/null | sed 's/[[:space:]]\+$//' || print -r -- "(no user crontab)"
    else
      print -r -- "(crontab not found)"
    fi

    _p_section "authorized_keys (fingerprints + file hash)"
    local ak="$HOME/.ssh/authorized_keys"
    if [[ -e "$ak" ]]; then
      _p_file_stat "$ak"
      _p_file_sha "$ak"
      if _p_have ssh-keygen; then
        ssh-keygen -lf "$ak" 2>/dev/null | LC_ALL=C sort || true
      else
        print -r -- "(ssh-keygen not found)"
      fi
    else
      print -r -- "(missing file) $ak"
    fi

    _p_section "shell rc files stat"
    local -a rcs
    rcs=(
      "$HOME/.zshrc"
      "$HOME/.zshenv"
      "$HOME/.zprofile"
      "$HOME/.bashrc"
      "$HOME/.bash_profile"
      "$HOME/.profile"
    )
    local f
    for f in "${rcs[@]}"; do _p_file_stat "$f"; done

    _p_section "shell rc files sha256"
    for f in "${rcs[@]}"; do _p_file_sha "$f"; done

    _p_section "writable PATH dirs"
    local -a path_dirs uniq_dirs
    path_dirs=("${(@s/:/)PATH}")
    uniq_dirs=()
    local d
    for d in "${path_dirs[@]}"; do
      [[ -z "$d" ]] && continue
      [[ "${uniq_dirs[(Ie)$d]}" -gt 0 ]] && continue
      uniq_dirs+=("$d")
    done
    for d in "${uniq_dirs[@]}"; do
      [[ -d "$d" && -w "$d" ]] && print -r -- "$d"
    done | LC_ALL=C sort || true

    _p_section "executables in writable PATH dirs (stat)"
    for d in "${uniq_dirs[@]}"; do
      [[ -d "$d" && -w "$d" ]] || continue
      print -r -- "-- $d"
      if find "$d" -maxdepth 0 -printf "" >/dev/null 2>&1; then
        LC_ALL=C find "$d" -maxdepth 1 -type f -perm -111 -printf '%p\t%Y\t%s\t%m\t%u\t%g\n' 2>/dev/null | LC_ALL=C sort || true
      else
        LC_ALL=C find "$d" -maxdepth 1 -type f -perm -111 -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
          stat -c '%n\t%Y\t%s\t%a\t%U\t%G' "$p" 2>/dev/null || print -r -- "$p\t(stat_failed)"
        done || true
      fi
    done

    _p_section "executables in writable PATH dirs (sha256)"
    for d in "${uniq_dirs[@]}"; do
      [[ -d "$d" && -w "$d" ]] || continue
      print -r -- "-- $d"
      LC_ALL=C find "$d" -maxdepth 1 -type f -perm -111 -print0 2>/dev/null \
        | LC_ALL=C sort -z \
        | xargs -0r sha256sum 2>/dev/null \
        | LC_ALL=C sort -k2,2 || true
    done

    return 0
  }

  _p_snap > "$current" || { print -ru2 -- "persist: snapshot failed"; return 2; }
  chmod 600 "$current" 2>/dev/null || true

  if (( init )); then
    cp -f "$current" "$baseline" || { print -ru2 -- "persist: cannot write baseline"; return 2; }
    cp -f "$current" "$last" || { print -ru2 -- "persist: cannot write last"; return 2; }
    print -r -- "persist: baseline initialized: ${baseline/#$HOME/~}"
    return 0
  fi

  if [[ ! -f "$baseline" ]]; then
    cp -f "$current" "$baseline" || { print -ru2 -- "persist: cannot write baseline"; return 2; }
    cp -f "$current" "$last" || { print -ru2 -- "persist: cannot write last"; return 2; }
    print -r -- "persist: baseline created: ${baseline/#$HOME/~}"
    print -r -- "persist: ok (rerun to diff)"
    return 0
  fi

  if [[ ! -f "$last" ]]; then
    cp -f "$current" "$last" || { print -ru2 -- "persist: cannot write last"; return 2; }
    print -r -- "persist: created last snapshot: ${last/#$HOME/~}"
    return 0
  fi

  [[ "$compare" == "baseline" ]] && ref="$baseline" || ref="$last"

  if (( full )); then
    cat "$current"
    cp -f "$current" "$last" 2>/dev/null || true
    return 0
  fi

  local out rc
  out="$(diff -u --label "ref:$(basename "$ref")" --label "now:$(basename "$current")" "$ref" "$current" 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    print -r -- "$out"
    rc=1
  else
    print -r -- "persist: ok"
    rc=0
  fi

  cp -f "$current" "$last" 2>/dev/null || true
  return "$rc"
}

# ============================================
# netwatch - network egress visibility
# "who is my machine talking to right now?"
#
# deps: ss (iproute2)
# optional: whois (for --cymru), mmdblookup + GeoLite2 mmdb (for --enrich), getent (for --rdns)
#
# flags:
#   --all        include non-outbound-ish sockets too
#   --dns        show only DNS (53/853/5353)
#   --top        summary only
#   --enrich     best-effort ASN + country (offline if mmdb exists)
#   --cymru      allow online ASN lookup (Team Cymru) if offline not available
#   --rdns       reverse DNS via getent (slow-ish)
#   --dns-log N  show last N minutes of systemd-resolved logs (best-effort)
# ============================================
netwatch() {
  emulate -L zsh
  setopt pipefail no_unset

  local all=0 only_dns=0 top=0
  local enrich=0 cymru=0 rdns=0
  local dns_log=0 dns_log_mins=5

  while (( $# )); do
    case "$1" in
      --all) all=1; shift ;;
      --dns) only_dns=1; shift ;;
      --top) top=1; shift ;;
      --enrich) enrich=1; shift ;;
      --cymru) cymru=1; enrich=1; shift ;;
      --rdns) rdns=1; shift ;;
      --dns-log)
        dns_log=1
        if [[ -n "${2-}" ]] && [[ "$2" -ge 0 ]] 2>/dev/null; then
          dns_log_mins="$2"
          shift 2
        else
          shift
        fi
        ;;
      -h|--help)
        cat <<'EOF'
netwatch [--all] [--dns] [--top] [--enrich] [--cymru] [--rdns] [--dns-log N]

default: shows outbound-ish TCP/UDP with process mapping using ss
EOF
        return 0
        ;;
      *)
        print -ru2 -- "netwatch: unknown arg: $1"
        return 2
        ;;
    esac
  done

  command -v ss >/dev/null 2>&1 || {
    print -ru2 -- "netwatch: missing dep: ss (iproute2)"
    return 127
  }

  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}/seckit/netwatch"
  mkdir -p "$state_root" 2>/dev/null || true
  chmod 700 "$state_root" 2>/dev/null || true

  local ports_csv="${NETWATCH_COMMON_PORTS:-22,53,80,123,443,465,587,853,993,995,8080,8443}"
  local -a common_ports
  common_ports=("${(s:,:)ports_csv}")

  local ts tmp ips
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  tmp="$state_root/active.$ts.tsv"
  ips="$state_root/ips.$ts.txt"

  # Snapshot + parse to TSV:
  # dir proto state pid proc lhost lport rhost rport timer
  ss -H -n -tup -o 2>/dev/null | awk -v all="$all" '
    function split_hp(s, host, port) {
      host=s; port=s
      if (s ~ /^\[/) {
        sub(/^\[/,"",host); sub(/\].*$/,"",host)
        sub(/^.*\]:/,"",port)
      } else {
        sub(/:[^:]*$/,"",host)
        sub(/^.*:/,"",port)
      }
      return host SUBSEP port
    }
    function pid_from_users(u,   x) {
      if (match(u,/pid=[0-9]+/)) return substr(u,RSTART+4,RLENGTH-4)
      return "-"
    }
    function comm_from_users(u,   t) {
      if (match(u,/\(\("[^"]+"/)) {
        t=substr(u,RSTART+3,RLENGTH-3); sub(/"$/,"",t); return t
      }
      return "-"
    }
    BEGIN { OFS="\t" }
    {
      proto=$1; state=$2
      l=$5; r=$6
      users=""; timer=""
      for (i=7;i<=NF;i++) {
        if ($i ~ /^users:/) users=$i
        if ($i ~ /^timer:/) timer=$i
      }

      x=split_hp(l); split(x,L,SUBSEP); lhost=L[1]; lport=L[2]
      x=split_hp(r); split(x,R,SUBSEP); rhost=R[1]; rport=R[2]

      if (proto=="udp" && (rhost=="*" || rhost=="0.0.0.0" || rhost=="::")) next

      dir="mix"
      lp=lport+0; rp=rport+0
      if (lp>1024 && rp>=1 && rp<=65535) dir="out"
      if (!all && dir!="out") next

      pid=pid_from_users(users)
      comm=comm_from_users(users)

      print dir, proto, state, pid, comm, lhost, lport, rhost, rport, timer
    }
  ' > "$tmp" || { print -ru2 -- "netwatch: snapshot failed"; return 2; }

  if (( only_dns )); then
    awk -F'\t' '($9=="53" || $9=="853" || $9=="5353"){print}' "$tmp" > "$tmp.dns" 2>/dev/null || true
    mv -f "$tmp.dns" "$tmp" 2>/dev/null || true
  fi

  awk -F'\t' '{print $8}' "$tmp" | sort -u > "$ips" 2>/dev/null || true

  typeset -A ip_class ip_asn ip_cc ip_org ip_name

  # classify IPs in one shot
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$ips" <<'PY' 2>/dev/null
import sys, ipaddress
path=sys.argv[1]
for line in open(path,'r',encoding='utf-8',errors='ignore'):
  ip=line.strip()
  if not ip or ip in ("*","0.0.0.0","::"):
    continue
  try:
    o=ipaddress.ip_address(ip)
    if o.is_loopback: cls="loopback"
    elif o.is_private: cls="private"
    elif o.is_link_local: cls="linklocal"
    elif o.is_multicast: cls="multicast"
    elif o.is_reserved: cls="reserved"
    else: cls="public"
  except Exception:
    cls="unknown"
  print(ip, cls, sep="\t")
PY
  fi | while IFS=$'\t' read -r ip cls; do
    [[ -n "$ip" ]] && ip_class["$ip"]="$cls"
  done

  # best-effort enrichment
  if (( enrich )); then
    local asn_db="" ctry_db=""
    local -a cand

    cand=(
      "${NETWATCH_ASN_MMDB:-}"
      "/usr/share/GeoIP/GeoLite2-ASN.mmdb"
      "/usr/local/share/GeoIP/GeoLite2-ASN.mmdb"
      "/var/lib/GeoIP/GeoLite2-ASN.mmdb"
    )
    local p
    for p in "${cand[@]}"; do
      [[ -n "$p" && -r "$p" ]] && { asn_db="$p"; break; }
    done

    cand=(
      "${NETWATCH_COUNTRY_MMDB:-}"
      "/usr/share/GeoIP/GeoLite2-Country.mmdb"
      "/usr/local/share/GeoIP/GeoLite2-Country.mmdb"
      "/var/lib/GeoIP/GeoLite2-Country.mmdb"
    )
    for p in "${cand[@]}"; do
      [[ -n "$p" && -r "$p" ]] && { ctry_db="$p"; break; }
    done

    while IFS= read -r ip; do
      [[ -z "$ip" ]] && continue
      [[ "${ip_class[$ip]-unknown}" != "public" ]] && continue

      local asn="" cc="" org=""

      if command -v mmdblookup >/dev/null 2>&1 && [[ -n "$asn_db$ctry_db" ]]; then
        if [[ -n "$asn_db" ]]; then
          asn="$(mmdblookup --file "$asn_db" --ip "$ip" autonomous_system_number 2>/dev/null \
            | awk '/uint/{print $2; exit}' | tr -d '[:space:]')"
          org="$(mmdblookup --file "$asn_db" --ip "$ip" autonomous_system_organization 2>/dev/null \
            | awk -F'"' '/"[^"]+"/{print $2; exit}')"
        fi
        if [[ -n "$ctry_db" ]]; then
          cc="$(mmdblookup --file "$ctry_db" --ip "$ip" country iso_code 2>/dev/null \
            | awk -F'"' '/"[^"]+"/{print $2; exit}')"
          [[ -z "$cc" ]] && cc="$(mmdblookup --file "$ctry_db" --ip "$ip" registered_country iso_code 2>/dev/null \
            | awk -F'"' '/"[^"]+"/{print $2; exit}')"
        fi
      fi

      if [[ -z "$asn$cc$org" && $cymru -eq 1 ]] && command -v whois >/dev/null 2>&1; then
        local line
        line="$(whois -h whois.cymru.com " -v $ip" 2>/dev/null | awk 'NR==2{print; exit}')"
        if [[ -n "$line" ]]; then
          asn="$(print -r -- "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}')"
          cc="$(print -r -- "$line"  | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')"
          org="$(print -r -- "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$7); print $7}')"
        fi
      fi

      [[ -n "$asn" ]] && ip_asn["$ip"]="$asn"
      [[ -n "$cc"  ]] && ip_cc["$ip"]="$cc"
      [[ -n "$org" ]] && ip_org["$ip"]="$org"
    done < "$ips"
  fi

  if (( rdns )) && command -v getent >/dev/null 2>&1; then
    while IFS= read -r ip; do
      [[ -z "$ip" ]] && continue
      [[ "${ip_class[$ip]-unknown}" != "public" ]] && continue
      local nm
      nm="$(getent hosts "$ip" 2>/dev/null | awk '{print $2; exit}')"
      [[ -n "$nm" ]] && ip_name["$ip"]="$nm"
    done < "$ips"
  fi

  local total public dns
  total="$(wc -l < "$tmp" 2>/dev/null | tr -d '[:space:]')"
  public="$(awk -F'\t' '{print $8}' "$tmp" | while read -r ip; do
    [[ "${ip_class[$ip]-unknown}" == "public" ]] && print -r -- 1
  done | wc -l | tr -d '[:space:]')"
  dns="$(awk -F'\t' '($9=="53" || $9=="853" || $9=="5353"){c++} END{print c+0}' "$tmp" 2>/dev/null)"

  print -r -- "netwatch: conns=$total public=$public dns=$dns (sudo shows more pids)"
  [[ $enrich -eq 1 ]] && print -r -- "netwatch: enrich=on cymru=$cymru rdns=$rdns"

  if (( top )); then
    print -r -- ""
    print -r -- "top processes by connection count"
    awk -F'\t' '{k=$5 "\t" $4; c[k]++} END{for (k in c) print c[k] "\t" k}' "$tmp" \
      | sort -nr | head -n 15 \
      | awk -F'\t' '{printf "%5s  %-22s pid=%s\n",$1,$2,$3}'
  else
    print -r -- ""
    printf "%-1s %-3s %-4s %-10s %-6s %-18s -> %-39s %-5s %-8s %-2s %-7s %s\n" \
      "!" "dir" "pr" "state" "pid" "proc" "remote" "port" "class" "cc" "asn" "org"

    awk -F'\t' -v ports="${ports_csv}" '
      function is_common(p,   a,i,n) {
        n=split(ports,a,",")
        for (i=1;i<=n;i++) if (a[i]==p) return 1
        return 0
      }
      { print }
    ' "$tmp" | while IFS=$'\t' read -r dir proto state pid proc lhost lport rhost rport timer; do
      local cls="${ip_class[$rhost]-unknown}"
      local cc="${ip_cc[$rhost]-"-"}"
      local asn="${ip_asn[$rhost]-"-"}"
      local org="${ip_org[$rhost]-"-"}"
      local nm="${ip_name[$rhost]-""}"

      local sev=""
      if [[ "$rport" == 53 || "$rport" == 853 || "$rport" == 5353 ]]; then
        sev="D"
      elif [[ "$cls" == "public" && "$state" == "ESTAB" ]]; then
        local common=0
        local p
        for p in "${common_ports[@]}"; do
          [[ "$p" == "$rport" ]] && { common=1; break; }
        done
        (( common == 0 )) && sev="!"
        [[ "$timer" == *keepalive* ]] && sev="!"
      fi

      local remote="$rhost"
      [[ -n "$nm" ]] && remote="$remote ($nm)"

      printf "%-1s %-3s %-4s %-10s %-6s %-18s -> %-39s %-5s %-8s %-2s %-7s %s\n" \
        "$sev" "$dir" "$proto" "$state" "$pid" "$proc" "$remote" "$rport" "$cls" "$cc" "$asn" "$org"
    done | sort -k1,1 -k2,2 -k6,6

    print -r -- ""
    print -r -- "dns sockets"
    awk -F'\t' '($9=="53" || $9=="853" || $9=="5353"){print}' "$tmp" \
      | awk -F'\t' '{printf "  %-4s %-10s pid=%-6s %-18s -> %s:%s\n",$2,$3,$4,$5,$8,$9}' \
      | head -n 25
  fi

  if (( dns_log )); then
    print -r -- ""
    print -r -- "dns log (systemd-resolved, last ${dns_log_mins}m, best-effort)"
    if command -v journalctl >/dev/null 2>&1; then
      local -a jc
      jc=( -u systemd-resolved --since "${dns_log_mins} minutes ago" --no-pager )
      journalctl "${jc[@]}" 2>/dev/null \
        | grep -Ei 'dns|query|transaction|reply|server' \
        | tail -n 40 \
        | sed 's/^/  /'
    else
      print -r -- "  journalctl not found"
    fi
  fi

  return 0
}

