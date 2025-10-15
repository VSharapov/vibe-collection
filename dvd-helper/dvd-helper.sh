#!/bin/bash

set -euo pipefail

WORKDIR=""
OUTPUTDIR="./"
DELETE_PARTS=false
VERBOSE=false
NAME=""
VOB_FILES=()

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] VOB_FILES...

Convert DVD VOB files to clean MKV format.

OPTIONS:
    --workdir=DIR      Temporary working directory (default: mktemp -d)
    --outputdir=DIR    Output directory for final MKV files (default: ./)
    --delete-parts     Delete intermediate part files after combination
    --verbose          Enable verbose output
    --name=NAME        Override output filename pattern (default: auto-detect)
    --help             Show this help message

EXAMPLES:
    $0 VTS_01_*.VOB
    $0 --workdir=./temp --outputdir=./output VTS_01_*.VOB
    $0 --delete-parts --name=extras VTS_02_*.VOB
    $0 --verbose VTS_01_*.VOB VTS_02_*.VOB

EOF
}

log() {
    if [[ "$VERBOSE" == "true" || "$1" == "ERROR" || "$1" == "INFO" ]]; then
        echo "[$1] $2" >&2
    fi
}

check_ffmpeg() {
    if ! command -v ffmpeg >/dev/null 2>&1; then
        log "ERROR" "ffmpeg is required but not installed"
        exit 1
    fi
    if ! command -v ffprobe >/dev/null 2>&1; then
        log "ERROR" "ffprobe is required but not installed"
        exit 1
    fi
}

