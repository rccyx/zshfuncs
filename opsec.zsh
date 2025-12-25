

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



# ============================================
# panicnet - immediate outbound containment
# blocks all outbound traffic except SSH
#
# usage:
#   sudo panicnet on
#   sudo panicnet off
#   sudo panicnet status
#   panicnet help
#
# env:
#   PANICNET_SSH_PORT=22
#   PANICNET_MODE=egress|lockdown
#
# notes:
#   egress: only touches OUTPUT (outbound). keeps inbound unchanged.
#   lockdown: also restricts INPUT except SSH + established/related.
# ============================================
panicnet() {
  emulate -L zsh
  setopt pipefail err_return no_unset

  local action="${1:-help}"
  local ssh_port="${PANICNET_SSH_PORT:-22}"
  local mode="${PANICNET_MODE:-egress}"

  _pn_err(){ print -ru2 -- "panicnet: $*"; }
  _pn_ok(){ print -r -- "panicnet: $*"; }

  _pn_help() {
    cat <<EOF
panicnet: containment switch (outbound)

What it does
  Blocks all outbound traffic except SSH (tcp/$ssh_port).
  Uses nftables if present, otherwise iptables.
  Does not flush your existing firewall, it inserts a top-priority hook/chain.

Usage
  sudo panicnet on
  sudo panicnet off
  sudo panicnet status

Common variants
  sudo PANICNET_SSH_PORT=2222 panicnet on
  sudo PANICNET_MODE=lockdown panicnet on

Modes
  PANICNET_MODE=egress    only block outbound (default)
  PANICNET_MODE=lockdown  also restrict inbound except SSH + established/related

Quick recovery
  If you locked yourself out locally, run:
    sudo panicnet off

EOF
  }

  _has_nft() { command -v nft >/dev/null 2>&1; }
  _has_ipt() { command -v iptables >/dev/null 2>&1; }

  if [[ "$action" == "help" || "$action" == "-h" || "$action" == "--help" ]]; then
    _pn_help
    return 0
  fi

  if [[ "$EUID" -ne 0 ]]; then
    _pn_err "needs root. run: sudo panicnet $action"
    _pn_ok  "help: run 'panicnet help' for usage"
    return 1
  fi

  # -------------------------
  # nftables backend
  # -------------------------
  _nft_installed() {
    nft list table inet panicnet >/dev/null 2>&1
  }

  _nft_status() {
    if _nft_installed; then
      _pn_ok "status: on (nft) ssh_port=$ssh_port mode=$mode"
      _pn_ok "disable: sudo panicnet off"
      nft list table inet panicnet 2>/dev/null | sed 's/^/  /'
      return 0
    fi
    return 1
  }

  _nft_on() {
    if _nft_installed; then
      _pn_ok "already on (nft)"
      _pn_ok "disable: sudo panicnet off"
      return 0
    fi

    # priority -100 so it runs before most existing rules
    nft -f - >/dev/null 2>&1 <<EOF
add table inet panicnet
add chain inet panicnet output { type filter hook output priority -100; policy accept; }
add rule  inet panicnet output oif "lo" accept
add rule  inet panicnet output ct state established,related tcp sport $ssh_port accept
add rule  inet panicnet output tcp dport $ssh_port accept
add rule  inet panicnet output drop
EOF

    if [[ "$mode" == "lockdown" ]]; then
      nft -f - >/dev/null 2>&1 <<EOF
add chain inet panicnet input { type filter hook input priority -100; policy accept; }
add rule  inet panicnet input iif "lo" accept
add rule  inet panicnet input ct state established,related accept
add rule  inet panicnet input tcp dport $ssh_port accept
add rule  inet panicnet input drop
EOF
    fi

    _pn_ok "enabled (nft) outbound blocked except tcp/$ssh_port (mode=$mode)"
    _pn_ok "status: sudo panicnet status"
    _pn_ok "disable: sudo panicnet off"
    _pn_ok "help: panicnet help"
  }

  _nft_off() {
    if ! _nft_installed; then
      _pn_ok "already off (nft)"
      _pn_ok "enable: sudo panicnet on"
      return 0
    fi
    nft delete table inet panicnet >/dev/null 2>&1 || {
      _pn_err "failed to delete nft table inet panicnet"
      _pn_ok  "try: nft list tables | grep -n panicnet"
      return 1
    }
    _pn_ok "disabled (nft) restored normal egress"
    _pn_ok "enable: sudo panicnet on"
    _pn_ok "help: panicnet help"
  }

  # -------------------------
  # iptables backend
  # -------------------------
  _ipt_chain_exists() {
    iptables -S PANICNET_OUT >/dev/null 2>&1
  }

  _ipt_jump_installed() {
    iptables -C OUTPUT -j PANICNET_OUT >/dev/null 2>&1
  }

  _ipt_status() {
    if _ipt_chain_exists && _ipt_jump_installed; then
      _pn_ok "status: on (iptables) ssh_port=$ssh_port mode=$mode"
      _pn_ok "disable: sudo panicnet off"
      iptables -S PANICNET_OUT 2>/dev/null | sed 's/^/  /'
      if iptables -S PANICNET_IN >/dev/null 2>&1; then
        iptables -S PANICNET_IN 2>/dev/null | sed 's/^/  /' || true
      fi
      return 0
    fi
    return 1
  }

  _ipt_on() {
    if _ipt_chain_exists && _ipt_jump_installed; then
      _pn_ok "already on (iptables)"
      _pn_ok "disable: sudo panicnet off"
      return 0
    fi

    _ipt_chain_exists || iptables -N PANICNET_OUT >/dev/null 2>&1
    iptables -F PANICNET_OUT >/dev/null 2>&1 || true

    iptables -A PANICNET_OUT -o lo -j ACCEPT
    iptables -A PANICNET_OUT -p tcp --dport "$ssh_port" -j ACCEPT
    iptables -A PANICNET_OUT -p tcp --sport "$ssh_port" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A PANICNET_OUT -j DROP

    _ipt_jump_installed || iptables -I OUTPUT 1 -j PANICNET_OUT

    if [[ "$mode" == "lockdown" ]]; then
      iptables -N PANICNET_IN >/dev/null 2>&1 || true
      iptables -F PANICNET_IN >/dev/null 2>&1 || true
      iptables -A PANICNET_IN -i lo -j ACCEPT
      iptables -A PANICNET_IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A PANICNET_IN -p tcp --dport "$ssh_port" -j ACCEPT
      iptables -A PANICNET_IN -j DROP
      iptables -C INPUT -j PANICNET_IN >/dev/null 2>&1 || iptables -I INPUT 1 -j PANICNET_IN
    fi

    _pn_ok "enabled (iptables) outbound blocked except tcp/$ssh_port (mode=$mode)"
    _pn_ok "status: sudo panicnet status"
    _pn_ok "disable: sudo panicnet off"
    _pn_ok "help: panicnet help"
  }

  _ipt_off() {
    if _ipt_jump_installed; then
      while iptables -D OUTPUT -j PANICNET_OUT >/dev/null 2>&1; do :; done
    fi
    if iptables -C INPUT -j PANICNET_IN >/dev/null 2>&1; then
      while iptables -D INPUT -j PANICNET_IN >/dev/null 2>&1; do :; done
    fi

    iptables -F PANICNET_OUT >/dev/null 2>&1 || true
    iptables -X PANICNET_OUT >/dev/null 2>&1 || true

    iptables -F PANICNET_IN >/dev/null 2>&1 || true
    iptables -X PANICNET_IN >/dev/null 2>&1 || true

    _pn_ok "disabled (iptables) restored normal egress"
    _pn_ok "enable: sudo panicnet on"
    _pn_ok "help: panicnet help"
  }

  # -------------------------
  # dispatch
  # -------------------------
  case "$action" in
    on)
      if _has_nft; then _nft_on; return $?; fi
      if _has_ipt; then _ipt_on; return $?; fi
      _pn_err "no nft or iptables found"
      return 1
      ;;
    off)
      if _has_nft && _nft_installed; then _nft_off; return $?; fi
      if _has_ipt && (_ipt_chain_exists || _ipt_jump_installed); then _ipt_off; return $?; fi
      _pn_ok "already off"
      _pn_ok "enable: sudo panicnet on"
      _pn_ok "help: panicnet help"
      return 0
      ;;
    status)
      if _has_nft && _nft_status; then return 0; fi
      if _has_ipt && _ipt_status; then return 0; fi
      _pn_ok "status: off"
      _pn_ok "enable: sudo panicnet on"
      _pn_ok "help: panicnet help"
      return 0
      ;;
    *)
      _pn_err "unknown action: $action"
      _pn_ok  "try: sudo panicnet on | off | status"
      _pn_ok  "help: panicnet help"
      return 2
      ;;
  esac
}




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
# screenpeek - "who can see my screen / hear my mic right now?"
#
# surfaces:
# - wayland/x11 display socket fds
# - pipewire screen capture streams
# - pipewire audio capture streams (mic or monitor)
#
# deps:
# - display sockets: lsof (preferred) or /proc fallback
# - pipewire: pw-dump + python3 (preferred) or jq fallback
#
# tips:
# - run with sudo for full visibility across users:
#   sudo screenpeek
# ============================================
screenpeek() {
  emulate -L zsh
  setopt pipefail no_unset null_glob
  unsetopt xtrace verbose

  local raw=0
  while (( $# )); do
    case "$1" in
      --raw) raw=1; shift ;;
      -h|--help)
        cat <<'EOF'
screenpeek [--raw]

shows:
- processes with open fds to wayland/x11 display sockets
- pipewire screen capture streams (best-effort)
- pipewire audio capture streams (mic or monitor)

notes:
- without sudo, you generally only see your own processes
- on wayland, actual screen capture usually shows up under pipewire (portal)
EOF
        return 0
        ;;
      *)
        print -ru2 -- "screenpeek: unknown arg: $1"
        return 2
        ;;
    esac
  done

  _sp_have() { command -v "$1" >/dev/null 2>&1; }

  _sp_proc_user() {
    local pid="$1"
    ps -o user= -p "$pid" 2>/dev/null | awk '{print $1}' || print -r -- "?"
  }
  _sp_proc_comm() {
    local pid="$1"
    ps -o comm= -p "$pid" 2>/dev/null | awk '{print $1}' || print -r -- "?"
  }
  _sp_proc_exe() {
    local pid="$1" exe=""
    exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
    [[ -n "$exe" ]] && print -r -- "$exe" || print -r -- "-"
  }

  # returns TSV: pid user comm
  _sp_sock_users_tsv() {
    emulate -L zsh
    setopt pipefail no_unset null_glob

    local sock="$1"
    [[ -S "$sock" ]] || return 0

    if _sp_have lsof; then
      # lsof shows more with sudo; without it, expect partial
      lsof -nP -w -U -- "$sock" 2>/dev/null \
        | awk 'NR>1{print $2"\t"$3"\t"$1}' \
        | LC_ALL=C sort -u
      return 0
    fi

    local ino
    ino="$(stat -Lc '%i' -- "$sock" 2>/dev/null || true)"
    [[ -z "$ino" ]] && return 0

    local fd link pid
    for fd in /proc/[0-9]*/fd/*(N); do
      link="$(readlink "$fd" 2>/dev/null || true)"
      [[ "$link" == "socket:[$ino]" ]] || continue
      pid="${fd:h:t}"
      [[ -n "$pid" ]] && print -r -- "$pid"
    done | LC_ALL=C sort -u | while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      print -r -- "${pid}\t$(_sp_proc_user "$pid")\t$(_sp_proc_comm "$pid")"
    done
  }

  _sp_print_sock_section() {
    emulate -L zsh
    setopt pipefail no_unset

    local label="$1"; shift
    local -a socks
    socks=("$@")

    (( ${#socks[@]} > 0 )) || return 0

    print -r -- ""
    print -r -- "== ${label} =="
    local s
    for s in "${socks[@]}"; do
      [[ -S "$s" ]] || continue
      print -r -- "socket: $s"

      local tsv
      tsv="$(_sp_sock_users_tsv "$s" || true)"

      if [[ -z "$tsv" ]]; then
        print -r -- "  (none visible; try sudo)"
        continue
      fi

      if (( raw )); then
        print -r -- "$tsv" | sed 's/^/  /'
      else
        print -r -- "$tsv" | while IFS=$'\t' read -r pid user comm; do
          [[ -z "$pid" ]] && continue
          print -r -- "  pid=${pid} user=${user} proc=${comm} exe=$(_sp_proc_exe "$pid")"
        done
      fi
    done
  }

  _sp_pw_capture_tsv() {
    emulate -L zsh
    setopt pipefail no_unset

    _sp_have pw-dump || { print -ru2 -- "screenpeek: missing dep: pw-dump (pipewire-bin)"; return 127; }

    if _sp_have python3; then
      pw-dump 2>/dev/null | python3 - <<'PY'
import sys, json, re

try:
  data = json.load(sys.stdin)
except Exception:
  sys.exit(0)

clients = {}
nodes = {}

def gprops(obj):
  return (obj.get("info") or {}).get("props") or {}

def gstate(obj):
  return (obj.get("info") or {}).get("state")

for o in data:
  t = o.get("type","")
  if ":Interface:Client" in t:
    clients[o.get("id")] = gprops(o)
  elif ":Interface:Node" in t:
    nodes[o.get("id")] = {"props": gprops(o), "state": gstate(o)}

def first_present(d, keys):
  for k in keys:
    v = d.get(k)
    if v is None:
      continue
    if isinstance(v, str) and v.strip()=="":
      continue
    return v
  return None

def pid_from_client_props(p):
  v = first_present(p, ["application.process.id", "pipewire.sec.pid"])
  try:
    return int(str(v))
  except Exception:
    return None

def norm_state(s):
  if not s:
    return "-"
  return str(s)

def is_live(props, state):
  v = props.get("stream.is-live")
  if isinstance(v, bool):
    return v
  if isinstance(v, (int,float)):
    return bool(v)
  if isinstance(v, str):
    if v.lower() in ("true","1","yes","on"):
      return True
  return str(state).lower() == "running"

def text(*xs):
  return " ".join([x for x in xs if isinstance(x,str)])

def looks_like_screen(props, target_props):
  role = props.get("media.role") or (target_props or {}).get("media.role")
  if isinstance(role,str) and role.lower() == "screen":
    return True
  hay = text(
    props.get("node.name",""),
    props.get("node.description",""),
    props.get("media.name",""),
    (target_props or {}).get("node.name",""),
    (target_props or {}).get("node.description",""),
    (target_props or {}).get("media.name",""),
  ).lower()
  if re.search(r"\b(screen|screencast|desktop|portal|xdg-desktop-portal|xdpw)\b", hay):
    return True
  return False

def classify_audio_target(target_props):
  if not target_props:
    return "audio"
  mc = (target_props.get("media.class") or "").lower()
  desc = (target_props.get("node.description") or target_props.get("node.name") or "").lower()
  if "audio/source" in mc:
    if "monitor" in desc:
      return "audio-monitor"
    return "mic"
  return "audio"

out = []
for nid, n in nodes.items():
  props = n["props"]
  state = n["state"]
  mc = props.get("media.class") or ""
  if not isinstance(mc,str):
    continue
  mc_l = mc.lower()

  if mc_l not in ("stream/input/audio", "stream/input/video"):
    continue

  # ignore dead-ish streams when we have any signal; keep paused/running/live
  if not is_live(props, state) and str(state).lower() not in ("paused","running","idle"):
    continue

  cid = props.get("client.id")
  cprops = clients.get(cid, {})
  pid = pid_from_client_props(cprops)

  app = first_present(cprops, ["application.name", "application.process.binary"]) or "-"
  binp = first_present(cprops, ["application.process.binary"]) or "-"
  portal_app = first_present(cprops, ["pipewire.access.portal.app_id"]) or "-"
  flatpak = first_present(cprops, ["pipewire.sec.flatpak"]) or "-"

  target_id = props.get("node.target")
  target_props = None
  if isinstance(target_id, int) and target_id in nodes:
    target_props = nodes[target_id]["props"]

  role = props.get("media.role") or (target_props or {}).get("media.role") or "-"
  node_name = props.get("node.name") or "-"
  node_desc = props.get("node.description") or "-"

  if mc_l == "stream/input/video":
    kind = "screen" if looks_like_screen(props, target_props) else "video"
  else:
    kind = classify_audio_target(target_props)

  out.append((kind, pid if pid is not None else "-", app, binp, portal_app, flatpak, nid, norm_state(state), node_name, role, node_desc))

for row in out:
  # kind pid app bin portal_app flatpak node_id state node_name role node_desc
  print("\t".join(map(lambda x: str(x), row)))
PY
      return 0
    fi

    if _sp_have jq; then
      # fallback: lower fidelity (no link/target logic), still useful
      # kind pid app bin portal_app flatpak node_id state node_name role node_desc
      pw-dump 2>/dev/null | jq -r '
        def cprops: .info?.props? // {};
        def nprops: .info?.props? // {};
        (map(select(.type|test("Interface:Client")))|map({id:.id, p:cprops})|from_entries(.[]|{key:(.id|tostring), value:.p})) as $C
        | map(select(.type|test("Interface:Node")))
        | .[]
        | (nprops) as $p
        | ($p["media.class"] // "") as $mc
        | select($mc=="Stream/Input/Audio" or $mc=="Stream/Input/Video")
        | ($p["client.id"]|tostring) as $cid
        | ($C[$cid]["application.process.id"] // $C[$cid]["pipewire.sec.pid"] // "-") as $pid
        | ($C[$cid]["application.name"] // $C[$cid]["application.process.binary"] // "-") as $app
        | ($C[$cid]["application.process.binary"] // "-") as $bin
        | ($C[$cid]["pipewire.access.portal.app_id"] // "-") as $portal
        | ($C[$cid]["pipewire.sec.flatpak"] // "-") as $flatpak
        | ($p["media.role"] // "-") as $role
        | ($p["node.name"] // "-") as $nn
        | ($p["node.description"] // "-") as $nd
        | ($p["media.class"]=="Stream/Input/Video"
            ? (($role=="Screen") ? "screen" : "video")
            : "audio") as $kind
        | "\($kind)\t\($pid)\t\($app)\t\($bin)\t\($portal)\t\($flatpak)\t\(.id)\t\(.info.state // "-")\t\($nn)\t\($role)\t\($nd)"
      ' 2>/dev/null
      return 0
    fi

    print -ru2 -- "screenpeek: pipewire parsing needs python3 (preferred) or jq"
    return 127
  }

  _sp_print_pw_section() {
    emulate -L zsh
    setopt pipefail no_unset

    _sp_have pw-dump || return 0

    local tsv
    tsv="$(_sp_pw_capture_tsv 2>/dev/null || true)"
    [[ -z "$tsv" ]] && return 0

    local n_screen n_video n_mic n_audio n_mon
    n_screen="$(print -r -- "$tsv" | awk -F'\t' '$1=="screen"{c++} END{print c+0}')"
    n_video="$(print -r -- "$tsv" | awk -F'\t' '$1=="video"{c++} END{print c+0}')"
    n_mic="$(print -r -- "$tsv" | awk -F'\t' '$1=="mic"{c++} END{print c+0}')"
    n_mon="$(print -r -- "$tsv" | awk -F'\t' '$1=="audio-monitor"{c++} END{print c+0}')"
    n_audio="$(print -r -- "$tsv" | awk -F'\t' '$1=="audio"{c++} END{print c+0}')"

    print -r -- ""
    print -r -- "== pipewire capture streams =="
    print -r -- "screen=${n_screen} mic=${n_mic} audio_monitor=${n_mon} audio_unknown=${n_audio} other_video=${n_video}"

    local kind_label
    for kind_label in screen mic audio-monitor audio video; do
      local block
      block="$(print -r -- "$tsv" | awk -F'\t' -v k="$kind_label" '$1==k{print}')"
      [[ -z "$block" ]] && continue

      print -r -- ""
      print -r -- "-- ${kind_label} --"
      if (( raw )); then
        print -r -- "$block" | sed 's/^/  /'
      else
        print -r -- "$block" | while IFS=$'\t' read -r kind pid app bin portal flatpak node_id state node_name role node_desc; do
          local extra=""
          [[ "$portal" != "-" ]] && extra=" portal_app_id=${portal}"
          [[ "$flatpak" != "-" ]] && extra="${extra} flatpak=${flatpak}"
          print -r -- "  pid=${pid} app=${app} bin=${bin} state=${state} role=${role} node=${node_id} name=${node_name}${extra}"
        done
      fi
    done
  }

  local xdg="${XDG_RUNTIME_DIR:-/run/user/$UID}"
  local wdisp="${WAYLAND_DISPLAY:-wayland-0}"

  local -a wl_socks x_socks
  wl_socks=()
  if [[ -d "$xdg" ]]; then
    [[ -S "$xdg/$wdisp" ]] && wl_socks+=("$xdg/$wdisp")
    local s
    for s in "$xdg"/wayland-*; do
      [[ -S "$s" ]] && wl_socks+=("$s")
    done
  fi
  wl_socks=("${(@u)wl_socks}")

  x_socks=()
  local xs
  for xs in /tmp/.X11-unix/X*(N); do
    [[ -S "$xs" ]] && x_socks+=("$xs")
  done
  x_socks=("${(@u)x_socks}")

  local wl_count x_count
  wl_count="${#wl_socks[@]}"
  x_count="${#x_socks[@]}"

  print -r -- "screenpeek: wayland_sockets=${wl_count} x11_sockets=${x_count} (try sudo for full visibility)"

  _sp_print_sock_section "display socket access (wayland)" "${wl_socks[@]}"
  _sp_print_sock_section "display socket access (x11)" "${x_socks[@]}"

  _sp_print_pw_section

  return 0
}


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
    local p="$1" home="${HOME:-}"
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
      *) return 1 ;;
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
    if [[ "$p" == /nix/store/* ]] && command -v nix-store >/dev/null 2>&1; then
      print -r -- "nix: $(nix-store -q --references "$p" 2>/dev/null | head -n 1)"
      return 0
    fi
    if command -v dpkg-query >/dev/null 2>&1; then
      local hit; hit="$(dpkg-query -S "$p" 2>/dev/null | head -n 1)"
      [[ -n "$hit" ]] && { print -r -- "dpkg: $hit"; return 0; }
    fi
    if command -v rpm >/dev/null 2>&1; then
      local hit; hit="$(rpm -qf "$p" 2>/dev/null | head -n 1)"
      [[ -n "$hit" ]] && { print -r -- "rpm: $hit"; return 0; }
    fi
    if command -v pacman >/dev/null 2>&1; then
      local hit; hit="$(pacman -Qo "$p" 2>/dev/null | head -n 1)"
      [[ -n "$hit" ]] && { print -r -- "pacman: $hit"; return 0; }
    fi
    if command -v apk >/dev/null 2>&1; then
      local hit; hit="$(apk info -W "$p" 2>/dev/null | head -n 1)"
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
    local p="$1" sig asc
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
    local p="" resolved="" dir="" typ="" size_b="" size_h="" mode="" owner="" group="" mtime=""
    local -a hits; hits=()

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
      if command -v which >/dev/null 2>&1; then
        hits=("${(@f)$(which -a "$t" 2>/dev/null | awk 'NF{print}' | uniq)}")
      else
        hits=("$p")
      fi
    fi

    if command -v realpath >/dev/null 2>&1; then
      resolved="$(realpath -e "$p" 2>/dev/null || true)"
    fi
    [[ -z "$resolved" ]] && resolved="$p"
    dir="${resolved:h}"

    print -r -- "  path: $resolved"
    if (( ${#hits[@]} > 1 )); then
      print -r -- "  path hits:"
      local h
      for h in "${hits[@]}"; do print -r -- "    $h"; done
    fi

    if _is_suspicious_path "$resolved"; then
      print -P "  $_p_warn location smells like temp/cache/downloads"
    fi

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

    if [[ -n "$dir" ]]; then
      [[ -w "$resolved" ]] && print -P "  $_p_warn file is writable by current user"
      [[ -w "$dir" ]] && print -P "  $_p_warn parent dir is writable: $dir"
    fi

    local own
    own="$(_owner_of_file "$resolved" 2>/dev/null || true)"
    if [[ -n "$own" ]]; then
      print -r -- "  origin: $own"
    else
      print -r -- "  origin: unknown (not owned by known pkg managers)"
    fi

    if (( want_hash )); then
      local hh
      hh="$(_hash_file "$hash_alg" "$resolved" 2>/dev/null || true)"
      [[ -n "$hh" ]] && print -r -- "  hash:$hash_alg $hh" || print -P "  $_p_warn hash:$hash_alg unavailable"
    else
      print -r -- "  hash: skipped"
    fi

    local did_sig=0
    case "$resolved" in
      (*.rpm|*.deb|*.apk|*.pkg.tar*|*.AppImage|*.tar*|*.zip|*.gz|*.xz|*.zst) want_sig=1 ;;
    esac

    if (( want_sig )); then
      if [[ -f "$resolved" ]] && _sig_try_pkgfile "$resolved"; then
        did_sig=1
      fi
      (( did_sig == 0 )) && print -r -- "  signature: none detected / no verifier available"
    else
      print -r -- "  signature: skipped"
    fi
  done

  return "$any_bad"
}


anomaly() {
  emulate -L zsh
  setopt pipefail no_unset null_glob
  unsetopt xtrace verbose

  local top_n="${ANOMALY_TOP:-25}"
  local raw=0

  while (( $# )); do
    case "$1" in
      --top)
        [[ -n "${2-}" ]] || { print -ru2 -- "anomaly: --top needs N"; return 2; }
        top_n="$2"; shift 2 ;;
      --raw) raw=1; shift ;;
      -h|--help)
        cat <<'EOF'
anomaly [--top N] [--raw]

scans live processes for suspicious runtime patterns:
- execution from /tmp, /dev/shm, /run/user, cache dirs, Downloads
- deleted executables and memfd execution
- odd parent relationships (best-effort context)
- high cpu/mem outliers (context, not verdict)

notes:
- run with sudo for best visibility across users
- outputs ranked findings with explicit reasons, no remediation
EOF
        return 0
        ;;
      *) print -ru2 -- "anomaly: unknown arg: $1"; return 2 ;;
    esac
  done

  _a_have() { command -v "$1" >/dev/null 2>&1; }

  _a_susp_path() {
    local p="$1" home="${HOME:-}"
    [[ "$p" == /tmp/* ]] && return 0
    [[ "$p" == /var/tmp/* ]] && return 0
    [[ "$p" == /dev/shm/* ]] && return 0
    [[ "$p" == /run/user/* ]] && return 0
    [[ "$p" == /memfd:* ]] && return 0
    [[ -n "$home" && "$p" == "$home"/.cache/* ]] && return 0
    [[ -n "$home" && "$p" == "$home"/Downloads/* ]] && return 0
    [[ -n "$home" && "$p" == "$home"/.local/share/Trash/* ]] && return 0
    return 1
  }

  _a_pp_comm() {
    local ppid="$1"
    ps -o comm= -p "$ppid" 2>/dev/null | awk '{print $1}' || print -r -- "?"
  }

  local tmp
  tmp="$(mktemp -t anomaly.XXXXXX 2>/dev/null || print -r -- "/tmp/anomaly.$$")"

  ps -eo pid=,ppid=,user=,comm=,pcpu=,pmem=,etimes=,args= 2>/dev/null > "$tmp.ps" || {
    print -ru2 -- "anomaly: ps failed"
    rm -f "$tmp.ps" "$tmp" 2>/dev/null || true
    return 2
  }

  local line
  local -a out
  out=()

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local pid ppid user comm pcpu pmem et args
    pid="${line%% *}"
    local rest="${line#* }"
    rest="${rest## }"
    ppid="${rest%% *}"; rest="${rest#* }"; rest="${rest## }"
    user="${rest%% *}"; rest="${rest#* }"; rest="${rest## }"
    comm="${rest%% *}"; rest="${rest#* }"; rest="${rest## }"
    pcpu="${rest%% *}"; rest="${rest#* }"; rest="${rest## }"
    pmem="${rest%% *}"; rest="${rest#* }"; rest="${rest## }"
    et="${rest%% *}"; rest="${rest#* }"; rest="${rest## }"
    args="$rest"

    [[ -n "$pid" ]] || continue
    [[ "$pid" == "PID" ]] && continue

    local exelink exepath deleted=0 memfd=0
    exelink="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
    if [[ -n "$exelink" ]]; then
      [[ "$exelink" == *"(deleted)"* ]] && deleted=1
      [[ "$exelink" == /memfd:* ]] && memfd=1
      exepath="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
      [[ -z "$exepath" ]] && exepath="$exelink"
    else
      exepath="-"
    fi

    local score=0
    local reasons=""

    if (( deleted )); then
      score=$(( score + 90 ))
      reasons="${reasons} deleted_exe"
    fi
    if (( memfd )); then
      score=$(( score + 90 ))
      reasons="${reasons} memfd_exec"
    fi
    if [[ "$exepath" != "-" ]] && _a_susp_path "$exepath"; then
      score=$(( score + 60 ))
      reasons="${reasons} exec_from_temp_cache"
    fi

    local pcpu_i pmem_i
    pcpu_i="$(print -r -- "$pcpu" | awk '{printf("%d",$1+0)}' 2>/dev/null || echo 0)"
    pmem_i="$(print -r -- "$pmem" | awk '{printf("%d",$1+0)}' 2>/dev/null || echo 0)"

    if (( pcpu_i >= 60 )); then
      score=$(( score + 25 ))
      reasons="${reasons} cpu_high"
    elif (( pcpu_i >= 30 )); then
      score=$(( score + 10 ))
      reasons="${reasons} cpu_med"
    fi

    if (( pmem_i >= 20 )); then
      score=$(( score + 20 ))
      reasons="${reasons} mem_high"
    elif (( pmem_i >= 10 )); then
      score=$(( score + 8 ))
      reasons="${reasons} mem_med"
    fi

    local ppcomm
    ppcomm="$(_a_pp_comm "$ppid")"
    if [[ "$ppid" == "1" && "$user" != "root" ]]; then
      score=$(( score + 8 ))
      reasons="${reasons} ppid_1"
    fi

    reasons="${reasons# }"
    (( score > 0 )) || continue

    if (( raw )); then
      out+=("${score}\t${pid}\t${user}\t${pcpu}\t${pmem}\t${et}\t${comm}\t${ppid}\t${ppcomm}\t${exepath}\t${reasons}\t${args}")
    else
      out+=("${score}\t${pid}\t${user}\t${pcpu}\t${pmem}\t${et}\t${comm}\t${ppid}\t${ppcomm}\t${exepath}\t${reasons}")
    fi
  done < "$tmp.ps"

  rm -f "$tmp.ps" 2>/dev/null || true

  if (( ${#out[@]} == 0 )); then
    print -r -- "anomaly: no strong signals (try sudo for full visibility)"
    rm -f "$tmp" 2>/dev/null || true
    return 0
  fi

  print -r -- "anomaly: ranked signals (no verdicts) top=${top_n} (try sudo for full visibility)"
  print -r -- ""

  if (( raw )); then
    printf "%-5s %-6s %-10s %-5s %-5s %-7s %-16s %-6s %-12s %-44s %-22s %s\n" \
      "score" "pid" "user" "cpu" "mem" "etimes" "proc" "ppid" "pproc" "exe" "reasons" "args"
    print -r -- "${(F)out}" \
      | sort -t $'\t' -nr -k1,1 \
      | head -n "$top_n" \
      | while IFS=$'\t' read -r score pid user cpu mem et proc ppid pproc exe reasons args; do
          printf "%-5s %-6s %-10s %-5s %-5s %-7s %-16s %-6s %-12s %-44s %-22s %s\n" \
            "$score" "$pid" "$user" "$cpu" "$mem" "$et" "$proc" "$ppid" "$pproc" "${exe:0:44}" "${reasons:0:22}" "$args"
        done
  else
    printf "%-5s %-6s %-10s %-5s %-5s %-7s %-16s %-6s %-12s %-44s %s\n" \
      "score" "pid" "user" "cpu" "mem" "etimes" "proc" "ppid" "pproc" "exe" "reasons"
    print -r -- "${(F)out}" \
      | sort -t $'\t' -nr -k1,1 \
      | head -n "$top_n" \
      | while IFS=$'\t' read -r score pid user cpu mem et proc ppid pproc exe reasons; do
          printf "%-5s %-6s %-10s %-5s %-5s %-7s %-16s %-6s %-12s %-44s %s\n" \
            "$score" "$pid" "$user" "$cpu" "$mem" "$et" "$proc" "$ppid" "$pproc" "${exe:0:44}" "$reasons"
        done
  fi

  rm -f "$tmp" 2>/dev/null || true
  return 0
}
