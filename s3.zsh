# Elite S3 helpers: s3up, s3rm, s3down
# deps: awscli, fzf, jq, optional: fd

# ---------- ui helpers ----------
if ! typeset -f _ok   >/dev/null; then _ok(){ print -P "%F{2}✔%f $*"; } fi
if ! typeset -f _note >/dev/null; then _note(){ print -P "%F{4}ℹ️ %f $*"; } fi
if ! typeset -f _warn >/dev/null; then _warn(){ print -P "%F{3}‼%f $*"; } fi
if ! typeset -f _err  >/dev/null; then _err(){ print -P "%F{1}✖%f $*"; } fi
if ! typeset -f _hr   >/dev/null; then _hr(){ print -P "%F{244}${(l:60::-:)}%f"; } fi

# ---------- checks ----------
_s3_need(){ command -v "$1" >/dev/null 2>&1 || { _err "missing dep: $1"; return 1; } }
_s3_check(){
  _s3_need aws || return 1
  _s3_need fzf || return 1
  _s3_need jq  || return 1
  aws sts get-caller-identity >/dev/null 2>&1 || { _err "AWS creds not working. Check ~/.aws"; return 1; }
}

# ---------- region and bucket ----------
_s3_region(){ echo "${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}}" }
_s3_bucket_exists(){ aws s3api head-bucket --bucket "$1" >/dev/null 2>&1 }
_s3_list_buckets(){ aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null | tr '\t' '\n' | sort -u }

_s3_pick_bucket(){
  local default="ashgw-private-buckup" pick lines
  local -a existing; existing=("${(@f)$(_s3_list_buckets)}")
  if [[ -n "$S3_BUCKET" ]]; then echo "$S3_BUCKET"; return 0; fi
  lines=$(printf "%s\n" "$default" "${existing[@]}" | awk 'BEGIN{seen[""]=1} !seen[$0]++')
  pick=$(
    print -r -- "$lines" \
    | fzf --prompt="S3 bucket ⇢ " --header="Pick or type new, Enter to confirm" --print-query --height=40% \
    | awk 'NR==1{q=$0} END{print (NR>1?$0:q)}'
  )
  [[ -n "$pick" ]] && echo "$pick" || echo "$default"
}

