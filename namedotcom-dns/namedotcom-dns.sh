#!/usr/bin/env bash
set -euo pipefail

DNS_TTL="${DNS_TTL:-300}"
DNS_CONFIG_DIR="${DNS_CONFIG_DIR:-$HOME/.config/namedotcom}"

load-config() {
  local f
  for f in "$DNS_CONFIG_DIR"/*.env; do
    [[ -f "$f" ]] && source "$f"
  done
}

require-env() {
  local missing=()
  [[ -z "${DNS_TOKEN_USERNAME:-}" ]] && missing+=(DNS_TOKEN_USERNAME)
  [[ -z "${DNS_TOKEN_SECRET:-}" ]] && missing+=(DNS_TOKEN_SECRET)
  [[ -z "${DNS_TOKEN_ENDPOINT:-}" ]] && missing+=(DNS_TOKEN_ENDPOINT)
  if [[ ${#missing[@]} -gt 0 ]]; then
    >&2 echo "error: missing required env vars: ${missing[*]}"
    >&2 echo "configure in $DNS_CONFIG_DIR/*.env"
    exit 1
  fi
}

api() {
  local method="$1" path="$2"
  shift 2
  local url="${DNS_TOKEN_ENDPOINT}/core/v1${path}"
  local response http_code
  response=$(curl -s -w '\n%{http_code}' \
    -u "${DNS_TOKEN_USERNAME}:${DNS_TOKEN_SECRET}" \
    -X "$method" \
    -H 'Content-Type: application/json' \
    "$@" \
    "$url")
  http_code=$(tail -n1 <<< "$response")
  response=$(sed '$d' <<< "$response")
  if [[ "$http_code" -ge 400 ]]; then
    >&2 echo "error: $method $url returned $http_code"
    >&2 echo "$response" | jq -r '.message // .error // .' 2>/dev/null || >&2 echo "$response"
    exit 1
  fi
  echo "$response"
}

is-ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS='.'
  read -ra octets <<< "$ip"
  for octet in "${octets[@]}"; do
    (( octet <= 255 )) || return 1
  done
  return 0
}

external-ip() {
  local ip
  ip=$(dig +short txt ch whoami.cloudflare @1.1.1.1 2>/dev/null | sed 's/"//g') && is-ipv4 "$ip" && { echo "$ip"; return; }
  ip=$(dig @ns1.google.com TXT o-o.myaddr.l.google.com +short 2>/dev/null | sed 's/"//g') && is-ipv4 "$ip" && { echo "$ip"; return; }
  ip=$(curl -s --max-time 5 http://whatismyip.akamai.com 2>/dev/null) && is-ipv4 "$ip" && { echo "$ip"; return; }
  ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) && is-ipv4 "$ip" && { echo "$ip"; return; }
  ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null) && is-ipv4 "$ip" && { echo "$ip"; return; }
  ip=$(curl -s --max-time 5 icanhazip.com 2>/dev/null) && is-ipv4 "$ip" && { echo "$ip"; return; }
  >&2 echo "error: could not determine external IP"
  exit 1
}

dyndns() {
  local host="$1" domain="$2"
  local fqdn="${host}.${domain}"
  [[ "$host" == "@" ]] && fqdn="$domain"
  
  local ns
  ns=$(dig NS "$domain" +short | head -1)
  if [[ -z "$ns" ]]; then
    >&2 echo "error: could not determine nameserver for $domain"
    exit 1
  fi
  
  local dns_ip ext_ip
  dns_ip=$(dig "@${ns}" "$fqdn" A +short | head -1)
  ext_ip=$(external-ip)
  
  if [[ "$dns_ip" != "$ext_ip" ]]; then
    update "$domain" A "$host" "$ext_ip" >/dev/null
    echo "updated: $fqdn $dns_ip -> $ext_ip"
  fi
}

json-record() {
  local type="$1" host="$2" answer="$3"
  local ttl="${4:-$DNS_TTL}"
  local priority="${5:-}"
  local json
  json=$(jq -n \
    --arg type "$type" \
    --arg host "$host" \
    --arg answer "$answer" \
    --argjson ttl "$ttl" \
    '{type: $type, host: $host, answer: $answer, ttl: $ttl}')
  if [[ -n "$priority" ]]; then
    json=$(echo "$json" | jq --argjson p "$priority" '. + {priority: $p}')
  fi
  echo "$json"
}

is-record-type() {
  case "$1" in
    A|AAAA|ANAME|CNAME|MX|NS|SRV|TXT) return 0 ;;
    *) return 1 ;;
  esac
}

resolve-id() {
  local domain="$1" type="$2" host="$3"
  [[ "$host" == "@" ]] && host=""
  local ids
  ids=$(api GET "/domains/${domain}/records" | jq -r --arg t "$type" --arg h "$host" '
    [.records[] | select(.type == $t and (.host // "") == $h) | .id] | join(" ")
  ')
  local count
  count=$(wc -w <<< "$ids")
  if [[ "$count" -eq 0 ]]; then
    >&2 echo "error: no $type record found for host '$host'"
    exit 1
  elif [[ "$count" -gt 1 ]]; then
    >&2 echo "error: multiple $type records found for host '$host' (ids: $ids)"
    >&2 echo "use record ID directly to disambiguate"
    exit 1
  fi
  echo "$ids"
}

# --- Porcelain ---

list() {
  local domain="$1"
  api GET "/domains/${domain}/records" | jq -r '
    .records[]? |
    [.id, .type, .host // "@", .answer, .ttl, .priority // ""] |
    @tsv
  '
}

get() {
  local domain="$1" id_or_type="$2"
  local id
  if is-record-type "$id_or_type"; then
    local host="${3:-@}"
    id=$(resolve-id "$domain" "$id_or_type" "$host")
  else
    id="$id_or_type"
  fi
  api GET "/domains/${domain}/records/${id}" | jq -r '
    [.id, .type, .host // "@", .answer, .ttl, .priority // ""] |
    @tsv
  '
}

create() {
  local domain="$1" type="$2" host="$3" answer="$4"
  shift 4
  local ttl="$DNS_TTL" priority=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ttl) ttl="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      *) >&2 echo "error: unknown option $1"; exit 1 ;;
    esac
  done
  local json
  json=$(json-record "$type" "$host" "$answer" "$ttl" "$priority")
  api POST "/domains/${domain}/records" -d "$json"
}

update() {
  local domain="$1" id_or_type="$2"
  local id type host answer
  if is-record-type "$id_or_type"; then
    type="$id_or_type"
    host="$3"
    answer="$4"
    id=$(resolve-id "$domain" "$type" "$host")
    shift 4
  else
    id="$id_or_type"
    type="$3"
    host="$4"
    answer="$5"
    shift 5
  fi
  local ttl="$DNS_TTL" priority=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ttl) ttl="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      *) >&2 echo "error: unknown option $1"; exit 1 ;;
    esac
  done
  local json
  json=$(json-record "$type" "$host" "$answer" "$ttl" "$priority")
  api PUT "/domains/${domain}/records/${id}" -d "$json"
}

delete() {
  local domain="$1" id_or_type="$2"
  local id
  if is-record-type "$id_or_type"; then
    local host="${3:-@}"
    id=$(resolve-id "$domain" "$id_or_type" "$host")
  else
    id="$id_or_type"
  fi
  api DELETE "/domains/${domain}/records/${id}"
}

domains() {
  api GET "/domains" | jq -r '.domains[]?.domainName'
}

usage() {
  local me
  me=$(basename "$0")
  cat <<EOF
usage: $me <command> [args]

commands:
  list <domain>                         List all DNS records
  get <domain> <id>                     Get record by ID
  get <domain> <type> <host>            Get record by type+host
  create <domain> <type> <host> <answer> [--ttl N] [--priority N]
  update <domain> <id> <type> <host> <answer> [--ttl N] [--priority N]
  update <domain> <type> <host> <answer> [--ttl N] [--priority N]
  delete <domain> <id>                  Delete record by ID
  delete <domain> <type> <host>         Delete record by type+host
  domains                               List all domains in account
  external-ip                           Get external IP (for dynamic DNS)
  dyndns <host> <domain>                Update A record to external IP (if changed)

environment:
  Configure credentials in ~/.config/namedotcom/*.env
  Required: DNS_TOKEN_USERNAME, DNS_TOKEN_SECRET, DNS_TOKEN_ENDPOINT
  Optional: DNS_TTL (default 300)

examples:
  $me list example.com
  $me create example.com A www 1.2.3.4
  $me create example.com MX @ mail.example.com --priority 10
  $me delete example.com 12345
  $me delete example.com CNAME blog
  $me external-ip
  $me dyndns datacenter1.sites example.com                    # cron-friendly
EOF
}

load-config
require-env

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

"$@"
