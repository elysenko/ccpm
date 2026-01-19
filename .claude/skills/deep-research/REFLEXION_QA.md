# Reflexion Enhancement for /dr Quality Assurance

## Overview

This document describes the **Reflexion** enhancement for Phase 6 QA. Instead of a simple checklist that flags issues, Reflexion adds explicit failure analysis, self-correction loops, and learning across research projects.

## The Problem

Current Phase 6 QA is a **checklist**:
```
1. Run citation audit → find issues
2. Run claim coverage check → find issues
3. Run numeric audit → find issues
4. Flag issues in limitations section
5. Done
```

Issues with this approach:
1. **No root cause analysis**: Issues are flagged but not analyzed
2. **No structured fix process**: Fixes are ad-hoc, not systematic
3. **No learning**: Same mistakes repeat across research projects
4. **Single pass**: If fixes introduce new issues, they may not be caught
5. **No self-critique**: Agent doesn't reflect on WHY errors occurred

## The Solution: Reflexion-Based QA

Reflexion transforms QA from "find and flag" to "find, analyze, fix, verify, learn":

```
┌─────────────────────────────────────────────────────────────────┐
│                    REFLEXION QA LOOP                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │  ATTEMPT │───▶│ EVALUATE │───▶│ REFLECT  │───▶│  RETRY   │  │
│  │          │    │          │    │          │    │          │  │
│  │ Generate │    │ Run QA   │    │ Analyze  │    │ Fix with │  │
│  │ report   │    │ checks   │    │ failures │    │ reflection│  │
│  └──────────┘    └────┬─────┘    └──────────┘    └─────┬─────┘  │
│                       │                                │        │
│                       │         ┌──────────┐          │        │
│                       └────────▶│  PASS?   │◀─────────┘        │
│                                 └────┬─────┘                    │
│                                      │                          │
│                              ┌───────┴───────┐                  │
│                              │               │                  │
│                              ▼               ▼                  │
│                         ┌────────┐     ┌──────────┐            │
│                         │  DONE  │     │ MAX      │            │
│                         │        │     │ RETRIES? │            │
│                         └────────┘     └────┬─────┘            │
│                                             │                   │
│                                             ▼                   │
│                                    ┌─────────────┐             │
│                                    │ ESCALATE    │             │
│                                    │ (manual     │             │
│                                    │  review)    │             │
│                                    └─────────────┘             │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │               REFLECTION MEMORY                          │   │
│  │  Persists across research projects for continuous        │   │
│  │  improvement. Stores failure patterns and fixes.         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Failure Taxonomy

Categorize QA failures for targeted reflection:

| Category | Code | Examples | Typical Root Cause |
|----------|------|----------|-------------------|
| **Citation Drift** | CD | Citation doesn't support claim | Paraphrasing went too far; source misread |
| **Missing Evidence** | ME | C1 claim lacks required evidence | Rushed synthesis; evidence not indexed |
| **Independence Violation** | IV | Multiple citations trace to same source | Didn't check citation lineage |
| **Numeric Error** | NE | Wrong unit, denominator, timeframe | Copy error; didn't normalize |
| **Scope Creep** | SC | Content outside defined scope | Lost focus during synthesis |
| **Scope Gap** | SG | Major topic not covered | Subquestions missed it; retrieval gap |
| **Confidence Mismatch** | CM | High confidence without strong evidence | Overconfident language |
| **Hallucination** | HL | Claim not in any source | Generated without grounding |
| **Contradiction** | CT | Report contradicts itself | Different sources, not reconciled |
| **Stale Data** | SD | Outdated information presented as current | Didn't check publication dates |

---

## Reflection Prompt Templates

### Template 1: Failure Analysis

```
## QA Failure Analysis

The following issues were found in the research report:

### Issue 1: [CATEGORY CODE] - [BRIEF DESCRIPTION]
- **Location**: [Section/paragraph where issue occurs]
- **Specific problem**: [What exactly is wrong]
- **Evidence**: [What the QA check found]

