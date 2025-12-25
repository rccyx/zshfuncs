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