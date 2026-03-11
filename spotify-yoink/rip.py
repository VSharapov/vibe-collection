#!/usr/bin/env python3
"""
Spotify Episode Ripper
Uses Playwright + Chrome (with Widevine) + PulseAudio to capture audio
"""

import argparse
import subprocess
import time
import os
import sys
import signal
import re
from pathlib import Path


def setup_pulseaudio():
    """PulseAudio is started by entrypoint.sh, just return the monitor source"""
    return "recording.monitor"


def start_recording(output_file, monitor_source):
    """Start ffmpeg recording from PulseAudio monitor"""
    cmd = [
        "ffmpeg", "-y",
        "-f", "pulse",
        "-i", monitor_source,
        "-ac", "2",
        "-ar", "44100",
        "-b:a", "192k",
        output_file
    ]
    print(f"Starting recording to {output_file}")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return proc


def stop_recording(proc):
    """Stop ffmpeg recording gracefully"""
    proc.send_signal(signal.SIGINT)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    print("Recording stopped")


def parse_duration_string(text):
    """Parse duration string like '24:47' or '2:52:06' to seconds"""
    text = text.strip().lstrip('-')
    parts = text.split(':')
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
        elif len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
    except ValueError:
        pass
    return None


def get_episode_duration(page):
    """Extract episode duration from progress-timestamp element"""
    try:
        # Target: <span data-testid="progress-timestamp">24:47</span>
        timestamp = page.locator('[data-testid="progress-timestamp"]').first
        if timestamp.is_visible(timeout=3000):
            text = timestamp.text_content(timeout=2000)
            duration = parse_duration_string(text)
            if duration and duration > 60:
                return duration
    except Exception as e:
        print(f"Could not get duration from progress-timestamp: {e}")
    
    # Fallback: scan all text for duration patterns
    try:
        duration = page.evaluate("""() => {
            const timeEls = document.querySelectorAll('span, div');
            for (const el of timeEls) {
                const text = el.textContent.trim();
                const match = text.match(/^-?(\\d{1,2}):(\\d{2})(?::(\\d{2}))?$/);
                if (match) {
                    let hours = 0, mins = 0, secs = 0;
                    if (match[3]) {
                        hours = parseInt(match[1]);
                        mins = parseInt(match[2]);
                        secs = parseInt(match[3]);
                    } else {
                        mins = parseInt(match[1]);
                        secs = parseInt(match[2]);
                    }
                    const total = hours * 3600 + mins * 60 + secs;
                    if (total > 60) return total;
                }
            }
            return null;
        }""")
        if duration:
            return duration
    except Exception as e:
        print(f"Fallback duration detection failed: {e}")
    return None


