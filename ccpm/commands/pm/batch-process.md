# Batch Process PRDs

Automatically process all backlog PRDs in dependency order, with parallelism where dependencies allow.

## Usage
```
/pm:batch-process
```

No arguments required - automatically discovers all `status: backlog` PRDs.

## How It Works

1. **Scan** `.claude/prds/*.md` for PRDs with `status: backlog`
2. **Parse** dependencies from each PRD's frontmatter
3. **Build** dependency graph and detect circular dependencies
4. **Sort** PRDs into execution layers (topological sort)
5. **Generate** bash execution script
6. **Execute** the script immediately, streaming output

## Instructions

You are a batch execution planner and executor. Your job is to:
1. Analyze all backlog PRDs
2. Build an execution plan respecting dependencies
3. Generate and execute a bash script that processes PRDs

### Phase 1: Scan Backlog PRDs

```bash
echo "=== Batch Process Analysis ==="
echo ""
echo "Scanning .claude/prds/ for backlog PRDs..."

# Find all backlog PRDs
BACKLOG_PRDS=""
PRD_COUNT=0

for prd_file in .claude/prds/*.md; do
  [ -f "$prd_file" ] || continue

  # Extract status from frontmatter
  status=$(sed -n '/^---$/,/^---$/p' "$prd_file" | grep "^status:" | head -1 | cut -d: -f2 | tr -d ' ')

  if [ "$status" = "backlog" ]; then
    prd_name=$(basename "$prd_file" .md)
    BACKLOG_PRDS="$BACKLOG_PRDS $prd_name"
    PRD_COUNT=$((PRD_COUNT + 1))
  fi
done

echo "Found: $PRD_COUNT PRDs with status: backlog"
```

If no backlog PRDs found:
```
✅ No backlog PRDs to process
All PRDs are already complete or in-progress.
```
Exit successfully.

### Phase 2: Extract Dependencies

For each backlog PRD, extract dependencies from frontmatter:

```bash
# Parse dependencies for a PRD
# Format in PRD frontmatter:
#   dependencies:
#     - PRD 65: Architecture Phase
#     - PRD 68: HTML Feature Extraction

get_dependencies() {
  local prd_file="$1"

  # Extract dependencies section and parse PRD numbers
  sed -n '/^---$/,/^---$/p' "$prd_file" | \
    sed -n '/^dependencies:/,/^[a-z]/p' | \
    grep -oE 'PRD [0-9]+' | \
    sed 's/PRD //' | \
    tr '\n' ' '
}
```

Build a dependency map (use a temporary file or inline processing):
```
PRD_NAME -> DEPENDENCY_LIST
```

### Phase 3: Build Dependency Graph and Detect Cycles

Use Kahn's algorithm to:
1. Calculate in-degree (number of dependencies) for each PRD
2. Find PRDs with no dependencies (in-degree = 0)
3. Process layer by layer
4. Detect cycles if any PRD can't be processed

```bash
# Detect circular dependencies
# If after processing, some PRDs still have unmet dependencies, there's a cycle

if [ -n "$REMAINING_PRDS" ]; then
  echo "❌ Circular dependency detected!"
  echo ""
  echo "These PRDs have unresolvable dependencies:"
  for prd in $REMAINING_PRDS; do
    deps=$(get_dependencies ".claude/prds/${prd}.md")
    echo "  $prd depends on: $deps"
  done
  echo ""
  echo "Fix the circular dependency and try again."
  exit 1
fi
```

### Phase 4: Generate Execution Layers

Group PRDs into layers:
- **Layer 0**: PRDs with no dependencies (can run in parallel)
- **Layer 1**: PRDs depending only on Layer 0 (can run in parallel after Layer 0)
- **Layer N**: PRDs depending on Layers 0 to N-1

Output the execution plan:
```
Building dependency graph...
✓ No circular dependencies

Execution Plan:
  Layer 0 (parallel): 61-auth, 62-api-base, 63-database
  Layer 1 (parallel): 64-user-service (depends: 61, 62)
  Layer 2 (sequential): 65-notifications (depends: 64)
```

### Phase 5: Generate Execution Script

Create the execution script at `.claude/scripts/batch-execution-<timestamp>.sh`:

