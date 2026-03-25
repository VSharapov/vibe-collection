#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
DEVICES_JSON="${DEVICES_JSON:-$SCRIPT_DIR/devices.json}"

# Lease fetching: env var > local file > default ssh
if [[ -n "${GET_LEASES_COMMAND:-}" ]]; then
  get-leases-cmd() { eval "$GET_LEASES_COMMAND"; }
elif [[ -x "$SCRIPT_DIR/GET_LEASES_COMMAND" ]]; then
  get-leases-cmd() { "$SCRIPT_DIR/GET_LEASES_COMMAND"; }
else
  ROUTER_HOST="${ROUTER_HOST:-router.asus.com}"
  ROUTER_USER="${ROUTER_USER:-admin}"
  SSH_OPTS="${SSH_OPTS:--o PubkeyAcceptedKeyTypes=+ssh-rsa}"
  get-leases-cmd() { ssh $SSH_OPTS "${ROUTER_USER}@${ROUTER_HOST}" 'cat /var/lib/misc/dnsmasq.leases'; }
fi

normalize-mac() {
  tr '[:upper:]' '[:lower:]' | tr -d ':'
}

annotate() {
  local mac
  mac=$(echo "$1" | normalize-mac)
  jq -r --arg m "$mac" '.annotations[$m] // ""' "$DEVICES_JSON"
}

is-uninteresting() {
  local mac
  mac=$(echo "$1" | normalize-mac)
  [[ $(jq -r --arg m "$mac" '.uninteresting | index($m) != null' "$DEVICES_JSON") == "true" ]]
}

fetch-leases() {
  local result
  for i in {0..9}; do
    result=$(get-leases-cmd || true)
    [[ -n "$result" ]] && { echo "$result"; return; }
    sleep 0.1
  done
  # Perhaps it is truly empty...
}

show-leases() {
  echo "=== CURRENT DHCP LEASES ==="
  printf "%-19s %-15s %-30s %s\n" "MAC" "IP" "HOSTNAME" "ANNOTATION"
  printf "%-19s %-15s %-30s %s\n" "---" "--" "--------" "----------"
  fetch-leases | while read -r _exp mac ip hostname _clientid; do
    ann=$(annotate "$mac")
    printf "%-19s %-15s %-30s %s\n" "$mac" "$ip" "$hostname" "$ann"
  done | sort
}

show-offline() {
  echo "=== OFFLINE ANNOTATED DEVICES ==="
  printf "%-14s %s\n" "MAC" "ANNOTATION"
  printf "%-14s %s\n" "---" "----------"
  local -A online=()
  while read -r _exp mac _rest; do
    online[$(echo "$mac" | normalize-mac)]=1
  done < <(fetch-leases)
  jq -r '.annotations | to_entries[] | "\(.key) \(.value)"' "$DEVICES_JSON" | while read -r mac ann; do
    [[ -z "${online[$mac]:-}" ]] && printf "%-14s %s\n" "$mac" "$ann" || true
  done | sort
}

all() {
  show-leases
  echo
  show-offline
}

all-interesting() {
  show-leases | while IFS= read -r line; do
    mac=$(echo "$line" | awk '{print $1}')
    is-uninteresting "$mac" || echo "$line"
  done || true
  echo
  show-offline | while IFS= read -r line; do
    mac=$(echo "$line" | awk '{print $1}')
    is-uninteresting "$mac" || echo "$line"
  done || true
}

watch-diff() {
  local interval="${WATCH_INTERVAL:-10}"
  local fa=/tmp/asus-router-arp-annotations-a
  local fb=/tmp/asus-router-arp-annotations-b
  local old new tmp
  if [[ -f "$fa" && -f "$fb" ]]; then
    if [[ $(stat -c %Y "$fa") -le $(stat -c %Y "$fb") ]]; then
      old="$fa"; new="$fb"
    else
      old="$fb"; new="$fa"
    fi
  elif [[ -f "$fa" ]]; then
    old="$fa"; new="$fb"
  elif [[ -f "$fb" ]]; then
    old="$fb"; new="$fa"
  else
    all-interesting > "$fa"
    old="$fa"; new="$fb"
  fi
  while true; do
    sleep "$interval"
    all-interesting > "$new"
    diff "$old" "$new" || date --rfc-3339=s
    tmp="$old"; old="$new"; new="$tmp"
  done
}

usage() {
  cat >&2 <<'EOF'
Usage: main.sh <command>

Commands:
  all             Show leases + offline
  all-interesting Same but skip uninteresting devices
  watch-diff      Loop and print diffs (WATCH_INTERVAL=10)
  show-leases     Current DHCP leases with annotations
  show-offline    Annotated devices not in current leases

Environment:
  GET_LEASES_COMMAND  Shell command to fetch leases (see README.md)
  DEVICES_JSON        Path to devices.json (default: ./devices.json)
  ROUTER_HOST         Router hostname (default: router.asus.com)
  WATCH_INTERVAL      Seconds between polls (default: 10)
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }
"$@"
