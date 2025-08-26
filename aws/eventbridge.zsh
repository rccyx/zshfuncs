# =====================================================================
# eventbridge.zsh — Elite EventBridge / Scheduler / Pipes CLI + UI
# Deps: awscli v2, jq; optional: fzf, $EDITOR
# Safe defaults: read-heavy; destructive ops require explicit confirm
# Provides top-level UI: eb.ui
# =====================================================================

# ---- UI helpers (reuse globals if present) ----
if ! typeset -f _ok   >/dev/null; then _ok(){   print -P "%F{2}✔%f $*"; } fi
if ! typeset -f _note >/dev/null; then _note(){ print -P "%F{4}ℹ️ %f $*"; } fi
if ! typeset -f _warn >/dev/null; then _warn(){ print -P "%F{3}‼%f $*"; } fi
if ! typeset -f _err  >/dev/null; then _err(){  print -P "%F{1}✖%f $*"; } fi
_eb_hr(){ print -P "%F{244}$(printf '%*s' 64 '' | tr ' ' '-')%f"; }

# ---- knobs ----
: ${EB_DEFAULT_REGION:=${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}}}
: ${EB_DEFAULT_BUS:=default}
: ${EB_EDITOR:=${EDITOR:-vi}}
: ${EB_UI_HEIGHT:=80%}

# ---- checks & utils ----
_eb_need(){ command -v "$1" >/dev/null 2>&1 || { _err "missing dep: $1"; return 1; } }
_eb_check(){ _eb_need aws || return 1; _eb_need jq || return 1; aws sts get-caller-identity >/dev/null 2>&1 || { _err "AWS creds not working"; return 1; } }
_eb_has_fzf(){ command -v fzf >/dev/null 2>&1 }
_eb_jx(){ local out; if out="$("$@" --output json 2>/dev/null)"; then printf "%s" "$out"; else printf ""; fi; }
_eb_ctx(){
  local a p r b; a="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
  p="${AWS_PROFILE:-default}"; r="$EB_DEFAULT_REGION"; b="$EB_DEFAULT_BUS"
  print -P "%F{6}EVENTBRIDGE%f acct=%F{244}${a}%f profile=%F{244}${p}%f region=%F{244}${r}%f bus=%F{244}${b}%f"
}
_eb_confirm(){ local msg="$1" exp="${2:-DELETE}"; print -n "$msg "; local a; read -r a; [[ "$a" == "$exp" ]] }
_eb_edit_json(){
  local tmp; tmp="$(mktemp)"; print -rn -- "${1:-{}}" > "$tmp"
  ${=EB_EDITOR} "$tmp" </dev/tty >/dev/tty 2>/dev/tty || true
  cat -- "$tmp"
  rm -f -- "$tmp"
}

# ---- pickers ----
_eb_pick_bus(){
  emulate -L zsh; setopt pipefail
  local rows tok out
  while :; do
    [[ -n "$tok" ]] && out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-event-buses --max-results 100 --next-token "$tok")" \
                    || out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-event-buses --max-results 100)"
    [[ -z "$out" ]] && break
    rows+="$(
      jq -r '.EventBuses[]? | [.Name, .Arn] | @tsv' <<<"$out"
    )"$'\n'
    tok="$(jq -r '.NextToken // empty' <<<"$out")"
    [[ -z "$tok" ]] && break
  done
  rows="$(print -r -- "$rows" | sed '/^$/d')"
  [[ -z "$rows" ]] && { print -r -- "$EB_DEFAULT_BUS"; return 0; }

  if _eb_has_fzf; then
    print -r -- "$rows" \
      | awk -F'\t' '{printf "%-32s\t%s\n",$1,$2}' \
      | fzf --with-nth=1 --delimiter=$'\t' --prompt="Event bus ⇢ " --height="$EB_UI_HEIGHT" \
      | awk -F'\t' '{print $1}'
  else
    print -P "Event bus [${EB_DEFAULT_BUS}]: " | tr -d '\n'; local n; read -r n; print -r -- "${n:-$EB_DEFAULT_BUS}"
  fi
}

