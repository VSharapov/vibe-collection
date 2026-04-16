# ratphone

Remote tech support for grandfather's phone via scrcpy over wifi ADB.

## Components (on trash laptop at grandpa's house)

```
ratphone.sh         # dispatch script, all plumbing exposed
autoadb             # poll/udev: init wifi adb when USB appears
scrcpy-daemon       # systemd service, reconnects to phone:5555
autossh             # reverse tunnel laptop:8080 → server:XXXXX
guacamole/noVNC     # web wrapper for scrcpy window
```

## Flow

```
[phone reboots]
    ↓
[grandpa plugs USB for 30s]  ← only manual step
    ↓
autoadb detects USB, runs: adb tcpip 5555
    ↓
[grandpa unplugs]
    ↓
scrcpy connects to phone:5555 over wifi
    ↓
autossh keeps tunnel alive → you hit https://server/guac
    ↓
[you see phone, tap around]
```

## What needs building

1. `autoadb` — udev rule or polling loop; on USB attach → `adb tcpip 5555` → `adb connect $IP:5555`
2. scrcpy systemd unit — restarts on failure, connects wifi ADB
3. reverse tunnel — `autossh -R 8080:localhost:8080 server`
4. web exposure — guacamole VNC→scrcpy window, or noVNC, or scrcpy's `--web` (if exists)

## Trust setup (one-time)

- Plug phone, accept fingerprint prompt, check "always trust"

## Resources

- Trash tier laptop running Debian server (lives at grandpa's)
- Server with public IPv4 (reverse ssh tunnel target)
- Pixel 7 phone (trusts laptop's ADB fingerprint)
