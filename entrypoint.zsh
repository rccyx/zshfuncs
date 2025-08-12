# === Source all zshfuncs ===
# Always source utils.zsh first, then the rest in any order.

# Absolute path to current script's directory
__zf_dir="${0:A:h}"

# First: source utils.zsh if it exists
[[ -f "$__zf_dir/utils.zsh" ]] && source "$__zf_dir/utils.zsh"

# Then: source all other .zsh files except utils.zsh
for f in "$__zf_dir"/*.zsh; do
  [[ "$f" == "$__zf_dir/utils.zsh" ]] && continue
  [[ -f "$f" ]] && source "$f"
done

unset __zf_dir f
