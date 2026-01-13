# Extract Findings - Generate Comprehensive Scoping Document

Transform interrogation transcripts into a **development-ready scoping document** including requirements, technical architecture, integrations, risks, and more.

## Usage
```
/pm:extract-findings <session-name>
```

## Arguments
- `session-name` (required): Name of the interrogation session to analyze

## Output

**Directory:** `.claude/scopes/{session-name}/`

| File | Contents |
|------|----------|
| `00_scope_document.md` | Unified comprehensive scope document |
| `01_features.md` | Extracted features catalog |
| `02_user_journeys.md` | Mapped user journeys |
| `03_nfr_requirements.md` | Derived non-functional requirements |
| `04_technical_architecture.md` | Tech stack, integrations, ADRs |
| `05_risk_assessment.md` | Risk analysis and mitigations |
| `06_gap_analysis.md` | Missing info and clarification questions |

---

## Multi-Pass Extraction Process

```
conversation.md
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ PASS 1: Feature Extraction                          │
│ Extract discrete capabilities → 01_features.md      │
└─────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ PASS 2: User Journey Mapping                        │
│ Map step-by-step flows → 02_user_journeys.md        │
└─────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ PASS 3: Context & Constraints Extraction            │
│ Timeline, budget, success criteria, decisions       │
└─────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ PASS 4: Implicit Requirements Derivation            │
│ Apply NFR checklist → 03_nfr_requirements.md        │
└─────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ PASS 5: Technical Architecture Mapping              │
│ Stack, integrations, ADRs → 04_technical_arch.md    │
└─────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ PASS 6: Risk Assessment                             │
│ Technical, business, integration → 05_risks.md      │
└─────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ PASS 7: Gap Analysis                                │
│ Missing info, contradictions → 06_gap_analysis.md   │
└─────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ PASS 8: Synthesis                                   │
│ Compile everything → 00_scope_document.md           │
└─────────────────────────────────────────────────────┘
```

---

## Instructions

### Step 1: Initialize

```bash
SESSION_NAME="$ARGUMENTS"
CONV_DIR=".claude/interrogations/$SESSION_NAME"
CONV_FILE="$CONV_DIR/conversation.md"
SCOPE_DIR=".claude/scopes/$SESSION_NAME"
mkdir -p "$SCOPE_DIR"
```

**Verify session exists and is complete:**

If conversation.md doesn't exist or status is "in_progress":
```
❌ Session not found or incomplete: {session-name}

Resume interrogation: ./interrogate.sh {session-name}
```

Read the entire conversation.md file. Note the Type and Domain from header.

---

### Step 2: PASS 1 - Feature Extraction

**Goal:** Extract all discrete capabilities mentioned or implied.

Scan conversation for:
- Explicit capability requests ("users should be able to...")
- Actions mentioned ("upload", "approve", "export", "notify")
- System behaviors ("automatically...", "validates...", "calculates...")
- Feature confirmations ("Yes, that's right", "Exactly")

**For each feature, extract:**

| Field | Description |
|-------|-------------|
| ID | F-001, F-002, etc. |
| Name | Concise name (2-5 words) |
| Description | What it does (2-3 sentences) |
| User Story | As a [persona], I want [action] so that [benefit] |
| Acceptance Criteria | How we know it's done |
| Priority | Must Have / Should Have / Could Have / Won't Have |
| Stakeholder Source | Who mentioned it |
| Evidence | Verbatim quote from conversation |
| Related Features | Dependencies |
| Confidence | HIGH / MEDIUM / LOW |

**Write to:** `$SCOPE_DIR/01_features.md`

---

### Step 3: PASS 2 - User Journey Mapping

**Goal:** Map all step-by-step flows users will perform.

Scan conversation for:
- Step descriptions ("First they..., then they...")
- User type descriptions ("The admin would...")
- Flow confirmations ("So the journey is: [steps]?")
- Trigger descriptions ("When [event] happens...")

**For each journey, extract:**