_eb_pick_rule(){
  emulate -L zsh; setopt pipefail
  local bus="${1:-$EB_DEFAULT_BUS}" tok out rows=""
  while :; do
    [[ -n "$tok" ]] && out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-rules --event-bus-name "$bus" --max-results 100 --next-token "$tok")" \
                    || out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-rules --event-bus-name "$bus" --max-results 100)"
    [[ -z "$out" ]] && break
    rows+="$(
      jq -r '.Rules[]? | [.Name, (.State//""), (.ScheduleExpression//"pattern"), (.Description//"")] | @tsv' <<<"$out"
    )"$'\n'
    tok="$(jq -r '.NextToken // empty' <<<"$out")"
    [[ -z "$tok" ]] && break
  done
  rows="$(print -r -- "$rows" | sed '/^$/d')"
  [[ -z "$rows" ]] && { _warn "no rules on bus: $bus"; return 1; }

  if _eb_has_fzf; then
    print -r -- "$rows" \
    | awk -F'\t' '{printf "%-48s  %-8s  %-20s  %s\n",$1,$2,$3,$4}' \
    | fzf --prompt="Rule ⇢ " --height="$EB_UI_HEIGHT" --no-multi \
    | awk '{print $1}'
  else
    print -P "Rule name: " | tr -d '\n'; local r; read -r r; print -r -- "$r"
  fi
}

# ---- context ----
eb.ctx(){ _eb_check || return 1; _eb_hr; _eb_ctx; _eb_hr; }

# ---- buses ----
eb.bus.ls(){
  _eb_check || return 1
  local rows; rows="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-event-buses)"
  [[ -z "$rows" ]] && { _warn "no buses"; return 0; }
  jq -r '.EventBuses[] | [.Name, .Arn] | @tsv' <<<"$rows" \
  | awk -F'\t' '{printf "%-28s  %s\n",$1,$2}'
}
eb.bus.create(){
  _eb_check || return 1
  print -n "Bus name: "; local n; read -r n; [[ -z "$n" ]] && { _err "name required"; return 2; }
  aws --region "$EB_DEFAULT_REGION" events create-event-bus --name "$n" >/dev/null && _ok "created bus $n"
}
eb.bus.rm(){
  _eb_check || return 1
  local b; b="$(_eb_pick_bus)"; [[ -z "$b" ]] && return 1
  _eb_confirm "Type the bus name '$b' to confirm deletion:" "$b" || { _warn "aborted"; return 1; }
  aws --region "$EB_DEFAULT_REGION" events delete-event-bus --name "$b" >/dev/null && _ok "deleted bus $b"
}
eb.bus.policy.get(){
  _eb_check || return 1
  local b; b="$(_eb_pick_bus)"; aws --region "$EB_DEFAULT_REGION" events describe-event-bus --name "$b" | jq -r '.Policy // "no policy"'
}
eb.bus.policy.put(){
  _eb_check || return 1
  local b; b="$(_eb_pick_bus)"
  _note "Edit resource policy JSON (allows cross-account put, etc.)"
  local pol; pol="$(_eb_edit_json '{"Version":"2012-10-17","Statement":[{"Sid":"allow-one","Effect":"Allow","Principal":{"AWS":"111111111111"},"Action":"events:PutEvents","Resource":"*"}] }')" || return 1
  aws --region "$EB_DEFAULT_REGION" events put-permission --event-bus-name "$b" --policy "$pol" >/dev/null && _ok "policy attached"
}
eb.bus.policy.rm(){
  _eb_check || return 1
  local b; b="$(_eb_pick_bus)"; print -n "StatementId to remove: "; local sid; read -r sid
  aws --region "$EB_DEFAULT_REGION" events remove-permission --event-bus-name "$b" --statement-id "$sid" >/dev/null && _ok "policy statement removed"
}

