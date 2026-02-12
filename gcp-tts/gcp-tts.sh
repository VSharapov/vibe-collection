#!/usr/bin/env bash
# GCP Text-to-Speech CLI
# Portable runtime: curl, openssl, jq, ffmpeg
# Infrastructure setup/teardown: gcloud

set -euo pipefail

# --- Constants ---
SHORT_LIMIT=5000  # bytes, per Google docs
LONG_LIMIT=1000000  # 1MB

# --- Config Helpers ---

config-get() {
  local config_file="$1"
  local path="$2"
  jq -r "$path" "$config_file"
}

config-project-id() {
  config-get "$1" '.serviceaccount.project_id'
}

config-bucket() {
  config-get "$1" '.bucket'
}

config-client-email() {
  config-get "$1" '.serviceaccount.client_email'
}

config-private-key() {
  config-get "$1" '.serviceaccount.private_key'
}

# --- Auth ---

get-access-token() {
  local config_file="$1"
  local client_email=$(config-client-email "$config_file")
  local private_key=$(config-private-key "$config_file")
  local now=$(date +%s)
  local exp=$((now + 3600))

  local header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e | tr -d '=\n' | tr '/+' '_-')
  local claims=$(echo -n "{\"iss\":\"${client_email}\",\"scope\":\"https://www.googleapis.com/auth/cloud-platform\",\"aud\":\"https://oauth2.googleapis.com/token\",\"iat\":${now},\"exp\":${exp}}" | openssl base64 -e | tr -d '=\n' | tr '/+' '_-')
  local signature=$(echo -n "${header}.${claims}" | openssl dgst -sha256 -sign <(echo "$private_key") | openssl base64 -e | tr -d '=\n' | tr '/+' '_-')
  local jwt="${header}.${claims}.${signature}"

  curl -s -X POST https://oauth2.googleapis.com/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}" | \
    jq -r '.access_token'
}

# --- TTS Commands (portable) ---

tts() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    synthesize) tts-synthesize "$@" ;;
    short) tts-short "$@" ;;
    long) tts-long "$@" ;;
    which-pipeline) tts-which-pipeline ;;
    exceeds-short-limit) tts-exceeds-short-limit ;;
    format-for-tts) tts-format-for-tts ;;
    short-request) tts-short-request ;;
    short-submit) tts-short-submit "$@" ;;
    short-extract) tts-short-extract ;;
    long-request) tts-long-request "$@" ;;
    long-submit) tts-long-submit "$@" ;;
    long-await) tts-long-await "$@" ;;
    long-download) tts-long-download "$@" ;;
    long-cleanup) tts-long-cleanup "$@" ;;
    convert) tts-convert ;;
    *) usage; exit 1 ;;
  esac
}

