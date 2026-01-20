# pm:decompose Skill Definition

## Overview

The `pm:decompose` skill automatically decomposes a roadmap item (epic/initiative) into independent, well-bounded PRDs with validated dependency management.

---

## Command Signature

```
/pm:decompose <roadmap_item_path> [options]
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `roadmap_item_path` | Yes | Path to roadmap item markdown file |

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--max-prds` | 7 | Maximum PRDs to generate |
| `--min-prds` | 3 | Minimum PRDs to generate |
| `--strategy` | auto | Decomposition strategy (auto/vertical/spidr/story-map) |
| `--confidence-threshold` | 0.7 | Minimum confidence for auto-approval |
| `--output-dir` | ./prds | Directory for output PRDs |
| `--review` | false | Force human review regardless of confidence |
| `--dry-run` | false | Show what would be generated without writing |

---

## Input Requirements

### Roadmap Item File Format

```yaml
---
id: EPIC-001
title: User Authentication System
type: epic
status: planning
priority: high
---

# User Authentication System

## Overview
{Description of what this epic/initiative covers}

## Goals
- {Goal 1}
- {Goal 2}

## Constraints
- {Constraint 1}
- {Constraint 2}

## Success Criteria
- {Criterion 1}
- {Criterion 2}
```

---

## Output Structure

```
{output-dir}/
├── decomposition-summary.md     # Overview of decomposition
├── dependency-graph.json        # DAG in JSON format
├── dependency-graph.mermaid     # Visual DAG
├── PRD-{EPIC}-001.md           # First PRD
├── PRD-{EPIC}-002.md           # Second PRD
├── ...
└── validation-report.md         # INVEST scores, anti-patterns
```

---

## Skill Implementation

### File: `.claude/commands/pm/decompose.md`

```markdown
---
name: decompose
description: Decompose roadmap item into independent PRDs
arguments:
  - name: roadmap_item_path
    description: Path to roadmap item file
    required: true
options:
  - name: max-prds
    description: Maximum PRDs to generate
    default: "7"
  - name: min-prds
    description: Minimum PRDs to generate
    default: "3"
  - name: strategy
    description: Decomposition strategy
    default: "auto"
  - name: confidence-threshold
    description: Minimum confidence for auto-approval
    default: "0.7"
  - name: output-dir
    description: Output directory for PRDs
    default: "./prds"
  - name: review
    description: Force human review
    default: "false"
  - name: dry-run
    description: Preview without writing
    default: "false"
---

# pm:decompose

Decompose a roadmap item into independent, well-bounded PRDs.

## Pre-flight Checks

1. Verify roadmap item file exists
2. Parse and validate frontmatter
3. Ensure output directory is writable

## Execution Steps

### Step 1: Load and Parse Input

Read the roadmap item file at `$ARGUMENTS.roadmap_item_path`.
Extract:
- id, title, type from frontmatter
- description, goals, constraints from body

### Step 2: Select Decomposition Strategy

If `$OPTIONS.strategy` is "auto":
- Analyze item characteristics
- Select best strategy (vertical, spidr-paths, spidr-rules, spidr-data, story-map)

Otherwise use specified strategy.

### Step 3: Generate PRD Decomposition

Using the selected strategy:

1. Generate initial PRD decomposition using LLM with the prompt template
2. Validate output format (JSON with prds array)
3. Check for minimum/maximum PRD count

If count outside bounds, regenerate with adjusted parameters.

### Step 4: INVEST Validation

For each generated PRD:
1. Calculate independence score (dependency keyword analysis)
2. Calculate value score (user role, outcome, action verbs)
3. Calculate testability score (acceptance criteria quality)
4. Calculate size score (criteria count, word count)
5. Calculate estimability score (ambiguity detection)
6. Compute composite score with weights

### Step 5: Build Dependency Graph

1. Extract explicit dependencies from PRD definitions
2. Detect implicit dependencies (entity co-references)
3. Construct DAG
4. Run cycle detection (Tarjan's algorithm)
5. If cycles found, attempt resolution or flag

### Step 6: Anti-Pattern Detection

Check for all 10 anti-patterns:
- horizontal_slice
- process_step_split
- happy_path_only
- core_first
- crud_split
- trivial_data_split
- superficial_interface
- bad_conjunction_split
- superficial_role_split
- acceptance_criteria_as_prd

Flag HIGH severity for: horizontal_slice, core_first, happy_path_only
Flag MEDIUM severity for all others

### Step 7: Calculate Confidence

Aggregate confidence from:
- LLM consistency (30%)
- Average INVEST scores (30%)
- DAG validity (20%)
- Anti-pattern penalty (20%)

### Step 8: Output Generation

If `$OPTIONS.dry-run` is true:
- Display summary of what would be generated
- Exit without writing files

Otherwise:
1. Create output directory if needed
2. Write each PRD using template
3. Write dependency graph (JSON + Mermaid)
4. Write validation report
5. Write decomposition summary

### Step 9: Review Decision

If confidence < `$OPTIONS.confidence-threshold` OR `$OPTIONS.review` is true:
- Mark all PRDs as review_required: true
- Output message: "Human review required"
- List top issues requiring attention

Otherwise:
- Mark PRDs as review_required: false
- Output message: "Decomposition complete"

## Output Format

### Success

```
✅ Decomposition complete