# ---- rules ----
eb.rule.ls(){
  _eb_check || return 1
  local bus="${1:-$EB_DEFAULT_BUS}" tok out
  _eb_hr; print -P "%F{6}Rules%f  bus=%F{244}${bus}%f"; _eb_hr
  while :; do
    [[ -n "$tok" ]] && out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-rules --event-bus-name "$bus" --max-results 100 --next-token "$tok")" \
                    || out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-rules --event-bus-name "$bus" --max-results 100)"
    [[ -z "$out" ]] && break
    jq -r '.Rules[] | [.Name, .State, (.ScheduleExpression//"pattern"), (.Description//"")] | @tsv' <<<"$out" \
    | awk -F'\t' '{printf "%-48s  %-8s  %-12s  %s\n",$1,$2,$3,$4}'
    tok="$(jq -r '.NextToken // empty' <<<"$out")"
    [[ -z "$tok" ]] && break
  done
}

eb.rule.new(){
  emulate -L zsh; setopt pipefail
  _eb_check || return 1
  local bus name kind desc state="ENABLED"
  bus="$(_eb_pick_bus)"
  print -n "Rule name: "; read -r name
  [[ -z "$name" ]] && { _err "name required"; return 2; }
  if _eb_has_fzf; then
    kind="$(printf "event-pattern\nschedule\n" | fzf --prompt="Rule type ⇢ " --height=30%)"
  else
    print -n "Rule type [event-pattern|schedule]: "; read -r kind
  fi
  print -n "Description (optional): "; read -r desc
  print -n "State [ENABLED|DISABLED] (default ENABLED): "; read -r s; [[ -n "$s" ]] && state="$s"

  local putargs=(--region "$EB_DEFAULT_REGION" events put-rule --name "$name" --event-bus-name "$bus" --state "$state")
  if [[ "$kind" == "schedule" ]]; then
    print -n "Schedule expression (rate(...) or cron(...)): "; local expr; read -r expr
    [[ -n "$desc" ]] && putargs+=(--description "$desc")
    putargs+=(--schedule-expression "$expr")
  else
    _note "Edit event pattern JSON (default shown)"
    local patt; patt="$(_eb_edit_json '{"source":["app.example"],"detail-type":["sample"]}')" || patt="{}"
    [[ -n "$desc" ]] && putargs+=(--description "$desc")
    putargs+=(--event-pattern "$patt")
  fi

  local out; out="$("${(@)putargs}" 2>&1)"; local rc=$?
  (( rc == 0 )) && _ok "rule created: $name on $bus" || { print -r -- "$out" >&2; return $rc; }

  print -n "Add a target now? [y/N]: "; local a; read -r a
  [[ "$a" =~ ^[Yy]$ ]] && eb.target.add "$bus" "$name"
}

eb.rule.set(){
  emulate -L zsh; setopt pipefail
  _eb_check || return 1
  local bus rule; bus="$(_eb_pick_bus)"; rule="$(_eb_pick_rule "$bus")" || return 1
  if _eb_has_fzf; then
    local which; which="$(printf "state\ndescription\nevent-pattern\nschedule-expression\n" | fzf --prompt="Update ⇢ " --height=40%)" || return 0
    case "$which" in
      state)
        print -n "State [ENABLED|DISABLED]: "; local st; read -r st
        case "$st" in
          ENABLED)  aws --region "$EB_DEFAULT_REGION" events enable-rule  --event-bus-name "$bus" --name "$rule" >/dev/null && _ok "enabled";;
          DISABLED) aws --region "$EB_DEFAULT_REGION" events disable-rule --event-bus-name "$bus" --name "$rule" >/dev/null && _ok "disabled";;
          *) _warn "no change";;
        esac
        ;;
      description)
        print -n "New description: "; local d; read -r d
        aws --region "$EB_DEFAULT_REGION" events put-rule --event-bus-name "$bus" --name "$rule" --description "$d" >/dev/null && _ok "description updated"
        ;;
      event-pattern)
        _note "Edit pattern JSON"
        local patt; patt="$(_eb_edit_json "{}")"
        aws --region "$EB_DEFAULT_REGION" events put-rule --event-bus-name "$bus" --name "$rule" --event-pattern "$patt" >/dev/null && _ok "pattern updated"
        ;;
      schedule-expression)
        print -n "New schedule expr: "; local ex; read -r ex
        aws --region "$EB_DEFAULT_REGION" events put-rule --event-bus-name "$bus" --name "$rule" --schedule-expression "$ex" >/dev/null && _ok "schedule updated"
        ;;
    esac
  else
    _warn "non-fzf mode: use eb.rule.new / eb.rule.enable / eb.rule.disable"
  fi
}

