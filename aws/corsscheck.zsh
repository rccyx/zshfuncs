# crosscheck.zsh
# ===================================================================
# crosscheck: scan IAM for risky trust and broad * grants
# Deps: awscli v2, jq; optional: fzf, column
# Safe: read-only IAM/STS/Organizations calls only
# ===================================================================

# ---- UI helpers (fallbacks) ----
if ! typeset -f _ok   >/dev/null; then _ok(){   print -P "%F{2}✔%f $*"; } fi
if ! typeset -f _note >/dev/null; then _note(){ print -P "%F{4}ℹ️ %f $*"; } fi
if ! typeset -f _warn >/dev/null; then _warn(){ print -P "%F{3}‼%f $*"; } fi
if ! typeset -f _err  >/dev/null; then _err(){  print -P "%F{1}✖%f $*"; } fi
_cc_hr(){ print -P "%F{244}$(printf '%*s' 64 '' | tr ' ' '-')%f"; }

# ---- knobs (noise suppression) ----
: ${CC_SUPPRESS_AWS_MANAGED:=0}      # 1 = drop policies under arn:aws:iam::aws:policy/
: ${CC_SUPPRESS_SERVICE_LINKED:=0}   # 1 = drop findings on role/AWSServiceRole*

# ---- dep and context ----
_cc_need(){ command -v "$1" >/dev/null 2>&1 || { _err "missing dep: $1"; return 1; } }
_cc_check(){
  _cc_need aws || return 1
  _cc_need jq  || return 1
  aws sts get-caller-identity >/dev/null 2>&1 || { _err "AWS creds not working"; return 1; }
}

# tolerant JSON exec (drops AccessDenied noise)
_cc_jx(){ local out; if out="$("$@" --output json 2>/dev/null)"; then printf "%s" "$out"; else printf ""; fi; }

# current account id
_cc_acct(){ aws sts get-caller-identity --query Account --output text 2>/dev/null; }

# optional org id->name map (unused in table, kept for future pretty-print)
_cc_org_map(){
  local next="" out; local -A map
  while :; do
    if [[ -n "$next" ]]; then out="$(_cc_jx aws organizations list-accounts --max-items 1000 --starting-token "$next")"
    else out="$(_cc_jx aws organizations list-accounts --max-items 1000)"; fi
    [[ -z "$out" ]] && break
    jq -r '.Accounts[] | [.Id,.Name] | @tsv' <<<"$out" | while IFS=$'\t' read -r id name; do
      [[ -n "$id" ]] && map[$id]="$name"
    done
    next="$(jq -r '.NextToken // empty' <<<"$out")"
    [[ -z "$next" ]] && break
  done
  typeset -p map 2>/dev/null | sed -n 's/^typeset -A map=//p'
}

# ---- pagination helpers for IAM list calls ----
_cc_list_roles(){
  local marker="" resp
  while :; do
    if [[ -n "$marker" ]]; then resp="$(_cc_jx aws iam list-roles --marker "$marker")"
    else resp="$(_cc_jx aws iam list-roles)"; fi
    [[ -z "$resp" ]] && break
    jq -r '.Roles[]?.RoleName' <<<"$resp"
    marker="$(jq -r '.Marker // empty' <<<"$resp")"
    [[ "$(jq -r '.IsTruncated' <<<"$resp")" == "true" ]] || break
  done
}
_cc_list_users(){
  local marker="" resp
  while :; do
    if [[ -n "$marker" ]]; then resp="$(_cc_jx aws iam list-users --marker "$marker")"
    else resp="$(_cc_jx aws iam list-users)"; fi
    [[ -z "$resp" ]] && break
    jq -r '.Users[]?.UserName' <<<"$resp"
    marker="$(jq -r '.Marker // empty' <<<"$resp")"
    [[ "$(jq -r '.IsTruncated' <<<"$resp")" == "true" ]] || break
  done
}
_cc_list_groups(){
  local marker="" resp
  while :; do
    if [[ -n "$marker" ]]; then resp="$(_cc_jx aws iam list-groups --marker "$marker")"
    else resp="$(_cc_jx aws iam list-groups)"; fi
    [[ -z "$resp" ]] && break
    jq -r '.Groups[]?.GroupName' <<<"$resp"
    marker="$(jq -r '.Marker // empty' <<<"$resp")"
    [[ "$(jq -r '.IsTruncated' <<<"$resp")" == "true" ]] || break
  done
}

