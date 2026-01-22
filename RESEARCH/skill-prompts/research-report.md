# Best Practices for CCPM Skill/Command Prompts

**Research Report: Writing Effective LLM Agent Skill Definitions**

**Date:** 2026-01-21
**Scope:** Claude Code skill/command prompt structure for CCPM-style markdown commands
**Audience:** Technical - ensuring skill markdown files are actionable by Claude

---

## Executive Summary

This report synthesizes Anthropic's official Claude prompt engineering documentation, Claude Code skill authoring best practices, and analysis of 15+ existing CCPM commands to provide actionable guidance for writing effective skill prompts that spawn sub-tasks and handle interactive inputs reliably.

**Key Findings:**

1. **Claude 4.x models take instructions literally** - explicit is better than implicit
2. **Anti-pattern sections are highly effective** when structured with FORBIDDEN/REQUIRED format
3. **Task tool usage requires explicit prompts** - subagents don't inherit parent context
4. **Numbered steps with verification checks** dramatically improve reliability
5. **"Important Rules" sections work best at the end** of skill definitions

---

## Table of Contents

1. [Skill Structure Template](#1-skill-structure-template)
2. [Instruction Writing Patterns](#2-instruction-writing-patterns)
3. [Task Tool and Subagent Patterns](#3-task-tool-and-subagent-patterns)
4. [Anti-Pattern Prevention Sections](#4-anti-pattern-prevention-sections)
5. [Important Rules Sections](#5-important-rules-sections)
6. [Structured Output Formats](#6-structured-output-formats)
7. [CCPM Skill Validation Checklist](#7-ccpm-skill-validation-checklist)
8. [Specific Fixes for generate-inputs.md](#8-specific-fixes-for-generate-inputsmd)
9. [Specific Fixes for fix-problem.md](#9-specific-fixes-for-fix-problemmd)
10. [Sources](#10-sources)

---

## 1. Skill Structure Template

Based on analysis of successful CCPM commands (`batch-process.md`, `feature.md`, `scope-run.md`, `deploy.md`) and Anthropic's skill authoring best practices:

### Recommended Template

```markdown
---
allowed-tools: Bash, Read, Write, LS, Skill, Task, TodoWrite
description: Short description for skill discovery (max 1024 chars)
arguments:
  - name: arg_name
    description: What this argument does
    required: true
options:
  - name: option-name
    description: What this option controls
    default: "value"
---

# Skill Name - Brief Description

One-line summary of what this skill does.

## Usage
\`\`\`
/pm:skill-name <required-arg> [--option value]
\`\`\`

## CRITICAL: [Core Behavioral Constraint]

**Bold statement of the most important behavioral rule.**

This section appears in successful orchestrator commands (batch-process, feature, scope-run).
Use when the skill must run autonomously or has strict execution requirements.

## Quick Check / Preflight

\`\`\`bash
# Minimal validation - fail fast
test -f "$FILE" || echo "Error message with fix"
\`\`\`

## Instructions

### Step 1: Initialize
[Concrete bash commands or actions]

### Step 2: Core Logic
[Main execution with verification after each sub-step]

### Step 3: Handle Results
[What to do with outputs]

## Output Format

### Success
\`\`\`
Format of successful output
\`\`\`

### Failure
\`\`\`
Format of failure output with clear next steps
\`\`\`

## Anti-Pattern Prevention

**FORBIDDEN:**
- Item with explanation why it's bad

**REQUIRED:**
- Item with explanation why it's needed

## Important Rules

1. **Rule name** - Brief explanation
2. **Rule name** - Brief explanation
...

## Notes

- Additional context that doesn't fit elsewhere
- Integration points with other commands
```

### Critical Structure Elements

| Element | Purpose | When to Include |
|---------|---------|-----------------|
| CRITICAL section | Override default behavior | Orchestrator commands |
| Quick Check | Fail fast on bad inputs | Always |
| Numbered Steps | Guide execution order | Multi-step commands |
| Output Format | Set expectations | Always |
| Anti-Pattern Prevention | Prevent known failure modes | Complex commands |
| Important Rules | Reinforce key behaviors | Always |

---

## 2. Instruction Writing Patterns

### Pattern 1: Explicit Step-by-Step with Verification

**From Anthropic's documentation:** "Claude 4.x takes you literally and does exactly what you ask for, nothing more."

**Effective Pattern (from `prd-complete.md`):**

```markdown
## Phase 1: Parse PRD

**YOUR ACTION:** Call Skill tool with skill=`pm:prd-parse-core` args=`$ARGUMENTS`

**AFTER SKILL RETURNS:** Ignore all output. Run verify, then **IMMEDIATELY call Phase 2 Skill.**

Verify: `test -f .claude/epics/$ARGUMENTS/epic.md && echo "✓"`
```

**Why it works:**
- Explicit action instruction
- Clear verification check
- Explicit next step instruction
- Bold emphasis on critical behavior

### Pattern 2: Conditional Routing with Tables

**Effective Pattern (from `feature.md`):**

```markdown
| Complexity | Criteria | Path |
|------------|----------|------|
| **Simple** | <500 words, single feature | Direct to decompose |
| **Medium** | Multiple features, clear structure | Decompose to PRDs |
| **Complex** | Large scope, vague requirements | Full interrogate path |
```

**Why it works:**
- Visual structure aids comprehension
- Clear decision criteria
- Deterministic routing

### Pattern 3: Pseudocode for Loops

**Effective Pattern (from `scope-run.md`):**

```markdown
\`\`\`
iteration = 0
error_history = {}

while true:
    iteration++

    # Run tests
    result = run(test_cmd)

    # Check result
    if test.json.passed == true:
        log("All tests pass. Done.")
        break

    # Analyze failures
    for each failure:
        if count >= 7:
            log("Stuck. Escalating.")
            exit
\`\`\`
```

**Why it works:**
- Shows state management explicitly
- Clarifies loop termination conditions
- Makes algorithm visible

### Pattern 4: Context + Motivation

**From Anthropic's best practices:** "Providing context or motivation behind your instructions helps Claude 4.x models better understand your goals."

**Effective Pattern:**

```markdown
## CRITICAL: Autonomous Operation

**DO NOT STOP. DO NOT ASK PERMISSION. KEEP LOOPING.**

This command runs autonomously until completion. You must:
- Loop continuously until `test.json.passed = true`
- After creating a PRD, immediately run `/pm:batch-process` on it

**WHY:** Sub-skills don't know they're being orchestrated. Their "Next step"
suggestions are for standalone use, not for orchestrated execution.
```

---

## 3. Task Tool and Subagent Patterns

### When to Use Task Tool

| Scenario | Use Task? | Reason |
|----------|-----------|--------|
| Parallel independent searches | Yes | Context isolation |
| Processing multiple items | Yes | Each item gets fresh context |
| Complex multi-step workflow | Yes (for sub-steps) | Prevents context bloat |
| Simple file operation | No | Overhead not worth it |
| Needs parent context | No | Subagents don't inherit |

### Correct Task Tool Invocation

**From Claude Code documentation:** "Each subagent invocation creates a new instance with fresh context."

**Effective Pattern (from `batch-process.md`):**

```markdown
**Invoke:** Use the Task tool to spawn a sub-agent that runs `/pm:prd-complete {prd-name}`:

\`\`\`yaml
Task tool parameters:
  subagent_type: "general-purpose"
  description: "Process PRD {prd-name}"
  prompt: "Run /pm:prd-complete {prd-name} to completion. Do not stop for confirmation. Execute all phases until the PRD status is complete."
\`\`\`
```

**Key Elements:**
1. `subagent_type` specified explicitly
2. `description` for logging/tracking
3. `prompt` contains complete instructions (subagent has no parent context)
4. Behavioral constraints embedded in prompt

### Alternative Pattern: Explore Agent for Read-Only

**Effective Pattern (from `feature.md`):**

```markdown
\`\`\`yaml
Task:
  subagent_type: "Explore"
  description: "Search codebase for {feature}"
  prompt: |
    Search this codebase to understand:
    1. Similar features already implemented
    2. Existing patterns and architecture used
    3. Relevant utilities, helpers, or base classes

    Return:
    - Relevant files found
    - Patterns to follow
    - Code to reuse or extend
\`\`\`
```

### Subagent Constraints

From Anthropic documentation:
- **Subagents cannot spawn other subagents** - design flat hierarchies
- **Don't include Task in subagent's tools** - prevents recursion
- **Fresh context each invocation** - embed all needed instructions

---

## 4. Anti-Pattern Prevention Sections

### Why They Work

From Anthropic's prompt engineering: "Claude 4.x models pay close attention to details and examples. Ensure your examples align with behaviors you want to encourage and minimize behaviors you want to avoid."

Anti-pattern sections serve as negative examples that steer behavior away from failure modes.

### Effective Structure

**From `batch-process.md`:**

```markdown
## Anti-Pattern Prevention

**FORBIDDEN:**
- Stopping between PRDs to report status
- Following "Next step" suggestions from prd-complete
- Waiting for user confirmation between PRDs
- Grepping for code to decide if PRD is "already done"
- Skipping prd-complete because "it looks implemented"

**REQUIRED:**
- Use Task tool to spawn sub-agent for pm:prd-complete for each PRD
- IMMEDIATELY continue to next PRD after each Task completes
- Only stop after ALL PRDs are processed
- Only check PRD frontmatter status field for skip
```

### Design Principles

1. **Be specific** - Not "don't make mistakes" but "don't grep for code to decide"
2. **Include the why** - "PRD status is the ONLY source of truth"
3. **Use visual markers** - Checkboxes, icons help scanning
4. **Balance forbidden/required** - Show both what not to do and what to do instead

### Anti-Pattern Categories for CCPM

| Category | Common Anti-Patterns |
|----------|---------------------|
| **Autonomy violations** | Stopping to ask, waiting for confirmation |
| **Scope creep** | Doing extra work not requested |
| **State management** | Ignoring status fields, not updating state |
| **Orchestration leaks** | Following sub-skill suggestions meant for standalone |
| **Skip logic errors** | Using heuristics instead of authoritative sources |

---

## 5. Important Rules Sections

### Placement and Purpose

From analysis of successful CCPM commands, "Important Rules" sections appear:
- **At the end** of the skill definition (most common)
- **After the main instructions** but before Notes
- Function as a **summary checklist** of critical behaviors

### Effective Pattern

**From `extract-findings.md`:**

```markdown
## Important Rules

1. **Query database** - Don't parse conversation, use SQL
2. **Only confirmed data** - Filter by `status = 'confirmed'`
3. **Generate tech ops** - Create `03_technical_ops.md`
4. **Generate test plan** - Create `08_test_plan.md`
5. **Derive NFRs** - Infer from cross-cutting concerns and scale
6. **Identify gaps** - Check for missing data
7. **Link files** - Reference related files in scope document
```

### Design Principles

1. **Number them** - Creates scannable checklist
2. **Bold the action** - Front-load the key word
3. **Keep each short** - One line per rule
4. **7 items** - Human working memory limit
5. **Action-oriented** - "Query database" not "The database should be queried"

### Alternative: REMEMBER Section

**From `scope-run.md`:**

```markdown
## REMEMBER

After EVERY action, ask yourself: "Is test.json.passed = true?"
- If NO - take the next action immediately
- If YES - stop and report success

Never ask the user:
- "Should I continue?"
- "Want me to proceed?"
- "Ready for the next step?"

Just do it.
```

This format is more narrative and works well for behavioral reminders.

---

## 6. Structured Output Formats

### YAML for Configuration

**Effective Pattern (from `generate-inputs.md`):**

```yaml
# .claude/inputs/myapp-inputs.yaml
---
version: 1
generated: 2026-01-21T10:30:00Z
script: "./setup.sh"
context:
  project_name: myapp
  framework: react

inputs:
  - prompt: "Continue with installation? [y/N]"
    type: binary
    value: "y"
    confidence: 0.95
    reasoning: "Non-destructive installation, safe to proceed"
```

### JSON for State

**Effective Pattern (from `fix-problem.md`):**

```json
{
  "command": "npm run build",
  "command_hash": "a1b2c3d4",
  "desired": "Build succeeds",
  "current_attempt": 2,
  "circuit_breaker": {
    "threshold": 3,
    "error_hashes": ["abc123", "abc123"],
    "state": "CLOSED"
  }
}
```

### Markdown Tables for Routing

**Effective Pattern:**

```markdown
| Error Type | Classification | Action |
|------------|----------------|--------|
| timeout | Transient | Retry with backoff |
| SyntaxError | Fixable | Try different approach |
| 401 Unauthorized | Permanent | Escalate immediately |
```

---

## 7. CCPM Skill Validation Checklist

Use this checklist before deploying a new CCPM skill:

### Structure Validation

- [ ] Frontmatter includes `allowed-tools` for all tools used
- [ ] `description` in frontmatter is specific and under 1024 chars
- [ ] Usage section shows exact invocation syntax
- [ ] Arguments and options are documented with defaults

### Instructions Quality

- [ ] Steps are numbered sequentially
- [ ] Each step has a concrete action (not just description)
- [ ] Verification checks follow each critical step
- [ ] Conditional routing uses tables or clear if/then format
- [ ] Loops show explicit termination conditions

### Task Tool Usage (if applicable)

- [ ] `subagent_type` is specified for each Task invocation
- [ ] Task prompts are self-contained (don't assume parent context)
- [ ] Behavioral constraints are embedded in Task prompts
- [ ] No nested Task tool expectations (subagents can't spawn subagents)

### Anti-Pattern Prevention

- [ ] FORBIDDEN section lists specific failure modes
- [ ] REQUIRED section shows correct alternatives
- [ ] Each anti-pattern has a brief "why" explanation
- [ ] Most common failure modes are covered

### Important Rules

- [ ] Rules section exists at the end of instructions
- [ ] Rules are numbered (not bulleted)
- [ ] Each rule is one line with bolded action word
- [ ] 5-7 rules maximum

### Output Specification

- [ ] Success output format is shown
- [ ] Failure output format is shown with recovery steps
- [ ] Output uses consistent formatting (not mixed styles)

### Autonomy (for orchestrator commands)

- [ ] CRITICAL section appears early with behavioral constraints
- [ ] "Ignore sub-skill suggestions" is explicit
- [ ] Stopping conditions are clearly defined
- [ ] Escalation criteria are specified

---

## 8. Specific Fixes for generate-inputs.md

### Current Issues

1. **Lacks CRITICAL section** - Not clear this should run autonomously
2. **Task tool usage not specified** - How to spawn subagents unclear
3. **No verification steps** - Can't confirm correct behavior
4. **Anti-patterns incomplete** - Missing key failure modes

### Recommended Fixes

**Add CRITICAL section after Usage:**

```markdown
## CRITICAL: Deterministic Input Generation

**This skill must produce reproducible, testable inputs.**

Do NOT:
- Guess at input values without evidence
- Generate random or arbitrary values
- Auto-fill credentials or passwords (EVER)

DO:
- Research context from project files before generating
- Document reasoning for each generated input
- Mark uncertain inputs as `deferred: true`
```

**Add verification after each phase:**

```markdown
### Phase 1: Analyze Script for Input Prompts

1. Read the script file
2. Extract all input prompts using pattern matching
3. **Verify:** Count detected prompts
   \`\`\`bash
   echo "Detected prompts: $PROMPT_COUNT"
   test $PROMPT_COUNT -gt 0 || echo " No prompts found - script may not be interactive"
   \`\`\`
```

**Add explicit anti-patterns:**

```markdown
## Anti-Pattern Prevention

**FORBIDDEN:**
- Auto-filling any credential, API key, or password
- Generating inputs without checking project context
- Using default values for destructive confirmations (delete, format, overwrite)
- Generating inputs for GUI-based prompts (not supported)

**REQUIRED:**
- Check git config for author/email values
- Check package.json/setup.py for project metadata
- Check .env for environment-specific values
- Mark all credentials as `deferred: true`
- Log confidence scores for each generated input
```

**Add Important Rules:**

```markdown
## Important Rules

1. **Never auto-fill credentials** - API keys, passwords, tokens always deferred
2. **Research before generating** - Check project files for context
3. **Default to safe options** - "n" for destructive, "y" for non-destructive
4. **Document reasoning** - Every input needs a `reasoning` field
5. **Validate timestamp** - Check script modification vs inputs file age
6. **Fail on unknown prompts** - Don't guess, mark as deferred or fail
```

---

## 9. Specific Fixes for fix-problem.md

### Current Issues

1. **Command mode Task invocation unclear** - Sub-task spawning needs explicit format
2. **Circuit breaker logic described but not actionable** - Needs concrete steps
3. **Auto mode input handling vague** - Integration with generate-inputs unclear
4. **No verification between retry attempts** - Can't confirm fix was applied

### Recommended Fixes

**Clarify Task tool invocation for generate-inputs:**

```markdown
### Auto Mode Input Handling

When `--auto` is specified:

**Step 1: Check for existing inputs file**
\`\`\`bash
INPUTS_FILE=".claude/inputs/${SCRIPT_NAME}-inputs.yaml"
if [ -f "$INPUTS_FILE" ]; then
  echo "Using existing inputs: $INPUTS_FILE"
else
  # Spawn generate-inputs sub-task
fi
\`\`\`

**Step 2: Spawn generate-inputs if needed**

\`\`\`yaml
Task:
  subagent_type: "general-purpose"
  description: "Generate inputs for {command}"
  prompt: |
    Run /pm:generate-inputs for command: "{command}"
    Output file: .claude/inputs/{command_hash}-inputs.yaml

    Analyze the script, identify input prompts, research context,
    and generate viable test inputs.

    Do NOT auto-fill any credentials - mark them as deferred.

    Return the path to the generated inputs file.
\`\`\`

**Step 3: Verify inputs file was created**
\`\`\`bash
test -f "$INPUTS_FILE" || { echo " generate-inputs failed"; exit 1; }
\`\`\`
```

**Add explicit circuit breaker steps:**

```markdown
### Circuit Breaker Execution

After each failed attempt:

1. **Hash the error** (first 50 chars + error type):
   \`\`\`bash
   ERROR_HASH=$(echo "$ERROR_OUTPUT" | head -c 50 | md5sum | cut -d' ' -f1)
   \`\`\`

2. **Check state file:**
   \`\`\`bash
   PREV_HASHES=$(jq -r '.circuit_breaker.error_hashes[-3:]' state.json)
   \`\`\`

3. **Count consecutive identical:**
   \`\`\`bash
   if all_same "$PREV_HASHES" "$ERROR_HASH"; then
     CONSECUTIVE=$((CONSECUTIVE + 1))
   else
     CONSECUTIVE=1
   fi
   \`\`\`

4. **Open circuit if threshold reached:**
   \`\`\`bash
   if [ $CONSECUTIVE -ge $THRESHOLD ]; then
     jq '.circuit_breaker.state = "OPEN"' state.json > tmp && mv tmp state.json
     echo "Circuit OPEN - escalating"
     # Exit to escalation output
   fi
   \`\`\`
```

**Add verification between attempts:**

```markdown
### Between-Attempt Verification

After applying a fix and before running the next attempt:

1. **Verify fix was applied:**
   \`\`\`bash
   git diff --stat HEAD~1  # Should show changed files
   \`\`\`

2. **Update state file:**
   \`\`\`bash
   jq ".attempts[$ATTEMPT].fix_verified = true" state.json > tmp && mv tmp state.json
   \`\`\`

3. **Wait for backoff:**
   \`\`\`bash
   BACKOFF=$((INITIAL_BACKOFF * (2 ** (ATTEMPT - 1))))
   BACKOFF=$((BACKOFF > 60 ? 60 : BACKOFF))
   sleep $BACKOFF
   \`\`\`
```

**Add anti-patterns specific to fix-problem:**

```markdown
## Anti-Pattern Prevention

**FORBIDDEN:**
- Retrying without changing anything between attempts
- Applying the same fix twice
- Ignoring circuit breaker state
- Modifying files without git safety (stash first)
- Running indefinitely on transient errors without backoff

**REQUIRED:**
- Fresh error analysis each retry (error may have changed)
- Different approach each retry attempt
- Respect circuit breaker threshold
- Persist state after each attempt for resumability
- Verify fix was applied before next attempt
```

---

## 10. Sources

### Anthropic Official Documentation

- [Prompting best practices - Claude 4 Best Practices](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)
- [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Claude Code: Best practices for agentic coding](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Create custom subagents - Claude Code Docs](https://code.claude.com/docs/en/sub-agents)
- [Structured outputs - Claude Docs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)

### CCPM Codebase Analysis

Commands analyzed for pattern extraction:
- `batch-process.md` - Orchestration, Task tool, anti-patterns
- `feature.md` - Complex routing, phase management, Task tool
- `scope-run.md` - Autonomous loops, judgment, CRITICAL sections
- `prd-complete.md` - Skill chaining, verification
- `deploy.md` - Configuration loading, error handling
- `extract-findings.md` - Database operations, Important Rules
- `interrogate.md` - User interaction, state management
- `decompose.md` - INVEST validation, dependency graphs
- `generate-inputs.md` - Input analysis (target for fixes)
- `fix-problem.md` - Error handling, retry logic (target for fixes)

### External Research

- [PromptHub: Prompt Engineering for AI Agents](https://www.prompthub.us/blog/prompt-engineering-for-ai-agents)
- [Best practices for Claude Code subagents](https://www.pubnub.com/blog/best-practices-for-claude-code-sub-agents/)
- [Building agents with the Claude Agent SDK](https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk)

---

## Appendix: Quick Reference Card

### Skill Template Sections (in order)

1. **Frontmatter** - tools, description, arguments, options
2. **Title + Summary** - One-line description
3. **Usage** - Exact invocation syntax
4. **CRITICAL** (if orchestrator) - Core behavioral constraint
5. **Quick Check** - Fail-fast validation
6. **Instructions** - Numbered steps with verification
7. **Output Format** - Success and failure examples
8. **Anti-Pattern Prevention** - FORBIDDEN/REQUIRED
9. **Important Rules** - Numbered checklist (5-7 items)
10. **Notes** - Integration points, additional context

### Task Tool Invocation Template

```yaml
Task:
  subagent_type: "general-purpose"  # or "Explore" for read-only
  description: "Brief description for logging"
  prompt: |
    Complete instructions for the subagent.
    Include all context needed - subagent has no parent context.
    Specify behavioral constraints explicitly.
    State what output to return.
```

### Anti-Pattern Section Template

```markdown
## Anti-Pattern Prevention

**FORBIDDEN:**
- [Specific bad behavior] ([brief why])
- [Specific bad behavior] ([brief why])

**REQUIRED:**
- [Correct alternative behavior]
- [Correct alternative behavior]
```

### Important Rules Template

```markdown
## Important Rules

1. **[Action word]** - [Brief explanation]
2. **[Action word]** - [Brief explanation]
3. **[Action word]** - [Brief explanation]
4. **[Action word]** - [Brief explanation]
5. **[Action word]** - [Brief explanation]
```
