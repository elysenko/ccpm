# LLM UI Agent Methodologies Research

**Research Question**: What are the best methodologies and patterns for building an LLM-based agent that creates UI/frontend code?

**Complexity**: Type D - INVESTIGATION (Extended GoT + hypothesis testing + Red Team)

**Intensity**: Exhaustive

**Completed**: 2026-01-22

## Status

- [x] Phase 0: Complexity Classification
- [x] Phase 1: Scope and Research Contract
- [x] Phase 1.5: Hypothesis Formation
- [x] Phase 1.6: Perspective Discovery
- [x] Phase 2: Retrieval Planning
- [x] Phase 3: Iterative Querying (GoT Generate)
- [x] Phase 4: Triangulation (GoT Score)
- [x] Phase 5: Synthesis (GoT Aggregate)
- [x] Phase 6: Quality Assurance (Reflexion)
- [x] Phase 7: Output Packaging

## Key Deliverables

- **Final Report**: `../research-report-ui-agents.md`
- **Methodology Taxonomy**: `08_report/01_methodology_taxonomy.md`
- **Tool Comparison**: `08_report/02_tool_comparison.md`
- **Implementation Patterns**: `08_report/03_implementation_patterns.md`
- **Recommendations**: `08_report/04_recommendations.md`
- **Limitations & Risks**: `08_report/05_limitations_risks.md`

## Key Findings

1. **Composite architectures** (v0 model) outperform simple single-agent approaches
2. **Self-debugging** improves accuracy by 10-15% (essential for production)
3. **Constrained output** to shadcn/ui + Tailwind reduces hallucination
4. **Hierarchical generation** improves visual similarity by up to 15%
5. **Structured design input** (Figma MCP) > raw screenshots

## Source Quality

- **Grade A sources**: 14 (peer-reviewed research, official documentation)
- **Grade B sources**: 8 (technical blogs from tool creators)
- **Grade C sources**: 3 (comparison articles)

## Hypotheses Tested

| Hypothesis | Prior | Final | Status |
|------------|-------|-------|--------|
| Constrained component libraries improve quality | 70-80% | 85-90% | CONFIRMED |
| Multi-agent > single-agent for complex tasks | 50-60% | 65-75% | CONDITIONAL |
| Self-debugging essential for production | 75-85% | 90-95% | STRONGLY CONFIRMED |
| Visual input improves accuracy | 60-70% | 75-85% | CONFIRMED (with caveats) |
| Hierarchical approaches better | 70-80% | 85-90% | CONFIRMED |

## File Structure

```
./RESEARCH/llm-ui-agent-methodologies/
├── README.md
├── 00_research_contract.md
├── 01_hypotheses.md
├── 01_research_plan.md
├── 01a_perspectives.md
├── 03_source_catalog.csv
├── 04_evidence_ledger.csv
├── 08_report/
│   ├── 00_executive_summary.md
│   ├── 01_methodology_taxonomy.md
│   ├── 02_tool_comparison.md
│   ├── 03_implementation_patterns.md
│   ├── 04_recommendations.md
│   ├── 05_limitations_risks.md
│   └── 09_references.md
└── 09_qa/
    └── qa_report.md
```
