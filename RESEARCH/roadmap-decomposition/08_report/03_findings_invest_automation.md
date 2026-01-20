# Findings: INVEST Automation and Sizing Heuristics

## SQ2: How can INVEST principles be converted to automatable heuristics?

### INVEST Framework Overview

**Evidence Grade: A (Agile Alliance + IEEE Research)**

Bill Wake developed INVEST in 2003 to define criteria for good user stories. The acronym represents:

| Criterion | Definition | Automation Potential |
|-----------|------------|---------------------|
| **I**ndependent | Story doesn't rely on other stories | HIGH - Dependency analysis |
| **N**egotiable | May evolve through conversation | LOW - Inherently human |
| **V**aluable | Meets actual user need | MEDIUM - Value keyword detection |
| **E**stimable | Team can estimate relative size | MEDIUM - Complexity analysis |
| **S**mall | Completable in short time window | HIGH - Size metrics |
| **T**estable | Clear acceptance criteria exist | HIGH - Pattern matching |

### Critical Insight: Competing Criteria

"The INVEST criteria are competing, so you can never fully reach all of them simultaneously; you must make tradeoffs. For example, 'independence' is often adverse to 'small'."

**Implication for Automation:** System must handle trade-offs, not optimize all criteria equally.

---

## Automatable Heuristics by Criterion

### I - Independence (HIGH automation potential)

**Detection Methods:**
1. **Keyword scanning:** "depends on", "requires", "after", "when X is complete"
2. **Entity co-reference:** Same data entity mentioned in multiple PRDs
3. **Temporal markers:** "before", "first", "then", "following"
4. **API/interface references:** Shared service/endpoint mentions

**Scoring:**
```
independence_score = 1.0 - (dependency_count / total_prds)
THRESHOLD: > 0.8 = good, < 0.5 = requires re-slicing
```

### N - Negotiable (LOW automation potential)

**Why Low:** This criterion reflects the ability for requirements to evolve through conversation—inherently human.

**Partial Automation:**
- Flag overly prescriptive language ("must use X technology", "exactly Y fields")
- Detect solution-specification vs. problem-specification language
- Suggest rephrasing implementation details as acceptance criteria

### V - Valuable (MEDIUM automation potential)

**Detection Methods:**
1. **User role presence:** "As a [user type]" pattern
2. **Value keywords:** "can", "able to", "enables", "allows"
3. **Outcome focus:** Action verbs + benefit statements
4. **Anti-pattern:** Technical jargon without user context

**Scoring:**
```
value_score = (has_user_role * 0.3) + (has_outcome * 0.4) + (no_tech_jargon * 0.3)
THRESHOLD: > 0.6 = acceptable
```

### E - Estimable (MEDIUM automation potential)

**Detection Methods:**
1. **Ambiguity count:** Vague terms ("easy", "fast", "secure", "flexible")
2. **Scope clarity:** Bounded vs. open-ended language
3. **Unknown markers:** "TBD", "to be determined", question marks
4. **Complexity indicators:** Conditional logic count, integration points

**Scoring:**
```
estimability_score = 1.0 - (ambiguity_count * 0.1) - (unknowns * 0.2) - (unbounded_scope * 0.3)
THRESHOLD: > 0.7 = estimable
```

### S - Small (HIGH automation potential)

**Detection Methods:**
1. **Word count:** PRD body text length
2. **Acceptance criteria count:** More than 7-10 suggests too large
3. **Feature count:** Multiple distinct features in one PRD
4. **Time markers:** Duration estimates if present

**Sizing Rules (from literature):**
- User stories should average 3-4 days of work (in 2-week iterations)
- 6-10 stories should be completable in a sprint
- If > 10 acceptance criteria, consider splitting

**Scoring:**
```
size_score = 1.0 - max(0, (acceptance_criteria - 7) * 0.1) - max(0, (word_count - 500) * 0.001)
THRESHOLD: > 0.6 = appropriately sized
```

### T - Testable (HIGH automation potential)

**Detection Methods:**
1. **Acceptance criteria presence:** Must have defined criteria
2. **Criteria quality:** Follows Given-When-Then or similar pattern
3. **Measurable outcomes:** Contains quantifiable success metrics
4. **Deterministic:** Predictable input → output relationships

**IEEE 830 Testability Requirements:**
- Deterministic: Given inputs, outputs are predictable
- Unambiguous: Single interpretation by all readers
- Correct: Cause-effect relationships accurate
- Complete: No omissions

**Scoring:**
```
testability_score = (has_criteria * 0.4) + (criteria_structured * 0.3) + (measurable_outcomes * 0.3)
THRESHOLD: > 0.7 = testable
```

---

## Quality Metrics from IEEE Standards

**Evidence Grade: B (IEEE 830, ISO/IEC/IEEE 29148)**

### Requirement Quality Attributes

| Attribute | Definition | Measurable |
|-----------|------------|-----------|
| Clear | Unambiguous functional meaning | YES - NLP ambiguity detection |
| Concise | No extraneous content | YES - Word economy ratio |
| Complete | All functional steps included | PARTIAL - Checklist coverage |
| Consistent | Names consistent throughout | YES - Entity extraction |
| Measurable | Can be sized in function points | YES - COSMIC sizing |
| Testable | Acceptance criteria exist | YES - Pattern matching |
| Valuable | Necessary for user capabilities | PARTIAL - Value language |
| Design-free | Excludes implementation "how" | YES - Tech term detection |

### Quantitative Metrics

1. **Clarity Score:** Frequency of ambiguous terms (lower = better)
2. **Requirement Coverage:** Goals/needs mapped to requirements
3. **Traceability Index:** Links to design, test cases, objectives

---

## Composite INVEST Score Algorithm

```python
def calculate_invest_score(prd):
    scores = {
        'independent': check_independence(prd),    # 0-1
        'negotiable': check_negotiability(prd),    # 0-1
        'valuable': check_value(prd),              # 0-1
        'estimable': check_estimability(prd),      # 0-1
        'small': check_size(prd),                  # 0-1
        'testable': check_testability(prd)         # 0-1
    }

    # Weighted composite (based on automation confidence)
    weights = {
        'independent': 0.25,  # HIGH confidence
        'negotiable': 0.05,   # LOW confidence
        'valuable': 0.20,     # MEDIUM confidence
        'estimable': 0.15,    # MEDIUM confidence
        'small': 0.15,        # HIGH confidence
        'testable': 0.20      # HIGH confidence
    }

    composite = sum(scores[k] * weights[k] for k in scores)

    # Flag criteria conflicts
    conflicts = []
    if scores['independent'] < 0.6 and scores['small'] > 0.8:
        conflicts.append("independence-small tradeoff")

    return {
        'composite_score': composite,
        'individual_scores': scores,
        'conflicts': conflicts,
        'recommendation': 'approve' if composite > 0.7 else 'review'
    }
```

---

## Trade-off Resolution Strategy

When INVEST criteria conflict:

**Priority Order:** Valuable > Independent > Testable > Small > Estimable > Negotiable

**Rationale:**
1. **Value first:** No point in well-structured waste
2. **Independence second:** Reduces coordination overhead
3. **Testability third:** Enables quality verification
4. **Size fourth:** Can always split later if too big
5. **Estimability fifth:** Improves with conversation
6. **Negotiability last:** Inherently human, cannot automate

---

## What Would Change Our Mind

If research showed that specific INVEST violations correlate with project success (e.g., tightly coupled stories deliver faster in some contexts), we would adjust weights. Current evidence supports all criteria as generally positive.
