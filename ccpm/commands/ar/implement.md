# /ar:implement - Autonomous Recursive Implementation

<command-name>ar:implement</command-name>

## Description

Autonomously decompose a feature request into atomic, implementable units with **context preservation** across agent invocations.

This skill:
1. Collects user input on the feature to implement
2. Initializes session context files for state persistence
3. Uses `/dr` (deep research) to analyze requirements
4. Performs **multi-signal gap analysis** (linguistic, slot-filling, codebase, confidence)
5. Recursively decomposes gaps until each is atomic (1-3 files)
6. Persists tree structure + audit trail to PostgreSQL
7. Generates PRDs compatible with `/pm:decompose` → `/pm:batch-process`

## Arguments

```
/ar:implement [feature-description]
/ar:implement --resume <session-name>
```

- `feature-description`: Optional. The feature to implement. If not provided, will prompt interactively.
- `--resume`: Resume an interrupted session from its saved context.

## Context Preservation

### Why Context Preservation Matters

Research shows long prompts degrade LLM performance by 13-85% even when models can retrieve all relevant information. This skill uses **external context storage** rather than keeping full history in conversation.

### Context Files

Located in `.claude/ar/{session}/`:

| File | Purpose | Updated |
|------|---------|---------|
| `context.md` | Accumulated knowledge and research | After research, gaps |
| `progress.md` | Current phase and completed nodes | After each node |
| `tree.md` | Human-readable decomposition tree | After structure changes |

### Database Tables

| Table | Purpose |
|-------|---------|
| `decomposition_sessions` | Session tracking with stats |
| `decomposition_nodes` | Tree with context columns |
| `decomposition_audit_log` | Full audit trail |

### Agent Context Pattern

Agents receive **focused prompts** via XML tags, not full context:

```xml
<decomposition_context>
  <session>{session_name}</session>
  <current_node>...</current_node>
  <scope>
    <context_file>.claude/ar/{session}/context.md</context_file>
  </scope>
</decomposition_context>
```

Agents return **concise summaries** (3-5 bullets), never full details.

---

## Workflow

```
Phase 0: Initialize Session
├── Create .claude/ar/{session}/ directory
├── Initialize context.md, progress.md, tree.md
├── Create DB session record
└── Get original request from user

Phase 0.5: Interrogation (REQUIRED)
├── Check if detailed requirements provided (skip if >200 words + clear specs)
├── Use 4-phase question hierarchy:
│   ├── Context: Goal and scope questions
│   ├── Behavior: Input, output, happy path
│   ├── Edge Cases: Error handling, limits
│   └── Verification: Summary confirmation
├── Fill dialogue state slots:
│   ├── goal, scope, input_spec, output_spec
│   └── happy_path, error_handling, constraints
├── Ask ONE question at a time (Golden Prompt pattern)
├── Present verification summary when confidence >60%
├── Write confirmed spec to context.md
└── User must confirm "proceed" to continue

Phase 1: Research & Gap Analysis
├── Invoke /dr for technical requirements (informed by spec)
├── Run multi-signal gap detection:
│   ├── Linguistic analysis (ambiguity markers)
│   ├── Slot-filling (required fields check)
│   ├── Codebase context (pattern matching)
│   └── Confidence scoring (self-consistency)
├── Classify gaps: blocking vs nice-to-know
├── Auto-resolve gaps from codebase patterns
└── Write findings to context.md and DB

Phase 2: Recursive Decomposition
├── For each non-atomic node:
│   ├── Check atomicity (1-3 files, single responsibility)
│   ├── If atomic: mark and continue
│   └── If not: decompose → children (layer++)
├── Termination checks:
│   ├── MAX_DEPTH = 6
│   ├── MAX_ITERATIONS = 50
│   └── TIMEOUT = 30 minutes
├── Update progress.md after each node
└── Update tree.md with structure

Phase 3: PRD Generation
├── Query all atomic nodes
├── Transform to PRD format
├── Write to .claude/prds/{session}-{NNN}.md
└── Update node with prd_path in DB

Phase 4: Integration
├── Mark session complete in DB
├── Output summary with PRD paths
└── Suggest next: /pm:batch-process
```

