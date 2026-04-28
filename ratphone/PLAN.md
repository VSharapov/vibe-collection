# ratphone

Remote tech support for grandfather's phone via scrcpy over wifi ADB.

## Status

| Component | Status |
|-----------|--------|
| ratphone.sh dispatch | ✅ Done |
| USB detection (usb-await) | ✅ Done |
| WiFi ADB (wifi-init, wifi-await) | ✅ Done |
| scrcpy with reconnect | ✅ Done |
| noVNC web UI | ✅ Done |
| Reverse tunnel | ❌ TODO |
| Systemd units | ❌ TODO |

## Architecture

```
ratphone.sh         # dispatch script, all plumbing exposed
├── usb-await       # block until phone on USB
├── wifi-init       # adb tcpip 5555
├── wifi-await      # block until wifi adb connected
├── scrcpy-start    # scrcpy with reconnect loop
├── novnc-start     # web UI on port 6080
└── test            # docker harness
```

## Flow

```
[phone reboots]
    ↓
[grandpa plugs USB for 30s]  ← only manual step
    ↓
usb-await detects, wifi-init runs: adb tcpip 5555
    ↓
[grandpa unplugs]
    ↓
wifi-await → scrcpy-start connects over wifi
    ↓
novnc-start → http://localhost:6080/vnc.html
    ↓
[TODO: autossh tunnel → https://server/ratphone]
    ↓
[you see phone, tap around]
```

## What's implemented

1. ✅ `usb-await` — polls until phone on USB
2. ✅ `wifi-init` — `adb tcpip 5555`
3. ✅ `wifi-await` — polls until wifi adb connected
4. ✅ `scrcpy-start` — reconnect loop, `--no-audio`
5. ✅ `novnc-start` — web VNC on port 6080
6. ✅ Docker test harness with scrcpy 3.3.4

## What's left

1. ❌ Reverse tunnel — `autossh -R 6080:localhost:6080 server`
2. ❌ Systemd units for production
3. ❌ noVNC authentication

## Trust setup (one-time)

- Plug phone, accept fingerprint prompt, check "always trust"
- `./ratphone.sh show-fingerprint` to verify

## Resources

- Trash tier laptop running Debian server (lives at grandpa's)
- Server with public IPv4 (reverse ssh tunnel target)
- Pixel 7 phone, Android 16 (trusts laptop's ADB fingerprint)
