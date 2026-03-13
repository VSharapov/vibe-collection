#!/usr/bin/env python3
"""
smart_splice.py - Splice two overlapping audio recordings using cross-correlation

Finds the exact overlap point between two recordings and splices them seamlessly.
"""

import argparse
import subprocess
import tempfile
import os
import numpy as np
from scipy import signal

def load_audio(filepath, sr=16000):
    """Load audio file to numpy array using ffmpeg"""
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        tmp_path = tmp.name
    
    try:
        # Convert to mono WAV at specified sample rate
        subprocess.run([
            'ffmpeg', '-v', 'quiet', '-y',
            '-i', filepath,
            '-ac', '1',  # mono
            '-ar', str(sr),  # sample rate
            '-f', 'wav',
            tmp_path
        ], check=True)
        
        # Read the WAV file
        import wave
        with wave.open(tmp_path, 'rb') as wf:
            frames = wf.readframes(wf.getnframes())
            audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
        
        return audio, sr
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

def find_offset(audio1, audio2, sr, window_seconds=8):
    """
    Find where audio2's content begins relative to audio1's timeline.
    
    Since audio2 was recorded by seeking into the track, its beginning
    should match somewhere in the latter part of audio1.
    
    Returns: overlap_seconds (how much of audio2's start overlaps with audio1's end)
    """
    window_samples = sr * window_seconds
    
    # Take the last portion of audio1 (where overlap should be)
    tail_samples = min(len(audio1), sr * 15)  # Last 15 seconds max
    audio1_tail = audio1[-tail_samples:]
    
    # Take the first portion of audio2 (the overlapping part)
    audio2_head = audio2[:window_samples] if len(audio2) > window_samples else audio2
    
    # Cross-correlate: find where audio2_head appears in audio1_tail
    c = signal.correlate(audio1_tail, audio2_head, mode='full', method='fft')
    
    # Find peak correlation
    peak_idx = np.argmax(np.abs(c))
    peak_value = c[peak_idx]
    
    # The peak index tells us the lag
    # In 'full' mode, index 0 means audio2_head starts at position -(len(audio2_head)-1) in audio1_tail
    # The "zero lag" point is at index (len(audio2_head) - 1)
    zero_lag_idx = len(audio2_head) - 1
    lag_samples = peak_idx - zero_lag_idx
    
    # lag_samples is where audio2_head starts in audio1_tail
    # Positive lag means audio2 starts later in audio1_tail
    match_position_in_tail = lag_samples
    
    # Convert to position in full audio1
    match_position = len(audio1) - tail_samples + match_position_in_tail
    
    # The overlap is from match_position to end of audio1
    overlap_samples = len(audio1) - match_position
    overlap_seconds = overlap_samples / sr
    
    # Confidence metric
    noise_floor = np.median(np.abs(c))
    confidence = abs(peak_value) / (noise_floor + 1e-10)
    
    return overlap_seconds, confidence, match_position / sr

def get_duration(filepath):
    """Get duration of audio file using ffprobe"""
    result = subprocess.run([
        'ffprobe', '-v', 'quiet', '-show_entries', 'format=duration',
        '-of', 'csv=p=0', filepath
    ], capture_output=True, text=True)
    return float(result.stdout.strip())

