#!/bin/bash
# test-runner.sh — Standalone test runner for journey tests
#
# Runs Build & Deploy, Persona check, and Journey Tests independently
# of the full 20-step feature_interrogate.sh pipeline.
#
# Usage:
#   ./test-runner.sh [session-name] [flags]
#
# Flags:
#   --retry                 Retry all failed journeys from latest test_run_id
#   --journey J-001         Retry all personas that failed on J-001
#   --mode explicit|general Filter retry to one test mode (use with --retry)
#   --workers N             Worker count (default: 3)
#   --skip-build            Skip build.sh deployment
#   --regen-personas        Force regenerate personas (runs pipeline Step 19)
#   --help                  Show usage
#
# If session-name is omitted, auto-detect latest session in .claude/RESEARCH/
# that has personas-generated.txt.

set -euo pipefail

# ── Setup ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source shared test library
source "$SCRIPT_DIR/lib/test-lib.sh"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ── CLI Parsing ───────────────────────────────────────────────────────────────
SESSION_NAME=""
RETRY_MODE=false
RETRY_JOURNEY=""
RETRY_MODE_FILTER=""
NUM_WORKERS=3
SKIP_BUILD=false
REGEN_PERSONAS=false

show_usage() {
  cat << 'USAGE_EOF'
Usage: test-runner.sh [session-name] [flags]

Standalone test runner for journey tests (Steps 18-20 of the pipeline).

Arguments:
  session-name            Session in .claude/RESEARCH/ (auto-detected if omitted)

Flags:
  --retry                 Retry all failed journeys from latest test_run_id
  --journey J-001         Retry personas that failed on a specific journey
  --mode explicit|general Filter retry to one test mode
  --workers N             Worker count (default: 3)
  --skip-build            Skip build.sh deployment
  --regen-personas        Force regenerate personas (runs pipeline Step 19)
  --help                  Show this usage

Examples:
  # Run all tests for a session (with build)
  ./test-runner.sh task-3-20260210-214345

  # Skip build, just run tests
  ./test-runner.sh task-3-20260210-214345 --skip-build

  # Retry all failures from latest run
  ./test-runner.sh task-3-20260210-214345 --retry --skip-build

  # Retry only explicit failures on J-001
  ./test-runner.sh --retry --journey J-001 --mode explicit --skip-build

  # Auto-detect session, retry failures
  ./test-runner.sh --retry --skip-build
USAGE_EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_usage
      exit 0
      ;;
    --retry)
      RETRY_MODE=true
      shift
      ;;
    --journey)
      if [ -z "${2:-}" ]; then
        echo "Error: --journey requires a journey ID (e.g., J-001)" >&2
        exit 1
      fi
      RETRY_JOURNEY="$2"
      shift 2
      ;;
    --mode)
      if [ -z "${2:-}" ] || [[ ! "$2" =~ ^(explicit|general)$ ]]; then
        echo "Error: --mode must be 'explicit' or 'general'" >&2
        exit 1
      fi
      RETRY_MODE_FILTER="$2"
      shift 2
      ;;
    --workers)
      if [ -z "${2:-}" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --workers requires a number" >&2
        exit 1
      fi
      NUM_WORKERS="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --regen-personas)
      REGEN_PERSONAS=true
      shift
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      show_usage
      exit 1
      ;;
    *)
      if [ -z "$SESSION_NAME" ]; then
        SESSION_NAME="$1"
      else
        echo "Error: unexpected argument '$1'" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# ── Session detection ─────────────────────────────────────────────────────────
