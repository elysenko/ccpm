# Findings: LLM Effectiveness for Requirement Analysis

## SQ4: How effective is LLM-based requirement analysis for detecting dependencies?

### Industry Adoption Reality

**Evidence Grade: A (Systematic Literature Review + Industry Survey)**

The systematic literature review of 74 primary studies (2023-2024) combined with industry surveys reveals:

| Metric | Value | Implication |
|--------|-------|-------------|
| Industry adoption | 58.2% | Majority are using AI |
| Positive perception | 69.1% | Generally well-received |
| Full automation | 5.4% | Very rare |
| Human-AI collaboration | 54.4% | Dominant pattern |
| Believe LLM can do analysis alone | 0% | Zero practitioners |

**Critical Finding:** "Full AI autonomy was mostly rejected, with only 2% believing that AI could handle elicitation independently without human intervention, while no one believed that AI could handle analysis, specification, and validation independently without human intervention."

---

## LLM Capabilities in RE

### What LLMs Do Well

1. **Elicitation Support (20% of studies)**
   - Generating initial requirement drafts
   - Extracting requirements from documents
   - Suggesting missing requirements

2. **Validation Support (20% of studies)**
   - Checking requirement consistency
   - Identifying ambiguities
   - Suggesting acceptance criteria

3. **Pattern Recognition**
   - Identifying common requirement types
   - Detecting standard business rules
   - Recognizing user story formats

### What LLMs Struggle With

1. **Implied Relationships**
   - "The model successfully identified the most explicit classes and attributes but faltered when relationships were implied rather than clearly stated."

2. **Context Understanding**
   - Domain-specific nuances
   - Organizational conventions
   - Historical decisions

3. **False Positives**
   - "The model often misclassifies irrelevant components as part of the class diagrams, contributing to false positives."

4. **Stakeholder Judgment**
   - Priority decisions
   - Trade-off resolution
   - Business value assessment

---

## Prompting Strategies

**Evidence Grade: B (Literature review)**

| Strategy | Usage | Effectiveness |
|----------|-------|---------------|
| Zero-shot | 38% | Baseline, quick results |
| Few-shot/Many-shot | 26% | Better pattern matching |
| Reasoning/Decomposition | 22% | Improved for complex tasks |
| Context-rich | 19% | Helps with domain specificity |
| Template-based | 18% | Consistent output format |
| RAG | 7% | Underexplored but promising |
| Interactive | 5% | Highest quality, most effort |

### Recommended Strategy for Decomposition

```
STRATEGY: Few-shot + Template + Reasoning

Prompt Structure:
1. System context (product management role)
2. 2-3 examples of good PRD decomposition
3. Template for output format
4. Step-by-step reasoning instructions
5. Validation checklist to self-check
```

---

## Hallucination Detection and Mitigation

**Evidence Grade: B (Multiple approaches documented)**

### The Problem
"LLMs often produce outputs that are fallacious, incorporating fictional or insubstantial details that can be partly misleading or entirely fabricated. Moreover, such model generations often seem plausible, appearing tenable before further scrutiny."

### Detection Methods

#### 1. Self-Consistency Validation
Generate multiple outputs with temperature variation. Flag inconsistencies.
```python
def self_consistency_check(prompt, n_samples=3):
    outputs = [llm.generate(prompt, temperature=0.7) for _ in range(n_samples)]
    # Compare outputs for consistency
    return calculate_consistency_score(outputs)
```

#### 2. Metamorphic Testing (MetaQA)
Apply semantic-preserving transformations. If answer changes, likely hallucination.
```python
def metamorphic_check(requirement, decomposition):
    # Rephrase requirement without changing meaning
    rephrased = llm.rephrase(requirement)
    new_decomposition = llm.decompose(rephrased)
    # Compare: should be equivalent
    return compare_decompositions(decomposition, new_decomposition)
```

#### 3. External Reference Validation
Cross-check against known patterns and domain knowledge.
```python
def reference_validation(prd):
    # Check against known PRD patterns
    pattern_match = check_prd_patterns(prd)
    # Check for impossible claims
    feasibility = check_feasibility(prd)
    return pattern_match and feasibility
```

