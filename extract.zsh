# this one is big extractor func
extract() {
  # ANSI Colors
  local bold=$'\e[1m'
  local reset=$'\e[0m'
  local green=$'\e[32m'
  local red=$'\e[31m'
  local yellow=$'\e[33m'
  local blue=$'\e[34m'
  local cyan=$'\e[36m'
  local grey=$'\e[90m'

  local input="$1"
  local matches file

  if [[ "$input" == "--help" || -z "$input" ]]; then
    echo "${bold}${cyan}Usage:${reset} extract <partial-name-or-glob>"
    echo ""
    echo "${bold}${cyan}Description:${reset} Smart file extractor with fuzzy matching and format detection."
    echo ""
    echo "${bold}${cyan}Supported formats:${reset}"
    echo "  ${green}.tar.gz  .tar.bz2  .tar  .tgz  .tbz2  .gz  .bz2${reset}"
    echo "  ${green}.zip     .rar      .7z   .Z    .deb${reset}"
    echo ""
    echo "${bold}${cyan}Examples:${reset}"
    echo "  extract logs"
    echo "  extract '*.zip'"
    echo ""
    return 0
  fi

  echo "${bold}${blue}[extract]${reset} Looking for files matching ${yellow}*${input}*${reset}..."
  matches=(${(f)"$(ls *${input}* 2>/dev/null)"})

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "${red}[extract] No files matched pattern:${reset} *$input*"
    return 1
  elif [[ ${#matches[@]} -eq 1 ]]; then
    file="${matches[1]}"
    echo "${bold}${green}[extract] One match found:${reset} $file"
  else
    echo "${bold}${yellow}[extract] Multiple matches found:${reset}"
    for f in "${matches[@]}"; do echo "  ${grey}- $f${reset}"; done
    file=$(printf '%s\n' "${matches[@]}" | fzf --prompt="${bold}[extract] Select file: ${reset}")
    [[ -z "$file" ]] && echo "${red}[extract] No file selected.${reset}" && return 1
  fi

  if [[ ! -f "$file" ]]; then
    echo "${red}[extract] '$file' is not a valid file.${reset}"
    return 1
  fi

  echo "${bold}${blue}[extract]${reset} Extracting ${yellow}$file${reset}..."
  case "$file" in
    *.tar.bz2)   echo "→ ${green}tar xjf${reset} '$file'" ; tar xjf "$file" ;;
    *.tar.gz)    echo "→ ${green}tar xzf${reset} '$file'" ; tar xzf "$file" ;;
    *.bz2)       echo "→ ${green}bunzip2${reset} '$file'" ; bunzip2 "$file" ;;
    *.rar)       echo "→ ${green}unrar x${reset} '$file'" ; unrar x "$file" ;;
    *.gz)        echo "→ ${green}gunzip${reset} '$file'" ; gunzip "$file" ;;
    *.tar)       echo "→ ${green}tar xf${reset} '$file'" ; tar xf "$file" ;;
    *.tbz2)      echo "→ ${green}tar xjf${reset} '$file'" ; tar xjf "$file" ;;
    *.tgz)       echo "→ ${green}tar xzf${reset} '$file'" ; tar xzf "$file" ;;
    *.zip)       echo "→ ${green}unzip${reset} '$file'" ; unzip "$file" ;;
    *.Z)         echo "→ ${green}uncompress${reset} '$file'" ; uncompress "$file" ;;
    *.7z)        echo "→ ${green}7z x${reset} '$file'" ; 7z x "$file" ;;
    *.deb)
      local deb_dir="extracted_${file%.deb}"
      echo "→ ${green}dpkg -x${reset} '$file' '${cyan}$deb_dir${reset}'"
      mkdir -p "$deb_dir" && dpkg -x "$file" "$deb_dir"
      ;;
    *) echo "${red}[extract] Unsupported file type:${reset} $file" ;;
  esac
}
