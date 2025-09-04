# ---------------------------
# git.zsh — helpers & browse
# ---------------------------

# internal: prefer 'upstream' if present, else 'origin'
_git_primary_remote() {
  if git remote | grep -qx "upstream"; then
    echo upstream
  else
    echo origin
  fi
}

# internal: resolve the default base ref:
# 1) <remote>/HEAD (e.g. origin/main)
# 2) <remote>/main or <remote>/master
# 3) local main or master
# Fallback is to echo nothing and let caller handle.
_git_default_base_ref() {
  local remote="${1:-$(_git_primary_remote)}" ref
  # remote default head, e.g. "origin/main"
  ref=$(git symbolic-ref -q --short "refs/remotes/${remote}/HEAD" 2>/dev/null)
  if [[ -n "$ref" ]]; then
    echo "$ref"; return 0
  fi
  if git show-ref --verify --quiet "refs/remotes/${remote}/main"; then
    echo "${remote}/main"; return 0
  fi
  if git show-ref --verify --quiet "refs/remotes/${remote}/master"; then
    echo "${remote}/master"; return 0
  fi
  if git show-ref --verify --quiet "refs/heads/main"; then
    echo "main"; return 0
  fi
  if git show-ref --verify --quiet "refs/heads/master"; then
    echo "master"; return 0
  fi
  return 1
}

# ---------------------------
# Browsing helpers
# ---------------------------

# stands for "browse", opens the current repo on GitHub
bws() {
  local remote
  remote=$(git config --get remote.origin.url)
  remote=${remote/git@github.com:/https:\/\/github.com\/}
  remote=${remote/.git/}
  xdg-open "$remote"
}

