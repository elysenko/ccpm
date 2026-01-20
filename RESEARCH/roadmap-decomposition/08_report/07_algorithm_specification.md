# Algorithm Specification: pm:decompose

## Overview

This specification defines the algorithm for automatically decomposing a roadmap into independent, well-bounded PRDs with proper dependency management.

---

## Input Schema

```yaml
roadmap_item:
  id: string                    # Unique identifier
  title: string                 # Short descriptive title
  description: string           # Full description/context
  type: enum[epic|feature|initiative]
  domain: string                # Business domain (optional)
  constraints:                  # Optional constraints
    max_prds: integer           # Maximum PRDs to generate
    target_size: enum[small|medium|large]
    must_include: list[string]  # Required capabilities
    must_exclude: list[string]  # Excluded capabilities
  existing_context:             # Optional existing system info
    related_prds: list[prd_id]
    existing_components: list[string]
    tech_stack: list[string]
```

---

## Output Schema

```yaml
decomposition_result:
  prds: list[prd]
  dependency_graph:
    nodes: list[prd_id]
    edges: list[{from: prd_id, to: prd_id, type: string}]
  validation:
    invest_scores: map[prd_id, invest_score]
    antipatterns: list[antipattern_warning]
    dag_valid: boolean
    cycle_info: optional[cycle_details]
  metadata:
    confidence: float           # 0-1 confidence score
    requires_review: boolean
    suggestions: list[string]
    generation_timestamp: datetime

prd:
  id: string
  title: string
  description: string
  user_story: string            # "As a..., I want..., so that..."
  acceptance_criteria: list[string]
  dependencies: list[prd_id]
  estimated_size: enum[XS|S|M|L|XL]
  invest_score: invest_score
  tags: list[string]

invest_score:
  independent: float            # 0-1
  negotiable: float             # 0-1
  valuable: float               # 0-1
  estimable: float              # 0-1
  small: float                  # 0-1
  testable: float               # 0-1
  composite: float              # Weighted average
  conflicts: list[string]       # Trade-off warnings
```

---

## Algorithm: Main Flow

```python
def decompose(roadmap_item: RoadmapItem) -> DecompositionResult:
    """
    Main decomposition algorithm.

    Phases:
    1. Pre-processing and context extraction
    2. LLM-based initial decomposition
    3. INVEST validation and scoring
    4. Dependency graph construction
    5. Anti-pattern detection
    6. Confidence calculation
    7. Output packaging
    """

    # Phase 1: Pre-processing
    context = extract_context(roadmap_item)
    decomposition_strategy = select_strategy(roadmap_item, context)

    # Phase 2: LLM Decomposition
    draft_prds = llm_decompose(roadmap_item, decomposition_strategy)

    # Apply consistency check
    consistency_score = check_consistency(roadmap_item, draft_prds)
    if consistency_score < 0.6:
        draft_prds = regenerate_with_feedback(roadmap_item, draft_prds)

    # Phase 3: INVEST Validation
    for prd in draft_prds:
        prd.invest_score = calculate_invest_score(prd)

    # Phase 4: Dependency Graph
    dag = build_dependency_dag(draft_prds)
    dag_validation = validate_dag(dag)

    if not dag_validation.is_valid:
        # Attempt to fix cycles
        draft_prds, dag = resolve_cycles(draft_prds, dag, dag_validation)

    # Phase 5: Anti-Pattern Detection
    antipatterns = detect_antipatterns(draft_prds)

    # Phase 6: Confidence Calculation
    confidence = calculate_confidence(
        consistency_score,
        draft_prds,
        dag_validation,
        antipatterns
    )

    # Phase 7: Package Output
    return DecompositionResult(
        prds=draft_prds,
        dependency_graph=dag,
        validation={
            'invest_scores': {prd.id: prd.invest_score for prd in draft_prds},
            'antipatterns': antipatterns,
            'dag_valid': dag_validation.is_valid,
            'cycle_info': dag_validation.cycles if not dag_validation.is_valid else None
        },
        metadata={
            'confidence': confidence,
            'requires_review': confidence < 0.7,
            'suggestions': generate_suggestions(draft_prds, antipatterns),
            'generation_timestamp': datetime.utcnow()
        }
    )
```

