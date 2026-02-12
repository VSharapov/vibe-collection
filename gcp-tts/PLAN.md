# Plan: gcp-tts.sh

## Overview

| Phase | Environment | Tools Required |
|-------|-------------|----------------|
| **1. Infra Setup** | Developer machine | gcloud, jq |
| **2. Runtime** | Lambda / VM / Container | curl, openssl, jq, ffmpeg |
| **3. Infra Teardown** | Developer machine | gcloud |

---

## Config File

Single file deployed to runtime: `config.json`

```json
{
  "bucket": "gs://my-tts-project-1234567890-tts-output",
  "serviceaccount": {
    "type": "service_account",
    "project_id": "my-tts-project-1234567890",
    "private_key_id": "...",
    "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
    "client_email": "tts-long-audio@my-tts-project-1234567890.iam.gserviceaccount.com",
    "...": "..."
  }
}
```

**Derived values** (no separate env vars needed):
- `project_id` → `.serviceaccount.project_id`
- `client_email` → `.serviceaccount.client_email`
- `private_key` → `.serviceaccount.private_key`

---

## User Story

### Phase 1: Infrastructure Setup (Developer Machine)

```bash
# Check prerequisites
$ ./gcp-tts.sh infra check
# Verifies: gcloud auth, billing, permissions

# Decide on a project ID (or let it generate one)
$ export GCP_TTS_PROJECT_ID="my-tts-$(date +%s)"

# Run full infrastructure setup - outputs config.json to stdout
$ ./gcp-tts.sh infra setup > config.json
# Creates:
#   - GCP project (if GCP_TTS_PROJECT_ID set, otherwise generates)
#   - Enables texttospeech.googleapis.com
#   - Creates GCS bucket
#   - Creates service account with bucket write access
#   - Generates SA key
#
# Outputs config.json to stdout containing:
#   { "bucket": "gs://...", "serviceaccount": { ... } }

# Verify everything works
$ ./gcp-tts.sh infra verify config.json

# Quick test
$ echo "Hello world" | ./gcp-tts.sh tts synthesize config.json > test.m4a
```

### Phase 2: Runtime (Lambda / VM / Container)

Only needs:
- `config.json` (deployed via secrets manager, mounted volume, etc.)
- Tools: `curl`, `openssl`, `jq`, `ffmpeg`

```bash
# Auto-select short or long pipeline based on input size
$ cat essay.txt | ./gcp-tts.sh tts synthesize config.json > essay.m4a

# Or be explicit
$ cat short.txt | ./gcp-tts.sh tts short config.json > short.m4a
$ cat long.txt | ./gcp-tts.sh tts long config.json > long.m4a

# The magic: which-pipeline outputs "short" or "long"
$ PIPELINE=$(cat essay.txt | ./gcp-tts.sh tts which-pipeline)
$ cat essay.txt | ./gcp-tts.sh tts $PIPELINE config.json > essay.m4a
```

### Phase 3: Teardown (Developer Machine)

```bash
$ ./gcp-tts.sh infra teardown config.json
# Deletes: SA, bucket, API, project

$ rm config.json
```

---

## Limits

| API | Max Input | Pipeline |
|-----|-----------|----------|
| `text:synthesize` | 5,000 bytes | `short` |
| `synthesizeLongAudio` | 1,000,000 bytes | `long` |

```bash
# Plumbing: check if input exceeds short limit
$ cat text.txt | ./gcp-tts.sh tts exceeds-short-limit && echo "too long"

# Plumbing: which pipeline to use
$ cat text.txt | ./gcp-tts.sh tts which-pipeline
# Outputs: "short" or "long"
```

---

## Command Structure

