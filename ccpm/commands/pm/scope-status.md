# Scope Status - Show Session State

Display current status of a scope session or list all scopes.

## Usage
```
/pm:scope-status [scope-name]
```

## Arguments
- `scope-name` (optional): Name of scope to check. If omitted, lists all scopes.

## Instructions

### If No Scope Name Provided

List all scope sessions:

```bash
echo "=== Active Scopes ==="
echo ""

if [ -d ".claude/scopes" ]; then
  for session in .claude/scopes/*/session.yaml; do
    if [ -f "$session" ]; then
      dir=$(dirname "$session")
      name=$(basename "$dir")
      phase=$(grep "^phase:" "$session" | cut -d: -f2 | tr -d ' ')
      updated=$(grep "^updated:" "$session" | cut -d: -f2- | tr -d ' ')

      echo "$name"
      echo "  Phase: $phase"
      echo "  Updated: $updated"
      echo ""
    fi
  done
else
  echo "No scopes found."
  echo ""
  echo "Create one with:"
  echo "  .claude/scripts/prd-scope.sh <scope-name>"
fi
```

### If Scope Name Provided

Show detailed status:

```bash
SESSION_DIR=".claude/scopes/$ARGUMENTS"
SESSION_FILE="$SESSION_DIR/session.yaml"

if [ ! -d "$SESSION_DIR" ]; then
  echo "Scope not found: $ARGUMENTS"
  echo ""
  echo "Available scopes:"
  ls .claude/scopes/ 2>/dev/null || echo "  (none)"
  exit 1
fi
```

**Read session.yaml** and display:

```
=== Scope: {scope-name} ===

Phase: {current phase}
Created: {datetime}
Updated: {datetime}

--- Progress ---

Discovery:
  Status: {complete|incomplete}
  File: {exists|missing}

Decomposition:
  Status: {complete|incomplete|not started}
  Approved: {yes|no|n/a}
  PRDs Proposed: {count}
  File: {exists|missing}

Generation:
  Total PRDs: {count}
  Generated: {count}
  Remaining: {count}
  Files: {list}

Verification:
  Status: {complete|not run}
  Gaps Found: {count|n/a}
  File: {exists|missing}

--- Files ---

{list all files in session directory with sizes}

--- Next Action ---

{Based on current phase, suggest next command}
```

### Phase-Specific Next Actions

**discovery:**
```
Next: Complete discovery session
  .claude/scripts/prd-scope.sh {scope-name}

Or continue discovery:
  /pm:scope-discover {scope-name}
```

**decomposition:**
```
Next: Review and approve decomposition
  cat .claude/scopes/{scope-name}/decomposition.md

Then generate PRDs:
  .claude/scripts/prd-scope.sh {scope-name} --generate
```

**generation:**
```
Next: Continue generating PRDs
  .claude/scripts/prd-scope.sh {scope-name} --generate

Generated so far:
  {list of PRD files}
```

**verification:**
```
Next: Review verification results
  cat .claude/scopes/{scope-name}/verification.md

{If gaps found:}
Fix gaps, then re-verify:
  .claude/scripts/prd-scope.sh {scope-name} --verify

{If no gaps:}
Finalize to move PRDs to .claude/prds/:
  .claude/scripts/prd-scope.sh {scope-name} --verify
```

**complete:**
```
Scope complete!

PRDs created:
  {list PRDs in .claude/prds/ from this scope}

To process PRDs:
  .claude/scripts/batch-prd-complete.sh {prd-numbers}
```

### Output Format

```
=== Scope: {name} ===

Phase: {phase}
Created: {date}
Updated: {date}

Progress:
  [x] Discovery complete
  [x] Decomposition complete (8 PRDs proposed)
  [x] Generation complete (8/8 PRDs)
  [ ] Verification (not run)

Files:
  discovery.md       (12KB)
  decomposition.md   (8KB)
  prds/
    85-auth.md       (4KB)
    86-profile.md    (3KB)
    ...

Next:
  Run verification to check for gaps:
  .claude/scripts/prd-scope.sh {name} --verify
```

### Session Health Check

Also check for issues:

```
Warnings:
  - Discovery incomplete but decomposition started
  - PRDs generated but decomposition not approved
  - Verification has gaps but marked complete
```

### Output

Display the status report to the user. No files are modified by this command.
