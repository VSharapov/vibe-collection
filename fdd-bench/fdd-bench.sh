#!/usr/bin/env bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (all overridable via env vars)
# ---------------------------------------------------------------------------

FDD_BENCH_CHUNK_MIB="${FDD_BENCH_CHUNK_MIB:-128}"
FDD_BENCH_SRC_SIZE_MIB="${FDD_BENCH_SRC_SIZE_MIB:-1024}"
FDD_BENCH_ROUNDS="${FDD_BENCH_ROUNDS:-8}"
FDD_BENCH_FIND_MAXDEPTH="${FDD_BENCH_FIND_MAXDEPTH:-4}"
FDD_BENCH_STABLE_THRESHOLD="${FDD_BENCH_STABLE_THRESHOLD:-0.05}"

# ---------------------------------------------------------------------------
# Plumbing
# ---------------------------------------------------------------------------

find-big-file() {
  local mountpoint="$1"
  find "$mountpoint" -maxdepth "$FDD_BENCH_FIND_MAXDEPTH" -type f -printf '%s %P\n' 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f2-
}

file-size-mib() {
  local file="$1"
  local bytes
  bytes=$(stat -c%s "$file")
  echo $(( bytes / 1048576 ))
}

random-offset() {
  local file_size_mib="$1"
  local chunk_mib="$2"
  local max_offset=$(( file_size_mib - chunk_mib ))
  if (( max_offset <= 0 )); then
    echo 0
    return
  fi
  echo $(( RANDOM % (max_offset + 1) ))
}

init() {
  local size_mib="${1:-$FDD_BENCH_SRC_SIZE_MIB}"
  local size_bytes=$(( size_mib * 1048576 ))
  local tmpfile
  tmpfile=$(mktemp /tmp/fdd-bench-XXXXXXXX.bin)
  >&2 echo "Generating ${size_mib} MiB random data -> $tmpfile ..."
  if command -v openssl &>/dev/null; then
    openssl rand -out "$tmpfile" "$size_bytes"
  else
    dd if=/dev/urandom of="$tmpfile" bs=1M count="$size_mib" status=none
  fi
  echo "$tmpfile"
}

drop-caches() {
  sync
  if [[ $EUID -eq 0 ]]; then
    echo 3 > /proc/sys/vm/drop_caches
  else
    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
  fi
}

ensure-sudo() {
  if [[ $EUID -eq 0 ]]; then
    return
  fi
  if ! sudo -n true 2>/dev/null; then
    >&2 echo "Need sudo for drop-caches. Authenticating now..."
    sudo true
  fi
}

timed-write() {
  local src_file="$1"
  local offset_mib="$2"
  local dest_file="$3"
  local chunk_mib="$4"
  local round="$5"

  local start end elapsed mbps
  start=$(date +%s.%N)
  dd if="$src_file" of="$dest_file" \
    bs=1M count="$chunk_mib" skip="$offset_mib" \
    oflag=direct conv=fsync status=none
  end=$(date +%s.%N)

  elapsed=$(echo "$end - $start" | bc)
  mbps=$(echo "scale=1; $chunk_mib / $elapsed" | bc)

  printf "write\t%d\t%d\t%.2f\t%s\n" "$round" "$offset_mib" "$elapsed" "$mbps"
}

timed-read() {
  local src_file="$1"
  local offset_mib="$2"
  local chunk_mib="$3"
  local round="$4"

  drop-caches

  local start end elapsed mbps
  start=$(date +%s.%N)
  dd if="$src_file" of=/dev/null \
    bs=1M count="$chunk_mib" skip="$offset_mib" \
    iflag=direct status=none
  end=$(date +%s.%N)

  elapsed=$(echo "$end - $start" | bc)
  mbps=$(echo "scale=1; $chunk_mib / $elapsed" | bc)

  printf "read\t%d\t%d\t%.2f\t%s\n" "$round" "$offset_mib" "$elapsed" "$mbps"
}

clean() {
  local mountpoint="$1"
  rm -f "$mountpoint/fdd-bench-output.bin"
  >&2 echo "Cleaned $mountpoint/fdd-bench-output.bin"
}

# ---------------------------------------------------------------------------
# Porcelain
# ---------------------------------------------------------------------------

