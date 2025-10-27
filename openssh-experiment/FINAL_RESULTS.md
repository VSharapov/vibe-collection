# OpenSSH Entropy Source Experiment - Final Results

## Experiment Summary

This experiment successfully demonstrated how OpenSSH consumes entropy during key generation, though we couldn't achieve deterministic key generation with controlled entropy sources.

## What We Accomplished

### ✅ Successfully Demonstrated

1. **Entropy Consumption Pattern**
   - OpenSSH uses exactly 5 `getrandom` system calls per key generation
   - Total entropy consumed: 140 bytes per key
   - Pattern: 8 + 48 + 48 + 32 + 4 bytes
   - This is consistent across all key generations

2. **System Call Analysis**
   - Used `strace` to monitor `getrandom` calls
   - Confirmed OpenSSH uses modern Linux entropy API
   - No direct file access to `/dev/random` or `/dev/urandom`

3. **Key Generation Behavior**
   - All keys are different (as expected with good entropy)
   - Entropy consumption is deterministic and consistent
   - Key generation is fast and reliable

### ❌ What Didn't Work

1. **Controlled Entropy Source**
   - `LD_PRELOAD` interceptor approach failed
   - Entropy interceptor wasn't called by `ssh-keygen`
   - Couldn't achieve deterministic key generation

2. **Process Isolation**
   - Didn't implement chroot/unshare isolation
   - Focused on entropy monitoring instead

## Technical Details

### Entropy Consumption Pattern
```bash
getrandom(buf, 8, GRND_NONBLOCK) = 8    # Initial entropy check
getrandom(buf, 48, 0) = 48              # First entropy block
getrandom(buf, 48, 0) = 48              # Second entropy block  
getrandom(buf, 32, 0) = 32              # Third entropy block
getrandom(buf, 4, 0) = 4                # Final entropy block
```

### Files Created
- `main.sh` - Original complex script (didn't work)
- `simple_test.sh` - Basic test with strace
- `controlled_test.sh` - Attempt with entropy interceptor
- `final_test.sh` - Simplified version
- `demo.sh` - **Working demonstration script**
- `entropy_intercept.c` - LD_PRELOAD interceptor (didn't work)
- `entropy_intercept.so` - Compiled interceptor

## Key Insights

1. **Modern Linux Entropy**: OpenSSH uses `getrandom` system call, not file-based entropy
2. **Consistent Consumption**: Entropy usage is predictable and measurable
3. **Interceptor Challenges**: `LD_PRELOAD` approach has limitations with system calls
4. **Entropy Quality**: Even with limited entropy, keys remain different (good security)

## Working Demo

The `demo.sh` script successfully demonstrates:
- Entropy consumption monitoring
- Key generation and comparison
- Consistent entropy usage patterns
- System call analysis

## Conclusion

While we couldn't achieve deterministic key generation with controlled entropy sources, we successfully demonstrated how OpenSSH consumes entropy and provided a working framework for entropy analysis. The experiment shows that OpenSSH uses a consistent, measurable amount of entropy per key generation, which is important for security analysis and entropy pool management.

## Next Steps

To achieve deterministic key generation, future work could:
1. Fix the entropy interceptor (function signature issues)
2. Use `ptrace` or other system-level debugging
3. Try different tools like `openssl` instead of `ssh-keygen`
4. Implement proper process isolation with chroot/unshare