| Field | Description |
|-------|-------------|
| ID | J-001, J-002, etc. |
| Name | [User Type] - [Goal] |
| Actor/Persona | Who performs this journey |
| Trigger | What initiates the flow |
| Pre-conditions | What must be true before starting |
| Steps | Numbered sequential actions |
| Post-conditions | State after completion |
| Exception Paths | Error handling, alternate flows |
| Data Touched | Entities accessed/modified |
| Related Features | Which features are used |
| Evidence | Verbatim quote |

**Write to:** `$SCOPE_DIR/02_user_journeys.md`

---

### Step 4: PASS 3 - Context & Constraints

**Goal:** Extract project boundaries, success criteria, decisions, unknowns.

Extract:

**Project Identity:**
- Vision statement
- Problem being solved
- Target outcome

**Success Criteria:**
- Metrics and targets
- How success will be measured

**Constraints:**
- Timeline (milestones, deadlines, flexibility)
- Budget (total, breakdown, flexibility)
- Resources (team size, skills, availability)
- Technical (existing systems, required integrations)
- Organizational (policies, stakeholder approval)

**Decisions Made:**
- What was decided
- Rationale
- Who decided

**Unknowns:**
- Questions deferred
- Items needing research
- Stakeholder "I don't know" responses

---

### Step 5: PASS 4 - Implicit Requirements Derivation

**Goal:** Derive non-functional requirements stakeholders expect but didn't explicitly state.

**Apply NFR Checklist to each feature:**

#### Performance
- [ ] Response time targets (page load < 2s, API < 500ms)
- [ ] Concurrent user capacity
- [ ] Throughput (transactions/second)
- [ ] Data volume limits

#### Security
- [ ] Authentication method (OAuth, SAML, MFA)
- [ ] Authorization model (RBAC, ABAC)
- [ ] Data encryption (at rest, in transit)
- [ ] Audit logging requirements
- [ ] Session management

#### Scalability
- [ ] User growth projections (1yr, 3yr)
- [ ] Data growth projections
- [ ] Geographic expansion
- [ ] Horizontal/vertical scaling approach

#### Reliability & Availability
- [ ] Uptime target (99.9% = 8.76 hrs downtime/year)
- [ ] RTO (Recovery Time Objective)
- [ ] RPO (Recovery Point Objective)
- [ ] Backup frequency and retention
- [ ] Failover strategy

#### Usability & Accessibility
- [ ] WCAG compliance level (A, AA, AAA)
- [ ] Mobile responsiveness
- [ ] Browser support
- [ ] Internationalization (languages)

#### Compliance
- [ ] GDPR applicability
- [ ] HIPAA applicability
- [ ] PCI DSS applicability
- [ ] SOC 2 requirements
- [ ] Industry-specific regulations

#### Maintainability
- [ ] Logging standards
- [ ] Monitoring requirements
- [ ] Deployment approach (zero-downtime)
- [ ] Documentation requirements

#### Data Integrity
- [ ] Validation rules
- [ ] Transaction requirements
- [ ] Conflict resolution
- [ ] Data quality metrics

**Write to:** `$SCOPE_DIR/03_nfr_requirements.md`

---

### Step 6: PASS 5 - Technical Architecture Mapping

**Goal:** Map features to technical components, stack recommendations, integrations.

**Technology Stack Recommendations:**

Based on features, constraints, and domain, recommend:

| Layer | Technology | Rationale | Alternatives |
|-------|------------|-----------|--------------|
| Frontend | [Tech] | [Why] | [Options] |
| Backend | [Tech] | [Why] | [Options] |
| Database | [Tech] | [Why] | [Options] |
| API | [Protocol] | [Why] | [Options] |
| Infrastructure | [Platform] | [Why] | [Options] |

**Note:** Default stack per CLAUDE.md is Angular, GraphQL, Python, PostgreSQL unless conversation specifies otherwise.

**Integration Requirements:**

For each external system mentioned:
- System name
- Direction (Inbound/Outbound/Bidirectional)
- Protocol (REST, GraphQL, SOAP, File)
- Data exchanged
- Authentication method
- Error handling approach

