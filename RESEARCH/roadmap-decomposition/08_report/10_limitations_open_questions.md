# Limitations and Open Questions

## Research Limitations

### L1: Limited Formal Empirical Evidence

**Issue:** Most evidence for decomposition strategies comes from practitioner experience, not controlled studies.

**Impact:** Recommendations are "best current practice" not "proven optimal."

**Mitigation:**
- Weight claims by source independence
- Note uncertainty in recommendations
- Design system for iterative improvement

### L2: LLM Evolution Rapid

**Issue:** LLM capabilities changing rapidly. Research from 2024-2025 may not reflect 2026+ capabilities.

**Impact:** Confidence thresholds and human review requirements may need adjustment.

**Mitigation:**
- Build configurable thresholds
- Monitor LLM performance metrics
- Periodic re-evaluation of automation levels

### L3: Domain Specificity Not Tested

**Issue:** Research covers general software development. Specific domains (healthcare, finance, embedded) may have different optimal strategies.

**Impact:** Recommendations may not transfer to all contexts.

**Mitigation:**
- Allow domain-specific strategy overrides
- Track performance by domain
- Enable custom anti-pattern rules

### L4: Scale Limits Unknown

**Issue:** Most evidence from teams of 5-15 people with 20-100 backlog items. Enterprise scale (1000+ items) may behave differently.

**Impact:** DAG algorithms optimized for small-medium scale.

**Mitigation:**
- Include algorithm complexity analysis
- Plan for partitioning at scale
- Monitor performance as usage grows

---

## Open Questions

### OQ1: Optimal PRD Granularity

**Question:** What is the optimal size for a PRD in different contexts?

**Current Position:** "6-10 stories per sprint" suggests M-sized PRDs are default target.

**Unknown:**
- Does optimal size vary by team velocity?
- Does domain complexity affect optimal size?
- Should infrastructure PRDs be larger than feature PRDs?

**Proposed Investigation:**
- Track completion rates by PRD size
- Correlate size with rework frequency
- A/B test different granularity targets

### OQ2: Implicit Dependency Accuracy

**Question:** How accurate are LLM-detected implicit dependencies?

**Current Position:** LLMs "falter when relationships are implied rather than clearly stated."

**Unknown:**
- What is the false positive rate?
- What is the false negative rate?
- Can confidence scoring improve over time?

**Proposed Investigation:**
- Human validation of detected dependencies
- Track integration failures from missed dependencies
- Compare LLM detection to expert annotation

### OQ3: Human Review Effectiveness

**Question:** Does human review actually improve outcomes?

**Current Position:** Human review is mandatory for confidence < 0.7.

**Unknown:**
- What percentage of human reviews result in changes?
- Are changes significant or cosmetic?
- Is 0.7 the right threshold?

**Proposed Investigation:**
- Track review acceptance rate
- Categorize types of human changes
- Test different thresholds

### OQ4: Anti-Pattern Severity Weighting

**Question:** Are all HIGH severity anti-patterns equally problematic?

**Current Position:** horizontal_slice, core_first, happy_path_only are HIGH severity.

**Unknown:**
- Do some anti-patterns cause more rework than others?
- Does context affect severity (e.g., API-first vs. user-first)?
- Should severity be configurable?

**Proposed Investigation:**
- Track rework correlated with specific anti-patterns
- Survey practitioners on experienced impact
- Allow configurable severity in settings

### OQ5: Multi-Team Coordination

**Question:** How should decomposition account for multi-team environments?

**Current Position:** Focus on single-team decomposition.

**Unknown:**
- Should PRDs explicitly target specific teams?
- How do cross-team dependencies affect strategies?
- Does SAFe hierarchy mapping improve coordination?

**Proposed Investigation:**
- Study multi-ART decomposition patterns
- Track cross-team dependency friction
- Consider team assignment as decomposition input

---

## What Would Change Our Conclusions

### Hypothesis Updates

| Hypothesis | Current Confidence | Would Increase If... | Would Decrease If... |
|------------|-------------------|---------------------|---------------------|
| H1: Vertical > Horizontal | 90% | Formal study confirms | Study shows context-dependent |
| H2: LLM dependencies unreliable | 65% (negative) | Error rates measured high | New models show improvement |
| H3: INVEST automatable | 75% | Tools validate accurately | Practitioners report failures |
| H4: DAG incremental | 95% | Production deployment succeeds | Scale issues emerge |
| H5: Hybrid wins | 85% | Practitioners confirm | Full automation succeeds |

### Evidence That Would Change Recommendations

1. **If LLMs achieve 90%+ accuracy on dependency detection:**
   - Reduce human review threshold
   - Enable auto-approval for more cases

2. **If horizontal slicing shows faster delivery in specific contexts:**
   - Add conditional guidance
   - Create context-detection heuristics

3. **If anti-pattern detection has high false positive rate:**
   - Relax severity weighting
   - Require human confirmation of anti-patterns

4. **If small PRDs consistently cause more rework than medium:**
   - Adjust size scoring
   - Recommend fewer, larger PRDs

---

## Future Research Directions

### FR1: Domain-Specific Decomposition

Research how decomposition strategies should adapt for:
- Healthcare (regulatory requirements)
- Finance (compliance, audit trails)
- Embedded systems (hardware dependencies)
- ML/AI systems (experiment-driven)

### FR2: Learning from Outcomes

Build feedback loops:
- Track which PRDs lead to successful delivery
- Correlate INVEST scores with actual outcomes
- Use outcome data to improve heuristics

### FR3: Cross-Repository Learning

Investigate whether patterns from one codebase transfer:
- Common decomposition patterns by language/framework
- Industry-specific best practices
- Team-specific preferences

### FR4: Real-Time Collaboration

Explore human-AI collaboration patterns:
- Interactive decomposition refinement
- Explanation of decomposition decisions
- Confidence calibration through feedback

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| LLM produces low-quality decompositions | Medium | High | Mandatory validation + review |
| Dependency detection misses critical links | Medium | High | Human review gate |
| Over-automation leads to poor PRDs | Low | High | Configurable thresholds |
| Anti-pattern rules too restrictive | Medium | Medium | Allow rule customization |
| Performance degrades at scale | Low | Medium | Algorithm complexity monitoring |

---

## Acknowledgment of Uncertainty

This research represents best available evidence as of January 2026. Key uncertainties:

1. **Evidence quality:** Practitioner consensus vs. empirical studies
2. **Temporal validity:** LLM capabilities evolving rapidly
3. **Generalizability:** Tested primarily in web/mobile software contexts
4. **Threshold calibration:** 0.7 confidence threshold is informed estimate, not proven optimal

Recommendations should be treated as starting points, with continuous improvement based on actual usage data.
