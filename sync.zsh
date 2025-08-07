syncall() {
  local dotdir="$HOME/personal/projects/dotfiles"
  local backup_dir="$dotdir/other"
  mkdir -p "$backup_dir"

  _private_sync_apt "$backup_dir"
  _private_sync_pnpm "$backup_dir"
  _private_sync_npm "$backup_dir"
  _private_sync_cargo "$backup_dir"
  _private_sync_nix "$backup_dir"
  _private_sync_gnome_keys "$backup_dir"

  cd "$dotdir" || { _err "dotfiles repo not found"; return 1; }
  git add "$backup_dir"/*.txt "$backup_dir"/*.dconf
  git commit -m "sync: updated apt, pnpm, nix, cargo, gnome, etc."
  git push && _ok "all configs & packages synced"
}

# =================== PRIVATE HELPERS ===================

_private_sync_apt() {
  local backup="$1/apt-installed.txt"
  comm -23 \
    <(apt-mark showmanual | sort) \
    <(gzip -dc /var/log/installer/initial-status.gz | awk '/Package: / { print $2 }' | sort) \
    > "$backup"
  _ok "APT packages saved"
}

_private_sync_pnpm() {
  local backup="$1/pnpm-global.txt"
  if command -v pnpm &>/dev/null; then
    pnpm list -g --depth=0 --parseable 2>/dev/null \
      | tail -n +2 | grep -v '^$' \
      | xargs -n1 basename \
      > "$backup"
    _ok "PNPM packages saved"
  else
    _note "pnpm not found — skipped"
  fi
}

_private_sync_npm() {
  local backup="$1/npm-global.txt"
  if command -v npm &>/dev/null; then
    npm ls -g --depth=0 --parseable 2>/dev/null \
      | tail -n +2 | grep -v '^$' \
      | xargs -n1 basename \
      > "$backup"
    _ok "NPM packages saved"
  else
    _note "npm not found — skipped"
  fi
}

_private_sync_cargo() {
  local backup="$1/cargo-crates.txt"
  if command -v cargo &>/dev/null; then
    cargo install --list | grep '^[a-zA-Z0-9_-]\+ v' | awk '{print $1}' > "$backup"
    _ok "Cargo crates saved"
  else
    _note "cargo not found — skipped"
  fi
}

_private_sync_nix() {
  local backup="$1/nix-profile.txt"
  nix profile list | awk -F':' '/^Name:/ {print $2}' | awk '{$1=$1};1' > "$backup"
  _ok "Nix profile packages saved"
}

_private_sync_gnome_keys() {
  local backup="$1/keybindings.dconf"
  dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$backup"
  _ok "GNOME keybindings saved"
}

# =================== MESSAGE HELPERS ===================

_ok()   { print -P "%F{2}✅ $1%f" }
_err()  { print -P "%F{1}❌ $1%f" }
_note() { print -P "%F{4}ℹ️  $1%f" }