---

## Execution

<execution>

### Phase 0: Initialize Session

1. **Parse arguments**:
   ```bash
   if [ "$1" = "--resume" ]; then
       SESSION_NAME="$2"
       # Verify session exists
       source .claude/scripts/ar-context.sh
       if ! ar_context_exists "$SESSION_NAME"; then
           echo "❌ Session not found: $SESSION_NAME"
           exit 1
       fi
       # Read progress and continue from last phase
       PHASE=$(ar_read_progress_phase "$SESSION_NAME")
       # Jump to appropriate phase
   else
       FEATURE_DESCRIPTION="$1"
   fi
   ```

2. **Generate session name**:
   ```bash
   SESSION_NAME=$(echo "$FEATURE_DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | head -c 50)
   ```

3. **Initialize context files**:
   ```bash
   source .claude/scripts/ar-context.sh
   source .claude/scripts/ar-implement.sh

   ar_init_context_dir "$SESSION_NAME" "$FEATURE_DESCRIPTION"
   ```

4. **Create database session**:
   ```bash
   ar_check_schema || exit 1
   SESSION_ID=$(ar_create_session "$SESSION_NAME" "$FEATURE_DESCRIPTION")
   ```

5. **Update progress**:
   ```bash
   ar_write_progress "$SESSION_NAME" "in_progress" "interrogation" "" "" "0"
   ```

### Phase 0.5: Interrogation

**Purpose:** Collect implementation-critical information before research/decomposition.

1. **Check if interrogation is needed**:
   ```python
   # Skip interrogation if:
   # - Feature description > 200 words with clear specs
   # - User said "just start" or "use your judgment"
   # - Direct codebase pattern match exists

   word_count = len(FEATURE_DESCRIPTION.split())
   has_clear_specs = contains_specs(FEATURE_DESCRIPTION)  # input/output/happy path

   if word_count > 200 and has_clear_specs:
       skip_interrogation = True
   ```

2. **Spawn interrogator agent** with XML context:
   ```xml
   <interrogation_context>
     <session>{SESSION_NAME}</session>
     <feature>{FEATURE_DESCRIPTION}</feature>
     <user_role>developer</user_role>
     <context_file>.claude/ar/{SESSION_NAME}/context.md</context_file>
   </interrogation_context>

   <task>
   Interrogate the user to fill in the dialogue state slots.
   Use the 4-phase question hierarchy:
   1. Context (goal, scope)
   2. Behavior (input, output, happy path)
   3. Edge Cases (error handling, limits)
   4. Verification (summary confirmation)

   Ask ONE question at a time. Wait for answer before continuing.
   Present options in labeled tables (A, B, C) when applicable.
   When confidence >60%, present verification summary.
   User must reply "proceed" to continue.
   </task>
   ```

3. **4-Phase Question Hierarchy:**

   | Phase | Focus | Example Questions |
   |-------|-------|-------------------|
   | 1. Context | Goal & Scope | "What's the primary goal?", "What's in/out of scope?" |
   | 2. Behavior | Input/Output/Happy Path | "What inputs?", "What outputs?", "Walk through success case" |
   | 3. Edge Cases | Errors & Limits | "What if input invalid?", "Rate limits?", "Failure modes?" |
   | 4. Verification | Summary | "Does this capture your needs? Reply 'proceed' to continue" |

4. **Dialogue State Slots:**
   ```yaml
   slots:
     goal: null        # Primary objective
     scope: null       # In/out boundaries
     input_spec: null  # Data inputs
     output_spec: null # Expected outputs
     happy_path: null  # Success scenario
     error_handling: null  # Failure handling
     constraints: null # Performance/security requirements
   ```

5. **Golden Prompt Pattern:**
   - Ask ONE question at a time
   - Wait for answer before asking next
   - Present multiple options in labeled table:
     ```
     | Option | Description |
     |--------|-------------|
     | A | Option A description |
     | B | Option B description |
     | C | Option C description |
     ```