tts-exceeds-short-limit() {
  local input=$(cat)
  local size=${#input}
  if [[ $size -gt $SHORT_LIMIT ]]; then
    exit 0  # yes, exceeds
  else
    exit 1  # no, fits
  fi
}

tts-which-pipeline() {
  local input=$(cat)
  local size=${#input}
  if [[ $size -gt $SHORT_LIMIT ]]; then
    echo "long"
  else
    echo "short"
  fi
}

tts-format-for-tts() {
  # Escape quotes, convert newlines to SSML 1s breaks
  cat | sed "s/'/'/g" | sed 's/"/\&quot;/g' | sed -z 's/\n/<break time="1s"\/>/g'
}

tts-synthesize() {
  local config_file="${1:-config.json}"
  local input=$(cat)
  local size=${#input}

  if [[ $size -gt $SHORT_LIMIT ]]; then
    echo "$input" | tts-long "$config_file"
  else
    echo "$input" | tts-short "$config_file"
  fi
}

# --- Short Pipeline (≤5000 bytes, sync, returns MP3) ---

tts-short() {
  local config_file="${1:-config.json}"
  tts-format-for-tts | tts-short-request | tts-short-submit "$config_file" | tts-short-extract | tts-convert
}

tts-short-request() {
  local text=$(cat)
  local voice="${TTS_VOICE:-en-US-Studio-O}"
  jq -n \
    --arg text "<speak>$text</speak>" \
    --arg voice "$voice" \
    '{
      "input": {"ssml": $text},
      "voice": {"languageCode": "en-US", "name": $voice},
      "audioConfig": {"audioEncoding": "MP3"}
    }'
}

tts-short-submit() {
  local config_file="$1"
  local request=$(cat)
  local token=$(get-access-token "$config_file")
  local project_id=$(config-project-id "$config_file")

  >&2 echo "Submitting short TTS request..."
  local response=$(echo "$request" | curl -s -X POST \
    "https://texttospeech.googleapis.com/v1/text:synthesize" \
    -H "Authorization: Bearer $token" \
    -H "x-goog-user-project: $project_id" \
    -H "Content-Type: application/json" \
    -d @-)

  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    >&2 echo "Error: $(echo "$response" | jq -r '.error.message')"
    exit 1
  fi

  echo "$response"
}

tts-short-extract() {
  jq -r '.audioContent' | base64 -d
}

# --- Long Pipeline (≤1MB, async, returns WAV) ---

tts-long() {
  local config_file="${1:-config.json}"
  export TTS_OBJECT_NAME="${TTS_OBJECT_NAME:-$(date +%Y%m%d-%H%M%S-%N)}"

  # Run synthesis and wait (discard operation ID output)
  tts-format-for-tts | tts-long-request "$config_file" | tts-long-submit "$config_file" | tts-long-await "$config_file" >/dev/null
  # Download and convert
  tts-long-download "$config_file" | tts-convert
  # Cleanup GCS
  tts-long-cleanup "$config_file" >/dev/null 2>&1 || true
}

tts-long-request() {
  local config_file="$1"
  local text=$(cat)
  local voice="${TTS_VOICE:-en-US-Studio-O}"
  local bucket=$(config-bucket "$config_file")
  local object_name="${TTS_OBJECT_NAME:-$(date +%Y%m%d-%H%M%S-%N)}"
  local gcs_uri="${bucket}/${object_name}.wav"

  jq -n \
    --arg text "<speak>$text</speak>" \
    --arg voice "$voice" \
    --arg gcs_uri "$gcs_uri" \
    '{
      "input": {"ssml": $text},
      "voice": {"languageCode": "en-US", "name": $voice},
      "audioConfig": {"audioEncoding": "LINEAR16"},
      "outputGcsUri": $gcs_uri
    }'
}

tts-long-submit() {
  local config_file="$1"
  local request=$(cat)
  local token=$(get-access-token "$config_file")
  local project_id=$(config-project-id "$config_file")

  >&2 echo "Submitting long TTS request..."
  local response=$(echo "$request" | curl -s -X POST \
    "https://texttospeech.googleapis.com/v1/projects/${project_id}/locations/global:synthesizeLongAudio" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d @-)

  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    >&2 echo "Error: $(echo "$response" | jq -r '.error.message')"
    exit 1
  fi

  local op_name=$(echo "$response" | jq -r '.name')
  if [[ -z "$op_name" || "$op_name" == "null" ]]; then
    >&2 echo "Error: No operation name in response"
    exit 1
  fi

  echo "$op_name"
}

tts-long-await() {
  local config_file="$1"
  local operation_name=$(cat)

  if [[ -z "$operation_name" ]]; then
    >&2 echo "Error: No operation name"
    exit 1
  fi

  local token=$(get-access-token "$config_file")

  >&2 echo "Waiting for: $operation_name"
  while true; do
    local response=$(curl -s \
      "https://texttospeech.googleapis.com/v1/${operation_name}" \
      -H "Authorization: Bearer $token")

    local done=$(echo "$response" | jq -r '.done // false')
    local progress=$(echo "$response" | jq -r '.metadata.progressPercentage // 0')

    >&2 echo "  Progress: ${progress}%"

    if [[ "$done" == "true" ]]; then
      if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        >&2 echo "Error: $(echo "$response" | jq -r '.error.message')"
        exit 1
      fi
      break
    fi
    sleep 5
  done

  echo "$operation_name"
}

tts-long-download() {
  local config_file="$1"
  local token=$(get-access-token "$config_file")
  local bucket=$(config-bucket "$config_file")
  local object_name="${TTS_OBJECT_NAME}"
  local gcs_uri="${bucket}/${object_name}.wav"
  local gcs_path="${gcs_uri#gs://}"
  local bucket_name="${gcs_path%%/*}"
  local object="${gcs_path#*/}"

  >&2 echo "Downloading: $gcs_uri"
  curl -s \
    "https://storage.googleapis.com/storage/v1/b/${bucket_name}/o/$(echo "$object" | jq -Rr @uri)?alt=media" \
    -H "Authorization: Bearer $token"
}

tts-long-cleanup() {
  local config_file="$1"
  local token=$(get-access-token "$config_file")
  local bucket=$(config-bucket "$config_file")
  local object_name="${TTS_OBJECT_NAME}"
  local gcs_uri="${bucket}/${object_name}.wav"
  local gcs_path="${gcs_uri#gs://}"
  local bucket_name="${gcs_path%%/*}"
  local object="${gcs_path#*/}"

  >&2 echo "Cleaning up: $gcs_uri"
  curl -s -X DELETE \
    "https://storage.googleapis.com/storage/v1/b/${bucket_name}/o/$(echo "$object" | jq -Rr @uri)" \
    -H "Authorization: Bearer $token"
}

tts-convert() {
  local format="${TTS_OUTPUT_FORMAT:-m4a}"
  local tmp_in=$(mktemp)
  local tmp_out=$(mktemp)
  trap "rm -f '$tmp_in' '$tmp_out'" EXIT

  cat > "$tmp_in"

  >&2 echo "Converting to ${format}..."
  case "$format" in
    m4a)  ffmpeg -i "$tmp_in" -c:a aac -b:a 128k -f ipod "$tmp_out" -y -loglevel error ;;
    opus) ffmpeg -i "$tmp_in" -c:a libopus -b:a 64k "$tmp_out" -y -loglevel error ;;
    mp3)  ffmpeg -i "$tmp_in" -c:a libmp3lame -b:a 128k "$tmp_out" -y -loglevel error ;;
    wav)  cat "$tmp_in" > "$tmp_out" ;;
    *)    >&2 echo "Unknown format: $format"; exit 1 ;;
  esac

  cat "$tmp_out"
}

