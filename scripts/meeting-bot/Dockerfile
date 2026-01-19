FROM mcr.microsoft.com/playwright/python:v1.49.0-noble

# Install PulseAudio and audio tools
RUN apt-get update && apt-get install -y \
    xvfb \
    pulseaudio \
    pulseaudio-utils \
    ffmpeg \
    dbus-x11 \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Download Vosk model for streaming ASR
RUN mkdir -p /app/models && \
    cd /app/models && \
    wget -q https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip && \
    unzip -q vosk-model-small-en-us-0.15.zip && \
    rm vosk-model-small-en-us-0.15.zip

# Create non-root user with audio group membership
RUN useradd -m -s /bin/bash -G audio botuser

WORKDIR /app

# Create PulseAudio config for non-root user
RUN mkdir -p /home/botuser/.config/pulse && \
    echo "autospawn = no" > /home/botuser/.config/pulse/client.conf && \
    echo "daemon-binary = /bin/true" >> /home/botuser/.config/pulse/client.conf && \
    echo "enable-shm = false" >> /home/botuser/.config/pulse/client.conf && \
    chown -R botuser:botuser /home/botuser

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Playwright browsers (as root, then fix permissions)
RUN playwright install chromium && \
    chmod -R 755 /ms-playwright

# Copy application
COPY --chown=botuser:botuser . .

# Make entrypoint executable
RUN chmod +x entrypoint.sh

# Create output directory with correct permissions
RUN mkdir -p /app/output && chown -R botuser:botuser /app

# Switch to non-root user
USER botuser

# Environment
ENV PYTHONUNBUFFERED=1
ENV DISPLAY=:99
ENV HOME=/home/botuser
ENV XDG_RUNTIME_DIR=/tmp/runtime-botuser
ENV VOSK_MODEL_PATH=/app/models/vosk-model-small-en-us-0.15
ENV OLLAMA_URL=http://ollama:11434
ENV TRIGGER_MODEL=phi3:mini

# Entrypoint starts audio stack then bot
ENTRYPOINT ["/app/entrypoint.sh"]
