#!/bin/bash
# fix-loop.sh — Autonomous feedback-driven fix loop
#
# Reads test feedback from DB, synthesizes fix specs, spawns parallel fix agents,
# merges shared file changes, rebuilds, re-tests, and iterates until convergence.
#
# Usage:
#   ./fix-loop.sh [session-name] [flags]
#
# Flags:
#   --skip-first-test       Use latest test_run_id from DB instead of running tests first
#   --max-iterations N      Maximum fix-test iterations (default: 5)
#   --workers N             Parallel fix agent count (default: 3)
#   --test-workers N        Test runner worker count (default: 4)
#   --skip-build            Skip build.sh on first iteration (useful for debugging)
#   --help                  Show usage

set -euo pipefail

# ── Setup ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"

# Source libraries
source "$SCRIPT_DIR/lib/test-lib.sh"
source "$SCRIPT_DIR/lib/fix-cluster-map.sh"
source "$SCRIPT_DIR/lib/fix-lib.sh"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ── CLI Parsing ──────────────────────────────────────────────────────────────
SESSION_NAME=""
SKIP_FIRST_TEST=false
MAX_ITERATIONS=5
NUM_WORKERS=3
TEST_WORKERS=4
SKIP_BUILD=false
RESUME=false

show_usage() {
  cat << 'USAGE_EOF'
Usage: fix-loop.sh [session-name] [flags]

Autonomous feedback-driven fix loop. Reads test failures, synthesizes fixes,
applies them in parallel, rebuilds, and re-tests until convergence.

Arguments:
  session-name              Session in .claude/RESEARCH/ (auto-detected if omitted)

Flags:
  --skip-first-test         Use latest test_run_id from DB (skip initial test run)
  --max-iterations N        Maximum fix-test iterations (default: 5)
  --workers N               Parallel fix agent count (default: 3)
  --test-workers N          Test runner worker count (default: 4)
  --skip-build              Skip build.sh on first iteration
  --resume                  Resume from last completed iteration
  --help                    Show this usage

Examples:
  # Full autonomous run from existing test results
  ./fix-loop.sh task-3-20260210-214345 --skip-first-test

  # With custom limits
  ./fix-loop.sh task-3-20260210-214345 --max-iterations 3 --workers 4 --test-workers 4

  # Single iteration for debugging
  ./fix-loop.sh task-3-20260210-214345 --max-iterations 1 --skip-first-test

  # Resume after interruption
  ./fix-loop.sh task-3-20260210-214345 --max-iterations 3 --resume
USAGE_EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) show_usage; exit 0 ;;
    --skip-first-test) SKIP_FIRST_TEST=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --resume) RESUME=true; shift ;;
    --max-iterations)
      [[ -z "${2:-}" ]] && { echo "Error: --max-iterations requires a number" >&2; exit 1; }
      MAX_ITERATIONS="$2"; shift 2 ;;
    --workers)
      [[ -z "${2:-}" ]] && { echo "Error: --workers requires a number" >&2; exit 1; }
      NUM_WORKERS="$2"; shift 2 ;;
    --test-workers)
      [[ -z "${2:-}" ]] && { echo "Error: --test-workers requires a number" >&2; exit 1; }
      TEST_WORKERS="$2"; shift 2 ;;
    -*)
      echo "Unknown flag: $1" >&2; show_usage; exit 1 ;;
    *)
      if [ -z "$SESSION_NAME" ]; then
        SESSION_NAME="$1"
      else
        echo "Error: unexpected argument '$1'" >&2; exit 1
      fi
      shift ;;
  esac
done