# --- Infra Commands (requires gcloud) ---

infra() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    check) infra-check ;;
    setup) infra-setup "$@" ;;
    setup-project) infra-setup-project "$@" ;;
    setup-billing) infra-setup-billing "$@" ;;
    setup-apis) infra-setup-apis "$@" ;;
    setup-bucket) infra-setup-bucket "$@" ;;
    setup-sa) infra-setup-sa "$@" ;;
    setup-sa-key) infra-setup-sa-key "$@" ;;
    output-config) infra-output-config "$@" ;;
    verify) infra-verify "$@" ;;
    teardown) infra-teardown "$@" ;;
    *) usage; exit 1 ;;
  esac
}

infra-check() {
  >&2 echo "Checking prerequisites..."

  if ! command -v gcloud &>/dev/null; then
    >&2 echo "FAIL: gcloud not found"
    exit 1
  fi
  >&2 echo "  gcloud: OK"

  local account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
  if [[ -z "$account" ]]; then
    >&2 echo "FAIL: not logged in (run: gcloud auth login)"
    exit 1
  fi
  >&2 echo "  auth: OK ($account)"

  >&2 echo "Prerequisites OK"
}

# --- Infra Setup Subcommands ---

infra-setup-project() {
  local project_id="${GCP_TTS_PROJECT_ID:-tts-$(date +%s)}"
  >&2 echo "Creating project: $project_id"
  gcloud projects create "$project_id" --quiet 2>/dev/null || true
  echo "$project_id"
}