**Feature-to-Component Mapping:**

For each feature:
- Required components
- API endpoints
- Database entities
- Infrastructure needs
- Technical dependencies

**Architecture Decision Records (ADRs):**

For significant decisions:
```markdown
### ADR-001: [Decision Title]
**Status:** Proposed
**Context:** [What prompted this decision]
**Decision:** [What was decided]
**Consequences:** [Trade-offs]
```

**Write to:** `$SCOPE_DIR/04_technical_architecture.md`

---

### Step 7: PASS 6 - Risk Assessment

**Goal:** Identify and assess project and product risks.

**Risk Categories:**

| Category | Examples |
|----------|----------|
| Technical | Integration complexity, performance targets, new technology |
| Business | Scope creep, stakeholder availability, budget overrun |
| Integration | Third-party API changes, data quality, availability |
| Resource | Team capacity, skill gaps, key person dependency |
| Timeline | Dependencies, approvals, external factors |

**For each risk:**

| Field | Description |
|-------|-------------|
| ID | R-001, R-002, etc. |
| Risk | What could go wrong |
| Category | Technical / Business / Integration / Resource / Timeline |
| Likelihood | High / Medium / Low |
| Impact | High / Medium / Low |
| Score | Likelihood × Impact |
| Triggers | What would cause this |
| Early Warning Signs | How to detect early |
| Mitigation | Actions to reduce likelihood |
| Contingency | Plan if risk materializes |
| Owner | Who is responsible |

**Write to:** `$SCOPE_DIR/05_risk_assessment.md`

---

### Step 8: PASS 7 - Gap Analysis

**Goal:** Identify missing information, contradictions, and clarification needs.

**Gap Types:**

| Type | Description |
|------|-------------|
| Missing Information | Requirement mentioned but incompletely specified |
| Contradiction | Requirements that conflict |
| Ambiguity | Could be interpreted multiple ways |
| Edge Case | Exception scenario not addressed |
| Assumption | Implicit assumption needing validation |

**For each gap:**

| Field | Description |
|-------|-------------|
| ID | GAP-001, GAP-002, etc. |
| Gap | What's missing or unclear |
| Affected | Features/journeys impacted |
| Severity | Critical / High / Medium / Low |
| Impact | What cannot proceed without this |
| Clarification Question | Specific question to ask |
| Suggested Default | Reasonable assumption if stakeholder unavailable |

**Prioritize gaps:**
- **Critical:** Blocks development
- **High:** Should resolve before development
- **Medium:** Can address during development
- **Low:** Nice to clarify

**Write to:** `$SCOPE_DIR/06_gap_analysis.md`

---

### Step 9: PASS 8 - Synthesis

**Goal:** Compile all passes into unified scope document.

**Write `00_scope_document.md` with this structure:**