---

## Phase 2: LLM Decomposition

### Strategy Selection

```python
def select_strategy(item: RoadmapItem, context: Context) -> Strategy:
    """
    Select decomposition strategy based on item characteristics.
    """
    if item.type == 'epic':
        # Large items: Story mapping approach
        return Strategy.STORY_MAPPING
    elif has_clear_user_journeys(item):
        # Multiple user paths: SPIDR-Paths
        return Strategy.SPIDR_PATHS
    elif has_business_rules(item):
        # Rule variations: SPIDR-Rules
        return Strategy.SPIDR_RULES
    elif has_data_variations(item):
        # Data type variations: SPIDR-Data
        return Strategy.SPIDR_DATA
    else:
        # Default: Vertical slice
        return Strategy.VERTICAL_SLICE
```

### LLM Prompt Template

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
2. Use VERTICAL SLICES (touch all layers: UI → API → Data)
3. Avoid these anti-patterns:
   - Splitting by technical component
   - Splitting by process step without independent value
   - Separating happy path from error handling
   - Building "core" without end-to-end functionality

## SPIDR Techniques (apply in order: R → D → I → P → S)
- Rules: Can we defer business rules to simplify?
- Data: Are there meaningful data variations?
- Interface: Do interfaces differ significantly?
- Paths: Are there alternative user paths?
- Spikes: Is research needed before deciding?

## Example Good Decomposition
Input: "User can purchase products online"
Output PRDs:
1. "Purchase single product with credit card" (MVP vertical slice)
2. "Purchase with alternative payment methods" (PayPal, Apple Pay)
3. "Purchase multiple products in one transaction"
4. "Apply discount codes to purchase"

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
  "prds": [
    {{
      "id": "PRD-001",
      "title": "...",
      "user_story": "As a ..., I want ..., so that ...",
      "acceptance_criteria": ["...", "..."],
      "dependencies": [],
      "size": "M"
    }}
  ],
  "rationale": "Brief explanation of decomposition approach"
}}
```
"""
```

---

## Phase 3: INVEST Validation

```python
def calculate_invest_score(prd: PRD) -> INVESTScore:
    scores = {}

    # Independent (0-1)
    scores['independent'] = calculate_independence(prd)

    # Negotiable (0-1)
    scores['negotiable'] = calculate_negotiability(prd)

    # Valuable (0-1)
    scores['valuable'] = calculate_value(prd)

    # Estimable (0-1)
    scores['estimable'] = calculate_estimability(prd)

    # Small (0-1)
    scores['small'] = calculate_size_score(prd)

    # Testable (0-1)
    scores['testable'] = calculate_testability(prd)

    # Weighted composite
    weights = {
        'independent': 0.25,
        'negotiable': 0.05,
        'valuable': 0.20,
        'estimable': 0.15,
        'small': 0.15,
        'testable': 0.20
    }
    composite = sum(scores[k] * weights[k] for k in scores)

    # Detect conflicts
    conflicts = []
    if scores['independent'] < 0.6 and scores['small'] > 0.8:
        conflicts.append("Trade-off: high small score may indicate broken independence")

    return INVESTScore(
        **scores,
        composite=composite,
        conflicts=conflicts
    )


def calculate_independence(prd: PRD) -> float:
    """Score 0-1 for independence."""
    dependency_keywords = ['depends on', 'requires', 'after', 'when complete', 'blocked by']
    keyword_count = sum(1 for kw in dependency_keywords if kw in prd.full_text.lower())

    explicit_deps = len(prd.dependencies)

    # More dependencies = lower score
    score = 1.0 - min(1.0, (keyword_count * 0.15 + explicit_deps * 0.2))
    return max(0, score)


def calculate_value(prd: PRD) -> float:
    """Score 0-1 for value delivery."""
    score = 0.0

    # Has user role
    if re.search(r'[Aa]s a[n]?\s+\w+', prd.user_story):
        score += 0.3

    # Has outcome/benefit
    if 'so that' in prd.user_story.lower():
        score += 0.3

    # Has action verb (not just setup)
    action_verbs = ['purchase', 'create', 'view', 'manage', 'track', 'analyze', 'share']
    if any(verb in prd.full_text.lower() for verb in action_verbs):
        score += 0.2

    # No technical jargon dominating
    tech_ratio = count_tech_terms(prd) / word_count(prd)
    if tech_ratio < 0.2:
        score += 0.2

    return min(1.0, score)


def calculate_testability(prd: PRD) -> float:
    """Score 0-1 for testability."""
    score = 0.0

    # Has acceptance criteria
    if prd.acceptance_criteria:
        score += 0.4
        # Criteria are structured (Given-When-Then or similar)
        structured_count = sum(
            1 for ac in prd.acceptance_criteria
            if re.search(r'(given|when|then|should|verify)', ac.lower())
        )
        structure_ratio = structured_count / len(prd.acceptance_criteria)
        score += 0.3 * structure_ratio

    # Has measurable outcomes
    if re.search(r'\d+\s*(seconds?|minutes?|%|items?|users?)', prd.full_text):
        score += 0.3

    return min(1.0, score)
```

