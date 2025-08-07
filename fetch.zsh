ashgw() {
  local r=$'\e[0m' g=$'\e[1;32m' m=$'\e[1;35m'

  # ---------- gather ----------
  local os kernel uptime term shell wm pkgs cpu gpu mem disk ip temp
  os=$(command -v lsb_release >/dev/null && lsb_release -ds || grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"')
  kernel=$(uname -r)
  uptime=$(uptime -p | sed 's/^up //')
  term=$( [ -n "$TMUX" ] && echo "tmux" || echo "${TERM:-unknown}" )
  shell=$(basename "$SHELL")
  wm=${XDG_CURRENT_DESKTOP:-$(wmctrl -m 2>/dev/null | awk -F: '/Name/{gsub(/^ /,"",$2);print $2}')}
  pkgs=$(command -v dpkg >/dev/null && dpkg -l 2>/dev/null | awk 'BEGIN{n=0} /^ii/{n++} END{print n}')
  cpu=$(lscpu | awk -F: '/Model name/{gsub(/^[ \t]+/,"",$2);print $2}')
  gpu=$(lspci | grep -E "VGA|3D|Display" | sed -E 's/.*: //; s/ Corporation//; s/ Integrated Graphics Controller/ iGPU/' | head -n1)
  mem=$(free -h | awk '/Mem:/ {printf "%s used of %s", $3, $2}')
  disk=$(df -h / | awk 'NR==2{printf "%s used of %s (%s)", $3, $2, $5}')
  ip=$(ip -brief addr | awk '!/lo/ && $3 ~ /\// {print $1": "$3}' | head -n1)
  temp=$(command -v sensors >/dev/null && sensors 2>/dev/null | awk '/Package id 0|Tctl|Tdie|CPU/ {t=$NF; gsub(/[()]/,"",t); print t; exit}')

  # ---------- logo (fallback if figlet missing) ----------
  local logo
  if command -v figlet >/dev/null; then
    logo="$(figlet -f slant "@ashgw")"
  else
    logo="@ashgw  (install 'figlet' for big logo: sudo apt install figlet)"
  fi

  # ---------- format right column ----------
  local info
  info="$(printf "%s\n" \
    "${g}OS      ${r}${os}" \
    "${g}Kernel  ${r}${kernel}" \
    "${g}Uptime  ${r}${uptime}" \
    "${g}WM      ${r}${wm:-unknown}" \
    "${g}TERM    ${r}${term}" \
    "${g}SHELL   ${r}${shell}" \
    "${g}PKG     ${r}${pkgs:-0}" \
    "${g}CPU     ${r}${cpu}" \
    "$( [ -n "$gpu" ] && printf "%s" "${g}GPU     ${r}${gpu}" )" \
    "${g}MEM     ${r}${mem}" \
    "${g}DISK    ${r}${disk}" \
    "$( [ -n "$temp" ] && printf "%s" "${g}TEMP    ${r}${temp}" )" \
    "${g}NET     ${r}${ip}" \
  )"

  # ---------- side-by-side like neofetch ----------
  # pad logo to a fixed width so the info lines start aligned
  local COL=${AGFETCH_COL:-36}
  paste -d' ' \
    <(printf "%s\n" "$logo" | awk -v pad="$COL" -v pre="$m" -v suf="$r" '{printf "%s%-"pad"s%s\n",pre,$0,suf}') \
    <(printf "%s\n" "$info")
}
alias sysinfo="agfetch"
