# PRD Complete

Execute the full PRD lifecycle: parse, decompose, sync, implement, merge, and mark complete.

## Usage
```
/pm:prd-complete <prd-name>
```

## Example
```
/pm:prd-complete 76-workflow-phase-enum-updates
```

## CRITICAL: Continuous Execution Model

**READ THIS FIRST. This is where most failures happen.**

### The Trap You Must Avoid

When you invoke a sub-skill (prd-parse, epic-decompose, etc.), it will complete and output something like:

```
✅ Epic created: .claude/epics/feature-name/epic.md

Summary:
  - 3 task categories identified
  - Key architecture decisions: ...

Ready to break down into tasks? Run: /pm:epic-decompose feature-name
```

**THIS IS A TRAP. IGNORE ALL OF IT.**

The sub-skills don't know they're being orchestrated by prd-complete. Their "Next step" suggestions are for standalone use. When orchestrated:

1. The Skill tool returns → that's your signal
2. Run the verify command (one bash check)
3. **IMMEDIATELY invoke the next Skill**
4. **DO NOT OUTPUT ANY TEXT**

### The Golden Rule: NO OUTPUT BETWEEN PHASES

- **Phases 1-5**: ZERO text output. Nothing. No summaries. No acknowledgments.
- **Phase 6**: Final summary ONLY after ALL phases complete.

If you find yourself about to type ANYTHING between phases, **STOP**. You're about to violate this rule.

### Checklist: Am I About To Fail?

Before outputting text, ask yourself:
- [ ] Have ALL 6 phases completed? If no → **DO NOT OUTPUT**
- [ ] Am I following a sub-skill's "Next step" suggestion? → **THAT'S WRONG**
- [ ] Am I reporting intermediate status? → **THAT'S FORBIDDEN**
- [ ] Am I about to read/edit source code? → **THAT'S NOT YOUR JOB**

### What Success Looks Like

```
[Preflight check - bash]
[Skill: prd-parse] → [Verify - bash] →
[Skill: epic-decompose] → [Verify - bash] →
[Skill: epic-sync] → [Verify - bash] →
[Skill: epic-start] → [Verify - bash] →
[Skill: epic-merge] → [Verify - bash] →
[Phase 6 - bash commands] →
[FINAL OUTPUT ONLY HERE]
```

No text output until the final summary. Just tool calls.

---

## Instructions

You are executing the complete PRD-to-production lifecycle. This command orchestrates all PM commands in sequence.

### Role Constraint

**You are an ORCHESTRATOR, not an IMPLEMENTER.**

Your ONLY job is:
1. Check PRD status
2. Invoke Skills via the Skill tool
3. Run verify command
4. **IMMEDIATELY** invoke next Skill (no text output)
5. Repeat until done

You MUST NOT:
- Read source code files (only .claude/ files for status checks)
- Edit source code files
- Create git branches directly
- Make commits directly (except Phase 6 status update)
- "Help" by implementing when a Skill could do it
- Read task files to understand the implementation
- **Output any text between phases**

---

### Pre-flight Check

```bash
# Verify PRD exists
test -f .claude/prds/$ARGUMENTS.md || { echo "❌ PRD not found: $ARGUMENTS"; exit 1; }

# Check PRD status
status=$(grep "^status:" .claude/prds/$ARGUMENTS.md | cut -d: -f2 | tr -d ' ')
```

- If `status: complete` → Output "✅ PRD already complete. Nothing to do." and STOP
- If `status: backlog` or `status: in-progress` → Continue to Phase 1

---

### Phase 1: Parse PRD to Epic

**Invoke:** Use the Skill tool to call `pm:prd-parse` with argument `$ARGUMENTS`

**Verify:**
```bash
test -f .claude/epics/$ARGUMENTS/epic.md && echo "✓" || echo "❌"
```

**→ IMMEDIATELY invoke Phase 2. NO TEXT OUTPUT.**

---

### Phase 2: Decompose Epic to Tasks

