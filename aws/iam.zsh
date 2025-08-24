# ---------- iamwho ----------
iamwho() {
  emulate -L zsh
  setopt pipefail

  _s3_need aws || return 1
  _s3_need jq  || return 1

  local ident acct user arn
  ident="$(aws sts get-caller-identity --output json 2>/dev/null)" || { _err "failed sts get-caller-identity"; return 1; }
  acct="$(jq -r '.Account' <<<"$ident")"
  user="$(jq -r '.UserId' <<<"$ident")"
  arn="$(jq -r '.Arn' <<<"$ident")"

  _hr
  print -P "%F{6}IAM Identity%f"
  print -P "  %F{4}Account:%f $acct"
  print -P "  %F{4}UserId:%f  $user"
  print -P "  %F{4}ARN:%f     $arn"
  _hr

  local uname
  if [[ "$arn" == *":user/"* ]]; then
    uname="${arn##*/}"
  else
    uname="" # could be assumed role
  fi

  if [[ -z "$uname" ]]; then
    _warn "ARN not a direct user (may be role/session). Skipping group/policy lookup."
    return 0
  fi

  # groups
  local groups
  groups="$(aws iam list-groups-for-user --user-name "$uname" --output json 2>/dev/null \
            | jq -r '.Groups[]? | .GroupName')" || groups=""
  if [[ -z "$groups" ]]; then
    _note "No groups attached to user $uname"
  else
    print -P "%F{6}Groups for $uname%f"
    print -P "  $groups" | sed 's/^/  - /'
  fi

  # inline and attached policies
  local attached
  attached="$(aws iam list-attached-user-policies --user-name "$uname" --output json 2>/dev/null \
              | jq -r '.AttachedPolicies[]? | .PolicyName')" || attached=""
  local inline
  inline="$(aws iam list-user-policies --user-name "$uname" --output json 2>/dev/null \
             | jq -r '.PolicyNames[]?')" || inline=""

  if [[ -z "$attached$inline" ]]; then
    _note "No policies directly attached to $uname"
  else
    print -P "%F{6}Policies for $uname%f"
    [[ -n "$attached" ]] && {
      print -P "  %F{4}Attached:%f"
      print -P "$attached" | sed 's/^/    - /'
    }
    [[ -n "$inline" ]] && {
      print -P "  %F{4}Inline:%f"
      print -P "$inline" | sed 's/^/    - /'
    }
  fi
  _hr
}

