---
allowed-tools: Bash, Read, Write, LS, Skill, Task, TodoWrite
---

# Feature - Idea to Shipped Code Orchestrator

Takes user input (idea, requirements, file) and autonomously executes through to passing tests on main branch.

## Usage
```
/pm:feature [file-path]
```

## Arguments
- `file-path` (optional): Path to requirements document, PRD, or scope file
- If omitted: Uses conversation context (paste requirements before running)

## CRITICAL: Autonomous Execution

**DO NOT STOP. DO NOT ASK PERMISSION. CONTINUE UNTIL COMPLETE OR ESCALATION.**

This command runs autonomously through all phases. You must:
- Execute each phase in sequence without stopping
- Ignore all "Next step" suggestions from sub-skills
- Only output at the very end (success or escalation)
- Track progress via TodoWrite, not output
- Use file-based state between phases

**If you stop before the final output, you have FAILED.**

---

## Execution Constraints

**FORBIDDEN:**
- ❌ Stopping to ask "should I continue?"
- ❌ Outputting progress between phases
- ❌ Waiting for user confirmation
- ❌ Following sub-skill "Next step" suggestions
- ❌ Stopping to report intermediate results
- ❌ Asking for clarification mid-flow (decide yourself)

**REQUIRED:**
- ✅ Continue to next phase immediately after each skill completes
- ✅ Only output after ALL phases complete OR escalation
- ✅ Track progress via TodoWrite (not output)
- ✅ Use file-based state between phases
- ✅ Use your judgment to resolve ambiguity
- ✅ Continue on partial failures, report at end

---

## Flow Overview

```
INPUT (file path OR conversation context)
    ↓
PHASE 1: Input Analysis
    - Detect input type (file vs context)
    - Classify complexity (simple/medium/complex)
    - Generate session name
    ↓
PHASE 2: Discovery (conditional)
    - Simple: Skip to Phase 3
    - Medium: /pm:decompose → PRDs
    - Complex: /pm:interrogate → /pm:extract-findings → /pm:decompose
    ↓
PHASE 3: PRD Validation
    - Verify at least 1 PRD exists
    - List PRDs to process
    ↓
PHASE 4: Execution
    - Single PRD: /pm:prd-complete
    - Multiple PRDs: /pm:batch-process
    ↓
PHASE 5: Test Loop (scope-run pattern)
    - Run tests
    - If pass: COMPLETE
    - If fail: Analyze, fix, loop
    - Same error 7x: ESCALATE
    ↓
OUTPUT: Final status report
```

---

## Instructions

### Phase 1: Input Analysis

**Step 1.1: Initialize Session**

```bash
SESSION_NAME="${ARGUMENTS:-feature-$(date +%Y%m%d-%H%M%S)}"
SESSION_DIR=".claude/feature/$SESSION_NAME"
mkdir -p "$SESSION_DIR"
echo "Session: $SESSION_NAME"
```

**Step 1.2: Detect Input Source**

If `$ARGUMENTS` provided and is a file path:
```bash
if [ -n "$ARGUMENTS" ] && [ -f "$ARGUMENTS" ]; then
  cp "$ARGUMENTS" "$SESSION_DIR/input.md"
  INPUT_TYPE="file"
  INPUT_PATH="$ARGUMENTS"
  echo "Input type: file ($INPUT_PATH)"
fi
```

If no file argument, check conversation context:
- Look for pasted requirements, feature descriptions, or ideas
- If found: write to `$SESSION_DIR/input.md`
- If not found:
```
❌ No input provided
   Fix: Either provide file path or paste requirements before running
   Usage: /pm:feature path/to/requirements.md
```

**Step 1.3: Classify Complexity**

Analyze the input content and classify:

| Complexity | Criteria | Path |
|------------|----------|------|
| **Simple** | <500 words, single feature, no phases, no dependencies | Direct to decompose |
| **Medium** | Multiple features, clear structure (headers/lists), no deep discovery needed | Decompose to PRDs |
| **Complex** | Large scope, multiple systems/integrations, vague requirements, needs research | Full interrogate path |