usage() {
  >&2 cat <<'EOF'
Usage: fdd-bench.sh <subcommand> [args...]

Main:
  full-bench MOUNTPOINT            Run alternating read/write benchmark
  gnuplot DATAFILE                 Render ASCII plot from benchmark TSV
  pngplot DATAFILE                 Render PNG plot from benchmark TSV to stdout

Building blocks:
  find-big-file MOUNTPOINT         Find largest file on drive (prints relative path)
  file-size-mib FILE               Print file size in MiB
  random-offset SIZE_MIB CHUNK_MIB Print random 1MiB-aligned offset
  init [SIZE_MIB]                  Generate random source file (prints path)
  drop-caches                      Drop page cache (needs sudo)
  ensure-sudo                      Pre-authenticate sudo
  detect-finished                  Read speeds from stdin, detect if stabilized
  timed-write SRC OFF DEST CHUNK ROUND   One write round (prints TSV line)
  timed-read  SRC OFF CHUNK ROUND        One read round (prints TSV line)
  clean MOUNTPOINT                 Remove benchmark artifacts

Environment variables:
  FDD_BENCH_ROUNDS=8               Number of write/read round pairs
  FDD_BENCH_CHUNK_MIB=128          Chunk size per round in MiB
  FDD_BENCH_SRC_SIZE_MIB=1024      Random source file size in MiB
  FDD_BENCH_FIND_MAXDEPTH=4        Max directory depth for find-big-file
  FDD_BENCH_STABLE_THRESHOLD=0.05  Max relative drop to consider stable (5%)
  FDD_BENCH_PLOT_TITLE=...         Override plot title

Example:
  $ ./fdd-bench.sh find-big-file /media/vasiliy/Ventoy
  isos/linux/ubuntu-22.04.5-desktop-amd64.iso
  $ time (./fdd-bench.sh full-bench /media/vasiliy/Ventoy > /tmp/bench1.tsv)
  $ ./fdd-bench.sh gnuplot /tmp/bench1.tsv
  $ ./fdd-bench.sh pngplot /tmp/bench1.tsv > /tmp/bench1.png
EOF
}

detect-finished() {
  # Reads a list of speed values from stdin (one per line).
  # Compares the average of the first half to the second half.
  # "Finished" (stabilized) means:
  #   - Second half avg >= first half avg (recovered/improving), OR
  #   - Second half avg dropped by less than FDD_BENCH_STABLE_THRESHOLD (default 0.5%)
  # "Not finished" means speeds are still declining significantly.
  local threshold="$FDD_BENCH_STABLE_THRESHOLD"
  awk -v thresh="$threshold" '
    { vals[NR] = $1; n = NR }
    END {
      if (n < 4) { printf "too few data points\n"; exit }
      mid = int(n / 2)
      sum1 = 0; sum2 = 0
      for (i = 1; i <= mid; i++) sum1 += vals[i]
      for (i = mid + 1; i <= n; i++) sum2 += vals[i]
      avg1 = sum1 / mid
      avg2 = sum2 / (n - mid)
      if (avg1 == 0) { printf "stabilized at %.1f MB/s\n", avg2; exit }
      drop = (avg1 - avg2) / avg1
      if (drop <= 0) {
        printf "stabilized at %.1f MB/s (recovered from %.1f MB/s)\n", avg2, avg1
      } else if (drop <= thresh) {
        printf "stabilized at %.1f MB/s\n", avg2
      } else {
        printf "still declining: %.1f -> %.1f MB/s (%.1f%% drop)\n", avg1, avg2, drop * 100
      }
    }
  '
}

_ts() {
  # Timestamp prefix for stderr log lines
  date +%H:%M:%S
}

