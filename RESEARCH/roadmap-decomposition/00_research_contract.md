---
name: roadmap-decomposition
status: in-progress
created: 2026-01-20T00:00:00Z
updated: 2026-01-20T00:00:00Z
---

# Research Contract: Roadmap Decomposition

## Core Research Question
How should a roadmap be automatically decomposed into independent, well-bounded PRDs with proper dependency management?

## Decision/Use-Case
Build an automated `pm:decompose` skill that takes a high-level roadmap and generates:
- Independent, well-bounded PRD documents
- Dependency graph (DAG) between PRDs
- Validation rules for completeness and consistency

## Audience
Technical - developers building the pm:decompose automation skill

## Scope
### Included
- Decomposition strategies (vertical slice, MoSCoW, story mapping)
- INVEST principles automation
- Dependency detection and DAG construction
- LLM-based requirement analysis
- Failure modes and edge cases
- Industry best practices

### Excluded
- Project management tool integrations (Jira, Linear, etc.)
- Team capacity planning
- Sprint/iteration planning
- Budget allocation

## Constraints
- Focus on actionable, implementable specifications
- Prefer open-source or well-documented approaches
- Must work with LLM-based automation

## Output Format
1. Research report with evidence-backed findings
2. Algorithm specification for decomposition
3. PRD template/schema
4. Dependency validation logic
5. Ready-to-implement skill definition

## Definition of Done
- [ ] All 6 subquestions answered with C1-level evidence
- [ ] All 5 hypotheses validated/invalidated with evidence
- [ ] All 6 perspectives represented
- [ ] Actionable pm:decompose skill specification
- [ ] Edge cases and failure modes documented
