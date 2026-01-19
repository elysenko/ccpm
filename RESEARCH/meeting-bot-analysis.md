# Open-Source Meeting Bot Analysis

## Executive Summary

This document analyzes open-source meeting bot implementations that capture audio for transcription. The analysis covers architecture patterns, tech stacks, audio extraction methods, and Kubernetes deployment options.

---

## Tier 1: Production-Ready Solutions (Recommended)

### 1. ScreenApp Meeting Bot
**GitHub**: https://github.com/screenappai/meeting-bot
**License**: MIT
**Stars**: Active project, production-ready

| Component | Technology |
|-----------|------------|
| Language | TypeScript/Node.js 20+ |
| Browser Automation | Playwright |
| Job Queue | Redis (BLPOP) |
| API Framework | Express.js |
| Metrics | Prometheus |
| Container | Docker + Docker Compose |

**Architecture**:
- Single job execution model (one meeting at a time per instance)
- RESTful API + Redis message queue for job submission
- Webhook callbacks on completion
- XVFB wrapper for headless X11 display

**Audio/Video Capture**:
- Playwright joins meeting as browser participant
- Captures via browser's media APIs
- Saves as WebM format
- Auto-uploads to object storage (S3, GCS, MinIO, Azure Blob)

**API Endpoints**:
```
POST /google/join     - Join Google Meet
POST /microsoft/join  - Join MS Teams
POST /zoom/join       - Join Zoom
GET  /isbusy         - System status
GET  /metrics        - Prometheus metrics
```

**Deployment**:
- Production Dockerfile included
- Docker Compose orchestration
- Separate dev/prod configurations

**What We Can Reuse**:
- Playwright-based meeting joining
- Redis job queue pattern
- Storage abstraction layer
- Prometheus metrics integration

---

### 2. Vexa
**GitHub**: https://github.com/Vexa-ai/vexa
**License**: Apache 2.0
**Stars**: Active, enterprise-focused

| Component | Technology |
|-----------|------------|
| Language | Python |
| Database | PostgreSQL |
| Transcription | Whisper (100+ languages) |
| API | FastAPI + WebSocket |
| Container | Docker, Docker Compose |

**Architecture (Microservices)**:
- API Gateway - Request routing
- Bot Manager - Bot lifecycle
- Vexa Bot - Joins meetings, captures audio
- WhisperLive - Real-time transcription
- Transcription Collector - Persists transcript segments

**Audio Capture**:
- Bots join Google Meet and MS Teams as participants
- Real-time audio streaming to transcription service
- WebSocket delivery (sub-second latency)

**Deployment**:
- `vexaai/vexa-lite:latest` for single-container deployment
- Full Docker Compose stack for development
- Enterprise support for Kubernetes, HashiCorp Nomad, OpenShift

**API Authentication**: X-API-Key header

**What We Can Reuse**:
- Microservices architecture pattern
- WhisperLive integration for real-time transcription
- WebSocket streaming model

---

### 3. Attendee
**GitHub**: https://github.com/attendee-labs/attendee
**License**: Open Source
**Website**: https://attendee.dev

| Component | Technology |
|-----------|------------|
| Backend | Python/Django (80.9%) |
| Database | PostgreSQL |
| Cache | Redis |
| Transcription | Deepgram API |
| Meeting SDK | Zoom SDK |
| Container | Docker, Heroku |

**Architecture**:
- Containerized Django application
- Bot instances join meetings as participants
- Per-participant audio streams
- State machine: joining → in-meeting → ended

**API Endpoints**:
```
POST /bots         - Join meeting
GET  /bots/<id>    - Poll bot state
GET  /bots/<id>/transcript - Get transcript
```

**Platforms**: Zoom (primary), Google Meet, MS Teams, Webex (planned)

**What We Can Reuse**:
- Django API structure
- Bot state machine pattern
- Zoom SDK integration approach

---

### 4. MeetingBot (meetingbot/meetingbot)
**GitHub**: https://github.com/meetingbot/meetingbot
**License**: LGPL (commercial use allowed, modifications must be public)

| Component | Technology |
|-----------|------------|
| Frontend | Next.js |
| Backend | Express + tRPC |
| Database | PostgreSQL + Drizzle ORM |
| IaC | Terraform |
| Cloud | AWS |
| CI/CD | GitHub Actions |
| Package Manager | pnpm |

**Architecture**:
- Monorepo workspace (frontend, backend, bots)
- Type-safe API layer with tRPC
- Infrastructure as code with Terraform

**Platforms**: Google Meet, MS Teams, Zoom

**What We Can Reuse**:
- Terraform infrastructure patterns
- tRPC API architecture
- Monorepo structure

---

## Tier 2: Specialized/Partial Solutions

### 5. Meeting BaaS
**GitHub**: https://github.com/Meeting-Baas
**Focus**: Full platform with multiple components

**Key Components**:
- `realtime-meeting-transcription` - Real-time transcription with multiple providers
- `transcript-seeker` - Transcript viewer/manager
- `meeting-bot-as-a-service` - Core bot service
- **Kubernetes device plugin** for v4l2loopback virtual cameras

