

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


# ============================================
# verify - install-time sanity checker
# awareness, not enforcement
#
# usage:
#   verify <cmd|path> [more...]
#   verify --sig <file.pkg>     (force signature attempt)
#   verify --no-hash <target>
#   verify --hash sha256|sha1|blake2 <target>
#
# notes:
# - installed binaries rarely have direct signatures; package files often do
# - best-effort package ownership: dpkg, rpm, pacman, apk, nix, snap, flatpak
# ============================================
verify() {
  emulate -L zsh
  setopt pipefail no_unset

  local want_sig=0
  local want_hash=1
  local hash_alg="${VERIFY_HASH_ALG:-sha256}"

  while (( $# )); do
    case "$1" in
      --sig) want_sig=1; shift ;;
      --no-hash) want_hash=0; shift ;;
      --hash)
        [[ -n "${2-}" ]] || { print -ru2 -- "verify: --hash needs algo"; return 2; }
        hash_alg="$2"; shift 2 ;;
      -h|--help)
        cat <<'EOF'
verify <cmd|path> [more...]

shows:
- resolved path + all PATH hits
- file type, perms, owner, mtime, size
- hash (default sha256)
- best-effort package ownership
- signature verification when available (rpm/deb sidecars, etc)

flags:
  --sig           force signature attempt (also auto-attempts for known pkg files)
  --no-hash       skip hashing
  --hash <algo>   sha256 | sha1 | blake2
