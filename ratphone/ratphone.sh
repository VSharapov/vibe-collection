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

wifi-connect() { adb connect "$(config get PHONE_HOSTNAME):$(config get ADB_PORT)"; }

wifi-check() { adb devices | grep -q "$(config get PHONE_HOSTNAME).*device$"; }

wifi-await() { until wifi-check; do wifi-connect; sleep 2; done; }

xvfb-start() {
  pgrep -x Xvfb >/dev/null && return
  Xvfb :99 -screen 0 720x1280x24 &
  sleep 1
}

vnc-start() {
  xvfb-start
  pgrep -x x11vnc >/dev/null && return
  x11vnc -display :99 -forever -nopw -bg
}

novnc-start() {
  vnc-start
  pgrep -f websockify >/dev/null && return
  /usr/share/novnc/utils/novnc_proxy --listen 6080 --vnc localhost:5900 &
}

scrcpy-start() {
  local target="$(config get PHONE_HOSTNAME):$(config get ADB_PORT)"
  xvfb-start
  while true; do
    wifi-await
    echo "starting scrcpy..."
    DISPLAY=:99 scrcpy -s "$target" --no-audio || true
    echo "scrcpy exited, reconnecting in 3s..."
    sleep 3
  done
}

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
      -p 5900:5900 -p 6080:6080 \
      -v /dev/bus/usb:/dev/bus/usb \
      -v "$SCRIPT_DIR":/opt/ratphone \
      -v "$workdir":/root \
      -w /opt/ratphone \
      ratphone-test ./ratphone.sh test entrypoint
  }
  2() {
    apt-update-if-stale
    DEBIAN_FRONTEND=noninteractive apt install -y android-tools-adb jq openssl moreutils less
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
    
    echo "waiting for wifi connection..."
    wifi-await
    echo "phone connected via wifi adb"
    
    echo "starting novnc + scrcpy..."
    novnc-start
    scrcpy-start &
    echo "open http://localhost:6080/vnc.html"
    wait
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
  wifi-connect      adb connect to phone over wifi
  wifi-check        exit 0 if phone on wifi adb
  wifi-await        block until wifi adb connected
  xvfb-start        start virtual framebuffer
  vnc-start         start xvfb + x11vnc
  novnc-start       start xvfb + x11vnc + novnc (web)
  scrcpy-start      start scrcpy with reconnect loop
  test              docker test harness (1=run, 2=in-docker)
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
