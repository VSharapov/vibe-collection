# Notes

## Current State (2026-04-15)

All core functionality implemented and tested:
- `wifi-await` connects to phone over wifi adb
- `scrcpy-start` with automatic reconnect loop
- `novnc-start` for web-based access (no VNC client needed)
- Dockerfile downloads scrcpy 3.3.4 from GitHub

## Critical: scrcpy version

- Ubuntu package scrcpy 1.25 is **too old** for Android 16
- Need **scrcpy 3.3.4+** for Android 16 compatibility
- Dockerfile now downloads from GitHub releases

## Container setup

- `DEBIAN_FRONTEND=noninteractive` to avoid tzdata prompt
- Port 5900: VNC (x11vnc)
- Port 6080: noVNC web UI
- `--no-audio` required (no audio device in container)
- scrcpy installed to `/opt/scrcpy-linux-x86_64-v3.3.4/`

## Implemented Commands

```bash
# Config
./ratphone.sh config get              # show all
./ratphone.sh config get KEY          # get one
./ratphone.sh config set KEY VAL      # set

# USB workflow
./ratphone.sh usb-check               # is phone on USB?
./ratphone.sh usb-await               # block until USB

# WiFi workflow  
./ratphone.sh wifi-init               # adb tcpip
./ratphone.sh wifi-connect            # adb connect
./ratphone.sh wifi-check              # is wifi adb up?
./ratphone.sh wifi-await              # block until wifi

# Display
./ratphone.sh xvfb-start              # virtual framebuffer
./ratphone.sh vnc-start               # xvfb + x11vnc
./ratphone.sh novnc-start             # + novnc web (port 6080)
./ratphone.sh scrcpy-start            # scrcpy with reconnect

# Testing
./ratphone.sh test 1                  # docker container
./ratphone.sh test 2                  # e2e inside container
```

## TODO

- [ ] Reverse tunnel (autossh to public server)
- [ ] Systemd units for trash laptop deployment
- [ ] noVNC authentication
- [ ] Phone reboot detection
