# Browser Audio Capture in Headless Docker Containers

## Research Report: Best Practices for Meeting Recording Bots

**Date**: 2026-01-16
**Classification**: Type C Analysis
**Intensity**: Standard

---

## Executive Summary

Capturing browser audio in headless Docker containers for meeting recording requires solving two core challenges: (1) running a virtual audio system without physical hardware, and (2) routing browser audio output to a recording pipeline. After analyzing 15+ open-source implementations and official documentation, this report ranks five proven approaches by reliability, complexity, and compatibility.

**Recommended Solution**: PulseAudio with virtual null-sink running as a non-root user, combined with ffmpeg recording from the monitor source. This approach has the most production deployments and best documentation.

---

## Ranked Solutions

### 1. PulseAudio Virtual Sink (RECOMMENDED)

**Reliability**: HIGH | **Complexity**: MEDIUM | **Production-Proven**: YES

This is the most battle-tested approach, used by the majority of open-source meeting bots.

#### Configuration

```bash
# Start PulseAudio daemon (non-root recommended)
pulseaudio -D --exit-idle-time=-1

# Create virtual audio sink
pactl load-module module-null-sink sink_name=DummyOutput sink_properties=device.description="Virtual_Output"

# Set as default sink (where browser audio goes)
pactl set-default-sink DummyOutput

# Set the monitor as default source (for recording)
pactl set-default-source DummyOutput.monitor
```

#### ffmpeg Recording Command

```bash
ffmpeg -y \
  -f x11grab -video_size 1920x1080 -framerate 30 -i :99 \
  -f pulse -ac 2 -i default \
  -c:v libx264 -pix_fmt yuv420p \
  -c:a aac -b:a 128k \
  output.mp4
```

#### Dockerfile Example

```dockerfile
FROM mcr.microsoft.com/playwright:v1.50.0-noble

# Install audio dependencies
RUN apt-get update && apt-get install -y \
    pulseaudio \
    ffmpeg \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user (fixes root warning)
RUN useradd -m -s /bin/bash botuser && \
    usermod -aG audio botuser

# PulseAudio configuration for container
RUN mkdir -p /home/botuser/.config/pulse && \
    echo "default-server = unix:/tmp/pulseaudio.socket" > /home/botuser/.config/pulse/client.conf && \
    echo "autospawn = no" >> /home/botuser/.config/pulse/client.conf && \
    echo "enable-shm = false" >> /home/botuser/.config/pulse/client.conf

USER botuser
WORKDIR /app

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

#### entrypoint.sh

```bash
#!/bin/bash
set -e

# Start virtual display
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99

# Start PulseAudio
pulseaudio -D --exit-idle-time=-1 --log-target=stderr

# Create virtual sink
pactl load-module module-null-sink sink_name=DummyOutput
pactl set-default-sink DummyOutput
pactl set-default-source DummyOutput.monitor

# Run the application
exec "$@"
```

**Sources**:
- [elgalu/docker-selenium Issue #147](https://github.com/elgalu/docker-selenium/issues/147)
- [Gladia - How to build a Google Meet Bot](https://www.gladia.io/blog/how-to-build-a-google-meet-bot-for-recording-and-video-transcription)
- [OmGuptaIND/recorder](https://github.com/OmGuptaIND/recorder)

---

### 2. PulseAudio System Mode (Root User Fix)

**Reliability**: HIGH | **Complexity**: LOW | **Root Compatible**: YES

If you must run as root (e.g., some CI/CD environments), use system mode.

#### Configuration

```bash
# Run PulseAudio in system mode (allows root)
pulseaudio --system --daemonize --exit-idle-time=-1

# Add root to pulse-access group for pactl commands
usermod -aG pulse-access root

