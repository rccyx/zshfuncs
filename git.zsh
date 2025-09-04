# -----------------------------------
# Base helpers (keep once in the file)
# -----------------------------------
_git_primary_remote() {
  if git remote | grep -qx "upstream"; then
    echo upstream
  else
    echo origin
  fi
}

_git_default_base_ref() {
  local remote="${1:-$(_git_primary_remote)}" ref
  ref=$(git symbolic-ref -q --short "refs/remotes/${remote}/HEAD" 2>/dev/null)
  if [[ -n "$ref" ]]; then echo "$ref"; return 0; fi
  if git show-ref --verify --quiet "refs/remotes/${remote}/main"; then echo "${remote}/main"; return 0; fi
  if git show-ref --verify --quiet "refs/remotes/${remote}/master"; then echo "${remote}/master"; return 0; fi
  if git show-ref --verify --quiet "refs/heads/main"; then echo "main"; return 0; fi
  if git show-ref --verify --quiet "refs/heads/master"; then echo "master"; return 0; fi
  return 1
}

# Build <base>...HEAD (merge-base aware). Honors $BLL_BASE or arg.
_git_branch_range() {
  local base_ref="${1:-${BLL_BASE:-}}"
  if [[ -z "$base_ref" ]]; then
    base_ref="$(_git_default_base_ref "$(_git_primary_remote)")" || true
  fi
  [[ -z "$base_ref" ]] && return 1
  printf "%s...HEAD" "$base_ref"
}

# ---------------------------
# Your existing single-commit
# ---------------------------
gll()   { git show "$(git log -1 --format=%H)"; }         # keep as you have
gllc()  { git diff HEAD~1 HEAD --stat; }                  # keep as you have

# ----------------------------------------
# Whole-branch versions (no fzf, pure git)
# ----------------------------------------

# bll  -> full patch for the whole branch vs base, scroll in your pager
# usage: bll [<base-ref>]   # default base auto-detected; or export BLL_BASE=origin/main
bll() {
  emulate -L zsh
  setopt pipefail

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not in a git repo" >&2; return 1
  fi

  local range; range="$(_git_branch_range "$1")" || {
    echo "Could not determine base. Try: bll main" >&2; return 1; }

  # Exactly like gll, but for the branch range. Plus/minus hunks, through your pager.
  git diff --color "$range"
}

# bllc -> stats summary for the whole branch vs base (mirror of gllc)
# usage: bllc [<base-ref>]
bllc() {
  emulate -L zsh
  setopt pipefail

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not in a git repo" >&2; return 1
  fi

  local range; range="$(_git_branch_range "$1")" || {
    echo "Could not determine base. Try: bllc main" >&2; return 1; }

  git diff --stat --color "$range"
}