Generated {N} PRDs from {epic_id}:
- PRD-{EPIC}-001: {title} (INVEST: {score})
- PRD-{EPIC}-002: {title} (INVEST: {score})
...

Dependency chain depth: {depth}
Parallel groups: {groups}

Files written to: {output_dir}/

{If review required:}
⚠️ Human review required (confidence: {score})
Issues:
- {issue 1}
- {issue 2}
```

### Failure

```
❌ Decomposition failed: {reason}

{If partial results:}
Partial results saved to: {output_dir}/partial/

Suggestions:
- {suggestion 1}
- {suggestion 2}
```

## Examples

### Basic Usage

```bash
/pm:decompose .claude/epics/user-auth.md
```

### With Options

```bash
/pm:decompose .claude/epics/user-auth.md --max-prds 5 --strategy spidr --output-dir ./auth-prds
```

### Dry Run

```bash
/pm:decompose .claude/epics/user-auth.md --dry-run
```

### Force Review

```bash
/pm:decompose .claude/epics/user-auth.md --review
```
```

---

## Integration Points

### Input Sources
- Epic files from `.claude/epics/`
- Initiative files from planning tools
- Manual roadmap markdown files

### Output Consumers
- `pm:issue-create` - Create GitHub issues from PRDs
- `pm:epic-start` - Begin work on decomposed epic
- `pm:sprint-plan` - Include PRDs in sprint planning

### Related Skills
- `pm:prd-validate` - Validate individual PRD quality
- `pm:dag-visualize` - Generate dependency visualization
- `pm:prd-refine` - Improve PRD based on feedback

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| `FILE_NOT_FOUND` | Roadmap item path invalid | Check path exists |
| `INVALID_FORMAT` | Roadmap item missing required fields | Add frontmatter |
| `LLM_FAILURE` | LLM generation failed | Retry or simplify input |
| `CYCLE_DETECTED` | Unresolvable dependency cycle | Manual intervention |
| `TOO_MANY_PRDS` | Decomposition too granular | Increase min-prds |
| `TOO_FEW_PRDS` | Item may be too small | Decrease max-prds or skip decomposition |

---

## Configuration

### Global Settings (`.claude/settings.yaml`)

```yaml
decompose:
  default_strategy: auto
  confidence_threshold: 0.7
  max_prds: 7
  min_prds: 3
  output_dir: ./prds
  invest_weights:
    independent: 0.25
    negotiable: 0.05
    valuable: 0.20
    estimable: 0.15
    small: 0.15
    testable: 0.20
```

---

## Monitoring and Metrics

Track for continuous improvement:
- Decomposition success rate
- Average confidence scores
- Anti-pattern frequency by type
- Human review override rate
- PRD refinement frequency post-generation
