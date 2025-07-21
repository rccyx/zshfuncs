
# ================================================================
#    ZSH FUNCTION COLLECTION
# ================================================================
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

nodeclean() {
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
  local selection

  # find deletable items
  local items=($(find . -maxdepth 1 -mindepth 1 -not -path "./.git" 2>/dev/null))
  if [[ ${#items[@]} -eq 0 ]]; then
    echo -e "\e[1;31m❌ Nothing to delete here.\e[0m"
    return 1
  fi

  # use fzf to pick files/dirs
  selection=$(printf "%s\n" "${items[@]}" | fzf --multi --height=60% --reverse --border \
    --prompt="🗑️ Select items to delete ⇢ " \
    --preview '[[ -d {} ]] && tree -C -L 2 {} || bat --style=plain --color=always {} 2>/dev/null || cat {}' \
    --header="TAB to multi-select, ENTER to confirm")

  [[ -z "$selection" ]] && echo -e "\e[1;33m⚠️ Cancelled. Nothing deleted.\e[0m" && return 1

  echo -e "\e[1;31m❗ You're about to delete:\e[0m"
  echo "$selection" | sed 's/^/   🔸 /'

  echo -ne "\n\e[1;33mConfirm? [y/N] ⇢ \e[0m"
  read -r confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo -e "\e[1;31m🛑 Aborted.\e[0m" && return 1

  echo "$selection" | xargs -r rm -rf
  echo -e "\e[1;32m✅ Deleted.\e[0m"
}


#   WIFI FUNCTION: Connect to Wi-Fi from terminal w/ clean UX (autocomplete etc..), just pulling the wifi icon from the tool bar is a pain in the ass, might as well do it from the terminal
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

  # Check if it's already saved
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


# copy the last terminal buffer content in tmux only, `cop n` where n is the number of lines needed to copy
cop() {
  local n=${1:-100}
  local max_lines=10000
  (( n > max_lines )) && n=$max_lines

  if [ -n "$TMUX" ]; then
    tmux capture-pane -pS -$n | sed 's/\x1b\[[0-9;]*m//g' | xclip -selection clipboard
    echo -e "\e[1;32m📋 Copied $n lines from tmux.\e[0m"
    return
  fi

  # Outside tmux, we fallback to zsh history
  local histfile=${HISTFILE:-$HOME/.zsh_history}
  if [[ ! -f $histfile ]]; then
    echo -e "\e[1;31m❌ No zsh history file found.\e[0m"
    return 1
  fi

  local lines=$(tail -n "$n" "$histfile" | sed 's/^: [0-9]*:[0-9]*;//')
  echo "$lines" | xclip -selection clipboard
  echo -e "\e[1;33m⚠️ Not in tmux. Pasted last $n commands, not visual buffer.\e[0m"
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


# this one is big extractor func
extract() {
  # ANSI Colors
  local bold=$'\e[1m'
  local reset=$'\e[0m'
  local green=$'\e[32m'
  local red=$'\e[31m'
  local yellow=$'\e[33m'
  local blue=$'\e[34m'
  local cyan=$'\e[36m'
  local grey=$'\e[90m'

  local input="$1"
  local matches file

  if [[ "$input" == "--help" || -z "$input" ]]; then
    echo "${bold}${cyan}Usage:${reset} extract <partial-name-or-glob>"
    echo ""
    echo "${bold}${cyan}Description:${reset} Smart file extractor with fuzzy matching and format detection."
    echo ""
    echo "${bold}${cyan}Supported formats:${reset}"
    echo "  ${green}.tar.gz  .tar.bz2  .tar  .tgz  .tbz2  .gz  .bz2${reset}"
    echo "  ${green}.zip     .rar      .7z   .Z    .deb${reset}"
    echo ""
    echo "${bold}${cyan}Examples:${reset}"
    echo "  extract logs"
    echo "  extract '*.zip'"
    echo ""
    return 0
  fi

  echo "${bold}${blue}[extract]${reset} Looking for files matching ${yellow}*${input}*${reset}..."
  matches=(${(f)"$(ls *${input}* 2>/dev/null)"})

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "${red}[extract] No files matched pattern:${reset} *$input*"
    return 1
  elif [[ ${#matches[@]} -eq 1 ]]; then
    file="${matches[1]}"
    echo "${bold}${green}[extract] One match found:${reset} $file"
  else
    echo "${bold}${yellow}[extract] Multiple matches found:${reset}"
    for f in "${matches[@]}"; do echo "  ${grey}- $f${reset}"; done
    file=$(printf '%s\n' "${matches[@]}" | fzf --prompt="${bold}[extract] Select file: ${reset}")
    [[ -z "$file" ]] && echo "${red}[extract] No file selected.${reset}" && return 1
  fi

  if [[ ! -f "$file" ]]; then
    echo "${red}[extract] '$file' is not a valid file.${reset}"
    return 1
  fi

  echo "${bold}${blue}[extract]${reset} Extracting ${yellow}$file${reset}..."
  case "$file" in
    *.tar.bz2)   echo "→ ${green}tar xjf${reset} '$file'" ; tar xjf "$file" ;;
    *.tar.gz)    echo "→ ${green}tar xzf${reset} '$file'" ; tar xzf "$file" ;;
    *.bz2)       echo "→ ${green}bunzip2${reset} '$file'" ; bunzip2 "$file" ;;
    *.rar)       echo "→ ${green}unrar x${reset} '$file'" ; unrar x "$file" ;;
    *.gz)        echo "→ ${green}gunzip${reset} '$file'" ; gunzip "$file" ;;
    *.tar)       echo "→ ${green}tar xf${reset} '$file'" ; tar xf "$file" ;;
    *.tbz2)      echo "→ ${green}tar xjf${reset} '$file'" ; tar xjf "$file" ;;
    *.tgz)       echo "→ ${green}tar xzf${reset} '$file'" ; tar xzf "$file" ;;
    *.zip)       echo "→ ${green}unzip${reset} '$file'" ; unzip "$file" ;;
    *.Z)         echo "→ ${green}uncompress${reset} '$file'" ; uncompress "$file" ;;
    *.7z)        echo "→ ${green}7z x${reset} '$file'" ; 7z x "$file" ;;
    *.deb)
      local deb_dir="extracted_${file%.deb}"
      echo "→ ${green}dpkg -x${reset} '$file' '${cyan}$deb_dir${reset}'"
      mkdir -p "$deb_dir" && dpkg -x "$file" "$deb_dir"
      ;;
    *) echo "${red}[extract] Unsupported file type:${reset} $file" ;;
  esac
}

