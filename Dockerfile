FROM node:18-bullseye-slim

# Install audio/recording dependencies.
RUN apt-get update -y \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ffmpeg \
    mpv \
    alsa-utils \
    jq \
    ca-certificates \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/radio

# Install minimal Node deps for the config UI/API.
COPY package.json package-lock.json ./ 
RUN npm ci --omit=dev

# Copy app files.
COPY radio-docker.sh /opt/radio/radio-docker.sh
COPY web ./web

RUN chmod +x /opt/radio/radio-docker.sh \
  && mkdir -p /opt/radio/buffer

EXPOSE 3000

CMD ["/bin/bash", "/opt/radio/radio-docker.sh"]
