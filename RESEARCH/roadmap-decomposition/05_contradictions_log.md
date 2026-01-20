---
name: contradictions-log
created: 2026-01-20T00:00:00Z
---

# Contradictions and Tensions Log

## CT-01: Vertical vs Horizontal Slice Trade-off

**Nature:** Interpretation conflict
**Sources:** S01, S02, Visual Paradigm, practitioner discussions

**Tension:**
- Vertical slicing is strongly preferred for value delivery and risk reduction
- BUT horizontal slicing has legitimate uses when:
  - Extensive layer setup is needed (sprint 0 architecture)
  - Interactions between layers are very clear and well-understood
  - Specialist skills can be leveraged

**Resolution:**
- Vertical slice is DEFAULT strategy
- Horizontal slice permitted for infrastructure/foundational work ONLY
- Hybrid approach: horizontal base layer + vertical slices on top
- Document as algorithm option, not contradiction

---

## CT-02: INVEST Independence vs Small Trade-off

**Nature:** Methodological tension
**Sources:** S04, S05

**Tension:**
"The INVEST criteria are competing, so you can never fully reach all of them simultaneously; you must make tradeoffs. For example, 'independence' is often adverse to 'small'."

**Resolution:**
- Acknowledge as inherent trade-off in the algorithm
- Prioritize: Valuable > Independent > Small > other criteria
- Small can be sacrificed if it would break independence
- Flag for human review when criteria conflict

---

## CT-03: LLM Capability vs Reliability

**Nature:** Data disagreement
**Sources:** S06, S16, S17

**Tension:**
- LLMs show high capability (89% code generation accuracy)
- BUT practitioners reject full autonomy (0% for analysis/validation)
- 58.2% use AI, but only 5.4% full automation

**Resolution:**
- Evidence clearly supports Human-AI Collaboration model
- LLMs suitable for: draft generation, pattern matching, initial analysis
- Humans required for: validation, edge cases, stakeholder decisions
- Build system with mandatory human checkpoints

---

## CT-04: Formal Research vs Practitioner Evidence

**Nature:** Methodological gap
**Sources:** Multiple searches

**Tension:**
- Limited formal empirical studies comparing decomposition strategies
- Rich practitioner guidance and experience documentation
- "Practitioner evidence" dominates over "statistical evidence"

**Resolution:**
- Weight practitioner consensus when 3+ independent sources agree
- Note absence of formal studies in limitations
- Design system to be adaptable as better evidence emerges
- Treat recommendations as "best current practice" not "proven optimal"

---

## CT-05: Automation Precision vs Coverage

**Nature:** Technical limitation
**Sources:** S16, S17

**Tension:**
- Automated NLP can identify explicit components well
- BUT struggles with implied relationships
- Creates false positives (over-identification) and false negatives (missed implications)

**Resolution:**
- Use LLM for initial decomposition draft
- Require human review for dependency relationships
- Build confidence scoring into algorithm
- Set threshold for automatic vs manual review