# PRs list
prs() {
  local remote
  remote=$(git config --get remote.origin.url)
  remote=${remote/git@github.com:/https://github.com/}
  remote=${remote/.git/}
  xdg-open "$remote/pulls"
}

# Open the Pull Request for the current branch (if any)
prr() {
  emulate -L zsh
  setopt err_return

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not in a git repo" >&2
    return 1
  fi

  local branch
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD)

  if command -v gh >/dev/null 2>&1; then
    if gh pr view --web >/dev/null 2>&1; then
      return 0
    fi
  fi

  local remote_name="$(_git_primary_remote)" remote https slug owner repo
  remote=$(git config --get "remote.${remote_name}.url")
  if [[ -z "$remote" ]]; then
    echo "No ${remote_name} remote found" >&2
    return 1
  fi
  https=${remote/git@github.com:/https://github.com/}
  https=${https/.git/}
  slug=${https#https://github.com/}
  owner=${slug%%/*}
  repo=${slug#*/}

  local token resp pr_html api
  token=${GITHUB_TOKEN:-$GH_TOKEN}
  if command -v curl >/dev/null 2>&1; then
    api="https://api.github.com/repos/${owner}/${repo}/pulls?head=${owner}:${branch}&state=open&per_page=1"
    if [[ -n "$token" ]]; then
      resp=$(curl -fsSL -H "Authorization: token ${token}" -H "Accept: application/vnd.github+json" "$api" 2>/dev/null) || resp=""
    else
      resp=$(curl -fsSL -H "Accept: application/vnd.github+json" "$api" 2>/dev/null) || resp=""
    fi
    if [[ -n "$resp" ]]; then
      if command -v jq >/dev/null 2>&1; then
        pr_html=$(printf "%s" "$resp" | jq -r '.[0].html_url // empty')
      else
        pr_html=$(printf "%s" "$resp" | sed -n 's/.*"html_url": *"\([^"]*\)".*/\1/p' | head -n1)
      fi
      if [[ -n "$pr_html" ]]; then
        xdg-open "$pr_html" >/dev/null 2>&1 &
        return 0
      fi
    fi
  fi

  local urlencode search_url
  urlencode() {
    local i ch out="" s="$1"
    for ((i=1; i<=${#s}; i++)); do
      ch="${s[i]}"
      case "$ch" in
        [a-zA-Z0-9.~_-]) out+="$ch" ;;
        *) out+=$(printf '%%%02X' "'$ch") ;;
      esac
    done
    print -r -- "$out"
  }
  search_url="${https}/pulls?q=is%3Apr+is%3Aopen+head%3A$(urlencode "$branch")"
  xdg-open "$search_url" >/dev/null 2>&1 &
}

# issues list
issues() {
  local remote
  remote=$(git config --get remote.origin.url)
  remote=${remote/git@github.com:/https://github.com/}
  remote=${remote/.git/}
  xdg-open "$remote/issues"
}

# ---------------------------
# Branch and history helpers
# ---------------------------

# checkout with fzf
gck() {
  local branch
  branch=$(git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short)' \
    | fzf --prompt="🌿 checkout branch ⇢ " --preview="git log -n 10 --color=always {}" --height=50%)
  [[ -n "$branch" ]] && git checkout "$branch"
}
compdef _git gck

# grep commits by added/removed string, preview commit
ggrep() {
  local q
  echo -n "search term: "; read -r q
  git log --all --pretty=format:'%C(auto)%h %s %Cgreen(%cr)' -S"$q" |
    fzf --reverse --preview="echo {} | cut -d' ' -f1 | xargs git show --color=always"
}
compdef _git ggrep

# last commit details
gll() {
  git show "$(git log -1 --format=%H)"
}

# last commit file change stats
gllc() {
  git diff HEAD~1 HEAD --stat
}

# WHO did what
gitwho() {
  git -C "${1:-.}" shortlog -sn --no-merges | head | nl -ba
}

# root of repo
groot() {
  cd "$(git rev-parse --show-toplevel)" || echo "Not in a git repo"
}

# Danger: delete all local branches except current
dlb() {
  git branch | grep -v "$(git rev-parse --abbrev-ref HEAD)" | xargs git branch -D
}

# ---------------------------
# Whole-branch diffs (since diverging from base)
# ---------------------------

# bll  -> list files changed on this branch since it diverged from base
# usage: bll [<base-ref>]
# default base: remote default head (origin/main), with fallbacks
bll() {
  emulate -L zsh
  setopt pipefail

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not in a git repo" >&2
    return 1
  fi

  local base_ref="${1:-${BLL_BASE:-}}"
  if [[ -z "$base_ref" ]]; then
    base_ref="$(_git_default_base_ref "$(_git_primary_remote)")" || true
  fi
  if [[ -z "$base_ref" ]]; then
    echo "Could not determine base branch. Pass one explicitly, e.g. 'bll main'." >&2
    return 1
  fi

  # triple-dot = diff against merge-base(base_ref, HEAD)
  git diff --name-status -M --find-renames "${base_ref}...HEAD"
}

# bllc -> cumulative diff stats for the whole branch
# usage: bllc [<base-ref>]
bllc() {
  emulate -L zsh
  setopt pipefail

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not in a git repo" >&2
    return 1
  fi

  local base_ref="${1:-${BLL_BASE:-}}"
  if [[ -z "$base_ref" ]]; then
    base_ref="$(_git_default_base_ref "$(_git_primary_remote)")" || true
  fi
  if [[ -z "$base_ref" ]]; then
    echo "Could not determine base branch. Pass one explicitly, e.g. 'bllc main'." >&2
    return 1
  fi

  git diff --stat -M --find-renames "${base_ref}...HEAD"
}

# optional simple completion
compdef _git bll bllc

# ---------------------------
# SSH key helper for GitHub
# ---------------------------

# generate a GitHub SSH key, add to agent, copy .pub to clipboard
# usage: ghkey [-f] [-c comment] [path]
# defaults: path=$HOME/.ssh/github, comment="$(whoami)@$(hostname)"
ghkey() {
  emulate -L zsh
  set -u

  local force=0 comment="$(whoami)@$(hostname)" opt
  while getopts "fc:" opt; do
    case "$opt" in
      f) force=1 ;;
      c) comment="$OPTARG" ;;
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
      echo "Aborted. Use: ghkey -f to overwrite."
      return 1
    fi
  fi

  if [[ ! -f "$key" || $force -eq 1 ]]; then
    ssh-keygen -t ed25519 -C "$comment" -f "$key" -N "" || { echo "ssh-keygen failed"; return 1; }
    chmod 600 "$key" 2>/dev/null || true
  fi

  if ! ssh-add -l >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null 2>&1
  fi
  ssh-add -q "$key" || { echo "ssh-add failed"; return 1; }

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