def format_time(seconds):
    """Format seconds as H:MM:SS or MM:SS"""
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    if h > 0:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def rip_episode(url, output_file, manual_duration=0):
    """Main function to rip a Spotify episode"""
    from playwright.sync_api import sync_playwright
    
    # Setup audio capture
    monitor_source = setup_pulseaudio()
    
    # Extract episode ID from URL
    match = re.search(r'episode/([a-zA-Z0-9]+)', url)
    if not match:
        print(f"Error: Could not extract episode ID from URL: {url}")
        sys.exit(1)
    
    episode_id = match.group(1)
    embed_url = f"https://open.spotify.com/embed/episode/{episode_id}?utm_source=generator&theme=0"
    
    print(f"Episode ID: {episode_id}")
    print(f"Embed URL: {embed_url}")
    
    with sync_playwright() as p:
        # Launch real Chrome (not Chromium) for Widevine support
        browser = p.chromium.launch(
            channel="chrome",
            headless=False,  # Widevine often needs headed mode
            args=[
                "--autoplay-policy=no-user-gesture-required",
                "--disable-features=PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies",
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--use-fake-ui-for-media-stream",
                "--disable-gpu",
                "--alsa-output-device=pulse",
            ]
        )
        
        context = browser.new_context(
            viewport={"width": 400, "height": 200},
            user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
        
        page = context.new_page()
        
        # Capture console messages for debugging
        page.on("console", lambda msg: print(f"BROWSER: [{msg.type}] {msg.text}"))
        page.on("pageerror", lambda err: print(f"PAGE ERROR: {err}"))
        
        print(f"Navigating to {embed_url}")
        page.goto(embed_url, wait_until="networkidle")
        time.sleep(3)
        
        # Take screenshot for debugging
        page.screenshot(path="/output/debug_screenshot.png")
        print("Saved debug screenshot to /output/debug_screenshot.png")
        
        # Determine duration
        if manual_duration > 0:
            duration = manual_duration
            print(f"Using manual duration: {format_time(duration)}")
        else:
            duration = get_episode_duration(page)
            if duration:
                print(f"Auto-detected duration: {format_time(duration)} (+1s buffer)")
            else:
                print("Could not determine duration, will record until manually stopped")
        
        # Start recording BEFORE clicking play
        recorder = start_recording(output_file, monitor_source)
        time.sleep(1)
        
        # Click the play button - try multiple selectors
        clicked = False
        selectors = [
            'button[data-testid="play-button"]',
            'button[aria-label*="Play"]', 
            'button[aria-label*="play"]',
            '[role="button"][aria-label*="Play"]',
            'div[role="button"]',
            'button.Button-sc-1dqy6lx-0',  # Spotify's button class
            'button',  # Last resort - first button
        ]
        
        for selector in selectors:
            try:
                btn = page.locator(selector).first
                if btn.is_visible(timeout=2000):
                    btn.click(timeout=5000)
                    print(f"Clicked button with selector: {selector}")
                    clicked = True
                    break
            except Exception as e:
                continue
        
        if not clicked:
            print("Could not find play button, trying to click at coordinates")
            # The play button appears to be on the right side of the embed
            page.mouse.click(350, 100)  # Approximate location of play button
        
        time.sleep(3)
        
        # Screenshot after clicking
        page.screenshot(path="/output/debug_after_click.png")
        print("Saved post-click screenshot")
        
        # Check playback status via JavaScript
        playback_status = page.evaluate("""() => {
            // Check standard media elements
            const audios = document.querySelectorAll('audio');
            const videos = document.querySelectorAll('video');
            
            // Check for Web Audio API context
            let audioContextActive = false;
            if (window.AudioContext || window.webkitAudioContext) {
                audioContextActive = true;
            }
            
            // Look for play button state changes
            const playButtons = document.querySelectorAll('[data-testid="play-button"], [data-testid="pause-button"], button[aria-label*="Pause"]');
            const pauseButtons = document.querySelectorAll('[data-testid="pause-button"], button[aria-label*="Pause"]');
            
            // Check for any progress indicators
            const progressBars = document.querySelectorAll('[role="progressbar"], [data-testid="playback-progressbar"]');
            
            return {
                audioCount: audios.length,
                videoCount: videos.length,
                playButtonCount: playButtons.length,
                pauseButtonCount: pauseButtons.length,
                progressBarCount: progressBars.length,
                audioContextAvailable: audioContextActive,
                pageTitle: document.title
            };
        }""")
        print(f"Playback status: {playback_status}")
        
        # Check PulseAudio status
        result = subprocess.run(["pactl", "list", "short", "sinks"], capture_output=True, text=True)
        print(f"Sink status: {result.stdout.strip()}")
        
        result = subprocess.run(["pactl", "list", "short", "sink-inputs"], capture_output=True, text=True)
        print(f"Sink inputs: {result.stdout.strip() if result.stdout.strip() else '(none)'}")
        
        # Recording loop with progress
        print("Recording... Press Ctrl+C to stop early")
        
        if duration:
            wait_time = duration + 1  # +1 second buffer
            print(f"Total duration: {format_time(wait_time)}")
            start_time = time.time()
            try:
                while True:
                    elapsed = int(time.time() - start_time)
                    remaining = wait_time - elapsed
                    if remaining <= 0:
                        break
                    pct = min(100, int(elapsed * 100 / wait_time))
                    bar_len = 30
                    filled = int(bar_len * elapsed / wait_time)
                    bar = '=' * filled + '>' + ' ' * (bar_len - filled - 1)
                    print(f"\r  {format_time(elapsed)} / {format_time(wait_time)} [{bar}] {pct}%  ", end="", flush=True)
                    time.sleep(1)
                print()  # newline after progress
            except KeyboardInterrupt:
                print("\nStopping early...")
        else:
            # No duration - show elapsed time only
            start_time = time.time()
            try:
                while True:
                    elapsed = int(time.time() - start_time)
                    print(f"\r  Recording: {format_time(elapsed)} (Ctrl+C to stop)  ", end="", flush=True)
                    time.sleep(1)
            except KeyboardInterrupt:
                print("\nStopping...")
        
        stop_recording(recorder)
        browser.close()
    
    print(f"\nOutput saved to: {output_file}")


def main():
    parser = argparse.ArgumentParser(description="Rip Spotify episodes via browser playback")
    parser.add_argument("url", help="Spotify episode URL")
    parser.add_argument("-o", "--output", default="/output/episode.mp3", 
                        help="Output file path (default: /output/episode.mp3)")
    parser.add_argument("-d", "--duration", type=int, default=0,
                        help="Duration in seconds (0 = auto-detect or infinite)")
    
    args = parser.parse_args()
    rip_episode(args.url, args.output, manual_duration=args.duration)


if __name__ == "__main__":
    main()
