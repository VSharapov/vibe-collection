# spotify-yoink

No clever tricks brute force downloader. Runs at 1x time in a containerized browser.

## How it works

1. Spins up Docker container with Chrome + PulseAudio
2. Navigates to Spotify embed page (no login needed)
3. Chrome's built-in Widevine CDM handles DRM decryption
4. Audio routes through PulseAudio virtual sink
5. FFmpeg records from sink to MP3

Real-time only — a 3 hour episode takes 3 hours to record.

## Usage

```bash
# Build once
./spotify-yoink.sh build

# Record (auto-detects duration)
./spotify-yoink.sh rip <url> [output.mp3] [duration] [start_at]

# Splice chunks together (auto-detects overlap)
./spotify-yoink.sh splice chunk1.mp3 chunk2.mp3 [...] output.mp3
```

### Examples

```bash
# Basic recording
./spotify-yoink.sh rip "https://open.spotify.com/episode/ID"

# With output filename
./spotify-yoink.sh rip "https://open.spotify.com/episode/ID" episode.mp3

# With manual duration (30 minutes)
./spotify-yoink.sh rip "https://open.spotify.com/episode/ID" episode.mp3 1800

# Resume from 25 minutes, record 30 minutes
./spotify-yoink.sh rip "https://open.spotify.com/episode/ID" resume.mp3 1800 1500
```

## Recording Long Episodes in Chunks

```bash
URL="https://open.spotify.com/episode/YOUR_ID"
export SPOTIFY_YOINK_OUTPUT=$(mktemp -d)
cd $SPOTIFY_YOINK_OUTPUT

# Record 3 overlapping 35-minute chunks
for chunk in 1 2 3; do
  start=$(( (chunk - 1) * 1800 ))  # 0, 1800, 3600 (30 min increments)
  timeout 36m ~/src/vibe-collection/spotify-yoink/spotify-yoink.sh rip \
    "$URL" "chunk${chunk}.mp3" 2100 $start
done

# Splice all chunks
./spotify-yoink.sh splice chunk1.mp3 chunk2.mp3 chunk3.mp3 final.mp3
```

## Handling Unexpected Interruptions

If your recording dies mid-way:

```bash
# Check what you have
ffprobe -v quiet -show_entries format=duration -of csv=p=0 partial.mp3

# Resume from 2-5 minutes BEFORE where it stopped (safe overlap)
# e.g., if partial.mp3 is 45 min, resume from 42 min:
./spotify-yoink.sh rip "$URL" resume.mp3 0 2520

# Splice
./spotify-yoink.sh splice partial.mp3 resume.mp3 fixed.mp3
```

## Tips

### Trim Trailing Silence

```bash
# Find where silence starts
ffmpeg -i final.mp3 -af "silencedetect=noise=-50dB:d=5" -f null /dev/null 2>&1 | \
  grep silence_start | tail -1

# Trim (e.g., if silence starts at 5400s)
ffmpeg -i final.mp3 -t 5400 -c copy final_trimmed.mp3
```

## Requirements

- Docker
- ~2GB disk for image

## Output

- 192kbps MP3, stereo, 44.1kHz
- Debug screenshots saved alongside (can delete)
