# LLM-RETROSPECTIVE.md

## What went well
- Iterative approach: `attempt1.sh` → `attempt6.sh` → `dvd-helper.sh`
- User feedback drove improvements (audio fix, stream copy, grouping logic removal)
- Verbose flag was crucial for debugging ffmpeg errors
- `set -euo pipefail` + proper `if command` patterns

## What went wrong
- Initial grouping logic was unnecessary complexity
- `$?` checks with `set -euo pipefail` were redundant
- Missing `.mkv` extension caused silent failures
- Output redirection hid critical error messages

## Key learnings
- User defines groups by CLI invocation, not script logic
- Verbose mode essential for ffmpeg debugging
- Shell scripting: use `if command` not `command; if [[ $? -eq 0 ]]`
- Always show actual errors, not just "failed"

## Outcome
- Robust, fast DVD conversion script
- Handles VOB → MKV with stream copy
- Proper error handling and debugging
- Reusable for future DVD projects
