# Testing

## Without sudo

Test plumbing functions directly:

```bash
./script.sh usage
./script.sh some-plumbing arg1 arg2
./script.sh another-plumbing < input.txt
```

## With sudo

Don't invoke sudo repeatedly from the agent. Batch it.

1. Write `test-draftN.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
sudo true  # auth once

run() { echo "--- $* ---"; "$@" || echo "EXIT: $?"; }

rm -f /tmp/test-output  # sticky bit safety
run ./script.sh func1 arg
run ./script.sh func2 arg
```

2. Tell user:

> Run: `./test-draftN.sh 2>&1 | tee /tmp/test.log`

3. Await response, read `/tmp/test.log`, diagnose, iterate.

## Sticky bit note

`/tmp` has sticky bit. With `fs.protected_regular=1`, you can't redirect to a file owned by another user. Always `rm -f` before redirecting.
