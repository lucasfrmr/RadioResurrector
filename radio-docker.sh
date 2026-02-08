#!/bin/bash
# Docker-compatible version with environment variable support
# Lucas – Feb 2026

# Configuration with defaults + runtime override via /opt/radio/config.json
CONFIG_PATH="/opt/radio/config.json"
DEFAULT_STREAM="${STREAM_URL:-https://ice5.somafm.com/live-128-mp3}"
BUFFER_DIR="${BUFFER_DIR:-/opt/radio/buffer}"
CHUNK_SECONDS="${CHUNK_SECONDS:-300}"
BUFFER_MINUTES="${BUFFER_MINUTES:-120}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
VOLUME="${VOLUME:-90}"
MAX_CHUNKS=$((BUFFER_MINUTES*60/CHUNK_SECONDS))

# Audio backend: auto-detect ALSA; fall back to null (silent) if no device or AUDIO_BACKEND=null
detect_player() {
  local ao
  if [ "${AUDIO_BACKEND:-auto}" = "null" ]; then
    ao="--ao=null"
  elif [ -e /dev/snd ] || [ -d /proc/asound ]; then
    ao="--ao=alsa"
  else
    ao="--ao=null"
  fi
  PLAYER="mpv --no-video --quiet --volume=${VOLUME} ${ao} --user-agent='Mozilla/5.0' --no-ytdl --network-timeout=8"
}
detect_player

current_stream() {
  if [ -f "$CONFIG_PATH" ]; then
    val=$(jq -r '.streamUrl // empty' "$CONFIG_PATH" 2>/dev/null || true)
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
  echo "$DEFAULT_STREAM"
}

echo "[radio] Starting RadioResurrector..."
echo "[radio] Stream URL: $(current_stream)"
echo "[radio] Buffer directory: $BUFFER_DIR"
echo "[radio] Buffer duration: ${BUFFER_MINUTES} minutes"

mkdir -p "$BUFFER_DIR"

# Try to set ALSA configuration only if ALSA hardware exists
if [ -e /dev/snd ] || [ -d /proc/asound ]; then
  amixer cset numid=3 1 >/dev/null 2>&1 || true
  amixer sset 'PCM' 90% >/dev/null 2>&1 || true
fi

start_ui() {
  node /opt/radio/web/server.js >/opt/radio/ui.log 2>&1 &
  UI_PID=$!
  echo "[radio] UI server PID: $UI_PID (listening on ${PORT:-3000})"
}

# Graceful shutdown handler for Docker
cleanup() {
  echo "[radio] Shutting down gracefully..."
  kill $REC_PID 2>/dev/null || true
  kill $MPV_PID 2>/dev/null || true
  kill $WATCH_PID 2>/dev/null || true
  kill $UI_PID 2>/dev/null || true
  exit 0
}

trap cleanup SIGTERM SIGINT

prune_buffer() {
  ls -1t "$BUFFER_DIR"/*.mp3 2>/dev/null | tail -n +$((MAX_CHUNKS+1)) | xargs -r rm -f
}

record_stream() {
  while true; do
    local STREAM_URL
    STREAM_URL="$(current_stream)"
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
  local STREAM_URL
  STREAM_URL="$(current_stream)"
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
      if stream_ok; then
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
  # Wait until at least one buffered file exists to avoid mpv format errors.
  local attempts=0
  while true; do
    mapfile -t files < <(ls -1tr "$BUFFER_DIR"/*.mp3 2>/dev/null || true)
    if [ ${#files[@]} -gt 0 ]; then
      printf "%s\n" "${files[@]}" > "$BUFFER_DIR/loop.m3u"
      break
    fi
    attempts=$((attempts+1))
    if [ $attempts -eq 1 ]; then
      echo "[radio] Waiting for buffered audio chunks..."
    elif [ $attempts -ge 10 ]; then
      echo "[radio] Still no buffered chunks; continuing to wait."
      attempts=5  # prevent unbounded message spam
    fi
    sleep 3
  done
  detect_player
  $PLAYER --loop-playlist=inf "$BUFFER_DIR/loop.m3u" &
  MPV_PID=$!
  start_watcher "$MPV_PID"
  wait "$MPV_PID"
  echo "[radio] Buffer playback ended."
}

# -------- Main loop --------
start_ui
record_stream & 
REC_PID=$!
echo "[radio] Recorder PID: $REC_PID"

while true; do
  prune_buffer

  if stream_ok; then
    STREAM_URL="$(current_stream)"
    echo "[radio] Stream OK — playing live."
    $PLAYER "$STREAM_URL"
    echo "[radio] mpv exited; rechecking..."
  else
    echo "[radio] Stream DOWN — using buffer."
    play_buffer
    echo "[radio] Returning to live stream."
  fi

  sleep "$CHECK_INTERVAL"
done