**Invoke:** Use the Skill tool to call `pm:epic-decompose` with argument `$ARGUMENTS`

**Verify:**
```bash
ls .claude/epics/$ARGUMENTS/[0-9]*.md 2>/dev/null | head -1 && echo "✓" || echo "❌"
```

**→ IMMEDIATELY invoke Phase 3. NO TEXT OUTPUT.**

---

### Phase 3: Sync to GitHub

**Invoke:** Use the Skill tool to call `pm:epic-sync` with argument `$ARGUMENTS`

**Verify:**
```bash
grep -q "github:" .claude/epics/$ARGUMENTS/epic.md && echo "✓" || echo "❌"
```

**→ IMMEDIATELY invoke Phase 4. NO TEXT OUTPUT.**

---

### Phase 4: Implement Epic

**Invoke:** Use the Skill tool to call `pm:epic-start` with argument `$ARGUMENTS`

**Verify:**
```bash
echo "✓ (implementation delegated)"
```

**→ IMMEDIATELY invoke Phase 5. NO TEXT OUTPUT. Do not verify code.**

---

### Phase 5: Merge Epic

**Invoke:** Use the Skill tool to call `pm:epic-merge` with argument `$ARGUMENTS`

**Verify:**
```bash
git log --oneline -1 | grep -q "epic\|Epic\|Issue" && echo "✓" || echo "❌"
```

**→ Continue to Phase 6.**

---

### Phase 6: Mark PRD Complete

**Execute directly (no Skill invocation):**
```bash
# Update PRD status
sed -i 's/status: backlog/status: complete/' .claude/prds/$ARGUMENTS.md
sed -i 's/status: in-progress/status: complete/' .claude/prds/$ARGUMENTS.md

# Update timestamp
current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sed -i "s/^updated:.*/updated: $current_date/" .claude/prds/$ARGUMENTS.md

# Commit
git add .claude/prds/$ARGUMENTS.md .claude/epics/
git commit -m "PRD $ARGUMENTS: Mark complete"
git push origin main
```

---

### Final Output

**THIS IS THE ONLY PLACE YOU OUTPUT TEXT:**

```
✅ PRD Complete: $ARGUMENTS

Phases completed:
  1. ✓ Parse PRD to Epic
  2. ✓ Decompose to tasks
  3. ✓ Sync to GitHub
  4. ✓ Implement all tasks
  5. ✓ Merge to main
  6. ✓ PRD marked complete

PRD status: complete
```

---

## Error Handling

If any phase fails critically:
1. Report which phase failed
2. Show the specific error
3. STOP execution
4. Suggest manual fix

Partial failures (e.g., some tasks didn't implement) should NOT stop execution - continue to merge what's done.

## Quick Reference: Forbidden vs Required

**FORBIDDEN:**
- ❌ ANY text output between phases
- ❌ Following sub-skill "Next step" suggestions
- ❌ Stopping to report intermediate status
- ❌ Reading source code files
- ❌ Implementing code directly
- ❌ Waiting for user confirmation

**REQUIRED:**
- ✅ Invoke Skill → Verify → IMMEDIATELY invoke next Skill
- ✅ NO TEXT between phases
- ✅ Trust sub-skills to do their job
- ✅ Only output after Phase 6 completes

---

## REMINDER: Continuous Execution (Read This Again)

**If you're reading this, you're probably between phases. Ask yourself:**

1. Have ALL 6 phases completed?
   - **NO** → STOP READING. Invoke the next Skill NOW.
   - **YES** → Output the final PRD summary.

2. Did a sub-skill just output "Ready to X? Run /pm:Y"?
   - **IGNORE IT.** That's for standalone use. You're orchestrating.

3. Are you about to type text explaining what happened?
   - **THAT'S FORBIDDEN.** Just invoke the next Skill.

4. Did you just verify a phase and want to report "Phase X complete"?
   - **DON'T.** The verify bash command already echoed. Move on.

**The only valid text output is the final summary after Phase 6.**