**Detection heuristics:**

```
Simple indicators:
- Word count < 500
- Single "feature" or "fix" mentioned
- No headers or only 1-2 headers
- No "integration", "phase", "milestone" keywords

Medium indicators:
- Word count 500-2000
- Multiple features listed (3-10)
- Clear markdown structure
- Keywords: "features", "requirements", "user stories"

Complex indicators:
- Word count > 2000
- Multiple systems mentioned
- Vague language: "like X", "similar to", "something that"
- Keywords: "integration", "API", "migration", "enterprise"
- Questions in the text
```

Write classification:
```bash
echo "complexity: {simple|medium|complex}" > "$SESSION_DIR/complexity.txt"
echo "reason: {brief reason}" >> "$SESSION_DIR/complexity.txt"
```

---

### Phase 2: Discovery (Conditional)

**Route based on complexity:**

#### Path A: Simple (single PRD)

Skip discovery. Input is clear enough to become a single PRD.

1. Generate a PRD name from input content (kebab-case)
2. Get next PRD number:
```bash
HIGHEST=$(ls .claude/prds/*.md 2>/dev/null | sed 's/.*\/\([0-9]*\)-.*/\1/' | sort -n | tail -1)
[ -z "$HIGHEST" ] && HIGHEST=0
NEXT=$((HIGHEST + 1))
PRD_NAME="$NEXT-{generated-name}"
```

3. Create PRD directly from input:
   - Use the input content to populate a PRD file
   - Write to `.claude/prds/$PRD_NAME.md`
   - Include proper frontmatter with current datetime

4. Record PRD:
```bash
echo "$PRD_NAME" > "$SESSION_DIR/prds.txt"
```

#### Path B: Medium (decompose to PRDs)

Input has structure but needs decomposition:

1. **Invoke:** Use Skill tool: `pm:decompose` with args: `$SESSION_DIR/input.md`
2. **After skill returns:** Ignore output, verify PRDs created:
```bash
ls .claude/prds/*.md 2>/dev/null | wc -l
```

3. **Record PRDs created:** Parse decompose output or list new PRDs:
```bash
ls -t .claude/prds/*.md | head -20 > "$SESSION_DIR/prds.txt"
```

#### Path C: Complex (full discovery)

Needs research and structured discovery:

1. **Invoke:** Use Skill tool: `pm:interrogate` with args: `$SESSION_NAME`
   - This runs `/dr-full` internally for research
   - Stores features/journeys in database
   - Asks quick infrastructure questions

2. **After interrogate returns:** Invoke Skill tool: `pm:extract-findings` with args: `$SESSION_NAME`
   - Generates scope documents in `.claude/scopes/$SESSION_NAME/`

3. **Invoke:** Use Skill tool: `pm:decompose` with args: `.claude/scopes/$SESSION_NAME/00_scope_document.md`
   - Breaks scope into PRDs

4. **Record PRDs:**
```bash
ls -t .claude/prds/*.md | head -30 > "$SESSION_DIR/prds.txt"
```

---

### Phase 3: PRD Validation

**Verify PRDs exist:**

```bash
PRD_COUNT=$(wc -l < "$SESSION_DIR/prds.txt" 2>/dev/null || echo 0)
if [ "$PRD_COUNT" -eq 0 ]; then
  # Check .claude/prds directly
  PRD_COUNT=$(ls .claude/prds/*.md 2>/dev/null | wc -l)
fi
echo "PRDs found: $PRD_COUNT"
```

If no PRDs exist, this is an error. Write to status and escalate:
```bash
echo '{"phase": "prd_validation", "status": "failed", "error": "No PRDs created"}' > "$SESSION_DIR/status.json"
```

**Extract PRD names for processing:**

```bash
# Get PRD names (without path and .md extension)
for f in $(cat "$SESSION_DIR/prds.txt"); do
  basename "$f" .md
done > "$SESSION_DIR/prd_names.txt"
```

