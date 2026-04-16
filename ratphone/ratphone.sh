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

usage() { >&2 echo "Usage: ratphone.sh <config|show-fingerprint> [args...]"; }

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