```markdown
# Scope Document: {Project Name}

**Version:** 1.0
**Created:** {datetime}
**Source:** .claude/interrogations/{session-name}/conversation.md
**Status:** Draft - Pending Review

---

## 1. Executive Overview

### 1.1 Project Vision
{Vision statement from conversation}

### 1.2 Business Problem
{Problem being solved and impact of not solving}

### 1.3 Success Criteria
| Criterion | Metric | Target |
|-----------|--------|--------|

### 1.4 Scope Boundaries
**In Scope:**
**Out of Scope:**
**Deferred:**

---

## 2. Stakeholder Context

### 2.1 User Types/Personas
{From conversation}

### 2.2 Key Concerns
{What stakeholders emphasized}

---

## 3. Functional Requirements

### 3.1 Feature Catalog

| ID | Feature | Priority | Complexity |
|----|---------|----------|------------|

{Summary table linking to 01_features.md}

### 3.2 User Journeys

| ID | User Type | Goal | Steps |
|----|-----------|------|-------|

{Summary table linking to 02_user_journeys.md}

---

## 4. Non-Functional Requirements

### 4.1 Performance
### 4.2 Security
### 4.3 Scalability
### 4.4 Reliability
### 4.5 Compliance

{Summarized from 03_nfr_requirements.md}

---

## 5. Technical Architecture

### 5.1 Technology Stack
### 5.2 Integration Requirements
### 5.3 Key Architecture Decisions

{Summarized from 04_technical_architecture.md}

---

## 6. Project Constraints

### 6.1 Timeline
### 6.2 Budget
### 6.3 Resources
### 6.4 Technical Constraints

---

## 7. Risk Assessment

| ID | Risk | Severity | Mitigation |
|----|------|----------|------------|

{Summary from 05_risk_assessment.md}

---

## 8. Unknowns and Decisions

### 8.1 Open Questions
| Question | Impact | Priority |
|----------|--------|----------|

### 8.2 Decisions Made
| Decision | Rationale | Source |
|----------|-----------|--------|

### 8.3 Assumptions
| Assumption | Risk if Wrong |
|------------|---------------|

{From 06_gap_analysis.md}

---

## 9. Traceability

### Feature-Journey Matrix
| Feature | J-001 | J-002 | J-003 |
|---------|-------|-------|-------|

### Requirements Source Attribution
| Requirement | Conversation Reference |
|-------------|------------------------|

---

## 10. Next Steps

1. **Review this document** with stakeholders
2. **Resolve critical gaps** (see 06_gap_analysis.md)
3. **Research unknowns** using `/pm:scope-research`
4. **Build application** using Loki Mode:
   ```bash
   ./interrogate.sh --build {session-name}
   # Or directly:
   ./build-from-scope.sh {session-name}
   ```

---

## Appendix

### A. Glossary
### B. Conversation Summary
### C. Sign-off

| Stakeholder | Role | Date | Signature |
|-------------|------|------|-----------|
```

---

### Step 10: Present Summary

After generating all files, show:

```
✅ Scope document generated: {session-name}

Summary: {1-sentence project description}

Extraction Results:
- Features: {count}
- User Journeys: {count}
- NFRs Derived: {count}
- Integrations: {count}
- Risks Identified: {count}
- Gaps/Questions: {count} ({critical} critical)

Output Directory: .claude/scopes/{session-name}/

Files Created:
- 00_scope_document.md (comprehensive scope)
- 01_features.md
- 02_user_journeys.md
- 03_nfr_requirements.md
- 04_technical_architecture.md
- 05_risk_assessment.md
- 06_gap_analysis.md

Next Steps:
1. Review 00_scope_document.md with stakeholders
2. Address critical gaps: /pm:scope-research {session-name} "{question}"
3. Build application: ./interrogate.sh --build {session-name}
```

---

## Important Rules

1. **Multi-pass extraction** - Don't try to extract everything at once
2. **Quote verbatim** - Use exact quotes as evidence/source attribution
3. **Derive implicit requirements** - Apply NFR checklist systematically
4. **Flag uncertainty** - Mark confidence levels and gaps clearly
5. **Don't fabricate** - Only extract what's supported by conversation
6. **Maintain traceability** - Every requirement traces to conversation
7. **Technical defaults** - Use Angular/GraphQL/Python/PostgreSQL unless specified
8. **Actionable gaps** - Each gap has a clarification question
9. **Risk mitigations** - Every risk has a mitigation strategy

---

## Quality Checklist

Before finalizing, verify:

- [ ] All features have acceptance criteria
- [ ] All journeys have complete step sequences
- [ ] Security requirements addressed for sensitive features
- [ ] Performance targets defined
- [ ] All integrations identified
- [ ] Critical gaps have clarification questions
- [ ] High-severity risks have mitigations
- [ ] Traceability maintained throughout

---

## Sources

This extraction methodology is based on:
- IEEE 29148:2018 (Requirements Engineering)
- PMBOK Project Scope Management
- SAFe/Agile requirements hierarchy
- FURPS+ non-functional requirements model
- Industry best practices for AI-assisted requirements extraction