[Repeat for each issue]

---

## Reflection Questions

For each issue, analyze:

1. **ROOT CAUSE**: Why did this error occur?
   - Was it a retrieval failure (didn't find the right source)?
   - Was it a synthesis failure (misread or misinterpreted source)?
   - Was it a verification failure (didn't check claim against source)?
   - Was it a process failure (skipped a step)?

2. **PATTERN**: Have I made this type of error before?
   - Check reflection_memory.json for similar past failures
   - Is this a recurring weakness?

3. **PREVENTION**: What should I have done differently?
   - What checkpoint would have caught this?
   - What habit would prevent this?

4. **FIX**: How specifically will I fix this instance?
   - What needs to change in the report?
   - What additional research is needed (if any)?

---

## Reflection Output

For each issue, provide:

```json
{
  "issue_id": "QA-001",
  "category": "CD",
  "location": "Section 3.2, paragraph 4",
  "problem": "Claim states 40% improvement but source says 'up to 40% in ideal conditions'",
  "root_cause": "synthesis_failure",
  "root_cause_detail": "Dropped qualifier 'up to' and 'in ideal conditions' during paraphrase",
  "pattern_match": "Similar to QA-2024-127 (dropped qualifiers)",
  "prevention": "Always preserve qualifiers and conditions when citing statistics",
  "fix_action": "Revise to: 'up to 40% improvement under ideal conditions'",
  "fix_type": "text_revision",
  "confidence_in_fix": "high"
}
```
```

### Template 2: Fix Execution

```
## Executing Fixes with Reflection Context

I am fixing the following issues based on my reflection analysis:

### Fix 1: [ISSUE_ID]
- **Original text**: "[exact text from report]"
- **Problem identified**: [from reflection]
- **Root cause**: [from reflection]
- **Fix action**: [from reflection]
- **Revised text**: "[new text]"
- **Verification**: [How I confirmed this fix is correct]

### Self-Check Before Committing Fix:
- [ ] Fix addresses the root cause, not just the symptom
- [ ] Fix doesn't introduce new issues
- [ ] Fix is consistent with rest of report
- [ ] Fix maintains appropriate confidence level
- [ ] Source actually supports the revised claim

[Repeat for each fix]
```

### Template 3: Post-Fix Verification

```
## Post-Fix Verification

After applying fixes, re-run QA checks on modified sections:

### Re-Check Results

| Issue ID | Original Problem | Fix Applied | Re-Check Status | Notes |
|----------|------------------|-------------|-----------------|-------|
| QA-001 | Citation drift | Revised text | PASS | Now accurately reflects source |
| QA-002 | Missing evidence | Added citation | PASS | Found supporting passage |
| QA-003 | Numeric error | Corrected unit | FAIL | New issue: date mismatch |

### New Issues Introduced
[List any new issues found after fixes]

### Resolution
[How new issues will be addressed - may trigger another reflection cycle]
```

---

## Reflection Memory

Persist learnings across research projects:

### File: `~/.claude/reflection_memory.json`

```json
{
  "version": "1.0",
  "last_updated": "2026-01-19",
  "failure_patterns": [
    {
      "pattern_id": "FP-001",
      "category": "CD",
      "description": "Dropping qualifiers when citing statistics",
      "frequency": 7,
      "first_seen": "2025-09-15",
      "last_seen": "2026-01-19",
      "prevention_rule": "Always preserve: 'up to', 'approximately', 'under X conditions', 'in Y contexts'",
      "example_failures": ["QA-2024-127", "QA-2024-189", "QA-2025-012"]
    },
    {
      "pattern_id": "FP-002",
      "category": "IV",
      "description": "News articles citing same press release counted as independent",
      "frequency": 4,
      "first_seen": "2025-10-22",
      "last_seen": "2026-01-10",
      "prevention_rule": "For breaking news, trace all articles to original source before counting independence",
      "example_failures": ["QA-2024-201", "QA-2025-003"]
    },
    {
      "pattern_id": "FP-003",
      "category": "NE",
      "description": "Mixing fiscal year and calendar year data",
      "frequency": 3,
      "first_seen": "2025-11-05",
      "last_seen": "2026-01-15",
      "prevention_rule": "Always note FY vs CY; normalize to consistent timeframe or flag explicitly",
      "example_failures": ["QA-2024-245", "QA-2025-008"]
    }
  ],
  "prevention_checklist": [
    "Preserve all statistical qualifiers (up to, approximately, under conditions)",
    "Trace news articles to original source for independence check",
    "Verify fiscal year vs calendar year alignment",
    "Check publication date against 'current' claims",
    "Confirm units match when combining data from multiple sources"
  ],
  "stats": {
    "total_failures_logged": 47,
    "most_common_category": "CD",
    "improvement_trend": "23% reduction in CD failures over last 10 projects"
  }
}
```

### Using Reflection Memory

At the START of Phase 6 QA:

```
## Loading Reflection Memory

Before running QA checks, review past failure patterns:

**Most Common Failures (last 10 projects):**
1. Citation Drift (CD): 12 occurrences - especially dropping qualifiers
2. Independence Violation (IV): 6 occurrences - news articles from same source
3. Numeric Error (NE): 4 occurrences - FY/CY confusion

**Prevention Checklist to Apply:**
- [ ] Check all statistics for preserved qualifiers
- [ ] Verify independence of news sources
- [ ] Confirm timeframe alignment (FY vs CY)

**High-Risk Patterns for THIS Research:**
[Based on topic, identify which failure patterns are most likely]
```

---

## Integration with Phase 6

### Modified Phase 6 Flow

```
Phase 6: Quality Assurance (Reflexion-Enhanced)

STEP 1: LOAD REFLECTION MEMORY
- Read ~/.claude/reflection_memory.json
- Identify high-risk patterns for this research topic
- Generate pre-QA checklist from past learnings

STEP 2: RUN QA CHECKS (existing)
- Citation match audit
- Passage-level citation verification
- Claim coverage
- Numeric audit
- Scope audit
- Uncertainty labeling

STEP 3: REFLECT ON FAILURES (new)
- Categorize each failure by type
- Analyze root cause
- Check for pattern matches
- Generate fix plan with rationale

STEP 4: EXECUTE FIXES (new)
- Apply fixes with reflection context
- Document what changed and why
- Self-check before committing

STEP 5: VERIFY FIXES (new)
- Re-run QA on modified sections
- Check for introduced issues
- If new issues: return to STEP 3 (max 3 cycles)

STEP 6: UPDATE REFLECTION MEMORY (new)
- Log new failure patterns
- Update frequency counts
- Add to prevention checklist if novel

STEP 7: FINALIZE
- Document unresolved issues in limitations
- Generate QA summary with reflection insights
```

### Gate Criteria (Updated)

**Phase 6 PASSES when:**
- All "red" issues resolved OR escalated with justification
- Maximum 3 reflection cycles completed
- No HIGH severity issues remain unfixed
- Reflection memory updated with learnings

**Phase 6 FAILS when:**
- HIGH severity issues remain after 3 fix cycles
- Fixes introduced more issues than they resolved
- Root cause analysis reveals systematic process failure

---

## Output Artifacts

### New File: `09_qa/reflection_log.md`

```markdown
# QA Reflection Log

## Research Project: [PROJECT_NAME]
## Date: [DATE]

---

## Reflection Memory Loaded

**Past patterns checked:**
- FP-001: Dropping qualifiers (7 past occurrences)
- FP-002: News independence (4 past occurrences)
- FP-003: FY/CY confusion (3 past occurrences)

**Pre-QA risk assessment:**
This research involves financial data → HIGH risk for FP-003 (FY/CY)
This research involves recent news → MEDIUM risk for FP-002 (independence)

---

## QA Cycle 1

### Issues Found: 4

| ID | Category | Location | Problem | Severity |
|----|----------|----------|---------|----------|
| QA-001 | CD | Section 3.2 | Dropped "up to" qualifier | MEDIUM |
| QA-002 | NE | Section 4.1 | Mixed FY2025 and CY2025 data | HIGH |
| QA-003 | ME | Section 5.3 | C1 claim lacks second source | HIGH |
| QA-004 | CM | Section 2.1 | "Clearly shows" but only one study | LOW |

### Reflections

**QA-001 (Citation Drift)**
- Root cause: Synthesis failure - compressed quote lost qualifier
- Pattern match: YES - FP-001 (7th occurrence of this pattern)
- Prevention: Should have flagged "up to" during passage extraction
- Fix: Restore qualifier in text
- Confidence: HIGH

**QA-002 (Numeric Error)**
- Root cause: Process failure - didn't normalize timeframes
- Pattern match: YES - FP-003 (4th occurrence)
- Prevention: Should have standardized all dates to CY during extraction
- Fix: Convert FY2025 figures to CY equivalent OR note discrepancy
- Confidence: MEDIUM (need to verify conversion)

**QA-003 (Missing Evidence)**
- Root cause: Retrieval failure - second source exists but wasn't found
- Pattern match: NO - novel failure
- Prevention: Should have verified independence requirement during synthesis
- Fix: Search for additional source OR downgrade claim confidence
- Confidence: MEDIUM

**QA-004 (Confidence Mismatch)**
- Root cause: Language choice - used definitive language without warrant
- Pattern match: NO - novel failure
- Prevention: Flag definitive language ("clearly", "proves", "definitely") for review
- Fix: Soften to "suggests" or "indicates"
- Confidence: HIGH

### Fixes Applied

[Details of each fix with before/after text]

---

## QA Cycle 2

### Re-Check Results

| ID | Original Status | After Fix | Notes |
|----|-----------------|-----------|-------|
| QA-001 | FAIL | PASS | Qualifier restored |
| QA-002 | FAIL | PASS | Added FY/CY note |
| QA-003 | FAIL | PASS | Found second source |
| QA-004 | FAIL | PASS | Language softened |

### New Issues: 0

---

## Reflection Memory Updates

**New pattern added:** None (all matched existing)

**Frequency updates:**
- FP-001: 7 → 8
- FP-003: 3 → 4

**Prevention checklist addition:**
- "Flag definitive language (clearly, proves, definitely) for evidence check"

---

## Final Status: PASS

- Cycles completed: 2
- Issues resolved: 4/4
- New patterns logged: 0
- Prevention rules added: 1
```

---

## Modifications to deep-research.md

### Replace existing Phase 6 content with:

```markdown
## Phase 6: Quality Assurance (Reflexion-Enhanced)

### Overview

Phase 6 uses **Reflexion** - a self-correction methodology that goes beyond checklists to analyze failures, learn from patterns, and systematically improve.

### Step 1: Load Reflection Memory

Before running QA, load learnings from past research:

```
Read: ~/.claude/reflection_memory.json

Identify:
- Most common failure patterns
- Patterns relevant to THIS research topic
- Prevention checklist items to apply
```

### Step 2: Run QA Checks

Execute all mandatory checks:

1. **Citation match audit**: Citation supports the sentence (no drift)
2. **Passage-level verification**: Retrieved passage actually supports claim
3. **Claim coverage**: Every C1 has required evidence + independence
4. **Numeric audit**: Units, denominators, timeframe, currency normalization
5. **Scope audit**: Nothing out-of-scope; no major gaps
6. **Uncertainty labeling**: Weak evidence is labeled appropriately

### Step 3: Reflect on Failures

For each issue found, analyze:

| Question | Purpose |
|----------|---------|
| **What category?** | CD, ME, IV, NE, SC, SG, CM, HL, CT, SD |
| **Root cause?** | Retrieval / Synthesis / Verification / Process failure |
| **Pattern match?** | Does this match a known failure pattern? |
| **Prevention?** | What should have caught this earlier? |
| **Fix plan?** | Specific action to resolve |

**Reflection Prompt:**
```
Issue: [DESCRIPTION]
Location: [WHERE IN REPORT]

1. ROOT CAUSE: Why did this error occur?
2. PATTERN: Have I made this mistake before? (Check reflection_memory.json)
3. PREVENTION: What checkpoint would have caught this?
4. FIX: How specifically will I fix this?
```

### Step 4: Execute Fixes

Apply fixes with reflection context:

```
Original: "[exact original text]"
Problem: [from reflection]
Root cause: [from reflection]
Fix: "[revised text]"
Verification: [how I confirmed fix is correct]

Self-check:
- [ ] Fix addresses root cause, not just symptom
- [ ] Fix doesn't introduce new issues
- [ ] Fix is consistent with rest of report
- [ ] Source actually supports revised claim
```

### Step 5: Verify Fixes

Re-run QA checks on modified sections:

- If all pass → proceed to Step 6
- If new issues → return to Step 3 (max 3 cycles)
- If stuck after 3 cycles → escalate to manual review

### Step 6: Update Reflection Memory

Log learnings for future research:

```
Update ~/.claude/reflection_memory.json:
- Add new failure patterns (if novel)
- Increment frequency for matched patterns
- Add prevention rules discovered
- Update statistics
```

### Step 7: Finalize

- Document unresolved issues in limitations section
- Generate `09_qa/reflection_log.md`
- Mark Phase 6 complete

### Outputs

- `09_qa/qa_report.md` - Standard QA results
- `09_qa/citation_audit.md` - Citation verification details
- `09_qa/reflection_log.md` - **NEW**: Failure analysis and learnings
- Updated `~/.claude/reflection_memory.json` - **NEW**: Cross-project learnings

### Gate Criteria

**PASS when:**
- All HIGH severity issues resolved
- Maximum 3 reflection cycles completed
- Reflection memory updated
- Remaining issues documented in limitations

**FAIL when:**
- HIGH severity issues remain after 3 cycles
- Fixes introduced more issues than resolved
- Systematic process failure identified (requires process change, not just fixes)

### Failure Categories Reference

| Code | Category | Description |
|------|----------|-------------|
| CD | Citation Drift | Citation doesn't support claim as stated |
| ME | Missing Evidence | C1 claim lacks required evidence |
| IV | Independence Violation | Sources trace to same origin |
| NE | Numeric Error | Unit, denominator, or timeframe error |
| SC | Scope Creep | Content outside defined scope |
| SG | Scope Gap | Major topic not covered |
| CM | Confidence Mismatch | Confidence level doesn't match evidence strength |
| HL | Hallucination | Claim not grounded in any source |
| CT | Contradiction | Report contradicts itself |
| SD | Stale Data | Outdated info presented as current |
```

---

## Bootstrap: Initial Reflection Memory

For first-time use, create `~/.claude/reflection_memory.json`:

```json
{
  "version": "1.0",
  "last_updated": "2026-01-19",
  "failure_patterns": [],
  "prevention_checklist": [
    "Preserve statistical qualifiers (up to, approximately, under conditions)",
    "Verify source independence (trace news to original)",
    "Check fiscal year vs calendar year alignment",
    "Confirm publication date for 'current' claims",
    "Match units when combining multi-source data",
    "Flag definitive language for evidence check"
  ],
  "stats": {
    "total_failures_logged": 0,
    "most_common_category": null,
    "improvement_trend": null
  }
}
```

---

## Expected Impact

| Metric | Before (Checklist) | After (Reflexion) |
|--------|-------------------|-------------------|
| Issue detection | Same | Same |
| Root cause identified | Rarely | Always |
| Fix quality | Variable | Systematic |
| Repeat errors | Common | Decreasing |
| Cross-project learning | None | Continuous |
| QA documentation | Minimal | Comprehensive |
