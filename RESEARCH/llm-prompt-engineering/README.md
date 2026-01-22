# LLM Prompt Engineering Best Practices Research

## Research Focus
Best practices and guiding principles for writing effective LLM prompts, with emphasis on Claude/Anthropic models.

## Status
- **Phase**: 7 - COMPLETE
- **Type**: C (Analysis) - Full 7-phase GoT
- **Started**: 2026-01-22
- **Completed**: 2026-01-22
- **QA Score**: 9.5/10

## Key Outputs

### Primary Report
- **Location**: `./08_report/research-report.md`
- **Also copied to**: `./research-report.md` (project root)

### Supporting Documents
- Research contract: `./00_research_contract.md`
- Research plan: `./01_research_plan.md`
- Perspectives: `./01a_perspectives.md`
- Evidence: `./07_working_notes/evidence_passages.json`
- Hypothesis evaluation: `./07_working_notes/hypothesis_evaluation.md`
- QA report: `./09_qa/qa_report.md`
- Citation audit: `./09_qa/citation_audit.md`

## Key Findings

### Hypothesis Outcomes
| Hypothesis | Prior | Final | Verdict |
|------------|-------|-------|---------|
| XML tags improve Claude's parsing | 80% | 90% | CONFIRMED |
| Extended thinking improves complex reasoning | 75% | 85% | CONFIRMED (with nuance) |
| Few-shot needed for novel formats only | 60% | 55% | PARTIALLY DISCONFIRMED |
| Long system prompts degrade performance | 50% | 75% | CONFIRMED |
| Prompt injection mitigable but not eliminable | 85% | 95% | STRONGLY CONFIRMED |

### Top 5 Actionable Insights

1. **Use XML tags** - Claude was trained with XML in training data; tags like `<instructions>`, `<context>`, `<example>` significantly improve parsing accuracy

2. **Extended thinking needs high-level instructions** - "Think deeply" outperforms prescriptive step-by-step; model creativity may exceed prescribed processes

3. **Context is finite with diminishing returns** - Long prompts degrade performance 13.9%-85% even with perfect retrieval; use 70-80% of context window max

4. **Few-shot helps more than just novel formats** - Include 3-5 diverse examples for complex tasks, consistency, and reducing instruction misinterpretation

5. **Injection defense requires depth** - 78% attack success rate on Claude with persistence; implement prevention + detection + mitigation layers

## Sources Used

### Grade A (8 sources)
- Anthropic Official Documentation (8)
- OWASP Security Guidance (1)

### Grade B (5 sources)
- Academic Research (2)
- Practitioner Guides (2)

## Topics Covered
1. Prompt structure patterns (XML tags, markdown, organization)
2. Chain-of-thought techniques
3. System prompt design
4. Few-shot vs zero-shot approaches
5. Constitutional AI principles
6. Prompt injection prevention
7. Meta-prompting strategies
8. Claude-specific optimizations

## Research Methodology
- Graph of Thoughts (GoT) with Standard intensity tier
- 7 phases: Classification → Scoping → Hypotheses → Perspectives → Retrieval → Triangulation → Synthesis → QA
- All C1 claims verified with evidence and independence checks
