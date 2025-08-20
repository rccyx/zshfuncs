files(){
    nautilus
}
#   - Requires: shred (coreutils), fzf. Uses fd if available for faster listing.
#   - On SSDs or journaled FS, secure deletion is not guaranteed. Consider full disk crypto.
shatter() {
  emulate -L zsh
  setopt ERR_RETURN PIPE_FAIL NO_NOMATCH

  local passes=69
  if ! command -v shred >/dev/null 2>&1; then
    echo "shred not found. On Debian: sudo apt install coreutils"
    return 1
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf not found. On Debian: sudo apt install fzf"
    return 1
  fi

  local -a targets
  if (( $# == 0 )); then
    local selection
    if command -v fd >/dev/null 2>&1; then
      selection=$(fd --hidden --follow --exclude .git --type f \
        | fzf --multi --height=80% --reverse \
              --prompt="shatter> " \
              --header="Select files to shred. Tab to mark, Enter to confirm." \
              --preview 'stat --printf="Size: %s bytes\n" {} 2>/dev/null || stat -f "%z bytes" {}' \
              --preview-window=down:5:wrap)
    else
      selection=$(find . -type f -not -path '*/.git/*' -print \
        | sed 's#^\./##' \
        | fzf --multi --height=80% --reverse \
              --prompt="shatter> " \
              --header="Select files to shred. Tab to mark, Enter to confirm." \
              --preview 'stat --printf="Size: %s bytes\n" {} 2>/dev/null || stat -f "%z bytes" {}' \
              --preview-window=down:5:wrap)
    fi
    [[ -z "$selection" ]] && { echo "No selection."; return 1; }
    targets=("${(@f)selection}")
  else
    local p
    for p in "$@"; do
      if [[ -d "$p" ]]; then
        targets+=("${(@f)$(find "$p" -type f -not -path '*/.git/*')}")
      elif [[ -e "$p" ]]; then
        targets+=("$p")
      else
        echo "Skip missing: $p"
      fi
    done
  fi

  # de-dup
  targets=(${(u)targets})
  (( ${#targets} )) || { echo "Nothing to shred."; return 1; }

  # total size
  local total_bytes total_h
  total_bytes=$(printf '%s\0' "${targets[@]}" | xargs -0 stat --format %s 2>/dev/null | awk '{s+=$1} END{print s+0}')
  if command -v numfmt >/dev/null 2>&1; then
    total_h=$(numfmt --to=iec --suffix=B "$total_bytes")
  else
    total_h="${total_bytes}B"
  fi

  echo "About to IRREVERSIBLY shred ${#targets} file(s), approx ${total_h}, 69 passes."
  echo "Type YES to proceed:"
  local reply; read -r reply
  [[ "$reply" != "YES" ]] && { echo "Aborted."; return 130; }

  local fail=0 f
  for f in "${targets[@]}"; do
    if [[ -w "$f" ]]; then
      shred -n "$passes" -u -z -v -- "$f" || { echo "Failed: $f"; ((fail++)); }
    else
      sudo shred -n "$passes" -u -z -v -- "$f" || { echo "Failed: $f"; ((fail++)); }
    fi
  done

  (( fail )) && { echo "$fail file(s) failed."; return 1; }
  echo "Done."
}

# zsh completion: files and dirs
compdef _files shatter

