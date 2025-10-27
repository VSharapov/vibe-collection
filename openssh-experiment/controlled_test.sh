#!/bin/bash

set -euo pipefail

echo "=== Controlled OpenSSH Entropy Test ==="
echo

# Create working directory
WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

echo "Working directory: $WORKDIR"
echo

# Function to generate key with controlled entropy
generate_key_with_controlled_entropy() {
    local key_file="$1"
    local entropy_file="$2"
    local description="$3"
    
    echo "--- $description ---"
    echo "Using entropy file: $entropy_file"
    
    # Run ssh-keygen with our entropy interceptor
    CONTROLLED_ENTROPY_FILE="$entropy_file" \
    LD_PRELOAD="./entropy_intercept.so" \
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
generate_key_with_controlled_entropy "key1_normal" "/dev/urandom" "Normal key generation #1"
generate_key_with_controlled_entropy "key2_normal" "/dev/urandom" "Normal key generation #2"

echo "Step 2: Compare normal keys"
compare_keys "key1_normal" "key2_normal" "Normal keys comparison"

echo "Step 3: Create controlled entropy sources"
# High entropy source (random data)
dd if=/dev/urandom of="$WORKDIR/high_entropy" bs=1024 count=10 2>/dev/null

# Low entropy source (zeros)
dd if=/dev/zero of="$WORKDIR/low_entropy" bs=1024 count=100 2>/dev/null

# Medium entropy source (pattern)
yes "ENTROPY" | head -c 10240 > "$WORKDIR/medium_entropy"

echo "Step 4: Generate keys with high entropy (should be different)"
generate_key_with_controlled_entropy "key1_high" "$WORKDIR/high_entropy" "High entropy key generation #1"
generate_key_with_controlled_entropy "key2_high" "$WORKDIR/high_entropy" "High entropy key generation #2"

echo "Step 5: Compare high entropy keys"
compare_keys "key1_high" "key2_high" "High entropy keys comparison"

echo "Step 6: Generate keys with low entropy (should be identical)"
generate_key_with_controlled_entropy "key1_low" "$WORKDIR/low_entropy" "Low entropy key generation #1"
generate_key_with_controlled_entropy "key2_low" "$WORKDIR/low_entropy" "Low entropy key generation #2"

echo "Step 7: Compare low entropy keys"
compare_keys "key1_low" "key2_low" "Low entropy keys comparison"

echo "Step 8: Generate keys with medium entropy (pattern)"
generate_key_with_controlled_entropy "key1_medium" "$WORKDIR/medium_entropy" "Medium entropy key generation #1"
generate_key_with_controlled_entropy "key2_medium" "$WORKDIR/medium_entropy" "Medium entropy key generation #2"

echo "Step 9: Compare medium entropy keys"
compare_keys "key1_medium" "key2_medium" "Medium entropy keys comparison"

echo "Step 10: Analyze entropy consumption"
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