# =================== PACKAGE-ONLY SYNC ===================
# Backs up: APT manual pkgs, dpkg selections,
# snaps, flatpaks, pip/pipx, npm/pnpm, cargo, rustup, go, nix,
# and GNOME keybindings only if GNOME is running.
# Also backs up APT repo config + keyrings.
# Writes: restore.sh inside $dotdir/packages
# ========================================================

# --- msg helpers (safe defaults) ---
_ok()   { print -P "%F{2}✅ $1%f"; }
_note() { print -P "%F{4}ℹ️  $1%f"; }
_err()  { print -P "%F{1}❌ $1%f"; }

# GNOME detection: only when GNOME is the current desktop or gnome-shell is running
_is_gnome_active() {
  [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] && return 0
  pgrep -x gnome-shell >/dev/null 2>&1 && return 0
  return 1
}

sync() {
  setopt local_options err_return pipe_fail

  # dotfiles root, override with DOTFILES_DIR if you want
  local dotdir="${DOTFILES_DIR:-$HOME/personal/projects/dotfiles}"

  # new target: everything lives under ./packages (not ./other)
  local backup_dir="$dotdir/packages"
  mkdir -p "$backup_dir"

  _private_sync_apt         "$backup_dir"
  _private_sync_dpkg_sel    "$backup_dir"

  _private_sync_snap        "$backup_dir"
  _private_sync_flatpak     "$backup_dir"

  _private_sync_pip         "$backup_dir"
  _private_sync_pipx        "$backup_dir"
  _private_sync_npm         "$backup_dir"
  _private_sync_pnpm        "$backup_dir"

  _private_sync_cargo       "$backup_dir"
  _private_sync_rustup      "$backup_dir"
  _private_sync_go          "$backup_dir"
  _private_sync_nix         "$backup_dir"

  # Only save GNOME keybindings if GNOME is active; otherwise ignore GNOME completely
  if _is_gnome_active; then
    _private_sync_gnome_keys "$backup_dir"
  else
    _note "GNOME not running, skipping GNOME keybindings"
  fi

  _private_write_restore_min "$backup_dir"

  # commit only if there are real changes
  cd "$dotdir" || { _err "dotfiles repo not found: $dotdir"; return 1; }
  git add -A "$backup_dir" 2>/dev/null || true
  if git diff --cached --quiet; then
    _note "no changes to commit"
  else
    git commit -m "sync: pkgs $(date -Iseconds)" || { _err "commit failed"; return 1; }
    git push && _ok "packages synced"
  fi
}

# ---------- helpers (packages only) ----------

