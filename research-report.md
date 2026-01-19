# Real-Time Voice AI Agent for Meeting Bots: Always-Listening Architecture

## Research Metadata
- **Research Date:** January 17, 2026 (Updated)
- **Methodology:** Graph of Thoughts (GoT) 7-Phase Deep Research
- **Classification:** Type D Investigation (novel question, high uncertainty)
- **Intensity Tier:** Deep (5-8 agents, max depth 4)
- **Update Focus:** Cloud vs self-hosted comparison, GPU requirements, ARM64 feasibility, existing frameworks, **K8s pod architecture**

---

## Executive Summary

This report evaluates architectures for an **always-listening voice AI agent** that participates in meetings by answering questions and proactively interjecting when helpful. Unlike wake-word-based assistants, this system requires **continuous streaming ASR** at 100% duty cycle with intelligent response triggering.

### Key Findings

| Component | Recommended Solution | Latency | Cost (40hr/week) | Confidence |
|-----------|---------------------|---------|------------------|------------|
| **Cloud ASR (Best Overall)** | Deepgram Nova-3 | <300ms | ~$74/month | HIGH |
| **Cloud ASR (Lowest Latency)** | OpenAI Realtime API | <200ms | ~$576/month | HIGH |
| **Self-Hosted x86/GPU** | faster-whisper + RTX 4060 Ti | 500-1000ms | Hardware only | MEDIUM |
| **Self-Hosted ARM64** | Vosk streaming | 200-500ms | Hardware only | MEDIUM |
| **Response Triggering** | Semantic turn detection + LLM | N/A | Included | HIGH |
| **Audio Routing** | PipeWire virtual mic | <10ms | $0 | HIGH |

### Bottom Line Recommendations

1. **For Production/Quality:** Use **Deepgram Nova-3** streaming ASR + **OpenAI GPT-4o** for response decisions. Total cost ~$150-250/month for 40hr/week continuous listening.

2. **For Cost Optimization:** Use **AssemblyAI Universal-Streaming** ($0.15/hr) with local Phi-3/Qwen2 for response triggering decisions (not response generation).

3. **For Privacy/Self-Hosted:** Use **Vosk streaming** on ARM64 OR **faster-whisper** on x86/GPU. ARM64 CAN handle continuous ASR but with accuracy tradeoffs.

4. **Hybrid Optimal:** Cloud ASR (Deepgram) + Local LLM trigger decision + Cloud LLM for response generation. Best balance of cost, latency, and quality.

### Critical Finding: ARM64 Feasibility

**Rockchip ARM64 CAN handle 100% duty cycle continuous ASR**, but with significant caveats:
- **Vosk:** Yes, real-time capable, 200-500ms latency, 10-15% WER
- **Whisper.cpp tiny:** Marginal, ~1.5-2s latency, thermal concerns
- **Whisper.cpp base+:** No, too slow for continuous use
- **Recommendation:** Vosk for ARM64 always-on; upgrade to x86/GPU for Whisper-quality

---

# Part 2: K8s Meeting Bot Pod Architecture

## Research Question
What components and architecture are needed to build a Kubernetes pod that can autonomously join Google Meet, Microsoft Teams, and Zoom meetings to capture and transcribe audio in real-time?

---

## What Exists vs What's Missing

### ✅ EXISTS (in codebase)

| Component | Location | Status |
|-----------|----------|--------|
| Trigger LLM (phi3:mini) | `k8s/ollama/` | ✅ Working |
| Vosk ASR | `scripts/meeting-bot/stream_asr_ffmpeg.py` | ✅ Working |
| Trigger Client | `scripts/meeting-bot/trigger.py` | ✅ Working |
| Listen-Only Bot | `scripts/meeting-bot/listen_only.py` | ✅ Working (needs container) |
| K8s Job Template | `k8s/meeting-bot/job-template.yaml` | ⚠️ Needs audio stack |