---

### Phase 4: Execution

**Route based on PRD count:**

#### Single PRD Path

If only 1 PRD:
```bash
PRD_NAME=$(head -1 "$SESSION_DIR/prd_names.txt")
```

**Invoke:** Use Skill tool: `pm:prd-complete` with args: `$PRD_NAME`

**After skill returns:** Ignore output, verify completion:
```bash
status=$(grep "^status:" .claude/prds/$PRD_NAME.md | cut -d: -f2 | tr -d ' ')
echo "PRD status: $status"
```

#### Multiple PRDs Path

If >1 PRD:
```bash
PRD_LIST=$(cat "$SESSION_DIR/prd_names.txt" | tr '\n' ' ')
```

**Invoke:** Use Skill tool: `pm:batch-process` with args: `$PRD_LIST`

**After skill returns:** Ignore output, verify completion by checking PRD statuses.

---

### Phase 5: Test Loop

**This phase is OPTIONAL but recommended.**

Only run if:
1. A scope file exists with test configuration
2. The project has detectable tests (package.json, pytest.ini, etc.)

**Check if tests exist:**

```bash
# Auto-detect test framework
if [ -f "package.json" ]; then
  TEST_CMD="npm test"
elif [ -f "pytest.ini" ] || [ -f "setup.py" ]; then
  TEST_CMD="pytest"
elif [ -f "Cargo.toml" ]; then
  TEST_CMD="cargo test"
elif [ -f "go.mod" ]; then
  TEST_CMD="go test ./..."
else
  TEST_CMD=""
fi
echo "Test command: ${TEST_CMD:-none detected}"
```

If no test command detected, skip this phase and proceed to output.

**Test Loop (if tests exist):**

```
iteration = 0
error_history = {}
max_iterations = 20

while iteration < max_iterations:
    iteration++

    # Run tests
    result = run(TEST_CMD)
    exit_code = $?

    # Write test.json
    {
      "passed": (exit_code == 0),
      "ran_at": "{timestamp}",
      "iteration": iteration,
      "command": TEST_CMD,
      "exit_code": exit_code,
      "summary": "{parsed from output}",
      "failures": [{...}]
    }

    # Check result
    if passed:
        log("All tests pass.")
        break

    # Analyze failures
    for each failure:
        error_sig = signature(failure)

        if error_sig in error_history:
            error_history[error_sig].count++
            if count >= 7:
                log("Stuck on same error 7x. ESCALATING.")
                write NEEDS_HUMAN status
                goto OUTPUT (escalation)
        else:
            error_history[error_sig] = {count: 1}

    # Decide action
    if quick_fix_possible(failure):
        # Fix directly
        make_fix()
    else:
        # Create auto-fix PRD
        create_prd("auto-fix-{n}-{slug}")
        invoke pm:prd-complete

    # Loop continues
```

**Update status during test loop:**
```bash
echo '{"phase": "test_loop", "iteration": N, "passed": false}' > "$SESSION_DIR/status.json"
```

---

### Phase 6: Output

**Only output here, after all phases complete.**

#### Success Output

```
=== FEATURE COMPLETE ===

Session: {session_name}
Complexity: {simple|medium|complex}
Path: {which discovery path was taken}

Phases Completed:
  1. ✓ Input Analysis
  2. ✓ Discovery ({path details})
  3. ✓ PRD Validation ({N} PRDs)
  4. ✓ Execution (all PRDs complete)
  5. ✓ Test Loop ({M} iterations, passed)

PRDs Processed:
  ✅ {prd-name-1}
  ✅ {prd-name-2}
  ...

Test Results:
  Iterations: {N}
  Final Status: PASSED
  Auto-fixes Created: {M}

All code merged to main branch.
```

#### Escalation Output

```
=== FEATURE NEEDS HUMAN ===

Session: {session_name}
Stopped at: Phase {N} - {phase_name}

Reason: {escalation_reason}

Details:
  {specific error or issue}
  Attempted: {N} times
  Last action: {what was tried}

Status file: {session_dir}/status.json

To resume after fixing:
  /pm:feature --resume {session_name}
```