**Transcription Providers Supported**:
- Gladia (default)
- Deepgram
- AssemblyAI

**Real-time Architecture**:
- MeetingBaas Client → Proxy Server → Transcription Client
- WebSocket audio streaming (port 4040)
- HTTP webhook receiver for events

**What We Can Reuse**:
- Multi-provider transcription abstraction
- v4l2loopback Kubernetes plugin pattern
- VoiceRouter SDK approach

---

### 6. ZoomRec
**GitHub**: https://github.com/kastldratza/zoomrec
**Focus**: Automated Zoom recording in Docker

| Component | Technology |
|-----------|------------|
| Orchestration | Python 3 |
| Recording | FFmpeg |
| Display | Xvfb + Xfce + TigerVNC |
| Audio | PulseAudio (virtual loopback) |
| Container | Ubuntu 20.04 based |

**How Audio Capture Works**:
1. PulseAudio creates virtual loopback device at startup
2. Microphone output mapped to microphone input
3. FFmpeg captures both screen and audio
4. Saves to `/home/zoomrec/recordings`

**Docker Run**:
```bash
docker run -d \
  --security-opt seccomp:unconfined \
  -p 5901:5901 \
  -v ./recordings:/home/zoomrec/recordings \
  kastldratza/zoomrec
```

**Meeting Automation**: CSV-based scheduling with meeting ID, password, duration

**What We Can Reuse**:
- PulseAudio virtual loopback pattern
- FFmpeg recording command patterns
- Selenium-based Zoom automation

---

### 7. OmGuptaIND/Recorder
**GitHub**: https://github.com/OmGuptaIND/recorder
**Focus**: Generic browser recording with streaming support

| Component | Technology |
|-----------|------------|
| Language | Go (94.1%) |
| Browser Automation | Chromedp |
| Display | Xvfb |
| Audio | PulseAudio |
| Recording | FFmpeg |
| Streaming | RTMP |
| Storage | AWS S3 |

**Architecture**:
```
api/        - HTTP endpoints
executor/   - Recording process management
pipeline/   - Workflow orchestration
recorder/   - Core recording logic
display/    - Xvfb management
livestream/ - RTMP streaming
uploader/   - S3 integration
```

**API**:
```
POST /start-recording - {record_url, stream_url}
PATCH /stop-recording - {pipeline_id}
```

**Recording Flow**:
1. Chromedp navigates to URL in virtual display
2. FFmpeg captures Xvfb display + PulseAudio sink
3. Simultaneous recording and RTMP streaming supported
4. Multiple concurrent recordings via isolated PulseAudio instances

**What We Can Reuse**:
- Go-based architecture
- Xvfb + PulseAudio + FFmpeg pipeline
- RTMP streaming capability
- Concurrent recording isolation pattern

---

### 8. Meetily (Zackriya-Solutions/meeting-minutes)
**GitHub**: https://github.com/Zackriya-Solutions/meeting-minutes
**License**: MIT
**Stars**: 7,000+ | Users: 17,000+

| Component | Technology |
|-----------|------------|
| Backend | Rust (43.7%) |
| Frontend | TypeScript/Next.js (29.5%) |
| Desktop | Tauri |
| Transcription | Whisper.cpp, Parakeet |
| LLM | Ollama (local) |

**Audio Capture** (Different approach):
- **NOT a bot that joins meetings**
- Captures system audio + microphone simultaneously
- "Professional audio mixing" with ducking
- Platform-agnostic (works with any meeting app)

**GPU Acceleration**:
- macOS: Metal/CoreML
- Windows: NVIDIA CUDA, AMD/Intel Vulkan
- Linux: Build from source

**What We Can Reuse**:
- Local transcription with Whisper.cpp
- Ollama integration for summarization
- Rust audio processing patterns (if building desktop app)

---

### 9. UHH-LT MeetingBot
**GitHub**: https://github.com/uhh-lt/MeetingBot
**Focus**: Offline meeting transcription with summarization

| Component | Technology |
|-----------|------------|
| Frontend | Node.js + Vue.js |
| Microservices | Java, Python 3 |
| ASR | Kaldi |
| Container | Docker Compose |

**Key Feature**: 100% offline operation, no network required

**Deployment**: `docker-compose -f docker-compose-prod.yml up -d`

**What We Can Reuse**:
- Kaldi ASR integration (alternative to Whisper)
- Offline-first architecture pattern

---

## Audio Capture Techniques Comparison

### Approach 1: Browser Automation (Playwright/Puppeteer)
**Used by**: ScreenApp, Vexa, Attendee

| Pros | Cons |
|------|------|
| Works with any web-based meeting | Requires Playwright/Puppeteer |
| Can capture per-participant streams | Resource intensive |
| No SDK dependencies | Bot detection possible |

**Technical Implementation**:
```javascript
// Playwright joins meeting URL
const browser = await playwright.chromium.launch();
const page = await browser.newPage();
await page.goto(meetingUrl);
// Browser's MediaRecorder API captures streams
```

### Approach 2: Virtual Display + FFmpeg
**Used by**: ZoomRec, OmGuptaIND/Recorder

