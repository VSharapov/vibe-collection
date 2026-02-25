# Deterministic Ed25519 SSH Key Generator

## User Story

```bash
# Plumbing: step by step
./seedkey.sh seed-to-pem "my secret passphrase"     | (umask 077; tee ~/.ssh/id_ed25519.pem)
./seedkey.sh pem-to-private < ~/.ssh/id_ed25519.pem | (umask 077; tee ~/.ssh/id_ed25519)
./seedkey.sh pem-to-pub < ~/.ssh/id_ed25519.pem     | (umask 022; tee ~/.ssh/id_ed25519.pub)
rm ~/.ssh/id_ed25519.pem

# Porcelain: equivalent to above
./seedkey.sh generate "my secret passphrase" ~/.ssh/id_ed25519
# Creates ~/.ssh/id_ed25519 (mode 600) and ~/.ssh/id_ed25519.pub (mode 644)
# Exits with warning if any of those files already exist
```

## Function Table

### Plumbing

| Function | stdin | stdout | Description |
|----------|-------|--------|-------------|
| `seed-to-pem` | - | PEM | SHA256 seed → PKCS#8 Ed25519 private key |
| `pem-to-private` | PEM | OpenSSH privkey | Convert PKCS#8 → OpenSSH private key format |
| `pem-to-pub` | PEM | ssh-ed25519 line | Extract public key in SSH format |

### Porcelain

| Function | args | stdout | stderr | Description |
|----------|------|--------|--------|-------------|
| `generate` | seed, path | - | progress | Write path (600) and path.pub (644), fail if exist |

## Details

### seed-to-pem
1. Read seed from $1
2. SHA256 hash to 32 bytes
3. Prepend PKCS#8 DER header: `302e020100300506032b657004220420`
4. Base64 encode
5. Wrap in PEM armor

### pem-to-private
1. `openssl pkey -inform PEM -outform openssh`
2. Requires OpenSSL 3.x

### pem-to-pub
1. `openssl pkey -pubout` to get PEM public key
2. `ssh-keygen -i -m PKCS8` to convert to ssh-ed25519 line

### generate
1. Check if $2 or $2.pub exist, exit 1 with warning if so
2. Pipe through: seed-to-pem | tee to temp | pem-to-private > $2; pem-to-pub < temp > $2.pub
3. chmod 600 $2, chmod 644 $2.pub
4. Clean up temp

## Open Questions

- [x] OpenSSH format: OpenSSL 3.x has `-outform openssh`, older versions don't. Require 3.x or fallback?
  - require, check
- [x] Comment field in pubkey: empty? configurable via env var?
  - reasonable default overwritten if env var
- [x] Should seed be read from stdin instead of arg (avoid showing in ps)?
- [x] Filename: `seedkey.sh`?
  - sgtm
