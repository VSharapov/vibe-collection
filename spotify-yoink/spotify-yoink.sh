#!/usr/bin/env bash
set -euo pipefail

# spotify-yoink.sh - no clever tricks brute force downloader, runs at 1x time in a containerized browser

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${SPOTIFY_YOINK_IMAGE:-spotify-yoink}"
OUTPUT_DIR="${SPOTIFY_YOINK_OUTPUT:-$(pwd)}"

usage() {
  >&2 cat <<'EOF'
spotify-yoink.sh - brute force Spotify episode downloader

Runs a containerized Chrome browser, plays the episode, records audio in real-time.
No account needed. Takes as long as the episode duration (1x speed).

USAGE:
  spotify-yoink.sh rip <spotify-url> [output.mp3] [duration-seconds]
  spotify-yoink.sh build
  spotify-yoink.sh help

COMMANDS:
  rip <url> [out] [dur]   Download episode. Duration auto-detected if omitted.
  build                   Build/rebuild the Docker image
  help                    Show this message

EXAMPLES:
  spotify-yoink.sh rip "https://open.spotify.com/episode/0kiCA30wyU8M2X9sM3JuB2"
  spotify-yoink.sh rip "https://open.spotify.com/episode/0kiCA30wyU8M2X9sM3JuB2" maze.mp3
  spotify-yoink.sh rip "https://open.spotify.com/episode/0kiCA30wyU8M2X9sM3JuB2" maze.mp3 1500

ENV VARS:
  SPOTIFY_YOINK_IMAGE    Docker image name (default: spotify-yoink)
  SPOTIFY_YOINK_OUTPUT   Output directory (default: current dir)
EOF
}

build() {
  >&2 echo "Building Docker image: $IMAGE_NAME"
  docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
}

ensure-image() {
  if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    >&2 echo "Image '$IMAGE_NAME' not found, building..."
    build
  fi
}

extract-episode-id() {
  local url="$1"
  echo "$url" | grep -oP 'episode/\K[a-zA-Z0-9]+' || {
    >&2 echo "Error: Could not extract episode ID from URL"
    exit 1
  }
}

rip() {
  local url="${1:-}"
  local output="${2:-}"
  local duration="${3:-0}"

  if [[ -z "$url" ]]; then
    >&2 echo "Error: URL required"
    usage
    exit 1
  fi

  ensure-image

  local episode_id
  episode_id=$(extract-episode-id "$url")
  
  if [[ -z "$output" ]]; then
    output="${episode_id}.mp3"
  fi

  >&2 echo "Episode ID: $episode_id"
  >&2 echo "Output: $OUTPUT_DIR/$output"
  if [[ "$duration" -gt 0 ]]; then
    >&2 echo "Duration: ${duration}s (manual)"
  else
    >&2 echo "Duration: auto-detect"
  fi

  local docker_args=( 
    --rm
    -v "$OUTPUT_DIR:/output"
    "$IMAGE_NAME"
    "$url"
    -o "/output/$output"
  )

  if [[ "$duration" -gt 0 ]]; then
    docker_args+=( -d "$duration" )
  fi

  docker run "${docker_args[@]}"

  >&2 echo "Done: $OUTPUT_DIR/$output"
}

help() {
  usage
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

"$@"
