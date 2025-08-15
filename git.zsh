# stands for "browse", opens  the current repo on GitHub
bws() {
  local remote
  remote=$(git config --get remote.origin.url)
  remote=${remote/git@github.com:/https:\/\/github.com\/}
  remote=${remote/.git/}
  xdg-open "$remote"
}
# PRs
prs() {
  local remote
  remote=$(git config --get remote.origin.url)
  remote=${remote/git@github.com:/https://github.com/}
  remote=${remote/.git/}
  xdg-open "$remote/pulls"
}

# yessir
issues() {
  local remote
  remote=$(git config --get remote.origin.url)
  remote=${remote/git@github.com:/https://github.com/}
  remote=${remote/.git/}
  xdg-open "$remote/issues"
}
# git checkout on roids
gck() {
  local branch
  branch=$(git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short)' \
    | fzf --prompt="🌿 checkout branch ⇢ " --preview="git log -n 10 --color=always {}" --height=50%)
  [[ -n "$branch" ]] && git checkout "$branch"
}
compdef _git gck

# git grepper for commits
ggrep() {
  local q
  echo -n "🔍 search term: "; read -r q
  git log --all --pretty=format:'%C(auto)%h %s %Cgreen(%cr)' -S"$q" |
    fzf --reverse --preview="echo {} | cut -d' ' -f1 | xargs git show --color=always"
}

## g for git, double l is for last, since I already have gl as git log.. in the .gitconfig file.
gll() {
	 git show $(git log -1 --format=%H)
}

gllc(){
	git diff HEAD~1 HEAD --stat
}

#   show top repo contributors fast
gitwho() {
  git -C "${1:-.}" shortlog -sn --no-merges | head | nl -ba
}
# generate a GitHub SSH key, add it to the agent, and copy the .pub to clipboard
# usage: ghkey [-f] [-c comment] [path]
# defaults: path=$HOME/.ssh/github, comment="$(whoami)@$(hostname)"
ghkey() {
  emulate -L zsh
  set -u

  local force=0 comment="$(whoami)@$(hostname)" opt
  while getopts "fc:" opt; do
    case "$opt" in
      f) force=1 ;;         # overwrite existing key without prompting
      c) comment="$OPTARG" ;;# set key comment
    esac
  done
  shift $((OPTIND - 1))

  local key="${1:-$HOME/.ssh/github}"
  local pub="$key.pub"
  local cfg="$HOME/.ssh/config"

  mkdir -p "$HOME/.ssh" || { echo "mkdir ~/.ssh failed"; return 1; }
  chmod 700 "$HOME/.ssh" 2>/dev/null || true

  if [[ -e "$key" && $force -ne 1 ]]; then
    echo "Key exists at $key"
    read -q "REPLY?Reuse it? [Y/n] "; echo
    if [[ "$REPLY" == [Nn] ]]; then
      echo "Aborted. Use: ghkey -f  to overwrite."
      return 1
    fi
  fi

  if [[ ! -f "$key" || $force -eq 1 ]]; then
    ssh-keygen -t ed25519 -C "$comment" -f "$key" -N "" || { echo "ssh-keygen failed"; return 1; }
    chmod 600 "$key" 2>/dev/null || true
  fi

  # ensure an ssh-agent is running
  if ! ssh-add -l >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null 2>&1
  fi
  ssh-add -q "$key" || { echo "ssh-add failed"; return 1; }

  # write minimal config for GitHub if not present
  if [[ ! -f "$cfg" ]] || ! grep -q "IdentityFile $key" "$cfg"; then
    {
      echo "Host github.com"
      echo "  HostName github.com"
      echo "  AddKeysToAgent yes"
      echo "  IdentityFile $key"
      echo "  IdentitiesOnly yes"
    } >> "$cfg"
    chmod 600 "$cfg" 2>/dev/null || true
  fi

  # copy pub key to clipboard using your ops.zsh if available, else fall back
  if typeset -f _clip >/dev/null; then
    < "$pub" _clip || { echo "clipboard copy failed"; return 1; }
  elif typeset -f copy >/dev/null; then
    < "$pub" copy || { echo "clipboard copy failed"; return 1; }
  elif command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$pub"
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard < "$pub"
  elif command -v xsel >/dev/null 2>&1; then
    xsel --clipboard < "$pub"
  else
    echo "No clipboard tool found. Here is your public key:"
    echo
    cat "$pub"
    echo
  fi

  echo "Done. Public key is in your clipboard. Add it in GitHub -> Settings -> SSH and GPG keys."
  echo "Test when ready: ssh -T git@github.com"
}



# go into the root of the current git dir
groot() {
  cd "$(git rev-parse --show-toplevel)" || echo "Not in a git repo"
}

# USE WITH CAUTION: DELETES ALL THE GIT BRANCHES EXCEPT FOR THE ONE YOU'RE ON RN
dlb() {
 git branch | grep -v "$(git rev-parse --abbrev-ref HEAD)" | xargs git branch -D
}

compdef _git ggrep