EOF
        return 0
        ;;
      --) shift; break ;;
      -*) print -ru2 -- "verify: unknown flag: $1"; return 2 ;;
      *) break ;;
    esac
  done

  (( $# > 0 )) || { print -ru2 -- "verify: missing target"; return 2; }

  local _p_ok="%F{2}ok%f"
  local _p_warn="%F{3}warn%f"
  local _p_bad="%F{1}bad%f"
  local _p_note="%F{6}::%f"

  _is_suspicious_path() {
    local p="$1"
    local home="${HOME:-}"
    [[ "$p" == /tmp/* ]] && return 0
    [[ "$p" == /var/tmp/* ]] && return 0
    [[ "$p" == /dev/shm/* ]] && return 0
    [[ "$p" == /run/user/* ]] && return 0
    [[ -n "$home" && "$p" == "$home"/.cache/* ]] && return 0
    [[ -n "$home" && "$p" == "$home"/Downloads/* ]] && return 0
    [[ -n "$home" && "$p" == "$home"/.local/share/Trash/* ]] && return 0
    return 1
  }

  _hash_file() {
    local alg="$1" p="$2"
    case "$alg" in
      sha256)
        if command -v sha256sum >/dev/null 2>&1; then sha256sum "$p" | awk '{print $1}'
        elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$p" | awk '{print $NF}'
        else return 1
        fi
        ;;
      sha1)
        if command -v sha1sum >/dev/null 2>&1; then sha1sum "$p" | awk '{print $1}'
        elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha1 "$p" | awk '{print $NF}'
        else return 1
        fi
        ;;
      blake2|b2|blake2b)
        if command -v b2sum >/dev/null 2>&1; then b2sum "$p" | awk '{print $1}'
        else return 1
        fi
        ;;
      *)
        return 1
        ;;
    esac
  }

  _fmt_size() {
    local bytes="$1"
    if command -v numfmt >/dev/null 2>&1; then
      numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || print -r -- "$bytes"
    else
      print -r -- "$bytes"
    fi
  }

  _owner_of_file() {
    local p="$1"
    # try multiple ecosystems; first win prints one line
    if [[ "$p" == /nix/store/* ]] && command -v nix-store >/dev/null 2>&1; then
      print -r -- "nix: $(nix-store -q --references "$p" 2>/dev/null | head -n 1)"
      return 0
    fi
    if command -v dpkg-query >/dev/null 2>&1; then
      local hit
      hit="$(dpkg-query -S "$p" 2>/dev/null | head -n 1)"
      [[ -n "$hit" ]] && { print -r -- "dpkg: $hit"; return 0; }
    fi
    if command -v rpm >/dev/null 2>&1; then
      local hit
      hit="$(rpm -qf "$p" 2>/dev/null | head -n 1)"
      [[ -n "$hit" ]] && { print -r -- "rpm: $hit"; return 0; }
    fi
    if command -v pacman >/dev/null 2>&1; then
      local hit
      hit="$(pacman -Qo "$p" 2>/dev/null | head -n 1)"
      [[ -n "$hit" ]] && { print -r -- "pacman: $hit"; return 0; }
    fi
    if command -v apk >/dev/null 2>&1; then
      local hit
      hit="$(apk info -W "$p" 2>/dev/null | head -n 1)"
      [[ -n "$hit" ]] && { print -r -- "apk: $hit"; return 0; }
    fi
    if [[ "$p" == /snap/* || "$p" == /var/lib/snapd/* ]]; then
      print -r -- "snap: path indicates snap"
      return 0
    fi
    if [[ "$p" == /var/lib/flatpak/* || "$p" == "$HOME"/.local/share/flatpak/* ]]; then
      print -r -- "flatpak: path indicates flatpak"
      return 0
    fi
    return 1
  }

  _sig_try_pkgfile() {
    local p="$1"
    local base sig asc

    # sidecar signatures (common in the wild)
    sig="${p}.sig"
    asc="${p}.asc"
    if command -v gpg >/dev/null 2>&1; then
      if [[ -f "$sig" ]]; then
        print -P "  $_p_note gpg verify: ${sig:t}"
        gpg --verify "$sig" "$p" 2>&1 | sed 's/^/    /'
        return 0
      fi
      if [[ -f "$asc" ]]; then
        print -P "  $_p_note gpg verify: ${asc:t}"
        gpg --verify "$asc" "$p" 2>&1 | sed 's/^/    /'
        return 0
      fi
    fi

    case "$p" in
      (*.rpm)
        if command -v rpm >/dev/null 2>&1; then
          print -P "  $_p_note rpm -K"
          rpm -K "$p" 2>&1 | sed 's/^/    /'
          return 0
        fi
        ;;
      (*.deb)
        if command -v debsig-verify >/dev/null 2>&1; then
          print -P "  $_p_note debsig-verify"
          debsig-verify "$p" 2>&1 | sed 's/^/    /'
          return 0
        fi
        if command -v dpkg-sig >/dev/null 2>&1; then
          print -P "  $_p_note dpkg-sig --verify"
          dpkg-sig --verify "$p" 2>&1 | sed 's/^/    /'
          return 0
        fi
        ;;
    esac

    return 1
  }

  local any_bad=0

  local t
  for t in "$@"; do
    local p="" resolved="" dir="" typ="" meta="" size_b="" size_h="" mode="" owner="" group="" mtime=""
    local -a hits
    hits=()

    print -r -- ""
    print -P "$_p_note verify $t"

    if [[ -e "$t" ]]; then
      p="$t"
    else
      p="$(command -v -- "$t" 2>/dev/null || true)"
      if [[ -z "$p" ]]; then
        print -P "  $_p_bad not found"
        any_bad=1
        continue
      fi
      # PATH hits (all)
      if command -v which >/dev/null 2>&1; then
        hits=("${(@f)$(which -a "$t" 2>/dev/null | awk 'NF{print}' | uniq)}")
      else
        hits=("$p")
      fi
    fi

    # resolve path
    if command -v realpath >/dev/null 2>&1; then
      resolved="$(realpath -e "$p" 2>/dev/null || true)"
    fi
    [[ -z "$resolved" ]] && resolved="$p"

    dir="${resolved:h}"

    print -r -- "  path: $resolved"
    if (( ${#hits[@]} > 1 )); then
      print -r -- "  path hits:"
      local h
      for h in "${hits[@]}"; do
        print -r -- "    $h"
      done
    fi

    if _is_suspicious_path "$resolved"; then
      print -P "  $_p_warn location smells like temp/cache/downloads"
      print -r -- "       if this is an install artifact, verify source before you run it"
    fi

    # basic metadata
    if command -v stat >/dev/null 2>&1; then
      size_b="$(stat -c '%s' "$resolved" 2>/dev/null || true)"
      mode="$(stat -c '%a' "$resolved" 2>/dev/null || true)"
      owner="$(stat -c '%U' "$resolved" 2>/dev/null || true)"
      group="$(stat -c '%G' "$resolved" 2>/dev/null || true)"
      mtime="$(stat -c '%y' "$resolved" 2>/dev/null | awk '{print $1" "$2}' || true)"
      [[ -n "$size_b" ]] && size_h="$(_fmt_size "$size_b")"
    fi

    if command -v file >/dev/null 2>&1; then
      typ="$(file -b "$resolved" 2>/dev/null || true)"
    fi

    [[ -n "$typ" ]] && print -r -- "  type: $typ"
    [[ -n "$size_h" ]] && print -r -- "  size: $size_h"
    [[ -n "$mode$owner$group" ]] && print -r -- "  perms: $mode  owner=$owner group=$group"
    [[ -n "$mtime" ]] && print -r -- "  mtime: $mtime"

    # writable binary checks (quietly high value)
    if [[ -n "$dir" ]]; then
      if [[ -w "$resolved" ]]; then
        print -P "  $_p_warn file is writable by current user"
      fi
      if [[ -w "$dir" ]]; then
        print -P "  $_p_warn parent dir is writable: $dir"
      fi
    fi

    # package ownership
    local own
    own="$(_owner_of_file "$resolved" 2>/dev/null || true)"
    if [[ -n "$own" ]]; then
      print -r -- "  origin: $own"
    else
      print -r -- "  origin: unknown (not owned by known pkg managers)"
    fi

    # hash
    if (( want_hash )); then
      local h
      h="$(_hash_file "$hash_alg" "$resolved" 2>/dev/null || true)"
      if [[ -n "$h" ]]; then
        print -r -- "  hash:$hash_alg $h"
      else
        print -P "  $_p_warn hash:$hash_alg unavailable (missing tool?)"
      fi
    fi

    # signatures
    local did_sig=0
    case "$resolved" in
      (*.rpm|*.deb|*.apk|*.pkg.tar*|*.AppImage|*.tar*|*.zip|*.gz|*.xz|*.zst)
        want_sig=1
        ;;
    esac

    if (( want_sig )); then
      if [[ -f "$resolved" ]]; then
        if _sig_try_pkgfile "$resolved"; then
          did_sig=1
        fi
      fi
      if (( did_sig == 0 )); then
        print -r -- "  signature: none detected / no verifier available"
      fi
    else
      print -r -- "  signature: skipped"
    fi
  done

  return "$any_bad"
}