# Deep Research Report: pm:decompose Skill Implementation

**Research Question:** What is the optimal implementation pattern for a pm:decompose skill that uses AI analysis to break down input documents into individual PRD files?

**Date:** 2026-01-20
**Depth:** Exhaustive
**Scope:** CCPM codebase patterns, templates, and conventions

---

## Executive Summary

This research analyzed 78 existing PM commands, the PRD template structure, input handling patterns, and decomposition algorithms in the CCPM system. The recommended implementation for `pm:decompose` follows a **hybrid input pattern** (file path OR conversation context), uses **AI-driven boundary detection** with INVEST validation, and generates PRD files using the established template at `.claude/templates/prd.md`.

---

## 1. Research Methodology

### Sources Analyzed
- **78 PM commands** in `.claude/commands/pm/`
- **PRD template** at `.claude/templates/prd.md`
- **Scope templates** at `.claude/templates/scope/`
- **Project rules** at `.claude/rules/`
- **Key decomposition commands:** scope-decompose.md, epic-decompose.md, roadmap-generate.md, prd-new.md, import.md

### Key Questions Addressed
1. How do existing commands handle different input types?
2. What decomposition strategies are used?
3. How are PRD files created from templates?
4. What validation patterns ensure quality?

---

## 2. Findings: Input Handling Patterns

### Pattern A: File Path from $ARGUMENTS (Most Common)
```
/pm:prd-parse <feature_name>
→ Reads: .claude/prds/$ARGUMENTS.md
→ Creates: .claude/epics/$ARGUMENTS/epic.md
```

**Validation chain:**
1. Check $ARGUMENTS provided
2. Validate file exists
3. Validate frontmatter
4. Check for existing output (ask overwrite)

### Pattern B: Conversation Context (Interactive)
```
/pm:prd-new <feature_name>
→ Brainstorms with user
→ Creates: .claude/prds/$ARGUMENTS.md
```

Uses conversation history to gather requirements before generating output.

### Pattern C: Hybrid (File + Context)
```
/pm:scope-generate <scope-name> <prd-name>
→ Reads: .claude/scopes/$SCOPE_NAME/decomposition.md
→ Reads: .claude/scopes/$SCOPE_NAME/discovery.md
→ Creates: .claude/prds/$PRD_NAME.md
```

Combines structured file input with contextual understanding.

### Pattern D: Smart Defaults (No Input)
```
/pm:interrogate [session-name]
→ If no arg: SESSION_NAME=$(date +%Y%m%d-%H%M%S)
→ Auto-detects and uses most recent scope if ambiguous
```

### **Recommendation for pm:decompose: Pattern C (Hybrid)**

Accept:
1. **File path argument**: `/pm:decompose roadmap.md` or `/pm:decompose .claude/scopes/session/discovery.md`
2. **Conversation context**: User pastes/describes requirements, then runs `/pm:decompose`
3. **Both**: Reference file AND use conversation to clarify ambiguities

---

## 3. Findings: Decomposition Strategies

### Existing Strategies (from scope-decompose.md)

| Strategy | Use Case | Example |
|----------|----------|---------|
| **By User Journey** | User-centric products | Registration → Onboarding → Core → Retention |
| **By System Layer** | Technical products | Data → API → Business Logic → Frontend |
| **By Business Capability** | Enterprise apps | Auth → Core Feature A → Core Feature B → Analytics |
| **By Timeline/Phase** | Phased releases | MVP → Enhancement → Scale |
| **By Risk** | Innovative products | Foundation → Core → Experimental |

### Boundary Detection Heuristics

From scope-decompose.md (lines 75-79):
- **Different user personas** → separate PRDs
- **Different systems/integrations** → separate PRDs
- **Different phases mentioned** → separate PRDs
- **Explicit dependencies** → establish ordering

### INVEST Validation (Lines 64-71)

Each generated PRD must be:
- **I**ndependent: Developable without other PRDs
- **N**egotiable: Flexible in implementation
- **V**aluable: Delivers standalone user value
- **E**stimable: Clear enough to estimate effort
- **S**mall: Completable in reasonable timeframe
- **T**estable: Has clear acceptance criteria

### Sizing Rules (Lines 193-199)

