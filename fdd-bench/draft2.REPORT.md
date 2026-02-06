# draft2 Test Report

## Changes from draft1

1. **No-args → usage + exit 1** — `if [[ $# -eq 0 ]]` guard before `"$@"`
2. **openssl rand** with dd/urandom fallback — 2x faster (see /tmp/randBench.REPORT.md)
3. **Plateau detection** — `detect-plateau` function: compares first-half avg to second-half avg, reports drop if ≤80%
4. **All config via env vars** — `FDD_BENCH_ROUNDS`, `FDD_BENCH_CHUNK_MIB`, `FDD_BENCH_SRC_SIZE_MIB`, `FDD_BENCH_FIND_MAXDEPTH`, `FDD_BENCH_PLOT_TITLE`
5. **`oflag=direct`** on writes — bypasses page cache on write side too
6. **`ensure-sudo`** — pre-authenticates sudo at start of `full-bench` so it doesn't prompt mid-benchmark
7. **stdin support for gnuplot/pngplot** — buffers to variable, then splits (fixed SIGPIPE bug from first attempt)
8. **Plot title** from `FDD_BENCH_PLOT_TITLE` env var or defaults; `full-bench` labels with basename of mountpoint
9. **`find-big-file` maxdepth** configurable via `FDD_BENCH_FIND_MAXDEPTH`

## What was tested

| Test | Result |
|---|---|
| No args | PASS — prints usage, exits 1 |
| `init 4` (small, uses openssl) | PASS — creates 4 MiB file, prints path |
| `detect-plateau` declining data | PASS — `plateau detected at 37.8 MB/s (dropped from 71.2 MB/s)` |
| `detect-plateau` stable data | PASS — `no plateau detected (avg 49.9 MB/s)` |
| `detect-plateau` 2 data points | PASS — `too few data points` |
| `timed-write` with `oflag=direct` to exfat flash | PASS — 53.4 MB/s |
| `gnuplot` from stdin pipe | PASS (after fixing stdin double-read bug) |
| `pngplot` from stdin pipe | PASS — valid PNG |
| `gnuplot` with `FDD_BENCH_PLOT_TITLE` | PASS — title shows in plot |
| `full-bench` mini run (2 rounds, 4 MiB chunks) on Metal234GiB | PASS — write ~50 MB/s, read ~117 MB/s |
| `full-bench` stderr labels | PASS — shows `[Metal234GiB]` prefix from basename |
| env var overrides (`ROUNDS`, `CHUNK_MIB`, `SRC_SIZE_MIB`) | PASS |
| `clean` | PASS |

## Bugs found and fixed during testing

1. **gnuplot/pngplot stdin SIGPIPE** — first `awk` consumed all of stdin, second got nothing. Fixed by buffering to variable first.

## Remaining ideas (not implemented)

- [x] non-current drafts can be deleted now, right? Since the patch exists? If yes - remove.
- [x] reduce the number of `sudo` invocations to 1 per draft
  - From now on make an invoker script, e.g. draft3.invoker.sh - this should do all the test you can concieve of in one batch, instead of one test at a time. I know this makes iterating harder, oh well.
- [x] `detect-plateau` is simplistic (first-half vs second-half average). Could use a proper moving-average or sliding-window approach
  - I think if the change is _positive_ (i.e. reversed) consider it done. Maybe rename from plateau to detect-finished.
  - If the change is negative but <0.5% consider it done. (env overwritable of course)
- [x] The `full-bench` stderr could include a timestamp per line (for correlating with `dmesg` if something goes wrong)
- [ ] `full-bench` stdout/stderr interleave looks messy when not redirecting stdout — could add a `--tee` mode that writes TSV to a tempfile and only shows stderr live, then cats TSV at the end
- [ ] The `ensure-sudo` check at the start is good, but if the benchmark takes longer than sudo's timeout (default 15 min), it'll stall mid-run. Could `sudo -v` in background periodically
- [ ] No validation that mountpoint is actually a removable drive — would be bad if someone accidentally pointed at `/`
- [ ] Could auto-run both drives in sequence: `full-bench-all` that discovers all /media/$USER/... mounts