6. **Confidence Thresholds:**
   | Slots Filled | Confidence | Action |
   |--------------|------------|--------|
   | 7/7 | >80% | Proceed to research |
   | 5-6 | 60-80% | Proceed with assumptions |
   | 3-4 | 40-60% | Ask blocking questions |
   | <3 | <40% | Continue interrogation |

7. **Write specification to context.md:**
   ```bash
   ar_write_context "$SESSION_NAME" "specification" "$SPEC_SUMMARY"
   ar_write_progress "$SESSION_NAME" "in_progress" "research" "" "" "0"
   ```

8. **Verification summary format:**
   ```markdown
   ## Feature Specification

   **Goal:** {goal}
   **Scope:** {scope}

   **Inputs:** {input_spec}
   **Outputs:** {output_spec}
   **Happy Path:** {happy_path}
   **Error Handling:** {error_handling}
   **Constraints:** {constraints}

   **Confidence:** {confidence}%

   Reply "proceed" to start decomposition.
   ```

### Phase 1: Research & Gap Analysis

1. **Invoke deep research**:
   ```
   /dr "Analyze requirements for implementing: $FEATURE_DESCRIPTION

   Focus on:
   1. What database changes are needed?
   2. What API endpoints are required?
   3. What frontend components are needed?
   4. What integrations are involved?
   5. What are the dependencies?

   Context: cattle-erp system (FastAPI backend, React frontend, PostgreSQL).
   Check: backend/app/api/v1/, backend/app/models/, frontend/src/pages/"
   ```

2. **Spawn gap-analyzer agent** with XML context:
   ```xml
   <decomposition_context>
     <session>{SESSION_NAME}</session>
     <feature>{FEATURE_DESCRIPTION}</feature>
     <context_file>.claude/ar/{SESSION_NAME}/context.md</context_file>
     <user_role>developer</user_role>
   </decomposition_context>

   <task>
   Analyze codebase to identify gaps between current state and desired feature.
   Use multi-signal detection: linguistic, slot-filling, codebase patterns, confidence.
   Classify gaps as blocking vs nice-to-know.
   Write findings to database and context.md.
   </task>
   ```

3. **Create root node** from feature request:
   ```bash
   ROOT_NODE=$(ar_add_node "$SESSION_NAME" "" "$FEATURE_NAME" "$FEATURE_DESCRIPTION" "other" "$RESEARCH_QUERY")
   ```

4. **Create initial gap nodes** (layer 1):
   ```bash
   for gap in $GAPS; do
       ar_add_node "$SESSION_NAME" "$ROOT_NODE" "$GAP_NAME" "$GAP_DESCRIPTION" "$GAP_TYPE" "" "$PARENT_CONTEXT"
   done
   ```

5. **Update context files**:
   ```bash
   ar_write_context "$SESSION_NAME" "research" "$RESEARCH_SUMMARY"
   ar_write_context "$SESSION_NAME" "gaps" "$GAP_TABLE"
   ar_write_progress "$SESSION_NAME" "in_progress" "decomposition" "$ROOT_NODE" "$FEATURE_NAME" "0"
   ```

### Phase 2: Recursive Decomposition

1. **Initialize loop**:
   ```bash
   START_TIME=$(date +%s)
   ```

2. **Decomposition loop** (via decomposition-coordinator agent):
   ```
   WHILE pending nodes exist AND not terminated:
       │
       ├─► Read progress.md for current state
       │
       ├─► Query pending nodes from DB
       │
       ├─► FOR each pending node:
       │     │
       │     ├─► Spawn atomicity-checker with focused XML prompt
       │     │   Returns: "Atomic: 2 files" or "Split: 3 ways"
       │     │
       │     └─► IF not atomic:
       │           Create children in DB with parent_context
       │
       ├─► Update progress.md
       │
       ├─► Generate tree.md from DB
       │
       └─► Check termination:
             REASON=$(ar_should_terminate "$SESSION_NAME" "$START_TIME")
             IF [ -n "$REASON" ]: break
   ```

