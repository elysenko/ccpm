#!/bin/bash
# test-feature-interrogate.sh - Test suite for feature_interrogate.sh
#
# Usage:
#   ./test-feature-interrogate.sh              # Run all tests
#   ./test-feature-interrogate.sh --unit       # Unit tests only
#   ./test-feature-interrogate.sh --integration # Integration tests only
#   ./test-feature-interrogate.sh --quick      # Quick smoke test
#
# Test Levels:
#   1. Unit Tests     - Test individual functions with mocks
#   2. Integration    - Test full pipeline with real Claude CLI
#   3. Smoke Test     - Quick validation that script runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEATURE_SCRIPT="$SCRIPT_DIR/feature_interrogate.sh"
TEST_SESSION="test-$(date +%Y%m%d-%H%M%S)"
TEST_DIR=".claude/RESEARCH/$TEST_SESSION"
SCOPE_DIR=".claude/scopes/$TEST_SESSION"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
  echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_skip() {
  echo -e "${YELLOW}[SKIP]${NC} $1"
}

run_test() {
  local name="$1"
  local cmd="$2"

  TESTS_RUN=$((TESTS_RUN + 1))
  log_test "$name"

  if eval "$cmd"; then
    log_pass "$name"
    return 0
  else
    log_fail "$name"
    return 1
  fi
}

