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

connected-devices(){
  GATEWAY_IP=$(ip route | grep default | awk '{print $3}')
  echo "Scanning for connected devices on your network..."
  sudo arp-scan --localnet | grep -v "Interface:" | grep -v "Starting arp-scan" | grep -v "Ending arp-scan"
  CONNECTED_DEVICES=$(sudo arp-scan --localnet | grep -c "^\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}")
  echo "Total number of connected devices: $CONNECTED_DEVICES"
  GATEWAY_IP=$(ip route | grep default | awk '{print $3}')
  echo "Scanning for connected devices on your network..."
  sudo arp-scan --localnet | grep -v "Interface:" | grep -v "Starting arp-scan" | grep -v "Ending arp-scan"
  CONNECTED_DEVICES=$(sudo arp-scan --localnet | grep -c "^\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}")
  echo "Total number of connected devices: $CONNECTED_DEVICES"
}


netspeed() {
  if ! command -v speedtest &>/dev/null; then
    echo -e "\e[1;31mspeedtest-cli not found. Install it with:\e[0m pip install speedtest-cli"
    return 1
  fi

  echo -e "\e[1;34m⏳ Testing internet speed...\e[0m"
  local output=$(speedtest --secure --simple 2>/dev/null)

  if [[ $? -ne 0 ]]; then
    echo -e "\e[1;31m❌ Failed to test speed. Check connection.\e[0m"
    return 1
  fi

  local ping=$(echo "$output" | grep "Ping" | awk '{print $2 " " $3}')
  local download=$(echo "$output" | grep "Download" | awk '{print $2 " " $3}')
  local upload=$(echo "$output" | grep "Upload" | awk '{print $2 " " $3}')

  echo -e "\e[1;36m📡 Ping:\e[0m     $ping"
  echo -e "\e[1;36m⬇️  Download:\e[0m $download"
  echo -e "\e[1;36m⬆️  Upload:\e[0m   $upload"

  # Copy to clipboard if available
  if command -v xclip >/dev/null; then
    printf "Ping: %s\nDownload: %s\nUpload: %s\n" "$ping" "$download" "$upload" | xclip -selection clipboard
    echo -e "\e[1;32m📋 Copied to clipboard.\e[0m"
  fi
}


# autogenerate QR for current Wi-Fi network
wifiqr() {
  if ! command -v qrencode &>/dev/null; then
    echo -e "\e[1;31mqrencode not installed. Install with: sudo apt install qrencode\e[0m"
    return 1
  fi

  local ssid password

  ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
  if [[ -z "$ssid" ]]; then
    echo -e "\e[1;31mNot connected to any Wi-Fi.\e[0m"
    return 1
  fi

  password=$(sudo grep -r '^psk=' /etc/NetworkManager/system-connections/ 2>/dev/null \
              | grep "$ssid" | head -n1 | cut -d= -f2)

  if [[ -z "$password" ]]; then
    auth="nopass"
  else
    auth="WPA"
  fi

  local payload="WIFI:T:$auth;S:$ssid;P:$password;;"

  echo -e "\e[1;36m📶 Current SSID: \e[0m$ssid"
  echo -e "\e[1;34m🔳 Scan to connect:\e[0m"
  echo "$payload" | qrencode -t ANSIUTF8
}

compdef _wifi_ssids wifireconnect