| Pros | Cons |
|------|------|
| Works with any application | Higher resource usage |
| Can record desktop clients | More complex setup |
| Captures exactly what's displayed | Requires Xvfb, PulseAudio |

**FFmpeg Command Pattern**:
```bash
ffmpeg -y \
  -video_size 1920x1080 \
  -framerate 30 \
  -f x11grab -i :99 \           # Capture Xvfb display
  -f pulse -i default \          # Capture PulseAudio
  -t {duration} \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -c:a aac \
  -strict experimental \
  output.mp4
```

### Approach 3: Native SDK
**Used by**: Attendee (Zoom SDK)

| Pros | Cons |
|------|------|
| Best integration | Platform-specific |
| Per-participant audio | SDK licensing constraints |
| Lower resource usage | Limited to SDK platforms |

### Approach 4: System Audio Capture (No Bot)
**Used by**: Meetily

| Pros | Cons |
|------|------|
| No bot joins meeting | Can't capture remote audio directly |
| Works with any platform | Requires desktop app |
| Privacy-friendly | Not suitable for server deployment |

---

## Kubernetes Deployment

### v4l2loopback Device Plugin
**GitHub**: https://github.com/mpreu/k8s-device-plugin-v4l2loopback

Creates virtual video devices for Kubernetes pods running meeting bots.

**How It Works**:
1. DaemonSet runs on each node
2. Pre-installs v4l2loopback kernel module
3. Creates virtual video devices
4. Pods request devices via resource limits

**Pod Spec Example**:
```yaml
resources:
  limits:
    devices.meetingbaas.com/v4l2loopback: 1
```

**Requirements**:
- v4l2loopback kernel module on nodes
- Device plugin DaemonSet

### Scaling Considerations

| Approach | Scale Model |
|----------|-------------|
| Single job per instance | Horizontal pod scaling |
| Virtual display per recording | Isolated PulseAudio per pod |
| Stateless bots | Can use Kubernetes Deployment |

**Resource Requirements** (estimated per bot):
- CPU: 1-2 cores
- Memory: 2-4 GB
- GPU: Optional (for local transcription)

---

## Recommended Architecture for Our Implementation

Based on analysis, the optimal architecture combines:

### Core Components
1. **Job Queue**: Redis (proven pattern across projects)
2. **Bot Service**: Node.js/TypeScript with Playwright (ScreenApp pattern)
3. **Transcription**:
   - Real-time: Deepgram/AssemblyAI (external)
   - Offline: Whisper (local)
4. **Storage**: S3-compatible object storage
5. **API**: Express.js with Prometheus metrics

### Audio Capture Stack
```
Playwright (browser automation)
    ↓
WebRTC MediaStream capture
    ↓
WebM recording
    ↓
S3 upload
    ↓
Transcription service
```

### Alternative: FFmpeg Stack (for desktop client recording)
```
Xvfb (virtual display)
    ↓
PulseAudio (virtual audio)
    ↓
FFmpeg (capture both)
    ↓
MP4/WebM output
    ↓
S3 upload
```

### Kubernetes Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: meeting-bot
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: bot
        image: meeting-bot:latest
        resources:
          limits:
            memory: "4Gi"
            cpu: "2"
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: v4l2loopback-plugin
spec:
  # Device plugin for virtual cameras
```

---

## License Summary

| Project | License | Commercial Use |
|---------|---------|----------------|
| ScreenApp | MIT | Yes, freely |
| Vexa | Apache 2.0 | Yes, freely |
| Attendee | Open Source | Yes |
| MeetingBot | LGPL | Yes, must publish mods |
| Meetily | MIT | Yes, freely |
| ZoomRec | - | Check repo |
| OmGuptaIND/Recorder | - | Check repo |

---

## Key Takeaways

1. **Playwright/Puppeteer is the dominant approach** for browser-based meeting bots
2. **Redis + Express is the proven job queue pattern**
3. **PulseAudio + Xvfb + FFmpeg** is the standard stack for headless recording
4. **Deepgram and AssemblyAI** are the preferred transcription providers
5. **v4l2loopback** is critical for Kubernetes virtual camera support
6. **Most projects use MIT or Apache 2.0** licenses, enabling commercial use

---

## Sources

- [ScreenApp Meeting Bot](https://github.com/screenappai/meeting-bot)
- [Vexa](https://github.com/Vexa-ai/vexa)
- [Attendee](https://github.com/attendee-labs/attendee)
- [MeetingBot](https://github.com/meetingbot/meetingbot)
- [Meeting BaaS](https://github.com/Meeting-Baas)
- [Meetily](https://github.com/Zackriya-Solutions/meeting-minutes)
- [ZoomRec](https://github.com/kastldratza/zoomrec)
- [OmGuptaIND/Recorder](https://github.com/OmGuptaIND/recorder)
- [UHH-LT MeetingBot](https://github.com/uhh-lt/MeetingBot)
- [k8s-device-plugin-v4l2loopback](https://github.com/mpreu/k8s-device-plugin-v4l2loopback)
- [puppeteer-stream](https://www.npmjs.com/package/puppeteer-stream)
- [RecordRTC](https://github.com/muaz-khan/RecordRTC)