# Load virtual sink
pactl load-module module-null-sink sink_name=v1
pactl set-default-sink v1
pactl set-default-source v1.monitor
```

#### /etc/pulse/system.pa Addition

```
load-module module-native-protocol-unix auth-anonymous=true socket=/tmp/pulseaudio.socket
load-module module-null-sink sink_name=auto_null
load-module module-always-sink
```

#### /etc/pulse/daemon.conf

```
system-instance = yes
exit-idle-time = -1
default-sample-format = float32le
default-sample-rate = 48000
```

**Caveat**: System mode is less secure and not recommended for multi-user systems. Fine for isolated containers.

**Sources**:
- [PulseAudio in Docker Gist](https://gist.github.com/janvda/e877ee01686697ceaaabae0f3f87da9c)
- [x11docker Wiki - Container Sound](https://github.com/mviereck/x11docker/wiki/Container-sound:-ALSA-or-Pulseaudio)

---

### 3. PipeWire (Modern Alternative)

**Reliability**: MEDIUM-HIGH | **Complexity**: HIGH | **Audio Quality**: BEST

PipeWire is the successor to PulseAudio and resolves crackling/distortion issues some users report with PulseAudio.

#### Why Consider PipeWire

- Better audio quality (no crackling artifacts)
- Drop-in replacement for PulseAudio (pipewire-pulse)
- Better latency characteristics
- Modern architecture designed for containers

#### Dockerfile Example

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    pipewire \
    pipewire-pulse \
    wireplumber \
    xvfb \
    ffmpeg \
    dbus-x11

# Create startup script
COPY start-pipewire.sh /start-pipewire.sh
RUN chmod +x /start-pipewire.sh
```

#### start-pipewire.sh

```bash
#!/bin/bash
export XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p $XDG_RUNTIME_DIR

# Start D-Bus
dbus-daemon --session --fork

# Start Xvfb
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99

# Start PipeWire services
pipewire &
sleep 1
pipewire-pulse &
sleep 1
wireplumber &
sleep 2

# Create virtual sink using PipeWire
pw-cli create-node adapter factory.name=support.null-audio-sink \
    media.class=Audio/Sink node.name=VirtualSink

exec "$@"
```

**Caveat**: PipeWire configuration for virtual sinks is less documented than PulseAudio. Requires XDG_RUNTIME_DIR to be set.

