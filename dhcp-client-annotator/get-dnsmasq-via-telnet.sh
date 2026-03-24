#!/usr/bin/env bash
# Fetch dnsmasq leases via telnetd on port 19999 (~25x faster than SSH)
# See get-dnsmasq-via-telnet.README.md for router setup
set -euo pipefail
ROUTER_HOST="${ROUTER_HOST:-router.asus.com}"
echo "" | nc -w 2 "$ROUTER_HOST" 19999 | tr -d '\377\375\373\001\037\003\r' | grep .
# Mister Clopus says:
#  ┌───────┬──────┬───────────────────────────────────────┐
#  │ Octal │ Hex  │ Meaning                               │
#  ├───────┼──────┼───────────────────────────────────────┤
#  │ \377  │ 0xFF │ IAC (Interpret As Command)            │
#  │ \375  │ 0xFD │ DO (request other side enable option) │
#  │ \373  │ 0xFB │ WILL (agree to enable option)         │
#  │ \001  │ 0x01 │ ECHO option                           │
#  │ \037  │ 0x1F │ NAWS (window size) option             │
#  │ \003  │ 0x03 │ Suppress Go Ahead option              │
#  │  \r   │ 0x0D │ CR (telnet uses CRLF line endings)    │
#  └───────┴──────┴───────────────────────────────────────┘
# grep . filters the empty first line left after stripping
# When you connect, telnetd sends:
# ... IAC DO ECHO, IAC DO NAWS, IAC WILL ECHO, IAC WILL SUPPRESS-GO-AHEAD
# ... basically asking "do you want echo? what's your terminal size?"
