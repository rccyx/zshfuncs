# ===========================
#  Cross desktop clipboard utils for Wayland, GNOME, X11, tmux, SSH
# ===========================

_have(){ command -v "$1" >/dev/null 2>&1; }
_err(){ print -P "%F{1}❌ $1%f" >&2; }
_ok(){  print -P "%F{2}✅ $1%f"; }

# Detect session backend
_session(){
  if [[ -n ${WAYLAND_DISPLAY:-} || ${XDG_SESSION_TYPE:-} == wayland ]]; then
    printf "wayland"
  elif [[ -n ${DISPLAY:-} ]]; then
    printf "x11"
  else
    printf "none"
  fi
}

# OSC52 copy to terminal, works even over SSH and inside tmux
_osc52_copy(){
  local data b64 esc="\x1b" bel="\x07"
  data="$(cat)"
  if (( ${#data} > 1048576 )); then _err "OSC52 payload too large (>1 MB)"; return 1; fi
  b64="$(printf "%s" "$data" | base64 | tr -d '\r\n')"
  if [[ -n ${TMUX:-} ]]; then
    printf "${esc}Ptmux;${esc}]52;c;%s${bel}${esc}\\" "$b64"
  else
    printf "${esc}]52;c;%s${bel}" "$b64"
  fi
}

# Write to clipboard. Reads stdin. Optional: set CLIP_BACKEND=wl|x|xsel|osc52 to force.
_clip(){
  local be="${CLIP_BACKEND:-$(_session)}"
  case "$be" in
    wl|wayland)
      if _have wl-copy; then wl-copy "$@"; return; fi
      ;;
    x|x11)
      if _have xclip; then xclip -selection clipboard "$@"; return; fi
      if _have xsel;  then xsel --clipboard "$@"; return; fi
      ;;
    xsel)
      if _have xsel;  then xsel --clipboard "$@"; return; fi
      ;;
    osc52)
      _osc52_copy; return
      ;;
  esac

  case "$(_session)" in
    wayland)
      if _have wl-copy; then wl-copy "$@"; return; fi
      if _have xclip;   then xclip -selection clipboard "$@"; return; fi
      if _have xsel;    then xsel --clipboard "$@"; return; fi
      ;;
    x11)
      if _have xclip;   then xclip -selection clipboard "$@"; return; fi
      if _have xsel;    then xsel --clipboard "$@"; return; fi
      ;;
    none)
      _osc52_copy; return
      ;;
  esac

  _osc52_copy
}

# Read from clipboard to stdout
_paste(){
  local be="${CLIP_BACKEND:-$(_session)}"
  case "$be" in
    wl|wayland)
      if _have wl-paste; then wl-paste "$@"; return; fi
      ;;
    x|x11)
      if _have xclip; then xclip -selection clipboard -o "$@"; return; fi
      if _have xsel;  then xsel --clipboard -o "$@"; return; fi
      ;;
    xsel)
      if _have xsel;  then xsel --clipboard -o "$@"; return; fi
      ;;
    osc52)
      _err "paste via OSC52 is not possible"; return 1
      ;;
  esac

  case "$(_session)" in
    wayland)
      if _have wl-paste; then wl-paste "$@"; return; fi
      if _have xclip;    then xclip -selection clipboard -o "$@"; return; fi
      if _have xsel;     then xsel --clipboard -o "$@"; return; fi
      ;;
    x11)
      if _have xclip;    then xclip -selection clipboard -o "$@"; return; fi
      if _have xsel;     then xsel --clipboard -o "$@"; return; fi
      ;;
    none)
      _err "no GUI clipboard in this session"; return 1
      ;;
  esac

  _err "no clipboard tool found. install wl-clipboard or xclip"
  return 1
}

# Handy frontends
copy(){ _clip; }     # usage: echo hi | copy
paste(){ _paste; }   # prints clipboard

# --------------------
# Your utilities (fixed to use _clip without -i)
# --------------------

# create a new directory & cd into it
mdd () { mkdir -p "$@" && cd "$@"; }

