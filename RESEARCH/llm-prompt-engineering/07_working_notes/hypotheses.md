# Hypotheses Under Investigation

## H1: XML Tags Improve Claude's Parsing
**Prior Probability**: 80% (High)

**Testable Prediction**: Anthropic documentation explicitly recommends XML tags; empirical evidence shows improved output structure with XML-tagged prompts.

**Research Design**:
- Search Anthropic docs for XML tag recommendations
- Find comparative studies or examples
- Look for counter-examples or caveats

**Evidence to Look For**:
- Official documentation statements
- Before/after examples
- Specific tag conventions (e.g., `<context>`, `<instructions>`)

---

## H2: Extended Thinking Improves Complex Reasoning
**Prior Probability**: 75% (Medium-High)

**Testable Prediction**: Extended thinking mode demonstrably improves accuracy on multi-step reasoning, math, and complex analytical tasks.

**Research Design**:
- Find Anthropic documentation on extended thinking
- Look for benchmarks comparing with/without
- Identify task types where it helps most

**Evidence to Look For**:
- Performance metrics
- Task categories where effective
- Resource/latency tradeoffs

---

## H3: Few-Shot Needed for Novel Formats Only
**Prior Probability**: 60% (Medium)

**Testable Prediction**: Claude performs well zero-shot on standard tasks; few-shot examples primarily help with unusual output formats or domain-specific conventions.

**Research Design**:
- Compare guidance on few-shot vs zero-shot
- Find task categories where each is recommended
- Look for decision frameworks

**Evidence to Look For**:
- Task-specific recommendations
- Empirical comparisons
- Guidelines on when to use each

---

## H4: Long System Prompts Degrade Performance
**Prior Probability**: 50% (Medium - Uncertain)

**Testable Prediction**: There exists a point where additional system prompt length hurts model performance through confusion, attention dilution, or instruction conflict.

**Research Design**:
- Search for context length recommendations
- Find guidance on system prompt organization
- Look for evidence of attention degradation

**Evidence to Look For**:
- Length recommendations
- Organization strategies for long prompts
- Performance studies on prompt length

---

## H5: Prompt Injection Mitigable but Not Eliminable
**Prior Probability**: 85% (High)

**Testable Prediction**: While mitigation strategies exist, no known technique provides complete protection against prompt injection attacks.

**Research Design**:
- Catalog known injection mitigation techniques
- Find security research on effectiveness
- Look for Anthropic's guidance

**Evidence to Look For**:
- Mitigation technique list
- Effectiveness studies
- Official security guidance
- Known bypasses

---

## Tracking Table

| ID | Hypothesis | Prior | Updated | Δ | Key Evidence |
|----|------------|-------|---------|---|--------------|
| H1 | XML tags improve parsing | 80% | TBD | - | - |
| H2 | Extended thinking for reasoning | 75% | TBD | - | - |
| H3 | Few-shot for novel formats | 60% | TBD | - | - |
| H4 | Long prompts degrade | 50% | TBD | - | - |
| H5 | Injection mitigable not eliminated | 85% | TBD | - | - |
