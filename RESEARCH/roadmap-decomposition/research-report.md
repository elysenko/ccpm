# Research Report: Roadmap-to-PRD Decomposition

**Research Question:** How should a roadmap be automatically decomposed into independent, well-bounded PRDs with proper dependency management?

**Classification:** TYPE C (ANALYSIS) - Full 7-phase GoT research
**Date:** 2026-01-20
**Research Folder:** `./RESEARCH/roadmap-decomposition/`

---

## Executive Summary

This research investigated automatic decomposition of roadmaps into PRDs. Key finding: **Human-AI collaboration is mandatory** - 58.2% industry LLM adoption but only 5.4% full automation, with zero practitioners believing LLMs can handle analysis/validation independently.

### Hypothesis Validation Results

| Hypothesis | Prior | Final | Verdict |
|------------|-------|-------|---------|
| H1: Vertical slice > horizontal | 70% | **90%** | CONFIRMED |
| H2: LLMs detect dependencies reliably | 55% | **35%** | REFUTED |
| H3: INVEST automatable | 65% | **75%** | CONFIRMED |
| H4: DAG validation incremental | 80% | **95%** | CONFIRMED |
| H5: Hybrid strategy wins | 60% | **85%** | CONFIRMED |

### Recommended Architecture

```
Roadmap Input
    |
[LLM Decomposition Agent] --> Draft PRDs + Dependencies
    |
[INVEST Validator] --> Quality scores per PRD
    |
[DAG Builder] --> Dependency graph (detect cycles)
    |
[Anti-Pattern Detector] --> Flag violations
    |
[Human Review Gate] --> Mandatory checkpoint (confidence < 0.7)
    |
Final PRDs + Validated DAG
```

---

## 1. Decomposition Strategies

### Vertical Slice (Evidence Grade: A)

**Key Finding:** Vertical slice decomposition is the evidence-backed default. It produces end-to-end functionality enabling faster feedback and reduced integration risk.

**SPIDR Framework (in order of application: R → D → I → P → S):**
- **R**ules: Defer complex business rules
- **D**ata: Split by meaningful data variations
- **I**nterface: Split when interfaces differ significantly
- **P**aths: Split by alternative user journeys
- **S**pikes: Use research spikes for unknowns

### Strategy Selection Algorithm

```python
def select_strategy(item: RoadmapItem, context: Context) -> Strategy:
    if item.type == 'epic':
        return Strategy.STORY_MAPPING
    elif has_clear_user_journeys(item):
        return Strategy.SPIDR_PATHS
    elif has_business_rules(item):
        return Strategy.SPIDR_RULES
    elif has_data_variations(item):
        return Strategy.SPIDR_DATA
    else:
        return Strategy.VERTICAL_SLICE
```

---

## 2. INVEST Scoring Algorithm

### Weighted Criteria

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Independent | 0.25 | No blocking dependencies |
| Negotiable | 0.05 | Flexibility in implementation |
| Valuable | 0.20 | Delivers user value |
| Estimable | 0.15 | Clear enough to estimate |
| Small | 0.15 | Completable in sprint |
| Testable | 0.20 | Clear acceptance criteria |

### Scoring Functions

