# ---------- orgmap (interactive, zero-flags) ----------
# Walk AWS Organizations from root and show OUs, accounts, IAM aliases, enabled regions, and SCPs.
# No flags. Uses fzf dropdowns for choices. Safe UI helpers that override any globals.

orgmap() {
  emulate -L zsh
  setopt localoptions no_unset pipefail

  # UI helpers (force override, no brittle ${(l:...)} stuff)
  _ok(){   print -P "%F{2}✔%f $*"; }
  _note(){ print -P "%F{4}ℹ️  %f $*"; }
  _warn(){ print -P "%F{3}‼%f $*"; }
  _err(){  print -P "%F{1}✖%f $*"; }
  _hr(){   print -P "%F{244}$(printf '%*s' 64 '' | tr ' ' '-')%f"; }

  # deps
  _need(){ command -v "$1" >/dev/null 2>&1 || { _err "missing dep: $1"; return 1; }; }
  _need aws || return 1
  _need jq  || return 1

  # pickers
  _has_fzf(){ command -v fzf >/dev/null 2>&1; }
  _pick_one() {
    local def="$1" prompt="$2"; shift 2
    if _has_fzf; then
      printf "%s\n" "$@" \
      | fzf --prompt="$prompt " --height=40% --border --no-multi --ansi \
      || print -r -- "$def"
    else
      print -P "$prompt [%F{244}$def%f]: " | tr -d '\n'
      local sel; read -r sel
      [[ -n "$sel" ]] && print -r -- "$sel" || print -r -- "$def"
    fi
  }
  _pick_role() {
    local def="${ORGMAP_ASSUME_ROLE:-OrganizationAccountAccessRole}"
    local choice; choice="$(_pick_one "$def" "Assume role for alias lookup" \
      "$def" "OrganizationAccountAccessRole" "OrgAuditRole" "SecurityAudit" "custom")"
    if [[ "$choice" == "custom" ]]; then
      print -P "Role name [%F{244}$def%f]: " | tr -d '\n'
      local rn; read -r rn
      print -r -- "${rn:-$def}"
    else
      print -r -- "$choice"
    fi
  }
  _pick_json_path() {
    local ts path; ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)"
    path="/tmp/orgmap-${ts}.json"
    local choice; choice="$(_pick_one "no" "Write JSON too" "no" "$path" "custom")"
    case "$choice" in
      no) print -r "" ;;
      custom)
        print -P "Path [%F{244}$path%f]: " | tr -d '\n'
        local p; read -r p
        print -r -- "${p:-$path}"
        ;;
      *) print -r -- "$choice" ;;
    esac
  }

  # header so you see output immediately
  _hr
  print -P "%F{6}orgmap%f  %F{244}interactive%f"
  _hr

  # STS
  local ident acct arn
  if ! ident="$(aws sts get-caller-identity --output json 2>&1)"; then
    _err "STS failed. Check creds or MFA."
    print -r -- "$ident" >&2
    return 1
  fi
  acct="$(jq -r '.Account' <<<"$ident")"
  arn="$(jq -r '.Arn'     <<<"$ident")"

  # Organizations endpoint region selection
  local ORGREG; ORGREG="$(_pick_one "us-east-1" "Organizations endpoint region" "us-east-1" "us-gov-west-1" "cn-northwest-1")"

  # describe org
  local desc rc
  desc="$(aws organizations describe-organization --region "$ORGREG" --output json 2>&1)"; rc=$?
  if (( rc != 0 )); then
    if grep -qi 'AWSOrganizationsNotInUseException' <<<"$desc"; then
      _err "This account is not in an AWS Organization."; print -r -- "$desc" >&2; return 1
    elif grep -qi 'AccessDenied' <<<"$desc"; then
      _err "Access denied to Organizations. Use the management account."; print -r -- "$desc" >&2; return 1
    else
      _err "describe-organization failed on $ORGREG"; print -r -- "$desc" >&2; return 1
    fi
  fi

  # enforce management account
  local mgmtId orgId
  mgmtId="$(jq -r '.Organization.ManagementAccountId // .Organization.MasterAccountId' <<<"$desc")"
  orgId="$(jq -r '.Organization.Id' <<<"$desc")"
  if [[ "$acct" != "$mgmtId" ]]; then
    _err "Not the management account. mgmt=$mgmtId current=$acct"
    return 1
  fi

  # root info
  local roots_out rootId scp_enabled SCP_ACTIVE=0
  roots_out="$(aws organizations list-roots --region "$ORGREG" --output json 2>/dev/null)" || { _err "list-roots failed"; return 1; }
  rootId="$(jq -r '.Roots[0].Id' <<<"$roots_out")"
  scp_enabled="$(jq -r '.Roots[0].PolicyTypes[]? | select(.Type=="SERVICE_CONTROL_POLICY") | .Status' <<<"$roots_out")"
  [[ "$scp_enabled" == "ENABLED" ]] && SCP_ACTIVE=1

  print -P "Org: %F{244}$orgId%f   OrgRegion: %F{244}$ORGREG%f"
  print -P "Management: %F{244}$mgmtId%f   Caller: %F{244}$acct%f"
  print -P "Root: %F{244}$rootId%f   SCPs: %F{244}$([[ $SCP_ACTIVE -eq 1 ]] && print enabled || print disabled)%f"
  _hr

  # interactive choices
  local WANT_ALIAS REG_MODE MAX_DEPTH JSON_OUT ROLE
  WANT_ALIAS="$(_pick_one "yes" "Look up IAM account alias" "yes" "no")"
  if [[ "$WANT_ALIAS" == "yes" ]]; then
    ROLE="$(_pick_role)"
  else
    ROLE=""
  fi
  REG_MODE="$(_pick_one "enabled" "Regions to show" "enabled" "all")"
  MAX_DEPTH="$(_pick_one "unlimited" "Max OU depth" "unlimited" "0" "1" "2" "3")"
  JSON_OUT="$(_pick_json_path)"

  # caches
  typeset -gA _SCP_NAME=() _STS_AK=() _STS_SK=() _STS_ST=() _STS_EXP=()

  # SCP names
  if (( SCP_ACTIVE )); then
    local tok out
    while :; do
      if [[ -n "$tok" ]]; then
        out="$(aws organizations list-policies --region "$ORGREG" --filter SERVICE_CONTROL_POLICY --max-items 1000 --starting-token "$tok" --output json 2>/dev/null)" || break
      else
        out="$(aws organizations list-policies --region "$ORGREG" --filter SERVICE_CONTROL_POLICY --max-items 1000 --output json 2>/dev/null)" || break
      fi
      jq -r '.Policies[] | [.Id,.Name] | @tsv' <<<"$out" \
      | while IFS=$'\t' read -r id name; do _SCP_NAME[$id]="$name"; done
      tok="$(jq -r '.NextToken // empty' <<<"$out")"
      [[ -z "$tok" ]] && break
    done
  fi

  # org helpers
  _pol_names(){
    local json="$1"
    jq -r '(.Policies//[]) | map(.Id) | .[]?' <<<"$json" | while read -r pid; do
      local nm="${_SCP_NAME[$pid]-}"
      [[ -n "$nm" ]] && print -- "${nm} (${pid})" || print -- "$pid"
    done
  }
  _pol_list_for_target(){
    local tid="$1" tok out
    while :; do
      if [[ -n "$tok" ]]; then
        out="$(aws organizations list-policies-for-target --region "$ORGREG" --target-id "$tid" --filter SERVICE_CONTROL_POLICY --max-items 1000 --starting-token "$tok" --output json 2>/dev/null)" || break
      else
        out="$(aws organizations list-policies-for-target --region "$ORGREG" --target-id "$tid" --filter SERVICE_CONTROL_POLICY --max-items 1000 --output json 2>/dev/null)" || break
      fi
      print -r -- "$out"
      tok="$(jq -r '.NextPageToken // empty' <<<"$out")"
      [[ -z "$tok" ]] && break
    done | jq -s '{Policies:(map(.Policies//[])|add)}'
  }
  _list_child_ous(){
    local pid="$1" tok out
    while :; do
      if [[ -n "$tok" ]]; then
        out="$(aws organizations list-organizational-units-for-parent --region "$ORGREG" --parent-id "$pid" --max-items 1000 --starting-token "$tok" --output json 2>/dev/null)" || break
      else
        out="$(aws organizations list-organizational-units-for-parent --region "$ORGREG" --parent-id "$pid" --max-items 1000 --output json 2>/dev/null)" || break
      fi
      jq -c '.OrganizationalUnits[]?' <<<"$out"
      tok="$(jq -r '.NextToken // empty' <<<"$out")"
      [[ -z "$tok" ]] && break
    done
  }
  _list_child_accounts(){
    local pid="$1" tok out
    while :; do
      if [[ -n "$tok" ]]; then
        out="$(aws organizations list-accounts-for-parent --region "$ORGREG" --parent-id "$pid" --max-items 1000 --starting-token "$tok" --output json 2>/dev/null)" || break
      else
        out="$(aws organizations list-accounts-for-parent --region "$ORGREG" --parent-id "$pid" --max-items 1000 --output json 2>/dev/null)" || break
      fi
      jq -c '.Accounts[]?' <<<"$out"
      tok="$(jq -r '.NextToken // empty' <<<"$out")"
      [[ -z "$tok" ]] && break
    done
  }

  # per account helpers
  _sts_for_acct(){
    local acct="$1" role="$2" now; now=$(date +%s)
    if [[ -n "${_STS_EXP[$acct]-}" && $now -lt ${_STS_EXP[$acct]} ]]; then
      print -r -- "${_STS_AK[$acct]}|${_STS_SK[$acct]}|${_STS_ST[$acct]}"; return 0
    fi
    local cred
    cred="$(aws sts assume-role --role-arn "arn:aws:iam::${acct}:role/${role}" --role-session-name "orgmap-${acct}" --output json 2>/dev/null)" || return 1
    _STS_AK[$acct]="$(jq -r '.Credentials.AccessKeyId'     <<<"$cred")"
    _STS_SK[$acct]="$(jq -r '.Credentials.SecretAccessKey' <<<"$cred")"
    _STS_ST[$acct]="$(jq -r '.Credentials.SessionToken'    <<<"$cred")"
    _STS_EXP[$acct]="$(date -d "$(jq -r '.Credentials.Expiration' <<<"$cred")" +%s 2>/dev/null || echo $(( $(date +%s)+300 )))"
    print -r -- "${_STS_AK[$acct]}|${_STS_SK[$acct]}|${_STS_ST[$acct]}"
  }
  _acct_alias(){
    local acct="$1"
    [[ "$WANT_ALIAS" != "yes" || -z "$ROLE" ]] && { print -r ""; return 0; }
    local trip; if ! trip="$(_sts_for_acct "$acct" "$ROLE")"; then print -r ""; return 0; fi
    local ak="${trip%%|*}"; local rest="${trip#*|}"; local sk="${rest%%|*}"; local st="${rest#*|}"
    local out; out="$(AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_SESSION_TOKEN="$st" aws iam list-account-aliases --output json 2>/dev/null)" || { print -r ""; return 0; }
    jq -r '(.AccountAliases//[])[0] // ""' <<<"$out"
  }
  _acct_regions(){
    local acct="$1" mode="$2" out
    if [[ "$mode" == "all" ]]; then
      out="$(aws account list-regions --region "$ORGREG" --account-id "$acct" --output json 2>/dev/null)" || { print -r ""; return 0; }
      jq -r '.Regions[] | .RegionName+" ("+.RegionOptStatus+")"' <<<"$out"
    else
      out="$(aws account list-regions --region "$ORGREG" --account-id "$acct" --region-opt-status-contains ENABLED ENABLED_BY_DEFAULT --output json 2>/dev/null)" || { print -r ""; return 0; }
      jq -r '.Regions[] | .RegionName' <<<"$out"
    fi
  }

  # optional JSON sink
  local json_tmp=""; [[ -n "$JSON_OUT" ]] && json_tmp="$(mktemp)" && : > "$json_tmp"
  _json_emit(){ [[ -z "$JSON_OUT" ]] || print -r -- "$1" >> "$json_tmp"; }

  # walker
  local IND="  "
  local depth_limit; [[ "$MAX_DEPTH" == "unlimited" ]] && depth_limit=-1 || depth_limit="$MAX_DEPTH"

  _walk(){
    local parent="$1" depth="$2" inh_json="$3" path="$4"
    local direct_pols='{"Policies":[]}'
    if (( SCP_ACTIVE )); then
      direct_pols="$(_pol_list_for_target "$parent" 2>/dev/null || printf '{"Policies":[]}')"
    fi
    local eff_ids; eff_ids="$(jq -n --argjson a "$inh_json" --argjson b "$direct_pols" '{Policies: ((($a.Policies//[])+($b.Policies//[]))|unique)}')"

    # OUs
    local ou
    while read -r ou; do
      [[ -z "$ou" ]] && continue
      local ouId ouName; ouId="$(jq -r '.Id' <<<"$ou")"; ouName="$(jq -r '.Name' <<<"$ou")"
      printf "%s%F{6}OU%f %F{4}%s%f  %F{244}(%s)%f\n" "$IND" "$ouName" "$ouId"
      if (( SCP_ACTIVE )); then
        local dnames; dnames="$(_pol_names "$(_pol_list_for_target "$ouId")")"
        [[ -n "$dnames" ]] && printf "%s  SCPs: %s\n" "$IND" "$(print -r -- "$dnames" | paste -sd ', ' -)"
      fi
      _json_emit "$(jq -n --arg id "$ouId" --arg name "$ouName" --arg type "OU" --arg path "$path/$ouName" \
        --argjson direct "$(_pol_list_for_target "$ouId")" --argjson inherited "$eff_ids" \
        '{type:$type,id:$id,name:$name,path:$path,scpDirect:direct.Policies,scpInherited:inherited.Policies}')"

      if (( depth_limit < 0 || depth < depth_limit )); then
        _walk "$ouId" "$((depth+1))" "$eff_ids" "$path/$ouName"
      fi
    done < <(_list_child_ous "$parent")

    # Accounts
    local row
    while read -r row; do
      [[ -z "$row" ]] && continue
      local id name email status alias regions pols eff_all=""
      id="$(jq -r '.Id' <<<"$row")"
      name="$(jq -r '.Name' <<<"$row")"
      email="$(jq -r '.Email' <<<"$row")"
      status="$(jq -r '.Status' <<<"$row")"
      alias="$(_acct_alias "$id")"
      if [[ "$REG_MODE" == "all" ]]; then regions="$(_acct_regions "$id" all)"; else regions="$(_acct_regions "$id" enabled)"; fi
      if (( SCP_ACTIVE )); then
        pols="$(_pol_list_for_target "$id")"
        eff_all="$(jq -n --argjson a "$eff_ids" --argjson b "$pols" '{Policies:((($a.Policies//[])+($b.Policies//[]))|unique)}')"
      fi

      printf "%s%F{2}Account%f %F{4}%s%f  %F{244}(%s)%f\n" "$IND" "$name" "$id"
      [[ -n "$alias" ]]   && printf "%s  Alias: %s\n" "$IND" "$alias"
      printf "%s  Email: %s   Status: %s\n" "$IND" "$email" "$status"
      if [[ -n "$regions" ]]; then
        if [[ "$REG_MODE" == "all" ]]; then
          printf "%s  Regions: %s\n" "$IND" "$(print -r -- "$regions" | paste -sd ', ' -)"
        else
          printf "%s  Regions (enabled): %s\n" "$IND" "$(print -r -- "$regions" | paste -sd ', ' -)"
        fi
      else
        printf "%s  Regions: %s\n" "$IND" "n/a"
      fi
      if (( SCP_ACTIVE )); then
        local dnames enames
        dnames="$(_pol_names "$pols")"
        enames="$(_pol_names "$eff_all")"
        [[ -n "$dnames" ]] && printf "%s  SCPs (direct): %s\n" "$IND" "$(print -r -- "$dnames" | paste -sd ', ' -)"
        [[ -n "$enames" ]] && printf "%s  SCPs (effective): %s\n" "$IND" "$(print -r -- "$enames" | paste -sd ', ' -)"
      fi

      _json_emit "$(jq -n \
        --arg type "ACCOUNT" --arg id "$id" --arg name "$name" --arg email "$email" --arg status "$status" \
        --arg path "$path/$name" --arg alias "$alias" \
        --arg regMode "$REG_MODE" --argjson regions "$(jq -R -s 'split("\n")|map(select(.!=""))' <<<"$regions")" \
        --argjson scpDirect "${pols:-{\"Policies\":[]}}" --argjson scpEff "${eff_all:-{\"Policies\":[]}}" \
        '{type:$type,id:$id,name:$name,email:$email,status:$status,path:$path,alias:$alias,
          regions:{mode:$regMode,values:$regions}, scpDirect:scpDirect.Policies, scpEffective:scpEff.Policies}')"
    done < <(_list_child_accounts "$parent")
  }

  # root SCPs line
  if (( SCP_ACTIVE )); then
    local root_direct rnames
    root_direct="$(_pol_list_for_target "$rootId")"
    rnames="$(_pol_names "$root_direct")"
    [[ -n "$rnames" ]] && print -P "Root SCPs: %F{244}$(print -r -- "$rnames" | paste -sd ', ' -)%f"
  fi

  # walk
  _walk "$rootId" 0 '{"Policies":[]}' "/"

  # finalize JSON
  if [[ -n "$JSON_OUT" ]]; then
    jq -s '.' "$json_tmp" > "$JSON_OUT" 2>/dev/null || { _warn "failed to write JSON"; :; }
    rm -f -- "$json_tmp"
    _note "JSON written to $JSON_OUT"
  fi
}

