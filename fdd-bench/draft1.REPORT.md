# draft1 Test Report

## What was tested

| Test | Result |
|---|---|
| `bash -n` syntax check | PASS |
| `usage` | PASS — prints to stderr |
| `find-big-file /media/vasiliy/Ventoy` | PASS — `isos/windows/Win11_24H2_English_x64_20250106.iso` (5.5G, largest) |
| `find-big-file /media/vasiliy/Metal234GiB` | PASS — `isos/ubuntu-22.04.5-desktop-amd64.iso` |
| `file-size-mib` on 4.5G ISO | PASS — `4542` |
| `random-offset 1024 128` (x5) | PASS — varied values, all in [0, 896] |
| `random-offset 4500 128` (x5) | PASS — varied values, all in [0, 4372] |
| `random-offset 128 128` (edge: exact fit) | PASS — returns 0 |
| `random-offset 100 128` (edge: too small) | PASS — returns 0 (clamped) |
| `timed-write` 4 MiB to /tmp | PASS — `write 1 0 0.02 165.6` |
| `timed-write` 4 MiB to actual flash (Metal234GiB) | PASS — `write 1 0 0.08 51.6` |
| `timed-read` 4 MiB from /tmp | PASS — needs sudo for drop-caches |
| `timed-read` 4 MiB from exfat flash (iflag=direct) | PASS — `read 1 0 0.04 112.2` |
| `clean` | PASS |
| `gnuplot` with synthetic 8-round TSV | PASS — nice ASCII art |
| `pngplot` with synthetic TSV | PASS — valid 1200x600 PNG |
| No args (`./fdd-bench.sh`) | Silently exits 0 — not great |

## Issues found

1. **No-args = silent success.** `"$@"` with no args just runs nothing and exits 0. Should default to `usage`.
2. **`dd status=progress`** in `init` sends progress to stderr — fine for interactive use, but it goes to stderr alongside the `echo` path on stdout. Works, but `full-bench` captures stdout cleanly so this is OK. Cosmetic: dd's final summary line (bytes copied) is noise on stderr during full-bench.
3. **PLAN says `iflag=skip_bytes`** but the script uses `skip=N` with `bs=1M`, so skip is already in MiB blocks. Consistent, but plan and code disagree. Minor doc issue.

## Improvement ideas

- [x] /tmp/fdd-bench-test-data.tsv is alright, but even better would be a `mktemp /tmp/$0.$(date +%s).XXX`, but I guess that's up to the function that invokes it,
- [x] No-args should print `usage` (add `if [[ $# -eq 0 ]]; then usage; exit 1; fi` before `"$@"`)
- [x] `init` is slow (~15-20s for 1 GiB from urandom). Could use `openssl rand` or `shuf` seeded into dd for speed, or just accept it
  - Do a little mini benchmark in /tmp and write fallback logic in case `which openssl` fails. Write /tmp/randBench.REPORT.md - for my curiosity.
- [x] The `full-bench` summary could detect plateau (the user story mentions "Write speed plateau detected at..."). Currently just prints avg/min/max
- [x] `find-big-file` uses `find -maxdepth 4` — arbitrary. Could drop the limit, or make it configurable
  - For any arbitrary value just use a pattern where it's env-managed: FDD_BENCH_FIND_BIG_FILE_MAXDEPTH=${FDD_BENCH_FIND_BIG_FILE_MAXDEPTH:-4}
- [x] Consider `oflag=direct` on writes too (bypass page cache on write side). Currently relying on `conv=fsync` which flushes but still goes through page cache first
  - Sounds like it's worth a try
- [x] The gnuplot/pngplot functions can't read from stdin (`${1:--}` is `-` but awk with `-` as filename may not work everywhere). Should handle stdin explicitly via `cat "$datafile"` piped to awk, or use `/dev/stdin`
- [X] Round count is only configurable via `full-bench` arg. Could also honor an env var like `FDD_BENCH_ROUNDS=16`
  - In fact don't even use an arg - env only
- [x] Chunk size (128 MiB) and source size (1 GiB) are hardcoded globals. Could be env-var configurable
- [x] The plot doesn't show the drive name/label in the title. `full-bench` could accept an optional label, or auto-detect from mountpoint basename
  - I think the mount point is the only arg, and should be the title
- [x] `timed-read` calls `drop-caches` every round (needs sudo every time). Works, but could prompt once at start or check if already root
- [ ] dd `conv=fsync` flushes the single file, but doesn't guarantee the USB controller's internal write cache is flushed. Could add a `sync` + `hdparm -F /dev/sdX` for belt-and-suspenders, but that's probably overkill
- [ ] `RANDOM` is 15-bit (0–32767). Fine for our offsets but technically has modulo bias. `shuf -i 0-N -n1` would be unbiased
- [ ] `pngplot` writes to stdout — could optionally accept an output filename
- [ ] No `set -x` / `self-test` subcommand like the tts script has