```python
def calculate_invest_score(prd: PRD) -> INVESTScore:
    scores = {
        'independent': calculate_independence(prd),  # Dependency keyword analysis
        'negotiable': calculate_negotiability(prd),  # Flexibility indicators
        'valuable': calculate_value(prd),            # User role, outcome, action verbs
        'estimable': calculate_estimability(prd),    # Ambiguity detection
        'small': calculate_size_score(prd),          # Criteria count, word count
        'testable': calculate_testability(prd)       # Acceptance criteria quality
    }

    weights = {'independent': 0.25, 'negotiable': 0.05, 'valuable': 0.20,
               'estimable': 0.15, 'small': 0.15, 'testable': 0.20}
    composite = sum(scores[k] * weights[k] for k in scores)

    # Detect trade-offs
    conflicts = []
    if scores['independent'] < 0.6 and scores['small'] > 0.8:
        conflicts.append("Trade-off: high small score may indicate broken independence")

    return INVESTScore(**scores, composite=composite, conflicts=conflicts)

def calculate_independence(prd: PRD) -> float:
    dependency_keywords = ['depends on', 'requires', 'after', 'when complete', 'blocked by']
    keyword_count = sum(1 for kw in dependency_keywords if kw in prd.full_text.lower())
    explicit_deps = len(prd.dependencies)
    score = 1.0 - min(1.0, (keyword_count * 0.15 + explicit_deps * 0.2))
    return max(0, score)

def calculate_value(prd: PRD) -> float:
    score = 0.0
    if re.search(r'[Aa]s a[n]?\s+\w+', prd.user_story): score += 0.3
    if 'so that' in prd.user_story.lower(): score += 0.3
    action_verbs = ['purchase', 'create', 'view', 'manage', 'track', 'analyze', 'share']
    if any(verb in prd.full_text.lower() for verb in action_verbs): score += 0.2
    tech_ratio = count_tech_terms(prd) / word_count(prd)
    if tech_ratio < 0.2: score += 0.2
    return min(1.0, score)

def calculate_testability(prd: PRD) -> float:
    score = 0.0
    if prd.acceptance_criteria:
        score += 0.4
        structured_count = sum(
            1 for ac in prd.acceptance_criteria
            if re.search(r'(given|when|then|should|verify)', ac.lower())
        )
        structure_ratio = structured_count / len(prd.acceptance_criteria)
        score += 0.3 * structure_ratio
    if re.search(r'\d+\s*(seconds?|minutes?|%|items?|users?)', prd.full_text):
        score += 0.3
    return min(1.0, score)
```

---

## 3. Dependency DAG Validation

### Algorithm Selection

| Algorithm | Complexity | Use Case |
|-----------|------------|----------|
| Kahn's Algorithm | O(V+E) | Topological sort |
| Tarjan's SCC | O(V+E) | Cycle detection |
| Incremental DAG | O(m^3/2) | Dynamic updates |

### Implementation

```python
def build_dependency_dag(prds: List[PRD]) -> DependencyDAG:
    dag = DependencyDAG()

    # Add all PRDs as nodes
    for prd in prds:
        dag.add_node(prd.id)

    # Add explicit dependencies
    for prd in prds:
        for dep_id in prd.dependencies:
            success, error = dag.add_edge(dep_id, prd.id, type='explicit')
            if not success:
                dag.add_warning(f"Dependency {dep_id} -> {prd.id}: {error}")

    # Detect implicit dependencies
    implicit_deps = detect_implicit_dependencies(prds)
    for from_id, to_id, confidence in implicit_deps:
        if confidence > 0.7:
            dag.add_edge(from_id, to_id, type='implicit')

    return dag

def validate_dag(dag: DependencyDAG) -> DAGValidation:
    cycles = dag.find_cycles()  # Tarjan's algorithm
    max_depth = dag.calculate_max_depth()
    orphans = dag.find_orphans()

    return DAGValidation(
        is_valid=len(cycles) == 0,
        cycles=cycles,
        max_depth=max_depth,
        orphans=orphans,
        warnings=[
            f"Depth {max_depth} may indicate over-decomposition" if max_depth > 5 else None,
            f"Orphan PRDs: {orphans}" if orphans else None
        ]
    )

def resolve_cycles(prds, dag, validation):
    """Attempt to resolve cycles by removing lowest-confidence implicit edges."""
    for cycle in validation.cycles:
        for i in range(len(cycle)):
            from_id, to_id = cycle[i], cycle[(i + 1) % len(cycle)]
            edge = dag.get_edge(from_id, to_id)
            if edge and edge.type == 'implicit':
                dag.remove_edge(from_id, to_id)
                break
        else:
            raise CycleUnresolvableError(f"Cannot resolve cycle: {' -> '.join(cycle)}")

    new_validation = validate_dag(dag)
    if not new_validation.is_valid:
        raise CycleUnresolvableError("Cycles remain after resolution attempt")
    return prds, dag
```

