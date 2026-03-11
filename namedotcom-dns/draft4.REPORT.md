# Draft 4 Report (Final)

## Changes from draft3

- Renamed `dns.sh` to `namedotcom-dns.sh`
- Usage now uses `$(basename "$0")` for script name references
- Added `is-ipv4` validator function
- `external-ip` now validates each response before accepting it

## Test results

| Test | Result |
|------|--------|
| `./namedotcom-dns.sh usage` | PASS - shows "namedotcom-dns.sh" in output |
| `./namedotcom-dns.sh external-ip` | PASS - returns 173.48.66.123 (validated) |
| Makefile updated | PASS - targets renamed |

## Files

```
namedotcom-dns.sh    # final script
draft1.patch         # initial implementation
draft2.patch         # external-ip, error URLs
draft3.patch         # type+host resolution
draft4.patch         # rename, ipv4 validation
Makefile             # builds from patches
PLAN.md              # original spec
```
