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


# generate new SSH keys for github, run this u'll get the pub key copied to ur clipboard,just paste it
ghkey() {
    bash ~/.ssh/_gh_gen.sh
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