```bash
#!/bin/bash
# Auto-generated batch execution plan
# Generated: <TIMESTAMP>
# PRDs: <COUNT>
# Layers: <LAYER_COUNT>

set -uo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOGDIR=".claude/logs/batch-$TIMESTAMP"
mkdir -p "$LOGDIR"

TOTAL_PRDS=<COUNT>
SUCCEEDED=0
FAILED=0

log_result() {
  local prd="$1"
  local exit_code="$2"
  if [ "$exit_code" -eq 0 ]; then
    echo "  [$prd] ✅ Complete"
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    echo "  [$prd] ❌ Failed (exit code: $exit_code)"
    FAILED=$((FAILED + 1))
  fi
}

# Layer 0 - No dependencies
echo "=== Layer 0: <N> PRDs (parallel) ==="
(
  claude --dangerously-skip-permissions --print "/pm:prd-complete <prd-A>" 2>&1 | tee "$LOGDIR/<prd-A>.log" &
  PID_A=$!
  claude --dangerously-skip-permissions --print "/pm:prd-complete <prd-B>" 2>&1 | tee "$LOGDIR/<prd-B>.log" &
  PID_B=$!

  wait $PID_A
  log_result "<prd-A>" $?
  wait $PID_B
  log_result "<prd-B>" $?
)
echo "[Layer 0] Complete"
echo ""

# Layer 1 - Depends on Layer 0
echo "=== Layer 1: <N> PRDs ==="
claude --dangerously-skip-permissions --print "/pm:prd-complete <prd-C>" 2>&1 | tee "$LOGDIR/<prd-C>.log"
log_result "<prd-C>" $?
echo "[Layer 1] Complete"
echo ""

# ... more layers ...

echo ""
echo "=== Batch Complete ==="
echo "Total: $TOTAL_PRDS PRDs"
echo "Succeeded: $SUCCEEDED"
echo "Failed: $FAILED"
echo "Logs: $LOGDIR/"

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "Failed PRDs - check logs for details:"
  grep -l "exit code:" "$LOGDIR"/*.log 2>/dev/null | while read f; do
    echo "  $(basename "$f" .log)"
  done
  exit 1
fi
```

### Phase 6: Execute the Script

After generating, immediately execute:

```bash
SCRIPT_PATH=".claude/scripts/batch-execution-$TIMESTAMP.sh"
chmod +x "$SCRIPT_PATH"

echo "Generated: $SCRIPT_PATH"
echo "Logs: .claude/logs/batch-$TIMESTAMP/"
echo ""
echo "=== Executing Batch ==="
echo ""

# Execute and stream output
bash "$SCRIPT_PATH"
```

## Complete Implementation

Here is the full bash script to generate and execute (run this in Bash tool):

