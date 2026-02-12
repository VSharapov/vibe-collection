# gcp-tts.sh

Google Cloud Text-to-Speech CLI with automatic short/long pipeline selection.

## Quick Start

```bash
# Setup (developer machine, needs gcloud)
./gcp-tts.sh infra setup > config.json

# Synthesize (portable: curl, openssl, jq, ffmpeg)
cat text.txt | ./gcp-tts.sh tts synthesize config.json > audio.m4a

# Teardown
./gcp-tts.sh infra teardown config.json
```

## Limits

| Pipeline | Max Input | API |
|----------|-----------|-----|
| `short` | 5,000 bytes | `text:synthesize` (sync, returns MP3) |
| `long` | 1,000,000 bytes | `synthesizeLongAudio` (async, returns WAV) |

The `tts synthesize` command auto-selects based on input size.

## Magic

```bash
# Which pipeline would be used?
cat essay.txt | ./gcp-tts.sh tts which-pipeline
# Output: "short" or "long"
```

## Files

| File | Description |
|------|-------------|
| `gcp-tts.sh` | The script |
| `config.json` | Credentials + bucket (DO NOT COMMIT) |
| `PLAN.md` | Detailed architecture |
| `NOTES.md` | Development notes |