# ── Session detection ─────────────────────────────────────────────────────────
if [ -z "$SESSION_NAME" ]; then
  # Auto-detect from .claude/RESEARCH/ (same logic as test-runner.sh)
  research_dir="$PROJECT_ROOT/.claude/RESEARCH"
  if [ -d "$research_dir" ]; then
    latest="" latest_time=0
    for dir in "$research_dir"/*/; do
      [ ! -d "$dir" ] && continue
      if [ -f "$dir/personas-generated.txt" ] || [ -f "$dir/personas.json" ]; then
        mtime=$(stat -c %Y "$dir" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$latest_time" ]; then
          latest_time="$mtime"
          latest=$(basename "$dir")
        fi
      fi
    done
    SESSION_NAME="$latest"
  fi
  if [ -z "$SESSION_NAME" ]; then
    echo -e "${RED}No session specified and none auto-detected.${NC}" >&2
    exit 1
  fi
  fl_log "Auto-detected session: $SESSION_NAME"
fi

SESSION_DIR="$PROJECT_ROOT/.claude/RESEARCH/$SESSION_NAME"
if [ ! -d "$SESSION_DIR" ]; then
  fl_log_error "Session directory not found: $SESSION_DIR"
  exit 1
fi

# ── Load DB config ────────────────────────────────────────────────────────────
tl_load_db_config

# ── Working directory ────────────────────────────────────────────────────────
WORK_DIR="$SESSION_DIR/.fix-loop"
mkdir -p "$WORK_DIR" 2>/dev/null || true

HISTORY_FILE="$WORK_DIR/metrics-history.txt"
UNFIXABLE_FILE="$WORK_DIR/unfixable.json"

# Initialize unfixable file if missing
if [ ! -f "$UNFIXABLE_FILE" ]; then
  echo '{"items":[]}' > "$UNFIXABLE_FILE"
fi

# ── Resume Detection ──────────────────────────────────────────────────────────
START_ITERATION=1
ITER_MARKER="$WORK_DIR/last-completed-iteration.txt"
LAST_TRID_FILE="$WORK_DIR/last-test-run-id.txt"

if [ "$RESUME" = true ]; then
  if [ -f "$ITER_MARKER" ]; then
    last_done=$(cat "$ITER_MARKER" | tr -d '[:space:]')
    if [ -n "$last_done" ] && [ "$last_done" -ge 1 ] 2>/dev/null; then
      START_ITERATION=$((last_done + 1))
      # Validate that the last test run has enough results (>= 15 instances).
      # If session crashed mid-test, the data is incomplete and tests must re-run.
      if [ -f "$LAST_TRID_FILE" ]; then
        last_trid=$(cat "$LAST_TRID_FILE" | tr -d '[:space:]')
        instance_count=$(echo "SELECT count(*) FROM test_instance WHERE test_run_id='$last_trid';" | tl_db_query | tr -d '[:space:]') || true
        if [ -n "$instance_count" ] && [ "$instance_count" -ge 15 ] 2>/dev/null; then
          SKIP_FIRST_TEST=true
          echo -e "${CYAN}Resuming from iteration $START_ITERATION (iteration $last_done completed, $instance_count test instances)${NC}"
        else
          echo -e "${YELLOW}Resuming from iteration $START_ITERATION but last test run incomplete ($instance_count instances) — will re-test${NC}"
        fi
      else
        echo -e "${CYAN}Resuming from iteration $START_ITERATION (iteration $last_done completed, no prior test data)${NC}"
      fi
    fi
  elif [ -f "$LAST_TRID_FILE" ]; then
    # Tests ran but no iteration completed (crashed during synthesis/fix/commit).
    # Only skip re-running tests if the run looks complete.
    last_trid=$(cat "$LAST_TRID_FILE" | tr -d '[:space:]')
    instance_count=$(echo "SELECT count(*) FROM test_instance WHERE test_run_id='$last_trid';" | tl_db_query | tr -d '[:space:]') || true
    if [ -n "$instance_count" ] && [ "$instance_count" -ge 15 ] 2>/dev/null; then
      SKIP_FIRST_TEST=true
      echo -e "${CYAN}Resuming: $instance_count test instances found, skipping test phase${NC}"
    else
      echo -e "${YELLOW}Resuming: last test run incomplete ($instance_count instances) — will re-test${NC}"
    fi
  fi
fi

if [ "$START_ITERATION" -gt "$MAX_ITERATIONS" ]; then
  echo -e "${GREEN}All $MAX_ITERATIONS iterations already completed.${NC}"
  exit 0
fi

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${MAGENTA}Autonomous Fix Loop${NC}"
echo -e "${DIM}─────────────────────────────────────────────────${NC}"
echo -e "  Session:        ${BOLD}$SESSION_NAME${NC}"
echo -e "  Max iterations: $MAX_ITERATIONS"
echo -e "  Start from:     $START_ITERATION"
echo -e "  Fix workers:    $NUM_WORKERS"
echo -e "  Test workers:   $TEST_WORKERS"
echo -e "  Skip 1st test:  $SKIP_FIRST_TEST"
echo -e "${DIM}─────────────────────────────────────────────────${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Main Loop
# ══════════════════════════════════════════════════════════════════════════════
for iteration in $(seq "$START_ITERATION" "$MAX_ITERATIONS"); do
  echo ""
  echo -e "${BOLD}${CYAN}═══ Iteration $iteration / $MAX_ITERATIONS ═══${NC}"

  # ── Phase 1: Get Test Results ──────────────────────────────────────────────
  if [ "$iteration" -eq "$START_ITERATION" ] && [ "$SKIP_FIRST_TEST" = true ]; then
    fl_log "Phase 1: Using latest test results from DB"
    test_run_id=$(fl_get_latest_test_run_id "$SESSION_NAME")
    if [ -z "$test_run_id" ]; then
      fl_log_error "No test results found for session '$SESSION_NAME'"
      exit 1
    fi
    fl_log "Using test_run_id: $test_run_id"
  else
    fl_log "Phase 1: Build & Test"

    if [ "$iteration" -eq "$START_ITERATION" ] && [ "$SKIP_BUILD" = true ]; then
      fl_log "Skipping build (--skip-build)"
      "$SCRIPT_DIR/test-runner.sh" "$SESSION_NAME" --skip-build --workers "$TEST_WORKERS" || true
    else
      "$SCRIPT_DIR/test-runner.sh" "$SESSION_NAME" --workers "$TEST_WORKERS" || true
    fi

    # Read test_run_id from output file
    local_trid_file="$SESSION_DIR/.fix-loop/last-test-run-id.txt"
    if [ -f "$local_trid_file" ]; then
      test_run_id=$(cat "$local_trid_file" | tr -d '[:space:]')
    else
      test_run_id=$(fl_get_latest_test_run_id "$SESSION_NAME")
    fi

    if [ -z "$test_run_id" ]; then
      fl_log_error "Could not determine test_run_id after test run"
      exit 1
    fi
    fl_log "test_run_id: $test_run_id"
  fi

  # ── Phase 2: Extract & Evaluate ───────────────────────────────────────────
  fl_log "Phase 2: Extracting metrics"
  metrics=$(fl_get_test_metrics "$SESSION_NAME" "$test_run_id")
  IFS='|' read -r pass_count fail_count total_count avg_score <<< "$metrics"

  fl_log "Results: $pass_count pass, $fail_count fail, $total_count total, avg score: $avg_score"

  # All pass → exit success
  if [ "${fail_count:-0}" -eq 0 ] && [ "${pass_count:-0}" -gt 0 ]; then
    fl_log_success "All tests pass! Exiting loop."
    break
  fi

  # Regression detection (compare with previous iteration)
  if [ "$iteration" -gt "$START_ITERATION" ] || [ "$SKIP_FIRST_TEST" = false ]; then
    fl_detect_regressions "$SESSION_NAME" "$test_run_id" "$WORK_DIR" "$iteration"
  fi

  # Stall detection
  stall_status=$(fl_check_stall "$HISTORY_FILE" "$iteration" "${pass_count:-0}" "${avg_score:-0}")
  if [ "$stall_status" = "stalled" ]; then
    fl_log_warn "Stall detected — no improvement over last 2 iterations"
    fl_log_warn "Exiting loop. Remaining failures may need manual intervention."
    break
  fi

  # ── Phase 3: Extract failures by cluster ──────────────────────────────────
  fl_log "Phase 3: Extracting failures by cluster"
  failures_raw="$WORK_DIR/failures-raw-iter${iteration}.json"
  failures_filtered="$WORK_DIR/failures-iter${iteration}.json"

  fl_extract_failures "$SESSION_NAME" "$test_run_id" "$failures_raw"
  fl_filter_unfixable "$failures_raw" "$UNFIXABLE_FILE" "$failures_filtered"

  # Count remaining failures
  remaining=$(python3 -c "
import json
d = json.load(open('$failures_filtered'))
total = sum(len(c.get('failures',[])) for c in d.get('clusters',{}).values())
clusters = list(d.get('clusters',{}).keys())
print(f'{total}|{\",\".join(clusters)}')
" 2>/dev/null) || true
  IFS='|' read -r remaining_count remaining_clusters <<< "$remaining"

  if [ "${remaining_count:-0}" -eq 0 ]; then
    fl_log_success "No fixable failures remaining"
    break
  fi
  fl_log "Failures to fix: $remaining_count across clusters: $remaining_clusters"

  # ── Phase 4: Synthesis ────────────────────────────────────────────────────
  fl_log "Phase 4: Running synthesis agent"
  synthesis_file="$WORK_DIR/synthesis-iter${iteration}.json"

  if ! fl_run_synthesis "$failures_filtered" "$PROJECT_ROOT" "$synthesis_file"; then
    fl_log_error "Synthesis failed — exiting loop (code from prior iterations is committed)"
    break
  fi

  # Count fix specs
  spec_count=$(python3 -c "
import json
d = json.load(open('$synthesis_file'))
specs = d.get('fix_specs', [])
fixable = [s for s in specs if not s.get('unfixable', False)]
unfixable = [s for s in specs if s.get('unfixable', False)]
print(f'{len(fixable)}|{len(unfixable)}')
" 2>/dev/null) || true
  IFS='|' read -r fixable_specs unfixable_specs <<< "$spec_count"
  fl_log "Synthesis: $fixable_specs fixable specs, $unfixable_specs unfixable"

  # Record newly unfixable items
  if [ "${unfixable_specs:-0}" -gt 0 ]; then
    python3 << UPDATE_UNFIXABLE_EOF
import json

synthesis = json.load(open('$synthesis_file'))
unfixable = json.load(open('$UNFIXABLE_FILE'))

existing = set((i['journey_id'], i['mode']) for i in unfixable.get('items', []) if 'journey_id' in i)

for spec in synthesis.get('fix_specs', []):
    if spec.get('unfixable', False):
        cluster = spec.get('cluster', '')
        reason = spec.get('unfixable_reason', 'unknown')
        # Mark all journeys in this cluster as unfixable
        from collections import defaultdict
        cluster_journeys = {
            'organizations': ['J-001','J-002','J-003','J-013'],
            'connections': ['J-004','J-005'],
            'sharing': ['J-006','J-007','J-008'],
            'deals': ['J-009','J-010','J-011'],
            'invoices': ['J-012'],
        }
        for jid in cluster_journeys.get(cluster, []):
            for mode in ['explicit', 'general']:
                if (jid, mode) not in existing:
                    unfixable['items'].append({
                        'journey_id': jid,
                        'mode': mode,
                        'cluster': cluster,
                        'reason': reason,
                        'iteration': $iteration,
                    })
                    existing.add((jid, mode))

with open('$UNFIXABLE_FILE', 'w') as f:
    json.dump(unfixable, f, indent=2)
UPDATE_UNFIXABLE_EOF
  fi

  # ── Phase 5: Interrogation (skipped for now — future enhancement) ────────
  # For failures with needs_interrogation=true, we'd resume the test agent's
  # Claude session and ask targeted questions. Omitted in v1.

  # ── Phase 5.5: Data Fixes ──────────────────────────────────────────────
  data_fixable=$(fl_has_data_fixable_specs "$synthesis_file")
  if [ "$data_fixable" = "yes" ]; then
    fl_log "Phase 5.5: Applying data fixes (RBAC grants, migrations, seed data)"
    fl_apply_data_fixes "$SESSION_DIR" "$PROJECT_ROOT" "$synthesis_file"
  fi

  # ── Phase 6: Parallel Fix Agents ─────────────────────────────────────────
  fl_log "Phase 6: Spawning fix agents"

  # Extract per-cluster fix specs and launch agents
  clusters_to_fix=$(python3 -c "
import json
d = json.load(open('$synthesis_file'))
specs = [s for s in d.get('fix_specs', []) if not s.get('unfixable', False)]
for s in specs:
    print(s['cluster'])
" 2>/dev/null) || true

  agent_pids=()
  agent_clusters=()

  while IFS= read -r cluster; do
    [ -z "$cluster" ] && continue

    # Extract this cluster's fix spec
    fix_spec_file="$WORK_DIR/fix-spec-${cluster}-iter${iteration}.json"
    python3 -c "
import json
d = json.load(open('$synthesis_file'))
for s in d.get('fix_specs', []):
    if s['cluster'] == '$cluster':
        print(json.dumps(s, indent=2))
        break
" > "$fix_spec_file" 2>/dev/null || true

    if [ ! -s "$fix_spec_file" ]; then
      fl_log_warn "No fix spec for cluster '$cluster' — skipping"
      continue
    fi

    # Get owned and shared files
    owned_files=$(fc_get_owned_files "$cluster")
    shared_files=$(fc_get_shared_files)
    fix_spec_json=$(cat "$fix_spec_file")

    result_file="$WORK_DIR/fix-result-${cluster}.json"
    agent_log="$WORK_DIR/fix-log-${cluster}-iter${iteration}.txt"

    fl_log "  Launching fix agent: $cluster"

    fl_run_fix_agent "$cluster" "$fix_spec_json" "$owned_files" "$shared_files" \
      "$PROJECT_ROOT" "$result_file" "$agent_log" &
    agent_pids+=($!)
    agent_clusters+=("$cluster")

  done <<< "$clusters_to_fix"

  # Wait for all fix agents
  if [ ${#agent_pids[@]} -gt 0 ]; then
    fl_log "Waiting for ${#agent_pids[@]} fix agents..."
    for i in "${!agent_pids[@]}"; do
      wait "${agent_pids[$i]}" || true
      fl_log "  ${agent_clusters[$i]}: done"
    done
  else
    fl_log_warn "No fix agents launched — nothing to fix"
    break
  fi

  # Validate fix results
  for cluster in "${agent_clusters[@]}"; do
    result_file="$WORK_DIR/fix-result-${cluster}.json"
    if [ -f "$result_file" ] && [ -s "$result_file" ]; then
      if python3 -c "import json; json.load(open('$result_file'))" 2>/dev/null; then
        local_fixes=$(python3 -c "import json; d=json.load(open('$result_file')); print(len(d.get('fixes_applied',[])))" 2>/dev/null) || true
        fl_log "  $cluster: ${local_fixes:-0} fixes applied"
      else
        fl_log_warn "  $cluster: invalid JSON output (agent may have crashed)"
      fi
    else
      fl_log_warn "  $cluster: no output (agent may have crashed)"
    fi
  done

  # ── Phase 7: Merge Shared Files ──────────────────────────────────────────
  fl_log "Phase 7: Merging shared file changes"
  merge_result="$WORK_DIR/merge-result-iter${iteration}.json"

  # Check if any agents reported shared file changes
  has_shared_changes=$(python3 -c "
import json, glob, os
found = False
for f in glob.glob(os.path.join('$WORK_DIR', 'fix-result-*.json')):
    try:
        d = json.load(open(f))
        if d.get('shared_file_changes_needed'):
            found = True
            break
    except:
        pass
print('yes' if found else 'no')
")

  if [ "$has_shared_changes" = "yes" ]; then
    fl_run_merge_agent "$WORK_DIR" "$PROJECT_ROOT" "$merge_result"
    fl_log_success "Merge complete"
  else
    fl_log "No shared file changes to merge"
    echo '{"merged":[],"conflicts":[]}' > "$merge_result"
  fi

  # ── Phase 7.5: Validate Changes ─────────────────────────────────────────
  fl_log "Phase 7.5: Validating syntax"
  fl_validate_changes "$PROJECT_ROOT" || fl_log_warn "Some files had syntax errors and were reverted"

  # ── Phase 8: Commit ──────────────────────────────────────────────────────
  fl_log "Phase 8: Committing changes"

  cd "$PROJECT_ROOT"
  # Only stage files that were actually modified (not all untracked files)
  if git diff --quiet; then
    fl_log "No changes to commit"
  else
    # Stage only modified tracked files (frontend + backend, not .claude/)
    git add frontend/ backend/ 2>/dev/null || true

    if git diff --cached --quiet; then
      fl_log "No staged changes to commit"
    else
      commit_msg="$(cat <<COMMIT_MSG_EOF
fix-loop iteration ${iteration}: fix ${remaining_clusters}

Clusters: ${remaining_clusters}
Iteration: ${iteration}/${MAX_ITERATIONS}
Failures addressed: ${remaining_count}
Pass rate before: ${pass_count}/${total_count}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
COMMIT_MSG_EOF
)"
      git commit -m "$commit_msg" || true
      fl_log_success "Committed iteration $iteration changes"
    fi
  fi

  # Write iteration completion marker (for --resume)
  echo "$iteration" > "$ITER_MARKER"

  # ── Phase 9: Loop ────────────────────────────────────────────────────────
  fl_log "Iteration $iteration complete — looping to re-test"

  # Reset skip flags for subsequent iterations
  SKIP_FIRST_TEST=false
  SKIP_BUILD=false

done

# ══════════════════════════════════════════════════════════════════════════════
# Final Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${MAGENTA}Fix Loop Complete${NC}"
echo -e "${DIM}─────────────────────────────────────────────────${NC}"

# Get final metrics
if [ -n "${test_run_id:-}" ]; then
  final_metrics=$(fl_get_test_metrics "$SESSION_NAME" "$test_run_id")
  IFS='|' read -r final_pass final_fail final_total final_avg <<< "$final_metrics"
  echo -e "  Final:  $final_pass pass, $final_fail fail (${final_total} total, avg: ${final_avg})"
fi

# Show iteration history
if [ -f "$HISTORY_FILE" ]; then
  echo ""
  echo -e "  ${DIM}Iteration history:${NC}"
  while IFS='|' read -r iter pc as; do
    echo -e "    Iter ${iter}: pass=${pc}, avg_score=${as}"
  done < "$HISTORY_FILE"
fi

# Show unfixable items
unfixable_count=$(python3 -c "import json; print(len(json.load(open('$UNFIXABLE_FILE')).get('items',[])))" 2>/dev/null) || true
if [ "${unfixable_count:-0}" -gt 0 ]; then
  echo ""
  echo -e "  ${YELLOW}Unfixable items: $unfixable_count${NC} (see $WORK_DIR/unfixable.json)"
fi

echo -e "${DIM}─────────────────────────────────────────────────${NC}"
