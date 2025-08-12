# checkout my whisper repo, to work instantly with keybindings and shit
w() {
  local AUDIO_PATH="/tmp/record.wav"
  local MODEL_PATH="$HOME/whisper/whisper.cpp/models/ggml-base.en.bin"
  local WHISPER_BIN="$HOME/whisper/whisper.cpp/build/bin/whisper-cli"

  echo -e "\e[1;34m🎙️ Recording... Press Ctrl+C to stop.\e[0m"

  arecord -f cd -t wav -r 16000 -c 1 "$AUDIO_PATH" &
  local RECORD_PID=$!

  trap "kill $RECORD_PID; wait $RECORD_PID 2>/dev/null; echo -e '\n🧠 Transcribing...'; $WHISPER_BIN -m $MODEL_PATH -f $AUDIO_PATH -otxt && cat ${AUDIO_PATH}.txt && xclip -selection clipboard -i ${AUDIO_PATH}.txt && echo -e '\n✅ Done. Copied to clipboard.'; trap - INT" INT

  wait $RECORD_PID
}