# copy all readable text files from a directory to clipboard
cpd() {
  local dir total_bytes max_mb=10 warn=$'\u26A0' interactive=0 arg
  local -a ignore_dirs=("*/.git/*" "*/node_modules/*" "*/.venv/*" "*/__pycache__/*" "*/dist/*" "*/build/*" "*/.next/*" "*/out/*" "*/.turbo/*" "*/.vercel/*" "*/target/*" "*/vendor/*")

  for arg in "$@"; do
    case "$arg" in
      -i|--ignore) interactive=1 ;;
      *) [[ -z "$dir" && -d "$arg" ]] && dir="$arg" ;;
    esac
  done

  if [[ -z $dir ]]; then
    if _have fzf; then
      if _have fd; then
        dir=$(fd -t d --hidden --exclude .git . | fzf --prompt='📂 pick dir ⇢ ' --height 60% --border --reverse)
      else
        dir=$(find . -type d -not -path '*/.git/*' | fzf --prompt='📂 pick dir ⇢ ' --height 60% --border --reverse)
      fi
    else
      _err "pass a directory or install fzf"; return 1
    fi
  fi

  [[ -z $dir ]]   && { _err "cancelled"; return 1; }
  [[ ! -d $dir ]] && { _err "'$dir' is not a directory"; return 1; }

  if (( interactive )); then
    local picks p base more=1
    local -a candidates
    while (( more )); do
      candidates=(".git" "node_modules" ".venv" "__pycache__" "dist" "build" ".next" "out" ".turbo" ".vercel" "target" "vendor")
      while IFS= read -r d; do candidates+=("${d#./}"); done < <(cd "$dir" && find . -maxdepth 2 -type d \( -name .git -prune -o -print \) | sed '1d;s#^\./##')
      candidates=("${(@u)candidates}")
      picks=$(printf '%s\n' "${candidates[@]}" | fzf --multi --height 60% --border --reverse \
              --prompt='🙈 ignore which dirs ⇢ ' \
              --preview='[[ -d "'"$dir"'"/{} ]] && ls -a "'"$dir"'"/{} | head -n 200')
      if [[ -n $picks ]]; then
        while IFS= read -r p; do
          [[ -z "$p" ]] && continue
          base="${p##*/}"
          ignore_dirs+=("*/${base}/*")
        done <<< "$picks"
      fi
      echo -n "➕ Add more ignores? [y/N] "; read -r ans; [[ "$ans" =~ ^[Yy]$ ]] || more=0
    done
  fi

  total_bytes=$(du -sb "$dir" | awk '{print $1}')
  if (( total_bytes > max_mb*1024*1024 )); then
    read -q "REPLY?$warn  $((total_bytes/1024/1024)) MB > $max_mb MB, copy anyway? [y/N] "; echo
    [[ $REPLY =~ ^[Yy]$ ]] || { _err "aborted"; return 1; }
  fi

  {
    cd "$dir" || { _err "cd failed"; return 1; }
    find . -type f $(for i in "${ignore_dirs[@]}"; do printf "! -path %q " "$i"; done) -print0 \
    | sort -z \
    | while IFS= read -r -d '' f; do
        if _have file && ! file --mime "$f" | grep -q text; then
          echo "# $f [binary skipped]"
        else
          echo "# $f"
          sed -e 's/\x1b\[[0-9;]*m//g' "$f"
          echo
        fi
      done
  } | _clip || return 1

  _ok "directory '$dir' copied to clipboard (size: $(du -sh "$dir" | awk '{print $1}'))"
}

# Copy or paste current directory as a tar stream
clipdir() {
  case "$1" in
    copy)  tar -cf - * 2>/dev/null | _clip || return 1; _ok "directory copied";;
    paste) _paste | tar -xvf - 2>/dev/null; _ok "directory pasted to $(pwd)";;
    *)     _err "usage: clipdir {copy|paste}"; return 1;;
  esac
}

# FZF delete picker
rmw() {
  _have fzf || { echo "fzf missing"; return 1; }
  local finder selection
  if _have fd; then finder='fd --hidden --follow --exclude .git .'
  else finder='find . -mindepth 1 -not -path "*/\.git/*"'; fi
  selection=$(
    eval "$finder" | fzf --multi --height 60% --reverse --border \
      --prompt="🗑️  select items to delete ⇢ " \
      --preview '
        [[ -d {} ]] && { command -v tree >/dev/null && tree -C -L 2 {} || ls -a {} ; } ||
        { command -v bat >/dev/null && bat --style=numbers --color=always --line-range :200 {} || head -n 200 {} ; }'
  )
  [[ -z $selection ]] && echo "nothing chosen, aborting" && return 1
  echo "about to delete:"; echo "$selection" | sed 's/^/   🔸 /'
  read -q "REPLY?confirm? [y/N] "; echo
  [[ $REPLY =~ ^[Yy]$ ]] || { echo "aborted"; return 1 }
  echo "$selection" | xargs -r rm -rf
  echo "✅ deleted"
}

# Copy picked files to clipboard
cpf() {
  local -a picks; local max_mb=10
  if (( $# )); then picks=("$@")
  else
    _have fzf || { _err "fzf not found, pass a file path"; return 1 }
    local finder; _have fd && finder="fd -t f --hidden --exclude .git ." || finder="find . -type f -not -path '*/\.git/*'"
    picks=("${(@f)$(eval "$finder" | fzf --multi --height 60% --border --reverse \
      --prompt='📋 pick file ⇢ ' \
      --preview 'command -v bat >/dev/null && bat --style=numbers --color=always --line-range :300 {} || head -n 300 {}')}")
    [[ -z $picks ]] && _err "cancelled" && return 1
  fi

  for f in "${picks[@]}"; do [[ -f $f ]] || { _err "'$f' is not a regular file"; return 1; } done
  local total_bytes=$(du -cb "${picks[@]}" | tail -1 | awk '{print $1}')
  if (( total_bytes > max_mb*1024*1024 )); then
    read -q "REPLY?⚠️ ${total_bytes} bytes > ${max_mb} MB, copy anyway? [y/N] "; echo
    [[ $REPLY =~ ^[Yy]$ ]] || { _err "aborted"; return 1; }
  fi

  cat "${picks[@]}" | _clip || return 1
  _ok "copied ${#picks[@]} file(s) to clipboard (${total_bytes} bytes)"
}

# copy stdout of any command to clipboard
ccmd(){ eval "$@" | _clip; }

