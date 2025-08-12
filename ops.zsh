# create a new directory & cd into it
mdd () {
 mkdir -p "$@" && cd "$@"
}

# copy file(s) contents to clipboard with elite UX
cpf() {
  local -a picks                                     # array for chosen files
  local max_mb=10                                    # warn if total >10 MB

  _err(){ print -P "%F{1}❌ $1%f" ; }
  _ok(){ print -P "%F{2}✅ $1%f" ; }

  # ---- gather file list ----
  if (( $# )); then
    picks=("$@")
  else
    command -v fzf >/dev/null || { _err "fzf not found, pass a file path"; return 1 }
    local finder; command -v fd >/dev/null && finder="fd -t f --hidden --exclude .git ." \
                                            || finder="find . -type f -not -path '*/\.git/*'"
    picks=("${(@f)$(eval "$finder" | \
      fzf --multi --height 60% --border --reverse \
          --prompt='📋 pick file ⇢ ' \
          --preview 'command -v bat >/dev/null && bat --style=numbers --color=always --line-range :300 {} || head -n 300 {}')}")
    [[ -z $picks ]] && _err "cancelled" && return 1
  fi

  # ---- sanity checks ----
  for f in "${picks[@]}"; do [[ -f $f ]] || { _err "'$f' is not a regular file"; return 1; } done

  local total_bytes=$(du -cb "${picks[@]}" | tail -1 | awk '{print $1}')
  if (( total_bytes > max_mb*1024*1024 )); then
    read -q "REPLY?⚠️ ${total_bytes} bytes > ${max_mb} MB, copy anyway? [y/N] "
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || { _err "aborted"; return 1; }
  fi

  # ---- copy ----
  cat "${picks[@]}" | xclip -selection clipboard
  _ok "copied ${#picks[@]} file(s) → clipboard (${total_bytes} bytes)"
}

# optional completion
_cpf(){ _arguments '*:files:_files' }
compdef _cpf cpf

# Needs xclip
# short for copy command, copies the output of the command to the clipboard
ccmd() {
  eval "$@" | xclip -selection clipboard
}
