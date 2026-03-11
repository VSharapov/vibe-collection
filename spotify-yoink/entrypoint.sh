#!/bin/bash
set -e

# Start Xvfb (virtual display)
echo "Starting Xvfb..."
Xvfb :99 -screen 0 1280x720x24 &
sleep 2

# Start D-Bus 
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# Configure PulseAudio to not require authentication
mkdir -p /root/.config/pulse
cat > /root/.config/pulse/default.pa << 'EOF'
.fail
load-module module-null-sink sink_name=recording sink_properties=device.description=RecordingSink
set-default-sink recording
load-module module-native-protocol-unix auth-anonymous=1
load-module module-native-protocol-tcp auth-anonymous=1
EOF

# Start PulseAudio in user mode
echo "Starting PulseAudio..."
pulseaudio --start --exit-idle-time=-1 --log-level=notice
sleep 2

# Verify PulseAudio setup
echo "PulseAudio sinks:"
pactl list short sinks || true

# Find and export PulseAudio socket
PULSE_SOCKET=$(find /tmp -name "pulse-*" -type d 2>/dev/null | head -1)/native
if [ -S "$PULSE_SOCKET" ]; then
    export PULSE_SERVER="unix:$PULSE_SOCKET"
    echo "PulseAudio socket: $PULSE_SERVER"
else
    export PULSE_SERVER="unix:/root/.config/pulse/native"
    echo "Using default PulseAudio socket: $PULSE_SERVER"
fi

# Run the ripper
exec python /app/rip.py "$@"
