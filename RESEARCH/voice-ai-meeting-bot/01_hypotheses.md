# Research Hypotheses

## H1: ARM64 CPU Limitation (Prior: HIGH 70%)
**Hypothesis**: Rockchip ARM64 CPU cannot handle continuous (100% duty cycle) ASR processing with acceptable latency (<500ms) for real-time meeting participation.

**Evidence needed to CONFIRM**: Benchmark data showing >500ms latency or >90% CPU utilization with streaming ASR on ARM64.
**Evidence needed to DISCONFIRM**: Working implementations of continuous ASR on ARM64 with <500ms latency.

## H2: Cloud ASR Cost Viability (Prior: MEDIUM 50%)
**Hypothesis**: Cloud ASR costs for 40+ hours/week continuous listening will exceed $200/month, making self-hosted options economically attractive for always-on use cases.

**Evidence needed to CONFIRM**: Pricing calculations showing >$200/month for major cloud providers.
**Evidence needed to DISCONFIRM**: Pricing models that are flat-rate or significantly cheaper than expected.

## H3: Hybrid Architecture Optimal (Prior: HIGH 75%)
**Hypothesis**: The optimal architecture for always-on voice AI is hybrid: cloud ASR for transcription + local LLM for response triggering decisions to minimize latency and cost.

**Evidence needed to CONFIRM**: Latency/cost analysis showing hybrid outperforms pure cloud or pure local.
**Evidence needed to DISCONFIRM**: Evidence that pure cloud or pure local approaches achieve better overall performance/cost.

## H4: Response Triggering Complexity (Prior: MEDIUM 60%)
**Hypothesis**: Intelligent response triggering (deciding WHEN to speak) requires an LLM analyzing conversation context, not just keyword/pattern matching.

**Evidence needed to CONFIRM**: Examples of failed keyword-based approaches, research on conversation understanding.
**Evidence needed to DISCONFIRM**: Successful implementations using simple heuristics or pattern matching.

## H5: OpenAI Realtime API Leadership (Prior: MEDIUM 55%)
**Hypothesis**: OpenAI's Realtime API provides the lowest latency and best quality for voice AI interactions but at the highest cost.

**Evidence needed to CONFIRM**: Benchmark comparisons showing OpenAI with lowest latency; pricing analysis showing premium.
**Evidence needed to DISCONFIRM**: Other solutions matching or exceeding OpenAI on latency/quality at lower cost.

## Probability Tracking
| Hypothesis | Initial Prior | After Phase 3 | After Phase 4 | Final |
|------------|--------------|---------------|---------------|-------|
| H1 | 70% | - | - | - |
| H2 | 50% | - | - | - |
| H3 | 75% | - | - | - |
| H4 | 60% | - | - | - |
| H5 | 55% | - | - | - |