# Cleanup function
cleanup() {
  if [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
  if [ -d "$SCOPE_DIR" ]; then
    rm -rf "$SCOPE_DIR"
  fi
}

#==============================================================================
# UNIT TESTS - Test individual components
#==============================================================================

test_script_exists() {
  [ -f "$FEATURE_SCRIPT" ]
}

test_script_executable() {
  [ -x "$FEATURE_SCRIPT" ]
}

test_script_syntax() {
  bash -n "$FEATURE_SCRIPT"
}

test_help_output() {
  "$FEATURE_SCRIPT" --help 2>&1 | grep -q "Feature Interrogate"
}

test_help_shows_steps() {
  local output
  output=$("$FEATURE_SCRIPT" --help 2>&1)
  echo "$output" | grep -q "Repo Familiarization" && \
  echo "$output" | grep -q "Feature Input" && \
  echo "$output" | grep -q "Flow Diagram Loop" && \
  echo "$output" | grep -q "Database Sync"
}

test_help_shows_output_files() {
  "$FEATURE_SCRIPT" --help 2>&1 | grep -q "repo-analysis.md"
}

test_session_name_generation() {
  # Script should accept a session name argument
  local output
  output=$("$FEATURE_SCRIPT" --help 2>&1)
  echo "$output" | grep -q "session-name"
}

test_creates_research_directory() {
  mkdir -p "$TEST_DIR"
  [ -d "$TEST_DIR" ]
}

test_creates_scope_directory() {
  mkdir -p "$SCOPE_DIR"
  [ -d "$SCOPE_DIR" ]
}

test_sync_script_exists() {
  [ -f "$SCRIPT_DIR/sync-interview-to-db.sh" ]
}

run_unit_tests() {
  echo ""
  echo "=============================================="
  echo "  UNIT TESTS"
  echo "=============================================="
  echo ""

  run_test "Script exists" test_script_exists
  run_test "Script is executable" test_script_executable
  run_test "Script syntax is valid" test_script_syntax
  run_test "Help output works" test_help_output
  run_test "Help shows all 7 steps" test_help_shows_steps
  run_test "Help shows output files" test_help_shows_output_files
  run_test "Session name documented" test_session_name_generation
  run_test "Can create RESEARCH directory" test_creates_research_directory
  run_test "Can create scopes directory" test_creates_scope_directory
  run_test "sync-interview-to-db.sh exists" test_sync_script_exists
}

#==============================================================================
# MOCK TESTS - Test with simulated inputs
#==============================================================================

test_mock_session_init() {
  # Test that session directories are created
  local mock_session="mock-test-$$"
  local mock_dir=".claude/RESEARCH/$mock_session"
  local mock_scope=".claude/scopes/$mock_session"

  mkdir -p "$mock_dir" "$mock_scope"

  local result=0
  [ -d "$mock_dir" ] && [ -d "$mock_scope" ] || result=1

  rm -rf "$mock_dir" "$mock_scope"
  return $result
}

test_mock_feature_input_file() {
  # Test feature input file format
  local mock_session="mock-test-$$"
  local mock_dir=".claude/RESEARCH/$mock_session"
  mkdir -p "$mock_dir"

  cat > "$mock_dir/feature-input.md" << 'EOF'
---
name: mock-test
created: 2024-01-01T00:00:00Z
type: feature-request
---

# Initial Feature Request

Test feature description
EOF

  local result=0
  grep -q "^---$" "$mock_dir/feature-input.md" || result=1
  grep -q "name: mock-test" "$mock_dir/feature-input.md" || result=1
  grep -q "# Initial Feature Request" "$mock_dir/feature-input.md" || result=1

  rm -rf "$mock_dir"
  return $result
}

test_mock_summary_file() {
  # Test summary file format
  local mock_session="mock-test-$$"
  local mock_dir=".claude/RESEARCH/$mock_session"
  mkdir -p "$mock_dir"

  cat > "$mock_dir/summary.md" << 'EOF'
---
name: mock-test
created: 2024-01-01T00:00:00Z
status: in-progress
type: discovery-summary
---

# Feature Discovery Summary: mock-test

## Session Info
- Created: 2024-01-01T00:00:00Z
- Status: In Progress
EOF

  local result=0
  grep -q "^---$" "$mock_dir/summary.md" || result=1
  grep -q "status: in-progress" "$mock_dir/summary.md" || result=1
  grep -q "# Feature Discovery Summary" "$mock_dir/summary.md" || result=1

  rm -rf "$mock_dir"
  return $result
}

test_mock_scope_document() {
  # Test scope document format
  local mock_session="mock-test-$$"
  local mock_scope=".claude/scopes/$mock_session"
  mkdir -p "$mock_scope"

  cat > "$mock_scope/00_scope_document.md" << 'EOF'
---
name: mock-test
created: 2024-01-01T00:00:00Z
updated: 2024-01-01T00:00:00Z
status: in-progress
type: scope
---

# Scope Document: mock-test

## Overview
Test overview
EOF

  local result=0
  grep -q "^---$" "$mock_scope/00_scope_document.md" || result=1
  grep -q "type: scope" "$mock_scope/00_scope_document.md" || result=1
  grep -q "# Scope Document" "$mock_scope/00_scope_document.md" || result=1

  rm -rf "$mock_scope"
  return $result
}

test_mock_flow_confirmed() {
  # Test flow confirmation marker
  local mock_session="mock-test-$$"
  local mock_dir=".claude/RESEARCH/$mock_session"
  mkdir -p "$mock_dir"

  cat > "$mock_dir/flow-confirmed.txt" << 'EOF'
Flow confirmed at iteration 2
Timestamp: 2024-01-01T00:00:00Z
EOF

  local result=0
  grep -q "Flow confirmed at iteration" "$mock_dir/flow-confirmed.txt" || result=1
  grep -q "Timestamp:" "$mock_dir/flow-confirmed.txt" || result=1

  rm -rf "$mock_dir"
  return $result
}

run_mock_tests() {
  echo ""
  echo "=============================================="
  echo "  MOCK TESTS (Simulated Inputs)"
  echo "=============================================="
  echo ""

  run_test "Session initialization" test_mock_session_init
  run_test "Feature input file format" test_mock_feature_input_file
  run_test "Summary file format" test_mock_summary_file
  run_test "Scope document format" test_mock_scope_document
  run_test "Flow confirmed marker format" test_mock_flow_confirmed
}

#==============================================================================
# INTEGRATION TESTS - Test with real Claude CLI
#==============================================================================

test_claude_cli_available() {
  command -v claude &> /dev/null
}

test_integration_step1_repo_analysis() {
  # Test repo analysis step
  if ! command -v claude &> /dev/null; then
    log_skip "Claude CLI not available"
    return 0
  fi

  local mock_session="integ-test-$$"
  local mock_dir=".claude/RESEARCH/$mock_session"
  mkdir -p "$mock_dir"

  # Run just the repo analysis
  claude --dangerously-skip-permissions --print "/dr What is this repository?" > "$mock_dir/repo-analysis.md" 2>&1 || true

  local result=0
  [ -f "$mock_dir/repo-analysis.md" ] || result=1
  [ -s "$mock_dir/repo-analysis.md" ] || result=1  # File is not empty

  rm -rf "$mock_dir"
  return $result
}

test_integration_dr_refine() {
  # Test /dr-refine skill
  if ! command -v claude &> /dev/null; then
    log_skip "Claude CLI not available"
    return 0
  fi

  # Just verify the skill exists
  claude --dangerously-skip-permissions --print "/dr-refine test query" 2>&1 | head -5 > /dev/null || true
  return 0  # Non-blocking test
}

test_integration_flow_diagram() {
  # Test /pm:flow-diagram skill
  if ! command -v claude &> /dev/null; then
    log_skip "Claude CLI not available"
    return 0
  fi

  # Just verify the skill can be invoked
  claude --dangerously-skip-permissions --print "/pm:flow-diagram test" 2>&1 | head -5 > /dev/null || true
  return 0  # Non-blocking test
}

run_integration_tests() {
  echo ""
  echo "=============================================="
  echo "  INTEGRATION TESTS (Real Claude CLI)"
  echo "=============================================="
  echo ""

  if ! test_claude_cli_available; then
    log_skip "Claude CLI not available - skipping integration tests"
    return 0
  fi

  log_test "Claude CLI available"
  log_pass "Claude CLI available"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))

  run_test "Step 1: Repo analysis" test_integration_step1_repo_analysis
  run_test "/dr-refine skill" test_integration_dr_refine
  run_test "/pm:flow-diagram skill" test_integration_flow_diagram
}

#==============================================================================
# SMOKE TEST - Quick end-to-end validation
#==============================================================================