---

## 4. Anti-Pattern Detection

### 10 Documented Anti-Patterns

| Anti-Pattern | Severity | Detection Heuristic |
|--------------|----------|---------------------|
| Horizontal slice | HIGH | Single layer keywords only |
| Process step split | MEDIUM | Sequential markers + no standalone value |
| Happy path only | HIGH | Missing error/edge case keywords |
| Core first | HIGH | "Core/base/foundation" + no user value |
| CRUD split | MEDIUM | Same entity, different CRUD verbs |
| Trivial data split | MEDIUM | Structurally identical PRDs |
| Superficial interface | MEDIUM | Differs only by web/mobile |
| Bad conjunction split | MEDIUM | Setup-only PRD with no outcome |
| Superficial role split | MEDIUM | Same functionality, different roles |
| Test case as PRD | MEDIUM | Test language dominates |

### Composite Detector

```python
class AntiPatternDetector:
    def __init__(self):
        self.checks = [
            ('horizontal_slice', is_horizontal_slice, 'HIGH'),
            ('process_step', is_process_step_split, 'MEDIUM'),
            ('happy_path_only', is_happy_path_only, 'HIGH'),
            ('core_first', is_core_first, 'HIGH'),
            ('crud_split', is_crud_split, 'MEDIUM'),
            ('trivial_data', is_trivial_data_split, 'MEDIUM'),
            ('superficial_interface', is_superficial_interface_split, 'MEDIUM'),
            ('bad_conjunction', is_bad_conjunction_split, 'MEDIUM'),
            ('superficial_role', is_superficial_role_split, 'MEDIUM'),
            ('test_case_as_prd', is_acceptance_criteria_as_prd, 'MEDIUM'),
        ]

    def analyze(self, prds):
        issues = []
        for name, check, severity in self.checks:
            if check(prds):
                issues.append({
                    'pattern': name,
                    'severity': severity,
                    'recommendation': self._get_recommendation(name)
                })
        return issues

def is_horizontal_slice(prd):
    layer_keywords = {
        'ui': ['frontend', 'ui', 'interface', 'view', 'component'],
        'api': ['api', 'endpoint', 'service', 'backend'],
        'db': ['database', 'schema', 'migration', 'table']
    }
    layers_mentioned = sum(
        1 for layer, keywords in layer_keywords.items()
        if any(kw in prd.text.lower() for kw in keywords)
    )
    return layers_mentioned == 1 and prd.is_technical_focused()

def is_happy_path_only(prd):
    error_keywords = ['error', 'fail', 'invalid', 'exception', 'edge case']
    has_error_handling = any(kw in prd.text.lower() for kw in error_keywords)
    happy_path_indicators = ['happy path', 'main flow', 'basic', 'simple case']
    is_happy_path_focused = any(ind in prd.text.lower() for ind in happy_path_indicators)
    return is_happy_path_focused and not has_error_handling

def is_core_first(prd):
    core_indicators = ['core', 'base', 'foundation', 'infrastructure', 'framework']
    has_core_language = any(ind in prd.text.lower() for ind in core_indicators)
    lacks_user_value = 'As a' not in prd.text and not prd.has_user_outcome()
    return has_core_language and lacks_user_value
```

---

## 5. LLM Integration

### Industry Reality (Evidence Grade: A)

| Metric | Value |
|--------|-------|
| Industry AI adoption | 58.2% |
| Full automation | 5.4% |
| Human-AI collaboration | 54.4% |
| Believe LLM can do analysis alone | **0%** |

### Prompting Strategy

**Recommended:** Few-shot + Template + Reasoning

