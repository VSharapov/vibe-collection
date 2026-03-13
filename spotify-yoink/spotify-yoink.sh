#!/usr/bin/env bash
set -euo pipefail

# spotify-yoink.sh - no clever tricks brute force downloader, runs at 1x time in a containerized browser

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${SPOTIFY_YOINK_IMAGE:-spotify-yoink}"
OUTPUT_DIR="${SPOTIFY_YOINK_OUTPUT:-}"

usage() {
  >&2 cat <<'EOF'
spotify-yoink.sh - brute force Spotify episode downloader

Runs a containerized Chrome browser, plays the episode, records audio in real-time.
No account needed. Takes as long as the episode duration (1x speed).

USAGE:
  spotify-yoink.sh rip <spotify-url> [output.mp3] [duration-seconds] [start-at-seconds]
  spotify-yoink.sh splice <chunk1.mp3> <chunk2.mp3> [...] <output.mp3>
  spotify-yoink.sh build
  spotify-yoink.sh help

COMMANDS:
  rip <url> [out] [dur] [start]   Download episode. Duration auto-detected if omitted.
  splice <in...> <out>            Auto-detect overlap and splice chunks together.
  build                           Build/rebuild the Docker image
  help                            Show this message

EXAMPLES:
  spotify-yoink.sh rip "https://open.spotify.com/episode/ID" maze.mp3
  spotify-yoink.sh rip "https://open.spotify.com/episode/ID" maze.mp3 1800      # 30 min
  spotify-yoink.sh rip "https://open.spotify.com/episode/ID" maze.mp3 1800 1500 # resume from 25m
  spotify-yoink.sh splice chunk1.mp3 chunk2.mp3 chunk3.mp3 final.mp3

ENV VARS:
  SPOTIFY_YOINK_IMAGE    Docker image name (default: spotify-yoink)
  SPOTIFY_YOINK_OUTPUT   Output directory (default: mktemp -d)
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
  local start_at="${4:-0}"

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

  # Default output dir to mktemp -d if not set
  local out_dir="$OUTPUT_DIR"
  if [[ -z "$out_dir" ]]; then
    out_dir=$(mktemp -d)
    >&2 echo "Output dir: $out_dir"
  fi

  >&2 echo "Episode ID: $episode_id"
  >&2 echo "Output: $out_dir/$output"
  if [[ "$duration" -gt 0 ]]; then
    >&2 echo "Duration: ${duration}s (manual)"
  else
    >&2 echo "Duration: auto-detect"
  fi
  if [[ "$start_at" -gt 0 ]]; then
    >&2 echo "Resume from: ${start_at}s"
  fi

  local docker_args=( 
    --rm
    -e "HOST_UID=$(id -u)"
    -e "HOST_GID=$(id -g)"
    -v "$out_dir:/output"
    "$IMAGE_NAME"
    "$url"
    -o "/output/$output"
  )

  if [[ "$duration" -gt 0 ]]; then
    docker_args+=( -d "$duration" )
  fi

  if [[ "$start_at" -gt 0 ]]; then
    docker_args+=( -s "$start_at" )
  fi

  docker run "${docker_args[@]}"

  >&2 echo "Done: $out_dir/$output"
}

splice() {
  if [[ $# -lt 3 ]]; then
    >&2 echo "Error: splice needs at least 2 input files and 1 output file"
    >&2 echo "Usage: spotify-yoink.sh splice <chunk1.mp3> <chunk2.mp3> [...] <output.mp3>"
    exit 1
  fi

  ensure-image

  # All args except last are inputs, last is output
  local args=("$@")
  local num_args=${#args[@]}
  local output="${args[-1]}"
  local inputs=("${args[@]:0:num_args-1}")
  local out_dir
  out_dir="$(cd "$(dirname "$output")" && pwd)"
  local out_name
  out_name="$(basename "$output")"

  # Build volume mounts and container paths
  local volumes=()
  local container_inputs=()
  local i=0

  for input in "${inputs[@]}"; do
    local abs_path
    abs_path="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
    local container_path="/input/chunk_${i}.mp3"
    volumes+=(-v "$abs_path:$container_path:ro")
    container_inputs+=("$container_path")
    i=$((i + 1))
  done

  volumes+=(-v "$out_dir:/output")

  >&2 echo "Splicing ${#inputs[@]} files -> $output"
  
  docker run --rm \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    "${volumes[@]}" \
    --entrypoint python \
    "$IMAGE_NAME" \
    /app/splice.py "${container_inputs[@]}" "/output/$out_name"
  
  # Fix ownership
  if [[ -f "$output" ]]; then
    >&2 echo "Done: $output"
  fi
}

help() {
  usage
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

"$@"
