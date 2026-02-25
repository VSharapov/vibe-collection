# deterministic-ed25519

Generate deterministic Ed25519 SSH keypairs from a seed string.

## Usage

```bash
# Generate keypair
./seedkey.sh generate "my secret seed" ~/.ssh/id_ed25519

# Plumbing (pipe-friendly)
./seedkey.sh seed-to-pem "my secret seed" > key.pem
./seedkey.sh pem-to-private < key.pem > id_ed25519
./seedkey.sh pem-to-pub < key.pem > id_ed25519.pub
```

## Dependencies

`bash`, `openssl`, `xxd`, `base64`, `fold`, `od`

Ubuntu: `apt install openssl xxd`

## Install

```bash
make install  # copies to /usr/local/bin/seedkey
```