# ---- trust policy analyzer for roles ----
_cc_scan_trust(){
  local role="$1" arn="$2" acct="$3" doc="$4"
  [[ -z "$doc" || "$doc" == "null" ]] && return 0
  jq -c --arg acc "$acct" --arg name "$role" --arg arn "$arn" '
    def arr(x): x|if type=="array" then . else (if .==null then [] else [.] end) end;
    def acctid(s):
      if s|test("^[0-9]{12}$") then s
      elif s|test("^arn:aws:iam::[0-9]{12}:") then (capture("arn:aws:iam::(?<a>[0-9]{12}):").a)
      else empty end;
    def hasAssume(s): (arr(s.Action) | map(tostring) | any(.=="sts:AssumeRole" or .=="sts:*" or .=="*"));
    def principals(p):
      if p==null then []
      elif p|type=="string" then [p]
      else arr(p.AWS) + arr(p.Federated) + arr(p.Service) end;
    . as $d
    | arr($d.Statement[])
    | map(select((.Effect // "Allow")=="Allow") | select(hasAssume(.)))
    | .[]
    | (principals(.Principal) | map(tostring)) as $pr
    | if ($pr|length)==0 then empty
      else
        if ($pr|any(.=="*")) then
          {kind:"role-trust", issue:"TRUST_WILDCARD", name:$name, arn:$arn,
           principals:$pr, hasCondition:(has("Condition")), statement:.}
        else
          [ $pr[] | acctid(.) | select(.!=null and .!=$acc) ] as $ext
          | if ($ext|length)>0 then
              {kind:"role-trust", issue:"TRUST_CROSS_ACCOUNT", name:$name, arn:$arn,
               principals:$pr, external_accounts:$ext, hasCondition:(has("Condition")), statement:.}
            else empty end
        end
      end
  ' <<<"$doc"
}

# ---- identity policy analyzer (inline or managed) ----
_cc_scan_policy_doc(){
  # args: attachKind attachName policyName policyArn policyVersion docJSON
  local atKind="$1" atName="$2" pName="$3" pArn="$4" pVer="$5" doc="$6"
  [[ -z "$doc" || "$doc" == "null" ]] && return 0
  jq -c --arg ak "$atKind" --arg an "$atName" --arg pn "$pName" --arg pa "$pArn" --arg pv "$pVer" '
    def arr(x): x|if type=="array" then . else (if .==null then [] else [.] end) end;
    . as $d
    | arr($d.Statement[])
    | map(select((.Effect // "Allow")=="Allow"))
    | .[]
    | (arr(.Action)   | map(tostring)) as $acts
    | (arr(.Resource) | map(tostring)) as $res
    | (has("NotResource")) as $hasNR
    | ($acts | any(.=="*" or (.|endswith("*")))) as $actStar
    | ($res  | any(.=="*")) as $resStar
    | select($actStar or $resStar or $hasNR)
    | {kind:"policy", attached_to:($ak+"/"+$an), policy_name:$pn, policy_arn:$pa, policy_version:$pv,
       issue: ( if $actStar and $resStar then "ACTION_AND_RESOURCE_WILDCARD"
                elif $actStar then "ACTION_WILDCARD"
                elif $resStar then "RESOURCE_WILDCARD"
                else "NOTRESOURCE_ALLOW" end ),
       actions:$acts, resources:$res, hasCondition:(has("Condition")), statement:.}
  ' <<<"$doc"
}

# ---- fetch policy documents ----
_cc_get_managed_doc(){
  # in: policy ARN; out: name\tversion\t<json>
  local arn="$1" meta verId name ver doc
  meta="$(_cc_jx aws iam get-policy --policy-arn "$arn")" || return 1
  verId="$(jq -r '.Policy.DefaultVersionId' <<<"$meta")"
  name="$(jq -r '.Policy.PolicyName' <<<"$meta")"
  ver="$(_cc_jx aws iam get-policy-version --policy-arn "$arn" --version-id "$verId")" || return 1
  doc="$(jq -c '.PolicyVersion.Document' <<<"$ver")"
  print -r -- "$name"$'\t'"$verId"$'\t'"$doc"
}

_cc_get_inline_doc_role(){  # role name, policy name
  local rn="$1" pn="$2" out doc
  out="$(_cc_jx aws iam get-role-policy --role-name "$rn" --policy-name "$pn")" || return 1
  doc="$(jq -c '.PolicyDocument' <<<"$out")"
  print -r -- "$doc"
}
_cc_get_inline_doc_user(){  # user name, policy name
  local un="$1" pn="$2" out doc
  out="$(_cc_jx aws iam get-user-policy --user-name "$un" --policy-name "$pn")" || return 1
  doc="$(jq -c '.PolicyDocument' <<<"$out")"
  print -r -- "$doc"
}
_cc_get_inline_doc_group(){ # group name, policy name
  local gn="$1" pn="$2" out doc
  out="$(_cc_jx aws iam get-group-policy --group-name "$gn" --policy-name "$pn")" || return 1
  doc="$(jq -c '.PolicyDocument' <<<"$out")"
  print -r -- "$doc"
}

# ---- scanners for each principal type ----
_cc_scan_role(){
  local rn="$1" acct="$2" jr arn trust
  jr="$(_cc_jx aws iam get-role --role-name "$rn")"
  arn="$(jq -r '.Role.Arn' <<<"$jr")"
  trust="$(jq -c '.Role.AssumeRolePolicyDocument' <<<"$jr")"
  _cc_scan_trust "$rn" "$arn" "$acct" "$trust"
  # managed
  local rap; rap="$(_cc_jx aws iam list-attached-role-policies --role-name "$rn")"
  jq -r '.AttachedPolicies[]?.PolicyArn' <<<"$rap" | while read -r parn; do
    [[ -z "$parn" ]] && continue
    local row name ver doc
    row="$(_cc_get_managed_doc "$parn")" || continue
    name="${row%%$'\t'*}"; row="${row#*$'\t'}"
    ver="${row%%$'\t'*}";  doc="${row#*$'\t'}"
    _cc_scan_policy_doc "role" "$rn" "$name" "$parn" "$ver" "$doc"
  done
  # inline
  local rip; rip="$(_cc_jx aws iam list-role-policies --role-name "$rn")"
  jq -r '.PolicyNames[]?' <<<"$rip" | while read -r pn; do
    [[ -z "$pn" ]] && continue
    local doc; doc="$(_cc_get_inline_doc_role "$rn" "$pn")" || continue
    _cc_scan_policy_doc "role" "$rn" "$pn" "" "" "$doc"
  done
}

_cc_scan_user(){
  local un="$1"
  local ap; ap="$(_cc_jx aws iam list-attached-user-policies --user-name "$un")"
  jq -r '.AttachedPolicies[]?.PolicyArn' <<<"$ap" | while read -r parn; do
    [[ -z "$parn" ]] && continue
    local row name ver doc
    row="$(_cc_get_managed_doc "$parn")" || continue
    name="${row%%$'\t'*}"; row="${row#*$'\t'}"
    ver="${row%%$'\t'*}";  doc="${row#*$'\t'}"
    _cc_scan_policy_doc "user" "$un" "$name" "$parn" "$ver" "$doc"
  done
  local ip; ip="$(_cc_jx aws iam list-user-policies --user-name "$un")"
  jq -r '.PolicyNames[]?' <<<"$ip" | while read -r pn; do
    [[ -z "$pn" ]] && continue
    local doc; doc="$(_cc_get_inline_doc_user "$un" "$pn")" || continue
    _cc_scan_policy_doc "user" "$un" "$pn" "" "" "$doc"
  done
}

_cc_scan_group(){
  local gn="$1"
  local ap; ap="$(_cc_jx aws iam list-attached-group-policies --group-name "$gn")"
  jq -r '.AttachedPolicies[]?.PolicyArn' <<<"$ap" | while read -r parn; do
    [[ -z "$parn" ]] && continue
    local row name ver doc
    row="$(_cc_get_managed_doc "$parn")" || continue
    name="${row%%$'\t'*}"; row="${row#*$'\t'}"
    ver="${row%%$'\t'*}";  doc="${row#*$'\t'}"
    _cc_scan_policy_doc "group" "$gn" "$name" "$parn" "$ver" "$doc"
  done
  local ip; ip="$(_cc_jx aws iam list-group-policies --group-name "$gn")"
  jq -r '.PolicyNames[]?' <<<"$ip" | while read -r pn; do
    [[ -z "$pn" ]] && continue
    local doc; doc="$(_cc_get_inline_doc_group "$gn" "$pn")" || continue
    _cc_scan_policy_doc "group" "$gn" "$pn" "" "" "$doc"
  done
}

# ---- main entry ----
crosscheck(){
  emulate -L zsh
  setopt pipefail

  local WANT_JSON=0 NO_FZF=0
  while (( $# )); do
    case "$1" in
      -j|--json) WANT_JSON=1; shift;;
      --no-fzf)  NO_FZF=1; shift;;
      *) _err "unknown arg: $1"; return 2;;
    esac
  done

  _cc_check || return 1
  local acct; acct="$(_cc_acct)"
  _cc_hr
  print -P "%F{6}CROSSCHECK%f  account=%F{244}${acct}%f  profile=%F{244}${AWS_PROFILE:-default}%f"
  _cc_hr

  local tmp; tmp="$(mktemp)"
  : > "$tmp"

  _note "scanning roles"
  local rn
  while IFS= read -r rn; do
    [[ -z "$rn" ]] && continue
    _cc_scan_role "$rn" "$acct" >>"$tmp"
  done < <(_cc_list_roles)

  _note "scanning users"
  local un
  while IFS= read -r un; do
    [[ -z "$un" ]] && continue
    _cc_scan_user "$un" >>"$tmp"
  done < <(_cc_list_users)

  _note "scanning groups"
  local gn
  while IFS= read -r gn; do
    [[ -z "$gn" ]] && continue
    _cc_scan_group "$gn" >>"$tmp"
  done < <(_cc_list_groups)

  # Optional suppression filters
  local jqf='.'
  (( CC_SUPPRESS_AWS_MANAGED ))    && jqf+=' | select((.policy_arn//"") | startswith("arn:aws:iam::aws:policy/") | not)'
  (( CC_SUPPRESS_SERVICE_LINKED )) && jqf+=' | select((.attached_to//"") | startswith("role/AWSServiceRole") | not)'
  jq -c "$jqf" "$tmp" > "$tmp.f" && mv "$tmp.f" "$tmp"

  local findings; findings="$(wc -l <"$tmp" | tr -d ' ')"
  _cc_hr
  print -P "Findings: %F{6}${findings}%f  (jsonl: %F{244}${tmp}%f)"

  (( WANT_JSON )) && { cat -- "$tmp"; return 0; }
  (( findings == 0 )) && { _ok "no risky trust or broad * grants detected in IAM identities"; return 0; }

  # Build TSV with stable index for preview -> JSON mapping
  local tsv="${tmp}.tsv"
  : > "$tsv"
  nl -ba -w1 -s$'\t' "$tmp" | while IFS=$'\t' read -r idx json; do
    printf '%s\n' "$json" | jq -r --arg i "$idx" '
      def sev(x):
        if x=="TRUST_WILDCARD" or x=="ACTION_AND_RESOURCE_WILDCARD" then "critical"
        elif x=="TRUST_CROSS_ACCOUNT" or x=="ACTION_WILDCARD" then "high"
        elif x=="RESOURCE_WILDCARD" or x=="NOTRESOURCE_ALLOW" then "medium"
        else "info" end;
      def subj: if .kind=="role-trust" then .name else .attached_to end;
      def extra:
        if .kind=="role-trust" then "ext=" + ((.external_accounts//[])|join(","))
        else "policy=" + ((.policy_name//"")) end;
      [$i, sev(.issue), .kind, .issue, subj,
       "cond=" + ((.hasCondition // false)|tostring), extra] | @tsv
    ' >> "$tsv"
  done

  if command -v fzf >/dev/null 2>&1 && (( NO_FZF == 0 )); then
    _note "fzf view - Enter to preview raw JSON"
    # {1} is safe numeric index from `nl`; preview maps back to the JSONL.
    fzf --ansi --no-multi --height=80% \
        --delimiter=$'\t' --with-nth=2.. \
        --header=$'sev\tkind\tissue\tsubject\tcond\textra' \
        --preview 'sed -n {1}p '"$tmp"' | jq -C .' < "$tsv"
  else
    print -P "%F{244}idx\tsev\tkind\tissue\tsubject\tcond\textra%f"
    column -ts $'\t' "$tsv"
  fi
}

# completion (basic)
_crosscheck_complete(){
  _arguments \
    '(-j --json)'{-j,--json}'[emit JSONL to stdout]' \
    '(--no-fzf)--no-fzf[disable fzf view]'
}
compdef _crosscheck_complete crosscheck

