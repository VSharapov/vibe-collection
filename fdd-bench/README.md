# fdd-bench — Flash Drive Benchmark

Benchmarks USB flash drives with real (non-cached) sequential read/write speeds over time, so you can observe thermal throttling.

## Quick start

```bash
make
sudo make install

sudo fdd-bench full-bench /media/$USER/your-flash-drive > /tmp/bench.tsv
fdd-bench gnuplot /tmp/bench.tsv
fdd-bench pngplot /tmp/bench.tsv > /tmp/bench.png
```

## Subcommands

Run `fdd-bench` with no args for full usage. Highlights:

- `full-bench MOUNTPOINT` — alternating write/read rounds, TSV on stdout, progress on stderr
- `gnuplot DATAFILE` — ASCII art plot
- `pngplot DATAFILE` — PNG plot to stdout
- All internal functions (`find-big-file`, `timed-write`, `timed-read`, `detect-finished`, etc.) are also callable

## Configuration

All via environment variables:

| Variable                     | Default               | Description                                |
|------------------------------|-----------------------|--------------------------------------------|
| `FDD_BENCH_ROUNDS`           | 8                     | Number of write/read round pairs           |
| `FDD_BENCH_CHUNK_MIB`        | 128                   | Chunk size per round                       |
| `FDD_BENCH_SRC_SIZE_MIB`     | 1024                  | Random source file size                    |
| `FDD_BENCH_STABLE_THRESHOLD` | 0.05                  | Max relative drop to consider "stabilized" |
| `FDD_BENCH_FIND_MAXDEPTH`    | 4                     | Max depth for find-big-file                |
| `FDD_BENCH_PLOT_TITLE`       | Flash Drive Benchmark | Plot title override                        |


## Building

The draft `.sh` files are not checked in — only the patches are.

```bash
make
```

## Development history

| File               | What                                                                   |
|--------------------|------------------------------------------------------------------------|
| `PLAN.md`          | Design doc                                                             |
| `draft1.patch`     | Initial implementation                                                 |
| `draft1.REPORT.md` | Test results + improvement ideas (checkboxed)                          |
| `draft2.patch`     | Env vars, openssl rand, oflag=direct, plateau detection, stdin gnuplot |
| `draft2.REPORT.md` | Test results + improvement ideas (checkboxed)                          |
| `draft3.patch`     | detect-finished, timestamps, EUID-aware sudo, threshold tuning         |
| `draft3.REPORT.md` | Test results (27/27 pass)                                              |
| `draft4.patch`     | sync before drop_caches                                                |
| `draft4.REPORT.md` | One-liner                                                              |


## Dependencies

- `dd`, `bc`, `date`, `awk`, `stat`, `find` (coreutils)
- `openssl` (optional, falls back to `/dev/urandom`)
- `gnuplot` (for plotting subcommands)
- `sudo` (for drop_caches, unless running as root)


## Example: comparing two drives