---

## Phase 4: Dependency Graph

```python
def build_dependency_dag(prds: List[PRD]) -> DependencyDAG:
    """Build DAG from PRD dependencies."""
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
            success, error = dag.add_edge(from_id, to_id, type='implicit')
            if success:
                dag.add_note(f"Inferred dependency: {from_id} -> {to_id}")

    return dag


def detect_implicit_dependencies(prds: List[PRD]) -> List[Tuple[str, str, float]]:
    """
    Detect dependencies not explicitly stated.

    Looks for:
    - Shared entity references
    - Temporal language
    - API/data dependencies
    """
    dependencies = []

    entities = {}
    for prd in prds:
        prd_entities = extract_entities(prd)
        entities[prd.id] = prd_entities

    # If PRD A creates entity X and PRD B uses entity X, A -> B
    for prd_a in prds:
        for prd_b in prds:
            if prd_a.id == prd_b.id:
                continue

            creates_a = entities[prd_a.id].get('creates', set())
            uses_b = entities[prd_b.id].get('uses', set())

            shared = creates_a & uses_b
            if shared:
                confidence = min(1.0, len(shared) * 0.3)
                dependencies.append((prd_a.id, prd_b.id, confidence))

    return dependencies


def validate_dag(dag: DependencyDAG) -> DAGValidation:
    """Validate DAG properties."""
    # Check for cycles
    cycles = dag.find_cycles()

    # Check depth
    max_depth = dag.calculate_max_depth()

    # Check for orphans
    orphans = dag.find_orphans()

    return DAGValidation(
        is_valid=len(cycles) == 0,
        cycles=cycles,
        max_depth=max_depth,
        orphans=orphans,
        warnings=[
            f"Depth {max_depth} may indicate over-decomposition"
            if max_depth > 5 else None,
            f"Orphan PRDs: {orphans}" if orphans else None
        ]
    )
```

---

## Phase 5: Anti-Pattern Detection

```python
def detect_antipatterns(prds: List[PRD]) -> List[AntipatternWarning]:
    """Run all anti-pattern checks."""
    warnings = []

    # Individual PRD checks
    for prd in prds:
        if is_horizontal_slice(prd):
            warnings.append(AntipatternWarning(
                pattern='horizontal_slice',
                prd_ids=[prd.id],
                severity='HIGH',
                recommendation='Re-slice to include all layers (UI, API, Data)'
            ))

        if is_happy_path_only(prd):
            warnings.append(AntipatternWarning(
                pattern='happy_path_only',
                prd_ids=[prd.id],
                severity='HIGH',
                recommendation='Add key error handling to this PRD'
            ))

        if is_core_first(prd):
            warnings.append(AntipatternWarning(
                pattern='core_first',
                prd_ids=[prd.id],
                severity='HIGH',
                recommendation='Deliver thin end-to-end slice instead of core'
            ))

    # Multi-PRD checks
    if is_crud_split(prds):
        warnings.append(AntipatternWarning(
            pattern='crud_split',
            prd_ids=[p.id for p in prds],
            severity='MEDIUM',
            recommendation='Combine CRUD operations or split by data variation'
        ))

    if is_process_step_split(prds):
        warnings.append(AntipatternWarning(
            pattern='process_step_split',
            prd_ids=[p.id for p in prds],
            severity='MEDIUM',
            recommendation='Each PRD should deliver standalone value'
        ))

    return warnings
```