_s3_secure_create_if_missing(){
  local b="$1" r="$(_s3_region)"
  if _s3_bucket_exists "$b"; then _note "bucket exists: $b"; return 0; fi
  _note "creating private bucket $b in $r"
  if [[ "$r" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$b" >/dev/null
  else
    aws s3api create-bucket --bucket "$b" --create-bucket-configuration LocationConstraint="$r" >/dev/null
  fi
  aws s3api put-public-access-block \
    --bucket "$b" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null
  aws s3api put-bucket-encryption \
    --bucket "$b" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
  _ok "created and secured: $b"
}

# ---------- size helpers ----------
_s3_bytes(){
  local p="$1"
  if [[ -d "$p" ]]; then
    du -sb "$p" 2>/dev/null | awk '{print $1}'
  else
    stat --printf="%s" "$p" 2>/dev/null || wc -c <"$p"
  fi
}
_s3_hsize(){
  local b="$1" kib=1024 mib=$((1024*1024)) gib=$((1024*1024*1024)) tib=$((1024*1024*1024*1024))
  if   (( b >= tib )); then printf "%.2f TiB" "$((b*100/tib))e-2"
  elif (( b >= gib )); then printf "%.2f GiB" "$((b*100/gib))e-2"
  elif (( b >= mib )); then printf "%.2f MiB" "$((b*100/mib))e-2"
  elif (( b >= kib )); then printf "%.2f KiB" "$((b*100/kib))e-2"
  else printf "%d B" "$b"; fi
}

# ---------- local picker ----------
_s3_pick_local(){
  if (( $# > 0 )); then print -r -- "$@"; return 0; fi
  if command -v fd >/dev/null 2>&1; then
    fd -H -d 1 -t f -t d . | sort | fzf --multi --height=70% --prompt="pick files or folders ⇢ "
  else
    find . -maxdepth 1 -mindepth 1 -printf "%P\n" | sort | fzf --multi --height=70% --prompt="pick files or folders ⇢ "
  fi
}

# ---------- plan render ----------
_s3_plan_upload(){
  local bucket="$1"; shift
  local -a items=("$@")
  local total=0 line
  _hr
  print -P "%F{244}PLAN: upload%f to %F{6}s3://$bucket/%f"
  for p in "${items[@]}"; do
    local base="${p:t}" bytes="$(_s3_bytes "$p" 2>/dev/null || echo 0)"
    (( total+=bytes ))
    if [[ -d "$p" ]]; then
      line="dir  $base/  ~ $(_s3_hsize "$bytes")"
    else
      line="file $base    $(_s3_hsize "$bytes")"
    fi
    print -P "  $line"
  done
  print -P "total ~ %F{6}$(_s3_hsize "$total")%f across %F{6}${#items[@]}%f item(s)"
  _hr
}

# ---------- s3up ----------
s3up(){
  emulate -L zsh
  setopt pipefail
  _s3_check || return 1

  local bucket; bucket="$(_s3_pick_bucket)" || return 1
  [[ -z "$bucket" ]] && { _err "no bucket chosen"; return 1; }
  _s3_secure_create_if_missing "$bucket" || return 1

  local -a picks; picks=("${(@f)$(_s3_pick_local "$@")}")
  (( ${#picks[@]} )) || { _err "nothing selected"; return 1; }

  local -a items=() p
  for p in "${picks[@]}"; do
    [[ -e "$p" ]] || { _err "missing: $p"; return 1; }
    items+=("${p:A}")
  done

  _s3_plan_upload "$bucket" "${items[@]}"

  local ans
  read -r "ans?Proceed with upload [y/N]: "
  [[ "$ans" =~ ^[Yy]$ ]] || { _warn "aborted"; return 1; }

  local rc=0 dest base cmd
  for p in "${items[@]}"; do
    base="${p:t}"
    if [[ -d "$p" ]]; then
      dest="s3://$bucket/${base}/"
      cmd=(aws s3 sync "$p" "$dest" --exact-timestamps)
    else
      dest="s3://$bucket/${base}"
      cmd=(aws s3 cp "$p" "$dest")
    fi
    print -P "%F{244}→%f ${cmd[*]}"
    "${cmd[@]}" || rc=$?
  done

  (( rc == 0 )) && _ok "upload complete" || _err "upload finished with errors (rc=$rc)"
  return $rc
}

# ---------- list every key as: key<TAB>size<TAB>lastmodified ----------
_s3_list_all_keys(){
  local bucket="$1" prefix="${2:-}" token resp
  while :; do
    resp="$(aws s3api list-objects-v2 \
              --bucket "$bucket" \
              --prefix "$prefix" \
              ${token:+--continuation-token "$token"} \
              --output json 2>/dev/null)" || break
    jq -r '.Contents[]? | [ .Key, ( .Size // 0 ), ( .LastModified // "" ) ] | @tsv' <<<"$resp"
    token="$(jq -r '.NextContinuationToken // empty' <<<"$resp")"
    [[ -z "$token" ]] && break
  done
}

# ---------- s3ls browser ----------
s3ls() {
  emulate -L zsh
  _s3_check || return 1
  local b="$1" pfx="${2:-}"
  [[ -z "$b" ]] && b="$(_s3_pick_bucket)"
  local rows; rows="$(_s3_list_all_keys "$b" "$pfx")"
  [[ -z "$rows" ]] && { _warn "no objects found in $b"; return 0; }
  print -r -- "$rows" \
    | fzf --with-nth=1 --delimiter='\t' --header="s3://$b/${pfx}" \
          --preview-window=down,6 \
          --preview 'printf "Key: %s\nSize: %s bytes\n" {1} {2}'
}

# ---------- delete plan ----------
_s3_plan_delete(){
  local bucket="$1" mode="$2"; shift 2
  local -a keys=("$@")
  local total=0 k sz
  _hr
  if [[ "$mode" == "prefix" ]]; then
    print -P "%F{244}PLAN: delete recursively%f from %F{6}s3://$bucket/%f"
    for k in "${keys[@]}"; do print -P "  prefix: $k"; done
    print -P "This will remove all objects under those prefix(es)."
  else
    print -P "%F{244}PLAN: delete objects%f from %F{6}s3://$bucket/%f"
    for k in "${keys[@]}"; do
      sz="$(aws s3api head-object --bucket "$bucket" --key "$k" --query 'ContentLength' --output text 2>/dev/null || echo 0)"
      (( total+=${sz:-0} ))
      print -P "  $k  ($(_s3_hsize "$sz"))"
    done
    print -P "total ~ %F{6}$(_s3_hsize "$total")%f across %F{6}${#keys[@]}%f object(s)"
  fi
  _hr
}

# ---------- s3rm ----------
# Usage:
#   s3rm                   -> interactive picker, multi select keys
#   s3rm prefix/           -> delete entire prefix recursively
#   s3rm key1 key2 ...     -> delete specific keys
s3rm(){
  emulate -L zsh
  setopt pipefail
  _s3_check || return 1

  local bucket; bucket="$(_s3_pick_bucket)" || return 1
  [[ -z "$bucket" ]] && { _err "no bucket chosen"; return 1; }

  local mode="" # keys or prefix
  local -a targets=()

  if (( $# == 0 )); then
    _note "fetching object list..."
    local rows; rows="$(_s3_list_all_keys "$bucket")" || true
    [[ -z "$rows" ]] && { _warn "no objects found in $bucket"; return 0; }
    targets=("${(@f)$(print -r -- "$rows" \
      | fzf --multi --with-nth=1 --delimiter='\t' --height=70% \
            --prompt="select to delete ⇢ " \
            --preview-window=down,8 \
            --preview 'printf "Key: %s\nSize: %s bytes\n" {1} {2}' \
      | awk -F'\t' '{print $1}')}")
    (( ${#targets[@]} )) || { _warn "nothing selected"; return 1; }
    mode="keys"
  else
    local anyprefix=0 t
    for t in "$@"; do [[ "$t" == */ ]] && anyprefix=1; done
    if (( anyprefix )); then
      mode="prefix"; for t in "$@"; do [[ "$t" == */ ]] && targets+=("$t"); done
    else
      mode="keys"; targets=("$@")
    fi
  fi

  _s3_plan_delete "$bucket" "$mode" "${targets[@]}"

  local confirm
  if [[ "$mode" == "prefix" ]]; then
    print -n "Type the bucket name '$bucket' to confirm recursive delete: "
    read -r confirm
    [[ "$confirm" == "$bucket" ]] || { _warn "confirmation mismatch. aborted."; return 1; }
  else
    print -n "Type DELETE to confirm object deletion: "
    read -r confirm
    [[ "$confirm" == "DELETE" ]] || { _warn "confirmation mismatch. aborted."; return 1; }
  fi

  local rc=0 k
  if [[ "$mode" == "prefix" ]]; then
    for k in "${targets[@]}"; do
      print -P "%F{244}→%f aws s3 rm s3://$bucket/$k --recursive"
      aws s3 rm "s3://$bucket/$k" --recursive || rc=$?
    done
  else
    local tmp payload
    tmp="$(mktemp)"; : > "$tmp"
    for k in "${targets[@]}"; do printf '{"Key":"%s"}\n' "$k" >> "$tmp"; done
    payload="$(jq -cs '{Objects: ., Quiet: false}' "$tmp")"
    print -P "%F{244}→%f aws s3api delete-objects (batched)"
    aws s3api delete-objects --bucket "$bucket" --delete "$payload" >/dev/null || rc=$?
    rm -f "$tmp"
  fi

  (( rc == 0 )) && _ok "delete complete" || _err "delete finished with errors (rc=$rc)"
  return $rc
}

# ---------- s3down ----------
# Usage:
#   s3down                        -> interactive pick, then ask destination dir
#   s3down photos/ logs/ ./out    -> download prefixes into ./out
#   s3down key1 key2              -> download specific keys into current dir
alias d3down='s3down'
_s3_is_dirpath(){ [[ -d "$1" || "$1" == */ || "$1" == "." || "$1" == ./* || "$1" == /* ]]; }

_s3_plan_download(){
  local bucket="$1" dest="$2"; shift 2
  local -a items=("$@") prefixes=() keys=() t
  for t in "${items[@]}"; do [[ "$t" == */ ]] && prefixes+=("$t") || keys+=("$t"); done
  _hr
  print -P "%F{244}PLAN: download%f from %F{6}s3://$bucket%f to %F{6}${dest:A}%f"
  (( ${#prefixes[@]} )) && { print -P "prefixes:"; for t in "${prefixes[@]}"; do print -P "  $t"; done; }
  if (( ${#keys[@]} )); then
    print -P "objects:"
    local k sz
    for k in "${keys[@]}"; do
      sz="$(aws s3api head-object --bucket "$bucket" --key "$k" --query 'ContentLength' --output text 2>/dev/null || echo 0)"
      print -P "  $k  ($(_s3_hsize "$sz"))"
    done
  fi
  _hr
}

s3down(){
  emulate -L zsh
  setopt pipefail
  _s3_check || return 1

  local bucket; bucket="$(_s3_pick_bucket)" || return 1
  [[ -z "$bucket" ]] && { _err "no bucket chosen"; return 1; }

  local -a args; args=("$@")
  local dest="" last=""
  if (( ${#args[@]} )); then last="${args[-1]}"; fi
  if (( ${#args[@]} )) && _s3_is_dirpath "$last"; then
    dest="${last%/}"
    args=("${args[@]:0:${#args[@]}-1}")
  fi

  local -a targets=()
  if (( ${#args[@]} == 0 )); then
    _note "fetching object list..."
    local rows; rows="$(_s3_list_all_keys "$bucket")" || true
    [[ -z "$rows" ]] && { _warn "no objects found in $bucket"; return 0; }
    targets=("${(@f)$(print -r -- "$rows" \
      | fzf --multi --with-nth=1 --delimiter='\t' --height=70% \
            --prompt="select to download ⇢ " \
            --preview-window=down,8 \
            --preview 'printf "Key: %s\nSize: %s bytes\n" {1} {2}' \
      | awk -F'\t' '{print $1}')}")
    (( ${#targets[@]} )) || { _warn "nothing selected"; return 1; }
  else
    targets=("${args[@]}")
  fi

  if [[ -z "$dest" ]]; then
    local inp
    read -r "?Download into which local directory [.] : " inp
    dest="${inp:-.}"
  fi
  mkdir -p -- "$dest" || { _err "cannot create dest dir: $dest"; return 1; }

  _s3_plan_download "$bucket" "$dest" "${targets[@]}"

  local ans
  read -r "ans?Proceed with download [y/N]: "
  [[ "$ans" =~ ^[Yy]$ ]] || { _warn "aborted"; return 1; }

  local rc=0 k p
  local -a prefixes=() keys=()
  for k in "${targets[@]}"; do [[ "$k" == */ ]] && prefixes+=("$k") || keys+=("$k"); done

  for k in "${keys[@]}"; do
    local out="$dest/$k"
    mkdir -p -- "${out:h}"
    print -P "%F{244}→%f aws s3 cp s3://$bucket/$k $out"
    aws s3 cp "s3://$bucket/$k" "$out" || rc=$?
  done

  for p in "${prefixes[@]}"; do
    local out="$dest/$p"
    mkdir -p -- "$out"
    print -P "%F{244}→%f aws s3 sync s3://$bucket/$p $out --exact-timestamps"
    aws s3 sync "s3://$bucket/$p" "$out" --exact-timestamps || rc=$?
  done

  (( rc == 0 )) && _ok "download complete" || _err "download finished with errors (rc=$rc)"
  return $rc
}

# ---------- tiny conveniences ----------
s3buckets(){ _s3_check || return 1; _s3_list_buckets }
s3who(){ aws sts get-caller-identity }

# ---------- rudimentary completion for s3rm ----------
_s3rm_complete(){
  local b="${S3_BUCKET:-}"
  [[ -z "$b" ]] && b="$(_s3_pick_bucket)"
  local -a keys; keys=("${(@f)$(aws s3api list-objects-v2 --bucket "$b" --max-items 1000 --query 'Contents[].Key' --output text 2>/dev/null | tr '\t' '\n')}")
  _describe -t keys 'keys' keys
}
compdef _s3rm_complete s3rm

