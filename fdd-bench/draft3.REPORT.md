# draft3 Test Report

## Changes from draft2

1. **`detect-plateau` → `detect-finished`** — new logic:
   - Second half avg >= first half → "stabilized (recovered from ...)"
   - Drop < `FDD_BENCH_STABLE_THRESHOLD` (default 5%) → "stabilized at ..."
   - Otherwise → "still declining: X → Y MB/s (Z% drop)"
2. **Timestamps on stderr** — all `full-bench` progress lines prefixed with `[HH:MM:SS]`
3. **`drop-caches` / `ensure-sudo` check EUID** — skip sudo when already root
4. **Default stable threshold** raised from 0.5% to 5% (more realistic for noisy flash data)
5. **`FDD_BENCH_STABLE_THRESHOLD`** env var added to config section + usage

## Invoker test results (sudo run)

**27 passed, 0 failed.**

All tests pass including mini full-bench with timestamps and drive label in stderr.

### Bug found and fixed during testing

`fs.protected_regular` on `/tmp`: when the invoker runs as root, it can't overwrite temp files owned by another user in the sticky `/tmp` directory. Fixed by adding `rm -f` before each redirect to a `/tmp` file.

## Improvements needed

- [x] `sync` before `echo 3 > /proc/sys/vm/drop_caches`

