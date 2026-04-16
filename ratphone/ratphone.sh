#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"

config() {
  get() {
    [[ $# -eq 0 ]] && { jq . "$CONFIG"; return; }
    local val
    val=$(jq -r --arg k "$1" '.[$k] // empty' "$CONFIG")
    [[ -z "$val" ]] && { >&2 echo "no such key: $1"; return 1; }
    echo "$val"
  }
  set() { jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$CONFIG" | sponge "$CONFIG"; }
  "$@"
}

show-fingerprint() {
  awk '{print $1}' <(adb pubkey ~/.android/adbkey) | openssl base64 -A -d | openssl md5 -c | awk '{print $2}' | tr '[:lower:]' '[:upper:]'
}

test() {
  apt-update-if-stale() {
    local cache=/var/cache/apt/pkgcache.bin max_age=$((10 * 24 * 3600))
    [[ -f "$cache" && $(($(date +%s) - $(stat -c %Y "$cache"))) -lt $max_age ]] && return
    apt update
  }
  1() {
    docker build -t ratphone-test "$SCRIPT_DIR"
    docker run -it --rm --privileged -v "$SCRIPT_DIR":/root ratphone-test bash
  }
  2() {
    apt-update-if-stale
    apt install -y android-tools-adb jq openssl moreutils less
    adb start-server
    echo "=== e2e tests ==="
    config get
  }
  "$@"
}

usage() { >&2 cat <<'EOF'
Usage: ratphone.sh <command> [args...]

Commands:
  config            get/set config values
  show-fingerprint  display adb pubkey fingerprint
  test              docker test harness (1=run, 2=in-docker)
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
