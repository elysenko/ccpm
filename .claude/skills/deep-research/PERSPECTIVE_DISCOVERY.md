# Perspective Discovery Enhancement for /dr

## Overview

This document describes the **Perspective Discovery** phase to be added to the deep-research agent. This is adapted from Stanford's STORM methodology and addresses a key deficit: generating subquestions from a single perspective misses important research angles.

## The Problem

Current Phase 2 (Retrieval Planning) generates "3-7 subquestions that cover the whole scope" but does so from a single implicit perspective (the researcher). This leads to:

1. **Blind spots**: Questions a domain expert would ask but a generalist wouldn't think of
2. **Homogeneous framing**: All questions come from similar angle
3. **Missing stakeholders**: Regulatory, ethical, practical perspectives often overlooked
4. **Shallow coverage**: Surface-level breadth without expert-depth on critical aspects

## The Solution: Phase 1.6 Perspective Discovery

Insert between Phase 1.5 (Hypothesis Formation) and Phase 2 (Retrieval Planning).

---

## Phase 1.6: Perspective Discovery

### Purpose

Before generating subquestions, identify the diverse expert perspectives that would have meaningful, distinct views on this research topic. Then generate subquestions FROM each perspective.

### Step 1: Identify Related Well-Researched Topics

**Prompt template:**
```
Given the research question: "[RESEARCH_QUESTION]"

What are 3-5 related topics or questions that have been extensively researched or written about? These should be adjacent topics where established expertise exists.

For example:
- If researching "autonomous vehicle liability" → related: product liability law, aviation accident investigation, medical device regulation
- If researching "LLM hallucination" → related: knowledge graph grounding, fact-checking systems, calibration in ML

List related topics that might offer transferable frameworks or expert perspectives.
```

**Output:** List of 3-5 related domains with established expertise

### Step 2: Discover Expert Perspectives

**Prompt template:**
```
For the research question: "[RESEARCH_QUESTION]"

Identify 4-6 distinct expert perspectives that would have meaningfully DIFFERENT views, concerns, or questions about this topic.

For each perspective, specify:
1. **Role/Title**: Who is this expert? (e.g., "Regulatory Compliance Officer", "Academic Researcher", "Industry Practitioner")
2. **Primary Concern**: What do they care most about?
3. **Unique Angle**: What would they ask that others wouldn't?
4. **Potential Blind Spots**: What might they overlook?

Requirements:
- Perspectives must be DISTINCT (not just different job titles for same viewpoint)
- Include at least one "adversarial" perspective (critic, skeptic, regulator)
- Include at least one "practical" perspective (implementer, end-user, operator)
- Avoid generic perspectives like "general public" unless specifically relevant

Example for "Should we adopt microservices architecture?":
1. **Platform Architect** - Cares about: system resilience, scalability. Asks: "What are the failure modes?"
2. **DevOps Engineer** - Cares about: operational complexity, deployment. Asks: "How do we debug distributed traces?"
3. **Finance/CFO** - Cares about: infrastructure costs, team scaling. Asks: "What's the TCO vs monolith?"
4. **Security Auditor** - Cares about: attack surface, compliance. Asks: "How do we secure service-to-service auth?"
5. **Junior Developer** - Cares about: learning curve, productivity. Asks: "How long until team is productive?"
```

**Output:** 4-6 named perspectives with their concerns and unique angles

### Step 3: Generate Perspective-Specific Questions

**Prompt template:**
```
For each identified perspective, generate 2-3 questions they would ask about: "[RESEARCH_QUESTION]"

Requirements:
- Questions must reflect that perspective's PRIMARY CONCERN
- Questions should be ones a GENERALIST researcher might not think to ask
- Avoid generic questions any perspective would ask
- Flag if a question overlaps with another perspective (consolidate later)

Format:
## [Perspective Name]
Primary concern: [X]

Questions:
1. [Question that reflects their expertise/concern]
2. [Question that reflects their expertise/concern]
3. [Optional third question]

Rationale: Why would this perspective ask these specific questions?
```

**Output:** 8-18 perspective-specific questions (2-3 per perspective)

### Step 4: Consolidate into Research Subquestions

**Prompt template:**
```
Given these perspective-specific questions:
[LIST ALL QUESTIONS FROM STEP 3]

Consolidate into 5-9 research subquestions that:
1. Cover all major perspectives (no perspective should be completely unrepresented)
2. Eliminate redundancy (merge overlapping questions)
3. Maintain distinct angles (don't homogenize into generic questions)
4. Are answerable through research (not opinion-only questions)

For each consolidated subquestion, note:
- Which perspectives it addresses
- Why it's distinct from other subquestions

Output format:
| # | Subquestion | Perspectives Addressed | Distinct Because |
|---|-------------|----------------------|------------------|
| 1 | [Question]  | [Perspective A, B]   | [Why unique]     |
```

**Output:** 5-9 consolidated subquestions with perspective mapping

---

## Integration with Existing Phases

### Before (Current Flow)
```
Phase 1.5: Hypothesis Formation
    ↓
Phase 2: Retrieval Planning (generates 3-7 subquestions)
```

### After (With Perspective Discovery)
```
Phase 1.5: Hypothesis Formation
    ↓
Phase 1.6: Perspective Discovery
    Step 1: Find related well-researched topics
    Step 2: Identify 4-6 expert perspectives
    Step 3: Generate perspective-specific questions
    Step 4: Consolidate into subquestions
    ↓
Phase 2: Retrieval Planning (uses perspective-informed subquestions)
```

---

## Gate Criteria