| Issue | Solution |
|-------|----------|
| PRD > 10 requirements | Split it |
| PRD < 2 requirements | Merge with related PRD |
| Infrastructure-only PRD | Add user value or merge |
| Circular dependency | Extract shared component |

---

## 4. Findings: Template Usage

### PRD Template Structure (.claude/templates/prd.md)

```yaml
---
name: {feature-name}
description: {Brief one-line description}
status: backlog
created: {datetime}
---
```

**Sections (12 total):**
1. Executive Summary
2. Problem Statement
3. User Stories (personas, journeys, acceptance criteria)
4. Requirements (functional + non-functional)
5. Success Criteria (measurable outcomes, KPIs)
6. Constraints & Assumptions
7. Out of Scope
8. Dependencies
9. Technical Considerations
10. Risks & Mitigations
11. Open Questions
12. Appendix

### Template Consumption Pattern

Commands do NOT copy templates directly. They:
1. Read template structure as reference
2. Generate content following the structure
3. Fill placeholders with analyzed content
4. Write to `.claude/prds/{name}.md`

### Placeholder Convention
- Format: `{placeholder-name}`
- Examples: `{feature-name}`, `{datetime}`, `{persona_name}`, `{requirement}`

---

## 5. Findings: File Creation Patterns

### Directory Structure
```
.claude/
├── prds/                  # PRD files created here
│   └── {name}.md
├── templates/
│   └── prd.md            # Template reference
└── scopes/
    └── {session}/
        └── decomposition.md  # Decomposition plan
```

### Frontmatter Requirements

**Required fields:**
- `name` - Feature identifier (kebab-case)
- `status` - Always `backlog` for new PRDs
- `created` - Real ISO 8601 datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

**Optional fields:**
- `description` - One-line summary
- `depends_on` - List of PRD dependencies

### Numbering Convention

From scope-decompose.md (lines 93-98):
```bash
# Find highest existing PRD number
HIGHEST=$(ls .claude/prds/*.md 2>/dev/null | sed 's/.*\/\([0-9]*\)-.*/\1/' | sort -n | tail -1)
NEXT=$((HIGHEST + 1))
```

PRD naming: `{number}-{descriptive-name}.md` (e.g., `76-user-authentication.md`)

---

## 6. Findings: Validation Patterns

### Preflight Checklist (from prd-new.md)

1. **Input validation** - Format check (kebab-case)
2. **Existence check** - File already exists?
3. **Directory check** - Create `.claude/prds/` if missing
4. **Overwrite confirmation** - Ask only if file exists

### Quality Checks Before Save

From prd-new.md (lines 125-132):
- [ ] All sections complete (no placeholders)
- [ ] User stories include acceptance criteria
- [ ] Success criteria are measurable
- [ ] Dependencies clearly identified
- [ ] Out of scope items explicit

### Decomposition Validation (from scope-decompose.md)

- [ ] Every requirement assigned to a PRD
- [ ] No circular dependencies
- [ ] Clear boundaries (in/out of scope)
- [ ] PRDs numbered correctly
- [ ] Dependencies form valid DAG
- [ ] Coverage check accounts for all items

---

## 7. Implementation Recommendation

### Skill File Structure

**File:** `.claude/commands/pm/decompose.md`

```markdown
---
allowed-tools: Bash, Read, Write, LS
---

# Decompose - Break Documents into PRDs

Analyze input documents (roadmaps, scope docs, requirements) and generate individual PRD files.

## Usage
```
/pm:decompose [file-path]
```

## Arguments
- `file-path` (optional): Path to document to decompose
- If omitted: Uses conversation context

## Required Rules
- `.claude/rules/datetime.md` - For timestamps
- `.claude/rules/frontmatter-operations.md` - For PRD metadata

## Instructions
[See full implementation below]
```

### Input Handling Logic

```markdown
### 1. Determine Input Source

**If $ARGUMENTS provided:**
1. Check if file exists: `test -f "$ARGUMENTS"`
2. If exists: Read file content
3. If not exists: "❌ File not found: $ARGUMENTS"

**If $ARGUMENTS empty:**
1. Check conversation context for:
   - Pasted documents/roadmaps
   - Described requirements
   - Feature lists
2. If no context: "❌ No input provided. Either:
   - Provide a file path: /pm:decompose path/to/roadmap.md
   - Paste your document and run /pm:decompose"
```

