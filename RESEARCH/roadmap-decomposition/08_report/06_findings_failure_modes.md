# Findings: Failure Modes and Anti-Patterns

## SQ5: What are common failure modes and edge cases in PRD decomposition?

### The 10 Story Splitting Anti-Patterns

**Evidence Grade: A (Multiple independent authoritative sources)**

Richard Lawrence, Peter Green (Humanizing Work), and Roman Pichler have documented comprehensive anti-patterns that directly apply to PRD decomposition:

---

### Anti-Pattern 1: Split by Component (Horizontal Slicing)

**What it looks like:**
Decomposing a feature into UI, backend, and database PRDs.

**Why teams do it:**
- Matches organizational structure (frontend team, backend team)
- "Separate the concerns" seems like good advice
- Easier to assign to specialists

**Why it backfires:**
- No working software until everything integrates
- Integration is the hardest and riskiest part
- Feedback limited to those with technical skills
- Value delivery delayed to the end

**Detection Heuristic:**
```python
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
    # If only one layer mentioned extensively, likely horizontal
    return layers_mentioned == 1 and prd.is_technical_focused()
```

---

### Anti-Pattern 2: Split by Process Step

**What it looks like:**
"As a user, I can login" → "As a user, I can add items to cart" → "As a user, I can checkout"

**Why teams do it:**
- Maps to concrete user-visible parts
- Steps look somewhat independent

**Why it backfires:**
- Each step only valuable in relation to whole
- "Login" is useless without subsequent actions
- "Checkout" can't be tested without prior steps

**Detection Heuristic:**
```python
def is_process_step_split(prds):
    # Look for sequential temporal markers
    sequential_markers = ['then', 'after', 'next', 'before']
    # Look for login/setup steps with no standalone value
    setup_only_patterns = ['login', 'authenticate', 'connect', 'initialize']

    for prd in prds:
        if any(marker in prd.text.lower() for marker in setup_only_patterns):
            if not prd.has_standalone_value():
                return True
    return False
```

---

### Anti-Pattern 3: Split by Scenario (Happy Path vs Errors)

**What it looks like:**
"Happy path" first, "error handling" in next sprint.

**Why teams do it:**
- Error cases are plentiful and small
- Easy to make stories fit sprint capacity

**Why it backfires:**
- Creates tech debt from day one
- Original design doesn't account for edge cases
- Rework required when adding error handling
- "Small" stories require significant refactoring

**Detection Heuristic:**
```python
def is_happy_path_only(prd):
    # Missing error handling indicators
    error_keywords = ['error', 'fail', 'invalid', 'exception', 'edge case']
    has_error_handling = any(kw in prd.text.lower() for kw in error_keywords)

    # Has explicit happy path language
    happy_path_indicators = ['happy path', 'main flow', 'basic', 'simple case']
    is_happy_path_focused = any(ind in prd.text.lower() for ind in happy_path_indicators)

    return is_happy_path_focused and not has_error_handling
```

---

### Anti-Pattern 4: Build the "Core" First

**What it looks like:**
"We'll build the core/base/foundation first, then add features."

**Why teams do it:**
- Sounds efficient
- Foundation-first seems logical

**Why it backfires:**
- "Core" is usually big and vague
- Nothing to show until lots of work done
- Assumptions pile up without validation
- Core becomes hard to change

**Detection Heuristic:**
```python
def is_core_first(prd):
    core_indicators = ['core', 'base', 'foundation', 'infrastructure', 'framework']
    # Combined with lack of user-facing value
    has_core_language = any(ind in prd.text.lower() for ind in core_indicators)
    lacks_user_value = 'As a' not in prd.text and not prd.has_user_outcome()
    return has_core_language and lacks_user_value
```

---

### Anti-Pattern 5: Split by CRUD Operations

**What it looks like:**
Separate PRDs for Create, Read, Update, Delete of the same entity.

**Why teams do it:**
- Independently valuable actions... right?
- Easy to enumerate

**Why it backfires:**
- "Create" useless without "Read"
- "Delete" meaningless with only one item
- None deliver real user value in isolation

**Detection Heuristic:**
```python
def is_crud_split(prds):
    crud_verbs = ['create', 'read', 'update', 'delete', 'add', 'edit', 'remove', 'view']
    # Group PRDs by entity
    entities = group_by_entity(prds)
    for entity, entity_prds in entities.items():
        crud_count = sum(
            1 for prd in entity_prds
            if any(verb in prd.text.lower() for verb in crud_verbs)
        )
        # If multiple PRDs only differ by CRUD verb, flag
        if crud_count > 1 and len(entity_prds) == crud_count:
            return True
    return False
```

---

### Anti-Pattern 6: Split by Non-Varying Data

**What it looks like:**
"First phone number, then email, then address."

**Why teams do it:**
- Different data = different stories?
- Feels like incremental delivery

**Why it backfires:**
- All are just text fields
- No meaningful variation in processing
- Real value is in workflow, not field count

**Detection Heuristic:**
```python
def is_trivial_data_split(prds):
    # Detect PRDs that differ only in field names
    field_patterns = ['phone', 'email', 'address', 'name', 'field']
    field_prds = [
        prd for prd in prds
        if any(fp in prd.text.lower() for fp in field_patterns)
    ]
    # If PRDs are structurally identical except for field name
    if len(field_prds) > 1:
        structures = [extract_structure(prd) for prd in field_prds]
        if all_same_structure(structures):
            return True
    return False
```

---

### Anti-Pattern 7: Split by Interface When Not Meaningful

**What it looks like:**
"Web version first, mobile later."