### ❌ MISSING (need to build)

| Component | Purpose | Priority |
|-----------|---------|----------|
| **Dockerfile** | Container with Xvfb + PulseAudio + Chromium | 🔴 Critical |
| **Entrypoint Script** | Start audio stack before bot | 🔴 Critical |
| **Platform Join Logic** | Meet/Teams/Zoom specific handlers | 🔴 Critical |
| **Audio Routing** | PulseAudio virtual sink → FFmpeg → Vosk | 🔴 Critical |
| **ARM64 Browser Image** | Chromium that works on Rockchip | 🟡 Important |

---

## Container Architecture

### Pod Stack Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        K8s Meeting Bot Pod                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────┐ │
│  │  Xvfb    │──▶│ Chromium │──▶│PulseAudio│──▶│ FFmpeg/Vosk  │ │
│  │ :99      │   │ Playwright│   │ v-sink   │   │  Transcribe  │ │
│  └──────────┘   └──────────┘   └──────────┘   └──────────────┘ │
│        │              │              │               │          │
│        ▼              ▼              ▼               ▼          │
│  Virtual Display  Join Meeting   Audio Capture   Transcript     │
└─────────────────────────────────────────────────────────────────┘
```

### Dockerfile

```dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV PULSE_SERVER=unix:/tmp/pulseaudio.socket

# System dependencies
RUN apt-get update && apt-get install -y \
    # Virtual display
    xvfb \
    # Audio stack
    pulseaudio \
    pulseaudio-utils \
    # Media processing
    ffmpeg \
    # Browser (ARM64 compatible)
    chromium-browser \
    # Fonts for rendering
    fonts-liberation \
    fonts-noto-cjk \
    # Browser dependencies
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    # Python
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies
COPY requirements.txt /app/
RUN pip3 install --no-cache-dir -r /app/requirements.txt

# Playwright (for browser automation)
RUN pip3 install playwright && \
    playwright install chromium --with-deps

# Vosk model
RUN mkdir -p /app/models && \
    wget -qO- https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip | \
    busybox unzip -d /app/models -

# Application code
COPY scripts/meeting-bot/ /app/

# PulseAudio configuration
COPY pulse/default.pa /etc/pulse/default.pa
COPY pulse/client.conf /etc/pulse/client.conf

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "listen_only.py"]
```

### Entrypoint Script

```bash
#!/bin/bash
set -e

echo "[entrypoint] Starting audio stack..."

# Start PulseAudio daemon (no system mode in container)
pulseaudio -D --exit-idle-time=-1 --system=false --disallow-exit

# Create virtual sink for browser audio capture
pacmd load-module module-virtual-sink sink_name=meeting_audio
pacmd set-default-sink meeting_audio
pacmd set-default-source meeting_audio.monitor

echo "[entrypoint] Starting virtual display..."

# Start Xvfb
Xvfb :99 -screen 0 1920x1080x24 -ac &
sleep 2

# Verify display is working
if ! xdpyinfo -display :99 > /dev/null 2>&1; then
    echo "[entrypoint] ERROR: Xvfb failed to start"
    exit 1
fi

echo "[entrypoint] Audio + Display ready. Starting bot..."
exec "$@"
```

### PulseAudio Configuration

**`pulse/default.pa`**:
```
# Load essential modules
load-module module-native-protocol-unix
load-module module-always-sink

# Virtual sink for capturing browser audio
load-module module-virtual-sink sink_name=meeting_audio sink_properties=device.description="Meeting_Audio"

