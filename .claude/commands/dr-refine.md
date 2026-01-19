---
description: Refine a vague research question before deep research (optional - /dr now auto-refines)
allowed-tools: AskUserQuestion
argument-hint: [vague research topic]
---

# Research Question Refiner

**Note:** This skill is now optional. `/dr` automatically detects vague queries and triggers refinement. Use `/dr-refine` if you want to refine a question WITHOUT starting research, or to explore what you want before committing.

Before launching deep research, refine this vague question into a well-structured research prompt: $ARGUMENTS

## Ask clarifying questions to capture:

1. **Core Question**: What is the one-sentence research question?
2. **Decision/Use-case**: What will this research inform? (investment, strategy, learning, etc.)
3. **Audience**: Who will consume this? (Executive, Technical, Mixed)
4. **Scope**:
   - Geographic focus (Global, US, EU, specific country?)
   - Timeframe (Historical? Current state? Future projections?)
   - What to include/exclude?
5. **Constraints**:
   - Required sources (academic only? include news?)
   - Banned sources (avoid vendor content? exclude specific outlets?)
   - Budget/depth preference (Quick overview vs exhaustive analysis)
6. **Output Format**: Report, bullet summary, data pack, slides outline?
7. **Citation Strictness**: Full academic citations vs light sourcing?
8. **Definition of Done**: What would make this research "complete"?

## After gathering answers, output:

A structured research prompt ready for `/dr`:

```
### RESEARCH QUESTION
[One clear sentence]

### CONTEXT
[What this informs, who will use it]

### SCOPE
- Geography: [X]
- Timeframe: [X]
- Include: [X]
- Exclude: [X]

### CONSTRAINTS
- Required sources: [X]
- Avoid: [X]
- Depth: [Quick/Standard/Deep/Exhaustive]

### OUTPUT FORMAT
[What deliverable looks like]

### SUCCESS CRITERIA
[How we know we're done]
```

Then offer to run `/dr` with the refined question.