full-bench() {
  local mountpoint="$1"
  local rounds="$FDD_BENCH_ROUNDS"
  local chunk="$FDD_BENCH_CHUNK_MIB"
  local src_size="$FDD_BENCH_SRC_SIZE_MIB"
  local label
  label=$(basename "$mountpoint")

  # Pre-auth sudo so it doesn't prompt mid-benchmark
  ensure-sudo

  # Find big file for reads
  local bigfile_rel
  bigfile_rel=$(find-big-file "$mountpoint")
  local bigfile_path="$mountpoint/$bigfile_rel"
  local bigfile_size_mib
  bigfile_size_mib=$(file-size-mib "$bigfile_path")
  >&2 printf "[%s] [%s] Read source: %s (%d MiB)\n" "$(_ts)" "$label" "$bigfile_rel" "$bigfile_size_mib"

  # Sanity check
  if (( bigfile_size_mib < chunk )); then
    >&2 printf "[%s] ERROR: Big file (%d MiB) < chunk size (%d MiB)\n" "$(_ts)" "$bigfile_size_mib" "$chunk"
    exit 1
  fi

  # Generate random source for writes
  local src_file
  src_file=$(init "$src_size")
  trap "rm -f '$src_file'" EXIT
  >&2 printf "[%s] [%s] Write source: %s (%d MiB)\n" "$(_ts)" "$label" "$src_file" "$src_size"
  >&2 printf "[%s] [%s] Starting %d rounds of %d MiB write/read...\n" "$(_ts)" "$label" "$rounds" "$chunk"
  >&2 echo ""

  local dest_file="$mountpoint/fdd-bench-output.bin"

  # TSV header
  printf "type\tround\toffset_mib\tseconds\tmbps\n"

  local write_speeds=()
  local read_speeds=()

  for (( i = 1; i <= rounds; i++ )); do
    # --- Write round ---
    local w_offset w_line w_secs w_mbps
    w_offset=$(random-offset "$src_size" "$chunk")
    w_line=$(timed-write "$src_file" "$w_offset" "$dest_file" "$chunk" "$i")
    echo "$w_line"
    w_secs=$(echo "$w_line" | cut -f4)
    w_mbps=$(echo "$w_line" | cut -f5)
    write_speeds+=("$w_mbps")
    >&2 printf "[%s] [WRITE %2d/%d]  offset=%4dMiB  %d MiB in %ss  →  %s MB/s\n" \
      "$(_ts)" "$i" "$rounds" "$w_offset" "$chunk" "$w_secs" "$w_mbps"

    # --- Read round ---
    local r_offset r_line r_secs r_mbps
    r_offset=$(random-offset "$bigfile_size_mib" "$chunk")
    r_line=$(timed-read "$bigfile_path" "$r_offset" "$chunk" "$i")
    echo "$r_line"
    r_secs=$(echo "$r_line" | cut -f4)
    r_mbps=$(echo "$r_line" | cut -f5)
    read_speeds+=("$r_mbps")
    >&2 printf "[%s] [READ  %2d/%d]  offset=%4dMiB  %d MiB in %ss  →  %s MB/s\n" \
      "$(_ts)" "$i" "$rounds" "$r_offset" "$chunk" "$r_secs" "$r_mbps"
  done

  # Summary
  >&2 echo ""
  >&2 printf "[%s] --- %s Summary ---\n" "$(_ts)" "$label"
  >&2 printf "Write: %s\n" "$(printf '%s\n' "${write_speeds[@]}" | awk '
    { s+=$1; if(NR==1||$1<min)min=$1; if($1>max)max=$1; n++ }
    END { printf "avg=%.1f min=%.1f max=%.1f MB/s", s/n, min, max }
  ')"
  >&2 printf "Read:  %s\n" "$(printf '%s\n' "${read_speeds[@]}" | awk '
    { s+=$1; if(NR==1||$1<min)min=$1; if($1>max)max=$1; n++ }
    END { printf "avg=%.1f min=%.1f max=%.1f MB/s", s/n, min, max }
  ')"
  >&2 printf "Write: %s\n" "$(printf '%s\n' "${write_speeds[@]}" | detect-finished)"
  >&2 printf "Read:  %s\n" "$(printf '%s\n' "${read_speeds[@]}" | detect-finished)"

  # Cleanup
  rm -f "$src_file"
  trap - EXIT
  clean "$mountpoint"
}

gnuplot() {
  local datafile="${1:-/dev/stdin}"
  local data
  data=$(cat "$datafile")

  local write_data read_data
  write_data=$(echo "$data" | awk -F'\t' '$1 == "write" { print $2, $5 }')
  read_data=$(echo "$data" | awk -F'\t' '$1 == "read" { print $2, $5 }')

  local title
  title="${FDD_BENCH_PLOT_TITLE:-Flash Drive Benchmark}"

  command gnuplot <<GNUPLOT
set terminal dumb size 120 30
set title "$title"
set xlabel "Round"
set ylabel "MB/s"
set key top right
\$data_write << EOD
${write_data}
EOD
\$data_read << EOD
${read_data}
EOD
plot \$data_write using 1:2 with linespoints title "Write MB/s", \\
     \$data_read using 1:2 with linespoints title "Read MB/s"
GNUPLOT
}

pngplot() {
  local datafile="${1:-/dev/stdin}"
  local data
  data=$(cat "$datafile")

  local write_data read_data
  write_data=$(echo "$data" | awk -F'\t' '$1 == "write" { print $2, $5 }')
  read_data=$(echo "$data" | awk -F'\t' '$1 == "read" { print $2, $5 }')

  local title
  title="${FDD_BENCH_PLOT_TITLE:-Flash Drive Benchmark}"

  command gnuplot <<GNUPLOT
set terminal pngcairo size 1200,600 enhanced font "sans,12"
set output "/dev/stdout"
set title "$title"
set xlabel "Round"
set ylabel "MB/s"
set key top right
set grid
\$data_write << EOD
${write_data}
EOD
\$data_read << EOD
${read_data}
EOD
plot \$data_write using 1:2 with linespoints linewidth 2 pointtype 7 title "Write MB/s", \\
     \$data_read using 1:2 with linespoints linewidth 2 pointtype 7 title "Read MB/s"
GNUPLOT
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

"$@"
