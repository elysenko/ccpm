# Roadmap Generate - Create MVP Roadmap from Scope Document

Transform a scope document into a phased MVP implementation roadmap with prioritized features, dependencies, and success criteria.

## Usage
```
/pm:roadmap-generate <session-name> [--phases N]
```

## Arguments
- `session-name` (required): Name of the scoped session (from /pm:extract-findings)
- `--phases N` (optional): Number of phases to generate (default: 4)

## Input
**Required:** `.claude/scopes/{session-name}/` containing:
- `00_scope_document.md`
- `01_features.md`
- `02_user_journeys.md`
- `04_technical_architecture.md`

## Output
**File:** `.claude/scopes/{session-name}/07_roadmap.md`

---

## Process

### Step 1: Initialize and Validate

```bash
SESSION_NAME="${ARGUMENTS%% *}"
PHASES="${ARGUMENTS#*--phases }"
[ "$PHASES" = "$ARGUMENTS" ] && PHASES=4
SCOPE_DIR=".claude/scopes/$SESSION_NAME"
```

Verify scope directory exists:
```
If .claude/scopes/{session-name}/ doesn't exist:
❌ Scope not found: {session-name}

Run /pm:extract-findings {session-name} first
```

Read:
- `$SCOPE_DIR/00_scope_document.md`
- `$SCOPE_DIR/01_features.md`
- `$SCOPE_DIR/02_user_journeys.md`
- `$SCOPE_DIR/04_technical_architecture.md`

---

### Step 2: Parse Features with MoSCoW Categories

Extract features from `01_features.md` and group by priority:

```
MUST_HAVE = []     # MVP backbone - product broken without these
SHOULD_HAVE = []   # MVP enhancement - makes product competitive
COULD_HAVE = []    # Post-MVP - nice-to-have
WONT_HAVE = []     # Out of scope
```

