txkill(){
  tmux list-sessions -F '#S' | xargs -I {} tmux kill-session -t {}
}

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