```python
def build_decomposition_prompt(item: RoadmapItem, strategy: Strategy) -> str:
    return f"""
You are an expert product manager decomposing a roadmap item into independent PRDs.

## Context
Roadmap Item: {item.title}
Description: {item.description}
Strategy: {strategy.name}

## Decomposition Rules
1. Each PRD must deliver STANDALONE USER VALUE
2. Use VERTICAL SLICES (touch all layers: UI -> API -> Data)
3. Avoid these anti-patterns:
   - Splitting by technical component
   - Splitting by process step without independent value
   - Separating happy path from error handling
   - Building "core" without end-to-end functionality

## SPIDR Techniques (apply in order: R -> D -> I -> P -> S)
- Rules: Can we defer business rules to simplify?
- Data: Are there meaningful data variations?
- Interface: Do interfaces differ significantly?
- Paths: Are there alternative user paths?
- Spikes: Is research needed before deciding?

## Your Task
Decompose this item into 3-7 PRDs following the rules above.

For each PRD, provide:
- Title
- User story (As a..., I want..., so that...)
- 3-5 acceptance criteria
- Dependencies on other PRDs (if any)
- Size estimate (XS/S/M/L/XL)

## Output Format (JSON)
```json
{{
  "prds": [{{
    "id": "PRD-001",
    "title": "...",
    "user_story": "As a ..., I want ..., so that ...",
    "acceptance_criteria": ["..."],
    "dependencies": [],
    "size": "M"
  }}],
  "rationale": "Brief explanation of decomposition approach"
}}
```
"""
```

### Hallucination Detection

```python
def self_consistency_check(prompt, n_samples=3):
    """Generate multiple outputs with temperature variation. Flag inconsistencies."""
    outputs = [llm.generate(prompt, temperature=0.7) for _ in range(n_samples)]
    return calculate_consistency_score(outputs)

def metamorphic_check(requirement, decomposition):
    """Apply semantic-preserving transformations. If answer changes, likely hallucination."""
    rephrased = llm.rephrase(requirement)
    new_decomposition = llm.decompose(rephrased)
    return compare_decompositions(decomposition, new_decomposition)
```

---

## 6. Confidence Calculation

```python
def calculate_confidence(consistency, prds, dag_validation, antipatterns) -> float:
    # Base from LLM consistency
    confidence = consistency * 0.3

    # INVEST contribution
    avg_invest = sum(prd.invest_score.composite for prd in prds) / len(prds)
    confidence += avg_invest * 0.3

    # DAG validity
    confidence += 0.2 if dag_validation.is_valid else 0.05

    # Anti-pattern penalty
    high_severity = sum(1 for w in antipatterns if w.severity == 'HIGH')
    medium_severity = sum(1 for w in antipatterns if w.severity == 'MEDIUM')
    antipattern_penalty = high_severity * 0.1 + medium_severity * 0.05
    confidence += max(0, 0.2 - antipattern_penalty)

    return min(1.0, confidence)
```

### Confidence Thresholds

| Confidence | Action |
|------------|--------|
| > 0.9 | Auto-approve |
| 0.7 - 0.9 | Light review |
| 0.5 - 0.7 | Full review |
| < 0.5 | Regenerate |

---

## 7. PRD Template Schema

### YAML Schema

```yaml
prd:
  id: string                    # e.g., "PRD-AUTH-001"
  title: string                 # < 80 chars
  status: enum                  # draft | review | approved | in-progress | done
  created: datetime             # ISO 8601
  updated: datetime             # ISO 8601

  user_story:
    role: string
    goal: string
    benefit: string

  description: string           # Markdown supported

  acceptance_criteria:
    - criterion: string
      type: enum                # functional | performance | security | ux
      testable: boolean

  dependencies:
    - prd_id: string
      type: enum                # blocks | informs | related
      description: string

  size:
    estimate: enum              # XS | S | M | L | XL
    confidence: enum            # high | medium | low

  invest_score:
    independent: float          # 0.0 - 1.0
    negotiable: float
    valuable: float
    estimable: float
    small: float
    testable: float
    composite: float

  tags: list[string]
  epic_id: string
  review_required: boolean
```

---

## 8. pm:decompose Skill Definition

### Command Signature