eb.rule.enable(){ _eb_check || return 1; local b r; b="$(_eb_pick_bus)"; r="$(_eb_pick_rule "$b")" || return 1; aws --region "$EB_DEFAULT_REGION" events enable-rule --event-bus-name "$b" --name "$r" && _ok "enabled $r"; }
eb.rule.disable(){ _eb_check || return 1; local b r; b="$(_eb_pick_bus)"; r="$(_eb_pick_rule "$b")" || return 1; aws --region "$EB_DEFAULT_REGION" events disable-rule --event-bus-name "$b" --name "$r" && _ok "disabled $r"; }

eb.rule.rm(){
  _eb_check || return 1
  local b r; b="$(_eb_pick_bus)"; r="$(_eb_pick_rule "$b")" || return 1
  _eb_confirm "Type DELETE to remove rule '$r' (targets removed too):" DELETE || { _warn "aborted"; return 1; }
  local ids; ids="$(aws --region "$EB_DEFAULT_REGION" events list-targets-by-rule --event-bus-name "$b" --rule "$r" --query 'Targets[].Id' --output text 2>/dev/null)"
  if [[ -n "$ids" ]]; then
    aws --region "$EB_DEFAULT_REGION" events remove-targets --event-bus-name "$b" --rule "$r" --ids ${=ids} >/dev/null || true
  fi
  aws --region "$EB_DEFAULT_REGION" events delete-rule --event-bus-name "$b" --name "$r" >/dev/null && _ok "deleted $r"
}

# ---- targets ----
eb.target.ls(){
  _eb_check || return 1
  local bus; bus="$(_eb_pick_bus)"
  local rule; rule="$(_eb_pick_rule "$bus")" || return 1
  local out; out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-targets-by-rule --event-bus-name "$bus" --rule "$rule")"
  [[ -z "$out" ]] && { _warn "no targets or not visible"; return 0; }
  _eb_hr; print -P "%F{6}Targets%f  bus=%F{244}${bus}%f rule=%F{244}${rule}%f"; _eb_hr
  jq -r '.Targets[] | [.Id, .Arn, ( .DeadLetterConfig.Arn // "" ), ( .RetryPolicy.MaximumRetryAttempts // 0 )] | @tsv' <<<"$out" \
  | awk -F'\t' '{printf "%-24s  %-80s  DLQ=%-36s  retries=%s\n",$1,$2,$3,$4}'
}