```bash
$ for fdd in /media/vasiliy/{Ventoy,Metal234GiB}/ ; do noslash=$(echo $fdd | tr -d '/'); time (./fdd-bench.sh full-bench $fdd >/tmp/$noslash.tsv); read; done
[17:38:56] [Ventoy] Read source: isos/windows/Win11_24H2_English_x64_20250106.iso (5549 MiB)
Generating 1024 MiB random data -> /tmp/fdd-bench-VLtdMqcD.bin ...
[17:38:57] [Ventoy] Write source: /tmp/fdd-bench-VLtdMqcD.bin (1024 MiB)
[17:38:57] [Ventoy] Starting 8 rounds of 128 MiB write/read...

[17:39:00] [WRITE  1/8]  offset=  97MiB  128 MiB in 3.07s  →  41.6 MB/s
[17:39:09] [READ   1/8]  offset=3988MiB  128 MiB in 3.89s  →  32.9 MB/s
[17:39:22] [WRITE  2/8]  offset= 763MiB  128 MiB in 12.10s  →  10.5 MB/s
[17:39:30] [READ   2/8]  offset=2502MiB  128 MiB in 3.77s  →  33.9 MB/s
[17:39:40] [WRITE  3/8]  offset=  17MiB  128 MiB in 9.86s  →  12.9 MB/s
[17:39:50] [READ   3/8]  offset=2734MiB  128 MiB in 3.79s  →  33.8 MB/s
[17:40:00] [WRITE  4/8]  offset= 636MiB  128 MiB in 9.91s  →  12.9 MB/s
[17:40:09] [READ   4/8]  offset=2300MiB  128 MiB in 3.71s  →  34.4 MB/s
[17:40:21] [WRITE  5/8]  offset= 669MiB  128 MiB in 11.83s  →  10.8 MB/s
[17:40:29] [READ   5/8]  offset=3858MiB  128 MiB in 3.05s  →  42.0 MB/s
[17:40:34] [WRITE  6/8]  offset= 429MiB  128 MiB in 5.12s  →  24.9 MB/s
[17:40:44] [READ   6/8]  offset= 804MiB  128 MiB in 3.87s  →  33.1 MB/s
[17:40:54] [WRITE  7/8]  offset= 588MiB  128 MiB in 10.07s  →  12.7 MB/s
[17:41:02] [READ   7/8]  offset=5036MiB  128 MiB in 3.32s  →  38.5 MB/s
[17:41:10] [WRITE  8/8]  offset= 694MiB  128 MiB in 7.76s  →  16.4 MB/s
[17:41:19] [READ   8/8]  offset=  62MiB  128 MiB in 2.89s  →  44.3 MB/s

[17:41:19] --- Ventoy Summary ---
Write: avg=17.8 min=10.5 max=41.6 MB/s
Read:  avg=36.6 min=32.9 max=44.3 MB/s
Write: still declining: 19.5 -> 16.2 MB/s (16.8% drop)
Read:  stabilized at 39.5 MB/s (recovered from 33.8 MB/s)
Cleaned /media/vasiliy/Ventoy/fdd-bench-output.bin

real    2m22.645s
user    0m0.652s
sys     0m3.572s

[17:53:43] [Metal234GiB] Read source: isos/ubuntu-22.04.5-desktop-amd64.iso (4542 MiB)
Generating 1024 MiB random data -> /tmp/fdd-bench-uF4LaLfQ.bin ...
[17:53:44] [Metal234GiB] Write source: /tmp/fdd-bench-uF4LaLfQ.bin (1024 MiB)
[17:53:44] [Metal234GiB] Starting 8 rounds of 128 MiB write/read...

[17:53:49] [WRITE  1/8]  offset= 416MiB  128 MiB in 4.82s  →  26.5 MB/s
[17:53:55] [READ   1/8]  offset= 504MiB  128 MiB in 0.90s  →  142.6 MB/s
[17:54:00] [WRITE  2/8]  offset= 227MiB  128 MiB in 4.62s  →  27.7 MB/s
[17:54:06] [READ   2/8]  offset=3425MiB  128 MiB in 0.92s  →  139.2 MB/s
[17:54:11] [WRITE  3/8]  offset= 104MiB  128 MiB in 4.58s  →  27.9 MB/s
[17:54:18] [READ   3/8]  offset=4280MiB  128 MiB in 0.91s  →  140.1 MB/s
[17:54:23] [WRITE  4/8]  offset= 519MiB  128 MiB in 5.11s  →  25.0 MB/s
[17:54:29] [READ   4/8]  offset=1730MiB  128 MiB in 0.91s  →  140.6 MB/s
[17:54:35] [WRITE  5/8]  offset= 539MiB  128 MiB in 5.52s  →  23.2 MB/s
[17:54:45] [READ   5/8]  offset=1595MiB  128 MiB in 0.93s  →  137.0 MB/s
[17:54:51] [WRITE  6/8]  offset= 104MiB  128 MiB in 6.10s  →  20.9 MB/s
[17:55:04] [READ   6/8]  offset=2993MiB  128 MiB in 0.88s  →  145.1 MB/s
[17:55:09] [WRITE  7/8]  offset= 270MiB  128 MiB in 5.21s  →  24.5 MB/s
[17:55:22] [READ   7/8]  offset=1269MiB  128 MiB in 0.90s  →  142.1 MB/s
[17:55:26] [WRITE  8/8]  offset= 658MiB  128 MiB in 4.59s  →  27.9 MB/s
[17:55:39] [READ   8/8]  offset=2885MiB  128 MiB in 0.90s  →  142.8 MB/s

[17:55:39] --- Metal234GiB Summary ---
Write: avg=25.4 min=20.9 max=27.9 MB/s
Read:  avg=141.2 min=137.0 max=145.1 MB/s
Write: still declining: 26.8 -> 24.1 MB/s (9.9% drop)
Read:  stabilized at 141.8 MB/s (recovered from 140.6 MB/s)
Cleaned /media/vasiliy/Metal234GiB//fdd-bench-output.bin


real    2m20.257s
user    0m0.698s
sys     0m3.439s

$ ./fdd-bench.sh gnuplot /tmp/mediavasiliyMetal234GiB.tsv 

                                                                                                                        
                                                                                                                        
                                                    Flash Drive Benchmark                                               
     160 +----------------------------------------------------------------------------------------------------------+   
         |              +               +              +              +              +               +              |   
         |                                                                        ###B#######    Write MB/s ***A*** |   
     140 |##############B###############B##############B#######           ########           ########B#########B####|   
         |                                                     #######B###                                          |   
         |                                                                                                          |   
         |                                                                                                          |   
     120 |-+                                                                                                      +-|   
         |                                                                                                          |   
         |                                                                                                          |   
     100 |-+                                                                                                      +-|   
         |                                                                                                          |   
         |                                                                                                          |   
      80 |-+                                                                                                      +-|   
         |                                                                                                          |   
         |                                                                                                          |   
      60 |-+                                                                                                      +-|   
         |                                                                                                          |   
         |                                                                                                          |   
         |                                                                                                          |   
      40 |-+                                                                                                      +-|   
         |                                                                                                          |   
         |**************A***************A**************A**************A*******       +       ********A**************|   
      20 +----------------------------------------------------------------------------------------------------------+   
         1              2               3              4              5              6               7              8   
                                                            Round                                                       
                                                                                                                        

```

Enjoy
