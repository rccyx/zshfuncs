# counts the lines of code in your current codebase
# needs pnpm
loc() {
  local dir="${1:-.}"
  pnpm dlx cloc "$dir" \
    --exclude-dir='node_modules,dist,out,.next,build,.turbo,.vercel,.git,.venv,__pycache__,target,vendor' \
    --not-match-f='.*lock|.*min.js|.*.svg|.*.map|.*.log'
}

precmd() {
    # Print the previously configured title
    print -Pnr -- "$TERM_TITLE"

    # Print a new line before the prompt, but only if it is not the first line
    if [ "$NEWLINE_BEFORE_PROMPT" = yes ]; then
        if [ -z "$_NEW_LINE_BEFORE_PROMPT" ]; then
            _NEW_LINE_BEFORE_PROMPT=1
        else
            print ""
        fi
    fi
}
