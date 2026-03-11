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
# First run builds the Docker image (~3-4 min)
./spotify-yoink.sh rip "https://open.spotify.com/episode/0kiCA30wyU8M2X9sM3JuB2"

# Specify output filename
./spotify-yoink.sh rip "https://open.spotify.com/episode/..." my-episode.mp3

# Specify duration manually (seconds) if auto-detect fails
./spotify-yoink.sh rip "https://open.spotify.com/episode/..." out.mp3 1500
```

## Requirements

- Docker
- ~2GB disk for image

## Output

- 192kbps MP3, stereo, 44.1kHz
- Debug screenshots saved alongside (can delete)
