# ============================================
# screenpeek - "who can see my screen / hear my mic right now?"
#
# surfaces:
# - wayland/x11 display socket fds
# - pipewire screen capture streams
# - pipewire audio capture streams (mic or monitor)
#
# deps:
# - display sockets: lsof (preferred) or /proc fallback
# - pipewire: pw-dump + python3 (preferred) or jq fallback
#
# tips:
# - run with sudo for full visibility across users:
#   sudo screenpeek
# ============================================
screenpeek() {
  emulate -L zsh
  setopt pipefail no_unset null_glob
  unsetopt xtrace verbose

  local raw=0
  while (( $# )); do
    case "$1" in
      --raw) raw=1; shift ;;
      -h|--help)
        cat <<'EOF'
screenpeek [--raw]

shows:
- processes with open fds to wayland/x11 display sockets
- pipewire screen capture streams (best-effort)
- pipewire audio capture streams (mic or monitor)

notes:
- without sudo, you generally only see your own processes
- on wayland, actual screen capture usually shows up under pipewire (portal)
EOF
        return 0
        ;;
      *)
        print -ru2 -- "screenpeek: unknown arg: $1"
        return 2
        ;;
    esac
  done

  _sp_have() { command -v "$1" >/dev/null 2>&1; }

  _sp_proc_user() {
    local pid="$1"
    ps -o user= -p "$pid" 2>/dev/null | awk '{print $1}' || print -r -- "?"
  }
  _sp_proc_comm() {
    local pid="$1"
    ps -o comm= -p "$pid" 2>/dev/null | awk '{print $1}' || print -r -- "?"
  }
  _sp_proc_exe() {
    local pid="$1" exe=""
    exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
    [[ -n "$exe" ]] && print -r -- "$exe" || print -r -- "-"
  }

  # returns TSV: pid user comm
  _sp_sock_users_tsv() {
    emulate -L zsh
    setopt pipefail no_unset null_glob

    local sock="$1"
    [[ -S "$sock" ]] || return 0

    if _sp_have lsof; then
      # lsof shows more with sudo; without it, expect partial
      lsof -nP -w -U -- "$sock" 2>/dev/null \
        | awk 'NR>1{print $2"\t"$3"\t"$1}' \
        | LC_ALL=C sort -u
      return 0
    fi

    local ino
    ino="$(stat -Lc '%i' -- "$sock" 2>/dev/null || true)"
    [[ -z "$ino" ]] && return 0

    local fd link pid
    for fd in /proc/[0-9]*/fd/*(N); do
      link="$(readlink "$fd" 2>/dev/null || true)"
      [[ "$link" == "socket:[$ino]" ]] || continue
      pid="${fd:h:t}"
      [[ -n "$pid" ]] && print -r -- "$pid"
    done | LC_ALL=C sort -u | while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      print -r -- "${pid}\t$(_sp_proc_user "$pid")\t$(_sp_proc_comm "$pid")"
    done
  }

  _sp_print_sock_section() {
    emulate -L zsh
    setopt pipefail no_unset

    local label="$1"; shift
    local -a socks
    socks=("$@")

    (( ${#socks[@]} > 0 )) || return 0

    print -r -- ""
    print -r -- "== ${label} =="
    local s
    for s in "${socks[@]}"; do
      [[ -S "$s" ]] || continue
      print -r -- "socket: $s"

      local tsv
      tsv="$(_sp_sock_users_tsv "$s" || true)"

      if [[ -z "$tsv" ]]; then
        print -r -- "  (none visible; try sudo)"
        continue
      fi

      if (( raw )); then
        print -r -- "$tsv" | sed 's/^/  /'
      else
        print -r -- "$tsv" | while IFS=$'\t' read -r pid user comm; do
          [[ -z "$pid" ]] && continue
          print -r -- "  pid=${pid} user=${user} proc=${comm} exe=$(_sp_proc_exe "$pid")"
        done
      fi
    done
  }

  _sp_pw_capture_tsv() {
    emulate -L zsh
    setopt pipefail no_unset

    _sp_have pw-dump || { print -ru2 -- "screenpeek: missing dep: pw-dump (pipewire-bin)"; return 127; }

    if _sp_have python3; then
      pw-dump 2>/dev/null | python3 - <<'PY'
import sys, json, re

try:
  data = json.load(sys.stdin)
except Exception:
  sys.exit(0)

clients = {}
nodes = {}

def gprops(obj):
  return (obj.get("info") or {}).get("props") or {}

def gstate(obj):
  return (obj.get("info") or {}).get("state")

for o in data:
  t = o.get("type","")
  if ":Interface:Client" in t:
    clients[o.get("id")] = gprops(o)
  elif ":Interface:Node" in t:
    nodes[o.get("id")] = {"props": gprops(o), "state": gstate(o)}

def first_present(d, keys):
  for k in keys:
    v = d.get(k)
    if v is None:
      continue
    if isinstance(v, str) and v.strip()=="":
      continue
    return v
  return None

def pid_from_client_props(p):
  v = first_present(p, ["application.process.id", "pipewire.sec.pid"])
  try:
    return int(str(v))
  except Exception:
    return None

def norm_state(s):
  if not s:
    return "-"
  return str(s)

def is_live(props, state):
  v = props.get("stream.is-live")
  if isinstance(v, bool):
    return v
  if isinstance(v, (int,float)):
    return bool(v)
  if isinstance(v, str):
    if v.lower() in ("true","1","yes","on"):
      return True
  return str(state).lower() == "running"

def text(*xs):
  return " ".join([x for x in xs if isinstance(x,str)])

def looks_like_screen(props, target_props):
  role = props.get("media.role") or (target_props or {}).get("media.role")
  if isinstance(role,str) and role.lower() == "screen":
    return True
  hay = text(
    props.get("node.name",""),
    props.get("node.description",""),
    props.get("media.name",""),
    (target_props or {}).get("node.name",""),
    (target_props or {}).get("node.description",""),
    (target_props or {}).get("media.name",""),
  ).lower()
  if re.search(r"\b(screen|screencast|desktop|portal|xdg-desktop-portal|xdpw)\b", hay):
    return True
  return False

def classify_audio_target(target_props):
  if not target_props:
    return "audio"
  mc = (target_props.get("media.class") or "").lower()
  desc = (target_props.get("node.description") or target_props.get("node.name") or "").lower()
  if "audio/source" in mc:
    if "monitor" in desc:
      return "audio-monitor"
    return "mic"
  return "audio"

out = []
for nid, n in nodes.items():
  props = n["props"]
  state = n["state"]
  mc = props.get("media.class") or ""
  if not isinstance(mc,str):
    continue
  mc_l = mc.lower()

  if mc_l not in ("stream/input/audio", "stream/input/video"):
    continue

  # ignore dead-ish streams when we have any signal; keep paused/running/live
  if not is_live(props, state) and str(state).lower() not in ("paused","running","idle"):
    continue

  cid = props.get("client.id")
  cprops = clients.get(cid, {})
  pid = pid_from_client_props(cprops)

  app = first_present(cprops, ["application.name", "application.process.binary"]) or "-"
  binp = first_present(cprops, ["application.process.binary"]) or "-"
  portal_app = first_present(cprops, ["pipewire.access.portal.app_id"]) or "-"
  flatpak = first_present(cprops, ["pipewire.sec.flatpak"]) or "-"

  target_id = props.get("node.target")
  target_props = None
  if isinstance(target_id, int) and target_id in nodes:
    target_props = nodes[target_id]["props"]

  role = props.get("media.role") or (target_props or {}).get("media.role") or "-"
  node_name = props.get("node.name") or "-"
  node_desc = props.get("node.description") or "-"

  if mc_l == "stream/input/video":
    kind = "screen" if looks_like_screen(props, target_props) else "video"
  else:
    kind = classify_audio_target(target_props)

  out.append((kind, pid if pid is not None else "-", app, binp, portal_app, flatpak, nid, norm_state(state), node_name, role, node_desc))

for row in out:
  # kind pid app bin portal_app flatpak node_id state node_name role node_desc
  print("\t".join(map(lambda x: str(x), row)))
PY
      return 0
    fi

    if _sp_have jq; then
      # fallback: lower fidelity (no link/target logic), still useful
      # kind pid app bin portal_app flatpak node_id state node_name role node_desc
      pw-dump 2>/dev/null | jq -r '
        def cprops: .info?.props? // {};
        def nprops: .info?.props? // {};
        (map(select(.type|test("Interface:Client")))|map({id:.id, p:cprops})|from_entries(.[]|{key:(.id|tostring), value:.p})) as $C
        | map(select(.type|test("Interface:Node")))
        | .[]
        | (nprops) as $p
        | ($p["media.class"] // "") as $mc
        | select($mc=="Stream/Input/Audio" or $mc=="Stream/Input/Video")
        | ($p["client.id"]|tostring) as $cid
        | ($C[$cid]["application.process.id"] // $C[$cid]["pipewire.sec.pid"] // "-") as $pid
        | ($C[$cid]["application.name"] // $C[$cid]["application.process.binary"] // "-") as $app
        | ($C[$cid]["application.process.binary"] // "-") as $bin
        | ($C[$cid]["pipewire.access.portal.app_id"] // "-") as $portal
        | ($C[$cid]["pipewire.sec.flatpak"] // "-") as $flatpak
        | ($p["media.role"] // "-") as $role
        | ($p["node.name"] // "-") as $nn
        | ($p["node.description"] // "-") as $nd
        | ($p["media.class"]=="Stream/Input/Video"
            ? (($role=="Screen") ? "screen" : "video")
            : "audio") as $kind
        | "\($kind)\t\($pid)\t\($app)\t\($bin)\t\($portal)\t\($flatpak)\t\(.id)\t\(.info.state // "-")\t\($nn)\t\($role)\t\($nd)"
      ' 2>/dev/null
      return 0
    fi

    print -ru2 -- "screenpeek: pipewire parsing needs python3 (preferred) or jq"
    return 127
  }

  _sp_print_pw_section() {
    emulate -L zsh
    setopt pipefail no_unset

    _sp_have pw-dump || return 0

    local tsv
    tsv="$(_sp_pw_capture_tsv 2>/dev/null || true)"
    [[ -z "$tsv" ]] && return 0

    local n_screen n_video n_mic n_audio n_mon
    n_screen="$(print -r -- "$tsv" | awk -F'\t' '$1=="screen"{c++} END{print c+0}')"
    n_video="$(print -r -- "$tsv" | awk -F'\t' '$1=="video"{c++} END{print c+0}')"
    n_mic="$(print -r -- "$tsv" | awk -F'\t' '$1=="mic"{c++} END{print c+0}')"
    n_mon="$(print -r -- "$tsv" | awk -F'\t' '$1=="audio-monitor"{c++} END{print c+0}')"
    n_audio="$(print -r -- "$tsv" | awk -F'\t' '$1=="audio"{c++} END{print c+0}')"

    print -r -- ""
    print -r -- "== pipewire capture streams =="
    print -r -- "screen=${n_screen} mic=${n_mic} audio_monitor=${n_mon} audio_unknown=${n_audio} other_video=${n_video}"

    local kind_label
    for kind_label in screen mic audio-monitor audio video; do
      local block
      block="$(print -r -- "$tsv" | awk -F'\t' -v k="$kind_label" '$1==k{print}')"
      [[ -z "$block" ]] && continue

      print -r -- ""
      print -r -- "-- ${kind_label} --"
      if (( raw )); then
        print -r -- "$block" | sed 's/^/  /'
      else
        print -r -- "$block" | while IFS=$'\t' read -r kind pid app bin portal flatpak node_id state node_name role node_desc; do
          local extra=""
          [[ "$portal" != "-" ]] && extra=" portal_app_id=${portal}"
          [[ "$flatpak" != "-" ]] && extra="${extra} flatpak=${flatpak}"
          print -r -- "  pid=${pid} app=${app} bin=${bin} state=${state} role=${role} node=${node_id} name=${node_name}${extra}"
        done
      fi
    done
  }

  local xdg="${XDG_RUNTIME_DIR:-/run/user/$UID}"
  local wdisp="${WAYLAND_DISPLAY:-wayland-0}"

  local -a wl_socks x_socks
  wl_socks=()
  if [[ -d "$xdg" ]]; then
    [[ -S "$xdg/$wdisp" ]] && wl_socks+=("$xdg/$wdisp")
    local s
    for s in "$xdg"/wayland-*; do
      [[ -S "$s" ]] && wl_socks+=("$s")
    done
  fi
  wl_socks=("${(@u)wl_socks}")

  x_socks=()
  local xs
  for xs in /tmp/.X11-unix/X*(N); do
    [[ -S "$xs" ]] && x_socks+=("$xs")
  done
  x_socks=("${(@u)x_socks}")

  local wl_count x_count
  wl_count="${#wl_socks[@]}"
  x_count="${#x_socks[@]}"

  print -r -- "screenpeek: wayland_sockets=${wl_count} x11_sockets=${x_count} (try sudo for full visibility)"

  _sp_print_sock_section "display socket access (wayland)" "${wl_socks[@]}"
  _sp_print_sock_section "display socket access (x11)" "${x_socks[@]}"

  _sp_print_pw_section

  return 0
}
