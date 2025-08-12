txkill(){
  tmux list-sessions -F '#S' | xargs -I {} tmux kill-session -t {}
}
