# Terse Scripts

Prefer 10 lines that fail loudly over 60 lines that validate everything.

## Philosophy

- `set -Eeuo pipefail` catches most errors
- Annoying on misuse is a feature — teaches correct usage
- User is expected to read source and use `bash -x`
- Scripts are sharp tools, not baby-proof appliances

## What NOT to do

```bash
# Too defensive — 15 lines of validation
validate_input() {
  if [[ -z "$1" ]]; then
    echo "Error: missing argument" >&2
    return 1
  fi
  if [[ ! -f "$1" ]]; then
    echo "Error: file not found: $1" >&2
    return 1
  fi
  if [[ ! -r "$1" ]]; then
    echo "Error: file not readable: $1" >&2
    return 1
  fi
  # ... more validation ...
}
```

## What to do instead

```bash
# Let it fail — 1 line
process() { wc -l < "$1"; }
```

If `$1` is missing or not a file, `set -e` kills it. User sees the error, runs `bash -x`, learns.

## When validation IS appropriate

- Destructive operations (rm, dd, format)
- Ambiguous defaults that could cause silent wrong behavior
- User-facing porcelain where UX matters

For plumbing? Let it crash.
