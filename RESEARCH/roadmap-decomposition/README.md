# Deep Research: Roadmap Decomposition into PRDs

## Research Question
How should a roadmap be automatically decomposed into independent, well-bounded PRDs with proper dependency management?

## Classification
**TYPE C (ANALYSIS)** - Full 7-phase GoT research completed

## Hypotheses Validation Results

| ID | Hypothesis | Prior | Final | Verdict |
|----|------------|-------|-------|---------|
| H1 | Vertical slice decomposition produces more independent PRDs than horizontal layers | 70% | **90%** | CONFIRMED |
| H2 | LLMs can reliably detect dependencies without explicit declarations | 55% | **35%** | REFUTED |
| H3 | INVEST principles can be converted to automatable heuristics | 65% | **75%** | CONFIRMED |
| H4 | DAG validation can be done incrementally | 80% | **95%** | CONFIRMED |
| H5 | Hybrid strategy outperforms single strategy | 60% | **85%** | CONFIRMED |

## Key Findings Summary

### 1. Decomposition Strategy
**Vertical slice is the evidence-backed default.** The SPIDR framework (Spikes, Paths, Interface, Data, Rules) provides systematic decomposition techniques covering nearly all scenarios.

### 2. INVEST Automation
INVEST criteria can be partially automated with weighted scoring:
- Independent: 0.25 weight (HIGH automation)
- Negotiable: 0.05 weight (LOW automation)
- Valuable: 0.20 weight (MEDIUM automation)
- Estimable: 0.15 weight (MEDIUM automation)
- Small: 0.15 weight (HIGH automation)
- Testable: 0.20 weight (HIGH automation)

### 3. Dependency Management
- **Topological sort:** O(V+E) for static graphs
- **Incremental updates:** O(m^3/2) via Haeupler's algorithm
- **Cycle detection:** Tarjan's SCC algorithm O(V+E)

### 4. LLM Effectiveness
- 58.2% industry adoption but only 5.4% full automation
- Human-AI collaboration dominates at 54.4%
- **Zero practitioners** believe LLM can handle analysis/validation alone

### 5. Anti-Patterns
10 documented anti-patterns to detect and avoid, including:
- Horizontal slicing (HIGH severity)
- Core-first approach (HIGH severity)
- Happy path only (HIGH severity)

## Perspectives Covered
1. Product Management - Value delivery, stakeholder alignment
2. Software Architecture - Technical coupling, interface boundaries
3. Agile/Scrum - INVEST principles, story mapping
4. AI/LLM Orchestration - Prompting strategies, hallucination detection
5. Graph Theory/Algorithms - DAG construction, cycle detection
6. Skeptic/Failure Modes - Anti-patterns, edge cases

## Deliverables

| File | Description |
|------|-------------|
| `00_research_contract.md` | Research scope and definition of done |
| `01_research_plan.md` | Query strategy and subquestions |
| `01a_perspectives.md` | 6 expert perspectives |
| `02_query_log.csv` | 18 search queries with results |
| `03_source_catalog.csv` | 20 sources with quality grades |
| `04_evidence_ledger.csv` | 20 verified claims |
| `05_contradictions_log.md` | 5 tensions resolved |
| `08_report/00_executive_summary.md` | Executive overview |
| `08_report/02_findings_decomposition_strategies.md` | Vertical slice, SPIDR, story mapping |
| `08_report/03_findings_invest_automation.md` | INVEST heuristics |
| `08_report/04_findings_dag_algorithms.md` | DAG algorithms specification |
| `08_report/05_findings_llm_effectiveness.md` | LLM capabilities and limitations |
| `08_report/06_findings_failure_modes.md` | 10 anti-patterns with detection |
| `08_report/07_algorithm_specification.md` | **Full decomposition algorithm** |
| `08_report/08_prd_template.md` | PRD schema and template |
| `08_report/09_skill_definition.md` | **Ready-to-implement pm:decompose** |
| `08_report/10_limitations_open_questions.md` | Research limitations |
| `09_references.md` | 24 sources cited |
| `09_qa/qa_report.md` | Quality assurance verification |
| `09_qa/citation_audit.md` | Citation independence audit |

## Status
- Created: 2026-01-20
- Completed: 2026-01-20
- Phase: 7 (Complete)
- Progress: 100%

## Quick Start

To implement the `pm:decompose` skill:
1. Review `08_report/07_algorithm_specification.md` for the complete algorithm
2. Use `08_report/08_prd_template.md` for output format
3. Implement `08_report/09_skill_definition.md` as the skill file
4. Test with sample epics using confidence threshold 0.7