```
./gcp-tts.sh <group> <command> [config.json]

GROUPS:

  infra (requires gcloud)
    check                 - verify gcloud, permissions, billing
    setup                 - full setup, outputs config.json to stdout
    verify <config>       - test that setup works
    teardown <config>     - full teardown

  tts (portable: curl, openssl, jq, ffmpeg)
    synthesize <config>   - auto-select short/long, stdin text → stdout audio
    short <config>        - force short pipeline (≤5000 bytes)
    long <config>         - force long pipeline (≤1MB)
    which-pipeline        - output "short" or "long" based on stdin size

  tts plumbing:
    exceeds-short-limit   - exit 0 if stdin > 5000 bytes, exit 1 otherwise
    format-for-tts        - escape for SSML, add <break time="1s"/> for newlines
    # short pipeline:
    short-request         - create JSON for text:synthesize
    short-submit <config> - POST, get base64 audio
    short-extract         - decode base64 to raw audio
    # long pipeline:
    long-request <config> - create JSON for synthesizeLongAudio
    long-submit <config>  - POST, get operation ID
    long-await <config>   - poll until done
    long-download <config>- fetch WAV from GCS
    long-cleanup <config> - delete WAV from GCS
    # shared:
    convert               - WAV/MP3 stdin → m4a/opus/mp3 stdout
```

---

## Data Flow

```
                    ┌─────────────────┐
                    │   stdin (text)  │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  which-pipeline │ ─── outputs "short" or "long"
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                              ▼
     ┌─────────────────┐            ┌─────────────────┐
     │  SHORT (≤5KB)   │            │  LONG (≤1MB)    │
     └────────┬────────┘            └────────┬────────┘
              │                              │
              ▼                              ▼
     ┌─────────────────┐            ┌─────────────────┐
     │  format-for-tts │            │  format-for-tts │
     │  (SSML escaping │            │  (SSML + breaks)│
     │   + 1s breaks)  │            └────────┬────────┘
     └────────┬────────┘                     │
              │                              ▼
              ▼                     ┌─────────────────┐
     ┌─────────────────┐            │  long-request   │
     │  short-request  │            │  (JSON + GCS    │
     │  (JSON)         │            │   output URI)   │
     └────────┬────────┘            └────────┬────────┘
              │                              │
              ▼                              ▼
     ┌─────────────────┐            ┌─────────────────┐
     │  short-submit   │            │  long-submit    │
     │  (API call)     │            │  (start job)    │
     └────────┬────────┘            └────────┬────────┘
              │                              │
              ▼                              ▼
     ┌─────────────────┐            ┌─────────────────┐
     │  short-extract  │            │  long-await     │
     │  (base64 decode)│            │  (poll status)  │
     └────────┬────────┘            └────────┬────────┘
              │                              │
              │                              ▼
              │                     ┌─────────────────┐
              │                     │  long-download  │
              │                     │  (fetch from    │
              │                     │   GCS bucket)   │
              │                     └────────┬────────┘
              │                              │
              └──────────────┬───────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │     convert     │
                    │  (ffmpeg: WAV/  │
                    │   MP3 → m4a)    │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  stdout (audio) │
                    └─────────────────┘
```

---

## GCS Object Naming

Default object name for long pipeline: timestamp with nanoseconds

```bash
# Generated automatically if not set
TTS_OBJECT_NAME="${TTS_OBJECT_NAME:-$(date +%Y%m%d-%H%M%S-%N)}"
# Example: 20260125-143052-123456789
```

---

## SSML Formatting

`format-for-tts` does:
1. Escape single quotes: `'` → `'` (unicode apostrophe)
2. Escape double quotes: `"` → `&quot;`
3. Convert newlines to SSML breaks: `\n` → `<break time="1s"/>`

Example:
```
Input:  Hello world.\nThis is line two.
Output: Hello world.<break time="1s"/>This is line two.
```

---

## Notes

- Short pipeline returns MP3 directly (base64 in response)
- Long pipeline returns WAV (must convert)
- Both pipelines go through `convert` step for consistent output format
- `config.json` is ~2.5KB - deploy as file, not base64 env var
