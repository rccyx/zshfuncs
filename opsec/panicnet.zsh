

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


