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

usb-check() { adb devices | grep -qE $'\t''device$'; }

usb-await() { until usb-check; do sleep 2; done; }

wifi-init() { adb tcpip "$(config get ADB_PORT)"; }

test() {
  apt-update-if-stale() {
    local cache=/var/cache/apt/pkgcache.bin max_age=$((10 * 24 * 3600))
    [[ -f "$cache" && $(($(date +%s) - $(stat -c %Y "$cache"))) -lt $max_age ]] && return
    apt update
  }
  1() {
    docker build -t ratphone-test "$SCRIPT_DIR"
    local workdir=/tmp/ratphone-docker-test-harness
    mkdir -p "$workdir"
    docker run -it --rm --privileged \
      -v /dev/bus/usb:/dev/bus/usb \
      -v "$SCRIPT_DIR":/opt/ratphone \
      -v "$workdir":/root \
      -w /opt/ratphone \
      ratphone-test ./ratphone.sh test entrypoint
  }
  2() {
    apt-update-if-stale
    apt install -y android-tools-adb jq openssl moreutils less
    adb start-server
    echo "=== e2e tests ==="
    
    echo "config:"
    config get
    
    echo "fingerprint:"
    show-fingerprint
    
    echo "waiting for usb..."
    usb-await
    echo "phone connected via usb"
    
    wifi-init
    echo "wifi adb enabled, you may unplug"
  }
  entrypoint() {
    select opt in "test 2" "bash"; do
      case $opt in
        "test 2") 2;;
        "bash") bash;;
        *) exit;;
      esac
    done
  }
  "$@"
}

usage() { >&2 cat <<'EOF'
Usage: ratphone.sh <command> [args...]

Commands:
  config            get/set config values
  show-fingerprint  display adb pubkey fingerprint
  usb-check         exit 0 if phone on usb
  usb-await         block until phone on usb
  wifi-init         enable wifi adb (adb tcpip)
  test              docker test harness (1=run, 2=in-docker)
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
