
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

# Get public DNS and geo info
whereami() {
  curl ipinfo.io
}
