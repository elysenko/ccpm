# Research Plan: Voice AI Meeting Bot

## Subquestions

### SQ1: Cloud ASR Streaming Capabilities
**Question**: Which cloud ASR services support true continuous/streaming transcription suitable for always-on meeting participation?

**Planned queries**:
1. "OpenAI Realtime API continuous listening streaming audio 2026"
2. "Deepgram live streaming ASR real-time transcription latency"
3. "Google Cloud Speech-to-Text streaming API continuous audio"
4. "Amazon Transcribe streaming real-time meeting transcription"
5. "Azure Speech Services conversation transcription streaming"
6. "AssemblyAI real-time transcription streaming API"

**Source types**: Official documentation, API references, developer guides

### SQ2: Cloud ASR Pricing for Continuous Use
**Question**: What are the costs of cloud ASR services for 40+ hours/week continuous audio streaming?

**Planned queries**:
1. "OpenAI Realtime API pricing cost per minute 2026"
2. "Deepgram pricing streaming ASR cost calculator"
3. "Google Speech-to-Text pricing streaming audio"
4. "Amazon Transcribe streaming pricing per hour"

**Source types**: Pricing pages, cost calculators, case studies

### SQ3: ARM64 Self-Hosted ASR Feasibility
**Question**: Can ARM64 CPU (Rockchip) handle continuous streaming ASR with acceptable performance?

**Planned queries**:
1. "Whisper.cpp ARM64 streaming real-time performance benchmark"
2. "Vosk ARM64 streaming speech recognition performance"
3. "faster-whisper ARM64 CPU inference benchmark"
4. "Raspberry Pi continuous speech recognition streaming"
5. "ARM64 speech recognition CPU usage real-time"

**Source types**: GitHub repos, benchmark reports, developer forums

### SQ4: x86/GPU Hardware Requirements
**Question**: What hardware is needed for self-hosted continuous ASR + LLM inference?

**Planned queries**:
1. "Whisper streaming ASR GPU requirements real-time"
2. "faster-whisper NVIDIA GPU benchmark latency"
3. "continuous speech recognition server hardware requirements"
4. "LLM inference local hardware requirements Phi-3 Qwen"

**Source types**: Benchmark studies, hardware guides, GitHub repos

### SQ5: Response Triggering Strategies
**Question**: How can an AI intelligently decide when to respond during a meeting conversation?

**Planned queries**:
1. "conversational AI when to respond turn-taking detection"
2. "voice assistant proactive interjection meeting bot"
3. "LLM conversation understanding response triggering"
4. "detecting questions in speech meeting AI assistant"
5. "conversational turn-taking AI agent"

**Source types**: Research papers, AI/ML blogs, implementation guides

### SQ6: Audio Routing Architecture
**Question**: How to route TTS output to browser/meeting platform as microphone input?

**Planned queries**:
1. "virtual microphone PulseAudio PipeWire Linux TTS"
2. "route audio to browser microphone Linux meeting"
3. "meeting bot audio injection virtual audio device"

**Source types**: Technical guides, Linux audio documentation, GitHub repos

### SQ7: Existing Meeting Bot Solutions
**Question**: Are there existing voice AI meeting assistants designed for real-time participation?

**Planned queries**:
1. "AI meeting assistant real-time voice participation 2026"
2. "voice AI meeting bot speaks in meeting open source"
3. "real-time meeting AI assistant voice interaction"

**Source types**: Product reviews, GitHub repos, technical blogs

## Query Strategy
1. Start broad with official documentation
2. Narrow to benchmarks and real-world implementations
3. Cross-reference vendor claims with independent tests
4. Prioritize primary sources (official docs, academic papers)

## Stop Rules
1. **Saturation**: 3 consecutive queries yield <10% new information
2. **Coverage**: Each subquestion has 3+ quality sources
3. **Budget**: Max 40 searches, 40 fetches