For each feature, extract:
- ID (F-001, etc.)
- Name
- Description
- Priority (Must Have / Should Have / Could Have / Won't Have)
- Acceptance criteria count
- Related features (dependencies)

---

### Step 3: Apply RICE Scoring

For each feature in SHOULD_HAVE and COULD_HAVE, estimate RICE score:

```
RICE = (Reach × Impact × Confidence) / Effort
```

**Reach** (users affected per quarter):
- Estimate from user journeys and feature scope
- Use relative scale: 1000 = all users, 100 = subset, 10 = few

**Impact** (contribution to goal):
| Score | Definition |
|-------|------------|
| 3 | Massive - core value proposition |
| 2 | High - significant improvement |
| 1 | Medium - noticeable improvement |
| 0.5 | Low - minor improvement |
| 0.25 | Minimal - barely noticeable |

**Confidence** (how sure are we):
| Score | Definition |
|-------|------------|
| 100% | High - clear requirements, proven approach |
| 80% | Medium - some unknowns but manageable |
| 50% | Low - significant uncertainty |

**Effort** (person-days):
- Estimate based on acceptance criteria count and complexity
- Use T-shirt sizing converted to days:
  - XS: 1 day
  - S: 2-3 days
  - M: 5 days
  - L: 10 days
  - XL: 20+ days

**Sort features by RICE score descending within each category.**

---

### Step 4: Map Dependencies

Build dependency graph from "Related Features" in feature list:

```
For each feature:
  DEPENDS_ON = [features it requires]
  ENABLES = [features that require it]
```

**Dependency types to identify:**
1. **Feature dependencies** - Feature B needs Feature A's data/capability
2. **Technical dependencies** - Shared components, APIs, database schemas
3. **External dependencies** - Third-party integrations, vendor work

**Detect circular dependencies:**
```
If A → B → C → A detected:
  ⚠️ Circular dependency: A ↔ B ↔ C
  Recommendation: Combine into single feature or break cycle
```

---

### Step 5: Define Walking Skeleton (Phase 0)

The walking skeleton is a tiny end-to-end implementation that proves the architecture works.

**Extract from technical architecture:**

| Layer | Walking Skeleton Deliverable |
|-------|------------------------------|
| Frontend | Single page with basic interaction |
| API | One endpoint with full request/response cycle |
| Business Logic | Minimal processing (happy path only) |
| Database | Core tables with basic CRUD |
| Infrastructure | CI/CD pipeline deploying to staging |

**Walking Skeleton Exit Criteria:**
- [ ] Frontend renders and calls API
- [ ] API endpoint returns data from database
- [ ] Changes deploy automatically to staging
- [ ] Basic error handling works
- [ ] Logging captures requests

---

### Step 6: Sequence Features into Phases

#### Phase 0: Foundation (Walking Skeleton)
**Goal:** Prove architecture end-to-end
**Features:** Infrastructure, auth scaffolding, CI/CD

#### Phase 1: MVP Core
**Goal:** Deliver minimum viable product
**Features:** All MUST_HAVE features
**Sequencing:**
1. Features with no dependencies first
2. Then features whose dependencies are satisfied
3. Apply topological sort (Kahn's algorithm)

#### Phase 2: MVP Enhancement
**Goal:** Competitive advantage
**Features:** High-RICE SHOULD_HAVE features (top 50%)
**Sequencing:** By RICE score, respecting dependencies

#### Phase 3+: Post-MVP
**Goal:** Complete vision
**Features:** Remaining SHOULD_HAVE and COULD_HAVE
**Sequencing:** By RICE score, respecting dependencies

**Topological Sort Algorithm:**
```
function topological_sort(features):
    sorted = []
    no_deps = [f for f in features if f.depends_on == []]

    while no_deps:
        f = no_deps.pop(0)
        sorted.append(f)
        for dependent in f.enables:
            dependent.depends_on.remove(f)
            if dependent.depends_on == []:
                no_deps.append(dependent)

    if any remaining features with unmet deps:
        ERROR: Circular dependency detected

    return sorted
```

---

### Step 7: Define Exit Criteria Per Phase

For each phase, define:

**Functional Criteria:**
- Which features are complete (all acceptance criteria pass)
- Which user journeys work end-to-end

**Quality Criteria:**
- Test coverage target (e.g., 70% for MVP)
- Performance thresholds met
- Security checklist passed

**Deployment Criteria:**
- Environment requirements (staging → production)
- Rollback capability verified
- Monitoring in place

**Stakeholder Criteria:**
- Demo completed
- Sign-off obtained

---

### Step 8: Generate Roadmap Document

Write to `$SCOPE_DIR/07_roadmap.md`:

```markdown
# MVP Roadmap: {Project Name}

**Version:** 1.0
**Created:** {datetime}
**Source:** .claude/scopes/{session-name}/
**Status:** Draft

---

## Executive Summary

**Vision:** {one-line vision from scope}

**MVP Definition:** {what is the minimum viable product}

**Phase Summary:**
| Phase | Goal | Features | Exit Criteria |
|-------|------|----------|---------------|
| 0 | Foundation | Walking skeleton | Architecture proven |
| 1 | MVP Core | {count} Must Haves | Beta launch |
| 2 | Enhancement | {count} Should Haves | Public launch |
| 3+ | Complete | {count} remaining | Full vision |

---

## Phase 0: Foundation (Walking Skeleton)

**Goal:** Establish technical infrastructure and prove architecture

**Duration Estimate:** Sprint 1-2

### Deliverables

| Layer | Deliverable | Status |
|-------|-------------|--------|
| Frontend | {framework} app with routing | ⬜ |
| API | {protocol} endpoint with auth | ⬜ |
| Database | Core schema with {count} tables | ⬜ |
| Infrastructure | CI/CD to staging | ⬜ |
| Observability | Logging + error tracking | ⬜ |

### Exit Criteria
- [ ] End-to-end request works (UI → API → DB → UI)
- [ ] Automatic deployment to staging
- [ ] Basic authentication functional
- [ ] Logging captures all requests
- [ ] Team can develop and deploy independently

---

## Phase 1: MVP Core

**Goal:** Deliver minimum viable product

**Duration Estimate:** Sprint 3-{N}

### Features (Must Have)

| Order | ID | Feature | Dependencies | Effort | Status |
|-------|----|---------|--------------| -------|--------|
| 1 | F-XXX | {name} | None | {size} | ⬜ |
| 2 | F-XXX | {name} | F-001 | {size} | ⬜ |
...

### User Journeys Enabled
- J-XXX: {journey name}
- J-XXX: {journey name}

### Exit Criteria
- [ ] All Must Have features complete
- [ ] Primary user journey works end-to-end
- [ ] Test coverage > {target}%
- [ ] Performance meets targets
- [ ] Security review passed
- [ ] Beta users can access system

---

## Phase 2: MVP Enhancement

**Goal:** Improve based on feedback, gain competitive advantage

**Duration Estimate:** Sprint {N+1}-{M}

### Features (High-Priority Should Have)

| Order | ID | Feature | RICE Score | Dependencies | Effort | Status |
|-------|----|---------| -----------|--------------|--------|--------|
| 1 | F-XXX | {name} | {score} | {deps} | {size} | ⬜ |
...

### Exit Criteria
- [ ] Top {N} Should Have features complete
- [ ] User feedback incorporated
- [ ] Performance optimized
- [ ] Public launch criteria met

---

## Phase 3+: Post-MVP

**Goal:** Complete product vision

### Backlog (Prioritized by RICE)

| Priority | ID | Feature | RICE Score | Category |
|----------|----|---------|------------|----------|
| 1 | F-XXX | {name} | {score} | Should Have |
| 2 | F-XXX | {name} | {score} | Could Have |
...

---

## Dependency Map

### Feature Dependencies

```
{Visual dependency graph}

F-001 ──→ F-003 ──→ F-007
   │         │
   └──→ F-002 ──→ F-005
```

### External Dependencies

| Dependency | Type | Impact | Mitigation |
|------------|------|--------|------------|
| {vendor} | Integration | Blocks F-XXX | Early engagement |
...

---

## RICE Scores (Full List)

| ID | Feature | Reach | Impact | Confidence | Effort | RICE |
|----|---------|-------|--------|------------|--------|------|
...

---

## Risk Considerations

### High-Risk Features
{Features with low confidence or complex dependencies}

### Mitigation Strategies
{Spikes, early integration, fallback options}

---

## Success Metrics

| Phase | Metric | Target | Measurement |
|-------|--------|--------|-------------|
| 1 | Beta users | {N} | Active signups |
| 2 | Activation | {N}% | Complete onboarding |
| Launch | {KPI} | {target} | {method} |

---

## Next Steps

1. **Review roadmap** with stakeholders
2. **Resolve blockers** before Phase 0
3. **Start development:**
   ```bash
   /pm:prd-parse {session-name}
   # Creates PRDs for each feature
   ```
4. **Track progress:**
   ```bash
   /pm:epic-status {epic-name}
   ```

---

## Appendix

### A. Feature-Journey Matrix

| Feature | J-001 | J-002 | J-003 |
|---------|-------|-------|-------|
| F-001 | ✓ | | ✓ |
...

### B. Effort Estimation Basis
- XS: < 1 day (trivial change)
- S: 1-3 days (small feature)
- M: 3-5 days (medium feature)
- L: 5-10 days (large feature)
- XL: 10+ days (epic-scale)

### C. RICE Scoring Methodology
See research-report.md for detailed methodology.
```

---

### Step 9: Present Summary

```
✅ Roadmap generated: {session-name}

Summary: {1-sentence project + MVP description}

Phases:
- Phase 0 (Foundation): {deliverables count} deliverables
- Phase 1 (MVP Core): {count} Must Have features
- Phase 2 (Enhancement): {count} Should Have features
- Phase 3+ (Post-MVP): {count} remaining features

Feature Breakdown:
| Category | Count | Est. Effort |
|----------|-------|-------------|
| Must Have | {N} | {days} days |
| Should Have | {N} | {days} days |
| Could Have | {N} | {days} days |
| Won't Have | {N} | - |

Dependencies:
- {N} feature dependencies mapped
- {N} external dependencies identified
- {N} potential blockers flagged

Output: .claude/scopes/{session-name}/07_roadmap.md

Next Steps:
1. Review roadmap with stakeholders
2. Resolve external dependencies
3. Start Phase 0: /pm:prd-parse {session-name}
```

---

## Important Rules

1. **Walking skeleton first** - Always start with Phase 0 to prove architecture
2. **Vertical slices** - Each feature should work end-to-end (UI → API → DB)
3. **RICE for ordering** - Use quantitative scoring, not gut feel
4. **Respect dependencies** - Never schedule a feature before its dependencies
5. **Exit criteria required** - Every phase needs measurable completion criteria
6. **No time estimates** - Use effort sizes (S/M/L) not calendar dates
7. **Must Have = MVP** - If it's not Must Have, it's not MVP
8. **Defer wisely** - Could Have items are explicitly post-MVP

---

## Framework Reference

### MoSCoW Definitions
| Category | MVP? | Definition |
|----------|------|------------|
| Must Have | YES | Product is broken without it |
| Should Have | Partial | Makes product competitive |
| Could Have | NO | Nice-to-have |
| Won't Have | NO | Explicitly excluded |

### RICE Formula
```
RICE = (Reach × Impact × Confidence) / Effort

Impact: 3=massive, 2=high, 1=medium, 0.5=low, 0.25=minimal
Confidence: 100%=high, 80%=medium, 50%=low
Effort: person-days
```

### Phase Template
```markdown
## Phase N: {Name}

**Goal:** {One sentence}
**Duration:** Sprint X-Y

### Features
| Order | ID | Feature | Dependencies | Effort |
|-------|----|---------|--------------| -------|

### Exit Criteria
- [ ] {Functional criterion}
- [ ] {Quality criterion}
- [ ] {Deployment criterion}
```

---

## Sources

This roadmap methodology is based on:
- Intercom RICE Framework
- SAFe WSJF (Weighted Shortest Job First)
- Kano Model for feature categorization
- Walking Skeleton pattern (Alistair Cockburn)
- Vertical Slice Architecture (Jimmy Bogard)

Research: See `research-report.md` for detailed methodology.
