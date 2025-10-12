#!/bin/bash
# FINAL version — heartbeat watcher auto-switches back to live
# Lucas – Oct 2025

STREAM_URL="https://findyourownstream.example/stream"
BUFFER_DIR="/opt/radio/buffer"
CHUNK_SECONDS=300
BUFFER_MINUTES=120
MAX_CHUNKS=$((BUFFER_MINUTES*60/CHUNK_SECONDS))
CHECK_INTERVAL=10
PLAYER="mpv --no-video --quiet --volume=90 --user-agent='Mozilla/5.0' --no-ytdl --network-timeout=8"

mkdir -p "$BUFFER_DIR"

amixer cset numid=3 1 >/dev/null 2>&1
amixer sset 'PCM' 90% >/dev/null 2>&1

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
  ls -1tr "$BUFFER_DIR"/*.mp3 > "$BUFFER_DIR/loop.m3u" 2>/dev/null
  mpv --audio-device=alsa --no-video --quiet --volume=90 --loop-playlist=inf "$BUFFER_DIR/loop.m3u" &
  MPV_PID=$!
  start_watcher "$MPV_PID"
  wait "$MPV_PID"
  echo "[radio] Buffer playback ended."
}

# -------- Main loop --------
record_stream & 
REC_PID=$!
echo "[radio] Recorder PID: $REC_PID"

while true; do
  prune_buffer

  if stream_ok; then
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
