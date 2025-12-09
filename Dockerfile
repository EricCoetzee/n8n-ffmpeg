FROM n8nio/n8n:latest

# Install FFmpeg
USER root
RUN apk update && apk add --no-cache ffmpeg bash
USER node

# Create directories (they will be mounted but just in case)
RUN mkdir -p /home/node/scripts /home/node/yt /home/node/processed