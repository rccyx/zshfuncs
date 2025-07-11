
# ================================================================
#    ZSH FUNCTION COLLECTION
# ================================================================
precmd() {
    # Print the previously configured title
    print -Pnr -- "$TERM_TITLE"

    # Print a new line before the prompt, but only if it is not the first line
    if [ "$NEWLINE_BEFORE_PROMPT" = yes ]; then
        if [ -z "$_NEW_LINE_BEFORE_PROMPT" ]; then
            _NEW_LINE_BEFORE_PROMPT=1
        else
            print ""
        fi
    fi
}
# Needs SSH
# generate new SSH keys for github, run this u'll get the pub key copied to ur clipboard,just paste it
ghkey() {
 bash <(curl -L https://raw.githubusercontent.com/AshGw/dotfiles/main/.ssh/_gh_gen.sh )
}

# Needs docker
# terminate all running containers
tercon() {
	for c in $(docker ps -a | tail -n+2 | awk '{print $1}'); do
  		docker stop "${c}" || :
  		docker rm "${c}"
	done
}

# remove all volumes
tervol() {
   docker volume rm $(docker volume ls -q)
}

# remove all images
terimg() {
   for img in $(docker images -q); do
        docker rmi "${img}" || :
    done
}

dprune() {
	 tercon && terimg && tervol
   docker container prune -f
   docker system prune -f
   docker image prune -f
   docker volume prune -f
}

# shows pretty `man` page.
man () {
  env \
    LESS_TERMCAP_mb=$(printf "\e[1;31m") \
    LESS_TERMCAP_md=$(printf "\e[1;31m") \
    LESS_TERMCAP_me=$(printf "\e[0m") \
    LESS_TERMCAP_se=$(printf "\e[0m") \
    LESS_TERMCAP_so=$(printf "\e[1;44;33m") \
    LESS_TERMCAP_ue=$(printf "\e[0m") \
    LESS_TERMCAP_us=$(printf "\e[1;32m") \
      man "$@"
}

# create a new directory & cd into it
mdd () {
 mkdir -p "$@" && cd "$@"
}

# This needs my GPG key
# encrypt a file with a passphrase
passenc() {
    local input_file=$1
    local output_file="${input_file}.gpg"
    if gpg --symmetric --cipher-algo AES256 --quiet --batch --yes --output "$output_file" "$input_file"; then
        shred -u "$input_file"
        echo -e "\e[1;32mEncrypted $input_file and saved as: $output_file\e[0m"
    else
        echo -e "\e[1;31mEncryption failed for $input_file\e[0m"
    fi
}

passdec() {
    local input_file=$1
    local output_file="${input_file%.gpg}"

    if gpg --use-agent --quiet --batch --yes --decrypt --cipher-algo AES256 --output "$output_file" "$input_file" 2>/dev/null; then
        shred -u "$input_file"
        echo -e "\e[1;32mDecrypted $input_file and saved as: $output_file\e[0m"
    else
        echo -e "\e[1;31mDecryption failed for $input_file\e[0m"
    fi
}

# copies the content of a file to the clipboard
cpf() {
    if [[ -n $1 && -f $1 ]]; then
        xclip -selection clipboard < $1
        echo -e "\e[1;32mContents of '$1' copied to clipboard.\e[0m"
    else
        echo "Usage: cpf <filename>"
    fi
}
# Needs xclip
# short for copy command, copies the output of the command to the clipboard
ccmd() {
  eval "$@" | xclip -selection clipboard
}

# When the gpg dameon fucking up in TTY, you gotta lock in
loadpg() {
   pkill -9 gpg-agent
   export GPG_TTY=$(tty)
}

## g for git, double l is for last, since I already have gl as git log.
# anyways, this basically shows the diff of the last commit
gll() {
	 git show $(git log -1 --format=%H)
}

# gll & s for status, but typing s requires additional effort, so I made it c, like the git diff --stat
gllc(){
  git diff HEAD~1 HEAD --stat
}

# Kill all TMUX sessions
txkill(){
  tmux list-sessions -F '#S' | xargs -I {} tmux kill-session -t {}
}

# auto syncs my current gnome keybindings
synckeys() {
  local backup_dir="$HOME/personal/projects/dotfiles/other"
  mkdir -p "$backup_dir"
  dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$backup_dir/keybindings.dconf"
  cd "$HOME/personal/projects/dotfiles" && git add "$backup_dir/keybindings.dconf" && git commit -m "update GNOME keybindings" && git push
}

#### Get the total number of connected devices, needs `arp-scan`

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


#### Sometimes I really do need to gen a pass on the spot (all 32 chars)

# hex only
genpass_easy() {
    openssl rand -hex 16
}

# smoking mid
genpass_mid() {
    openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32
}

genpass_hard() {
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+[]{}<>?,.:;' | head -c 32
}

# USE WITH CAUTION: DELETES ALL THE GIT BRANCHES EXCEPT FOR THE ONE YOU'RE ON RN
dlb() {
 git branch | grep -v "$(git rev-parse --abbrev-ref HEAD)" | xargs git branch -D
}

# Function to display disk space in a human-readable sentence with green output
diskspace() {
  local df_output=$(df -h $HOME | tail -n 1)
  local total=$(echo $df_output | awk '{print $2}')
  local used=$(echo $df_output | awk '{print $3}')
  local avail=$(echo $df_output | awk '{print $4}')
  local sentence="Your total disk space is $total, with $used used and $avail available."
  echo -e "\033[32m$sentence\033[0m"
}

# ================================================================
#   WHISPER FUNCTION: Talk and get transcript in clipboard
# ================================================================
whisperclip() {
  local AUDIO_PATH="/tmp/record.wav"
  local MODEL_PATH="$HOME/whisper/whisper.cpp/models/ggml-medium.en.bin"
  local WHISPER_BIN="$HOME/whisper/whisper.cpp/build/bin/whisper-cli"
  echo -e "\e[1;34m🎙️  Recording... Press Ctrl+C when done.\e[0m"
  arecord -f cd -t wav -r 16000 -c 1 "$AUDIO_PATH" || return
  echo -e "\e[1;34m🧠 Transcribing with Whisper...\e[0m"
  "$WHISPER_BIN" -m "$MODEL_PATH" -f "$AUDIO_PATH" -otxt || return
  echo -e "\e[1;32m📋 Copied to clipboard:\e[0m"
  cat "${AUDIO_PATH}.txt" | tee >(xclip -selection clipboard)
}

# Show SSH public keys quick
mykeys() {
  cat ~/.ssh/*.pub
}

cleanup_node_modules() {
  find . -name "node_modules" -type d -prune -exec rm -rf '{}' +
  echo "All node_modules folders nuked tf out."
}

# Get public DNS and geo info, can be wrong if mfs subnet into oblivion
whereami() {
  curl ipinfo.io
}

 remindme() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: remindme <seconds> <message>"
    return 1
  fi
  (sleep "$1" && echo "Reminder: $2") &
}

# Copies all files in current directory to clipboard as a tar archive, paste them later
clipdir() {
  if [ "$1" = "copy" ]; then
    tar -cf - * 2>/dev/null | xclip -selection clipboard -i
    echo -e "\e[1;32mDirectory contents copied to clipboard.\e[0m"
  elif [ "$1" = "paste" ]; then
    xclip -selection clipboard -o | tar -xvf - 2>/dev/null
    echo -e "\e[1;32mDirectory contents pasted to $(pwd).\e[0m"
  else
    echo -e "\e[1;31mUsage: clipdir {copy|paste}\e[0m"
  fi
}

# Delete files and directories in current directory starting with a given string or matching a regex
rmw() {
  if [ -z "$1" ]; then
    echo -e "\e[1;31mUsage: rmw <pattern>\e[0m"
    return 1
  fi
  local pattern="$1"
  if echo "test" | grep -E "$pattern" >/dev/null 2>&1; then
    find . -maxdepth 1 -regex "./$pattern.*" -exec ls -ld {} \;
    echo -e "\e[1;33mAbove items will be deleted. Confirm? (y/n)\e[0m"
    read -r confirm
    if [ "$confirm" = "y" ]; then
      find . -maxdepth 1 -regex "./$pattern.*" -exec rm -rf {} \;
      echo -e "\e[1;32mDeleted items matching '$pattern'.\e[0m"
    else
      echo -e "\e[1;31mDeletion cancelled.\e[0m"
    fi
  else
    find . -maxdepth 1 -name "$pattern*" -exec ls -ld {} \;
    echo -e "\e[1;33mAbove items will be deleted. Confirm? (y/n)\e[0m"
    read -r confirm
    if [ "$confirm" = "y" ]; then
      find . -maxdepth 1 -name "$pattern*" -exec rm -rf {} \;
      echo -e "\e[1;32mDeleted items starting with '$pattern'.\e[0m"
    else
      echo -e "\e[1;31mDeletion cancelled.\e[0m"
    fi
  fi
}



#   WIFI FUNCTION: Connect to Wi-Fi from terminal w/ clean UX (autocomplete etc..), just pulling the wifi icon from the tool bar is a pain in the ass, might as well do it from the terminal

wifi() {
  local interface=$(nmcli device | awk '/wifi|wl/ {print $1; exit}')
  if [[ -z "$interface" ]]; then
    echo -e "\e[1;31mNo Wi-Fi interface found.\e[0m"
    return 1
  fi

  echo -e "\n\e[1;34m📡 Scanning Wi-Fi networks...\e[0m"
  nmcli device wifi rescan > /dev/null 2>&1
  sleep 1

  local networks=$(nmcli -t -f SSID,SIGNAL device wifi list | awk -F: '!seen[$1]++ && length($1)>0 {printf "%-40s [%s%%]\n", $1, $2}')
  if [[ -z "$networks" ]]; then
    echo -e "\e[1;31mNo networks found.\e[0m"
    return 1
  fi

  echo -e "\n\e[1;36mAvailable Networks:\e[0m"
  echo "$networks"

  echo -ne "\n\e[1;33m🔍 Enter SSID (or partial match): \e[0m"
  read -r query

  local matched_ssid=$(echo "$networks" | grep -i "$query" | head -n 1 | awk '{print $1}')
  if [[ -z "$matched_ssid" ]]; then
    echo -e "\e[1;31mNo match found for '$query'.\e[0m"
    return 1
  fi

  echo -ne "\e[1;33m🔑 Password for '$matched_ssid' (leave blank for saved): \e[0m"
  read -sr password
  echo ""

  if [[ -z "$password" ]]; then
    echo -e "\e[1;34m⏳ Attempting to connect to saved network '$matched_ssid'...\e[0m"
    nmcli device wifi connect "$matched_ssid"
  else
    echo -e "\e[1;34m🔗 Connecting to '$matched_ssid' with password...\e[0m"
    nmcli device wifi connect "$matched_ssid" password "$password"
  fi

  if [[ $? -eq 0 ]]; then
    echo -e "\e[1;32m✅ Connected to '$matched_ssid'\e[0m"
  else
    echo -e "\e[1;31m❌ Failed to connect.\e[0m"
  fi
}

# Copies the last n lines of terminal history to clipboard
cop() {
  local n=${1:-100}  # default to 100 lines if not specified
  local max_lines=5000  # safety cap to avoid massive mem dumps

  if (( n > max_lines )); then
    echo -e "\e[1;33mWarning: Clipping to $max_lines lines max.\e[0m"
    n=$max_lines
  fi

  if [ -n "$TMUX" ]; then
    # Inside tmux, use capture-pane
    tmux capture-pane -pS -$n | xclip -selection clipboard
    echo -e "\e[1;32m📋 Last $n lines copied from tmux pane.\e[0m"
  elif command -v script >/dev/null 2>&1; then
    # Not in tmux, fallback to script hack
    local tmpfile=$(mktemp)
    script -q -c "tail -n $n ~/.zsh_history" "$tmpfile"
    tail -n $n "$tmpfile" | xclip -selection clipboard
    rm -f "$tmpfile"
    echo -e "\e[1;32m📋 Last $n history lines copied (approx).\e[0m"
  else
    echo -e "\e[1;31m❌ Not in tmux and 'script' not found. Can't fetch terminal buffer.\e[0m"
  fi
}

bth() {
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    echo -e "\e[1;31m❌ bluetoothctl not found. Install it.\e[0m"
    return 1
  fi

  local action="$1"

  if [[ "$action" == "disconnect" ]]; then
    echo -e "\e[1;35m🔌 Disconnecting all connected Bluetooth devices...\e[0m"
    bluetoothctl info | grep -B1 "Connected: yes" | grep Device | awk '{print $2}' | while read -r connected_mac; do
      bluetoothctl disconnect "$connected_mac" >/dev/null
      echo -e "\e[1;33m⛔ Disconnected $connected_mac\e[0m"
    done
    echo -e "\e[1;32m✅ All active devices disconnected.\e[0m"
    return 0
  fi

  if [[ "$action" != "connect" ]]; then
    echo -e "\e[1;33mUsage: bth {connect|disconnect}\e[0m"
    return 1
  fi

  trap 'echo -e "\n\e[1;31m⚠️ Aborted.\e[0m"; return 130' INT

  echo -e "\n\e[1;34m🔍 Scanning for Bluetooth devices...\e[0m"
  bluetoothctl power on >/dev/null
  bluetoothctl scan on >/dev/null &
  local scan_pid=$!
  sleep 5
  kill "$scan_pid" 2>/dev/null
  bluetoothctl scan off >/dev/null

  local devices=$(bluetoothctl devices | sort | awk '{$1=$2=""; print substr($0,3)}' | nl -w2 -s'. ')
  if [[ -z "$devices" ]]; then
    echo -e "\e[1;31m❌ No Bluetooth devices found.\e[0m"
    return 1
  fi

  echo -e "\n\e[1;36m📡 Nearby Bluetooth Devices:\e[0m"
  echo "$devices"

  echo -ne "\n\e[1;33m🔍 Enter device name (or partial match): \e[0m"
  read -r query

  local full_line=$(bluetoothctl devices | grep -i "$query" | head -n 1)
  local mac=$(echo "$full_line" | awk '{print $2}')
  local name=$(echo "$full_line" | cut -d ' ' -f3-)

  if [[ -z "$mac" ]]; then
    echo -e "\e[1;31m❌ No match found for '$query'.\e[0m"
    return 1
  fi

  echo -e "\n\e[1;35m🔌 Disconnecting all other devices first...\e[0m"
  bluetoothctl info | grep -B1 "Connected: yes" | grep Device | awk '{print $2}' | while read -r connected_mac; do
    bluetoothctl disconnect "$connected_mac" >/dev/null
    echo -e "\e[1;33m⛔ Disconnected $connected_mac\e[0m"
  done

  echo -e "\n\e[1;34m🔗 Pairing and connecting to: $name [$mac]...\e[0m"
  bluetoothctl trust "$mac"
  bluetoothctl pair "$mac"
  bluetoothctl connect "$mac"

  if [[ $? -eq 0 ]]; then
    echo -e "\e[1;32m✅ Connected to '$name' successfully.\e[0m"
  else
    echo -e "\e[1;31m❌ Failed to connect to '$name'.\e[0m"
  fi
}

#
#   show top repo contributors fast
gitwho() {
  git -C "${1:-.}" shortlog -sn --no-merges | head | nl -ba
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

# rerun last command with sudo
please() {
  sudo $(fc -ln -1)
}