```
/pm:decompose <roadmap_item_path> [options]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--max-prds` | 7 | Maximum PRDs to generate |
| `--min-prds` | 3 | Minimum PRDs to generate |
| `--strategy` | auto | Decomposition strategy (auto/vertical/spidr/story-map) |
| `--confidence-threshold` | 0.7 | Minimum confidence for auto-approval |
| `--output-dir` | ./prds | Output directory |
| `--review` | false | Force human review |
| `--dry-run` | false | Preview without writing |

### Output Structure

```
{output-dir}/
├── decomposition-summary.md     # Overview
├── dependency-graph.json        # DAG in JSON
├── dependency-graph.mermaid     # Visual DAG
├── PRD-{EPIC}-001.md           # First PRD
├── PRD-{EPIC}-002.md           # Second PRD
├── ...
└── validation-report.md         # INVEST scores, anti-patterns
```

### Execution Flow

1. **Load and Parse Input** - Extract id, title, type, description, goals, constraints
2. **Select Decomposition Strategy** - Based on item characteristics
3. **Generate PRD Decomposition** - LLM with prompt template, validate format
4. **INVEST Validation** - Score each PRD on 6 criteria
5. **Build Dependency Graph** - Explicit + implicit dependencies, cycle detection
6. **Anti-Pattern Detection** - Check all 10 patterns
7. **Calculate Confidence** - Aggregate from all validators
8. **Output Generation** - Write PRDs, DAG, validation report
9. **Review Decision** - Require human review if confidence < threshold

---

## 9. Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| `FILE_NOT_FOUND` | Invalid path | Check path exists |
| `INVALID_FORMAT` | Missing required fields | Add frontmatter |
| `LLM_FAILURE` | Generation failed | Retry or simplify input |
| `CYCLE_DETECTED` | Unresolvable dependency cycle | Manual intervention |
| `TOO_MANY_PRDS` | Too granular | Increase min-prds |
| `TOO_FEW_PRDS` | Item too small | Decrease max-prds or skip |

---

## 10. Implementation Priority

1. **INVEST heuristic validator** - Quick win, immediate quality feedback
2. **Anti-pattern detection rules** - High value, catches common mistakes
3. **DAG construction with Tarjan's cycle check** - Foundational infrastructure
4. **LLM decomposition with confidence scoring** - Iterative improvement
5. **Human review workflow integration** - Required for production use

---

## References

### Primary Sources (Grade A)

1. Bogard, J. *Vertical Slice Architecture*. https://www.jimmybogard.com/vertical-slice-architecture/
2. Cohn, M. *Five Simple but Powerful Ways to Split User Stories (SPIDR)*. Mountain Goat Software. https://www.mountaingoatsoftware.com/blog/five-simple-but-powerful-ways-to-split-user-stories
3. Agile Alliance. *INVEST*. https://agilealliance.org/glossary/invest/
4. Heck, P., & Zaidman, A. (2025). *Large Language Models for Requirements Engineering: A Systematic Literature Review*. arXiv:2509.11446. https://arxiv.org/html/2509.11446v1
5. Research Team (2025). *AI for Requirements Engineering: Industry Adoption*. arXiv:2511.01324. https://arxiv.org/html/2511.01324v2
6. Lawrence, R., & Green, P. *10 Anti-Patterns for User Story Splitting*. Humanizing Work. https://www.humanizingwork.com/10-anti-patterns-for-user-story-splitting/
7. Wikipedia. *Topological sorting*. https://en.wikipedia.org/wiki/Topological_sorting
8. Wikipedia. *Tarjan's strongly connected components algorithm*. https://en.wikipedia.org/wiki/Tarjan%27s_strongly_connected_components_algorithm

### Standards Referenced

- IEEE Std 830 - Software Requirements Specifications
- ISO/IEC/IEEE 29148 - Requirements Engineering

---

## Full Research Materials

Complete research artifacts available in `./RESEARCH/roadmap-decomposition/`:
- `08_report/` - All detailed findings
- `09_references.md` - Full bibliography
- `09_qa/` - Quality assurance audit

---

*Generated by deep-research agent on 2026-01-20*
