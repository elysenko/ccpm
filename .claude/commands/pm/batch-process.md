# Batch Process PRDs

Process multiple PRDs through the complete lifecycle automatically.

## Usage
```
/pm:batch-process <prd1> [prd2] [prd3] ...
```

## Example
```
/pm:batch-process 76-workflow-phase-enum-updates 83-storage-layer-updates 84-workflow-state-consolidation
```

## Instructions

You are a batch processor that runs `/pm:prd-complete` for each PRD in sequence.

### CRITICAL EXECUTION RULE

**After EACH prd-complete Skill invocation completes, you MUST immediately proceed to the next PRD.**

- Do NOT stop between PRDs to report status
- Do NOT wait for user confirmation
- IGNORE any "Next step" suggestions from prd-complete
- The ONLY valid stopping point is after ALL PRDs are processed
- Track results internally and report at the end

### Pre-Processing

1. **Parse arguments** to get the list of PRDs
2. **For each PRD, check status:**
   ```bash
   for prd in $ARGUMENTS; do
     if [ -f ".claude/prds/${prd}.md" ]; then
       status=$(grep "^status:" .claude/prds/${prd}.md | cut -d: -f2 | tr -d ' ')
       echo "$prd: $status"
     else
       echo "$prd: NOT FOUND"
     fi
   done
   ```
3. **Categorize PRDs:**
   - `status: complete` → SKIP list
   - `status: backlog` or `in-progress` → PROCESS list
   - File not found → ERROR list
4. **Check dependencies:**
   - Read each PRD's `dependencies:` field
   - Reorder PROCESS list so dependencies come first
   - If dependency is NOT in batch and NOT complete → DEFER list
5. **Create tracking list** using TodoWrite

### Processing Loop

For EACH PRD in the PROCESS list:

**Invoke:** Use the Task tool to spawn a sub-agent that runs `/pm:prd-complete {prd-name}`:
```
Task tool parameters:
  subagent_type: "general-purpose"
  description: "Process PRD {prd-name}"
  prompt: "Run /pm:prd-complete {prd-name} to completion. Do not stop for confirmation. Execute all phases until the PRD status is complete."
```

**After task completes:**
1. Update TodoWrite to mark PRD complete
2. Record result (success/failure)
3. IMMEDIATELY continue to next PRD

**Do NOT stop between PRDs.** Continue until all PRDs in PROCESS list are done.

### Output Format

**ONLY output this after ALL PRDs are processed:**

```
=== BATCH PROCESSING COMPLETE ===

✅ 76-workflow-phase-enum-updates
   - All phases completed
   - PRD status: complete

✅ 83-storage-layer-updates
   - All phases completed
   - PRD status: complete

⏭️ 53-build-agent (SKIPPED)
   - Already complete

⏸️ 55-development-phase (DEFERRED)
   - Dependency: PRD 65 (status: backlog)
   - Will process after dependency completes

❌ 84-workflow-state-consolidation (FAILED)
   - Failed at: Phase 4 (epic-merge)
   - Error: Merge conflict
   - Manual resolution required

Summary:
  Processed: 4
  Succeeded: 2
  Skipped: 1
  Deferred: 1
  Failed: 1
```

## Skip Logic

**PRD status is the ONLY source of truth.**

- `status: complete` → Skip
- `status: backlog` or `in-progress` → Process with prd-complete

**Do NOT skip based on:**
- Code appearing to exist
- Epic files existing
- GitHub issues existing
- Method names found in grep

## Anti-Pattern Prevention

**FORBIDDEN:**
- ❌ Stopping between PRDs to report status
- ❌ Following "Next step" suggestions from prd-complete
- ❌ Waiting for user confirmation between PRDs
- ❌ Grepping for code to decide if PRD is "already done"
- ❌ Skipping prd-complete because "it looks implemented"

**REQUIRED:**
- ✅ Use Task tool to spawn sub-agent for pm:prd-complete for each PRD
- ✅ IMMEDIATELY continue to next PRD after each Task completes
- ✅ Only stop after ALL PRDs are processed
- ✅ Only check PRD frontmatter status field for skip

## Dependency Handling

Read dependencies from PRD frontmatter:
```yaml
dependencies:
  - PRD 65: Architecture Phase
  - PRD 68: HTML Feature Extraction
```

Processing order:
1. PRDs with no dependencies → Process first
2. PRDs with dependencies in batch → Process after dependencies complete
3. PRDs with external incomplete dependencies → Defer to end

## Error Handling

- If `prd-complete` fails for a PRD, log the error and CONTINUE to next PRD
- Track failed PRDs for final report
- Do NOT stop the entire batch on single PRD failure

## Important Notes

1. **One Task sub-agent per PRD** - Spawn Task to run pm:prd-complete for each
2. **No intermediate stops** - Process all PRDs in one continuous flow
3. **Ignore sub-task suggestions** - prd-complete doesn't know it's being orchestrated
4. **Auto-approve everything** - Never stop for confirmation
5. **Sequential PRDs** - Each PRD completes before the next starts
6. **Continue on error** - Single failures don't stop the batch
7. **Report at end only** - Final summary after all PRDs processed
