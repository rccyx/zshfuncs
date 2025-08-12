# Generate a TOTP code via oathtool, secret entered interactively.
# Usage: tfa            → prompts for secret (hidden)
#        tfa <secret>   → uses provided secret directly
tfa() {
  local secret code

  if [[ -n "$1" ]]; then
    secret="$1"
  else
    print -n "TOTP secret: "
    stty -echo
    read -r secret
    stty echo
    print
  fi

  code=$(oathtool "$secret") || { echo "❌ oathtool failed"; return 1; }
  echo "$code"

  if command -v xclip >/dev/null 2>&1; then
    printf "%s" "$code" | xclip -selection clipboard
    echo "📋 Copied to clipboard."
  fi
}
