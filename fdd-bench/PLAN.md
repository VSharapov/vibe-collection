# Flash Drive Benchmark Plan

## User story

Say you have these two flash drives

| Label | Mount | Device | Size | FS | Read source file |
|---|---|---|---|---|---|
| Ventoy | `/media/vasiliy/Ventoy` | sda1 | 117G | exfat | `isos/linux/ubuntu-22.04.5-desktop-amd64.iso` (4.5G) |
| Metal234GiB | `/media/vasiliy/Metal234GiB` | sdb1 | 235G | exfat | `isos/ubuntu-22.04.5-desktop-amd64.iso` (4.5G) |

...and say you wanna benchmark them.
You wanna see:

- real (no caching) speed
- read and write
- over time (to see thermal throttle)
- gnuplot in the terminal
- png plot too

So you're gonna:
```bash
$ ./fdd-bench.sh find-big-file /media/vasiliy/Ventoy
isos/linux/ubuntu-22.04.5-desktop-amd64.iso
$ # Sweet, this was optional, this is an internal function of the bench test
$ time (./fdd-bench.sh full-bench /media/vasiliy/Ventoy > /tmp/bench1)
Write speed plateau detected at 6.9 MB/s
Read sped plateau detecter at 42.0 MB/s
real    4m20.000s
user    0m0.420s
sys     0m0.069s
$ # Cool!
$ for plot in gnu "png"; do ./fdd-bench.sh ${plot}plot /tmp/bench1 > /tmp/bench1.${plot}; done
$ less /tmp/bench1.gnuplot
$ # Wow, that's amazing how it plateaus
```


## Script: `fdd-bench.sh`

Follows the `"$@"` dispatch pattern (define functions, `"$@"` at bottom).
All functions are invokeable — some are user-facing, some are building blocks.

### Functions (all exposed via `"$@"`)

#### Plumbing (small, composable)

| Function | What it does |
|---|---|
| `find-big-file MOUNTPOINT` | Finds the largest file on the drive, prints its path relative to mountpoint. Handy standalone. |
| `file-size-mib FILE` | Prints size of FILE in MiB (integer). |
| `random-offset FILESIZE_MIB CHUNK_MIB` | Picks a random 1 MiB-aligned offset that fits a CHUNK_MIB chunk inside FILESIZE_MIB. Prints the offset in MiB. |
| `init` | `mktemp /tmp/fdd-bench-XXXXXXXX.bin`, fills it with 1 GiB from `/dev/urandom`, prints the path. Caller captures it. |
| `drop-caches` | `echo 3 > /proc/sys/vm/drop_caches` (needs sudo). |
| `timed-write SRC_FILE OFFSET_MIB DEST_FILE CHUNK_MIB` | One write round. dd with `conv=fsync`. Prints TSV line to stdout: `write\tROUND_IDX\tOFFSET\tSECONDS\tMBPS`. Progress to stderr. |
| `timed-read SRC_FILE OFFSET_MIB CHUNK_MIB` | One read round. Drops caches, dd with `iflag=direct`. Prints TSV line to stdout. Progress to stderr. |
| `clean MOUNTPOINT` | Removes `MOUNTPOINT/fdd-bench-output.bin`. |

#### Porcelain (orchestration)

| Function | What it does |
|---|---|
| `usage` | Print help with examples (like the user story above). |
| `full-bench MOUNTPOINT [ROUNDS]` | The main event. Auto-discovers big file via `find-big-file`. Runs `init`. Alternates `timed-write` / `timed-read` for ROUNDS iterations (default 8). **stdout** = TSV data. **stderr** = human-readable progress + plateau summary. |
| `gnuplot DATAFILE` | Reads TSV from DATAFILE (or stdin), outputs a gnuplot script that renders in the terminal (dumb terminal). |
| `pngplot DATAFILE` | Reads TSV from DATAFILE (or stdin), outputs a gnuplot script that renders to PNG on stdout. |

### TSV output format (stdout of `full-bench`)

```
type	round	offset_mib	seconds	mbps
write	1	384	2.34	54.7
read	1	2048	1.12	114.3
write	2	128	2.51	51.0
read	2	512	1.05	121.9
...
```

Machine-parseable. Pipeable to gnuplot/pngplot or anything else.

### stderr during `full-bench`

```
[WRITE  1/8]  offset=384MiB  128 MiB in 2.34s  →  54.7 MB/s
[READ   1/8]  offset=2048MiB 128 MiB in 1.12s  →  114.3 MB/s
[WRITE  2/8]  offset=128MiB  128 MiB in 2.51s  →  51.0 MB/s
...
--- Summary ---
Write: avg=51.2 min=48.1 max=54.7 MB/s
Read:  avg=118.0 min=112.5 max=121.9 MB/s
```

### Write round detail

1. `random-offset` picks offset into the 1 GiB source file (aligned to 1 MiB, chunk=128 MiB).
2. `dd if=$RANDOM_FILE of=MOUNTPOINT/fdd-bench-output.bin bs=1M count=128 skip=$OFFSET iflag=skip_bytes conv=fsync`
   - `conv=fsync` ensures data + metadata flushed to device before dd exits.
   - Each round overwrites the same output file (no leftover space issues).

### Read round detail

1. `drop-caches` to evict any cached pages.
2. `random-offset` picks offset into the big file on the drive.
3. `dd if=MOUNTPOINT/BIGFILE of=/dev/null bs=1M count=128 skip=$OFFSET iflag=skip_bytes,direct`
   - `iflag=direct` bypasses page cache (O_DIRECT).

### `full-bench` sequence

```
Round  1: WRITE  128 MiB → drive
Round  1: READ   128 MiB ← drive
Round  2: WRITE  128 MiB → drive
Round  2: READ   128 MiB ← drive
...
Round  8: WRITE  128 MiB → drive
Round  8: READ   128 MiB ← drive
```

16 I/O operations total (8 writes, 8 reads), alternating. Enough sustained I/O to observe thermal throttle.

## Anti-caching strategy

- **Writes**: `conv=fsync` forces flush to physical media. No cheating.
- **Reads**: `iflag=direct` (O_DIRECT) bypasses page cache entirely. Plus `drop_caches` before the first read as belt-and-suspenders.
- **Random offsets**: Varying the offset into the source/target file means we're not hitting the same sectors repeatedly (prevents any on-device cache from being helpful).

## Open questions

- Is `iflag=direct` OK on exfat? (Should be — it's a VFS-level flag, not FS-specific. Will test.)
- Do we want more than 16 rounds? Could make it configurable.
- sudo for `drop_caches` — acceptable?