auto_detect_session() {
  local research_dir="$PROJECT_ROOT/.claude/RESEARCH"
  if [ ! -d "$research_dir" ]; then
    echo "" && return
  fi
  # Find latest session directory with personas-generated.txt
  local latest=""
  local latest_time=0
  for dir in "$research_dir"/*/; do
    [ ! -d "$dir" ] && continue
    if [ -f "$dir/personas-generated.txt" ] || [ -f "$dir/personas.json" ]; then
      local mtime
      mtime=$(stat -c %Y "$dir" 2>/dev/null || stat -f %m "$dir" 2>/dev/null || echo 0)
      if [ "$mtime" -gt "$latest_time" ]; then
        latest_time="$mtime"
        latest=$(basename "$dir")
      fi
    fi
  done
  echo "$latest"
}

if [ -z "$SESSION_NAME" ]; then
  SESSION_NAME=$(auto_detect_session)
  if [ -z "$SESSION_NAME" ]; then
    echo -e "${RED}No session specified and none auto-detected.${NC}" >&2
    echo "Available sessions:" >&2
    ls -1 "$PROJECT_ROOT/.claude/RESEARCH/" 2>/dev/null | while read -r d; do
      if [ -f "$PROJECT_ROOT/.claude/RESEARCH/$d/personas.json" ]; then
        echo "  $d (has personas)" >&2
      else
        echo "  $d" >&2
      fi
    done
    exit 1
  fi
  echo -e "${CYAN}Auto-detected session:${NC} $SESSION_NAME"
fi

SESSION_DIR="$PROJECT_ROOT/.claude/RESEARCH/$SESSION_NAME"

if [ ! -d "$SESSION_DIR" ]; then
  echo -e "${RED}Session directory not found: $SESSION_DIR${NC}" >&2
  exit 1
fi

# ── Load DB config ────────────────────────────────────────────────────────────
tl_load_db_config

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}Standalone Test Runner${NC}"
echo -e "${DIM}─────────────────────────────────────────────────${NC}"
echo -e "  Session:  ${BOLD}$SESSION_NAME${NC}"
echo -e "  Workers:  $NUM_WORKERS"
echo -e "  Mode:     $([ "$RETRY_MODE" = true ] && echo "RETRY" || echo "NORMAL")"
[ -n "$RETRY_JOURNEY" ] && echo -e "  Journey:  $RETRY_JOURNEY"
[ -n "$RETRY_MODE_FILTER" ] && echo -e "  Filter:   $RETRY_MODE_FILTER only"
echo -e "${DIM}─────────────────────────────────────────────────${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Phase 1: Build & Deploy
# ══════════════════════════════════════════════════════════════════════════════
if [ "$SKIP_BUILD" = true ]; then
  tl_log "Phase 1: Build & Deploy — SKIPPED (--skip-build)"
else
  tl_log "Phase 1: Build & Deploy"
  if [ ! -x "$PROJECT_ROOT/build.sh" ]; then
    tl_log_error "build.sh not found or not executable at $PROJECT_ROOT/build.sh"
    exit 1
  fi
  (cd "$PROJECT_ROOT" && ./build.sh)
  tl_log_success "Build & deploy complete"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 2: Persona Check
# ══════════════════════════════════════════════════════════════════════════════
tl_log "Phase 2: Persona check"
local_personas="$SESSION_DIR/personas.json"

if [ "$REGEN_PERSONAS" = true ]; then
  tl_log_warn "Regenerating personas (--regen-personas)..."
  tl_log "Persona generation is part of the pipeline — running Step 19 via pipeline."
  if [ -x "$SCRIPT_DIR/feature_interrogate.sh" ]; then
    (cd "$PROJECT_ROOT" && "$SCRIPT_DIR/feature_interrogate.sh" --start-from-step 19 "$SESSION_NAME")
  else
    tl_log_error "feature_interrogate.sh not found. Generate personas manually."
    exit 1
  fi
fi

if [ ! -f "$local_personas" ]; then
  tl_log_error "personas.json not found at $local_personas"
  tl_log_error "Run the pipeline through Step 19 first, or use --regen-personas"
  exit 1
fi

persona_count=$(python3 -c "
import json
data = json.load(open('$local_personas'))
personas = data.get('personas', data if isinstance(data, list) else [])
print(len(personas))
" 2>/dev/null) || true

tl_log_success "Found ${persona_count:-0} personas in personas.json"

# ══════════════════════════════════════════════════════════════════════════════
# Phase 3: Journey Tests
# ══════════════════════════════════════════════════════════════════════════════
tl_log "Phase 3: Journey Tests"

# Run prerequisites check
if ! tl_check_test_prerequisites "$SESSION_DIR" "$SESSION_NAME" "$PROJECT_ROOT"; then
  tl_log_error "Prerequisites check failed"
  exit 1
fi

personas_json="$local_personas"
artifacts_dir="$SESSION_DIR/test-artifacts"
base_url="http://ubuntu.desmana-truck.ts.net:32081"
batch_dir="$SESSION_DIR/.worker-batches"
mkdir -p "$artifacts_dir" "$batch_dir" 2>/dev/null || true

# ── Build test matrix ─────────────────────────────────────────────────────────
if [ "$RETRY_MODE" = true ]; then
  # ── Retry mode: query DB for failures ────────────────────────────────────
  test_run_id="retry-$(date +%Y%m%d-%H%M%S)"
  tl_log "Retry mode — querying DB for latest test_run_id..."

  latest_run_id=$(echo "SELECT test_run_id FROM test_instance WHERE session_name='$SESSION_NAME' ORDER BY completed_at DESC LIMIT 1;" | tl_db_query) || true
  latest_run_id=$(echo "$latest_run_id" | tr -d '[:space:]')

  if [ -z "$latest_run_id" ]; then
    tl_log_error "No previous test runs found for session '$SESSION_NAME'"
    exit 1
  fi
  tl_log "Latest test_run_id: $latest_run_id"

  # Build SQL query with composable filters
  retry_sql="SELECT persona_id || '|' || COALESCE(journey_id, '') || '|' || mode FROM test_instance WHERE session_name='$SESSION_NAME' AND test_run_id='$latest_run_id' AND overall_status IN ('fail', 'error', 'partial')"

  if [ -n "$RETRY_MODE_FILTER" ]; then
    retry_sql="$retry_sql AND mode='$RETRY_MODE_FILTER'"
  fi
  if [ -n "$RETRY_JOURNEY" ]; then
    retry_sql="$retry_sql AND journey_id='$RETRY_JOURNEY'"
  fi
  retry_sql="$retry_sql ORDER BY persona_id, journey_id;"

  failed_combos=$(echo "$retry_sql" | tl_db_query) || true

  if [ -z "$failed_combos" ]; then
    tl_log_success "No failures found to retry! All tests passed in run $latest_run_id"
    exit 0
  fi

  # Split into explicit and general maps
  explicit_map=""
  general_map=""
  while IFS='|' read -r pid jid mode; do
    [ -z "$pid" ] && continue
    if [ "$mode" = "explicit" ]; then
      explicit_map+="${pid}|${jid}"$'\n'
    elif [ "$mode" = "general" ]; then
      general_map+="${pid}|${jid}"$'\n'
    fi
  done <<< "$failed_combos"
  # Trim trailing newlines
  explicit_map=$(echo -n "$explicit_map" | sed '/^$/d')
  general_map=$(echo -n "$general_map" | sed '/^$/d')

  explicit_count=0
  general_count=0
  [ -n "$explicit_map" ] && explicit_count=$(echo "$explicit_map" | wc -l | tr -d ' ')
  [ -n "$general_map" ] && general_count=$(echo "$general_map" | wc -l | tr -d ' ')
  tl_log "Retrying: $explicit_count explicit, $general_count general failures"

else
  # ── Normal mode: build full matrix ───────────────────────────────────────
  test_run_id="standalone-$(date +%Y%m%d-%H%M%S)"
  persona_journey_map=$(tl_build_test_matrix "$personas_json")

  if [ -z "$persona_journey_map" ]; then
    tl_log_error "Could not extract persona-journey mapping from personas.json"
    exit 1
  fi

  explicit_map="$persona_journey_map"
  general_map="$persona_journey_map"

  total_tests=$(echo "$persona_journey_map" | wc -l | tr -d ' ')
  tl_log "Test matrix: $total_tests persona-journey pairs (explicit + general)"
fi

tl_log "test_run_id: $test_run_id"

# ── Create MCP configs ─────────────────────────────────────────────────────
tl_create_mcp_configs "$batch_dir" "$NUM_WORKERS"

# ── Run explicit tests ─────────────────────────────────────────────────────
explicit_pass=0 explicit_fail=0 explicit_error=0

if [ -n "$explicit_map" ]; then
  echo ""
  tl_log "Running explicit journey tests ($NUM_WORKERS workers)..."

  tl_partition_batches "$batch_dir" "$NUM_WORKERS" "explicit" "$explicit_map"

  worker_pids=()
  for w in $(seq 1 "$NUM_WORKERS"); do
    if [ ! -s "$batch_dir/explicit-batch-${w}.txt" ]; then
      continue
    fi
    batch_count=$(wc -l < "$batch_dir/explicit-batch-${w}.txt" | tr -d ' ')
    tl_log "  Worker $w: $batch_count tests"

    tl_run_explicit_worker "$w" \
      "$batch_dir/explicit-batch-${w}.txt" \
      "$batch_dir/mcp-worker-${w}.json" \
      "$SESSION_DIR" \
      "$artifacts_dir" \
      "$personas_json" \
      "$SESSION_NAME" \
      "$test_run_id" \
      "$base_url" \
      "$TL_DB_NAMESPACE" \
      "$TL_DB_POD" \
      "$TL_DB_USER" \
      "$TL_DB_NAME" \
      "$TL_DB_PASSWORD" \
      "$batch_dir/explicit-result-${w}.txt" \
      "$batch_dir/explicit-log-${w}.txt" &
    worker_pids+=($!)
  done

  for pid in "${worker_pids[@]}"; do
    wait "$pid" || true
  done

  explicit_agg=$(tl_aggregate_explicit_results "$batch_dir" "$NUM_WORKERS")
  IFS='|' read -r explicit_pass explicit_fail explicit_error <<< "$explicit_agg"
  tl_stream_worker_logs "$batch_dir" "$NUM_WORKERS" "explicit"
  tl_log_success "Explicit: $explicit_pass pass, $explicit_fail fail, $explicit_error error"
else
  tl_log "No explicit tests to run"
fi

# ── Run general tests ──────────────────────────────────────────────────────
general_pass=0 general_fail=0 general_error=0 general_scores_sum=0 general_scores_count=0

if [ -n "$general_map" ]; then
  echo ""
  tl_log "Running general goal tests ($NUM_WORKERS workers)..."

  tl_partition_batches "$batch_dir" "$NUM_WORKERS" "general" "$general_map"

  worker_pids=()
  for w in $(seq 1 "$NUM_WORKERS"); do
    if [ ! -s "$batch_dir/general-batch-${w}.txt" ]; then
      continue
    fi
    batch_count=$(wc -l < "$batch_dir/general-batch-${w}.txt" | tr -d ' ')
    tl_log "  Worker $w: $batch_count tests"

    tl_run_general_worker "$w" \
      "$batch_dir/general-batch-${w}.txt" \
      "$batch_dir/mcp-worker-${w}.json" \
      "$SESSION_DIR" \
      "$artifacts_dir" \
      "$personas_json" \
      "$SESSION_NAME" \
      "$test_run_id" \
      "$base_url" \
      "$TL_DB_NAMESPACE" \
      "$TL_DB_POD" \
      "$TL_DB_USER" \
      "$TL_DB_NAME" \
      "$TL_DB_PASSWORD" \
      "$batch_dir/general-result-${w}.txt" \
      "$batch_dir/general-log-${w}.txt" &
    worker_pids+=($!)
  done

  for pid in "${worker_pids[@]}"; do
    wait "$pid" || true
  done

  general_agg=$(tl_aggregate_general_results "$batch_dir" "$NUM_WORKERS")
  IFS='|' read -r general_pass general_fail general_error general_scores_sum general_scores_count <<< "$general_agg"
  tl_stream_worker_logs "$batch_dir" "$NUM_WORKERS" "general"

  avg_score=0
  if [ "${general_scores_count:-0}" -gt 0 ]; then
    avg_score=$((general_scores_sum / general_scores_count))
  fi
  tl_log_success "General: $general_pass pass, $general_fail fail, $general_error error (avg score: $avg_score/100)"
else
  tl_log "No general tests to run"
  avg_score=0
fi

# ── Summary ───────────────────────────────────────────────────────────────────
total_pass=$((explicit_pass + general_pass))
total_fail=$((explicit_fail + general_fail))
total_error=$((explicit_error + general_error))

# Validate DB persistence
expected_db_rows=$((total_pass + total_fail))
actual_db_rows=$(echo "SELECT count(*) FROM test_instance WHERE test_run_id='$test_run_id';" | tl_db_query) || true
actual_db_rows=$(echo "$actual_db_rows" | tr -d '[:space:]')

echo ""
echo -e "${BOLD}${CYAN}Results${NC}"
echo -e "${DIM}─────────────────────────────────────────────────${NC}"
echo -e "  test_run_id: ${BOLD}$test_run_id${NC}"
echo -e "  Explicit:    $explicit_pass pass, $explicit_fail fail, $explicit_error error"
echo -e "  General:     $general_pass pass, $general_fail fail, $general_error error (avg: ${avg_score:-0}/100)"
echo -e "  Total:       $total_pass pass, $total_fail fail, $total_error error"
echo -e "  DB rows:     ${actual_db_rows:-0} (expected $expected_db_rows)"

if [ "${actual_db_rows:-0}" -lt "$expected_db_rows" ]; then
  echo -e "  ${RED}DB DATA LOSS: check worker logs in $batch_dir/${NC}"
fi

echo -e "${DIM}─────────────────────────────────────────────────${NC}"

# Suggest retry if there were failures
if [ "$total_fail" -gt 0 ] || [ "$total_error" -gt 0 ]; then
  echo ""
  echo -e "${YELLOW}To retry failures:${NC}"
  echo "  $0 $SESSION_NAME --retry --skip-build"
  if [ "$explicit_fail" -gt 0 ] || [ "$explicit_error" -gt 0 ]; then
    echo "  $0 $SESSION_NAME --retry --mode explicit --skip-build"
  fi
  if [ "$general_fail" -gt 0 ] || [ "$general_error" -gt 0 ]; then
    echo "  $0 $SESSION_NAME --retry --mode general --skip-build"
  fi
fi

# Exit with non-zero if any failures
if [ "$total_fail" -gt 0 ] || [ "$total_error" -gt 0 ]; then
  exit 1
fi

exit 0