infra-setup-billing() {
  local project_id="${1:-$(gcloud config get-value project 2>/dev/null)}"
  [[ -z "$project_id" ]] && { >&2 echo "Error: No project specified"; exit 1; }
  
  # Get billing account
  local billing_account=$(gcloud billing accounts list --format="value(name)" --limit=1 2>/dev/null)
  if [[ -z "$billing_account" ]]; then
    >&2 echo "FAIL: No billing account found or cloudbilling API not enabled"
    >&2 echo "Enable with: gcloud services enable cloudbilling.googleapis.com"
    exit 1
  fi
  
  >&2 echo "Linking billing account $billing_account to $project_id"
  gcloud billing projects link "$project_id" --billing-account="$billing_account" --quiet >/dev/null
}

infra-setup-apis() {
  local project_id="${1:-$(gcloud config get-value project 2>/dev/null)}"
  [[ -z "$project_id" ]] && { >&2 echo "Error: No project specified"; exit 1; }
  
  >&2 echo "Enabling TTS API on $project_id..."
  gcloud services enable texttospeech.googleapis.com --project="$project_id" --quiet
}

infra-setup-bucket() {
  local project_id="${1:-$(gcloud config get-value project 2>/dev/null)}"
  [[ -z "$project_id" ]] && { >&2 echo "Error: No project specified"; exit 1; }
  
  local bucket="gs://${project_id}-tts-output"
  >&2 echo "Creating bucket: $bucket"
  gcloud storage buckets create "$bucket" --project="$project_id" --location=us-central1 --quiet 2>/dev/null || true
  echo "$bucket"
}

infra-setup-sa() {
  local project_id="${1:-$(gcloud config get-value project 2>/dev/null)}"
  local bucket="${2:-gs://${project_id}-tts-output}"
  [[ -z "$project_id" ]] && { >&2 echo "Error: No project specified"; exit 1; }
  
  local sa_name="tts-worker"
  local sa_email="${sa_name}@${project_id}.iam.gserviceaccount.com"
  
  >&2 echo "Creating service account: $sa_email"
  gcloud iam service-accounts create "$sa_name" \
    --display-name="TTS Worker" \
    --project="$project_id" --quiet 2>/dev/null || true
  
  >&2 echo "Granting storage access..."
  gcloud projects add-iam-policy-binding "$project_id" \
    --member="serviceAccount:$sa_email" \
    --role="roles/storage.admin" --quiet >/dev/null
  
  >&2 echo "Granting serviceusage access..."
  gcloud projects add-iam-policy-binding "$project_id" \
    --member="serviceAccount:$sa_email" \
    --role="roles/serviceusage.serviceUsageConsumer" --quiet >/dev/null
  
  echo "$sa_email"
}

infra-setup-sa-key() {
  local sa_email="${1:-}"
  [[ -z "$sa_email" ]] && { >&2 echo "Error: No service account email specified"; exit 1; }
  
  >&2 echo "Generating key for: $sa_email"
  local tmp_key=$(mktemp)
  gcloud iam service-accounts keys create "$tmp_key" \
    --iam-account="$sa_email" --quiet
  cat "$tmp_key"
  rm -f "$tmp_key"
}

infra-output-config() {
  local bucket="${1:-}"
  local sa_key_file="${2:-/dev/stdin}"
  [[ -z "$bucket" ]] && { >&2 echo "Error: No bucket specified"; exit 1; }
  
  jq -n \
    --arg bucket "$bucket" \
    --slurpfile sa "$sa_key_file" \
    '{bucket: $bucket, serviceaccount: $sa[0]}'
}

# --- Full Setup (creates new project) ---

