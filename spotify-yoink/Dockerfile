FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    pulseaudio \
    pulseaudio-utils \
    ffmpeg \
    xvfb \
    dbus \
    dbus-x11 \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libasound2-plugins \
    alsa-utils \
    && rm -rf /var/lib/apt/lists/*

# Configure ALSA to use PulseAudio
RUN echo "pcm.!default pulse\nctl.!default pulse" > /etc/asound.conf

# Install Google Chrome (has Widevine CDM built-in)
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install playwright

WORKDIR /app

# Copy scripts
COPY rip.py /app/rip.py
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Create output directory
RUN mkdir -p /output

# PulseAudio config
RUN mkdir -p /root/.config/pulse
COPY pulse-client.conf /root/.config/pulse/client.conf

ENV DISPLAY=:99

ENTRYPOINT ["/app/entrypoint.sh"]
