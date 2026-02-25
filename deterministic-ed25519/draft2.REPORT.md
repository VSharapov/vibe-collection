# Draft 2 Report

## Changes from Draft 1

- Fixed `pem-to-private`: now constructs valid OpenSSH private key format
  - Added pubkey field before privkey (OpenSSH stores it twice)
  - Dynamic padding calculation based on comment length
  - Correct length field for private section
- Fixed `pem-to-pub`: working ssh-ed25519 public key line output

## Test Results

| Test | Result |
|------|--------|
| `seed-to-pem` outputs valid PEM | PASS |
| `pem-to-private` outputs valid OpenSSH key | PASS |
| `pem-to-pub` outputs valid ssh-ed25519 line | PASS |
| `generate` creates both files with correct perms | PASS |
| `ssh-keygen -y` validates generated private key | PASS |
| Works in Ubuntu 22.04 Docker (with openssl, xxd, openssh-client) | PASS |
| Public key is deterministic across runs | PASS |

## Dependencies

Requires: `bash`, `openssl`, `xxd`, `base64`, `fold`, `od`

On Ubuntu 22.04 minimal: `apt install openssl xxd openssh-client`

## Bugs Found and Fixed

- Draft 1: `pem-to-private` used `-outform openssh` which isn't available in OpenSSL 3.0.x
- Draft 1: `pem-to-pub` used `ssh-keygen -i -m PKCS8` which doesn't support Ed25519
- Draft 2: Fixed by manually constructing OpenSSH wire format

## Improvement Ideas

- [x] Make checkint deterministic (derive from seed) for fully reproducible private key files
  - Determinism was the whole point
- [ ] Remove `xxd` dependency (use pure bash hex conversion)
- [ ] Add `--force` flag to `generate` to overwrite existing files
- [ ] Add signing/verification plumbing functions
- [ ] Support reading seed from stdin for better security (avoid ps visibility)
  - No need if the files are properly umasked
