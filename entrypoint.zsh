# guard: never run twice in the same shell
if [[ -n ${__ZSF_ENTRYPOINT_SOURCED-} ]]; then
  return
fi
typeset -g __ZSF_ENTRYPOINT_SOURCED=1

emulate zsh
setopt null_glob

# resolve path to this file and its dir (works when sourced)
__zf_script="${(%):-%N}"
__zf_dir="${__zf_script:A:h}"
__self_base="${__zf_script:A:t}"

# export env early from ~/.exported before anything else
__zsf_load_env() {
  emulate -L zsh
  setopt null_glob
  set -a
  local envdir="${ZSF_EXPORTED_DIR:-$HOME/.exported}"
  local f
  for f in "$envdir"/.env "$envdir"/*.env "$envdir"/.env.*; do
    [[ -r "$f" ]] || continue
    source "$f"
  done
  set +a
}
__zsf_load_env
unset -f __zsf_load_env

# utils first
if [[ -r "$__zf_dir/utils.zsh" ]]; then
  builtin source "$__zf_dir/utils.zsh"
fi

# source a file, but never let it abort the entrypoint via top-level `return`
__zsf_source_safe() {
  emulate -L zsh
  setopt no_err_return
  local f="$1"
  [[ -r "$f" ]] || return 0
  builtin source "$f"
  return 0
}

# then every other .zsh in the folder, excluding self and utils
for f in "$__zf_dir"/*.zsh; do
  [[ "${f:t}" == "utils.zsh" ]] && continue
  [[ "${f:t}" == "$__self_base" ]] && continue
  __zsf_source_safe "$f"
done
unset -f __zsf_source_safe

# completion is initialized once, not per file
if ! whence -w compdef >/dev/null 2>&1; then
  autoload -Uz compinit
  compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
fi

# folders (always run, regardless of any module behavior above)
if [[ -r "$__zf_dir/aws/entrypoint.zsh" ]]; then
  builtin source "$__zf_dir/aws/entrypoint.zsh"
fi
if [[ -r "$__zf_dir/opsec/entrypoint.zsh" ]]; then
  builtin source "$__zf_dir/opsec/entrypoint.zsh"
fi

unset __zf_script __zf_dir __self_base
