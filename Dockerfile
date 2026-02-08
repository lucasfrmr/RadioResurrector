FROM debian:bookworm-slim

# Install dependencies: ffmpeg for recording, mpv for playback, alsa-utils for volume control.
RUN apt-get update -y \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ffmpeg \
    mpv \
    alsa-utils \
    ca-certificates \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/radio

# Copy the Docker-friendly script.
COPY radio-docker.sh /opt/radio/radio-docker.sh
RUN chmod +x /opt/radio/radio-docker.sh

# Pre-create buffer directory so it can be volume-mounted.
RUN mkdir -p /opt/radio/buffer

# Use bash for the script.
CMD ["/bin/bash", "/opt/radio/radio-docker.sh"]