validate_vob_files() {
    if [[ ${#VOB_FILES[@]} -eq 0 ]]; then
        log "ERROR" "No VOB files specified"
        show_usage
        exit 1
    fi
    
    for vob_file in "${VOB_FILES[@]}"; do
        if [[ ! -f "$vob_file" ]]; then
            log "ERROR" "VOB file not found: $vob_file"
            exit 1
        fi
        if [[ ! -r "$vob_file" ]]; then
            log "ERROR" "VOB file not readable: $vob_file"
            exit 1
        fi
    done
    
    log "INFO" "Validated ${#VOB_FILES[@]} VOB files"
}

find_common_prefix() {
    local files=("$@")
    if [[ ${#files[@]} -eq 0 ]]; then
        echo ""
        return
    fi
    
    local first_file="${files[0]}"
    local basename_first=$(basename "$first_file" .VOB)
    local common_prefix="$basename_first"
    
    for file in "${files[@]:1}"; do
        local basename_file=$(basename "$file" .VOB)
        local new_prefix=""
        
        for ((i=0; i<${#common_prefix} && i<${#basename_file}; i++)); do
            if [[ "${common_prefix:$i:1}" == "${basename_file:$i:1}" ]]; then
                new_prefix+="${common_prefix:$i:1}"
            else
                break
            fi
        done
        common_prefix="$new_prefix"
    done
    
    echo "$common_prefix"
}

determine_output_name() {
    local files=("$@")
    local common_prefix
    
    if [[ -n "$NAME" ]]; then
        if [[ "$NAME" == *.mkv ]]; then
            echo "$NAME"
        else
            echo "${NAME}.mkv"
        fi
        return
    fi
    
    common_prefix=$(find_common_prefix "${files[@]}")
    
    if [[ ${#common_prefix} -gt 0 ]]; then
        echo "${common_prefix}.mkv"
    else
        local first_file="${files[0]}"
        local basename_first=$(basename "$first_file" .VOB)
        echo "${basename_first}.mkv"
    fi
}


convert_vob_to_mkv() {
    local input_file="$1"
    local output_file="$2"
    
    log "INFO" "Converting $(basename "$input_file") to $(basename "$output_file")"
    
    local ffmpeg_output
    if [[ "$VERBOSE" == "true" ]]; then
        ffmpeg_output=""
    else
        ffmpeg_output=">/dev/null 2>&1"
    fi
    
    if eval "ffmpeg -fflags +genpts -i '$input_file' -c copy -avoid_negative_ts make_zero -fflags +genpts -y '$output_file' $ffmpeg_output"; then
        log "INFO" "Successfully converted $(basename "$input_file")"
    else
        log "ERROR" "Failed to convert $(basename "$input_file")"
        return 1
    fi
}

concatenate_mkv_files() {
    local input_files=("$@")
    local output_file="${input_files[-1]}"
    unset input_files[-1]
    
    log "INFO" "Concatenating ${#input_files[@]} files into $(basename "$output_file")"
    
    local concat_file=$(mktemp)
    for file in "${input_files[@]}"; do
        echo "file '$(realpath "$file")'" >> "$concat_file"
    done
    
    local ffmpeg_output
    if [[ "$VERBOSE" == "true" ]]; then
        ffmpeg_output=""
    else
        ffmpeg_output=">/dev/null 2>&1"
    fi
    
    if eval "ffmpeg -f concat -safe 0 -i '$concat_file' -c copy -y '$output_file' $ffmpeg_output"; then
        log "INFO" "Successfully created $(basename "$output_file")"
    else
        log "ERROR" "Failed to concatenate files into $(basename "$output_file")"
        rm -f "$concat_file"
        return 1
    fi
    
    rm -f "$concat_file"
}

process_vob_files() {
    local output_name=$(determine_output_name "${VOB_FILES[@]}")
    local workdir="$1"
    local outputdir="$2"
    
    log "INFO" "Processing files: ${VOB_FILES[*]} -> $output_name"
    
    local mkv_files=()
    for vob_file in "${VOB_FILES[@]}"; do
        local mkv_file="$workdir/$(basename "$vob_file" .VOB).mkv"
        convert_vob_to_mkv "$vob_file" "$mkv_file"
        mkv_files+=("$mkv_file")
    done
    
    local final_output="$workdir/$output_name"
    concatenate_mkv_files "${mkv_files[@]}" "$final_output"
    
    local final_dest="$outputdir/$output_name"
    mv "$final_output" "$final_dest"
    log "INFO" "Created final file: $final_dest"
    
    if [[ "$DELETE_PARTS" == "true" ]]; then
        rm -f "${mkv_files[@]}"
        log "INFO" "Cleaned up intermediate files"
    fi
}

setup_workdir() {
    if [[ -z "$WORKDIR" ]]; then
        WORKDIR=$(mktemp -d)
        log "INFO" "Created temporary workdir: $WORKDIR"
    else
        mkdir -p "$WORKDIR"
        log "INFO" "Using workdir: $WORKDIR"
    fi
}

setup_outputdir() {
    mkdir -p "$OUTPUTDIR"
    log "INFO" "Using outputdir: $OUTPUTDIR"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --workdir=*)
                WORKDIR="${1#*=}"
                shift
                ;;
            --outputdir=*)
                OUTPUTDIR="${1#*=}"
                shift
                ;;
            --delete-parts)
                DELETE_PARTS=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --name=*)
                NAME="${1#*=}"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                VOB_FILES+=("$1")
                shift
                ;;
        esac
    done
}

show_summary() {
    local output_files=("$OUTPUTDIR"/*.mkv)
    if [[ ${#output_files[@]} -eq 0 || ! -f "${output_files[0]}" ]]; then
        log "ERROR" "No output files created"
        return 1
    fi
    
    log "INFO" "Conversion complete!"
    log "INFO" "Created ${#output_files[@]} MKV files in $OUTPUTDIR:"
    for file in "${output_files[@]}"; do
        if [[ -f "$file" ]]; then
            local size=$(du -h "$file" | cut -f1)
            local duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | awk '{print int($1/60)":"int($1%60)}' || echo "unknown")
            log "INFO" "  $(basename "$file") - $size - $duration"
        fi
    done
}

main() {
    parse_arguments "$@"
    
    check_ffmpeg
    validate_vob_files
    setup_workdir
    setup_outputdir
    
    process_vob_files "$WORKDIR" "$OUTPUTDIR"
    
    show_summary
    
    if [[ "$WORKDIR" =~ ^/tmp/ ]]; then
        rm -rf "$WORKDIR"
        log "INFO" "Cleaned up temporary workdir"
    fi
}

main "$@"
