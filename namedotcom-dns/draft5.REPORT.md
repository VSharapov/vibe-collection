# Draft 5 Report

## Changes from draft4

- Added `dyndns` subcommand for cron-friendly dynamic DNS updates
- Derives nameserver from domain via `dig NS domain +short`
- Queries authoritative NS directly for current A record
- Only updates if IP changed; outputs status either way

## Usage

```bash
namedotcom-dns.sh dyndns datacenter1.sites example.com
# unchanged: datacenter1.sites.example.com -> 203.0.113.42
# or
# updated: datacenter1.sites.example.com 203.0.113.1 -> 203.0.113.42
```

## Crontab

```
*/5 * * * * /path/to/namedotcom-dns.sh dyndns datacenter1.sites example.com
```

## Test results

| Test | Result |
|------|--------|
| `dyndns datacenter1.sites example.com` | PASS |
| NS discovery | PASS - found nameserver via dig |
| Synced to voulge | PASS |

## Improvement ideas

- [ ] Quiet mode (`-q`) for cron — no output unless change/error
- [ ] Log to syslog via `logger` on change
- [ ] Support multiple host+domain pairs from config file
