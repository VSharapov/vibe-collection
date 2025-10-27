# TODO

## Completed
- [x] Basic script structure
- [x] Normal key generation with strace
- [x] Key comparison function
- [x] Controlled entropy source creation
- [x] Entropy consumption analysis
- [x] Working demo script
- [x] Entropy interceptor attempt (LD_PRELOAD)
- [x] System call analysis with strace

## Partially Working
- [x] Entropy monitoring (strace works perfectly)
- [x] Key generation and comparison
- [x] Entropy consumption measurement (140 bytes per key)

## Not Working
- [ ] Controlled entropy source injection (LD_PRELOAD approach failed)
- [ ] Deterministic key generation with same entropy
- [ ] Process isolation with chroot/unshare

## Key Findings
- OpenSSH uses `getrandom` system call (not `/dev/random` files)
- Consistent entropy consumption: 5 calls, 140 bytes total per key
- All keys are different even with controlled entropy (interceptor didn't work)
- Entropy pattern: 8 + 48 + 48 + 32 + 4 bytes

## Future improvements
- [ ] Fix entropy interceptor (function signature issues)
- [ ] Try different interception methods (ptrace, etc.)
- [ ] Test with different key types (RSA, ECDSA)
- [ ] Use different tools (openssl instead of ssh-keygen)