```bash
#!/bin/bash
set -uo pipefail

echo "=== Batch Process Analysis ==="
echo ""
echo "Scanning .claude/prds/ for backlog PRDs..."

# Ensure directories exist
mkdir -p .claude/scripts .claude/logs

# Phase 1: Find backlog PRDs
declare -A PRD_DEPS
BACKLOG_PRDS=()

for prd_file in .claude/prds/*.md; do
  [ -f "$prd_file" ] || continue

  # Extract status
  status=$(sed -n '1,/^---$/{ /^---$/d; p; }' "$prd_file" | sed -n '1,/^---$/p' | grep "^status:" | head -1 | cut -d: -f2 | tr -d ' ')

  # Handle frontmatter extraction properly
  status=$(awk '/^---$/{if(f)exit;f=1;next}f&&/^status:/{print $2;exit}' "$prd_file" | tr -d ' ')

  if [ "$status" = "backlog" ]; then
    prd_name=$(basename "$prd_file" .md)
    BACKLOG_PRDS+=("$prd_name")

    # Extract dependencies (PRD numbers only)
    deps=$(awk '/^---$/{if(f)exit;f=1;next}f&&/^dependencies:/,/^[a-z]/{print}' "$prd_file" | \
           grep -oE 'PRD [0-9]+' | sed 's/PRD //' | tr '\n' ' ')
    PRD_DEPS["$prd_name"]="$deps"
  fi
done

PRD_COUNT=${#BACKLOG_PRDS[@]}
echo "Found: $PRD_COUNT PRDs with status: backlog"

if [ "$PRD_COUNT" -eq 0 ]; then
  echo ""
  echo "✅ No backlog PRDs to process"
  echo "All PRDs are already complete or in-progress."
  exit 0
fi

echo ""

# Phase 2: Build dependency graph and compute layers using Kahn's algorithm
echo "Building dependency graph..."

declare -A IN_DEGREE
declare -A LAYER
LAYERS=()

# Initialize in-degrees
for prd in "${BACKLOG_PRDS[@]}"; do
  IN_DEGREE["$prd"]=0
done

# Calculate in-degrees (only count dependencies that are also in backlog)
for prd in "${BACKLOG_PRDS[@]}"; do
  for dep_num in ${PRD_DEPS["$prd"]}; do
    # Find PRD name matching this number
    for other in "${BACKLOG_PRDS[@]}"; do
      if [[ "$other" =~ ^${dep_num}- ]]; then
        IN_DEGREE["$prd"]=$((${IN_DEGREE["$prd"]} + 1))
      fi
    done
  done
done

# Kahn's algorithm - build layers
REMAINING=("${BACKLOG_PRDS[@]}")
CURRENT_LAYER=0

while [ ${#REMAINING[@]} -gt 0 ]; do
  # Find all PRDs with in-degree 0
  LAYER_PRDS=()
  NEW_REMAINING=()

  for prd in "${REMAINING[@]}"; do
    if [ "${IN_DEGREE["$prd"]}" -eq 0 ]; then
      LAYER_PRDS+=("$prd")
      LAYER["$prd"]=$CURRENT_LAYER
    else
      NEW_REMAINING+=("$prd")
    fi
  done

  # Check for cycle
  if [ ${#LAYER_PRDS[@]} -eq 0 ]; then
    echo "❌ Circular dependency detected!"
    echo ""
    echo "These PRDs have unresolvable dependencies:"
    for prd in "${NEW_REMAINING[@]}"; do
      echo "  $prd depends on: ${PRD_DEPS["$prd"]}"
    done
    echo ""
    echo "Fix the circular dependency and try again."
    exit 1
  fi

  # Store layer
  LAYERS[$CURRENT_LAYER]="${LAYER_PRDS[*]}"

  # Decrease in-degrees for PRDs that depended on this layer
  for done_prd in "${LAYER_PRDS[@]}"; do
    # Extract the number from done_prd
    done_num=$(echo "$done_prd" | grep -oE '^[0-9]+')

    for prd in "${NEW_REMAINING[@]}"; do
      if [[ " ${PRD_DEPS["$prd"]} " =~ " $done_num " ]]; then
        IN_DEGREE["$prd"]=$((${IN_DEGREE["$prd"]} - 1))
      fi
    done
  done

  REMAINING=("${NEW_REMAINING[@]}")
  CURRENT_LAYER=$((CURRENT_LAYER + 1))
done

TOTAL_LAYERS=$CURRENT_LAYER
echo "✓ No circular dependencies"
echo ""

# Phase 3: Display execution plan
echo "Execution Plan:"
for ((i=0; i<TOTAL_LAYERS; i++)); do
  layer_prds="${LAYERS[$i]}"
  prd_count=$(echo "$layer_prds" | wc -w)
  parallel_note=""
  [ "$prd_count" -gt 1 ] && parallel_note=" (parallel)"
  echo "  Layer $i$parallel_note: $layer_prds"
done
echo ""

# Phase 4: Generate execution script
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_PATH=".claude/scripts/batch-execution-$TIMESTAMP.sh"
LOGDIR=".claude/logs/batch-$TIMESTAMP"

cat > "$SCRIPT_PATH" << 'SCRIPT_HEADER'
#!/bin/bash
# Auto-generated batch execution plan
SCRIPT_HEADER

cat >> "$SCRIPT_PATH" << SCRIPT_META
# Generated: $TIMESTAMP
# PRDs: $PRD_COUNT
# Layers: $TOTAL_LAYERS

set -uo pipefail

LOGDIR="$LOGDIR"
mkdir -p "\$LOGDIR"

TOTAL_PRDS=$PRD_COUNT
SUCCEEDED=0
FAILED=0
FAILED_LIST=""

log_result() {
  local prd="\$1"
  local exit_code="\$2"
  if [ "\$exit_code" -eq 0 ]; then
    echo "  [\$prd] ✅ Complete"
    SUCCEEDED=\$((SUCCEEDED + 1))
  else
    echo "  [\$prd] ❌ Failed (exit code: \$exit_code)"
    FAILED=\$((FAILED + 1))
    FAILED_LIST="\$FAILED_LIST \$prd"
  fi
}

SCRIPT_META

# Generate layer execution code
for ((i=0; i<TOTAL_LAYERS; i++)); do
  layer_prds="${LAYERS[$i]}"
  prd_array=($layer_prds)
  prd_count=${#prd_array[@]}

  echo "" >> "$SCRIPT_PATH"

  if [ "$prd_count" -eq 1 ]; then
    # Single PRD - sequential
    prd="${prd_array[0]}"
    cat >> "$SCRIPT_PATH" << LAYER_SINGLE
echo "=== Layer $i: 1 PRD ==="
claude --dangerously-skip-permissions --print "/pm:prd-complete $prd" 2>&1 | tee "\$LOGDIR/$prd.log"
log_result "$prd" \$?
echo "[Layer $i] Complete"
echo ""

LAYER_SINGLE
  else
    # Multiple PRDs - parallel
    cat >> "$SCRIPT_PATH" << LAYER_PARALLEL_START
echo "=== Layer $i: $prd_count PRDs (parallel) ==="
(
LAYER_PARALLEL_START

    # Generate parallel commands with sanitized PID variable names
    pid_idx=0
    declare -A PID_MAP
    for prd in "${prd_array[@]}"; do
      PID_MAP["$prd"]="PID_$pid_idx"
      cat >> "$SCRIPT_PATH" << PARALLEL_CMD
  claude --dangerously-skip-permissions --print "/pm:prd-complete $prd" 2>&1 | tee "\$LOGDIR/$prd.log" &
  PID_$pid_idx=\$!
PARALLEL_CMD
      pid_idx=$((pid_idx + 1))
    done

    echo "" >> "$SCRIPT_PATH"

    # Generate wait and log commands
    for prd in "${prd_array[@]}"; do
      pid_var="${PID_MAP["$prd"]}"
      cat >> "$SCRIPT_PATH" << PARALLEL_WAIT
  wait \$$pid_var
  log_result "$prd" \$?
PARALLEL_WAIT
    done

    cat >> "$SCRIPT_PATH" << LAYER_PARALLEL_END
)
echo "[Layer $i] Complete"
echo ""

LAYER_PARALLEL_END
  fi
done

# Add summary footer
cat >> "$SCRIPT_PATH" << 'SCRIPT_FOOTER'
echo ""
echo "=== Batch Complete ==="
echo "Total: $TOTAL_PRDS PRDs"
echo "Succeeded: $SUCCEEDED"
echo "Failed: $FAILED"
echo "Logs: $LOGDIR/"

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "Failed PRDs:"
  for prd in $FAILED_LIST; do
    echo "  $prd"
  done
  exit 1
fi
SCRIPT_FOOTER

chmod +x "$SCRIPT_PATH"

echo "Generated: $SCRIPT_PATH"
echo "Logs: $LOGDIR/"
echo ""
echo "=== Executing Batch ==="
echo ""

# Execute the generated script
bash "$SCRIPT_PATH"
```

