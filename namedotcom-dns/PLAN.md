# DNS Management via Name.com API

Shell script to manage DNS records for domains hosted on name.com

## User story

```bash
# Credentials loaded automatically from ~/.config/namedotcom/*.env

# List all records for a domain
./dns.sh list example.com

# Create records
./dns.sh create example.com A www 1.2.3.4
./dns.sh create example.com A @ 1.2.3.4
./dns.sh create example.com CNAME blog www.example.com
./dns.sh create example.com MX @ mail.example.com --priority 10
./dns.sh create example.com TXT @ "v=spf1 include:_spf.google.com ~all"

# Update a record by ID
./dns.sh update example.com 12345 A www 5.6.7.8

# Delete a record by ID
./dns.sh delete example.com 12345

# Get a single record
./dns.sh get example.com 12345

# List domains in account
./dns.sh domains
```

## Configuration

Credentials are sourced from `~/.config/namedotcom/*.env`. The script sources all `.env` files in that directory.

Example `~/.config/namedotcom/production.env`:
```bash
DNS_TOKEN_USERNAME="vasiliysh"
DNS_TOKEN_NAME="production"
DNS_TOKEN_SECRET="abc123..."
DNS_TOKEN_ENDPOINT="https://api.name.com"
```

Example `~/.config/namedotcom/sandbox.env`:
```bash
DNS_TOKEN_USERNAME="vasiliysh-test"
DNS_TOKEN_NAME="sandbox"
DNS_TOKEN_SECRET="def456..."
DNS_TOKEN_ENDPOINT="https://api.dev.name.com"
```

| Variable | Description |
|----------|-------------|
| `DNS_TOKEN_USERNAME` | name.com username (with `-test` suffix for sandbox) |
| `DNS_TOKEN_NAME` | Human-readable label for this token |
| `DNS_TOKEN_SECRET` | API token |
| `DNS_TOKEN_ENDPOINT` | API base URL |

Additional env vars (optional, can be set in `.env` or shell):

| Variable | Default | Description |
|----------|---------|-------------|
| `DNS_TTL` | `300` | Default TTL for new records |

## Function table

### Plumbing (internal, composable)

| Function | Description |
|----------|-------------|
| `load-config` | Source all `~/.config/namedotcom/*.env` files |
| `api` | Make authenticated API call, handle errors |
| `require-env` | Check required env vars are set |
| `json-record` | Build JSON body for create/update |

### Porcelain (user-facing)

| Function | Description |
|----------|-------------|
| `list` | List all DNS records for a domain (formatted table) |
| `get` | Get single record by ID |
| `create` | Create a new DNS record |
| `update` | Update existing record by ID |
| `delete` | Delete record by ID |
| `domains` | List all domains in account |
| `usage` | Print help |

## API details

Base: `/core/v1`

| Operation | Method | Endpoint |
|-----------|--------|----------|
| List records | GET | `/domains/{domain}/records` |
| Get record | GET | `/domains/{domain}/records/{id}` |
| Create record | POST | `/domains/{domain}/records` |
| Update record | PUT | `/domains/{domain}/records/{id}` |
| Delete record | DELETE | `/domains/{domain}/records/{id}` |
| List domains | GET | `/domains` |

Record types: A, AAAA, ANAME, CNAME, MX, NS, SRV, TXT

Required fields for create: `type`, `host`, `answer`
Optional: `ttl` (default 300), `priority` (MX/SRV only)

## Output format

- `list`: tab-separated table with columns: ID, TYPE, HOST, ANSWER, TTL, PRIORITY
- `get`: same single-row format
- `create`/`update`/`delete`: JSON response from API (for scripting)
- `domains`: one domain per line

## Dependencies

- `curl` — HTTP client
- `jq` — JSON parsing (required)

## Open questions

- [ ] Should `list` support filtering by type or host?
- [ ] Should there be a `find` command to search records by host/type?
- [ ] Pagination for large record sets?
  - I hope not, we'll see if the API has this deranged behavior
- [x] Multiple `.env` files: source all and last one wins, or select by `DNS_TOKEN_NAME`?
  - Like I said, source *.env - nothing clever.
