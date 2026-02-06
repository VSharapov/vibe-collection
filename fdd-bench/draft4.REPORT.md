# draft4 Report

## Change

Added `sync` before `echo 3 > /proc/sys/vm/drop_caches` in `drop-caches()`. Ensures dirty pages are flushed to disk before the cache drop, so the kernel isn't racing to write back while we're trying to evict.