## Output Format

```
=== Batch Process Analysis ===

Scanning .claude/prds/ for backlog PRDs...
Found: 15 PRDs with status: backlog

Building dependency graph...
✓ No circular dependencies

Execution Plan:
  Layer 0 (parallel): 61-auth, 62-api-base, 63-database
  Layer 1 (parallel): 64-user-service (depends: 61, 62)
  Layer 2: 65-notifications (depends: 64)
  ...

Generated: .claude/scripts/batch-execution-20260122-143052.sh
Logs: .claude/logs/batch-20260122-143052/

=== Executing Batch ===

=== Layer 0: 3 PRDs (parallel) ===
  [61-auth] ✅ Complete
  [62-api-base] ✅ Complete
  [63-database] ✅ Complete
[Layer 0] Complete

=== Layer 1: 1 PRD ===
  [64-user-service] ✅ Complete
[Layer 1] Complete

...

=== Batch Complete ===
Total: 15 PRDs
Succeeded: 13
Failed: 2
Logs: .claude/logs/batch-20260122-143052/

Failed PRDs:
  67-reporting
  72-export
```

## Error Cases

### No Backlog PRDs
```
✅ No backlog PRDs to process
All PRDs are already complete or in-progress.
```

### Circular Dependencies
```
❌ Circular dependency detected!

These PRDs have unresolvable dependencies:
  64-user-service depends on: 65
  65-notifications depends on: 64

Fix the circular dependency and try again.
```

### PRD Execution Failure
Individual PRD failures don't stop the batch. Failed PRDs are logged and reported at the end. Subsequent layers still execute if their dependencies succeeded.

## Important Notes

1. **Automatic Discovery** - No arguments needed, scans all backlog PRDs
2. **Dependency Respect** - PRDs only run after their dependencies complete
3. **Maximum Parallelism** - Independent PRDs in the same layer run in parallel
4. **Continue on Failure** - Failed PRDs don't block independent work
5. **Full Logging** - Each PRD gets its own log file for debugging
6. **Reproducible** - Generated script can be re-run manually if needed
