# =================== PACKAGE-ONLY SYNC ===================
# backs up: APT sources+keys, APT pkg lists, dpkg selections,
# snaps, flatpaks, pip/pipx, npm/pnpm, cargo, rustup, nix, (brew if present),
# and GNOME KEYBINDINGS ONLY.
# writes: restore.sh => use to restore everything
# ========================================================

syncall() {
  local dotdir="$HOME/personal/projects/dotfiles"
  local backup_dir="$dotdir/other"
  mkdir -p "$backup_dir"

  _private_sync_apt         "$backup_dir"
  _private_sync_apt_sources "$backup_dir"
  _private_redact_sources   "$backup_dir"
  _private_sync_apt_keys    "$backup_dir"
  _private_sync_dpkg_sel    "$backup_dir"

  _private_sync_snap        "$backup_dir"
  _private_sync_flatpak     "$backup_dir"

  _private_sync_pip         "$backup_dir"
  _private_sync_pipx        "$backup_dir"
  _private_sync_npm         "$backup_dir"
  _private_sync_pnpm        "$backup_dir"

  _private_sync_cargo       "$backup_dir"
  _private_sync_rustup      "$backup_dir"
  _private_sync_nix         "$backup_dir"
  _private_sync_brew        "$backup_dir"

  _private_sync_gnome_keys  "$backup_dir"   # keybindings only

  _private_write_restore_min "$backup_dir"

  cd "$dotdir" || { _err "dotfiles repo not found"; return 1; }
  git add "$backup_dir"/* 2>/dev/null
  git commit -m "sync: pkgs+repos (safe) $(date -Iseconds)"
  git push && _ok "packages & repos synced"
}

# ---------- helpers (packages only) ----------

_private_sync_apt() {
  local out="$1/apt-installed.txt"
  if command -v apt-mark >/dev/null; then
    comm -23 \
      <(apt-mark showmanual | sort) \
      <(gzip -dc /var/log/installer/initial-status.gz 2>/dev/null | awk '/Package: / { print $2 }' | sort) \
      > "$out"
    _ok "APT manual packages saved"
  else
    _note "apt not found — skipped"
  fi
}

_private_sync_apt_sources() {
  local dir="$1/apt-sources"
  if [[ -d /etc/apt ]]; then
    mkdir -p "$dir"
    sudo cp -a /etc/apt/sources.list "$dir/" 2>/dev/null || :
    sudo cp -a /etc/apt/sources.list.d "$dir/" 2>/dev/null || :
    _ok "APT sources saved"
  else
    _note "no /etc/apt — skipped"
  fi
}

# redact any inline creds in apt source URLs (belt & suspenders)
_private_redact_sources(){
  local d="$1/apt-sources"
  [[ -d "$d" ]] || return 0
  grep -rl "@.*://" "$d" 2>/dev/null | while read -r f; do
    sed -i -E 's#(https?://)[^/]+@#\1<REDACTED>@#g' "$f"
  done
  _ok "APT sources redacted (if any creds existed)"
}

_private_sync_apt_keys() {
  local dir="$1/apt-keys"
  mkdir -p "$dir"
  if [[ -d /etc/apt/trusted.gpg.d ]]; then
    sudo cp -a /etc/apt/trusted.gpg.d "$dir/" 2>/dev/null || :
  fi
  if command -v apt-key >/dev/null; then
    sudo apt-key exportall > "$dir/apt-key-export.gpg" 2>/dev/null || :
  fi
  _ok "APT signing keys exported"
}

_private_sync_dpkg_sel() {
  local out="$1/dpkg-selections.txt"
  if command -v dpkg >/dev/null; then
    dpkg --get-selections > "$out"
    _ok "dpkg selections saved"
  else
    _note "dpkg not found — skipped"
  fi
}

_private_sync_snap() {
  local out="$1/snap-list.txt"
  if command -v snap >/dev/null; then
    snap list > "$out"
    _ok "snap list saved"
  else
    _note "snap not found — skipped"
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
    _ok "flatpak apps & remotes saved"
  else
    _note "flatpak not found — skipped"
  fi
}

_private_sync_pip() {
  local out="$1/pip3-freeze.txt"
  if command -v pip3 >/dev/null; then
    pip3 freeze > "$out" 2>/dev/null || :
    _ok "pip3 freeze saved"
  else
    _note "pip3 not found — skipped"
  fi
}

_private_sync_pipx() {
  local out="$1/pipx-list.json"
  if command -v pipx >/dev/null; then
    pipx list --json > "$out" 2>/dev/null || :
    _ok "pipx list saved"
  else
    _note "pipx not found — skipped"
  fi
}

_private_sync_npm() {
  local out="$1/npm-global.txt"
  if command -v npm >/dev/null; then
    npm ls -g --depth=0 --parseable 2>/dev/null | tail -n +2 | grep -v '^$' | xargs -n1 basename > "$out"
    _ok "NPM globals saved"
  else
    _note "npm not found — skipped"
  fi
}

_private_sync_pnpm() {
  local out="$1/pnpm-global.txt"
  if command -v pnpm >/dev/null; then
    pnpm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | grep -v '^$' | xargs -n1 basename > "$out"
    _ok "PNPM globals saved"
  else
    _note "pnpm not found — skipped"
  fi
}

_private_sync_cargo() {
  local out="$1/cargo-crates.txt"
  if command -v cargo >/dev/null; then
    cargo install --list | grep '^[a-zA-Z0-9_-]\+ v' | awk '{print $1}' > "$out"
    _ok "Cargo crates saved"
  else
    _note "cargo not found — skipped"
  fi
}

_private_sync_rustup() {
  local out="$1/rustup-toolchains.txt"
  if command -v rustup >/dev/null; then
    rustup toolchain list > "$out"
    _ok "rustup toolchains saved"
  else
    _note "rustup not found — skipped"
  fi
}

_private_sync_nix() {
  local out="$1/nix-profile.txt"
  if command -v nix >/dev/null; then
    nix profile list | awk -F':' '/^Name:/ {print $2}' | awk '{$1=$1};1' > "$out"
    _ok "Nix profile saved"
  else
    _note "nix not found — skipped"
  fi
}

_private_sync_brew() {
  local dir="$1/brew"
  if command -v brew >/dev/null; then
    mkdir -p "$dir"
    brew tap           > "$dir/taps.txt"    2>/dev/null || :
    brew leaves        > "$dir/leaves.txt"  2>/dev/null || :
    brew list --cask   > "$dir/casks.txt"   2>/dev/null || :
    _ok "Homebrew taps/leaves/casks saved"
  else
    _note "brew not found — skipped"
  fi
}

# GNOME: keybindings only (safe, portable)
_private_sync_gnome_keys() {
  local out="$1/keybindings.dconf"
  if command -v dconf >/dev/null; then
    dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$out"
    _ok "GNOME keybindings saved"
  else
    _note "dconf not found — skipped"
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

echo "==> Restoring APT sources (Debian/Ubuntu)…"
if [[ -d /etc/apt && -d "$BASEDIR/apt-sources" ]]; then
  sudo cp -a "$BASEDIR/apt-sources/sources.list" /etc/apt/ 2>/dev/null || true
  [[ -d "$BASEDIR/apt-sources/sources.list.d" ]] && sudo cp -a "$BASEDIR/apt-sources/sources.list.d" /etc/apt/ 2>/dev/null || true
  [[ -d "$BASEDIR/apt-keys/trusted.gpg.d"    ]] && sudo cp -a "$BASEDIR/apt-keys/trusted.gpg.d"    /etc/apt/ 2>/dev/null || true
  [[ -f "$BASEDIR/apt-keys/apt-key-export.gpg" ]] && sudo apt-key add "$BASEDIR/apt-keys/apt-key-export.gpg" 2>/dev/null || true
  sudo apt update || true
fi

echo "==> Installing APT manual packages…"
[[ -f "$BASEDIR/apt-installed.txt" ]] && xargs -a "$BASEDIR/apt-installed.txt" -r sudo apt install -y

echo "==> (Optional) Replaying dpkg selections…"
if [[ -f "$BASEDIR/dpkg-selections.txt" ]]; then
  sudo dpkg --set-selections < "$BASEDIR/dpkg-selections.txt" || true
  sudo apt-get dselect-upgrade -y || true
fi

echo "==> Restoring Snap…"
if command -v snap >/dev/null && [[ -f "$BASEDIR/snap-list.txt" ]]; then
  awk 'NR>1 {print $1}' "$BASEDIR/snap-list.txt" | while read -r s; do
    [[ -n "$s" ]] && sudo snap install "$s" || true
  done
fi

echo "==> Restoring Flatpak…"
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

echo "==> Restoring pip3…"
[[ -f "$BASEDIR/pip3-freeze.txt" ]] && command -v pip3 >/dev/null && pip3 install -U -r "$BASEDIR/pip3-freeze.txt" || true

echo "==> Restoring pipx…"
if command -v pipx >/dev/null && [[ -f "$BASEDIR/pipx-list.json" ]]; then
python3 - "$BASEDIR/pipx-list.json" <<'PY'
import json, subprocess, sys
j=json.load(open(sys.argv[1]))
for p in j.get("venvs",{}).keys():
    try: subprocess.run(["pipx","install",p],check=False)
    except: pass
PY
fi

echo "==> Restoring npm/pnpm globals…"
[[ -f "$BASEDIR/npm-global.txt"  ]] && command -v npm  >/dev/null && xargs -a "$BASEDIR/npm-global.txt"  -r npm  i -g || true
[[ -f "$BASEDIR/pnpm-global.txt" ]] && command -v pnpm >/dev/null && xargs -a "$BASEDIR/pnpm-global.txt" -r pnpm add -g || true

echo "==> Restoring Cargo & Rust toolchains…"
[[ -f "$BASEDIR/cargo-crates.txt"      ]] && command -v cargo  >/dev/null && xargs -a "$BASEDIR/cargo-crates.txt" -r -n1 cargo install || true
[[ -f "$BASEDIR/rustup-toolchains.txt" ]] && command -v rustup >/dev/null && awk '{print $1}' "$BASEDIR/rustup-toolchains.txt" | xargs -r -n1 rustup toolchain install || true

echo "==> Restoring Homebrew (if present)…"
if command -v brew >/dev/null && [[ -d "$BASEDIR/brew" ]]; then
  [[ -f "$BASEDIR/brew/taps.txt"   ]] && xargs -a "$BASEDIR/brew/taps.txt"   -r brew tap   || true
  [[ -f "$BASEDIR/brew/leaves.txt" ]] && xargs -a "$BASEDIR/brew/leaves.txt" -r brew install || true
  [[ -f "$BASEDIR/brew/casks.txt"  ]] && xargs -a "$BASEDIR/brew/casks.txt"  -r brew install --cask || true
fi

echo "==> GNOME keybindings (optional)…"
[[ -f "$BASEDIR/keybindings.dconf" ]] && command -v dconf >/dev/null && dconf load /org/gnome/settings-daemon/plugins/media-keys/ < "$BASEDIR/keybindings.dconf" || true

echo "==> Done."
RESTORE
  chmod +x "$file"
  _ok "restore script written → $file"
}