infra-setup() {
  local project_id="${GCP_TTS_PROJECT_ID:-tts-$(date +%s)}"

  >&2 echo "=== Setting up GCP TTS infrastructure ==="
  >&2 echo "Project: $project_id"

  # Check cloudbilling is enabled on current project
  gcloud services list --enabled --filter="name:cloudbilling.googleapis.com" --format="value(name)" 2>/dev/null | \
    grep -q cloudbilling || \
    { >&2 echo "FAIL: cloudbilling API not enabled on current project." && \
      >&2 echo "Run: gcloud services enable cloudbilling.googleapis.com" && \
      >&2 echo "Or use individual subcommands on an existing project:" && \
      >&2 echo "  infra setup-apis <project>" && \
      >&2 echo "  infra setup-bucket <project>" && \
      >&2 echo "  infra setup-sa <project> <bucket>" && \
      exit 1; }

  # Create project
  export GCP_TTS_PROJECT_ID="$project_id"
  infra-setup-project >/dev/null
  
  # Link billing
  infra-setup-billing "$project_id"
  
  # Enable APIs
  infra-setup-apis "$project_id"
  
  # Create bucket
  local bucket=$(infra-setup-bucket "$project_id")
  
  # Create service account
  local sa_email=$(infra-setup-sa "$project_id" "$bucket")
  
  # Generate key and output config
  infra-setup-sa-key "$sa_email" | infra-output-config "$bucket"

  >&2 echo "=== Setup complete ==="
}

infra-verify() {
  local config_file="${1:-config.json}"

  >&2 echo "Verifying setup..."

  local token=$(get-access-token "$config_file")
  if [[ -z "$token" || "$token" == "null" ]]; then
    >&2 echo "FAIL: Could not get access token"
    exit 1
  fi
  >&2 echo "  Token: OK"

  local project_id=$(config-project-id "$config_file")
  local bucket=$(config-bucket "$config_file")

  # Test short API
  local response=$(curl -s -X POST \
    "https://texttospeech.googleapis.com/v1/text:synthesize" \
    -H "Authorization: Bearer $token" \
    -H "x-goog-user-project: $project_id" \
    -H "Content-Type: application/json" \
    -d '{"input":{"text":"test"},"voice":{"languageCode":"en-US","name":"en-US-Studio-O"},"audioConfig":{"audioEncoding":"MP3"}}')

  if echo "$response" | jq -e '.audioContent' >/dev/null 2>&1; then
    >&2 echo "  Short API: OK"
  else
    >&2 echo "FAIL: Short API error: $response"
    exit 1
  fi

  >&2 echo "Verification complete!"
}

infra-teardown() {
  local config_file="${1:-config.json}"
  local project_id=$(config-project-id "$config_file")
  local bucket=$(config-bucket "$config_file")

  >&2 echo "=== Tearing down infrastructure ==="

  # Delete service account
  local sa_email="tts-worker@${project_id}.iam.gserviceaccount.com"
  >&2 echo "Deleting service account: $sa_email"
  gcloud iam service-accounts delete "$sa_email" --project="$project_id" --quiet 2>/dev/null || true

  # Delete bucket
  >&2 echo "Deleting bucket: $bucket"
  gcloud storage rm -r "$bucket" --quiet 2>/dev/null || true

  # Disable API
  >&2 echo "Disabling TTS API..."
  gcloud services disable texttospeech.googleapis.com --project="$project_id" --quiet 2>/dev/null || true

  # Delete project
  >&2 echo "Deleting project: $project_id"
  gcloud projects delete "$project_id" --quiet 2>/dev/null || true

  >&2 echo "=== Teardown complete ==="
}

# --- Self Test ---

