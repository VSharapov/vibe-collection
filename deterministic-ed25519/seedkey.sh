#!/usr/bin/env bash
set -euo pipefail

SEEDKEY_COMMENT="${SEEDKEY_COMMENT:-}"

seed-to-pem() {
    local seed="${1:?seed required}"
    local pkcs8_header='\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'
    local der_base64
    der_base64=$( (printf "$pkcs8_header"; echo -n "$seed" | openssl sha256 -binary) | base64 )
    printf '%s\n' "-----BEGIN PRIVATE KEY-----" "$der_base64" "-----END PRIVATE KEY-----"
}

pem-to-private() {
    local pem seed pubkey checkint privlen
    pem=$(cat)

    seed=$(echo "$pem" | openssl pkey -outform DER | tail -c 32 | xxd -p -c 32)
    pubkey=$(echo "$pem" | openssl pkey -pubout -outform DER | tail -c 32 | xxd -p -c 32)
    checkint=$(echo -n "checkint:$seed" | openssl sha256 -binary | head -c 4 | od -An -tu4 | tr -d ' ')

    local commentlen=${#SEEDKEY_COMMENT}
    local contentlen=$((4 + 4 + 4 + 11 + 4 + 32 + 4 + 64 + 4 + commentlen))
    local padded=$(( (contentlen + 7) / 8 * 8 ))
    local padlen=$((padded - contentlen))
    
    {
        printf 'openssh-key-v1\x00'
        printf '\x00\x00\x00\x04none'
        printf '\x00\x00\x00\x04none'
        printf '\x00\x00\x00\x00'
        printf '\x00\x00\x00\x01'
        printf '\x00\x00\x00\x33'
        printf '\x00\x00\x00\x0bssh-ed25519'
        printf '\x00\x00\x00\x20'
        printf '%b' "$(echo "$pubkey" | sed 's/../\\x&/g')"
        printf '%b' "$(printf '%08x' "$padded" | sed 's/../\\x&/g')"
        printf '%b' "$(printf '%08x' "$checkint" | sed 's/../\\x&/g')"
        printf '%b' "$(printf '%08x' "$checkint" | sed 's/../\\x&/g')"
        printf '\x00\x00\x00\x0bssh-ed25519'
        printf '\x00\x00\x00\x20'
        printf '%b' "$(echo "$pubkey" | sed 's/../\\x&/g')"
        printf '\x00\x00\x00\x40'
        printf '%b' "$(echo "$seed" | sed 's/../\\x&/g')"
        printf '%b' "$(echo "$pubkey" | sed 's/../\\x&/g')"
        printf '%b' "$(printf '%08x' "$commentlen" | sed 's/../\\x&/g')"
        printf '%s' "$SEEDKEY_COMMENT"
        for ((i=1; i<=padlen; i++)); do printf "\\x$(printf '%02x' $i)"; done
    } | base64 | tr -d '\n' | fold -w 70 | {
        echo "-----BEGIN OPENSSH PRIVATE KEY-----"
        cat
        echo ""
        echo "-----END OPENSSH PRIVATE KEY-----"
    }
}

pem-to-pub() {
    local pubkey
    pubkey=$(openssl pkey -pubout -outform DER | tail -c 32)
    {
        printf '\x00\x00\x00\x0bssh-ed25519'
        printf '\x00\x00\x00\x20'
        printf '%s' "$pubkey"
    } | base64 | tr -d '\n' | {
        printf 'ssh-ed25519 '
        cat
        [[ -n "$SEEDKEY_COMMENT" ]] && printf ' %s' "$SEEDKEY_COMMENT"
        printf '\n'
    }
}

generate() {
    local seed="${1:?seed required}"
    local path="${2:?path required}"
    local pubpath="${path}.pub"

    if [[ -e "$path" ]]; then
        echo >&2 "error: $path already exists"
        exit 1
    fi
    if [[ -e "$pubpath" ]]; then
        echo >&2 "error: $pubpath already exists"
        exit 1
    fi

    local tmpfile
    tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" EXIT

    seed-to-pem "$seed" > "$tmpfile"
    pem-to-private < "$tmpfile" > "$path"
    chmod 600 "$path"
    pem-to-pub < "$tmpfile" > "$pubpath"
    chmod 644 "$pubpath"

    echo >&2 "wrote $path"
    echo >&2 "wrote $pubpath"
}

usage() {
    cat >&2 <<'EOF'
Usage: seedkey.sh <command> [args...]

Commands:
  seed-to-pem <seed>        Convert seed to PKCS#8 PEM private key
  pem-to-private            Convert PEM (stdin) to OpenSSH private key format
  pem-to-pub                Convert PEM (stdin) to ssh-ed25519 public key line
  generate <seed> <path>    Generate keypair at path and path.pub

Environment:
  SEEDKEY_COMMENT           Comment for public key (default: empty)
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

"$@"
