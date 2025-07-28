# -------------------------------------------------
# Wi-Fi utilities
# -------------------------------------------------

wifi() {
  local interface ssid password selected entry
  interface=$(nmcli device | awk '/wifi|wl/ {print $1; exit}')
  if [[ -z "$interface" ]]; then
    echo -e "\e[1;31m❌ No Wi-Fi interface found.\e[0m"
    return 1
  fi

  echo -e "\e[1;34m📡 Scanning Wi-Fi networks...\e[0m"
  nmcli device wifi rescan >/dev/null 2>&1
  sleep 1

  local wifi_list=$(nmcli -t -f SSID,BSSID,SIGNAL,SECURITY device wifi list | awk -F: '
    !seen[$1]++ && length($1) > 0 {
      printf "%-35s  [%3s%%]  %s\n", $1, $3, ($4 == "--" ? "OPEN" : "🔒 " $4)
    }')

  if [[ -z "$wifi_list" ]]; then
    echo -e "\e[1;31m❌ No networks found.\e[0m"
    return 1
  fi

  entry=$(echo "$wifi_list" | fzf --prompt="📶 Select Wi-Fi ⇢ " --height=60% --border --reverse \
    --header="SSID                SIGNAL  SECURITY" \
    --preview-window=up:3:wrap)

  [[ -z "$entry" ]] && echo -e "\e[1;31m❌ Cancelled.\e[0m" && return 1

  ssid=$(echo "$entry" | awk '{print $1}')
  [[ -z "$ssid" ]] && echo -e "\e[1;31m❌ Failed to parse SSID.\e[0m" && return 1

  if nmcli connection show | grep -q "^$ssid "; then
    echo -e "\e[1;34m🔁 Connecting to saved network: \e[1;33m$ssid\e[0m"
    nmcli connection up "$ssid" && echo -e "\e[1;32m✅ Connected to $ssid\e[0m" && return 0
    echo -e "\e[1;31m❌ Failed to connect to $ssid.\e[0m"
    return 1
  fi

  echo -ne "\e[1;33m🔑 Password for '$ssid' (leave blank to try open connect): \e[0m"
  read -sr password
  echo

  if [[ -z "$password" ]]; then
    echo -e "\e[1;34m⏳ Trying to connect without password...\e[0m"
    nmcli device wifi connect "$ssid"
  else
    echo -e "\e[1;34m🔗 Connecting to '$ssid'...\e[0m"
    nmcli device wifi connect "$ssid" password "$password"
  fi

  if [[ $? -eq 0 ]]; then
    echo -e "\e[1;32m✅ Connected to '$ssid'\e[0m"
  else
    echo -e "\e[1;31m❌ Failed to connect to '$ssid'.\e[0m"
  fi
}

# ---- minimal Wi-Fi toolkit ----

iface(){ nmcli device | awk '/wifi|wl/ {print $1; exit}'; }
_sel_ssid(){
  local list choice
  list=$(nmcli -t -f SSID,SIGNAL dev wifi list | awk -F: 'length($1){printf "%-40s [%s%%]\n",$1,$2}' | sort -k2 -nr)
  [[ -z $list ]] && _err "no networks found" && return 1
  choice=$(printf "%s\n" "$list" | fzf --prompt="📶 SSID ➜ " --no-multi)
  [[ -z $choice ]] && _err "no ssid chosen" && return 1
  printf "%s" "${choice%% *}"
}

wifikill(){ nmcli radio wifi off && _ok "wifi radio off"; }
wifiresume(){ nmcli radio wifi on  && _ok "wifi radio on";  }

wifireconnect(){
  local ssid=$(_sel_ssid) || return 1
  _note "reconnecting to $ssid…"
  if nmcli connection up "$ssid" 2>/dev/null || nmcli device wifi connect "$ssid" 2>/dev/null; then
    _ok "connected to $ssid"
  else
    _err "failed to connect to $ssid"
  fi
}

wifipass(){
  local ssid pw
  ssid=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')
  [[ -z $ssid ]] && _err "not connected" && return 1
  pw=$(sudo grep -r "^psk=" /etc/NetworkManager/system-connections/ 2>/dev/null | grep "\/$ssid" | head -n1 | cut -d= -f2)
  if [[ -z $pw ]]; then
    _note "open network or key not stored"; return 0
  fi
  echo "SSID: $ssid  PW: $pw" | xclip -selection clipboard
  _ok "password copied to clipboard (also echoed below)"
  echo "$pw"
}

_wifi_ssids(){
  local -a ssids; ssids=( $(nmcli -t -f SSID dev wifi | sort -u) )
  _describe 'ssid' ssids
}
compdef _wifi_ssids wifireconnect 