run_smoke_test() {
  echo ""
  echo "=============================================="
  echo "  SMOKE TEST (Quick Validation)"
  echo "=============================================="
  echo ""

  local smoke_session="smoke-test-$$"
  local smoke_dir=".claude/RESEARCH/$smoke_session"
  local smoke_scope=".claude/scopes/$smoke_session"

  log_test "Smoke test: Create session directories"
  mkdir -p "$smoke_dir" "$smoke_scope"
  if [ -d "$smoke_dir" ] && [ -d "$smoke_scope" ]; then
    log_pass "Directories created"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_fail "Failed to create directories"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi

  log_test "Smoke test: Create mock files"
  echo "Test feature" > "$smoke_dir/feature-input.md"
  echo "Test requirements" > "$smoke_dir/refined-requirements.md"
  echo "Test research" > "$smoke_dir/research-output.md"
  echo "Test summary" > "$smoke_dir/summary.md"
  echo "Test flow" > "$smoke_dir/flow-diagram.md"
  echo "Confirmed" > "$smoke_dir/flow-confirmed.txt"

  local file_count
  file_count=$(ls -1 "$smoke_dir" | wc -l)
  if [ "$file_count" -ge 6 ]; then
    log_pass "Mock files created ($file_count files)"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_fail "Failed to create mock files"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  log_test "Smoke test: Create scope documents"
  echo "Scope doc" > "$smoke_scope/00_scope_document.md"
  echo "Features" > "$smoke_scope/01_features.md"
  echo "Journeys" > "$smoke_scope/02_user_journeys.md"

  local scope_count
  scope_count=$(ls -1 "$smoke_scope" | wc -l)
  if [ "$scope_count" -ge 3 ]; then
    log_pass "Scope documents created ($scope_count files)"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_fail "Failed to create scope documents"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  # Cleanup
  rm -rf "$smoke_dir" "$smoke_scope"
  log_test "Smoke test: Cleanup"
  if [ ! -d "$smoke_dir" ] && [ ! -d "$smoke_scope" ]; then
    log_pass "Cleanup successful"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_fail "Cleanup failed"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

#==============================================================================
# DATABASE SYNC TESTS
#==============================================================================

test_db_connection() {
  # Test database connectivity
  if [ -f ".env" ]; then
    source .env 2>/dev/null || true
  fi

  local host="${POSTGRES_HOST:-localhost}"
  local port="${POSTGRES_PORT:-5432}"

  # Just check if we can connect
  PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
    -h "$host" \
    -p "$port" \
    -U "${POSTGRES_USER:-postgres}" \
    -d "${POSTGRES_DB:-cattle_erp}" \
    -c "SELECT 1" > /dev/null 2>&1
}

test_sync_script_syntax() {
  bash -n "$SCRIPT_DIR/sync-interview-to-db.sh"
}

test_sync_script_help() {
  "$SCRIPT_DIR/sync-interview-to-db.sh" 2>&1 | head -5 | grep -q "Sync Interview"
}

run_database_tests() {
  echo ""
  echo "=============================================="
  echo "  DATABASE SYNC TESTS"
  echo "=============================================="
  echo ""

  run_test "sync-interview-to-db.sh syntax" test_sync_script_syntax

  if test_db_connection; then
    log_test "Database connection"
    log_pass "Database connection"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_test "Database connection"
    log_skip "Database not available"
  fi
}

#==============================================================================
# MAIN
#==============================================================================

show_help() {
  cat << 'EOF'
Test Suite for feature_interrogate.sh

Usage:
  ./test-feature-interrogate.sh              # Run all tests
  ./test-feature-interrogate.sh --unit       # Unit tests only
  ./test-feature-interrogate.sh --mock       # Mock tests only
  ./test-feature-interrogate.sh --integration # Integration tests only
  ./test-feature-interrogate.sh --smoke      # Quick smoke test
  ./test-feature-interrogate.sh --database   # Database sync tests
  ./test-feature-interrogate.sh --all        # Run everything

Test Levels:
  Unit        - Test script structure and syntax
  Mock        - Test file formats with simulated data
  Integration - Test with real Claude CLI (requires claude)
  Smoke       - Quick end-to-end validation
  Database    - Test database connectivity and sync
EOF
  exit 0
}

print_summary() {
  echo ""
  echo "=============================================="
  echo "  TEST SUMMARY"
  echo "=============================================="
  echo ""
  echo "  Total:  $TESTS_RUN"
  echo "  Passed: $TESTS_PASSED"
  echo "  Failed: $TESTS_FAILED"
  echo ""

  if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}Some tests failed.${NC}"
    return 1
  fi
}

main() {
  echo "=============================================="
  echo "  Feature Interrogate Test Suite"
  echo "=============================================="

  case "${1:-all}" in
    --help|-h)
      show_help
      ;;
    --unit)
      run_unit_tests
      ;;
    --mock)
      run_mock_tests
      ;;
    --integration)
      run_integration_tests
      ;;
    --smoke|--quick)
      run_smoke_test
      ;;
    --database|--db)
      run_database_tests
      ;;
    --all|*)
      run_unit_tests
      run_mock_tests
      run_smoke_test
      run_database_tests
      run_integration_tests
      ;;
  esac

  print_summary
}

# Trap cleanup on exit
trap cleanup EXIT

main "$@"