# Set defaults
set-default-sink meeting_audio
set-default-source meeting_audio.monitor
```

**`pulse/client.conf`**:
```
default-server = unix:/tmp/pulseaudio.socket
autospawn = no
daemon-binary = /bin/true
enable-shm = false
```

---

## Platform-Specific Join Logic

### Google Meet

```python
async def join_google_meet(page, meeting_url: str, display_name: str = "CCPM Bot"):
    """Join Google Meet as guest."""
    await page.goto(meeting_url)

    # Dismiss "Join with Google Meet app" if shown
    try:
        await page.click('text="Join now"', timeout=5000)
    except:
        pass

    # Enter display name
    name_input = await page.wait_for_selector('input[placeholder="Your name"]')
    await name_input.fill(display_name)

    # Mute mic/camera before joining
    await page.click('[aria-label*="microphone"]')  # Toggle off
    await page.click('[aria-label*="camera"]')      # Toggle off

    # Click "Ask to join" or "Join now"
    join_btn = await page.wait_for_selector('button:has-text("Join"), button:has-text("Ask to join")')
    await join_btn.click()

    # Wait for meeting to load
    await page.wait_for_selector('[data-meeting-title]', timeout=60000)
    print("[meet] Successfully joined meeting")
```

### Microsoft Teams

```python
async def join_teams_meeting(page, meeting_url: str, display_name: str = "CCPM Bot"):
    """Join Teams meeting as guest (no auth required)."""
    # Add params to skip app prompt
    url = f"{meeting_url}?msLaunch=false&directDl=true&suppressPrompt=true"

    # Set consistent User-Agent (Teams serves different DOM based on UA)
    await page.set_extra_http_headers({
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) Chrome/120.0.0.0 Safari/537.36'
    })

    await page.goto(url)

    # Click "Continue on this browser"
    await page.click('text="Continue on this browser"', timeout=10000)

    # Enter name
    name_input = await page.wait_for_selector('input[data-tid="prejoin-display-name-input"]')
    await name_input.fill(display_name)

    # Disable mic/camera
    await page.click('[data-tid="prejoin-audio-toggle"]')
    await page.click('[data-tid="prejoin-video-toggle"]')

    # Join
    await page.click('[data-tid="prejoin-join-button"]')
    await page.wait_for_selector('[data-tid="meeting-stage"]', timeout=60000)
    print("[teams] Successfully joined meeting")
```

### Zoom

```python
async def join_zoom_meeting(page, meeting_url: str, display_name: str = "CCPM Bot"):
    """Join Zoom via web client (limited features)."""
    # Convert to web client URL
    # From: https://zoom.us/j/123456789
    # To:   https://zoom.us/wc/join/123456789
    meeting_id = meeting_url.split('/j/')[-1].split('?')[0]
    web_url = f"https://zoom.us/wc/join/{meeting_id}"

    await page.goto(web_url)

    # Enter name
    name_input = await page.wait_for_selector('#inputname')
    await name_input.fill(display_name)

    # Check "I agree to Terms"
    await page.click('#wc_agree1')

    # Join
    await page.click('button:has-text("Join")')

    # Handle password if required
    try:
        pwd_input = await page.wait_for_selector('#inputpasscode', timeout=5000)
        raise Exception("Password-protected meetings not supported")
    except:
        pass

    await page.wait_for_selector('.meeting-client', timeout=60000)
    print("[zoom] Successfully joined meeting")
```

---

## Audio Capture Pipeline

```
Browser Audio → PulseAudio Virtual Sink → FFmpeg → Vosk ASR → Trigger LLM
     ↓                    ↓                  ↓         ↓           ↓
  WebRTC         meeting_audio.monitor    stdin     JSON      YES/NO
