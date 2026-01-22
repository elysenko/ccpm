---
name: contradictions-log
created: 2026-01-21T00:00:00Z
---

# Contradictions and Tensions Log

## T1: Autonomy vs Safety Tradeoff (Interpretation Conflict)

**Tension:** Sources disagree on how much autonomy is safe for AI agents.

- AutoGPT Wikipedia notes it "might be too autonomous to be useful" and doesn't allow corrective interventions
- SWE-Agent design prioritizes "maximal agency to the LM"
- Google ADK recommends strict guardrails and sandboxing
- Claude Code offers "--dangerously-skip-permissions" flag (YOLO mode) as explicit opt-in

**Resolution:** Present both viewpoints. The consensus is that autonomy should be:
1. Configurable (not all-or-nothing)
2. Sandboxed by default
3. Explicitly opted into for dangerous operations
4. Subject to audit trail regardless of autonomy level

## T2: Confidence Scoring Reliability (Methodological Conflict)

**Tension:** Sources disagree on whether LLM confidence scores are reliable for gating decisions.

- Academic paper (S25) shows LLMs are "overconfident" and calibration is "far from ideal"
- Conformal prediction research shows confidence can gate actions successfully
- Industry practice often uses confidence thresholds anyway

**Resolution:** Use confidence as one signal among several, not the sole decision gate. Combine with:
- Output validation (does the answer make sense?)
- Reversibility check (is this undoable?)
- Domain-specific rules (hard boundaries)

## T3: Convention Inference Feasibility (Data Conflict)

**Tension:** Can AI reliably infer conventions from codebase?

- Naturalize paper: Only recommends when "sufficient consensus" exists
- Developer context study: Developers provide less context for typed languages
- Practice: AI tools already do this with mixed results

**Resolution:** Convention inference is feasible for:
- High-consensus patterns (>80% consistency in codebase)
- Statically typed codebases (more inferrable)
- Well-established framework conventions (Rails, Next.js)

Not recommended for:
- Novel or inconsistent codebases
- Ambiguous naming where multiple conventions coexist
- Security-sensitive decisions

## T4: Input Classification Complexity

**Tension:** How complex is prompt/input classification?

- NVIDIA classifier uses 11 categories + 6 complexity dimensions
- Practical tools (yes/no prompts) use binary classification
- Some sources suggest NLP-based classification is essential

**Resolution:** Use tiered approach:
1. Simple pattern matching for common cases (Y/N, file overwrite)
2. LLM-based classification for ambiguous cases
3. Defer for unclassifiable inputs

## No Major Data Contradictions Found

The sources are largely complementary rather than contradictory. The main tensions are around interpretation of "how much is too much" autonomy, which is appropriately handled through configuration.