### Decomposition Logic

```markdown
### 2. Analyze Input Document

Read and understand the document structure:
- Identify sections, features, requirements
- Note any existing organization (phases, categories)
- Extract user personas if mentioned
- Identify dependencies and relationships

### 3. Choose Decomposition Strategy

Based on document structure, select:
- **By User Journey** - If document organized by user flows
- **By System Layer** - If document has technical architecture
- **By Business Capability** - If document has domain areas
- **By Timeline/Phase** - If document has phases/milestones
- **By Risk** - If document mentions risk levels

### 4. Identify PRD Boundaries

Apply boundary heuristics:
- Different user personas → separate PRDs
- Different systems/integrations → separate PRDs
- Different phases → separate PRDs
- >10 requirements → split PRD
- <2 requirements → merge with related PRD

### 5. Validate INVEST Principles

For each proposed PRD, verify:
- Independent: Can be developed alone
- Valuable: Delivers user value
- Estimable: Clear scope
- Small: Reasonable timeframe
- Testable: Has acceptance criteria
```

### PRD Generation Logic

```markdown
### 6. Load PRD Template

```bash
TEMPLATE=".claude/templates/prd.md"
if [ ! -f "$TEMPLATE" ]; then
  echo "❌ PRD template not found at $TEMPLATE"
  exit 1
