# refer to https://github.com/rccyx/whisper
w() {
  setopt localoptions errexit nounset pipefail
  autoload -Uz colors && colors
  say(){ print -P "%F{4}[*]%f $*"; }
  ok(){  print -P "%F{2}[ok]%f $*"; }
  die(){ print -P "%F{1}[err]%f $*"; return 1; }

  # paths
  local WROOT="${WHISPER_DIR:-$HOME/.local/opt/whisper.cpp}"
  local BIN="${WHISPER_CLI:-$WROOT/build/bin/whisper-cli}"
  local MODELS_DIR="${WHISPER_MODELS:-$HOME/.local/share/whisper/models}"
  local MODEL="${WHISPER_MODEL:-$MODELS_DIR/ggml-base.en.bin}"

  [[ -x "$BIN" ]]   || die "whisper-cli not found at $BIN"
  [[ -s "$MODEL" ]] || die "model missing at $MODEL"

  # pick recorder
  local REC=""
  if command -v pw-record >/dev/null 2>&1; then
    REC="pw-record"
  elif command -v arecord >/dev/null 2>&1; then
    REC="arecord"
  else
    die "no recorder found (install pipewire-bin or alsa-utils)"
  fi

  # choose PipeWire source (optional fzf picker)
  local SRC=""
  local cache="${XDG_CONFIG_HOME:-$HOME/.config}/whisper/default_source"
  if [[ "$REC" == "pw-record" ]]; then
    mkdir -p "${cache:h}"
    SRC="${WHISPER_SOURCE:-}"
    [[ -z "$SRC" && -f "$cache" ]] && SRC="$(<"$cache")"
    [[ -z "$SRC" ]] && SRC="$(pactl get-default-source 2>/dev/null | awk '{print $1}')"
    if [[ -z "$SRC" || "${WHISPER_PICK_SOURCE:-0}" = "1" ]]; then
      if command -v fzf >/dev/null 2>&1; then
        say "Pick input source (fzf)"
        SRC="$(pw-record --list-targets | awk 'NR>1{print $1"\t"$2}' | fzf --prompt='source > ' | awk '{print $1}')" || true
      fi
    fi
    [[ -n "$SRC" ]] && print -r -- "$SRC" > "$cache"
  fi

  # temp files
  local ts="$(date +%Y%m%d_%H%M%S)"
  local WAV="/tmp/whisper_${ts}.wav"
  local OUT="/tmp/whisper_${ts}"

  say "🎙️  Recording... Ctrl+C to stop"
  if [[ "$REC" == "pw-record" ]]; then
    if [[ -n "$SRC" ]]; then
      pw-record --target "$SRC" --rate 16000 --channels 1 --format s16 "$WAV" &
    else
      pw-record --rate 16000 --channels 1 --format s16 "$WAV" &
    fi
  else
    # ALSA path
    arecord -q -f S16_LE -r 16000 -c 1 "$WAV" &
  fi
  local recpid=$!

  trap '
    # stop recording cleanly
    kill $recpid >/dev/null 2>&1 || true
    wait $recpid 2>/dev/null || true

    [[ -s "'"$WAV"'" ]] || { print -P "%F{1}[err]%f no audio captured"; trap - INT; return 1; }

    say "🧠 Transcribing..."
    local threads="${WHISPER_THREADS:-$(nproc)}"
    local args=(-m "'"$MODEL"'" -f "'"$WAV"'" -t "$threads" -otxt -of "'"$OUT"'")
    case "$(basename "'"$MODEL"'")" in *".en.bin") args+=(-l en);; esac
    [[ -n "${WHISPER_LANG:-}" ]] && args+=(-l "$WHISPER_LANG")
    if [[ "${WHISPER_VAD:-0}" = "1" ]]; then
      local VAD="${WHISPER_VAD_MODEL:-"'"$MODELS_DIR"'/ggml-silero-v5.1.2.bin"}"
      [[ -s "$VAD" ]] && args+=(--vad --vad-model "$VAD")
    fi

    "'"$BIN"'" "${args[@]}" >/dev/null

    local TXT="'"$OUT"'.txt"
    if [[ -s "$TXT" ]]; then
      print -P "%F{8}------------------------------------------------------------%f"
      if command -v bat >/dev/null 2>&1; then bat -pp --wrap=never "$TXT"; else cat "$TXT"; fi
      print -P "%F{8}------------------------------------------------------------%f"
      if command -v wl-copy >/dev/null 2>&1; then
        wl-copy < "$TXT"
      elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard -i "$TXT"
      fi
      print -P "%F{2}[ok]%f Copied to clipboard"
    else
      print -P "%F{1}[err]%f no output generated"
    fi

    rm -f "'"$WAV"'" >/dev/null 2>&1 || true
    trap - INT
  ' INT

  # do not die if recorder returns non-zero on Ctrl+C
  wait $recpid || true
}