# ================================================================
#   MINIMAL WIFI TOOLKIT — ZSH FUNCTIONS (v2)
#   deps: nmcli ≥1.42, fzf, xclip
#   drop‑in; source this file or copy into .zshrc
# ================================================================
clr(){ printf "\e[%sm" "$1"; }
_err(){ clr 31; echo "❌ $1"; clr 0; }
_ok(){ clr 32; echo "✅ $1"; clr 0; }
_note(){ clr 34; echo "ℹ️  $1"; clr 0; }
_iface(){ nmcli device | awk '/wifi|wl/ {print $1; exit}'; }
_sel_ssid(){
  local list choice
  list=$(nmcli -t -f SSID,SIGNAL dev wifi list | awk -F: 'length($1){printf "%-40s [%s%%]\n",$1,$2}' | sort -k2 -nr)
  [[ -z $list ]] && _err "no networks found" && return 1
  choice=$(printf "%s\n" "$list" | fzf --prompt="📶 SSID ➜ " --no-multi)
  [[ -z $choice ]] && _err "no ssid chosen" && return 1
  printf "%s" "${choice%% *}"
}

# ---------- radio hard toggle ----------
wifikill(){ nmcli radio wifi off && _ok "wifi radio off"; }
wifiresume(){ nmcli radio wifi on  && _ok "wifi radio on";  }

# ---------- reconnect quick ----------
wifireconnect(){
  local ssid=$(_sel_ssid) || return 1
  _note "reconnecting to $ssid…"
  if nmcli connection up "$ssid" 2>/dev/null || nmcli device wifi connect "$ssid" 2>/dev/null; then
    _ok "connected to $ssid"
  else
    _err "failed to connect to $ssid"
  fi
}

