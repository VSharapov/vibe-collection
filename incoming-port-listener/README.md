# Incoming Port Tester

A tool to test which TCP/UDP ports are accessible from the internet, helping you determine if your ISP is blocking incoming connections on common ports.

## Overview

Home internet ISPs often block common ports like HTTP (80) and SMTP (25), dropping incoming connections. This tool helps you identify which ports are actually accessible by testing bidirectional connectivity.

**Note:** This tool should be run on your gateway/router, or you should have forwarded a port range on your gateway to the machine running this tool.

## Installation

The tool is a standalone Python 3 script. No dependencies required (uses Python's standard library).

```bash
chmod +x incoming-port-tester
```

## Basic Usage

```bash
./incoming-port-tester
```

This will test ports 1-16384 with default settings.

## Command-Line Options

### Test Configuration

- `--ports RANGE` - Port range to test (default: `1-16384`)
  - Examples: `--ports 80-443`, `--ports 8080`
- `--target IP` - Target IP address to test (default: `127.0.0.1`)
  - **Important:** Use your external IP address to test real connectivity
  - The tool will warn if you're testing against localhost
- `--timeout SECONDS` - Timeout in seconds (default: `3`)
- `--tcp-only` - Test TCP ports only
- `--udp-only` - Test UDP ports only

### Output Options

- `--no-group` - Disable grouping consecutive identical results
- `--always-print-protocol` - Print TCP/UDP even if only one protocol was specified
- `--error-codes` - Print numeric error codes instead of status words
- `--netcat-path PATH` - Path to netcat (kept for compatibility, not used)

### Internal Mode

- `--test-single-port PORT` - Test a single port and exit with error code (no output)
  - Used internally by the main script
  - Exits with status code: 0=PASS, 1=FAIL, 2=SEND, 4=SUDO, 8=USED, 16=RECV, 64=ERRO

## Examples

### Test common web ports

```bash
./incoming-port-tester --ports 80-443 --tcp-only
```

### Test with external IP

```bash
./incoming-port-tester --target 203.0.113.1 --ports 1-1000
```

### Test specific port range without grouping

```bash
./incoming-port-tester --ports 8080-8090 --no-group
```

### Test UDP only

```bash
./incoming-port-tester --udp-only --ports 53-53
```

## Output Format

The tool groups consecutive ports with identical results:

```
[PASS] TCP 8080-8085
[FAIL] TCP 25
[PASS] TCP 443
```

With `--always-print-protocol` or when testing both TCP and UDP:

```
[PASS] TCP/UDP 8080-8082
[FAIL] TCP 25
```

## Exit Codes

When using `--test-single-port`, the tool exits with these codes:

- `0` - **PASS** - Server started, client connected, bidirectional communication worked
- `1` - **FAIL** - Client could not establish connection in time
- `2` - **SEND** - Client's message failed to reach server in time
- `4` - **SUDO** - Server failed to start due to privilege issues (ports < 1024)
- `8` - **USED** - Server failed to start because port is already in use
- `16` - **RECV** - Server's message didn't reach client in time
- `64` - **ERRO** - Other error

Multiple errors can be combined (e.g., `82 = 64 + 16 + 2`).

## How It Works

1. For each port, the tool starts a server listening on `0.0.0.0` (all interfaces)
2. A client connects to the specified `--target` IP address
3. The client sends a test message: `"client -> server\n"`
4. The server receives and verifies the message
5. The server sends a response: `"server -> client\n"`
6. The client receives and verifies the response
7. Results are grouped and displayed

For UDP, the process is similar but uses connectionless UDP sockets.

## Use Cases

- **ISP Port Blocking Detection**: Identify which ports your ISP is blocking
- **Firewall Testing**: Verify your firewall rules are working correctly
- **Port Forwarding Verification**: Confirm port forwarding on your router is configured properly
- **Network Troubleshooting**: Diagnose connectivity issues

## Warnings

When testing against localhost (`127.0.0.1` or `localhost`), the tool will display:

```
WARNING: Target is localhost. All tests should succeed.
WARNING: To test external connectivity, use your external IP address with --target
```

This is expected - localhost tests verify the tool works, but won't tell you about ISP blocking. Use your external IP address for real-world testing.

## Notes

- The tool uses Python's `socket` library directly (no netcat dependency)
- Timeout resets after each step (connection establishment, send, receive)
- For ports below 1024, you may need to run with `sudo` (will show SUDO error code)
- UDP tests won't fail on "connection establish" - only on message delivery tests

## License

See LICENSE file (if applicable).
