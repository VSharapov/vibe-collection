#define _GNU_SOURCE
#include <sys/random.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/syscall.h>

// Intercept getrandom calls and redirect to our controlled entropy source
ssize_t getrandom(void *buf, size_t buflen, unsigned int flags) {
    static int entropy_fd = -1;
    static int entropy_offset = 0;
    
    // Open our controlled entropy source on first call
    if (entropy_fd == -1) {
        const char *entropy_file = getenv("CONTROLLED_ENTROPY_FILE");
        if (entropy_file) {
            entropy_fd = open(entropy_file, O_RDONLY);
            if (entropy_fd == -1) {
                // Fall back to system entropy if our file doesn't exist
                return syscall(__NR_getrandom, buf, buflen, flags);
            }
            // Debug: write to stderr that we're using controlled entropy
            write(2, "Using controlled entropy\n", 25);
        } else {
            // No controlled entropy file specified, use system
            return syscall(__NR_getrandom, buf, buflen, flags);
        }
    }
    
    // Read from our controlled entropy source
    ssize_t bytes_read = read(entropy_fd, buf, buflen);
    if (bytes_read == -1) {
        // If we can't read from our file, fall back to system
        return syscall(__NR_getrandom, buf, buflen, flags);
    }
    
    // If we've read all available data, loop back to beginning
    if (bytes_read < buflen) {
        lseek(entropy_fd, 0, SEEK_SET);
        entropy_offset = 0;
        
        // Read remaining bytes
        ssize_t remaining = buflen - bytes_read;
        ssize_t additional = read(entropy_fd, (char*)buf + bytes_read, remaining);
        if (additional > 0) {
            bytes_read += additional;
        }
    }
    
    return bytes_read;
}