# DVD Helper Script Specification

## Overview
A comprehensive script to convert DVD VOB files to clean MKV format with intelligent file grouping and optional cleanup.

## Command Line Interface

### Basic Usage
```bash
dvd-helper.sh [OPTIONS] VOB_FILES...
```

### Options
- `--workdir=DIR` - Temporary working directory (default: `mktemp -d`)
- `--outputdir=DIR` - Output directory for final MKV files (default: `./`)
- `--delete-parts` - Delete intermediate part files after combination (default: false)
- `--verbose` - Enable verbose output (default: false)
- `--name=NAME` - Override output filename pattern (default: auto-detect from VOB files)

### Examples
```bash
# Basic usage with auto-detection
dvd-helper.sh VTS_01_*.VOB

# Custom work and output directories
dvd-helper.sh --workdir=./temp --outputdir=./output VTS_01_*.VOB

# Delete intermediate files and use custom name
dvd-helper.sh --delete-parts --name=main VTS_01_*.VOB

# Verbose output
dvd-helper.sh --verbose VTS_01_*.VOB VTS_02_*.VOB
```

## Behavior

### File Grouping Logic
1. **Auto-detect common prefix**: Find longest common prefix among all VOB files
2. **Group by prefix**: Group files with same prefix into one output MKV
3. **Naming convention**: 
   - If common prefix length > 0: use `{prefix}.mkv`
   - If common prefix length = 0: use first file's basename as `{basename}.mkv`

### Processing Pipeline
1. **Validate inputs**: Check VOB files exist and are readable
2. **Create workdir**: Set up temporary working directory
3. **Convert VOBs**: Use ffmpeg with timestamp fixes for each VOB file
4. **Group and combine**: Concatenate related VOBs into single MKV per group
5. **Move to output**: Copy final MKV files to output directory
6. **Cleanup**: Optionally remove intermediate files

### Error Handling
- Exit on any critical error with clear message
- Preserve workdir on failure for debugging
- Validate ffmpeg availability before processing
- Check disk space before starting conversion

## Technical Details

### FFmpeg Parameters
- Input: `-fflags +genpts` for timestamp fixes
- Output: `-c copy -avoid_negative_ts make_zero` for stream copying
- Format: MKV container for better metadata support

### File Naming Examples
- `VTS_01_1.VOB`, `VTS_01_2.VOB`, `VTS_01_3.VOB` → `VTS_01_.mkv`
- `main_part1.VOB`, `main_part2.VOB` → `main_part.mkv`
- `1.VOB`, `2.VOB`, `3.VOB` → `1.mkv`
- `extras_1.VOB`, `extras_2.VOB` → `extras_.mkv`

## Implementation Notes
- Use well-named functions instead of comments
- Implement proper argument parsing
- Add progress indicators for long operations
- Support multiple file groups in single invocation
- Maintain original video/audio quality (no transcoding)