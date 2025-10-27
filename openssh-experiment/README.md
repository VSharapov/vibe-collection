# OpenSSH Entropy Source Experiment

This experiment tests how `ssh-keygen` behaves with different entropy sources and measures entropy consumption.

## What it does

1. **Normal keys**: Generates 2 keys with system entropy (should be different)
2. **High entropy keys**: Generates 2 keys with controlled high entropy (should be different)  
3. **Low entropy keys**: Generates 2 keys with controlled low entropy (should be identical)

## Key findings expected

- Normal and high entropy keys should be different
- Low entropy keys should be identical (deterministic)
- `strace` will show how much entropy each generation consumes
- Low entropy sources may cause `ssh-keygen` to read more data

## Usage

```bash
./main.sh
```

## Files

- `main.sh` - Main experiment script
- `README.md` - This file
- `TODO.md` - Development notes

## Technical details

Uses `strace` to monitor entropy reads and `dd` to create controlled entropy sources. Tests both `/dev/random` and `/dev/urandom` behavior.