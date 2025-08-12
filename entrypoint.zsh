# === zshfuncs entrypoint ===

# 1) guard: never run twice in the same shell
if [[ -n ${__ZSF_ENTRYPOINT_SOURCED-} ]]; then
  return
fi
typeset -g __ZSF_ENTRYPOINT_SOURCED=1

# 2) resolve path to this file and its dir (works when sourced)
__zf_script="${(%):-%N}"
__zf_dir="${__zf_script:A:h}"
__self_base="${__zf_script:A:t}"

# 3) utils first
if [[ -r "$__zf_dir/utils.zsh" ]]; then
  source "$__zf_dir/utils.zsh"
fi

# 4) then every other .zsh in the folder, excluding self and utils
for f in "$__zf_dir"/*.zsh; do
  [[ ! -r "$f" ]] && continue
  [[ "${f:t}" == "utils.zsh" ]] && continue
  [[ "${f:t}" == "$__self_base" ]] && continue
  source "$f"
done

# 5) optional: make sure completion is initialized once, not per file
if ! whence -w compdef >/dev/null 2>&1; then
  autoload -Uz compinit
  compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
fi

unset __zf_script __zf_dir __self_base
