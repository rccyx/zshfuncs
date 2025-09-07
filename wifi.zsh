# -------------------------------------------------
# Wi-Fi utilities (robust SSID handling)
# -------------------------------------------------

wifi() {
  local interface ssid password entry wifi_list
  interface=$(nmcli device | awk '/wifi|wl/ {print $1; exit}')
  [[ -z "$interface" ]] && echo -e "\e[1;31m❌ No Wi-Fi interface found.\e[0m" && return 1

  echo -e "\e[1;34m📡 Scanning Wi-Fi networks...\e[0m"
  nmcli device wifi rescan >/dev/null 2>&1
  sleep 1

  # Use tab as a hard delimiter so SSIDs with spaces survive selection
  wifi_list=$(
    nmcli --terse --escape no -f SSID,SIGNAL,SECURITY device wifi list \
    | awk -F: 'length($1){printf "%s\t[%3s%%]\t%s\n",$1,$2,($3=="--"?"OPEN":"🔒 "$3)}'
  )
  [[ -z "$wifi_list" ]] && echo -e "\e[1;31m❌ No networks found.\e[0m" && return 1

  entry=$(printf "%s\n" "$wifi_list" \
    | fzf --prompt="📶 Select Wi-Fi ⇢ " --height=60% --border --reverse \
          --header="SSID\tSIGNAL  SECURITY" -d $'\t' --with-nth=1..3)
  [[ -z "$entry" ]] && echo -e "\e[1;31m❌ Cancelled.\e[0m" && return 1

  ssid=$(printf "%s" "$entry" | cut -f1)
  [[ -z "$ssid" ]] && echo -e "\e[1;31m❌ Failed to parse SSID.\e[0m" && return 1

  # If a saved connection with the exact name exists, bring it up
  if nmcli -g NAME connection show | grep -Fxq "$ssid"; then
    echo -e "\e[1;34m🔁 Connecting to saved network: \e[1;33m$ssid\e[0m"
    if nmcli connection up "$ssid"; then
      echo -e "\e[1;32m✅ Connected to $ssid\e[0m"; return 0
    fi
    echo -e "\e[1;31m❌ Failed to connect to $ssid.\e[0m"; return 1
  fi

  echo -ne "\e[1;33m🔑 Password for '$ssid' (blank to try open): \e[0m"
  read -sr password; echo

  if [[ -z "$password" ]]; then
    echo -e "\e[1;34m⏳ Trying open connect...\e[0m"
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
  list=$(
    nmcli --terse --escape no -f SSID,SIGNAL dev wifi list \
    | awk -F: 'length($1){printf "%s\t[%s%%]\n",$1,$2}' \
    | sort -t$'\t' -k2 -nr
  )
  if [[ -z $list ]]; then _err "no networks found" >&2; return 1; fi
  choice=$(printf "%s\n" "$list" | fzf --prompt="📶 SSID ➜ " --no-multi -d $'\t' --with-nth=1..2)
  if [[ -z $choice ]]; then _err "no ssid chosen" >&2; return 1; fi
  printf "%s" "$(echo "$choice" | cut -f1)"
}

wifikill(){ nmcli radio wifi off && _ok "wifi radio off"; }
wifiresume(){ nmcli radio wifi on  && _ok "wifi radio on";  }

wifireconnect(){
  local ssid; ssid="$(_sel_ssid)" || return 1
  _note "reconnecting to $ssid…"
  if nmcli connection up "$ssid" 2>/dev/null || nmcli device wifi connect "$ssid" 2>/dev/null; then
    _ok "connected to $ssid"
  else
    _err "failed to connect to $ssid"
  fi
}

wifipass(){
  local ssid pw
  ssid=$(nmcli --terse --escape no -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')
  [[ -z $ssid ]] && _err "not connected" && return 1

  # Ask NetworkManager for the stored PSK. May be empty for open networks or root-only secrets.
  pw=$(nmcli -s -g 802-11-wireless-security.psk connection show "$ssid" 2>/dev/null)

  if [[ -z $pw ]]; then
    _note "open network or key not stored"; return 0
  fi
  echo "SSID: $ssid  PW: $pw" | xclip -selection clipboard
  _ok "password copied to clipboard (also echoed below)"
  echo "$pw"
}

_wifi_ssids(){
  local -a ssids
  mapfile -t ssids < <(nmcli --terse --escape no -f SSID dev wifi | awk 'length($0)')
  _describe 'ssid' ssids
}

connected-devices(){
  echo "Scanning for connected devices on your network..."
  sudo arp-scan --localnet | grep -v "Interface:" | grep -v "Starting arp-scan" | grep -v "Ending arp-scan"
  local count
  count=$(sudo arp-scan --localnet | grep -cE '(^|[[:space:]])([0-9]{1,3}\.){3}[0-9]{1,3}([[:space:]]|$)')
  echo "Total number of connected devices: $count"
}

netspeed() {
  if ! command -v speedtest &>/dev/null; then
    echo -e "\e[1;31mspeedtest-cli not found. Install it with:\e[0m pip install speedtest-cli"
    return 1
  fi
  echo -e "\e[1;34m⏳ Testing internet speed...\e[0m"
  local output; output=$(speedtest --secure --simple 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo -e "\e[1;31m❌ Failed to test speed. Check connection.\e[0m"
    return 1
  fi
  local ping download upload
  ping=$(echo "$output" | grep "Ping" | awk '{print $2 " " $3}')
  download=$(echo "$output" | grep "Download" | awk '{print $2 " " $3}')
  upload=$(echo "$output" | grep "Upload" | awk '{print $2 " " $3}')
  echo -e "\e[1;36m📡 Ping:\e[0m     $ping"
  echo -e "\e[1;36m⬇️  Download:\e[0m $download"
  echo -e "\e[1;36m⬆️  Upload:\e[0m   $upload"
  if command -v xclip >/dev/null; then
    printf "Ping: %s\nDownload: %s\nUpload: %s\n" "$ping" "$download" "$upload" | xclip -selection clipboard
    echo -e "\e[1;32m📋 Copied to clipboard.\e[0m"
  fi
}

wifiqr() {
  if ! command -v qrencode &>/dev/null; then
    echo -e "\e[1;31mqrencode not installed. Install with: sudo apt install qrencode\e[0m"
    return 1
  fi
  local ssid password auth payload
  ssid=$(nmcli --terse --escape no -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')
  [[ -z "$ssid" ]] && echo -e "\e[1;31mNot connected to any Wi-Fi.\e[0m" && return 1

  password=$(nmcli -s -g 802-11-wireless-security.psk connection show "$ssid" 2>/dev/null)
  [[ -z "$password" ]] && auth="nopass" || auth="WPA"

  payload="WIFI:T:$auth;S:$ssid;P:$password;;"
  echo -e "\e[1;36m📶 Current SSID: \e[0m$ssid"
  echo -e "\e[1;34m🔳 Scan to connect:\e[0m"
  echo "$payload" | qrencode -t ANSIUTF8
}

# Forget a saved Wi-Fi profile by exact name or via selector if none given
wifi_forget(){
  local ssid
  if [[ -n "$1" ]]; then
    ssid="$1"
  else
    ssid="$(_sel_ssid)" || return 1
  fi
  if nmcli connection delete id "$ssid"; then
    _ok "forgot $ssid"
  else
    _err "no saved connection named $ssid"
  fi
}

# zsh completion hook
compdef _wifi_ssids wifireconnect

