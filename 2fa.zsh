# ===============================
# tfa: plain-text TOTP manager with fzf
# deps: fzf, oathtool; optional: wl-copy or xclip or pbcopy; python only if you enable fallback
# data dir: ~/.2fa  (one file per account, contents = raw secret exactly as you paste it)
# strict default: runs exactly `oathtool "$secret"` and surfaces errors
# set TFA_ALLOW_FALLBACK=1 if you want a permissive python fallback for testing
# ===============================

_ok(){ print -P "%F{2}✔%f $*"; }
_warn(){ print -P "%F{3}‼%f $*"; }
_err(){ print -P "%F{1}✖%f $*"; }

# clipboard
_tfa_clip(){
  if command -v wl-copy >/dev/null 2>&1; then wl-copy
  elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard
  elif command -v pbcopy >/dev/null 2>&1; then pbcopy
  else cat
  fi
}

# storage
_tfa_dir="$HOME/.2fa"
_tfa_init(){ mkdir -p "$_tfa_dir"; chmod 700 "$_tfa_dir" 2>/dev/null || true; }

# normalize names: trim, collapse whitespace to single underscore, strip slashes, strip edge underscores
_tfa_slug(){
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"   # trim
  s="${s//[$' \t\r\n']/_}"                                         # whitespace -> _
  s="${s//\//_}"; s="${s//\\/_}"                                   # kill slashes
  s="${s##_}"; s="${s%%_}"                                         # strip edge _
  print -r -- "$s"
}

# list basenames of existing secrets
_tfa_list(){ _tfa_init; command printf '%s\n' "$_tfa_dir"/*(.N:t) 2>/dev/null | LC_ALL=C sort; }

# strict generator: exactly oathtool SECRET; show stderr on failure
# optional fallback only when TFA_ALLOW_FALLBACK=1
_tfa_code_from_secret(){
  local secret="$1" out rc
  if ! command -v oathtool >/dev/null 2>&1; then _err "missing dep: oathtool"; return 127; fi
  out="$(oathtool "$secret" 2>&1)"; rc=$?
  if (( rc != 0 )); then
    _err "oathtool failed (rc=$rc): $out"
    if [[ "${TFA_ALLOW_FALLBACK:-0}" == 1 ]]; then
      out="$(
python3 - "$secret" <<'PY'
import sys, time, base64, binascii, hmac, hashlib, struct
s=sys.argv[1].strip()
cands=[lambda x: base64.b32decode(x.upper().replace(" ",""), casefold=True),
       lambda x: binascii.unhexlify(x)]
for dec in cands:
  try:
    k=dec(s); t=int(time.time())//30
    msg=struct.pack(">Q", t)
    h=hmac.new(k, msg, hashlib.sha1).digest()
    o=h[-1]&0x0F
    code=(int.from_bytes(h[o:o+4],"big") & 0x7fffffff)%1000000
    print(f"{code:06d}"); sys.exit(0)
  except Exception: pass
print("fallback failed", file=sys.stderr); sys.exit(2)
PY
      )"; rc=$?
      (( rc != 0 )) && { _err "$out"; return $rc; }
    else
      return $rc
    fi
  fi
  print -r -- "$out"
}

# picker that returns the exact filename even if display has spaces
_tfa_pick_secret_file(){
  emulate -L zsh
  local items; items="$(_tfa_list)" || true
  [[ -z "$items" ]] && { _err "no secrets yet"; return 1; }
  local choice
  choice="$(print -r -- "$items" \
    | awk '{print $0 "\t" $0}' \
    | fzf --height=60% --with-nth=1 --delimiter='\t' --prompt="2FA account ⇢ " \
          --preview='sh -c '\''f=$_tfa_dir/"$(printf %s "{}" | cut -f2)"; [ -f "$f" ] && sed "s/./*/g" < "$f" || true'\''' \
          --preview-window=down,3 \
    | cut -f2)"
  [[ -z "$choice" ]] && return 1
  print -r -- "$choice"
}

# add a secret
tfa.add(){
  emulate -L zsh
  _tfa_init
  local name secret file ans
  print -n "account name: "; read -r name
  [[ -z "$name" ]] && { _err "empty name"; return 1; }
  name="$(_tfa_slug "$name")"
  [[ -z "$name" ]] && { _err "name collapsed to empty"; return 1; }
  file="$_tfa_dir/$name"
  if [[ -e "$file" ]]; then
    _warn "exists: $file"
    print -n "overwrite [y/N]: "; read -r ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 1
  fi
  print -n "raw 2FA secret: "; read -r secret
  [[ -z "$secret" ]] && { _err "empty secret"; return 1; }
  printf "%s\n" "$secret" > "$file"
  chmod 600 "$file" 2>/dev/null || true
  _ok "added $name"
}

# list secrets with masked preview
tfa.list(){
  emulate -L zsh
  _tfa_init
  local f nm head tail
  for f in "$_tfa_dir"/*(.N); do
    [[ -f "$f" ]] || continue
    nm="${f:t}"
    head="$(head -c 3 "$f" 2>/dev/null)"
    tail="$(tail -c 3 "$f" 2>/dev/null)"
    print -P "%F{6}${nm}%f  secret: ${head}***${tail}"
  done
}

# change an existing secret
tfa.change(){
  emulate -L zsh
  _tfa_init
  local pick file new
  pick="$(_tfa_pick_secret_file)" || return 1
  file="$_tfa_dir/$pick"
  print -n "new raw secret for ${pick}: "; read -r new
  [[ -z "$new" ]] && { _err "empty secret"; return 1; }
  printf "%s\n" "$new" > "$file"
  chmod 600 "$file" 2>/dev/null || true
  _ok "updated $pick"
}

# use a secret: run exactly oathtool "$secret", show errors, copy code on success
tfa.use(){
  emulate -L zsh
  _tfa_init
  local pick file secret code now step left
  pick="$(_tfa_pick_secret_file)" || return 1
  file="$_tfa_dir/$pick"
  if [[ ! -f "$file" ]]; then _err "missing file: $file"; return 1; fi
  secret="$(head -n1 "$file" | tr -d '\r\n')"
  code="$(_tfa_code_from_secret "$secret")" || return $?
  now=$(date +%s); step=$(( now % 30 )); left=$(( 30 - step ))
  print -r -- "$code" | _tfa_clip >/dev/null 2>&1 || true
  print -P "%F{2}${code}%f  copied  (${left}s left)"
}

# main menu
tfa(){
  emulate -L zsh
  _tfa_init
  local action
  action="$(
    printf "%s\n" "use" "add" "list" "change" \
    | fzf --height=40% --prompt="tfa ⇢ "
  )" || return 1
  [[ -z "$action" ]] && return 1
  "tfa.${action}"
}

# completion
_tfa_complete(){
  local -a subs=(use add list change)
  _describe -t commands 'tfa subcommands' subs
}
compdef _tfa_complete tfa

