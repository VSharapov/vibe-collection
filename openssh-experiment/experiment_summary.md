# OpenSSH Entropy Source Experiment - Summary

## What We Discovered

### 1. OpenSSH uses `getrandom` system call
- `ssh-keygen` uses the `getrandom` system call (not `/dev/random` or `/dev/urandom` files)
- This is the modern Linux way to get entropy
- `strace` shows 5 `getrandom` calls per key generation:
  - 1 call for 8 bytes (GRND_NONBLOCK)
  - 2 calls for 48 bytes each
  - 1 call for 32 bytes  
  - 1 call for 4 bytes

### 2. Entropy consumption is consistent
- All key generations consume exactly the same amount of entropy
- Total: 8 + 48 + 48 + 32 + 4 = 140 bytes per key
- This is independent of the quality of entropy source

### 3. Key generation is deterministic with same entropy
- When using the same entropy source, keys should be identical
- However, our `LD_PRELOAD` interceptor didn't work as expected
- This suggests `ssh-keygen` might be using additional entropy sources

## Technical Details

### System Calls Used
```bash
getrandom(buf, 8, GRND_NONBLOCK) = 8
getrandom(buf, 48, 0) = 48  
getrandom(buf, 48, 0) = 48
getrandom(buf, 32, 0) = 32
getrandom(buf, 4, 0) = 4
```

### Entropy Interceptor Attempt
- Created `entropy_intercept.c` to intercept `getrandom` calls
- Used `LD_PRELOAD` to load the interceptor
- Interceptor should redirect to controlled entropy files
- However, interceptor wasn't called (no debug output)

## Possible Issues with Interceptor

1. **Function signature mismatch**: `getrandom` might have different signature
2. **Static linking**: `ssh-keygen` might be statically linked
3. **Different mechanism**: `ssh-keygen` might use `syscall()` directly
4. **Library version**: Different glibc version might have different symbols

## Next Steps

To make this experiment work properly, we would need to:

1. **Fix the interceptor**: Ensure it properly intercepts `getrandom` calls
2. **Test with different approaches**: Try intercepting at different levels
3. **Use different tools**: Maybe try with `openssl` instead of `ssh-keygen`
4. **System-level approach**: Use `ptrace` or other system-level debugging

## Current Status

✅ **Working**: Basic entropy monitoring with `strace`
✅ **Working**: Key generation and comparison
❌ **Not working**: Controlled entropy source injection
❌ **Not working**: Deterministic key generation

The experiment demonstrates that OpenSSH uses a consistent amount of entropy (140 bytes) per key generation, but we couldn't successfully control the entropy source to make key generation deterministic.