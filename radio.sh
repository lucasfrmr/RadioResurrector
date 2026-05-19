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
# When 0, stream outages do not fall back to local MP3 playback.
BUFFER_ENABLED="${BUFFER_ENABLED:-0}"
MP3_PLAYER_DIR="${MP3_PLAYER_DIR:-/opt/radio/mp3}"
MP3_ORDER_FILE="${MP3_ORDER_FILE:-/opt/radio/mp3_order.m3u}"
MPV_SOCKET="${MPV_SOCKET:-/tmp/radio-mpv.sock}"

STATE_FILE="/opt/radio/state.json"
FORCE_BUFFER="/opt/radio/force_buffer"   # touch this file to force buffer mode
PLAYER="mpv --no-video --quiet --volume=${VOLUME} --audio-device=alsa --input-ipc-server=${MPV_SOCKET} --user-agent='Mozilla/5.0' --no-ytdl --network-timeout=8"

mkdir -p "$MP3_PLAYER_DIR"

amixer cset numid=3 1 >/dev/null 2>&1
amixer sset 'PCM' "${VOLUME}%" >/dev/null 2>&1

# -------- State file --------
write_state() {
  local mode="$1"
  printf '{"mode":"%s","url":"%s","since":%s}\n' \
    "$mode" "$STREAM_URL" "$(date +%s)" > "$STATE_FILE"
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

# -------- MP3 folder playback --------
mp3_files_available() {
  [[ -d "$MP3_PLAYER_DIR" ]] && [[ -n "$(find "$MP3_PLAYER_DIR" -maxdepth 1 -type f -iname '*.mp3' -print -quit)" ]]
}

play_buffer() {
  local playlist

  if [[ "$BUFFER_ENABLED" != "1" ]]; then
    echo "[radio] MP3 folder player disabled; no fallback playback."
    return 1
  fi

  if ! mp3_files_available; then
    echo "[radio] MP3 folder player disabled; no MP3 files in $MP3_PLAYER_DIR."
    return 1
  fi

  playlist="$(mktemp /tmp/radio-mp3-player.XXXXXX.m3u)"
  if [[ -f "$MP3_ORDER_FILE" ]]; then
    while IFS= read -r track; do
      if [[ -f "$track" && "${track,,}" == *.mp3 ]]; then
        printf '%s\n' "$track" >> "$playlist"
      fi
    done < "$MP3_ORDER_FILE"
  fi
  while IFS= read -r track; do
    if ! grep -Fxq "$track" "$playlist" 2>/dev/null; then
      printf '%s\n' "$track" >> "$playlist"
    fi
  done < <(find "$MP3_PLAYER_DIR" -maxdepth 1 -type f -iname '*.mp3' | sort)

  echo "[radio] Playing MP3 folder on loop: $MP3_PLAYER_DIR"
  rm -f "$MPV_SOCKET"
  mpv --no-video --quiet --volume="${VOLUME}" --loop-playlist=inf --audio-device=alsa --input-ipc-server="$MPV_SOCKET" --playlist="$playlist" &
  MPV_PID=$!
  start_watcher "$MPV_PID"
  wait "$MPV_PID"
  rm -f "$playlist"
  echo "[radio] MP3 folder playback ended."
}

# -------- Main loop --------
write_state "starting"

if [[ "$BUFFER_ENABLED" == "1" ]]; then
  echo "[radio] MP3 folder player enabled: $MP3_PLAYER_DIR"
else
  echo "[radio] MP3 folder player disabled — live stream only."
fi

while true; do
  # When the MP3 player is disabled or empty, FORCE_BUFFER is meaningless.
  if { [[ "$BUFFER_ENABLED" != "1" ]] || ! mp3_files_available || [[ ! -f "$FORCE_BUFFER" ]]; } && stream_ok; then
    echo "[radio] Stream OK — playing live."
    write_state "live"
    rm -f "$MPV_SOCKET"
    $PLAYER "$STREAM_URL"
    echo "[radio] mpv exited; rechecking..."
  elif [[ "$BUFFER_ENABLED" != "1" ]] || ! mp3_files_available; then
    # MP3 player disabled or empty and stream is down — wait and retry.
    echo "[radio] Stream DOWN — MP3 player unavailable, waiting $CHECK_INTERVAL s..."
    write_state "waiting"
  else
    if [[ -f "$FORCE_BUFFER" ]]; then
      echo "[radio] Force MP3 player mode active."
      write_state "forced"
    else
      echo "[radio] Stream DOWN — using MP3 folder player."
      write_state "buffer"
    fi
    if play_buffer; then
      echo "[radio] Returning to live stream."
    fi
  fi

  sleep "$CHECK_INTERVAL"
done