self-test() {
  local config_file="${1:-config.json}"

  if [[ ! -f "$config_file" ]]; then
    >&2 echo "Error: Config file not found: $config_file"
    exit 1
  fi

  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local essay_file="${script_dir}/olga-essay.txt"

  >&2 echo "=== Self Test ==="

  # Test which-pipeline
  local short_text="Hello world"
  local short_pipeline=$(echo "$short_text" | tts-which-pipeline)
  [[ "$short_pipeline" == "short" ]] || { >&2 echo "FAIL: which-pipeline for short text"; exit 1; }
  >&2 echo "  which-pipeline (short): OK"

  if [[ -f "$essay_file" ]]; then
    local long_pipeline=$(cat "$essay_file" | tts-which-pipeline)
    [[ "$long_pipeline" == "long" ]] || { >&2 echo "FAIL: which-pipeline for long text"; exit 1; }
    >&2 echo "  which-pipeline (long): OK"
  fi

  # Test short synthesis
  >&2 echo "Testing short pipeline..."
  local short_out="/tmp/gcp-tts-test-short.m4a"
  echo "Hello world, this is a test." | tts-synthesize "$config_file" > "$short_out"
  local short_size=$(wc -c < "$short_out")
  >&2 echo "  Short output: $short_out ($short_size bytes)"
  [[ $short_size -gt 1000 ]] || { >&2 echo "FAIL: Short output too small"; exit 1; }
  >&2 echo "  Short pipeline: OK"

  # Test long synthesis if essay exists
  if [[ -f "$essay_file" ]]; then
    >&2 echo "Testing long pipeline with essay..."
    export TTS_OBJECT_NAME="self-test-$(date +%s)"
    local long_out="/tmp/gcp-tts-test-long.m4a"
    cat "$essay_file" | tts-synthesize "$config_file" > "$long_out"
    local long_size=$(wc -c < "$long_out")
    >&2 echo "  Long output: $long_out ($long_size bytes)"
    [[ $long_size -gt 1000000 ]] || { >&2 echo "FAIL: Long output too small"; exit 1; }
    >&2 echo "  Long pipeline: OK"
  fi

  >&2 echo ""
  >&2 echo "=== SELF-TEST PASSED ==="
}

# --- Usage ---

usage() {
  cat <<EOF
Usage: $0 <group> <command> [args]

TTS Commands (portable: curl, openssl, jq, ffmpeg):
  tts synthesize <config>   Auto-select short/long pipeline
  tts short <config>        Force short pipeline (≤5KB)
  tts long <config>         Force long pipeline (≤1MB)
  tts which-pipeline        Output "short" or "long" based on stdin

Infra Commands (requires gcloud):
  infra check               Verify gcloud and permissions
  infra setup               Full setup: new project → config.json
  infra verify <config>     Test that config works
  infra teardown <config>   Delete everything

  Infra subcommands (for existing projects):
    infra setup-project           Create project (uses GCP_TTS_PROJECT_ID)
    infra setup-billing <proj>    Link billing account
    infra setup-apis <proj>       Enable TTS API
    infra setup-bucket <proj>     Create GCS bucket, outputs bucket URI
    infra setup-sa <proj> <bucket>  Create SA with permissions, outputs email
    infra setup-sa-key <email>    Generate SA key JSON to stdout
    infra output-config <bucket>  Read SA key from stdin, output config.json

Testing:
  self-test <config>        Run self-test

Environment:
  TTS_VOICE          Voice (default: en-US-Studio-O)
  TTS_OUTPUT_FORMAT  m4a, opus, mp3, wav (default: m4a)
  TTS_OBJECT_NAME    GCS object name (default: timestamp-nanoseconds)
  GCP_TTS_PROJECT_ID Project ID for infra setup (default: tts-<timestamp>)

Examples:
  # Full setup (new project)
  ./gcp-tts.sh infra setup > config.json

  # Setup on existing project
  PROJ=my-existing-project
  ./gcp-tts.sh infra setup-apis \$PROJ
  BUCKET=\$(./gcp-tts.sh infra setup-bucket \$PROJ)
  SA=\$(./gcp-tts.sh infra setup-sa \$PROJ \$BUCKET)
  ./gcp-tts.sh infra setup-sa-key \$SA | ./gcp-tts.sh infra output-config \$BUCKET > config.json

  # Synthesize
  cat essay.txt | ./gcp-tts.sh tts synthesize config.json > essay.m4a

Advanced:
  janky-e2e-test            Full E2E: setup → docker container → teardown
                            Requires: docker, gcloud logged in, billing API enabled
EOF
}

# --- Janky E2E Test ---

