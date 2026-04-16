# Notes

## Working

- `wifi-await` connects to phone over wifi adb
- `adb -s Natanz-Enrichment-Computer:5555 shell echo ok` works
- Xvfb + x11vnc + scrcpy 3.3.4 works!
- VNC on localhost:5900 shows phone screen

## Critical: scrcpy version

- Ubuntu package scrcpy 1.25 is **too old** for Android 16
- Need **scrcpy 3.3.4+** for Android 16 compatibility
- Must download from GitHub releases, not apt

```bash
curl -sL https://github.com/Genymobile/scrcpy/releases/download/v3.3.4/scrcpy-linux-x86_64-v3.3.4.tar.gz | tar xz
```

## Container quirks

- `DEBIAN_FRONTEND=noninteractive` to avoid tzdata prompt
- `-p 5900:5900` for VNC access
- `--no-audio` required (no audio device in container)
- Need curl to download scrcpy (not in base image)

## Full working workflow

```bash
# in container
Xvfb :99 -screen 0 1280x720x24 &
x11vnc -display :99 -forever -nopw -bg
./ratphone.sh wifi-await
DISPLAY=:99 ./scrcpy-linux-x86_64-v3.3.4/scrcpy -s Natanz-Enrichment-Computer:5555 --no-audio &
# then VNC to localhost:5900
```

## TODO

- [ ] Download scrcpy 3.3.4 in Dockerfile (not apt scrcpy)
- [ ] Add curl to Dockerfile
- [ ] Create `scrcpy-start` command (Xvfb + x11vnc + scrcpy)
- [ ] Create `vnc-start` command
- [ ] Consider noVNC for web access (no VNC client needed)
- [ ] Handle scrcpy reconnect on disconnect
- [ ] Reverse tunnel for remote access

## Commands

```bash
./ratphone.sh wifi-await          # connect to phone
./ratphone.sh config get          # show config
./ratphone.sh show-fingerprint    # for trust setup
```