**Why teams do it:**
- Feel like different features
- Matches team structure

**Why it backfires:**
- Usually more shared than different
- Real question: mobile-first or desktop-first?
- Once decided, split differently

**Detection Heuristic:**
```python
def is_superficial_interface_split(prds):
    interface_keywords = ['web', 'mobile', 'desktop', 'app', 'browser']
    # If PRDs differ only by interface
    for i, prd1 in enumerate(prds):
        for prd2 in prds[i+1:]:
            if differs_only_by_interface(prd1, prd2, interface_keywords):
                return True
    return False
```

---

### Anti-Pattern 8: Split by Conjunction

**What it looks like:**
Story has "and" → split at "and."

**Why teams do it:**
- Common heuristic (even in flowcharts)
- Mechanical and easy

**Why it backfires:**
- "Login and check balance" → "Login" alone isn't a story
- Creates duplicate setup across stories
- Often produces tasks, not stories

**Detection Heuristic:**
```python
def is_bad_conjunction_split(prd):
    # If PRD is essentially "setup only"
    setup_verbs = ['login', 'connect', 'authenticate', 'open', 'navigate']
    # With no subsequent action value
    if prd.text.lower().startswith(tuple(setup_verbs)):
        if not prd.has_outcome_beyond_setup():
            return True
    return False
```

---

### Anti-Pattern 9: Split by Non-Varying Roles

**What it looks like:**
"As admin, I can..." then "As user, I can..." for same feature.

**Why teams do it:**
- Told not to use generic "user"
- Different roles exist in system

**Why it backfires:**
- Roles may not be meaningfully different
- Creates duplicate backlog items
- More tracking overhead

**Detection Heuristic:**
```python
def is_superficial_role_split(prds):
    # Group by feature (excluding role)
    features = group_by_feature_excluding_role(prds)
    for feature, feature_prds in features.items():
        if len(feature_prds) > 1:
            # If only difference is role and functionality is same
            if functionality_is_same(feature_prds):
                return True
    return False
```

---

### Anti-Pattern 10: Split by Test Cases

**What it looks like:**
Each acceptance criterion becomes a PRD.

**Why teams do it:**
- Acceptance criteria are small pieces
- Quick way to create small stories

**Why it backfires:**
- Acceptance criterion ≠ unit of value
- Stories should be minimum viable value
- Creates incomplete, hard-to-track pieces

**Detection Heuristic:**
```python
def is_acceptance_criteria_as_prd(prd):
    # PRD that reads like a test case
    test_patterns = ['verify that', 'given', 'when', 'then', 'should', 'assert']
    test_pattern_count = sum(
        1 for pattern in test_patterns
        if pattern in prd.text.lower()
    )
    # If mostly test language without feature description
    return test_pattern_count >= 2 and not prd.has_feature_description()
```

---

## Backlog-Level Anti-Patterns

### Large Product Backlog (Wishlist)

**Root Causes:**
- Failure to fix bugs when found (adding to backlog instead)
- Misuse of tools making long lists easy to create
- Lack of portfolio management
- Breaking down items too far in advance

**Detection:**
```python
def has_wishlist_antipattern(backlog):
    return (
        len(backlog.items) > 100 or
        backlog.oldest_untouched_age() > 90 or  # days
        backlog.completion_rate() < 0.1  # < 10% ever completed
    )
```

### Dependent Stories

**Problem:** Heavy dependencies create coordination overhead and risk.

**Resolution Options:**
1. Combine dependent stories
2. Re-slice to break dependencies
3. Accept dependency but minimize chain length

---

## The Universal Test

**"Could you demo this to a stakeholder and have them care?"**

If no → not a valid split.

This test catches most anti-patterns because they all share a common flaw: **the resulting pieces don't deliver independent value**.

---

## Composite Anti-Pattern Detector

```python
class AntiPatternDetector:
    def __init__(self):
        self.checks = [
            ('horizontal_slice', is_horizontal_slice),
            ('process_step', is_process_step_split),
            ('happy_path_only', is_happy_path_only),
            ('core_first', is_core_first),
            ('crud_split', is_crud_split),
            ('trivial_data', is_trivial_data_split),
            ('superficial_interface', is_superficial_interface_split),
            ('bad_conjunction', is_bad_conjunction_split),
            ('superficial_role', is_superficial_role_split),
            ('test_case_as_prd', is_acceptance_criteria_as_prd),
        ]

    def analyze(self, prds):
        issues = []
        for name, check in self.checks:
            if check(prds):
                issues.append({
                    'pattern': name,
                    'severity': self._get_severity(name),
                    'recommendation': self._get_recommendation(name)
                })
        return issues

    def _get_severity(self, pattern):
        high_severity = ['horizontal_slice', 'core_first', 'happy_path_only']
        return 'HIGH' if pattern in high_severity else 'MEDIUM'

    def _get_recommendation(self, pattern):
        recommendations = {
            'horizontal_slice': 'Re-slice vertically through all layers',
            'process_step': 'Split by value variation, not workflow step',
            'happy_path_only': 'Include relevant error handling from start',
            'core_first': 'Deliver thin end-to-end slice first',
            'crud_split': 'Keep CRUD together or split by data variation',
            'trivial_data': 'Split by what users DO with data, not field names',
            'superficial_interface': 'Determine design-first decision, then split differently',
            'bad_conjunction': 'Ensure both parts deliver standalone value',
            'superficial_role': 'Split by permission needs, not role names',
            'test_case_as_prd': 'Group criteria into features, split differently',
        }
        return recommendations.get(pattern, 'Review and re-slice')
```
