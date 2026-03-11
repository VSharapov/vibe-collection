# Draft 1 Report

## Changes

Initial implementation of all planned functionality.

## Test results

| Test | Result |
|------|--------|
| `usage` | PASS - displays help |
| `domains` | PASS - lists domains |
| `list example.com` | PASS - shows records, tab-separated |
| `create example.com A test-draft1 1.2.3.4` | PASS - returns JSON with id |
| `get example.com <id>` | PASS - shows single record |
| `update example.com <id> A test-draft1 5.6.7.8` | PASS - updates answer |
| `delete example.com <id>` | PASS - empty response |
| `get example.com <id>` (after delete) | PASS - 404 error, exit 1 |
| `create example.com MX @ mail.test.com --priority 20` | PASS - priority included |

## Bugs found

None.

## Improvement ideas

- [ ] Add `--ttl` option test coverage
- [x] Add TXT record test (quoting edge cases)
- [ ] Header row for `list` output (opt-in with `--header`?)
- [ ] `list` output could use `column -t` for alignment
- [ ] `create`/`update` could output the TSV format instead of JSON for consistency
- [x] Error message could show the full URL for debugging
  - As long as no secrets would be printed
- [ ] Missing config file should have friendlier error message
- [ ] Add `--json` flag to force JSON output everywhere
- [x] Add functionality to determine external IP with fallback:
  - dig +short txt ch whoami.cloudflare @1.1.1.1 | sed 's/"//g'
  - dig @ns1.google.com TXT o-o.myaddr.l.google.com +short | sed 's/"//g'
  - curl -s http://whatismyip.akamai.com/
  - curl -s https://api.ipify.org
  - curl -s ifconfig.me
  - curl -s icanhazip.com
