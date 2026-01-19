# Adaptive Query Refinement for /dr

## Overview

This document describes the **adaptive refinement** system integrated into Phase 1 of `/dr`. Instead of a rigid question list, refinement now:

1. **Classifies the query target** (web, codebase, or mixed)
2. **Does quick reconnaissance** before asking questions
3. **Selects relevant questions** based on topic and clarity score
4. **Skips irrelevant questions** to reduce user fatigue

---

## The Problem with Rigid Refinement

Old approach asked ALL 8 questions for ANY vague query:
- Geographic focus for "how does TCP work" (irrelevant)
- Citation strictness for "best pizza in Brooklyn" (absurd)
- Timeframe for "explain our auth system" (doesn't apply)

Result: User fatigue, wasted interaction, questions that don't inform research.

---

## The Solution: Adaptive Refinement

```
User: "/dr [vague query]"
       ↓
Step 0: Clarity check (score 1-20)
       ↓
┌──────────────┬──────────────┐
│ Score ≥ 12   │ Score < 12   │
│ CLEAR        │ AMBIGUOUS    │
└──────┬───────┴──────┬───────┘
       │              │
       ▼              ▼
  Standard       Adaptive
  scoping        refinement
                      │
                      ▼
              Step 1: Classify target
              (Web / Codebase / Mixed)
                      │
                      ▼
              Step 2: Quick recon
              (WebSearch OR Glob+Grep+Read)
                      │
                      ▼
              Step 3: Select relevant questions
              (based on target + score + recon)
                      │
                      ▼
              Step 4: Ask (2-7 questions)
                      │
                      ▼
              Step 5: Confirm
```

---

## Step 1: Classify Query Target

Before reconnaissance, determine what the query is about:

| Target Type | Indicators | Recon Method |
|-------------|------------|--------------|
| **Web/External** | General topics, industry trends, "what is X", comparisons | WebSearch |
| **Local Codebase** | "this codebase", "our code", "how does X work here", file paths | Glob + Grep + Read |
| **Mixed** | "how does our X compare to", "best practices for our Y" | Both |

---

## Step 2: Topic Reconnaissance

### For Web/External Topics

```
WebSearch: "[topic] overview" OR "[topic] guide"
```

From top 2-3 results, extract:
- **Key facets**: What sub-areas exist?
- **Decision points**: What do people typically need to choose?
- **Domain type**: Technical | Strategic | Market | Personal | Academic
- **Time-sensitivity**: Rapidly evolving | Stable | Historical

### For Codebase Topics

```
Glob: Find relevant files (e.g., "**/auth*", "**/pipeline*")
Grep: Search for key terms, patterns
Read: Skim 2-3 most relevant files
```

Extract:
- **Architecture**: What components/modules exist?
- **Key files**: Where is the core logic?
- **Patterns used**: Frameworks, conventions
- **Entry points**: Where to start exploring?

### For Mixed Topics

Do both — understand local implementation AND external best practices.

---

## Step 3: Select Relevant Questions

### Refinement Tiers

| Clarity Score | Tier | Max Questions |
|---------------|------|---------------|
| 8-11 | Light | 2-3 |
| 4-7 | Medium | 3-5 |
| < 4 | Full | 5-7 |

### Question Relevance Matrix

**Universal (all targets):**

| Question | Ask When |
|----------|----------|
| Core Question | ALWAYS |
| Which Angle/Facet | Recon found multiple facets |
| Depth Preference | ALWAYS |
| Output Format | Medium+ |

**Web/External Only:**

| Question | Ask When | Skip When |
|----------|----------|-----------|
| Decision Context | Light+ | Obviously personal |
| Audience | Medium+ | Personal/casual |
| Geographic Focus | Market, regulatory topics | Pure technical |
| Timeframe | Evolving fields, markets | Stable concepts |
| Source Constraints | Full only | Casual |
| Citation Strictness | Full only | Personal |
| Definition of Done | Full only | Simple |

**Codebase Only:**

| Question | Ask When | Skip When |
|----------|----------|-----------|
| Which Modules | Recon found multiple areas | Single module obvious |
| Explanation Goal | Always | - |
| Output Type | Always | - |
| Include Tests/Configs | Medium+ | Simple explanation |

---

## Step 4: Question Templates

### Universal Questions

**Core Question**
```
You said: "[ORIGINAL_QUERY]"

Based on my quick lookup, [TOPIC] covers several areas:
- [Facet 1 from recon]
- [Facet 2 from recon]
- [Facet 3 from recon]

What's your specific question?
```

**Which Angle** (if multiple facets)
```
Which aspect interests you most?
□ [Facet 1] - [description]
□ [Facet 2] - [description]
□ [Facet 3] - [description]
□ All of the above
□ Other: ___________
```

**Depth Preference**
```
How deep should we go?
□ Quick overview (key points only)
□ Standard analysis (thorough but focused)
□ Deep dive (comprehensive)
□ Exhaustive (leave no stone unturned)
```

### Web-Specific Questions

**Decision Context**
```
What will this research inform?
□ Investment/financial decision
□ Technology/product selection
□ Strategy/planning
□ Learning/understanding
□ Compliance/risk assessment
□ Other: ___________
```

**Audience**
```
Who will consume this?
□ Executive (high-level insights)
□ Technical (implementation details)
□ Mixed
□ Just me
```

**Geographic Focus** (only if relevant)
```
Geographic scope?
□ Global
□ North America
□ Europe
□ Asia-Pacific
□ Specific: ___________
```

**Timeframe** (only if relevant)
```
Time period?
□ Historical analysis
□ Current state
□ Future projections
□ Specific period: ___________
```

### Codebase-Specific Questions

**Which Modules**
```
Based on my scan, this codebase has:
- [Module 1]: [description]
- [Module 2]: [description]
- [Module 3]: [description]

Which areas should I focus on?
□ All of the above
□ Specific: ___________
```

**Explanation Goal**
```
What do you want to understand?
□ High-level architecture (how pieces fit together)
□ Specific implementation (how X works)
□ Data flow (how data moves through)
□ Extension points (how to add features)
□ Debugging (why X behaves this way)
```

**Output Type**
```
What format would be most useful?
□ Written explanation (markdown)
□ Architecture diagram (mermaid/ASCII)
□ Annotated code walkthrough
□ Quick verbal summary
```

---

## Step 5: Adaptive Confirmation

Only include sections that were actually asked:

```
### RESEARCH QUESTION
[Synthesized from answers]

### CONTEXT
[Only if asked: Decision context, Audience]

### SCOPE
[Only if asked: Geography, Timeframe, Modules, Include/Exclude]

### CONSTRAINTS
[Depth is always included; sources only if asked]

### OUTPUT
[Format, Citations - only if asked]

### SUCCESS CRITERIA
[Only if asked; otherwise inferred]

---
Does this capture it? I can adjust before we begin.
```

---

## Examples

### Example 1: "AI safety" (Web, score 4, Full tier)

**Recon:** Technical alignment, governance, x-risk, near-term harms

**Questions asked:**
1. Core → Which aspect?
2. Angle → Alignment vs governance vs x-risk?
3. Decision context → Learning vs professional?
4. Depth → Standard
5. Timeframe → Current state vs history?

**Skipped:** Geographic, Citations, Output format

---

### Example 2: "best CI/CD tool" (Web, score 7, Medium tier)

**Recon:** GitHub Actions, GitLab CI, Jenkins; team size matters; cloud vs self-hosted

**Questions asked:**
1. Angle → Cloud-native vs self-hosted?
2. Decision context → Tech selection (implied)
3. Depth → Standard
4. Team size? (domain-specific)

**Skipped:** Geographic, Timeframe, Audience, Citations

---

### Example 3: "how does auth work in this codebase" (Codebase, score 6, Medium tier)

**Recon:** Found `src/auth/`, JWT tokens, Express middleware

**Questions asked:**
1. Which modules → Middleware? User model? Token handling?
2. Explanation goal → Architecture vs implementation vs data flow?
3. Depth → Standard
4. Output type → Doc vs diagram vs walkthrough?

**Skipped:** Tests/configs, Definition of done

---

### Example 4: "how does our caching compare to best practices" (Mixed, score 5, Medium tier)

**Recon (local):** Redis in `src/cache/`, TTL patterns
**Recon (web):** Write-through, cache-aside, thundering herd

**Questions asked:**
1. Core → What aspects to compare?
2. Which aspects → Performance? Consistency? Scalability?
3. Decision context → Improvement vs documentation vs audit?
4. Depth → Standard
5. Output → Comparison table vs narrative?

**Skipped:** Geographic, Timeframe, Citations

---

## What Happens to /dr-refine?

**Still available** as optional standalone skill for users who want to:
- Refine a question WITHOUT starting research
- Explore what they want before committing
- Generate a structured prompt to modify

But now `/dr` handles vague queries automatically — `/dr-refine` is no longer required.
