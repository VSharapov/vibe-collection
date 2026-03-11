# Draft 3 Report

## Changes from draft2

- `get`, `update`, `delete` now accept type+host instead of ID:
  ```bash
  ./dns.sh get example.com CNAME www          # instead of: get example.com 12345
  ./dns.sh update example.com A home 1.2.3.4  # finds record, updates answer
  ./dns.sh delete example.com CNAME blog      # no ID needed
  ```
- Added `is-record-type` helper to detect A/AAAA/ANAME/CNAME/MX/NS/SRV/TXT
- Added `resolve-id` helper to find record ID by type+host
- Errors on ambiguity (multiple records) or not found
- Updated usage with new syntax variants

## Test results

| Test | Result |
|------|--------|
| `get example.com CNAME www` | PASS - returns same as `get example.com <id>` |
| `get example.com MX @` | PASS - apex record works |
| `update example.com A test-draft3 2.2.2.2` | PASS - finds and updates |
| `delete example.com A test-draft3` | PASS - finds and deletes |
| `get example.com A nonexistent` | PASS - error: no A record found for host 'nonexistent' |
| Multiple records (round-robin) | PASS - error: multiple A records found... use ID directly |
| ID-based commands | PASS - still work unchanged |

## Bugs found

None.

## Improvement ideas

- [x] Replace mentions of dns.sh in the script with $0
- [x] Rename dns.sh to namedotcom-dns.sh in makefile and wherever else
- [x] Add a validate_ipv4 helper function
  - The external IP checker should validate the output || fallback
- [ ] Add `--ttl` option test coverage
- [ ] Header row for `list` output (opt-in with `--header`?)
- [ ] `list` output could use `column -t` for alignment
- [ ] `create`/`update` could output the TSV format instead of JSON for consistency
- [ ] Missing config file should have friendlier error message
- [ ] Add `--json` flag to force JSON output everywhere
- [ ] Add `dyndns` porcelain command that wraps external-ip + update
- [ ] Add `--config` flag to select specific .env file
- [ ] `list --type A` or `list --host www` filtering
