# === MODULE LOADER & BUNDLER ===
__zf_script="${(%):-%N}"
__zf_dir="${__zf_script:A:h}"

# If executed (not sourced) -> spit out full bundled script for easy piping
if [[ "$ZSH_EVAL_CONTEXT" != *":file"* ]]; then
  for file in "$__zf_dir/utils.zsh" "$__zf_script" "$__zf_dir/wifi.zsh" "$__zf_dir/bluetooth.zsh" "$__zf_dir/usb.zsh"; do
    [[ -f "$file" ]] && cat "$file" && echo
  done
  exit 0
fi

# If sourced, pull in any external modules that are present
for m in utils wifi bluetooth usb; do
  [[ -f "$__zf_dir/${m}.zsh" ]] && source "$__zf_dir/${m}.zsh"
done

# ================================================================
#    ZSH FUNCTION COLLECTION
# ================================================================
## UTILS
clr(){ printf "\e[%sm" "$1"; }
_err(){ clr 31; echo "❌ $1"; clr 0; }
_ok(){ clr 32; echo "✅ $1"; clr 0; }
_note(){ clr 34; echo "ℹ️  $1"; clr 0; }

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


 remindme() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: remindme <seconds> <message>"
    return 1
  fi
  (sleep "$1" && echo "Reminder: $2") &
}

# rerun last command with sudo
please() {
  sudo $(fc -ln -1)
}

# counts the lines of code in your current codebase
# needs pnpm
loc() {
  local dir="${1:-.}"
  pnpm dlx cloc "$dir" \
    --exclude-dir='node_modules,dist,out,.next,build,.turbo,.vercel,.git,.venv,__pycache__,target,vendor' \
    --not-match-f='.*lock|.*min.js|.*.svg|.*.map|.*.log'
}

# =========================
# psf  → find processes and kill selected
# psf             pick and SIGTERM
# psf -9          pick and SIGKILL
# =========================
psf() {
  local sig="15"
  [[ "$1" =~ ^-?[0-9]+$ ]] && sig="${1#-}"
  if _has fzf; then
    local lines pids
    lines=$(ps -eo pid,user,pcpu,pmem,etime,comm --sort=-pcpu | awk 'NR==1 || $3>0.1' | fzf --multi --height 70% --border --prompt="kill [sig $sig] ⇢ " --preview="echo {}")
    [[ -z "$lines" ]] && return 1
    pids=$(echo "$lines" | awk 'NR>1{print $1}')
    echo "$pids" | xargs -r kill -"$sig"
  else
    ps aux | head
    echo "fzf not installed. Use kill manually or install fzf."
  fi
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

# ===============  COMPLETIONS  ==================
compdef _usbdev usbmount usbumount usbformat usbwipe usbperf usbburn usbls
_usbdev(){
  local -a devs; devs=(${(f)"$(lsblk -nr -o NAME,TRAN | awk '$2=="usb"{print "/dev/"$1}')"})
  _describe 'usb' devs
}