---

## Phase 6: Confidence Calculation

```python
def calculate_confidence(
    consistency: float,
    prds: List[PRD],
    dag_validation: DAGValidation,
    antipatterns: List[AntipatternWarning]
) -> float:
    """
    Calculate overall confidence score.

    Factors:
    - LLM consistency across regenerations
    - Average INVEST scores
    - DAG validity
    - Anti-pattern severity
    """
    # Base from consistency
    confidence = consistency * 0.3

    # INVEST contribution
    avg_invest = sum(prd.invest_score.composite for prd in prds) / len(prds)
    confidence += avg_invest * 0.3

    # DAG validity
    if dag_validation.is_valid:
        confidence += 0.2
    else:
        confidence += 0.05  # Some credit for detection

    # Anti-pattern penalty
    high_severity = sum(1 for w in antipatterns if w.severity == 'HIGH')
    medium_severity = sum(1 for w in antipatterns if w.severity == 'MEDIUM')
    antipattern_penalty = high_severity * 0.1 + medium_severity * 0.05
    confidence += max(0, 0.2 - antipattern_penalty)

    return min(1.0, confidence)
```

---

## Error Handling

```python
class DecompositionError(Exception):
    """Base error for decomposition failures."""
    pass

class CycleUnresolvableError(DecompositionError):
    """Cycles could not be resolved automatically."""
    pass

class LLMFailureError(DecompositionError):
    """LLM generation failed or returned invalid output."""
    pass


def resolve_cycles(
    prds: List[PRD],
    dag: DependencyDAG,
    validation: DAGValidation
) -> Tuple[List[PRD], DependencyDAG]:
    """
    Attempt to resolve dependency cycles.

    Strategies:
    1. Remove lowest-confidence implicit dependencies
    2. Suggest PRD merging
    3. Flag for human review if unresolvable
    """
    for cycle in validation.cycles:
        # Try removing implicit edges in cycle
        for i in range(len(cycle)):
            from_id = cycle[i]
            to_id = cycle[(i + 1) % len(cycle)]

            edge = dag.get_edge(from_id, to_id)
            if edge and edge.type == 'implicit':
                dag.remove_edge(from_id, to_id)
                break
        else:
            # No implicit edges to remove
            raise CycleUnresolvableError(
                f"Cannot automatically resolve cycle: {' -> '.join(cycle)}"
            )

    # Re-validate
    new_validation = validate_dag(dag)
    if not new_validation.is_valid:
        raise CycleUnresolvableError("Cycles remain after resolution attempt")

    return prds, dag
```

---

## Usage Example

```python
# Initialize decomposer
decomposer = PRDDecomposer(
    llm=ClaudeClient(),
    confidence_threshold=0.7
)

# Define roadmap item
roadmap_item = RoadmapItem(
    id="EPIC-001",
    title="User Authentication System",
    description="""
    Implement complete user authentication including:
    - Email/password registration and login
    - Social login (Google, GitHub)
    - Password reset flow
    - Session management
    - Two-factor authentication
    """,
    type="epic"
)

# Decompose
result = decomposer.decompose(roadmap_item)

# Check result
if result.metadata['requires_review']:
    print("Human review required")
    print(f"Confidence: {result.metadata['confidence']:.2f}")
    print(f"Issues: {len(result.validation['antipatterns'])}")

# Access PRDs
for prd in result.prds:
    print(f"{prd.id}: {prd.title}")
    print(f"  INVEST: {prd.invest_score.composite:.2f}")
    print(f"  Dependencies: {prd.dependencies}")
```
