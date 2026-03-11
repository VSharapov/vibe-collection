# Spotify Ripper - Improvement Plan

## TODO

### 1. Auto-detect duration (#2)
Currently requires manual `-d` flag. Should parse duration from the embed page.

**Target element:**
```html
<span data-testid="progress-timestamp" class="...ProgressTimer_actualProgressTime__kN3ww">24:47</span>
```

**Implementation:**
- Query `[data-testid="progress-timestamp"]` after page load (before clicking play)
- Parse "MM:SS" or "H:MM:SS" format
- Add 1 second buffer
- Done

### 2. Progress indicator (#3)
Show elapsed/remaining time during recording instead of just dots.

Something like:
```
Recording: 05:32 / 24:47 [======>          ] 22%
```

### 3. Smart buffer instead of fixed 10s (#7)
Current: always adds 10 seconds.

**Fix:** Just use +1 second since we're getting exact duration from the timestamp element now. Combines with #1.

---

## Not Fixing (Accepted Limitations)

- **Real-time recording** — Fundamental to the approach
- **No playback health check** — Complex, diminishing returns
- **Debug screenshots** — Useful for troubleshooting
- **No metadata** — Can add via ffmpeg post-process if needed
- **No resume** — Just restart, not worth the complexity
- **Running as root** — Docker container, doesn't matter
- **No verification** — Can manually check file duration after

---

## Answer: Yes, embed page

Final URL pattern:
```
https://open.spotify.com/embed/episode/{EPISODE_ID}?utm_source=generator&theme=0
```

This is the embeddable player widget, not the full Spotify web player.