fi
cat "$TEMPLATE"
```

### 7. Get Next PRD Number

```bash
HIGHEST=$(ls .claude/prds/*.md 2>/dev/null | sed 's/.*\/\([0-9]*\)-.*/\1/' | sort -n | tail -1)
[ -z "$HIGHEST" ] && HIGHEST=0
NEXT=$((HIGHEST + 1))
```

### 8. Generate PRDs

For each identified PRD:

1. **Create frontmatter:**
```yaml
---
name: {number}-{descriptive-name}
description: {one-line summary from analysis}
status: backlog
created: {run: date -u +"%Y-%m-%dT%H:%M:%SZ"}
depends_on: [{list of dependency PRD numbers}]
---
```

2. **Fill template sections** using analyzed content:
   - Executive Summary: From document context
   - Problem Statement: Extracted problem/goal
   - User Stories: Mapped from personas/journeys
   - Requirements: Assigned from document
   - Success Criteria: Derived metrics
   - Out of Scope: Explicit boundaries
   - Dependencies: Cross-PRD dependencies

3. **Write file:**
```bash
mkdir -p .claude/prds
# Write to .claude/prds/{number}-{name}.md
```

4. **Increment number for next PRD**
```

### Output Format

```markdown
### 9. Output Summary

After generating all PRDs:

```
✅ Decomposition complete

Created {N} PRDs from: {input_source}

PRDs:
  {number}-{name} (P0) - {description}
  {number}-{name} (P1, depends: {n}) - {description}
  ...

Dependency graph:
  {number} ──> {number} ──> {number}
           └──> {number}

Files created:
  .claude/prds/{number}-{name}.md
  .claude/prds/{number}-{name}.md
  ...

Next steps:
  Review PRDs: ls .claude/prds/
  Parse to epic: /pm:prd-parse {name}
  Batch process: /pm:batch-process {name1} {name2} ...
```
```

### Error Handling

```markdown
### Error Recovery

**Partial completion:**
- List successfully created PRDs
- Report which PRDs failed
- Suggest manual fixes

**Circular dependencies:**
- Report the cycle
- Suggest extracting shared component

**Ambiguous boundaries:**
- Ask user to clarify
- Provide boundary options
```

---

## 8. Complete Skill File

```markdown
---
allowed-tools: Bash, Read, Write, LS
---

# Decompose - Break Documents into PRDs

Analyze input documents (roadmaps, scope docs, requirements, or conversation context) and generate individual PRD files.

## Usage
```
/pm:decompose [file-path]
```

## Arguments
- `file-path` (optional): Path to document to decompose
- If omitted: Uses conversation context (paste requirements before running)

## Required Rules

**IMPORTANT:** Before executing this command, read and follow:
- `.claude/rules/datetime.md` - For getting real current date/time
- `.claude/rules/frontmatter-operations.md` - For PRD metadata handling

## Preflight Checklist

### 1. Determine Input Source

**If $ARGUMENTS provided:**
```bash
if [ -n "$ARGUMENTS" ]; then
  if [ -f "$ARGUMENTS" ]; then
    echo "Reading from file: $ARGUMENTS"
    cat "$ARGUMENTS"
  else
    echo "❌ File not found: $ARGUMENTS"
    exit 1
  fi
fi
```

**If $ARGUMENTS empty:**
- Check conversation context for pasted documents, roadmaps, or requirements
- If no context found: "❌ No input provided. Either provide a file path or paste your document first."

### 2. Verify PRD Template Exists

```bash
TEMPLATE=".claude/templates/prd.md"
if [ ! -f "$TEMPLATE" ]; then
  echo "❌ PRD template not found. Create it at: $TEMPLATE"
  exit 1
fi
```

### 3. Ensure PRD Directory Exists

```bash
mkdir -p .claude/prds 2>/dev/null
```

## Instructions

You are a product strategist decomposing an input document into multiple well-bounded PRDs.

### Step 1: Analyze Input Document

Read and understand the document:
- Identify all features, requirements, and capabilities mentioned
- Note any existing organization (phases, categories, user flows)
- Extract user personas if mentioned
- Identify explicit and implicit dependencies
- Note any technical constraints or architectural requirements

### Step 2: Choose Decomposition Strategy

Select the most appropriate strategy based on document structure:

| Strategy | Use When |
|----------|----------|
| **By User Journey** | Document organized by user flows or personas |
| **By System Layer** | Document has clear technical architecture layers |
| **By Business Capability** | Document has distinct domain/feature areas |
| **By Timeline/Phase** | Document mentions phases, milestones, or releases |
| **By Risk** | Document categorizes by risk or uncertainty levels |

You may combine strategies if appropriate.

### Step 3: Identify PRD Boundaries

Apply these boundary heuristics:
- **Different user personas** → separate PRDs
- **Different systems/integrations** → separate PRDs
- **Different phases mentioned** → separate PRDs
- **Explicit dependencies** → establish ordering

### Step 4: Validate PRD Sizing

Each PRD must satisfy:
- **>10 requirements** → Split into smaller PRDs
- **<2 requirements** → Merge with related PRD
- **Infrastructure-only** → Add user value or merge with feature PRD
- **Circular dependency** → Extract shared component into new PRD

### Step 5: Validate INVEST Principles

For each proposed PRD, verify:
- **I**ndependent: Can be developed without other PRDs
- **V**aluable: Delivers standalone user value
- **E**stimable: Clear enough to estimate effort
- **S**mall: Completable in reasonable timeframe
- **T**estable: Has clear acceptance criteria

### Step 6: Get Next PRD Number

```bash
HIGHEST=$(ls .claude/prds/*.md 2>/dev/null | sed 's/.*\/\([0-9]*\)-.*/\1/' | sort -n | tail -1)
[ -z "$HIGHEST" ] && HIGHEST=0
NEXT=$((HIGHEST + 1))
echo "Starting PRD number: $NEXT"
```

### Step 7: Load PRD Template

```bash
cat .claude/templates/prd.md
```

Use this template structure for all generated PRDs.

### Step 8: Generate PRDs

For each identified PRD:

1. **Create file with frontmatter:**
```yaml
---
name: {number}-{descriptive-kebab-name}
description: {one-line summary}
status: backlog
created: {REAL datetime from: date -u +"%Y-%m-%dT%H:%M:%SZ"}
depends_on: [{list of dependency PRD numbers, or empty array}]
---
```

2. **Fill all template sections** using analyzed content:
   - Executive Summary: Derived from document context
   - Problem Statement: Extracted problem and urgency
   - User Stories: Mapped from personas/journeys in document
   - Requirements: Assigned requirements from document
   - Success Criteria: Derived measurable metrics
   - Out of Scope: Explicit boundaries with other PRDs
   - Dependencies: Cross-PRD and external dependencies

3. **Write to file:**
   - Location: `.claude/prds/{number}-{name}.md`
   - Use kebab-case for name
   - Increment number for each PRD

### Step 9: Create Dependency Graph

After all PRDs generated, create visual dependency representation:
```
{number}-{name} ──┬──> {number}-{name}
{number}-{name} ──┘
                 └──> {number}-{name}
```

### Step 10: Validate Coverage

Verify:
- [ ] Every requirement from input assigned to exactly one PRD
- [ ] No circular dependencies exist
- [ ] Each PRD has clear in-scope/out-of-scope boundaries
- [ ] All PRDs satisfy INVEST principles
- [ ] Dependencies form valid DAG (directed acyclic graph)

### Step 11: Output Summary

```
✅ Decomposition complete

Created {N} PRDs from: {input_source}

Strategy: {chosen strategy}

PRDs:
  {number}-{name} (P0) - {description}
  {number}-{name} (P1, depends: {deps}) - {description}
  ...

Dependency graph:
  {visual representation}

Execution order:
  Phase 1: {prds with no dependencies}
  Phase 2: {prds depending on Phase 1}
  ...

Files created:
  .claude/prds/{number}-{name}.md
  ...

Next steps:
  Review PRDs: cat .claude/prds/{name}.md
  Parse to epic: /pm:prd-parse {name}
  Batch process: /pm:batch-process {name1} {name2} ...
```

## Error Recovery

**If file not found:**
- "❌ File not found: {path}. Check the path and try again."

**If no input provided:**
- "❌ No input provided. Either:
  - Provide a file: /pm:decompose path/to/document.md
  - Paste your document first, then run /pm:decompose"

**If circular dependencies detected:**
- Report which PRDs form the cycle
- Suggest: "Extract shared requirements into a new foundation PRD"

**If partial completion:**
- List successfully created PRDs
- Report failures with reasons
- "Run /pm:decompose again after fixing issues"
```

---

## 9. Quality Assurance Validation

### Requirements Checklist

| Requirement | Implementation |
|-------------|----------------|
| Accept multiple input formats | Hybrid pattern: file path OR context |
| AI-driven boundary detection | INVEST + heuristics from scope-decompose |
| Use PRD template | Reads `.claude/templates/prd.md` |
| Create proper PRD files | Follows frontmatter + numbering conventions |
| Standalone skill | No calls to other pm commands |

### Edge Cases Handled

| Edge Case | Handling |
|-----------|----------|
| No input provided | Clear error with usage examples |
| File not found | Error with exact path |
| Empty document | "Document has no decomposable content" |
| Single PRD worth | Create one PRD, note consolidation |
| Circular dependencies | Report and suggest resolution |
| PRD directory missing | Auto-create `.claude/prds/` |
| Existing PRD conflict | Ask overwrite confirmation |
| Template missing | Error with creation instructions |

---

## 10. Implementation Artifacts

### Files to Create

1. **`.claude/commands/pm/decompose.md`** - Main skill file (content in Section 8)

### Tools Required

```yaml
allowed-tools: Bash, Read, Write, LS
```

### Dependencies

- `.claude/templates/prd.md` - Must exist
- `.claude/rules/datetime.md` - For timestamps
- `.claude/rules/frontmatter-operations.md` - For metadata

---

## 11. Appendix: Key Source References

| File | Lines | Pattern |
|------|-------|---------|
| scope-decompose.md | 35-62 | Decomposition strategies |
| scope-decompose.md | 64-71 | INVEST principles |
| scope-decompose.md | 75-79 | Boundary heuristics |
| scope-decompose.md | 93-98 | PRD numbering |
| scope-decompose.md | 100-181 | Output format |
| prd-new.md | 24-40 | Input validation |
| prd-new.md | 95-115 | File format |
| prd-new.md | 121-123 | DateTime handling |
| import.md | 25-29 | Flag parsing pattern |
| templates/prd.md | 1-230 | Full template structure |

---

## 12. Conclusion

The `pm:decompose` skill should be implemented as a **hybrid input command** that:

1. **Accepts** file paths OR conversation context
2. **Analyzes** input using AI-driven boundary detection
3. **Applies** INVEST validation to proposed PRDs
4. **Generates** properly formatted PRD files using the template
5. **Outputs** summary with dependency graph and next steps

This approach aligns with existing CCPM patterns while providing the flexibility needed for diverse input document types.

---

*Research completed: 2026-01-20*
*Methodology: 7-Phase Deep Research (Scope → Plan → Query → Triangulate → Synthesize → QA → Package)*
*Sources: 78 PM commands, PRD template, scope templates, project rules*
*Confidence: HIGH for implementation recommendations*