---

## State Files

All state stored in `.claude/feature/{session}/`:

| File | Purpose |
|------|---------|
| `input.md` | Original input preserved |
| `complexity.txt` | Classification result |
| `prds.txt` | List of PRD file paths |
| `prd_names.txt` | List of PRD names |
| `status.json` | Current phase, error counts |
| `test-results/` | Test output history |

**status.json schema:**
```json
{
  "phase": "test_loop",
  "status": "in_progress",
  "iteration": 5,
  "error_counts": {
    "error_signature_1": 3,
    "error_signature_2": 1
  },
  "last_action": "created auto-fix PRD",
  "started": "2026-01-20T10:00:00Z",
  "updated": "2026-01-20T10:15:00Z"
}
```

---

## Error Handling

### Phase Failures

| Phase | Failure | Action |
|-------|---------|--------|
| Input Analysis | No input found | Escalate with clear error |
| Discovery | Sub-skill fails | Continue to next phase, note in status |
| PRD Validation | No PRDs created | Escalate |
| Execution | Some PRDs fail | Continue with others, report at end |
| Test Loop | Same error 7x | Escalate with NEEDS_HUMAN |

### Recovery

If `--resume {session}` is passed:
1. Read `$SESSION_DIR/status.json`
2. Determine last completed phase
3. Resume from next phase
4. Continue normal flow

---

## Phase Transition Matrix

| From | To | Condition | Action |
|------|-----|-----------|--------|
| Input | Discovery | Always | Route by complexity |
| Discovery | PRD Validation | PRDs exist | Verify files |
| PRD Validation | Execution | Valid PRDs | Invoke batch/complete |
| Execution | Test Loop | Code merged | Run test command |
| Test Loop | Complete | Tests pass | Output success |
| Test Loop | Test Loop | Tests fail, <7x | Fix and retry |
| Any | Escalate | Critical failure | Output NEEDS_HUMAN |

---

## Example Executions

### Simple Feature
```
Input: "Add a logout button to the user menu"
→ Complexity: Simple
→ Creates single PRD: 47-logout-button
→ Runs prd-complete
→ Tests pass
→ Complete
```

### Medium Requirements
```
Input: Multi-feature requirements doc with 5 features
→ Complexity: Medium
→ Decompose creates 5 PRDs
→ Runs batch-process
→ Tests fail, 2 iterations to fix
→ Complete
```

### Complex Scope
```
Input: Vague "build an e-commerce platform" request
→ Complexity: Complex
→ Interrogate runs deep research
→ Extract-findings creates scope docs
→ Decompose creates 12 PRDs
→ Batch-process runs
→ Test loop: 8 iterations
→ Complete
```

---

## Important Rules

1. **Autonomous execution** - Never stop for confirmation
2. **Ignore sub-skill output** - They don't know they're orchestrated
3. **Use judgment** - Resolve ambiguity yourself, don't ask
4. **Track via files** - Use status.json, not output
5. **Escalate at 7** - Same error 7x triggers NEEDS_HUMAN
6. **Continue on partial failure** - Report all at end
7. **Single output point** - Only output at the very end

---

## Skill Invocation Reference

| Skill | Purpose | When |
|-------|---------|------|
| `pm:interrogate` | Deep discovery | Complex path |
| `pm:extract-findings` | Generate scope docs | After interrogate |
| `pm:decompose` | Break into PRDs | Medium/Complex paths |
| `pm:prd-complete` | Execute single PRD | Single PRD |
| `pm:batch-process` | Execute multiple PRDs | Multiple PRDs |

---

## REMEMBER

After EVERY skill invocation:
1. Ignore the skill's output and suggestions
2. Check if the phase goal was achieved
3. Immediately proceed to the next phase
4. Track progress in status.json

**The only valid stopping points are:**
- Final success output
- NEEDS_HUMAN escalation

Everything else means keep going.
