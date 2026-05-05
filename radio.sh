#!/bin/bash
# FINAL version — heartbeat watcher auto-switches back to live
# Lucas – Oct 2025

# Load config written by the web interface (if present)
CONFIG_SH="/opt/radio/config.sh"
if [[ -f "$CONFIG_SH" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_SH"
fi

# Defaults (used only when config.sh does not exist yet)
STREAM_URL="${STREAM_URL:-https://findyourownstream.example/stream}"
CHUNK_SECONDS="${CHUNK_SECONDS:-300}"
BUFFER_MINUTES="${BUFFER_MINUTES:-120}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
VOLUME="${VOLUME:-90}"
# When 0, no chunks are recorded and stream outages do not fall back to
# cached audio — the loop just retries the live URL.
BUFFER_ENABLED="${BUFFER_ENABLED:-1}"

BUFFER_DIR="/opt/radio/buffer"
STATE_FILE="/opt/radio/state.json"
FORCE_BUFFER="/opt/radio/force_buffer"   # touch this file to force buffer mode
MAX_CHUNKS=$(( BUFFER_MINUTES * 60 / CHUNK_SECONDS ))
PLAYER="mpv --no-video --quiet --volume=${VOLUME} --audio-device=alsa --user-agent='Mozilla/5.0' --no-ytdl --network-timeout=8"

mkdir -p "$BUFFER_DIR"

amixer cset numid=3 1 >/dev/null 2>&1
amixer sset 'PCM' "${VOLUME}%" >/dev/null 2>&1

# -------- State file --------
write_state() {
  local mode="$1"
  printf '{"mode":"%s","url":"%s","since":%s}\n' \
    "$mode" "$STREAM_URL" "$(date +%s)" > "$STATE_FILE"
}

prune_buffer() {
  ls -1t "$BUFFER_DIR"/*.mp3 2>/dev/null | tail -n +$((MAX_CHUNKS+1)) | xargs -r rm -f
}

record_stream() {
  while true; do
    ffmpeg -hide_banner -loglevel error \
      -reconnect 1 -reconnect_streamed 1 -reconnect_at_eof 1 \
      -headers "User-Agent: Mozilla/5.0\r\n" \
      -i "$STREAM_URL" -vn -ac 2 -ar 44100 \
      -c:a libmp3lame -b:a 128k \
      -f segment -segment_time "$CHUNK_SECONDS" -reset_timestamps 1 \
      "$BUFFER_DIR"/chunk_%03d.mp3
    sleep 5
  done
}

stream_ok() {
  timeout 8s ffmpeg -hide_banner -loglevel error \
    -reconnect 1 -reconnect_streamed 1 -reconnect_at_eof 1 \
    -headers "User-Agent: Mozilla/5.0\r\n" \
    -i "$STREAM_URL" -t 3 -f null - >/dev/null 2>&1
}

# -------- Heartbeat watcher --------
start_watcher() {
  local pid_to_kill="$1"
  (
    while true; do
      sleep "$CHECK_INTERVAL"
      # Return to live only if force_buffer flag is gone AND stream is up
      if [[ ! -f "$FORCE_BUFFER" ]] && stream_ok; then
        echo "[radio] Live stream detected (heartbeat). Restarting service."
        kill "$pid_to_kill" 2>/dev/null
        break
      fi
    done
  ) &
  WATCH_PID=$!
}

# -------- Buffer playback --------
play_buffer() {
  echo "[radio] Playing backup buffer..."
  ls -1tr "$BUFFER_DIR"/*.mp3 > "$BUFFER_DIR/loop.m3u" 2>/dev/null
  mpv --no-video --quiet --volume="${VOLUME}" --loop-playlist=inf --audio-device=alsa "$BUFFER_DIR/loop.m3u" &
  MPV_PID=$!
  start_watcher "$MPV_PID"
  wait "$MPV_PID"
  echo "[radio] Buffer playback ended."
}

# -------- Main loop --------
write_state "starting"

if [[ "$BUFFER_ENABLED" == "1" ]]; then
  record_stream &
  REC_PID=$!
  echo "[radio] Recorder PID: $REC_PID (buffer enabled)"
else
  echo "[radio] Buffer disabled — recorder not started, no failover."
fi

while true; do
  if [[ "$BUFFER_ENABLED" == "1" ]]; then
    prune_buffer
  fi

  # When the buffer is disabled, FORCE_BUFFER is meaningless — skip it.
  if { [[ "$BUFFER_ENABLED" != "1" ]] || [[ ! -f "$FORCE_BUFFER" ]]; } && stream_ok; then
    echo "[radio] Stream OK — playing live."
    write_state "live"
    $PLAYER "$STREAM_URL"
    echo "[radio] mpv exited; rechecking..."
  elif [[ "$BUFFER_ENABLED" != "1" ]]; then
    # Buffer disabled and stream is down — wait and retry, no fallback playback.
    echo "[radio] Stream DOWN — buffer disabled, waiting $CHECK_INTERVAL s..."
    write_state "waiting"
  else
    if [[ -f "$FORCE_BUFFER" ]]; then
      echo "[radio] Force buffer mode active."
      write_state "forced"
    else
      echo "[radio] Stream DOWN — using buffer."
      write_state "buffer"
    fi
    play_buffer
    echo "[radio] Returning to live stream."
  fi

  sleep "$CHECK_INTERVAL"
done
