#!/bin/bash

set -euo pipefail

# OpenSSH Entropy Source Experiment
# Tests how ssh-keygen behaves with different entropy sources

echo "=== OpenSSH Entropy Source Experiment ==="
echo

# Create working directory
WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

echo "Working directory: $WORKDIR"
echo

# Function to generate key and capture strace output
generate_key_with_strace() {
    local key_file="$1"
    local entropy_source="$2"
    local description="$3"
    
    echo "--- $description ---"
    echo "Entropy source: $entropy_source"
    
    # Run ssh-keygen with strace to monitor entropy reads
    strace -e trace=read,openat -f -o "$WORKDIR/strace_${key_file}.log" \
        ssh-keygen -t ed25519 -f "$WORKDIR/$key_file" -N "" -C "test@example.com" 2>/dev/null
    
    # Extract entropy read information from strace
    echo "Entropy reads from strace:"
    grep -E "(/dev/random|/dev/urandom)" "$WORKDIR/strace_${key_file}.log" | head -5 || echo "No entropy reads found"
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
        return 0
    else
        echo "Keys are DIFFERENT"
        return 1
    fi
}

echo "Step 1: Generate 2 keys normally (should be different)"
generate_key_with_strace "key1_normal" "system entropy" "Normal key generation #1"
generate_key_with_strace "key2_normal" "system entropy" "Normal key generation #2"

echo "Step 2: Compare normal keys"
compare_keys "key1_normal" "key2_normal" "Normal keys comparison"

echo "Step 3: Create controlled entropy environment"
# Create a temporary directory for our isolated environment
ISOLATED_DIR=$(mktemp -d)
trap "rm -rf '$ISOLATED_DIR'" EXIT

# Create controlled entropy sources
echo "Creating controlled entropy sources..."

# High entropy source (random data)
dd if=/dev/urandom of="$ISOLATED_DIR/urandom_high" bs=1024 count=10 2>/dev/null
dd if=/dev/urandom of="$ISOLATED_DIR/random_high" bs=1024 count=10 2>/dev/null

# Low entropy source (zeros)
dd if=/dev/zero of="$ISOLATED_DIR/urandom_low" bs=1024 count=100 2>/dev/null
dd if=/dev/zero of="$ISOLATED_DIR/random_low" bs=1024 count=100 2>/dev/null

echo "Step 4: Generate keys with high entropy (should be different)"
# Test with high entropy using bind mounts
sudo mount --bind "$ISOLATED_DIR/urandom_high" /dev/urandom
sudo mount --bind "$ISOLATED_DIR/random_high" /dev/random

generate_key_with_strace "key1_high_entropy" "high entropy" "High entropy key generation #1"
generate_key_with_strace "key2_high_entropy" "high entropy" "High entropy key generation #2"

echo "Step 5: Compare high entropy keys"
compare_keys "key1_high_entropy" "key2_high_entropy" "High entropy keys comparison"

echo "Step 6: Generate keys with low entropy (should be identical)"
# Replace with low entropy sources
sudo umount /dev/urandom /dev/random
sudo mount --bind "$ISOLATED_DIR/urandom_low" /dev/urandom
sudo mount --bind "$ISOLATED_DIR/random_low" /dev/random

generate_key_with_strace "key1_low_entropy" "low entropy" "Low entropy key generation #1"
generate_key_with_strace "key2_low_entropy" "low entropy" "Low entropy key generation #2"

echo "Step 7: Compare low entropy keys"
compare_keys "key1_low_entropy" "key2_low_entropy" "Low entropy keys comparison"

# Restore original entropy sources
sudo umount /dev/urandom /dev/random

echo "Step 8: Analyze entropy consumption"
echo "--- Entropy Consumption Analysis ---"
for log_file in "$WORKDIR"/strace_*.log; do
    if [[ -f "$log_file" ]]; then
        echo "File: $(basename "$log_file")"
        echo "Total entropy reads: $(grep -c "read.*/dev/urandom\|read.*/dev/random" "$log_file" 2>/dev/null || echo "0")"
        echo "Bytes read from entropy:"
        grep "read.*/dev/urandom\|read.*/dev/random" "$log_file" | head -3 || echo "No entropy reads found"
        echo
    fi
done

echo "=== Experiment Complete ==="
echo "Check $WORKDIR for all generated keys and strace logs"