#### 4. Confidence Scoring
Use model logits/probabilities to identify uncertain outputs.
```python
def confidence_score(output):
    # Low confidence → flag for human review
    if output.confidence < 0.7:
        return 'NEEDS_REVIEW'
    return 'AUTO_APPROVE'
```

---

## Human-AI Collaboration Model

**Evidence Grade: A (Industry consensus)**

### HARE-SM Framework (Human-AI RE Synergy Model)

```
┌─────────────────────────────────────────────────────────┐
│                    HUMAN TASKS                          │
├─────────────────────────────────────────────────────────┤
│ • Final approval of PRDs                                │
│ • Resolving ambiguities                                 │
│ • Stakeholder alignment                                 │
│ • Trade-off decisions                                   │
│ • Edge case handling                                    │
│ • Dependency validation                                 │
└─────────────────────────────────────────────────────────┘
                          ↑↓
┌─────────────────────────────────────────────────────────┐
│                 COLLABORATION ZONE                      │
├─────────────────────────────────────────────────────────┤
│ • AI suggests, human refines                            │
│ • Human provides context, AI scales                     │
│ • AI flags issues, human resolves                       │
│ • Human sets constraints, AI generates options          │
└─────────────────────────────────────────────────────────┘
                          ↑↓
┌─────────────────────────────────────────────────────────┐
│                     AI TASKS                            │
├─────────────────────────────────────────────────────────┤
│ • Initial decomposition draft                           │
│ • Pattern detection                                     │
│ • INVEST scoring                                        │
│ • Dependency graph construction                         │
│ • Anti-pattern detection                                │
│ • Format validation                                     │
└─────────────────────────────────────────────────────────┘
```

### Key Principle
"AI is most effective when positioned as a collaborative partner rather than a replacement for human expertise."

---

## Confidence Thresholds for Automation

Based on evidence, recommended automation levels:

| Confidence | Action | Rationale |
|------------|--------|-----------|
| > 0.9 | Auto-approve | High certainty |
| 0.7 - 0.9 | Light review | Quick human check |
| 0.5 - 0.7 | Full review | Human must validate |
| < 0.5 | Regenerate | Quality too low |

### Factors Affecting Confidence

1. **PRD Complexity:** More complex → lower confidence
2. **Domain Novelty:** New domain → lower confidence
3. **Dependency Count:** More dependencies → lower confidence
4. **Ambiguity Level:** Vague input → lower confidence

---

## Recommended LLM Integration

```python
class LLMDecomposer:
    def __init__(self, model, confidence_threshold=0.7):
        self.model = model
        self.threshold = confidence_threshold

    def decompose(self, roadmap_item):
        # Generate initial decomposition
        draft = self._generate_draft(roadmap_item)

        # Self-consistency check
        consistency = self._check_consistency(roadmap_item)

        # Anti-pattern check
        antipatterns = self._check_antipatterns(draft)

        # Calculate confidence
        confidence = self._calculate_confidence(
            consistency, antipatterns, draft
        )

        return {
            'prds': draft.prds,
            'dependencies': draft.dependencies,
            'confidence': confidence,
            'requires_review': confidence < self.threshold,
            'warnings': antipatterns,
            'suggestions': self._generate_suggestions(draft)
        }

    def _generate_draft(self, item):
        prompt = self._build_prompt(item)
        return self.model.generate(prompt)

    def _check_consistency(self, item):
        # Generate 3 variations, check agreement
        variations = [self._generate_draft(item) for _ in range(3)]
        return self._compare_variations(variations)

    def _check_antipatterns(self, draft):
        issues = []
        for prd in draft.prds:
            # Check each anti-pattern
            if self._is_horizontal_slice(prd):
                issues.append(('horizontal_slice', prd.id))
            if self._lacks_value(prd):
                issues.append(('no_value', prd.id))
            # ... more checks
        return issues
```

---

## What Would Change Our Mind

If future LLM models demonstrate:
1. Reliable implicit relationship detection (currently weak)
2. Consistent dependency identification (currently variable)
3. Domain adaptation without fine-tuning (currently limited)

We would increase automation thresholds. Current evidence strongly supports human-in-the-loop as mandatory.