3. **Termination conditions**:
   | Condition | Value | Action |
   |-----------|-------|--------|
   | MAX_DEPTH | 6 | Mark remaining as atomic |
   | MAX_ITERATIONS | 50 | Complete session |
   | TIMEOUT | 30 min | Complete with timeout |
   | all_atomic | - | Natural completion |

### Phase 3: PRD Generation

1. **Get all atomic nodes**:
   ```bash
   ATOMIC_NODES=$(ar_get_atomic_nodes "$SESSION_NAME")
   ```

2. **Generate PRD for each** (can parallelize):
   ```bash
   PRD_NUM=1
   for node in $ATOMIC_NODES; do
       PRD_PATH=".claude/prds/${SESSION_NAME}-$(printf '%03d' $PRD_NUM).md"
       ar_generate_prd_content "$SESSION_NAME" "$NODE_ID" "$PRD_NUM" > "$PRD_PATH"
       ar_record_prd "$NODE_ID" "$PRD_PATH" "${SESSION_NAME}-$(printf '%03d' $PRD_NUM)"
       PRD_NUM=$((PRD_NUM + 1))
   done
   ```

### Phase 4: Complete and Report

1. **Complete session**:
   ```bash
   ar_complete_session "$SESSION_NAME" "$TERMINATION_REASON"
   ```

2. **Generate final tree**:
   ```bash
   ar_generate_tree_from_db "$SESSION_NAME"
   ```

3. **Output summary**:
   ```
   ## Decomposition Complete

   Session: {session_name}
   Total Nodes: {total}
   Atomic (PRDs): {leaf_count}
   Max Depth: {depth}
   Duration: {minutes}m
   Termination: {reason}
   Confidence: {avg_confidence}%

   ## Gap Analysis Summary
   - Blocking gaps resolved: {N}
   - Auto-resolved from codebase: {M}
   - Nice-to-know deferred: {K}

   ## Generated PRDs

   1. {prd_path} - {name}
   2. {prd_path} - {name}
   ...

   ## Context Preserved

   Session context: .claude/ar/{session_name}/
   - context.md: Accumulated research and decisions
   - progress.md: Final status
   - tree.md: Decomposition visualization

   ## Next Steps

   Run `/pm:batch-process` to process all PRDs:

   /pm:batch-process .claude/prds/{session_name}-*.md

   Or process individually with `/pm:decompose`.
   ```

</execution>

---

## Subagents

This skill uses specialized agents with **context firewall** pattern:

### Interrogator Agent
- **Location**: `.claude/agents/ar/interrogator.md`
- **Input**: XML context with session, feature, user_role
- **Process**: 4-phase question hierarchy to fill dialogue state slots
- **Output**: Asks ONE question at a time, presents options in tables
- **Returns**: Specification summary with confidence score
- **Slots**: goal, scope, input_spec, output_spec, happy_path, error_handling, constraints

### Gap Analyzer Agent
- **Location**: `.claude/agents/ar/gap-analyzer.md`
- **Input**: XML context with session, feature, context_file path
- **Process**: Multi-signal gap detection (linguistic, slot-filling, codebase, confidence)
- **Output**: Concise summary; writes full analysis to DB
- **Returns**: `gap_count: N, blocking_count: M, confidence: 0.XX`

### Atomicity Checker Agent
- **Location**: `.claude/agents/ar/atomicity-checker.md`
- **Input**: XML context with node data and scope
- **Process**: Evaluates 1-3 files, single responsibility, <8 hours
- **Output**: `is_atomic: true/false` with estimates or children
- **Returns**: Concise YAML

### Decomposition Coordinator Agent
- **Location**: `.claude/agents/ar/decomposition-coordinator.md`
- **Input**: Session context
- **Process**: Manages recursive loop, spawns sub-agents
- **Output**: Coordinates context handoffs
- **Returns**: Completion summary

---

## Gap Analysis (Research-Based)

### Multi-Signal Detection