janky-e2e-test() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local config_file="/tmp/janky-e2e-config-$$.json"
  local payload_file="/tmp/janky-e2e-payload-$$.txt"
  local output_file="/tmp/janky-e2e-output-$$.m4a"
  
  >&2 echo "=== Janky E2E Test ==="
  >&2 echo "Prerequisites: docker, gcloud logged in, billing API enabled"
  >&2 echo ""
  
  # Check docker
  if ! command -v docker &>/dev/null; then
    >&2 echo "FAIL: docker not found"
    exit 1
  fi
  
  # Step 1: Setup infrastructure
  >&2 echo "--- Step 1: Creating GCP infrastructure ---"
  export GCP_TTS_PROJECT_ID="tts-e2e-$(date +%s)"
  "$script_dir/gcp-tts.sh" infra setup > "$config_file"
  >&2 echo "Config: $config_file"
  >&2 echo ""
  
  # Step 2: Create test payload (>5KB to force long pipeline)
  >&2 echo "--- Step 2: Creating test payload ---"
  for i in $(seq 1 150); do echo "This is sentence number $i of the E2E test payload."; done > "$payload_file"
  >&2 echo "Payload: $(wc -c < "$payload_file") bytes"
  >&2 echo ""
  
  # Step 3: Run in container
  >&2 echo "--- Step 3: Running synthesis in Ubuntu container ---"
  local docker_exit=0
  docker run --rm \
    -v "$config_file:/app/config.json:ro" \
    -v "$payload_file:/app/input.txt:ro" \
    -v "$script_dir/gcp-tts.sh:/app/gcp-tts.sh:ro" \
    -v "/tmp:/output" \
    ubuntu:22.04 \
    bash -c "
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update >/dev/null
      apt-get install -y curl jq openssl ffmpeg >/dev/null 2>&1
      cd /app
      cat input.txt | ./gcp-tts.sh tts synthesize config.json > /output/$(basename "$output_file")
    " || docker_exit=$?
  
  if [[ $docker_exit -ne 0 ]]; then
    >&2 echo "FAIL: Docker synthesis failed (exit $docker_exit)"
    >&2 echo ""
    >&2 echo "--- Cleaning up ---"
    "$script_dir/gcp-tts.sh" infra teardown "$config_file" || true
    rm -f "$config_file" "$payload_file" "$output_file" 2>/dev/null || true
    exit 1
  fi
  >&2 echo ""
  
  # Step 4: Verify output
  >&2 echo "--- Step 4: Verifying output ---"
  if [[ ! -f "$output_file" ]]; then
    >&2 echo "FAIL: Output file not created"
    "$script_dir/gcp-tts.sh" infra teardown "$config_file" || true
    rm -f "$config_file" "$payload_file" 2>/dev/null || true
    exit 1
  fi
  
  local file_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null)
  local duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$output_file" 2>/dev/null || echo "0")
  
  >&2 echo "Output: $output_file"
  >&2 echo "Size: $file_size bytes"
  >&2 echo "Duration: ${duration}s"
  
  if [[ $file_size -lt 100000 ]]; then
    >&2 echo "FAIL: Output file too small (expected >100KB)"
    "$script_dir/gcp-tts.sh" infra teardown "$config_file" || true
    rm -f "$config_file" "$payload_file" "$output_file" 2>/dev/null || true
    exit 1
  fi
  >&2 echo ""
  
  # Step 5: Teardown
  >&2 echo "--- Step 5: Tearing down infrastructure ---"
  "$script_dir/gcp-tts.sh" infra teardown "$config_file"
  >&2 echo ""
  
  # Cleanup temp files
  rm -f "$config_file" "$payload_file" "$output_file" 2>/dev/null || true
  
  >&2 echo "=== E2E Test PASSED ==="
}

# --- Main ---

case "${1:-}" in
  tts) shift; tts "$@" ;;
  infra) shift; infra "$@" ;;
  self-test) shift; self-test "$@" ;;
  janky-e2e-test) janky-e2e-test ;;
  *) usage; exit 1 ;;
esac
