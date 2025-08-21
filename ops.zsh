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

cpd() {
  # Copy readable TEXT files to clipboard from DIR (default .),
  # ignoring VCS junk, deps, caches, and build outputs. Size shown = actual text payload.
  emulate -L zsh
  setopt err_return

  local dir="${1:-.}" max_mb=10
  [[ -d "$dir" ]] || { _err "'$dir' is not a directory"; return 1; }

  # enumerate files as NUL-separated relative paths
  local list; list="$(mktemp)" || { _err "mktemp failed"; return 1; }
  (
    cd "$dir" || exit 1
    if _have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git ls-files -z --cached --others --exclude-standard -- .
    else
      if _have fd; then
        fd -t f --hidden --follow \
          --exclude .git --exclude .github --exclude .gitlab \
          --exclude node_modules --exclude .pnpm-store --exclude .yarn --exclude .npm \
          --exclude .venv --exclude venv --exclude __pycache__ --exclude .cache \
          --exclude dist --exclude build --exclude .next --exclude out --exclude .turbo --exclude .vercel \
          --exclude target --exclude vendor --exclude .idea --exclude .vscode \
          . -0
      else
        find . \( \
          -name .git -o -name .github -o -name .gitlab -o \
          -name node_modules -o -name .pnpm-store -o -name .yarn -o -name .npm -o \
          -name .venv -o -name venv -o -name __pycache__ -o -name .cache -o \
          -name dist -o -name build -o -name .next -o -name out -o -name .turbo -o -name .vercel -o \
          -name target -o -name vendor -o -name .idea -o -name .vscode \
        \) -prune -o -type f -print0
      fi
    fi
  ) >"$list" || { rm -f "$list"; _err "failed to enumerate files"; return 1; }

  # hard skip helper
  local _skip
  _skip() {
    local p="${1#./}"
    case "$p" in
      .git|.git/*|*/.git|*/.git/*) return 0 ;;
      .git*|*/.git*) return 0 ;;                      # .gitignore .gitattributes .gitmodules etc
      .github|.github/*|*/.github|*/.github/*) return 0 ;;
      .gitlab|.gitlab/*|*/.gitlab|*/.gitlab/*) return 0 ;;
      node_modules|node_modules/*|*/node_modules|*/node_modules/*) return 0 ;;
      .pnpm-store|.pnpm-store/*|*/.pnpm-store|*/.pnpm-store/*) return 0 ;;
      .yarn|.yarn/*|*/.yarn|*/.yarn/*|.npm|.npm/*|*/.npm|*/.npm/*) return 0 ;;
      .venv|.venv/*|*/.venv|*/.venv/*|venv|venv/*|*/venv|*/venv/*) return 0 ;;
      __pycache__|__pycache__/*|*/__pycache__|*/__pycache__/*) return 0 ;;
      .cache|.cache/*|*/.cache|*/.cache/*) return 0 ;;
      dist|dist/*|*/dist|*/dist/*|build|build/*|*/build|*/build/*) return 0 ;;
      .next|.next/*|*/.next|*/.next/*|out|out/*|*/out|*/out/*) return 0 ;;
      .turbo|.turbo/*|*/.turbo|*/.turbo/*|.vercel|.vercel/*|*/.vercel|*/.vercel/*) return 0 ;;
      target|target/*|*/target|*/target/*|vendor|vendor/*|*/vendor|*/vendor/*) return 0 ;;
      .idea|.idea/*|*/.idea|*/.idea/*|.vscode|.vscode/*|*/.vscode|*/.vscode/*) return 0 ;;
      .DS_Store|*/.DS_Store|Thumbs.db|*/Thumbs.db) return 0 ;;
    esac
    return 1
  }

  # text check
  local _is_text
  _is_text() {
    if _have file; then
      file --mime --brief -- "$1" | grep -qiE 'charset=(utf-8|us-ascii|iso-|text)'
    else
      LC_ALL=C grep -Iq . -- "$1"
    fi
  }

  # human size
  local _fmt_size
  _fmt_size() {
    local b="$1"
    if _have numfmt; then
      numfmt --to=iec --suffix=B "$b"
    else
      if (( b < 1024 )); then printf "%d B" "$b"
      elif (( b < 1048576 )); then awk -v x="$b" 'BEGIN{printf "%.1f KiB", x/1024}'
      elif (( b < 1073741824 )); then awk -v x="$b" 'BEGIN{printf "%.2f MiB", x/1048576}'
      else awk -v x="$b" 'BEGIN{printf "%.2f GiB", x/1073741824}'
      fi
    fi
  }

  # compute payload size of what we will actually copy
  local -i total=0 sz
  while IFS= read -r -d '' f; do
    _skip "$f" && continue
    [[ -f "$dir/$f" ]] || continue
    if _is_text "$dir/$f"; then
      sz=$(stat -c %s -- "$dir/$f" 2>/dev/null || echo 0)
      total=$(( total + sz ))
      # header + newline cost is negligible, skip for simplicity
    fi
  done <"$list"

  if (( total == 0 )); then
    rm -f "$list"; _err "no text files to copy after applying ignores"; return 1
  fi

  if (( total > max_mb*1024*1024 )); then
    read -q "REPLY?⚠️ $(_fmt_size "$total") > $max_mb MiB, copy anyway? [y/N] "; echo
    [[ $REPLY =~ ^[Yy]$ ]] || { rm -f "$list"; _err "aborted"; return 1; }
  fi

  # stream payload
  (
    cd "$dir" || exit 1
    while IFS= read -r -d '' f; do
      _skip "$f" && continue
      if ! _is_text "$f"; then
        continue
      fi
      echo "# ${f#./}"
      sed -e 's/\x1b\[[0-9;]*m//g' -- "$f"
      echo
    done <"$list"
  ) | _clip || { rm -f "$list"; _err "copy failed"; return 1; }

  local human; human="$(_fmt_size "$total")"
  rm -f "$list"
  _ok "copied files from '$dir' to clipboard ($human)"
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