eb.target.add(){
  emulate -L zsh; setopt pipefail
  _eb_check || return 1
  local bus="${1:-$(_eb_pick_bus)}" rule="${2:-$(_eb_pick_rule "$bus")}"
  [[ -z "$bus" || -z "$rule" ]] && return 2
  print -n "Target ARN (Lambda/SNS/SQS/Kinesis/StepFunctions/Bus/API Dest): "; local arn; read -r arn
  [[ -z "$arn" ]] && { _err "target arn required"; return 2; }
  print -n "Target Id (auto if empty): "; local tid; read -r tid; [[ -z "$tid" ]] && tid="t-$(date +%s)"
  print -n "RoleArn for target (optional): "; local role; read -r role
  print -n "Static Input JSON (leave empty to use InputTransformer): "; local in; read -r in

  local tmp tf; tmp="$(mktemp)"
  if [[ -z "$in" ]]; then
    _note "Edit InputTransformer JSON. Example:
{ \"InputPathsMap\": { \"detail\":\"$.detail\" }, \"InputTemplate\": \"<detail>\" }"
    tf="$(_eb_edit_json '{"InputPathsMap":{"detail":"$.detail"},"InputTemplate":"<detail>"}')"
    jq -n --arg id "$tid" --arg arn "$arn" --arg role "$role" --argjson tx "$tf" '
      [{Id:$id, Arn:$arn} + ( $role|length>0 ? {RoleArn:$role} : {} ) + {InputTransformer: $tx}]' > "$tmp"
  else
    jq -n --arg id "$tid" --arg arn "$arn" --arg role "$role" --argjson input "$in" '
      [{Id:$id, Arn:$arn} + ( $role|length>0 ? {RoleArn:$role} : {} ) + {Input:($input|tojson)}]' > "$tmp"
  fi

  aws --region "$EB_DEFAULT_REGION" events put-targets --event-bus-name "$bus" --rule "$rule" --targets "file://$tmp" >/dev/null \
    && _ok "target added: $tid → $arn" || _err "failed to add target"
  rm -f -- "$tmp"
}

eb.target.rm(){
  _eb_check || return 1
  local bus; bus="$(_eb_pick_bus)"
  local rule; rule="$(_eb_pick_rule "$bus")" || return 1
  local out; out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-targets-by-rule --event-bus-name "$bus" --rule "$rule")"
  [[ -z "$out" ]] && { _warn "no targets"; return 0; }
  local ids
  if _eb_has_fzf; then
    ids="$(
      jq -r '.Targets[] | [.Id, .Arn] | @tsv' <<<"$out" \
      | fzf --multi --with-nth=1 --delimiter=$'\t' --prompt="remove target(s) ⇢ " --height="$EB_UI_HEIGHT" \
      | awk -F'\t' '{print $1}'
    )"
  else
    print -n "Target Id to remove: "; read -r ids
  fi
  [[ -z "$ids" ]] && { _warn "nothing chosen"; return 1; }
  _eb_confirm "Type DELETE to remove selected target(s):" DELETE || { _warn "aborted"; return 1; }
  aws --region "$EB_DEFAULT_REGION" events remove-targets --event-bus-name "$bus" --rule "$rule" --ids ${=ids} >/dev/null && _ok "removed"
}

# ---- put/test events ----
eb.event.put(){
  _eb_check || return 1
  local bus; bus="$(_eb_pick_bus)"
  print -n "source (e.g. app.core): "; local src; read -r src
  print -n "detail-type (e.g. OrderCreated): "; local dty; read -r dty
  _note "Edit event detail JSON; saves on exit"
  local detail; detail="$(_eb_edit_json '{"orderId":"123","amount":99.99}')" || detail="{}"

  local tmp; tmp="$(mktemp)"
  jq -nc --arg bus "$bus" --arg src "$src" --arg dt "$dty" --argjson det "$detail" \
    '[{EventBusName:$bus, Source:$src, DetailType:$dt, Detail:($det|tostring)}]' > "$tmp"

  aws --region "$EB_DEFAULT_REGION" events put-events --entries "file://$tmp" >/dev/null \
    && _ok "event sent" || _err "put failed"
  rm -f "$tmp"
}

eb.pattern.test(){
  _eb_check || return 1
  _note "Edit PATTERN (left), then EVENT (right) sequentially"
  local patt; patt="$(_eb_edit_json '{"detail-type":["OrderCreated"],"source":["app.core"]}')" || patt="{}"
  local ev;   ev="$(_eb_edit_json '{"source":"app.core","detail-type":"OrderCreated","detail":{"x":1}}')" || ev="{}"
  aws --region "$EB_DEFAULT_REGION" events test-event-pattern --event-pattern "$patt" --event "$ev" >/dev/null \
   && _ok "MATCH" || _warn "NO MATCH (or error)"
}