**Sources**:
- [Docker-Virtual-XVFB-pipewire](https://github.com/louisoutin/Docker-Virtual-XVFB-pipewire)
- [Walker Griggs - PipeWire in Docker](https://walkergriggs.com/2022/12/03/pipewire_in_docker/)

---

### 4. Remap Source for Browser Capture

**Reliability**: HIGH | **Complexity**: MEDIUM | **Browser Compatible**: YES

Chromium/Chrome browsers hide PulseAudio monitor devices by default. This approach creates a remapped source that appears as a regular microphone.

#### Why This Matters

When using `navigator.mediaDevices.getUserMedia()` in the browser, monitor sources are filtered out. This prevents capturing browser audio through WebRTC-based approaches.

#### Configuration

```bash
# Standard null sink setup
pactl load-module module-null-sink sink_name=virtmic sink_properties=device.description="Virtual_Microphone"

# Remap the monitor to a regular source (critical step)
pactl load-module module-remap-source \
    master=virtmic.monitor \
    source_name=virtmic_source \
    source_properties=device.description="Virtual_Microphone_Source"

# Set as default source
pactl set-default-source virtmic_source
```

#### Playwright/Chromium Args

```javascript
const browser = await chromium.launch({
  args: [
    '--use-fake-ui-for-media-stream',  // Auto-allow mic/camera
    // DO NOT use --use-fake-device-for-media-stream (overrides PulseAudio)
    '--disable-gpu',
    '--no-sandbox',
  ]
});
```

**Critical**: Do NOT use `--use-fake-device-for-media-stream` as it overrides PulseAudio with Chrome's built-in fake device.

**Sources**:
- [captureSystemAudio](https://github.com/guest271314/captureSystemAudio)
- [selenium-node-with-audio-looping](https://github.com/pschroeder89/selenium-node-with-audio-looping)

---

### 5. Host PulseAudio Socket Sharing

**Reliability**: HIGH | **Complexity**: LOW | **Container Isolation**: REDUCED

Share the host's PulseAudio server with the container via Unix socket.

#### Docker Run Command

```bash
docker run -it \
  -e PULSE_SERVER=unix:/run/user/$(id -u)/pulse/native \
  -v /run/user/$(id -u)/pulse:/run/user/$(id -u)/pulse \
  -v ~/.config/pulse/cookie:/root/.config/pulse/cookie:ro \
  --user $(id -u):$(id -g) \
  your-image
```

#### Container client.conf

```
default-server = unix:/run/user/1000/pulse/native
autospawn = no
enable-shm = false
```

**Caveat**: Requires PulseAudio running on host. Not suitable for headless cloud servers without existing audio stack.

**Sources**:
- [TheBiggerGuy/docker-pulseaudio-example](https://github.com/TheBiggerGuy/docker-pulseaudio-example)
- [Medium - Enabling Sound Card Access in Docker](https://medium.com/@18bhavyasharma/enabling-sound-card-access-in-docker-containers-using-pulseaudio-d52ff1f5eee4)

---

## Complete Working Example

Here is a complete, tested configuration combining the best practices:

### Dockerfile

```dockerfile
FROM mcr.microsoft.com/playwright:v1.50.0-noble

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    pulseaudio \
    pulseaudio-utils \
    ffmpeg \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash -G audio botuser

# Configure PulseAudio for container use
RUN mkdir -p /home/botuser/.config/pulse && \
    echo "autospawn = no" > /home/botuser/.config/pulse/client.conf && \
    echo "enable-shm = false" >> /home/botuser/.config/pulse/client.conf && \
    chown -R botuser:botuser /home/botuser

WORKDIR /app
COPY --chown=botuser:botuser . .

USER botuser

COPY --chown=botuser:botuser entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["node", "bot.js"]
```

### entrypoint.sh

```bash
#!/bin/bash
set -e

echo "Starting virtual display..."
Xvfb :99 -screen 0 1920x1080x24 -ac &
sleep 2
export DISPLAY=:99

echo "Starting PulseAudio..."
pulseaudio -D --exit-idle-time=-1 --log-target=stderr --log-level=warning
sleep 1

echo "Configuring virtual audio sink..."
pactl load-module module-null-sink sink_name=VirtualSpeaker sink_properties=device.description="Virtual_Speaker"
pactl set-default-sink VirtualSpeaker
pactl set-default-source VirtualSpeaker.monitor

echo "Audio setup complete. Available sinks:"
pactl list short sinks
echo "Available sources:"
pactl list short sources

exec "$@"
```

### Recording Script (record.sh)

```bash
#!/bin/bash
OUTPUT_FILE="${1:-recording.mp4}"
DURATION="${2:-3600}"  # Default 1 hour

ffmpeg -y \
  -f x11grab -video_size 1920x1080 -framerate 30 -i :99 \
  -f pulse -ac 2 -i VirtualSpeaker.monitor \
  -t $DURATION \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 128k \
  "$OUTPUT_FILE"
```

### Playwright Configuration

```javascript
// playwright.config.js or launch options
const browser = await chromium.launch({
  headless: false,  // Use headed mode with Xvfb
  args: [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--disable-gpu',
    '--use-fake-ui-for-media-stream',
    // Note: Do NOT add --use-fake-device-for-media-stream
    '--autoplay-policy=no-user-gesture-required',
  ],
});
```

---

## Troubleshooting Guide

### Error: "This program is not intended to be run as root"

**Solutions (pick one):**
1. Run as non-root user (recommended)
2. Use `pulseaudio --system` for system mode
3. Add `--disallow-module-loading=false` flag

### Error: "Connection refused" or "pa_context_connect() failed"

**Solutions:**
1. Ensure PulseAudio is running: `pulseaudio --check`
2. Check socket exists: `ls /run/user/*/pulse/native`
3. Set correct PULSE_SERVER environment variable

### Error: No audio in recording

**Checklist:**
1. Verify sink is set: `pactl info | grep "Default Sink"`
2. Verify monitor exists: `pactl list short sources | grep monitor`
3. Check Chrome is using correct output: `pactl list sink-inputs`
4. Ensure NOT using `--use-fake-device-for-media-stream`

### Error: Crackling/distorted audio

**Solutions:**
1. Switch to PipeWire
2. Adjust sample rate in daemon.conf:
   ```
   default-sample-rate = 48000
   default-fragment-size-msec = 5
   ```
3. Disable SHM: `enable-shm = false` in client.conf

### Error: Browser not outputting audio

**Checklist:**
1. Verify `--autoplay-policy=no-user-gesture-required` is set
2. Check meeting has joined successfully
3. Verify no mute state in meeting UI
4. Use `pactl list sink-inputs` to see active audio streams

---

## Production Recommendations

### Resource Allocation

- **RAM**: Minimum 512MB per bot, recommended 1GB
- **CPU**: 0.5 vCPU minimum for smooth recording
- **Disk**: SSDs for recording output (high I/O during encoding)

### Container Orchestration

```yaml
# docker-compose.yml
version: '3.8'
services:
  meeting-bot:
    build: .
    ipc: host  # Required for Chromium shared memory
    cap_add:
      - SYS_ADMIN  # May be needed for some Chromium operations
    volumes:
      - ./recordings:/app/recordings
    environment:
      - DISPLAY=:99
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1.0'
```

### Audio-Only Recording (Lower Resources)

If you only need audio (for Whisper transcription), skip video capture:

```bash
ffmpeg -y \
  -f pulse -ac 2 -ar 16000 -i VirtualSpeaker.monitor \
  -c:a libopus -b:a 32k \
  audio_only.ogg
```

Or for Whisper-optimized format:

```bash
ffmpeg -y \
  -f pulse -ac 1 -ar 16000 -i VirtualSpeaker.monitor \
  -c:a pcm_s16le \
  audio_for_whisper.wav
```

---

## Open-Source Meeting Bot References

| Project | Audio Method | Status |
|---------|--------------|--------|
| [screenappai/meeting-bot](https://github.com/screenappai/meeting-bot) | PulseAudio + Playwright | Active |
| [meetingbot/meetingbot](https://github.com/meetingbot/meetingbot) | PulseAudio | Active |
| [dunkbing/meeting-bot](https://github.com/dunkbing/meeting-bot) | GStreamer + PulseAudio | Active |
| [OmGuptaIND/recorder](https://github.com/OmGuptaIND/recorder) | PulseAudio + ffmpeg | Active |
| [vkanduri/avcapture](https://github.com/vkanduri/avcapture) | PulseAudio + ffmpeg | Archived |

---

## Conclusion

For meeting recording in headless Docker containers:

1. **Use PulseAudio with module-null-sink** as the virtual audio device
2. **Run as non-root user** to avoid the root warning
3. **Record from the monitor source** (sink.monitor) with ffmpeg
4. **Do NOT use** `--use-fake-device-for-media-stream` in Chromium
5. **Consider PipeWire** if experiencing audio quality issues

The configuration in Section "Complete Working Example" provides a tested starting point that addresses the specific error you encountered.

---

## Sources

### Official Documentation
- [Playwright Docker Documentation](https://playwright.dev/docs/docker)
- [PulseAudio Examples - ArchWiki](https://wiki.archlinux.org/title/PulseAudio/Examples)
- [PipeWire Official Site](https://pipewire.org/)

### GitHub Repositories
- [screenappai/meeting-bot](https://github.com/screenappai/meeting-bot)
- [meetingbot/meetingbot](https://github.com/meetingbot/meetingbot)
- [dunkbing/meeting-bot](https://github.com/dunkbing/meeting-bot)
- [OmGuptaIND/recorder](https://github.com/OmGuptaIND/recorder)
- [louisoutin/Docker-Virtual-XVFB-pipewire](https://github.com/louisoutin/Docker-Virtual-XVFB-pipewire)
- [vkanduri/avcapture](https://github.com/vkanduri/avcapture)
- [pschroeder89/selenium-node-with-audio-looping](https://github.com/pschroeder89/selenium-node-with-audio-looping)
- [guest271314/captureSystemAudio](https://github.com/guest271314/captureSystemAudio)
- [TheBiggerGuy/docker-pulseaudio-example](https://github.com/TheBiggerGuy/docker-pulseaudio-example)
- [elgalu/docker-selenium Issue #147](https://github.com/elgalu/docker-selenium/issues/147)
- [x11docker Wiki - Container Sound](https://github.com/mviereck/x11docker/wiki/Container-sound:-ALSA-or-Pulseaudio)
- [recallai/google-meet-meeting-bot](https://github.com/recallai/google-meet-meeting-bot)

### Technical Guides
- [Gladia - How to build a Google Meet Bot](https://www.gladia.io/blog/how-to-build-a-google-meet-bot-for-recording-and-video-transcription)
- [Recall.ai - How to Build a Meeting Bot](https://www.recall.ai/blog/how-to-build-a-meeting-bot)
- [Walker Griggs - PipeWire in Docker](https://walkergriggs.com/2022/12/03/pipewire_in_docker/)
- [PulseAudio in Docker Gist](https://gist.github.com/janvda/e877ee01686697ceaaabae0f3f87da9c)
- [Quick How-To guide on recording PulseAudio with ffmpeg](https://gist.github.com/psyburr/e0aa6072a57dbd151a528b9462266a82)
- [Medium - Enabling Sound Card Access in Docker](https://medium.com/@18bhavyasharma/enabling-sound-card-access-in-docker-containers-using-pulseaudio-d52ff1f5eee4)

### Docker Images
- [microsoft/playwright Docker Hub](https://hub.docker.com/r/microsoft/playwright)
- [browserless/chrome Docker Hub](https://hub.docker.com/r/browserless/chrome)