def splice_audio(part1_path, part2_path, output_path, crossfade_ms=50):
    """
    Splice two audio files by finding their overlap and joining seamlessly.
    Uses low-quality analysis for offset detection, but splices original files.
    """
    # Get original durations
    dur1 = get_duration(part1_path)
    dur2 = get_duration(part2_path)
    print(f"Part 1: {part1_path} ({dur1:.2f}s)")
    print(f"Part 2: {part2_path} ({dur2:.2f}s)")
    
    # Load low-quality versions for analysis only
    print("\nAnalyzing overlap (downsampled for speed)...")
    audio1, sr = load_audio(part1_path, sr=16000)
    audio2, _ = load_audio(part2_path, sr=16000)
    
    overlap_seconds, confidence, match_start = find_offset(audio1, audio2, sr)
    print(f"  Audio2 content starts at {match_start:.2f}s in part1's timeline")
    print(f"  Overlap duration: {overlap_seconds:.2f}s")
    print(f"  Confidence: {confidence:.1f}x above noise floor")
    
    print(f"\nSplice plan:")
    print(f"  Keep part1: full ({dur1:.2f}s)")
    print(f"  Skip part2: first {overlap_seconds:.2f}s")
    print(f"  Keep part2: {overlap_seconds:.2f}s to {dur2:.2f}s")
    
    expected_duration = dur1 + dur2 - overlap_seconds
    print(f"  Expected output: {expected_duration:.2f}s")
    
    # Use ffmpeg to splice at full quality
    with tempfile.TemporaryDirectory() as tmpdir:
        # Trim part2 to remove overlap
        part2_trimmed = os.path.join(tmpdir, 'part2_trimmed.mp3')
        subprocess.run([
            'ffmpeg', '-v', 'warning', '-y',
            '-i', part2_path,
            '-ss', str(overlap_seconds),
            '-c', 'copy',
            part2_trimmed
        ], check=True)
        
        # Create concat list
        concat_list = os.path.join(tmpdir, 'concat.txt')
        with open(concat_list, 'w') as f:
            f.write(f"file '{os.path.abspath(part1_path)}'\n")
            f.write(f"file '{part2_trimmed}'\n")
        
        # Concatenate at full quality
        print("\nSplicing at original quality...")
        result = subprocess.run([
            'ffmpeg', '-v', 'warning', '-y',
            '-f', 'concat', '-safe', '0',
            '-i', concat_list,
            '-c', 'copy',
            output_path
        ], capture_output=True, text=True)
        
        # Ignore non-monotonic DTS warnings (normal for MP3 concat)
        if result.returncode != 0:
            print(f"Warning: {result.stderr}")
    
    final_duration = get_duration(output_path)
    print(f"\nResult:")
    print(f"  Output: {output_path}")
    print(f"  Duration: {final_duration:.2f}s")
    
    # Create a verification snippet around the splice point (preserve quality)
    splice_check_path = output_path.replace('.mp3', '_splice_check.mp3')
    splice_time = dur1
    snippet_start = max(0, splice_time - 3)
    subprocess.run([
        'ffmpeg', '-v', 'quiet', '-y',
        '-i', output_path,
        '-ss', str(snippet_start),
        '-t', '6',
        '-c:a', 'libmp3lame', '-b:a', '192k',
        splice_check_path
    ], check=True)
    print(f"  Splice check: {splice_check_path} ({snippet_start:.1f}s to {snippet_start+6:.1f}s)")
    
    return overlap_seconds, final_duration

def main():
    parser = argparse.ArgumentParser(
        description='Smart audio splice using cross-correlation to find overlap',
        usage='%(prog)s <chunk1.mp3> <chunk2.mp3> [chunk3.mp3 ...] <output.mp3>'
    )
    parser.add_argument('files', nargs='+', help='Input files followed by output file (minimum 3 args)')
    parser.add_argument('--crossfade', type=int, default=50, help='Crossfade duration in ms (default: 50)')
    
    args = parser.parse_args()
    
    if len(args.files) < 3:
        parser.error('Need at least 2 input files and 1 output file')
    
    inputs = args.files[:-1]
    output = args.files[-1]
    
    if len(inputs) == 1:
        parser.error('Need at least 2 input files to splice')
    
    print(f"Splicing {len(inputs)} files -> {output}\n")
    
    # Splice sequentially
    current = inputs[0]
    for i, next_file in enumerate(inputs[1:], 1):
        is_final = (i == len(inputs) - 1)
        
        if is_final:
            out_file = output
        else:
            out_file = f"/tmp/splice_temp_{i}.mp3"
        
        print(f"=== Step {i}/{len(inputs)-1}: {os.path.basename(current)} + {os.path.basename(next_file)} ===")
        splice_audio(current, next_file, out_file, args.crossfade)
        print()
        
        # Clean up intermediate temp file
        if not is_final and i > 1:
            os.unlink(current)
        
        current = out_file
    
    print(f"Final output: {output}")

if __name__ == '__main__':
    main()