# ---- archives / replays ----
eb.archive.ls(){
  _eb_check || return 1
  local tok out; while :; do
    [[ -n "$tok" ]] && out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-archives --max-results 100 --next-token "$tok")" \
                    || out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-archives --max-results 100)"
    [[ -z "$out" ]] && break
    jq -r '.Archives[] | [.ArchiveName, .EventSourceArn, .State, (.RetentionDays|tostring)] | @tsv' <<<"$out" \
      | awk -F'\t' '{printf "%-32s  %-60s  %-12s  %sd\n",$1,$2,$3,$4}'
    tok="$(jq -r '.NextToken // empty' <<<"$out")"
    [[ -z "$tok" ]] && break
  done
}
eb.archive.create(){
  _eb_check || return 1
  local b; b="$(_eb_pick_bus)"; print -n "Archive name: "; local an; read -r an
  print -n "Retention days [0..3650] (0=forever, default 365): "; local d; read -r d; [[ -z "$d" ]] && d=365
  local arn; arn="$(aws --region "$EB_DEFAULT_REGION" events describe-event-bus --name "$b" --query 'Arn' --output text 2>/dev/null)"
  aws --region "$EB_DEFAULT_REGION" events create-archive --archive-name "$an" --retention-days "$d" --event-source-arn "$arn" >/dev/null && _ok "archive created"
}
eb.replay.ls(){
  _eb_check || return 1
  local out; out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" events list-replays)"
  jq -r '.Replays[]? | [.ReplayName, .State, .EventStartTime, .EventEndTime] | @tsv' <<<"$out" \
  | awk -F'\t' '{printf "%-28s  %-10s  %s → %s\n",$1,$2,$3,$4}'
}
eb.replay.start(){
  _eb_check || return 1
  print -n "Replay name: "; local rn; read -r rn
  print -n "Archive name: "; local an; read -r an
  print -n "Start time (RFC3339, e.g. 2025-08-01T00:00:00Z): "; local s; read -r s
  print -n "End time (RFC3339): "; local e; read -r e
  local b; b="$(_eb_pick_bus)"
  local archArn busArn
  archArn="$(aws --region "$EB_DEFAULT_REGION" events describe-archive --archive-name "$an" --query 'ArchiveArn' --output text 2>/dev/null)"
  busArn="$(aws --region "$EB_DEFAULT_REGION" events describe-event-bus --name "$b" --query 'Arn' --output text 2>/dev/null)"
  aws --region "$EB_DEFAULT_REGION" events start-replay \
    --replay-name "$rn" \
    --event-source-arn "$archArn" \
    --destination "Arn=${busArn}" \
    --event-start-time "$s" --event-end-time "$e" >/dev/null && _ok "replay started"
}
eb.replay.cancel(){ _eb_check || return 1; print -n "Replay name: "; local rn; read -r rn; aws --region "$EB_DEFAULT_REGION" events cancel-replay --replay-name "$rn" >/dev/null && _ok "replay canceled"; }

