---
name: perspectives
created: 2026-01-20T00:00:00Z
---

# Perspective Discovery

## 6 Expert Perspectives

### 1. Product Management Perspective
**Primary Concern:** Value delivery and stakeholder alignment
**Key Questions:**
- How do we ensure each PRD delivers standalone user value?
- How do we maintain strategic alignment when decomposing?
- What happens when business priorities conflict with technical dependencies?

### 2. Software Architecture Perspective
**Primary Concern:** Technical coupling and interface boundaries
**Key Questions:**
- How do we identify shared data models and API contracts?
- What modularity principles ensure PRDs remain technically independent?
- How do we handle cross-cutting concerns (auth, logging, etc.)?

### 3. Agile/Scrum Perspective
**Primary Concern:** INVEST principles and iterative delivery
**Key Questions:**
- How do we ensure PRDs are estimable and testable?
- What sizing heuristics work across different team velocities?
- How do we balance independence with integration testing needs?

### 4. AI/LLM Orchestration Perspective
**Primary Concern:** Prompting accuracy and error handling
**Key Questions:**
- What prompting strategies yield consistent decomposition?
- How do we handle LLM hallucinations in dependency detection?
- What confidence thresholds should trigger human review?

### 5. Graph Theory/Algorithms Perspective
**Primary Concern:** DAG correctness and computational efficiency
**Key Questions:**
- What algorithms detect cycles in dependency graphs?
- How do we handle incremental DAG updates efficiently?
- What topological sort variants work best for PRD prioritization?

### 6. Skeptic/Failure Mode Perspective (Adversarial)
**Primary Concern:** What can go wrong
**Key Questions:**
- What happens when decomposition produces too many/few PRDs?
- How do hidden dependencies cause integration failures?
- What anti-patterns lead to unmaintainable PRD hierarchies?

## Perspective Coverage Matrix

| Subquestion | PM | Arch | Agile | LLM | Graph | Skeptic |
|-------------|:--:|:----:|:-----:|:---:|:-----:|:-------:|
| Decomposition strategies | ✓ | ✓ | ✓ | | | ✓ |
| INVEST automation | ✓ | | ✓ | ✓ | | ✓ |
| DAG algorithms | | ✓ | | | ✓ | ✓ |
| LLM dependency detection | | ✓ | | ✓ | | ✓ |
| Failure modes | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Enterprise practices | ✓ | ✓ | ✓ | | | |

All perspectives have at least 2 subquestions. Skeptic perspective covers all areas (adversarial requirement met).