**Phase 1.6 PASSES when:**
1. At least 4 distinct perspectives identified
2. At least one adversarial/critical perspective included
3. At least one practical/implementation perspective included
4. Each perspective has 2+ unique questions
5. Consolidated subquestions cover all perspectives (no orphans)
6. No two subquestions are >70% overlapping

**Phase 1.6 FAILS when:**
- Perspectives are superficially different (same viewpoint, different titles)
- All questions are generic (any perspective would ask them)
- Critical perspectives missing (no skeptic/regulator/critic)

---

## Outputs

Add to `./RESEARCH/[project_name]/`:

```
01a_perspectives.md
```

### Format:
```markdown
# Perspective Discovery

## Research Question
[The scoped research question from Phase 1]

## Related Domains
1. [Domain 1] - Relevance: [why]
2. [Domain 2] - Relevance: [why]
3. [Domain 3] - Relevance: [why]

## Expert Perspectives

### Perspective 1: [Role/Title]
- **Primary Concern**: [What they care about]
- **Unique Angle**: [What they'd ask that others wouldn't]
- **Potential Blind Spots**: [What they might miss]
- **Questions**:
  1. [Question 1]
  2. [Question 2]

### Perspective 2: [Role/Title]
[...]

## Consolidated Subquestions

| # | Subquestion | Perspectives | Distinct Because |
|---|-------------|--------------|------------------|
| 1 | [...]       | [...]        | [...]            |

## Perspective Coverage Matrix

| Perspective | Subquestions Addressing | Coverage |
|-------------|------------------------|----------|
| [Name]      | 1, 3, 5                | Good     |
| [Name]      | 2, 4                   | Good     |
```

---

## Example: "Should enterprise adopt LLM agents for customer support?"

### Step 2 Output: Perspectives

1. **Customer Experience Director**
   - Primary concern: Customer satisfaction, resolution rates, brand perception
   - Unique angle: "What happens when the agent fails mid-conversation?"
   - Blind spots: May overlook cost/technical feasibility

2. **IT Security Officer**
   - Primary concern: Data leakage, prompt injection, compliance
   - Unique angle: "How do we prevent PII exposure in agent responses?"
   - Blind spots: May over-index on risk vs. business value

3. **Contact Center Operations Manager**
   - Primary concern: Staffing, training, human-AI handoff, metrics
   - Unique angle: "How do we handle escalation when agent confidence is low?"
   - Blind spots: May focus on operational efficiency over customer experience

4. **Legal/Compliance Counsel**
   - Primary concern: Liability, regulatory requirements, audit trails
   - Unique angle: "Who is liable when the agent gives incorrect advice?"
   - Blind spots: May not understand technical capabilities/limitations

5. **Front-line Support Agent (Human)**
   - Primary concern: Job security, workload, tool usability
   - Unique angle: "Will this make my job harder or easier?"
   - Blind spots: May resist change regardless of merit

### Step 4 Output: Consolidated Subquestions

| # | Subquestion | Perspectives | Distinct Because |
|---|-------------|--------------|------------------|
| 1 | What are documented failure modes of LLM agents in customer support, and what is customer reaction to failures? | CX Director, Ops Manager | Focuses on failure experience, not just accuracy |
| 2 | What security risks (data leakage, prompt injection) exist and what mitigations are proven effective? | Security Officer | Technical security focus |
| 3 | What is the legal/regulatory landscape for AI-generated customer advice, and who bears liability? | Legal Counsel | Liability and compliance focus |
| 4 | How do successful deployments handle human-AI handoff and escalation? | Ops Manager, CX Director | Operational integration focus |
| 5 | What is the impact on human agent roles, and what change management approaches work? | Front-line Agent, Ops Manager | Human workforce impact |
| 6 | What is the realistic cost-benefit analysis including hidden costs (training, errors, oversight)? | All | Quantitative business case |
| 7 | What do critics and failed deployments reveal about limitations? | Adversarial (implied) | Counter-evidence focus |

---

## Cost Estimate

Phase 1.6 adds approximately:
- 4 additional LLM calls (Steps 1-4)
- ~2,000-4,000 additional tokens input
- ~1,500-3,000 additional tokens output

This is <5% overhead on a typical deep research task but significantly improves subquestion quality and coverage.

---

## Modification to deep-research.md

Add after line 145 (end of Phase 1.5) and before line 148 (Phase 2):

```markdown
## Phase 1.6: Perspective Discovery

**Purpose**: Identify diverse expert perspectives before generating subquestions to ensure comprehensive coverage and avoid single-perspective blind spots.

### Steps

1. **Find Related Domains**: Identify 3-5 well-researched adjacent topics
2. **Discover Perspectives**: Identify 4-6 distinct expert viewpoints with different concerns
3. **Generate Perspective Questions**: 2-3 questions per perspective reflecting their unique angle
4. **Consolidate**: Merge into 5-9 research subquestions covering all perspectives

### Requirements

- At least 4 distinct perspectives (not just different titles for same viewpoint)
- Must include one adversarial perspective (critic, skeptic, regulator)
- Must include one practical perspective (implementer, operator, end-user)
- Each perspective must have 2+ unique questions
- Consolidated subquestions must cover all perspectives

### Outputs
- `01a_perspectives.md`

**Gate**: PASS only if all perspectives have coverage in final subquestions and no perspective is orphaned.
```

Update Phase 2 opening to reference perspective-informed subquestions:

```markdown
## Phase 2: Retrieval Planning

### Inputs
- Research contract (Phase 1)
- Hypotheses (Phase 1.5)
- **Perspective-informed subquestions (Phase 1.6)**
```
