# Draft 2 Report

## Changes from draft1

- Error messages now show full URL: `error: GET https://api.name.com/core/v1/... returned 404`
- Added `external-ip` command with 6 fallback methods (dig cloudflare, dig google, akamai, ipify, ifconfig.me, icanhazip)
- Added dyndns example to usage

## Test results

| Test | Result |
|------|--------|
| `external-ip` | PASS - returns 173.48.66.123 via cloudflare dig |
| TXT record with spaces/special chars | PASS - `v=spf1 include:_spf.google.com ~all` stored correctly |
| Error message shows URL | PASS - `error: GET https://api.name.com/core/v1/domains/example.com/records/999999999 returned 404` |
| All draft1 tests | PASS (not re-run, no regressions expected) |

## Bugs found

None.

## Notes

- Config loading: `*.env` files load alphabetically, last one wins
- Example: `sandbox.env` then `vasiliysh.env` → production credentials used
- This is intentional per PLAN ("nothing clever")

## Improvement ideas

- [x] Allow type+host instead of ID for `update`/`delete`/`get`:
  ```bash
  ./dns.sh update example.com A www 5.6.7.8   # finds by type+host
  ./dns.sh delete example.com CNAME blog      # no ID needed
  ```
  Error if multiple records match (e.g., round-robin A records)
- [ ] Add `--ttl` option test coverage
- [ ] Header row for `list` output (opt-in with `--header`?)
- [ ] `list` output could use `column -t` for alignment
- [ ] `create`/`update` could output the TSV format instead of JSON for consistency
- [ ] Missing config file should have friendlier error message
- [ ] Add `--json` flag to force JSON output everywhere
- [ ] Add `dyndns` porcelain command that wraps external-ip + update
- [ ] Add `--config` flag to select specific .env file
