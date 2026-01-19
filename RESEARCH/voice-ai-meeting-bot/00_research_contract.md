# Research Contract: Real-Time Voice AI Meeting Bot

## One-Sentence Question
What is the optimal architecture for an always-listening (no wake word) voice AI agent that can participate in meetings by answering questions and proactively interjecting when helpful?

## Decision/Use-Case
This research will inform:
1. Technology selection for building a meeting bot
2. Hardware procurement decisions
3. Architecture design choices
4. Budget allocation (cloud vs self-hosted)

## Audience
Technical - developers/engineers building the system

## Scope

### Included
- **Geography**: Global (cloud services available worldwide)
- **Timeframe**: Current state (January 2026) + 6-month outlook
- **Technologies**:
  - Cloud ASR: OpenAI Realtime API, Google Speech-to-Text, Amazon Transcribe, Azure Speech, Deepgram, AssemblyAI
  - Self-hosted ASR: Vosk, Whisper.cpp, faster-whisper
  - LLM inference: Cloud APIs + local (Ollama with Phi-3, Qwen2)
  - Audio routing: PulseAudio, PipeWire, virtual microphones
- **Hardware platforms**:
  - ARM64 (Rockchip CPU-only)
  - x86 with NVIDIA GPU
  - Cloud infrastructure

### Excluded
- Mobile/embedded devices (phones, IoT)
- Non-English language support (focus on English)
- Video processing (audio-only scope)
- Meeting recording/transcription products (focus on real-time interaction)

## Constraints
- **Banned sources**: Marketing-only content without technical details
- **Required sources**: Official documentation, benchmark studies, GitHub repos
- **Budget context**: Must evaluate options from $0 (fully self-hosted) to $500+/month

## Output Format
Comprehensive markdown report at `/home/ubuntu/ccpm/research-report.md`

## Citation Strictness
Strict - full citations with URLs for all claims

## Definition of Done
Research is complete when:
1. All 6 cloud ASR solutions evaluated for continuous streaming capability
2. ARM64 feasibility determined with benchmark data
3. x86/GPU requirements specified
4. Response triggering strategies documented with at least 3 approaches
5. Cost analysis for 40+ hours/week continuous use
6. Architecture recommendations with diagrams
7. All C1 claims have 2+ independent sources OR explicit uncertainty noted

## Research Intensity
**Tier: Deep** (novel question, high stakes, multiple conflicting approaches)
- Agents: 5-8
- GoT Depth: Max 4
- Stop Score: > 9

## Budget Limits
- N_search = 40 (max search calls)
- N_fetch = 40 (max fetch calls)
- N_docs = 15 (max pages to deep-read)
- N_iter = 6 (max GoT iterations)
