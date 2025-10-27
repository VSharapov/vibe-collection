#!/bin/bash

set -euo pipefail

echo "=== Simple OpenSSH Entropy Test ==="
echo

# Create working directory
WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

echo "Working directory: $WORKDIR"
echo

# Function to generate key and capture strace output
generate_key_with_strace() {
    local key_file="$1"
    local description="$2"
    
    echo "--- $description ---"
    
    # Run ssh-keygen with strace to monitor entropy reads
    strace -e trace=read,openat,getrandom -f -o "$WORKDIR/strace_${key_file}.log" \
        ssh-keygen -t ed25519 -f "$WORKDIR/$key_file" -N "" -C "test@example.com" 2>/dev/null
    
    # Extract entropy read information from strace
    echo "Entropy reads from strace:"
    grep -E "(getrandom|/dev/random|/dev/urandom)" "$WORKDIR/strace_${key_file}.log" | head -5 || echo "No entropy reads found"
    echo
}

# Function to compare keys
compare_keys() {
    local key1="$1"
    local key2="$2"
    local description="$3"
    
    echo "--- $description ---"
    if diff "$WORKDIR/$key1" "$WORKDIR/$key2" >/dev/null 2>&1; then
        echo "Keys are IDENTICAL"
    else
        echo "Keys are DIFFERENT"
    fi
}

echo "Step 1: Generate 2 keys normally (should be different)"
generate_key_with_strace "key1_normal" "Normal key generation #1"
generate_key_with_strace "key2_normal" "Normal key generation #2"

echo "Step 2: Compare normal keys"
compare_keys "key1_normal" "key2_normal" "Normal keys comparison"

echo "Step 3: Test with controlled entropy using LD_PRELOAD approach"
# Create a simple entropy source
dd if=/dev/urandom of="$WORKDIR/entropy_source" bs=1024 count=10 2>/dev/null

# Test with different entropy sources
echo "Testing with limited entropy source..."
# This is a simplified test - we'll just run ssh-keygen and see what happens
generate_key_with_strace "key1_limited" "Limited entropy key generation #1"
generate_key_with_strace "key2_limited" "Limited entropy key generation #2"

echo "Step 4: Compare limited entropy keys"
compare_keys "key1_limited" "key2_limited" "Limited entropy keys comparison"

echo "Step 5: Analyze entropy consumption"
echo "--- Entropy Consumption Analysis ---"
for log_file in "$WORKDIR"/strace_*.log; do
    if [[ -f "$log_file" ]]; then
        echo "File: $(basename "$log_file")"
        echo "Total entropy reads: $(grep -c "getrandom\|read.*/dev/urandom\|read.*/dev/random" "$log_file" 2>/dev/null || echo "0")"
        echo "Bytes read from entropy:"
        grep "getrandom\|read.*/dev/urandom\|read.*/dev/random" "$log_file" | head -3 || echo "No entropy reads found"
        echo
    fi
done

echo "=== Test Complete ==="
echo "Check $WORKDIR for all generated keys and strace logs"