# ---------- show current password & copy ----------
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

# ---------- completion ----------
_wifi_ssids(){
  local -a ssids; ssids=( $(nmcli -t -f SSID dev wifi | sort -u) )
  _describe 'ssid' ssids
}
compdef _wifi_ssids wifireconnect

# smart copy ++ : cpw
# deps: fzf, rsync, fd (for speed), zoxide (optional), tree (optional)

cpw() {
  local -a srcs
  local dest picker_cmd

  _pick_sources() {
    if command -v fd >/dev/null; then
      picker_cmd="fd --hidden --follow --exclude .git ."
    else
      picker_cmd="find . \( -type f -o -type d \) -not -path '*/\.git/*' -print"
    fi
    srcs=("${(@f)$(
      eval "$picker_cmd" |
      fzf --multi --height 60% --border --prompt="📄 pick files/dirs ⇢ " \
          --preview '
            [[ -d {} ]] && { command -v tree >/dev/null && tree -C -L 2 {} || ls -a {} ; } ||
            { command -v bat >/dev/null && bat --style=numbers --color=always --line-range :200 {} || file {}; }'
    )}")
  }

  _parents_of_pwd() {
    local p="$PWD"
    while [[ "$p" != "/" ]]; do
      echo "$p"
      p=${p:h}
    done
    echo "/"
  }

  _fzf_preview_dir() {
    command -v tree >/dev/null && echo "tree -C -L 2 {}" || echo "ls -a {}"
  }

  _pick_dest() {
    local -a dirlist
    dirlist+=($(_parents_of_pwd))
    if command -v zoxide >/dev/null; then
      dirlist+=("${(@f)$(zoxide query -ls | awk '{$1=""; print substr($0,2)}')}")
    fi
    if command -v fd >/dev/null; then
      dirlist+=("${(@f)$(fd -t d --max-depth 3 --hidden --exclude .git . $HOME)}")
    else
      dirlist+=("${(@f)$(find $HOME -maxdepth 3 -type d -not -path '*/\.git/*')}")
    fi
    dest="$(
      printf '%s\n' "${dirlist[@]}" | awk '!seen[$0]++' | \
      fzf --height 60% --border --prompt="📂 choose destination ⇢ " \
          --preview="$(_fzf_preview_dir)"
    )"
    [[ -z $dest ]] && { echo "no destination chosen"; return 1; }
    if [[ ! -d $dest ]]; then
      read -q "REPLY?🔧 '$dest' doesn’t exist – create it? [y/N] "
      echo
      [[ $REPLY == [Yy] ]] || return 1
      mkdir -p "$dest" || { echo "mkdir failed"; return 1; }
    fi
  }

  # ----- arg parsing -----
  if [[ $# -eq 0 ]]; then
    _pick_sources || return 1
    [[ ${#srcs[@]} -eq 0 ]] && echo "nothing selected" && return 1
    _pick_dest   || return 1
  elif [[ $# -eq 1 ]]; then
    srcs=("$1")
    _pick_dest   || return 1
  else
    srcs=("${@:1:$#-1}")
    dest="${@: -1}"
  fi

  [[ -z $dest || ! -d $dest ]] && { echo "bad destination"; return 1; }

  echo "🔄 copying → ${srcs[@]} → $dest"
  rsync -aP "${srcs[@]}" "$dest"/
}

# ---------- completion ----------
_cpw() {
  _arguments \
    '1:source files:_files' \
    '2:destination dir:_path_files -/'
}
compdef _cpw cpw


# cd into a file u fuzzy picked
cdf() {
  local file=$(fd . | fzf --prompt="📄 jump to file dir ⇢ ")
  [[ -n $file ]] && cd "$(dirname "$file")"
}

# go into the root of the current git dir
groot() {
  cd "$(git rev-parse --show-toplevel)" || echo "Not in a git repo"
}

# open current repo in Github
gopen() {
  local remote=$(git remote get-url origin 2>/dev/null)
  [[ -z $remote ]] && echo "No remote" && return
  remote=${remote/git@github.com:/https:\/\/github.com\/}
  remote=${remote/.git/}
  xdg-open "$remote"
}