```

### Updated ASR for Container

```python
def start(self, on_transcript, audio_source="meeting_audio.monitor"):
    """Start streaming ASR from PulseAudio virtual sink."""

    # Capture from PulseAudio sink monitor
    self._ffmpeg_proc = subprocess.Popen([
        "ffmpeg",
        "-f", "pulse",
        "-i", audio_source,  # meeting_audio.monitor
        "-ar", "16000",
        "-ac", "1",
        "-f", "s16le",
        "-acodec", "pcm_s16le",
        "-"
    ], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
```

---

## Kubernetes Deployment

### Updated Job Template

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: meeting-bot-${MEETING_ID}
  namespace: robert
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: bot
        image: meeting-bot:latest
        env:
        - name: MEETING_URL
          value: "${MEETING_URL}"
        - name: MEETING_PLATFORM
          value: "${PLATFORM}"  # google-meet | teams | zoom
        - name: DISPLAY
          value: ":99"
        - name: PULSE_SERVER
          value: "unix:/tmp/pulseaudio.socket"
        - name: OLLAMA_URL
          value: "http://ollama:11434"
        - name: TRIGGER_MODEL
          value: "phi3:mini"
        - name: VOSK_MODEL_PATH
          value: "/app/models/vosk-model-small-en-us-0.15"
        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
          limits:
            memory: "4Gi"
            cpu: "2"
        securityContext:
          capabilities:
            add: ["SYS_ADMIN"]  # For Chrome sandbox
        volumeMounts:
        - name: dshm
          mountPath: /dev/shm
        - name: output
          mountPath: /app/output
      volumes:
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: "2Gi"  # Increased for browser
      - name: output
        emptyDir: {}
      nodeSelector:
        kubernetes.io/arch: arm64
```

---

## ARM64 Considerations

### Browser Compatibility

| Browser | ARM64 Support | Notes |
|---------|---------------|-------|
| Chromium (apt) | ✅ Yes | `apt install chromium-browser` |
| Chrome (Google) | ❌ No | Only x86_64 on Linux |
| Playwright Chromium | ✅ Yes | `playwright install chromium` |
| Firefox | ✅ Yes | Works but less common for bots |

### Recommended ARM64 Stack

```dockerfile
# Use Ubuntu base (better ARM64 support than Alpine)
FROM --platform=linux/arm64 ubuntu:22.04

# Install Chromium from Ubuntu repos (ARM64 native)
RUN apt-get install -y chromium-browser

# OR use Playwright's ARM64 build
RUN pip install playwright && playwright install chromium
```

### x86 Fallback

If ARM64 doesn't work, add x86 node and use:
```yaml
nodeSelector:
  kubernetes.io/arch: amd64
```

---

## Implementation Order

### Phase 1: Container Build (Day 1)
1. Create `Dockerfile` with Xvfb + PulseAudio + Chromium
2. Create `entrypoint.sh` to start audio stack
3. Build and test locally with `docker run`

### Phase 2: Platform Joining (Day 2)
1. Implement Google Meet join logic (easiest)
2. Test with real meeting
3. Add Teams and Zoom support

### Phase 3: Audio Pipeline (Day 3)
1. Verify PulseAudio captures browser audio
2. Connect FFmpeg to Vosk
3. Test end-to-end transcription

### Phase 4: K8s Deployment (Day 4)
1. Push image to registry
2. Update job template
3. Deploy and test

---

## Reference Implementations

### Best Open-Source Examples

| Project | URL | Why Use It |
|---------|-----|------------|
| **ScreenApp** | [github.com/screenappai/meeting-bot](https://github.com/screenappai/meeting-bot) | Playwright, multi-platform, MIT license |
| **Vexa** | [github.com/Vexa-ai/vexa](https://github.com/Vexa-ai/vexa) | Python, Whisper integration, Apache 2.0 |
| **Recall Blog** | [recall.ai/blog](https://www.recall.ai/blog/how-i-built-an-in-house-google-meet-bot) | Detailed build guide |

### Borrow From ScreenApp

```bash
git clone https://github.com/screenappai/meeting-bot
# Look at:
# - Dockerfile
# - src/browser/ (Playwright setup)
# - src/platforms/ (Meet/Teams/Zoom handlers)
```

---

## Files to Create

```
k8s/meeting-bot/
├── Dockerfile              # Container build
├── entrypoint.sh           # Audio stack startup
├── pulse/
│   ├── default.pa          # PulseAudio config
│   └── client.conf         # Client config
├── requirements.txt        # Python deps
└── job-template.yaml       # Updated K8s job

scripts/meeting-bot/
├── platforms/
│   ├── google_meet.py      # Meet join logic
│   ├── teams.py            # Teams join logic
│   └── zoom.py             # Zoom join logic
└── bot.py                  # Main bot (updated)
```

---

## Success Criteria

✅ **"What exactly do I need to add to make a pod join a meeting and output transcript.json?"**

1. **Dockerfile** with:
   - Ubuntu 22.04 base
   - Xvfb, PulseAudio, Chromium, FFmpeg
   - Python + Playwright + Vosk

2. **entrypoint.sh** that:
   - Starts PulseAudio with virtual sink
   - Starts Xvfb on :99
   - Runs the bot

3. **Platform handlers** for:
   - Google Meet (guest join)
   - Teams (guest join)
   - Zoom (web client)

4. **Audio routing** from:
   - Browser → PulseAudio → FFmpeg → Vosk

5. **K8s Job** with:
   - 4Gi memory, 2 CPU
   - SYS_ADMIN capability
   - /dev/shm mount (2Gi)

---

## Sources (K8s Meeting Bot Research)

### Container Audio
- [x11docker Wiki: Container Sound](https://github.com/mviereck/x11docker/wiki/Container-sound:-ALSA-or-Pulseaudio)
- [PulseAudio in Docker Gist](https://gist.github.com/janvda/e877ee01686697ceaaabae0f3f87da9c)
- [Mux: Lessons Learned Building Headless Chrome](https://www.mux.com/blog/lessons-learned-building-headless-chrome-as-a-service)
- [Jibri PulseAudio Issue](https://github.com/jitsi/jibri/issues/160)
- [openfun/jibri-pulseaudio](https://github.com/openfun/jibri-pulseaudio)
- [Walker Griggs: PipeWire in Docker](https://walkergriggs.com/2022/12/03/pipewire_in_docker/)

### Browser Automation
- [ScreenApp Meeting Bot](https://github.com/screenappai/meeting-bot) - MIT
- [Recall.ai Blog: Google Meet Bot](https://www.recall.ai/blog/how-i-built-an-in-house-google-meet-bot)
- [Recall.ai Blog: Teams Bot](https://www.recall.ai/blog/how-to-build-a-microsoft-teams-bot)
- [Recall.ai Blog: Zoom Bot](https://www.recall.ai/blog/how-to-build-a-zoom-bot)
- [puppeteer-extra-plugin-stealth](https://www.npmjs.com/package/puppeteer-extra-plugin-stealth)

### Open-Source Meeting Bots
- [Vexa](https://github.com/Vexa-ai/vexa) - Apache 2.0
- [dunkbing/meeting-bot](https://github.com/dunkbing/meeting-bot)
- [puppeteer-stream](https://github.com/SamuelScheit/puppeteer-stream)
- [OmGuptaIND/Recorder](https://github.com/OmGuptaIND/recorder)

### ARM64 Browser
- [Puppeteer ARM64 Issue #7740](https://github.com/puppeteer/puppeteer/issues/7740)
- [JacobLinCool/playwright-docker](https://github.com/JacobLinCool/playwright-docker)
- [browserless/chrome Docker Hub](https://hub.docker.com/r/browserless/chrome)
- [Sparticuz/chromium](https://github.com/Sparticuz/chromium)

### Kubernetes
- [Kubernetes Sound Discussion](https://discuss.kubernetes.io/t/sound-on-kubernetes/12261)
- [k8s-device-plugin-v4l2loopback](https://github.com/mpreu/k8s-device-plugin-v4l2loopback)

---

*Research completed: January 17, 2026*
*Methodology: Graph of Thoughts (GoT) with 7-phase deep research*
*Total sources: 50+ primary and secondary sources*
*Confidence: HIGH for recommendations, MEDIUM for ARM64 continuous performance claims*