```
Gap Score = 0.25*Linguistic + 0.30*SlotState + 0.20*Codebase + 0.25*Confidence
```

### Five-Category Taxonomy

| Category | Examples |
|----------|----------|
| **Requirements** | Input format, output structure, success criteria |
| **Constraint** | Performance, size, rate limits, permissions |
| **Edge Case** | Failure scenarios, empty states, concurrent access |
| **Integration** | API contracts, data flow, authentication |
| **Verification** | Acceptance tests, metrics, observability |

### Blocking Classification

- **BLOCKING**: Cannot test, cannot estimate, multiple interpretations, missing integration
- **NICE-TO-KNOW**: Has codebase precedent, has industry default, is optimization

### Confidence Thresholds

| Confidence | Action |
|------------|--------|
| >80% | Ready to implement |
| 60-80% | Proceed with documented assumptions |
| 40-60% | Ask blocking questions only |
| <40% | Comprehensive clarification required |

---

## Database Schema

Connection: CCPM PostgreSQL in `cattle-erp` namespace.

### Key Tables
- `decomposition_sessions` - Session tracking with stats
- `decomposition_nodes` - Tree with `layer`, `parent_context`, `gap_signals`, `slot_analysis`
- `decomposition_audit_log` - Full audit trail

### Key Functions
- `create_decomposition_session(name, request)` → session_id
- `add_decomposition_node(session, parent, name, desc, type, query, context)` → node_id
- `mark_node_atomic(node, files, hours, file_list, complexity)`
- `update_node_gap_analysis(node, signals, slots, auto_resolved, blocking, nice_to_know)`
- `record_prd_generation(node, path, name)`
- `complete_decomposition_session(session, reason, status)`

---

## Resumability

Sessions can be resumed after interruption:

```bash
/ar:implement --resume inventory-sharing
```

The skill will:
1. Read `.claude/ar/{session}/progress.md` for current phase and node
2. Query database for pending nodes
3. Continue from where it left off

---

## PRD Format

Generated PRDs are compatible with `/pm:decompose`:

```yaml
---
name: {session}-{NNN}
description: {node name}
status: backlog
created: {timestamp}
dependencies:
  - {parent PRD if applicable}
---

# PRD: {node name}

## Executive Summary
{description}

## Problem Statement
Gap identified during recursive decomposition.
- Gap Type: {type}
- Layer: {layer}
- Complexity: {complexity}
- Confidence: {confidence}%

## Requirements
### Files Affected
- {file1}
- {file2}

### Gap Analysis
- Blocking gaps resolved: {list}
- Auto-resolved from codebase: {list}

## Success Criteria
- [ ] Implementation complete
- [ ] Tests passing
```

---

## Examples

### Basic Usage
```
/ar:implement "Add inventory sharing between organizations"
```

### With Detailed Context
```
/ar:implement "Implement a multi-tenant inventory sharing system that allows organizations to share specific inventory items with partner organizations, with approval workflows and audit logging"
```

### Resume Interrupted Session
```
/ar:implement --resume inventory-sharing
```

---

## Troubleshooting

### Schema Not Found
```bash
.claude/ccpm/ccpm/scripts/create-decomposition-schema.sh
```

### Session Already Exists
Sessions use unique names. Append timestamp if needed:
```bash
SESSION_NAME="${FEATURE_NAME}-$(date +%Y%m%d%H%M%S)"
```

### Context Files Missing
```bash
source .claude/scripts/ar-context.sh
ar_init_context_dir "$SESSION_NAME" "$FEATURE_DESCRIPTION"
```

### Timeout During Decomposition
Increase timeout:
```bash
AR_TIMEOUT_MINUTES=60 /ar:implement "..."
```

---

## Related Commands

- `/dr` - Deep research (used for gap analysis)
- `/pm:decompose` - Process individual PRDs
- `/pm:batch-process` - Process multiple PRDs
- `/pm:prd-list` - List existing PRDs
- `/pm:gap-analysis` - Standalone gap analysis (planned)