# ---- Pipes (source→target, IAM role required) ----
eb.pipes.ls(){
  _eb_check || return 1
  local tok out; while :; do
    [[ -n "$tok" ]] && out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" pipes list-pipes --max-results 100 --next-token "$tok")" \
                    || out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" pipes list-pipes --max-results 100)"
    [[ -z "$out" ]] && break
    jq -r '.Pipes[] | [.Name, .DesiredState, .CurrentState, .Source, .Target] | @tsv' <<<"$out" \
    | awk -F'\t' '{printf "%-36s  %-10s (%-10s)  %-48s  %-48s\n",$1,$2,$3,$4,$5}'
    tok="$(jq -r '.NextToken // empty' <<<"$out")"; [[ -z "$tok" ]] && break
  done
}
eb.pipes.create(){
  _eb_check || return 1
  print -n "Pipe name: "; local name; read -r name
  print -n "Source ARN (SQS/Kinesis/Dynamo stream/EventBridge): "; local src; read -r src
  print -n "Target ARN (Lambda/SQS/SNS/StepFunctions/HTTP dest/etc.): "; local tgt; read -r tgt
  print -n "RoleArn (execution role for pipe): "; local role; read -r role
  print -n "Desired state [RUNNING|STOPPED] (default RUNNING): "; local st; read -r st; [[ -z "$st" ]] && st="RUNNING"

  print -n "Add filter criteria? [y/N]: "; local af; read -r af
  local sp=""; if [[ "$af" =~ ^[Yy]$ ]]; then
    _note "Edit FilterCriteria JSON. Example:
{ \"Filters\": [ { \"Pattern\": \"{ \\\"detail-type\\\": [\\\"OrderCreated\\\"] }\" } ] }"
    sp="$(mktemp)"; _eb_edit_json '{"Filters":[{"Pattern":"{\"detail-type\":[\"OrderCreated\"]}"}]}' > "$sp"
  fi

  print -n "Add target InputTemplate? [y/N]: "; local it; read -r it
  local tp=""; if [[ "$it" =~ ^[Yy]$ ]]; then
    tp="$(mktemp)"
    cat > "$tp" <<'JSON'
{ "InputTemplate": "{\"time\":\"<time>\",\"detail\":<detail>}" }
JSON
  fi

  local args=(--region "$EB_DEFAULT_REGION" pipes create-pipe --name "$name" --source "$src" --target "$tgt" --role-arn "$role" --desired-state "$st")
  [[ -n "$sp" ]] && args+=(--source-parameters "file://$sp")
  [[ -n "$tp" ]] && args+=(--target-parameters "file://$tp")

  "${(@)args}" >/dev/null && _ok "pipe created: $name" || _err "create failed"
  [[ -n "$sp" ]] && rm -f -- "$sp"
  [[ -n "$tp" ]] && rm -f -- "$tp"
}
eb.pipes.rm(){ _eb_check || return 1; print -n "Pipe name: "; local n; read -r n; _eb_confirm "Type DELETE to remove pipe '$n':" DELETE || { _warn "aborted"; return 1; }; aws --region "$EB_DEFAULT_REGION" pipes delete-pipe --name "$n" >/dev/null && _ok "deleted" }
eb.pipes.start(){ _eb_check || return 1; print -n "Pipe name: "; local n; read -r n; aws --region "$EB_DEFAULT_REGION" pipes start-pipe --name "$n" >/dev/null && _ok "started"; }
eb.pipes.stop(){  _eb_check || return 1; print -n "Pipe name: "; local n; read -r n; aws --region "$EB_DEFAULT_REGION" pipes stop-pipe  --name "$n" >/dev/null && _ok "stopped"; }

# ---- EventBridge Scheduler (v2) ----
sch.ls(){
  _eb_check || return 1
  local tok out; while :; do
    [[ -n "$tok" ]] && out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" scheduler list-schedules --max-results 100 --next-token "$tok")" \
                    || out="$(_eb_jx aws --region "$EB_DEFAULT_REGION" scheduler list-schedules --max-results 100)"
    [[ -z "$out" ]] && break
    jq -r '.Schedules[] | [.Name, .State, .ScheduleExpression, (.Target.Arn//""), (.FlexibleTimeWindow.Mode//"OFF")] | @tsv' <<<"$out" \
    | awk -F'\t' '{printf "%-40s  %-8s  %-28s  %-48s  flex=%s\n",$1,$2,$3,$4,$5}'
    tok="$(jq -r '.NextToken // empty' <<<"$out")"; [[ -z "$tok" ]] && break
  done
}
sch.create(){
  _eb_check || return 1
  print -n "Schedule name: "; local n; read -r n
  print -n "Schedule expr (rate|cron|at): "; local ex; read -r ex
  print -n "Target Arn (Lambda/SQS/SNS/StepFunctions/Bus): "; local ta; read -r ta
  print -n "RoleArn (scheduler invokes target): "; local ra; read -r ra
  _note "Edit Target Input JSON"; local inp; inp="$(_eb_edit_json '{"ping":"pong"}')"

  local tgt; tgt="$(mktemp)"
  jq -n --arg arn "$ta" --arg role "$ra" --argjson input "$inp" \
    '{Arn:$arn,RoleArn:$role,Input:($input|tojson)}' > "$tgt"

  aws --region "$EB_DEFAULT_REGION" scheduler create-schedule \
    --name "$n" --schedule-expression "$ex" --flexible-time-window Mode=OFF \
    --target "file://$tgt" >/dev/null && _ok "schedule created"

  rm -f -- "$tgt"
}
sch.rm(){ _eb_check || return 1; print -n "Schedule name: "; local n; read -r n; aws --region "$EB_DEFAULT_REGION" scheduler delete-schedule --name "$n" >/dev/null && _ok "deleted"; }
sch.run(){
  _eb_check || return 1
  print -n "Temp schedule name (auto ok): "; local n; read -r n; [[ -z "$n" ]] && n="oneshot-$(date -u +%Y%m%d%H%M%S)"
  print -n "Target Arn: "; local ta; read -r ta
  print -n "RoleArn: "; local ra; read -r ra
  local when; when="$(date -u -d '+2 minutes' -Iseconds)"
  _note "Edit payload JSON for one-shot"
  local inp; inp="$(_eb_edit_json '{"job":"oneshot"}')"
  local tgt; tgt="$(mktemp)"
  jq -n --arg arn "$ta" --arg role "$ra" --argjson input "$inp" \
    '{Arn:$arn,RoleArn:$role,Input:($input|tojson)}' > "$tgt"

  aws --region "$EB_DEFAULT_REGION" scheduler create-schedule \
    --name "$n" \
    --schedule-expression "at(${when})" \
    --flexible-time-window Mode=OFF \
    --target "file://$tgt" >/dev/null && _ok "scheduled at ${when}"

  rm -f -- "$tgt"
}

# ---- Top-level UI ----
eb.ui(){
  emulate -L zsh; setopt pipefail
  _eb_check || return 1
  _eb_hr; _eb_ctx; _eb_hr
  local -a items=(
    "Put event"
    "Pattern test"
    "List buses"
    "Create bus"
    "Delete bus"
    "Bus policy (get)"
    "Bus policy (put)"
    "Bus policy (remove statement)"
    "List rules"
    "New rule"
    "Update rule (state/desc/pattern/schedule)"
    "Enable rule"
    "Disable rule"
    "Delete rule"
    "List targets"
    "Add target"
    "Remove target"
    "List archives"
    "Create archive"
    "List replays"
    "Start replay"
    "Cancel replay"
    "Pipes: list"
    "Pipes: create"
    "Pipes: start"
    "Pipes: stop"
    "Pipes: delete"
    "Scheduler: list"
    "Scheduler: create"
    "Scheduler: delete"
    "Scheduler: run once"
    "Quit"
  )
  local pick
  if _eb_has_fzf; then
    pick="$(printf "%s\n" "${items[@]}" | fzf --prompt="EventBridge ⇢ " --height="$EB_UI_HEIGHT" --border --no-multi)" || return 0
  else
    printf "%s\n" "${items[@]}"; print -n "> "; read -r pick
  fi

  case "$pick" in
    "Put event") eb.event.put ;;
    "Pattern test") eb.pattern.test ;;
    "List buses") eb.bus.ls ;;
    "Create bus") eb.bus.create ;;
    "Delete bus") eb.bus.rm ;;
    "Bus policy (get)") eb.bus.policy.get ;;
    "Bus policy (put)") eb.bus.policy.put ;;
    "Bus policy (remove statement)") eb.bus.policy.rm ;;
    "List rules") eb.rule.ls ;;
    "New rule") eb.rule.new ;;
    "Update rule (state/desc/pattern/schedule)") eb.rule.set ;;
    "Enable rule") eb.rule.enable ;;
    "Disable rule") eb.rule.disable ;;
    "Delete rule") eb.rule.rm ;;
    "List targets") eb.target.ls ;;
    "Add target") eb.target.add ;;
    "Remove target") eb.target.rm ;;
    "List archives") eb.archive.ls ;;
    "Create archive") eb.archive.create ;;
    "List replays") eb.replay.ls ;;
    "Start replay") eb.replay.start ;;
    "Cancel replay") eb.replay.cancel ;;
    "Pipes: list") eb.pipes.ls ;;
    "Pipes: create") eb.pipes.create ;;
    "Pipes: start") eb.pipes.start ;;
    "Pipes: stop")  eb.pipes.stop ;;
    "Pipes: delete") eb.pipes.rm ;;
    "Scheduler: list") sch.ls ;;
    "Scheduler: create") sch.create ;;
    "Scheduler: delete") sch.rm ;;
    "Scheduler: run once") sch.run ;;
    *) return 0;;
  esac
}

# ---- completions (light) ----
_eb_rules_complete(){
  local -a r; r=("${(@f)$(aws --region "$EB_DEFAULT_REGION" events list-rules --event-bus-name "${EB_DEFAULT_BUS}" --query 'Rules[].Name' --output text 2>/dev/null | tr '\t' '\n')}")
  _describe -t rules 'rules' r
}
compdef _eb_rules_complete eb.rule.enable eb.rule.disable eb.rule.rm

# eof