_private_sync_apt() {
  local base="$1"
  local out="$base/apt-installed.txt"
  local etcdir="$base/apt-etc"

  if command -v apt-mark >/dev/null; then
    # manual packages
    comm -23 \
      <(apt-mark showmanual | sort) \
      <(gzip -dc /var/log/installer/initial-status.gz 2>/dev/null | awk '/Package: / { print $2 }' | sort) \
      > "$out"

    mkdir -p "$etcdir"

    # APT sources
    if [[ -f /etc/apt/sources.list ]]; then
      cp -a /etc/apt/sources.list "$etcdir/sources.list"
    fi

    if [[ -d /etc/apt/sources.list.d ]]; then
      mkdir -p "$etcdir/sources.list.d"
      cp -a /etc/apt/sources.list.d/* "$etcdir/sources.list.d/" 2>/dev/null || :
    fi

    # APT keyrings / trusted keys
    if [[ -d /etc/apt/trusted.gpg.d ]]; then
      mkdir -p "$etcdir/trusted.gpg.d"
      cp -a /etc/apt/trusted.gpg.d/* "$etcdir/trusted.gpg.d/" 2>/dev/null || :
    fi

    if [[ -d /etc/apt/keyrings ]]; then
      mkdir -p "$etcdir/keyrings"
      cp -a /etc/apt/keyrings/* "$etcdir/keyrings/" 2>/dev/null || :
    fi

    _ok "APT manual packages and repo config saved → $out, $etcdir"
  else
    _note "apt-mark not found, skipped APT snapshot"
  fi
}

_private_sync_dpkg_sel() {
  local out="$1/dpkg-selections.txt"
  if command -v dpkg >/dev/null; then
    dpkg --get-selections > "$out"
    _ok "dpkg selections saved → $out"
  else
    _note "dpkg not found, skipped"
  fi
}

_private_sync_snap() {
  local out="$1/snap-list.txt"
  if command -v snap >/dev/null; then
    snap list > "$out"
    _ok "snap list saved → $out"
  else
    _note "snap not found, skipped"
  fi
}

_private_sync_flatpak() {
  local out1="$1/flatpak-user.txt"
  local out2="$1/flatpak-system.txt"
  if command -v flatpak >/dev/null; then
    flatpak remotes --user   > "$1/flatpak-remotes-user.txt"   2>/dev/null || :
    flatpak remotes --system > "$1/flatpak-remotes-system.txt" 2>/dev/null || :
    flatpak list --user   --app --columns=application,origin > "$out1" 2>/dev/null || :
    flatpak list --system --app --columns=application,origin > "$out2" 2>/dev/null || :
    _ok "flatpak apps and remotes saved"
  else
    _note "flatpak not found, skipped"
  fi
}

_private_sync_pip() {
  local out="$1/pip3-freeze.txt"
  if command -v pip3 >/dev/null; then
    pip3 freeze > "$out" 2>/dev/null || :
    _ok "pip3 freeze saved → $out"
  else
    _note "pip3 not found, skipped"
  fi
}

_private_sync_pipx() {
  local out="$1/pipx-list.json"
  if command -v pipx >/dev/null; then
    pipx list --json > "$out" 2>/dev/null || :
    _ok "pipx list saved → $out"
  else
    _note "pipx not found, skipped"
  fi
}

_private_sync_npm() {
  local out="$1/npm-global.txt"
  if command -v npm >/dev/null; then
    npm ls -g --depth=0 --parseable 2>/dev/null | tail -n +2 | awk -F/ 'NF {print $NF}' > "$out"
    _ok "NPM globals saved → $out"
  else
    _note "npm not found, skipped"
  fi
}

_private_sync_pnpm() {
  local out="$1/pnpm-global.txt"
  if command -v pnpm >/dev/null; then
    pnpm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | awk -F/ 'NF {print $NF}' > "$out"
    _ok "PNPM globals saved → $out"
  else
    _note "pnpm not found, skipped"
  fi
}

_private_sync_cargo() {
  local out="$1/cargo-crates.txt"
  if command -v cargo >/dev/null; then
    cargo install --list | grep '^[a-zA-Z0-9._-]\+ v' | awk '{print $1}' > "$out"
    _ok "Cargo crates saved → $out"
  else
    _note "cargo not found, skipped"
  fi
}

_private_sync_rustup() {
  local out="$1/rustup-toolchains.txt"
  if command -v rustup >/dev/null; then
    rustup toolchain list > "$out"
    _ok "rustup toolchains saved → $out"
  else
    _note "rustup not found, skipped"
  fi
}

_private_sync_go() {
  local out="$1/go-tools.txt"
  if command -v go >/dev/null; then
    local gobin
    gobin="$(go env GOBIN 2>/dev/null)"
    [[ -z "$gobin" ]] && gobin="$(go env GOPATH 2>/dev/null)/bin"
    [[ -z "$gobin" ]] && gobin="$HOME/go/bin"

    if [[ -d "$gobin" ]]; then
      local tmp; tmp="$(mktemp)"
      # enumerate executables in GOBIN and try to extract module@version
      find "$gobin" -maxdepth 1 -type f -perm -u+x 2>/dev/null | while read -r bin; do
        local mod
        mod="$(go version -m "$bin" 2>/dev/null | awk '/^mod[[:space:]]/ {print $2"@"$3; exit}')"
        if [[ -n "$mod" ]]; then
          print -- "$mod"
        else
          print -- "# no module info: $(basename "$bin")"
        fi
      done | sort -u > "$tmp"
      mv "$tmp" "$out"
      _ok "Go tools detected from $(basename "$gobin") saved → $out"
    else
      : > "$out"
      _note "GOBIN not found, wrote empty go-tools.txt"
    fi

    go env GOPATH GOBIN GOOS GOARCH > "$1/go-env.txt" 2>/dev/null || :
  else
    _note "go not found, skipped"
  fi
}

_private_sync_nix() {
  local out="$1/nix-profile.txt"
  if command -v nix >/dev/null; then
    nix profile list | awk -F':' '/^Name:/ {print $2}' | awk '{$1=$1};1' > "$out"
    _ok "Nix profile saved → $out"
  else
    _note "nix not found, skipped"
  fi
}

# GNOME: keybindings only, and only if GNOME is active
_private_sync_gnome_keys() {
  local out="$1/keybindings.dconf"
  if command -v dconf >/dev/null; then
    dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$out" 2>/dev/null || :
    if [[ -s "$out" ]]; then
      _ok "GNOME keybindings saved → $out"
    else
      rm -f "$out"
      _note "No GNOME keybindings found, skipped"
    fi
  else
    _note "dconf not found, skipped"
  fi
}

# ---------- minimal restore writer ----------
_private_write_restore_min() {
  local dir="$1"
  local file="$dir/restore.sh"
  cat > "$file" <<'RESTORE'
#!/usr/bin/env bash
set -euo pipefail
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
APT_ETC="$BASEDIR/apt-etc"

echo "==> Restoring APT sources and keyrings"
if command -v apt >/dev/null && [[ -d "$APT_ETC" ]]; then
  if [[ -f "$APT_ETC/sources.list" ]]; then
    sudo cp -f "$APT_ETC/sources.list" /etc/apt/sources.list || true
  fi

  if [[ -d "$APT_ETC/sources.list.d" ]]; then
    sudo mkdir -p /etc/apt/sources.list.d
    sudo cp -f "$APT_ETC/sources.list.d"/* /etc/apt/sources.list.d/ 2>/dev/null || true
  fi

  if [[ -d "$APT_ETC/trusted.gpg.d" ]]; then
    sudo mkdir -p /etc/apt/trusted.gpg.d
    sudo cp -f "$APT_ETC/trusted.gpg.d"/* /etc/apt/trusted.gpg.d/ 2>/dev/null || true
  fi

  if [[ -d "$APT_ETC/keyrings" ]]; then
    sudo mkdir -p /etc/apt/keyrings
    sudo cp -f "$APT_ETC/keyrings"/* /etc/apt/keyrings/ 2>/dev/null || true
  fi

  sudo apt update || true
fi

echo "==> Installing APT manual packages"
if command -v apt >/dev/null && [[ -f "$BASEDIR/apt-installed.txt" ]]; then
  sudo apt update || true
  xargs -a "$BASEDIR/apt-installed.txt" -r sudo apt install -y || true
fi

echo "==> Replaying dpkg selections (optional)"
if command -v dpkg >/dev/null && [[ -f "$BASEDIR/dpkg-selections.txt" ]]; then
  sudo dpkg --set-selections < "$BASEDIR/dpkg-selections.txt" || true
  sudo apt-get dselect-upgrade -y || true
fi

echo "==> Restoring Snap"
if command -v snap >/dev/null && [[ -f "$BASEDIR/snap-list.txt" ]]; then
  awk 'NR>1 {print $1}' "$BASEDIR/snap-list.txt" | while read -r s; do
    [[ -n "$s" ]] && sudo snap install "$s" || true
  done
fi

echo "==> Restoring Flatpak"
if command -v flatpak >/dev/null; then
  [[ -f "$BASEDIR/flatpak-remotes-system.txt" ]] && awk 'NR>1{print $1,$2}' "$BASEDIR/flatpak-remotes-system.txt" | while read -r name url; do
    flatpak remote-add --if-not-exists "$name" "$url" --system || true
  done
  [[ -f "$BASEDIR/flatpak-remotes-user.txt" ]] && awk 'NR>1{print $1,$2}' "$BASEDIR/flatpak-remotes-user.txt" | while read -r name url; do
    flatpak remote-add --if-not-exists "$name" "$url" --user || true
  done
  [[ -f "$BASEDIR/flatpak-system.txt" ]] && awk '{print $1}' "$BASEDIR/flatpak-system.txt" | xargs -r -n1 flatpak install -y --system || true
  [[ -f "$BASEDIR/flatpak-user.txt"   ]] && awk '{print $1}' "$BASEDIR/flatpak-user.txt"   | xargs -r -n1 flatpak install -y --user   || true
fi

echo "==> Restoring pip3"
[[ -f "$BASEDIR/pip3-freeze.txt" ]] && command -v pip3 >/dev/null && pip3 install -U -r "$BASEDIR/pip3-freeze.txt" || true

echo "==> Restoring pipx"
if command -v pipx >/dev/null && [[ -f "$BASEDIR/pipx-list.json" ]]; then
python3 - "$BASEDIR/pipx-list.json" <<'PY'
import json, subprocess, sys
j=json.load(open(sys.argv[1]))
for p in j.get("venvs",{}).keys():
    try: subprocess.run(["pipx","install",p],check=False)
    except Exception:
        pass
PY
fi

echo "==> Restoring npm and pnpm globals"
[[ -f "$BASEDIR/npm-global.txt"  ]] && command -v npm  >/dev/null && xargs -a "$BASEDIR/npm-global.txt"  -r npm  i -g || true
[[ -f "$BASEDIR/pnpm-global.txt" ]] && command -v pnpm >/dev/null && xargs -a "$BASEDIR/pnpm-global.txt" -r pnpm add -g || true

echo "==> Restoring Cargo and rustup"
[[ -f "$BASEDIR/cargo-crates.txt"      ]] && command -v cargo  >/dev/null && xargs -a "$BASEDIR/cargo-crates.txt" -r -n1 cargo install || true
[[ -f "$BASEDIR/rustup-toolchains.txt" ]] && command -v rustup >/dev/null && awk '{print $1}' "$BASEDIR/rustup-toolchains.txt" | xargs -r -n1 rustup toolchain install || true

echo "==> Restoring Go tools"
if command -v go >/dev/null && [[ -f "$BASEDIR/go-tools.txt" ]]; then
  awk '!/^($|#)/{print $0}' "$BASEDIR/go-tools.txt" | xargs -r -n1 go install || true
fi

echo "==> GNOME keybindings (optional)"
[[ -f "$BASEDIR/keybindings.dconf" ]] && command -v dconf >/dev/null && dconf load /org/gnome/settings-daemon/plugins/media-keys/ < "$BASEDIR/keybindings.dconf" || true

echo "==> Done"
RESTORE
  chmod +x "$file"
  _ok "restore script written → $file"
}

