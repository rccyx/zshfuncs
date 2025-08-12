# create a new directory & cd into it
mdd () {
 mkdir -p "$@" && cd "$@"
}

# ================================================================
#   cpd — copy all readable text files from a directory to clipboard
#
#   - skips binaries and common junk (node_modules, .git, .venv, etc.)
#   - strips ANSI codes
#   - warns if dir >10MB
#   - supports fzf dir picker
#   - deps: fzf, xclip, file, (fd optional)
# ================================================================
cpd() {
  local dir total_bytes max_mb=10 warn=$'\u26A0'
  local interactive=0
  local arg

  # defaults
  local -a ignore_dirs=("*/.git/*" "*/node_modules/*" "*/.venv/*" "*/__pycache__/*" "*/dist/*" "*/build/*" "*/.next/*" "*/out/*" "*/.turbo/*" "*/.vercel/*" "*/target/*" "*/vendor/*")

  # ---- parse flags ----
  for arg in "$@"; do
    case "$arg" in
      -i|--ignore) interactive=1 ;;
      *) [[ -z "$dir" && -d "$arg" ]] && dir="$arg" ;;
    esac
  done

  # ---- choose directory ----
  if [[ -z $dir ]]; then
    if command -v fzf >/dev/null; then
      if command -v fd >/dev/null; then
        dir=$(fd -t d --hidden --exclude .git . | fzf --prompt='📂 pick dir ⇢ ' --height 60% --border --reverse)
      else
        dir=$(find . -type d -not -path '*/.git/*' | fzf --prompt='📂 pick dir ⇢ ' --height 60% --border --reverse)
      fi
    else
      echo "pass a directory or install fzf" >&2
      return 1
    fi
  fi

  [[ -z $dir ]]   && { _err "cancelled"; return 1; }
  [[ ! -d $dir ]] && { _err "'$dir' is not a directory"; return 1; }

  # ---- optional interactive ignore loop ----
  if (( interactive )); then
    local picks
    local -a candidates
    local more=1

    while (( more )); do
      # fresh candidate list every round
      candidates=(".git" "node_modules" ".venv" "__pycache__" "dist" "build" ".next" "out" ".turbo" ".vercel" "target" "vendor")
      while IFS= read -r d; do
        candidates+=("${d#./}")
      done < <(cd "$dir" && find . -maxdepth 2 -type d \( -name .git -prune -o -print \) | sed '1d' | sed 's#^\./##')
      candidates=("${(@u)candidates}")

      picks=$(printf '%s\n' "${candidates[@]}" | fzf --multi --height 60% --border --reverse \
              --prompt='🙈 ignore which dirs ⇢ ' \
              --preview='[[ -d "'"$dir"'"/{} ]] && ls -a "'"$dir"'"/{} | head -n 200')

      if [[ -n $picks ]]; then
        local p base
        while IFS= read -r p; do
          [[ -z "$p" ]] && continue
          base="${p##*/}"
          ignore_dirs+=("*/${base}/*")
        done <<< "$picks"
      fi

      echo -n "➕ Add more ignores? [y/N] "
      read -r ans
      [[ "$ans" =~ ^[Yy]$ ]] || more=0
    done
  fi

  # ---- size check ----
  total_bytes=$(du -sb "$dir" | awk '{print $1}')
  if (( total_bytes > max_mb*1024*1024 )); then
    read -q "REPLY?$warn  $((total_bytes/1024/1024)) MB > $max_mb MB, copy anyway? [y/N] "
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || { _err "aborted"; return 1; }
  fi

  # ---- dump and copy ----
  {
    cd "$dir" || { _err "cd failed"; return 1; }
    find . -type f \
      $(for i in "${ignore_dirs[@]}"; do printf "! -path %q " "$i"; done) \
      -print0 | sort -z | while IFS= read -r -d '' f; do
        if command -v file >/dev/null && ! file --mime "$f" | grep -q text; then
          echo "# $f [binary skipped]"
        else
          echo "# $f"
          sed -e 's/\x1b\[[0-9;]*m//g' "$f"
          echo
        fi
      done
  } | xclip -selection clipboard

  _ok "directory '$dir' copied to clipboard (size: $(du -sh "$dir" | awk '{print $1}'))"
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
  command -v fzf >/dev/null || { echo "fzf missing"; return 1 }
  local finder selection

  # pick every file and dir under cwd, hide .git and other junk
  if command -v fd >/dev/null; then
    finder='fd --hidden --follow --exclude .git .'
  else
    finder='find . -mindepth 1 -not -path "*/\.git/*"'
  fi

  selection=$(
    eval "$finder" | \
    fzf --multi --height 60% --reverse --border \
        --prompt="🗑️  select items to delete ⇢ " \
        --preview '
          [[ -d {} ]] && { command -v tree >/dev/null && tree -C -L 2 {} || ls -a {} ; } ||
          { command -v bat >/dev/null && bat --style=numbers --color=always --line-range :200 {} || cat {} ; }'
  )

  [[ -z $selection ]] && echo "nothing chosen, aborting" && return 1

  echo "about to delete:"
  echo "$selection" | sed 's/^/   🔸 /'
  read -q "REPLY?confirm? [y/N] "
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || { echo "aborted"; return 1 }

  echo "$selection" | xargs -r rm -rf
  echo "✅ deleted"
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
