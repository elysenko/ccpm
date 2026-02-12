#!/bin/bash
# test-lib.sh — Shared library for journey testing (pipeline Step 20 + standalone runner)
#
# All functions prefixed with tl_ to avoid naming collisions when sourced
# by feature_interrogate.sh (which has its own log(), db_exec(), etc.).
#
# Usage:
#   source "$SCRIPT_DIR/lib/test-lib.sh"
#
# Required variables (caller must set before sourcing):
#   PROJECT_ROOT — absolute path to project root
#
# Optional variables (set defaults if not provided):
#   TL_DB_NAMESPACE, TL_DB_POD, TL_DB_USER, TL_DB_NAME, TL_DB_PASSWORD

# ── Include guard ─────────────────────────────────────────────────────────────
[[ -n "${_TEST_LIB_LOADED:-}" ]] && return 0
_TEST_LIB_LOADED=1

# ── Logging ───────────────────────────────────────────────────────────────────
# Prefixed with tl_ to avoid collision with pipeline's log().
tl_log()         { echo -e "\033[0;34m[test-lib]\033[0m $*"; }
tl_log_success() { echo -e "\033[0;32m[test-lib] ✓\033[0m $*"; }
tl_log_error()   { echo -e "\033[0;31m[test-lib] ✗\033[0m $*" >&2; }
tl_log_warn()    { echo -e "\033[1;33m[test-lib] !\033[0m $*"; }

# ── Database helpers ──────────────────────────────────────────────────────────

# Load DB config from .env or defaults. Sets TL_DB_* variables.
tl_load_db_config() {
  local project_root="${PROJECT_ROOT:-.}"
  local env_file=""
  if [ -f "$project_root/.env" ]; then
    env_file="$project_root/.env"
  elif [ -f "$project_root/../.env" ]; then
    env_file="$project_root/../.env"
  fi

  if [ -n "$env_file" ]; then
    TL_DB_HOST=$(grep -m1 '^DB_HOST=' "$env_file" | cut -d= -f2- || true)
    TL_DB_PORT=$(grep -m1 '^DB_PORT=' "$env_file" | cut -d= -f2- || true)
    TL_DB_USER=$(grep -m1 '^DB_USER=' "$env_file" | cut -d= -f2- || true)
    TL_DB_NAME=$(grep -m1 '^DB_NAME=' "$env_file" | cut -d= -f2- || true)
    TL_DB_PASSWORD=$(grep -m1 '^DB_PASSWORD=' "$env_file" | cut -d= -f2- || true)
  fi

  # Fallback: query K8s secret if password missing
  if [ -z "${TL_DB_PASSWORD:-}" ]; then
    TL_DB_PASSWORD=$(kubectl get secret cattle-erp-postgresql -n cattle-erp \
      -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d 2>/dev/null || true)
  fi

  # Final defaults
  TL_DB_HOST="${TL_DB_HOST:-cattle-erp-postgresql.cattle-erp.svc.cluster.local}"
  TL_DB_PORT="${TL_DB_PORT:-5432}"
  TL_DB_USER="${TL_DB_USER:-postgres}"
  TL_DB_NAME="${TL_DB_NAME:-cattle-erp}"
  TL_DB_PASSWORD="${TL_DB_PASSWORD:-}"

  # Derive K8s pod name and namespace from DB_HOST
  local svc_name="${TL_DB_HOST%%.*}"
  local remainder="${TL_DB_HOST#*.}"
  TL_DB_NAMESPACE="${remainder%%.*}"
  TL_DB_POD="${svc_name}-0"
}

# Execute SQL via kubectl and return result. Reads SQL from stdin.
# Usage: echo "SELECT 1;" | tl_db_query
tl_db_query() {
  kubectl exec -i -n "$TL_DB_NAMESPACE" "$TL_DB_POD" -- \
    env PGPASSWORD="$TL_DB_PASSWORD" psql -U "$TL_DB_USER" -d "$TL_DB_NAME" -tA 2>/dev/null
}

# Execute SQL file via kubectl.
tl_db_exec_file() {
  local sql_file="$1"
  kubectl exec -i -n "$TL_DB_NAMESPACE" "$TL_DB_POD" -- \
    env PGPASSWORD="$TL_DB_PASSWORD" psql -U "$TL_DB_USER" -d "$TL_DB_NAME" -f - < "$sql_file" 2>&1
}

# Build the kubectl exec DB command prefix (for workers that shell out).
# Returns a string suitable for: $db_cmd psql -U user -d db ...
tl_build_db_cmd() {
  echo "kubectl exec -i -n $TL_DB_NAMESPACE $TL_DB_POD -- env PGPASSWORD=$TL_DB_PASSWORD"
}

# ── Persona helpers ───────────────────────────────────────────────────────────

# Extract email for a persona from personas.json
# Args: personas_json persona_id
tl_get_persona_email() {
  local personas_json="$1"
  local persona_id="$2"
  python3 -c "
import json
data = json.load(open('$personas_json'))
personas = data.get('personas', data if isinstance(data, list) else [])
for p in personas:
    if p.get('id') == '$persona_id':
        print(p.get('testData', {}).get('email', ''))
        break
" 2>/dev/null || true
}

# Extract password for a persona from personas.json
# Args: personas_json persona_id
tl_get_persona_password() {
  local personas_json="$1"
  local persona_id="$2"
  python3 -c "
import json
data = json.load(open('$personas_json'))
personas = data.get('personas', data if isinstance(data, list) else [])
for p in personas:
    if p.get('id') == '$persona_id':
        print(p.get('testData', {}).get('password', ''))
        break
" 2>/dev/null || true
}

# ── Test matrix ───────────────────────────────────────────────────────────────

# Build persona-journey test matrix from personas.json.
# Outputs lines of: persona_id|journey_id
# Args: personas_json
tl_build_test_matrix() {
  local personas_json="$1"
  python3 -c "
import json, sys
data = json.load(open('$personas_json'))
personas = data.get('personas', data if isinstance(data, list) else [])
for p in personas:
    pid = p.get('id', '')
    journeys = p.get('journeys', {})
    primary = journeys.get('primary', [])
    if primary:
        for jid in primary[:3]:
            print(f'{pid}|{jid}')
" 2>/dev/null || true
}

# ── MCP configs ───────────────────────────────────────────────────────────────

# Create per-worker MCP configs with isolated Playwright browser instances.
# Args: batch_dir num_workers
tl_create_mcp_configs() {
  local batch_dir="$1"
  local num_workers="$2"
  local w
  for w in $(seq 1 "$num_workers"); do
    mkdir -p "$batch_dir/pw-data-${w}" 2>/dev/null || true
    cat > "$batch_dir/mcp-worker-${w}.json" << MCPEOF
{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--executable-path","/snap/bin/chromium","--image-responses","omit","--user-data-dir","$batch_dir/pw-data-${w}"]}}}
MCPEOF
  done
}

# ── Batch partitioning ────────────────────────────────────────────────────────

# Round-robin partition persona_journey_map lines into per-worker batch files.
# Args: batch_dir num_workers prefix persona_journey_map_text
# Creates: $batch_dir/${prefix}-batch-N.txt, clears ${prefix}-log-N.txt and ${prefix}-result-N.txt
tl_partition_batches() {
  local batch_dir="$1"
  local num_workers="$2"
  local prefix="$3"
  local map_text="$4"

  local w
  for w in $(seq 1 "$num_workers"); do
    : > "$batch_dir/${prefix}-batch-${w}.txt"
    : > "$batch_dir/${prefix}-log-${w}.txt"
    : > "$batch_dir/${prefix}-result-${w}.txt"
  done

  local batch_num=1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" >> "$batch_dir/${prefix}-batch-${batch_num}.txt"
    batch_num=$(( (batch_num % num_workers) + 1 ))
  done <<< "$map_text"
}

# ── Result aggregation ────────────────────────────────────────────────────────

# Aggregate explicit worker results (pass|fail|error format).
# Args: batch_dir num_workers
# Outputs: pass|fail|error to stdout
tl_aggregate_explicit_results() {
  local batch_dir="$1"
  local num_workers="$2"

  local total_pass=0 total_fail=0 total_error=0
  local w
  for w in $(seq 1 "$num_workers"); do
    if [ -f "$batch_dir/explicit-result-${w}.txt" ]; then
      local p f e
      IFS='|' read -r p f e _ _ < "$batch_dir/explicit-result-${w}.txt"
      total_pass=$((total_pass + ${p:-0}))
      total_fail=$((total_fail + ${f:-0}))
      total_error=$((total_error + ${e:-0}))
    fi
  done
  echo "${total_pass}|${total_fail}|${total_error}"
}

# Aggregate general worker results (pass|fail|error|scores_sum|scores_count format).
# Args: batch_dir num_workers
# Outputs: pass|fail|error|scores_sum|scores_count to stdout
tl_aggregate_general_results() {
  local batch_dir="$1"
  local num_workers="$2"

  local total_pass=0 total_fail=0 total_error=0
  local total_scores_sum=0 total_scores_count=0
  local w
  for w in $(seq 1 "$num_workers"); do
    if [ -f "$batch_dir/general-result-${w}.txt" ]; then
      local p f e ss sc
      IFS='|' read -r p f e ss sc < "$batch_dir/general-result-${w}.txt"
      total_pass=$((total_pass + ${p:-0}))
      total_fail=$((total_fail + ${f:-0}))
      total_error=$((total_error + ${e:-0}))
      total_scores_sum=$((total_scores_sum + ${ss:-0}))
      total_scores_count=$((total_scores_count + ${sc:-0}))
    fi
  done
  echo "${total_pass}|${total_fail}|${total_error}|${total_scores_sum}|${total_scores_count}"
}

# Stream worker log files to a callback function (or echo).
# Args: batch_dir num_workers prefix [log_callback]
tl_stream_worker_logs() {
  local batch_dir="$1"
  local num_workers="$2"
  local prefix="$3"
  local log_fn="${4:-echo}"

  local w
  for w in $(seq 1 "$num_workers"); do
    if [ -f "$batch_dir/${prefix}-log-${w}.txt" ]; then
      while IFS= read -r logline; do
        $log_fn "$logline"
      done < "$batch_dir/${prefix}-log-${w}.txt"
    fi
  done
}

# ── Prerequisites check ──────────────────────────────────────────────────────

# Verify all prerequisites for running journey tests.
# Args: session_dir session_name project_root
# Returns 0 on success, 1 on failure (with error messages).
tl_check_test_prerequisites() {
  local session_dir="$1"
  local session_name="$2"
  local project_root="${3:-$PROJECT_ROOT}"
  local personas_json="$session_dir/personas.json"
  local ok=true

  # 1. personas.json exists
  if [ ! -f "$personas_json" ]; then
    tl_log_error "Personas JSON not found at $personas_json — run Step 19 first"
    ok=false
  fi

  # 2. Run test migrations
  tl_log "Ensuring test feedback tables exist..."
  for mig in backend/migrations/042_test_instances.sql \
             backend/migrations/043_explicit_journey_feedback.sql \
             backend/migrations/044_general_goal_feedback.sql \
             backend/migrations/045_test_instance_session_id.sql; do
    if [ -f "$project_root/$mig" ]; then
      kubectl exec -i -n "$TL_DB_NAMESPACE" "$TL_DB_POD" -- \
        env PGPASSWORD="$TL_DB_PASSWORD" psql -U "$TL_DB_USER" -d "$TL_DB_NAME" -f - \
        < "$project_root/$mig" 2>/dev/null || true
    fi
  done

  # 3. Test users exist
  local test_user_count
  test_user_count=$(echo "SELECT count(*) FROM users WHERE email LIKE 'test+persona%';" | tl_db_query) || true
  if [ "${test_user_count:-0}" -lt 5 ]; then
    tl_log_error "Only ${test_user_count:-0} test users found (need at least 5). Run Step 19 first."
    ok=false
  else
    tl_log "Found ${test_user_count} test users"
  fi

  # 4. Confirmed journeys exist for this session
  local journey_count
  journey_count=$(echo "SELECT count(*) FROM journey WHERE session_name='$session_name' AND confirmation_status='confirmed';" | tl_db_query) || true
  if [ "${journey_count:-0}" -eq 0 ]; then
    tl_log_error "No confirmed journeys found for session '$session_name'"
    ok=false
  else
    tl_log "Found ${journey_count} confirmed journeys"
  fi

  # 5. Backend health
  local health_status
  health_status=$(curl -sf "http://ubuntu.desmana-truck.ts.net:32080/health" 2>/dev/null) || true
  if [ -z "$health_status" ]; then
    tl_log_warn "Backend health check failed — tests may have connectivity issues"
  fi

  # 6. Persona RBAC privileges — fail if any persona has zero privileges
  local zero_priv_count
  zero_priv_count=$(echo "
    SELECT count(*) FROM users u
    WHERE u.email LIKE 'test+persona%'
      AND NOT EXISTS (
        SELECT 1 FROM user_group_members ugm
        JOIN group_privileges gp ON gp.group_id = ugm.group_id AND gp.granted = true
        WHERE ugm.user_id = u.id
      );
  " | tl_db_query) || true

  if [ "${zero_priv_count:-0}" -gt 0 ]; then
    tl_log_error "${zero_priv_count} persona(s) have ZERO RBAC privileges — RBAC groups/memberships/grants missing. Re-run Step 19."
    ok=false
  else
    tl_log "All test personas have RBAC privileges"
  fi

  if [ "$ok" = "false" ]; then
    return 1
  fi
  return 0
}

# ── Worker functions ──────────────────────────────────────────────────────────

# Worker function for explicit journey tests.
# Runs as a background subshell — communicates results via files only.
# Args: worker_id batch_file mcp_config session_dir artifacts_dir personas_json
#       session_name test_run_id base_url db_namespace db_pod db_user db_name db_password
#       result_file log_file
tl_run_explicit_worker() {
  local worker_id="$1"
  local batch_file="$2"
  local mcp_config="$3"
  local session_dir="$4"
  local artifacts_dir="$5"
  local personas_json="$6"
  local session_name="$7"
  local test_run_id="$8"
  local base_url="$9"
  local db_namespace="${10}"
  local db_pod="${11}"
  local db_user="${12}"
  local db_name="${13}"
  local db_password="${14}"
  local result_file="${15}"
  local log_file="${16}"

  local db_cmd="kubectl exec -i -n $db_namespace $db_pod -- env PGPASSWORD=$db_password"
  local pass=0 fail=0 error=0
  local test_num=0
  local total
  total=$(wc -l < "$batch_file" | tr -d ' ')

  while IFS='|' read -r persona_id journey_id <&3; do
    [ -z "$persona_id" ] && continue
    [ -z "$journey_id" ] && continue
    ((test_num++)) || true

    echo "[W${worker_id}] [$test_num/$total] Explicit: $persona_id × $journey_id" >> "$log_file"

    # Skip if already tested in THIS run (scoped by test_run_id)
    local already_tested
    already_tested=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
      "SELECT count(*) FROM test_instance WHERE session_name='$session_name' AND test_run_id='$test_run_id' AND persona_id='$persona_id' AND journey_id='$journey_id' AND mode='explicit';" 2>/dev/null) || true
    if [ "${already_tested:-0}" -gt 0 ]; then
      echo "[W${worker_id}]   Already tested in this run — skipping (resume)" >> "$log_file"
      local prev_status
      prev_status=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
        "SELECT overall_status FROM test_instance WHERE session_name='$session_name' AND test_run_id='$test_run_id' AND persona_id='$persona_id' AND journey_id='$journey_id' AND mode='explicit' ORDER BY completed_at DESC LIMIT 1;" 2>/dev/null) || true
      if [ "$prev_status" = "pass" ]; then
        ((pass++)) || true
      else
        ((fail++)) || true
      fi
      continue
    fi

    # Get persona credentials
    local persona_email persona_password
    persona_email=$(tl_get_persona_email "$personas_json" "$persona_id")
    persona_password=$(tl_get_persona_password "$personas_json" "$persona_id")

    if [ -z "$persona_email" ] || [ -z "$persona_password" ]; then
      echo "[W${worker_id}]   No credentials for $persona_id — skipping" >> "$log_file"
      ((error++)) || true
      continue
    fi

    # Get journey data from DB
    local journey_db_id journey_name journey_steps_json
    journey_db_id=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
      "SELECT id FROM journey WHERE session_name='$session_name' AND journey_id='$journey_id' AND confirmation_status='confirmed';" 2>/dev/null) || true

    if [ -z "$journey_db_id" ]; then
      echo "[W${worker_id}]   Journey $journey_id not found or not confirmed — skipping" >> "$log_file"
      ((error++)) || true
      continue
    fi

    journey_name=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
      "SELECT name FROM journey WHERE id=$journey_db_id;" 2>/dev/null) || true

    journey_steps_json=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
      "SELECT json_agg(row_to_json(s) ORDER BY s.step_number) FROM (
        SELECT step_number, step_name, user_action, user_intent,
               ui_page_route, ui_component_type, ui_component_name,
               ui_feedback, ui_state_after, possible_errors
        FROM journey_steps_detailed WHERE journey_id=$journey_db_id
        ORDER BY step_number
      ) s;" 2>/dev/null) || true

    if [ -z "$journey_steps_json" ] || [ "$journey_steps_json" = "null" ]; then
      echo "[W${worker_id}]   No steps found for $journey_id — skipping" >> "$log_file"
      ((error++)) || true
      continue
    fi

    # Create artifacts subdirectory
    local test_artifacts="$artifacts_dir/$persona_id/$journey_id"
    mkdir -p "$test_artifacts" 2>/dev/null || true

    # Build explicit test prompt — dynamic data only (instructions in system prompt)
    local prompt_file="$session_dir/.explicit-test-prompt-${persona_id}-${journey_id}.txt"
    cat > "$prompt_file" << EXPLICIT_PROMPT_EOF
APPLICATION: $base_url
LOGIN: Email: $persona_email  Password: $persona_password
JOURNEY: $journey_name ($journey_id)
SCREENSHOTS: $test_artifacts/

STEPS TO TEST:
$journey_steps_json
EXPLICIT_PROMPT_EOF

    # Run Claude sub-agent with worker-specific MCP config
    local output_file="$session_dir/.explicit-result-${persona_id}-${journey_id}.json"
    # Always use a fresh session to avoid reloading prior conversation history (snapshots)
    local claude_session_id
    claude_session_id=$(python3 -c "import uuid; print(uuid.uuid4())")

    # Dynamic max-turns: ceil((steps + 2) * 5.5) — login + steps + output, ~5.5 browser actions each
    local test_model="${TEST_MODEL:-sonnet}"
    local step_count max_turns
    step_count=$(python3 -c "import json; print(len(json.loads('''$journey_steps_json''')))" 2>/dev/null) || true
    step_count=${step_count:-5}
    max_turns=$(python3 -c "import math; print(math.ceil(($step_count + 2) * 5.5))")

    local claude_attempt=1
    local max_attempts=2
    local test_success=false

    while [ "$claude_attempt" -le "$max_attempts" ]; do
      claude --dangerously-skip-permissions --print \
        --model "$test_model" \
        --max-turns "$max_turns" \
        --session-id "$claude_session_id" \
        --strict-mcp-config --mcp-config "$mcp_config" \
        --append-system-prompt "You are a QA tester. Test a web app by following journey steps in the browser.
Instructions:
1. Navigate to the APPLICATION URL
2. Log in with the provided credentials
3. For each step, perform the user_action in the browser
4. Report each step as complete or incomplete
5. If incomplete: describe what went wrong in failure_reason
6. On failure: take a screenshot (save as step-{N}-failure.png to the SCREENSHOTS dir)
7. Include screenshot_path in JSON for failed steps
8. Continue testing even if a step fails
9. Close the browser when done

Output ONLY this JSON (no markdown fences, no explanation):
{\"login_status\":\"complete|incomplete\",\"login_notes\":\"...\",\"step_results\":[{\"step_number\":1,\"step_name\":\"...\",\"status\":\"complete|incomplete\",\"failure_reason\":\"...or null\",\"bugs_found\":[],\"page_url\":\"...\",\"screenshot_path\":\"...or null\"}]}" \
        -p "$(cat "$prompt_file")" \
        > "$output_file" 2>/dev/null || true

      if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        sed -i '/./,$!d' "$output_file"
        sed -i '/^```/d' "$output_file"

        if python3 -c "import json; data=json.load(open('$output_file')); assert 'step_results' in data" 2>/dev/null; then
          test_success=true
          break
        fi
      fi
      ((claude_attempt++)) || true
    done

    if [ "$test_success" != "true" ]; then
      echo "[W${worker_id}]   FAIL (no valid JSON) $persona_id × $journey_id" >> "$log_file"
      ((error++)) || true
      continue
    fi

    # Parse results and insert into database
    local sql_file="$session_dir/.sql-explicit-${persona_id}-${journey_id}.sql"
    python3 << PARSE_EXPLICIT_WEOF > "$sql_file"
import json, sys

try:
    data = json.load(open('$output_file'))
    steps = data.get('step_results', [])
    total = len(steps)
    completed = sum(1 for s in steps if s.get('status') in ('complete', 'pass'))
    failed = sum(1 for s in steps if s.get('status') in ('incomplete', 'fail'))

    if failed == 0 and completed > 0:
        status = 'pass'
    elif completed == 0:
        status = 'fail'
    else:
        status = 'partial'

    print(f"""INSERT INTO test_instance (
        session_name, test_run_id, persona_id, mode,
        journey_id, journey_db_id,
        overall_status, steps_total, steps_completed, steps_failed,
        base_url, artifacts_dir, started_at, completed_at
    ) VALUES (
        '$session_name', '$test_run_id', '$persona_id', 'explicit',
        '$journey_id', $journey_db_id,
        '{status}', {total}, {completed}, {failed},
        '$base_url', '$test_artifacts',
        NOW(), NOW()
    ) ON CONFLICT DO NOTHING;""")

    def esc(v):
        if v is None: return ''
        if isinstance(v, (list, dict)): return json.dumps(v).replace("'", "''")
        return str(v).replace("'", "''")

    for s in steps:
        sn = s.get('step_number', 0)
        sname = esc(s.get('step_name', ''))
        raw_status = s.get('status', 'skipped')
        sstatus = {'pass': 'complete', 'fail': 'incomplete'}.get(raw_status, raw_status)
        fr = esc(s.get('failure_reason'))
        fc = esc(s.get('failure_category'))
        eo = esc(s.get('expected_outcome'))
        ao = esc(s.get('actual_outcome'))
        bugs = json.dumps(s.get('bugs_found', [])).replace("'", "''")
        access = json.dumps(s.get('accessibility_issues', [])).replace("'", "''")
        perf = esc(s.get('performance_notes'))
        sugg = esc(s.get('suggestions'))
        purl = esc(s.get('page_url'))
        sspath = esc(s.get('screenshot_path'))

        print(f"""INSERT INTO explicit_journey_feedback (
            test_instance_id,
            step_number, step_name, status,
            failure_reason, failure_category, expected_outcome, actual_outcome,
            bugs_found, accessibility_issues, performance_notes, suggestions,
            page_url, screenshot_path
        ) VALUES (
            (SELECT id FROM test_instance WHERE test_run_id='$test_run_id' AND persona_id='$persona_id' AND journey_id='$journey_id' LIMIT 1),
            {sn}, '{sname}', '{sstatus}',
            '{fr}', '{fc}', '{eo}', '{ao}',
            '{bugs}'::jsonb, '{access}'::jsonb, '{perf}', '{sugg}',
            '{purl}', '{sspath}'
        );""")

except Exception as e:
    print(f"-- Error: {e}", file=sys.stderr)
PARSE_EXPLICIT_WEOF

    # Execute SQL with error capture
    if [ -s "$sql_file" ]; then
      local db_err
      db_err=$($db_cmd psql -U "$db_user" -d "$db_name" -f - < "$sql_file" 2>&1) || true
      if echo "$db_err" | grep -qi "error"; then
        echo "[W${worker_id}]   DB INSERT FAILED for $persona_id × $journey_id: $(echo "$db_err" | head -3)" >> "$log_file"
      fi
      # Store Claude session ID for later resume
      $db_cmd psql -U "$db_user" -d "$db_name" -c \
        "UPDATE test_instance SET claude_session_id='$claude_session_id' WHERE test_run_id='$test_run_id' AND persona_id='$persona_id' AND journey_id='$journey_id' AND mode='explicit';" 2>/dev/null || true
    else
      echo "[W${worker_id}]   SQL generation produced empty output for $persona_id × $journey_id" >> "$log_file"
    fi

    # Count result
    local test_status
    test_status=$(python3 -c "
import json
data = json.load(open('$output_file'))
steps = data.get('step_results', [])
completed = sum(1 for s in steps if s.get('status') in ('complete', 'pass'))
failed = sum(1 for s in steps if s.get('status') in ('incomplete', 'fail'))
if failed == 0 and completed > 0: print('pass')
elif completed == 0: print('fail')
else: print('partial')
" 2>/dev/null) || true

    if [ "$test_status" = "pass" ]; then
      echo "[W${worker_id}]   PASS $persona_id × $journey_id" >> "$log_file"
      ((pass++)) || true
    else
      echo "[W${worker_id}]   ${test_status:-error} $persona_id × $journey_id" >> "$log_file"
      ((fail++)) || true
    fi

    # Clear browser state between persona tests
    local pw_data_dir
    pw_data_dir="$(dirname "$mcp_config")/pw-data-${worker_id}"
    rm -rf "${pw_data_dir:?}/"* 2>/dev/null || true

  done 3< "$batch_file"

  # Write results for aggregation by main process
  echo "${pass}|${fail}|${error}" > "$result_file"
}

# Worker function for general goal tests.
# Args: same as tl_run_explicit_worker
tl_run_general_worker() {
  local worker_id="$1"
  local batch_file="$2"
  local mcp_config="$3"
  local session_dir="$4"
  local artifacts_dir="$5"
  local personas_json="$6"
  local session_name="$7"
  local test_run_id="$8"
  local base_url="$9"
  local db_namespace="${10}"
  local db_pod="${11}"
  local db_user="${12}"
  local db_name="${13}"
  local db_password="${14}"
  local result_file="${15}"
  local log_file="${16}"

  local db_cmd="kubectl exec -i -n $db_namespace $db_pod -- env PGPASSWORD=$db_password"
  local pass=0 fail=0 error=0
  local scores_sum=0 scores_count=0
  local test_num=0
  local total
  total=$(wc -l < "$batch_file" | tr -d ' ')

  while IFS='|' read -r persona_id journey_id <&3; do
    [ -z "$persona_id" ] && continue
    [ -z "$journey_id" ] && continue
    ((test_num++)) || true

    echo "[W${worker_id}] [$test_num/$total] General: $persona_id × $journey_id" >> "$log_file"

    # Skip if already tested in THIS run (scoped by test_run_id)
    local already_tested
    already_tested=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
      "SELECT count(*) FROM test_instance WHERE session_name='$session_name' AND test_run_id='$test_run_id' AND persona_id='$persona_id' AND journey_id='$journey_id' AND mode='general';" 2>/dev/null) || true
    if [ "${already_tested:-0}" -gt 0 ]; then
      echo "[W${worker_id}]   Already tested in this run — skipping (resume)" >> "$log_file"
      local prev_status
      prev_status=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
        "SELECT overall_status FROM test_instance WHERE session_name='$session_name' AND test_run_id='$test_run_id' AND persona_id='$persona_id' AND journey_id='$journey_id' AND mode='general' ORDER BY completed_at DESC LIMIT 1;" 2>/dev/null) || true
      if [ "$prev_status" = "pass" ]; then
        ((pass++)) || true
      else
        ((fail++)) || true
      fi
      continue
    fi

    # Get persona credentials
    local persona_email persona_password
    persona_email=$(tl_get_persona_email "$personas_json" "$persona_id")
    persona_password=$(tl_get_persona_password "$personas_json" "$persona_id")

    if [ -z "$persona_email" ] || [ -z "$persona_password" ]; then
      ((error++)) || true
      continue
    fi

    # Get journey DB id, goal text, and step count
    local journey_db_id goal_text step_count
    journey_db_id=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
      "SELECT id FROM journey WHERE session_name='$session_name' AND journey_id='$journey_id' AND confirmation_status='confirmed';" 2>/dev/null) || true
    goal_text=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
      "SELECT COALESCE(goal, '') FROM journey WHERE session_name='$session_name' AND journey_id='$journey_id';" 2>/dev/null) || true

    if [ -z "$goal_text" ]; then
      echo "[W${worker_id}]   No goal found for $journey_id — skipping" >> "$log_file"
      ((error++)) || true
      continue
    fi

    # Get step count for max-turns calculation
    if [ -n "$journey_db_id" ]; then
      step_count=$($db_cmd psql -U "$db_user" -d "$db_name" -tAc \
        "SELECT count(*) FROM journey_steps_detailed WHERE journey_id=$journey_db_id;" 2>/dev/null) || true
    fi
    step_count=${step_count:-5}

    local test_artifacts="$artifacts_dir/$persona_id/general-$journey_id"
    mkdir -p "$test_artifacts" 2>/dev/null || true

    # Build general test prompt — dynamic data only (instructions in system prompt)
    local prompt_file="$session_dir/.general-test-prompt-${persona_id}-${journey_id}.txt"
    cat > "$prompt_file" << GENERAL_PROMPT_EOF
APPLICATION: $base_url
LOGIN: Email: $persona_email  Password: $persona_password
GOAL: $goal_text
SCREENSHOTS: $test_artifacts/
GENERAL_PROMPT_EOF

    # Run Claude sub-agent with worker-specific MCP config
    local output_file="$session_dir/.general-result-${persona_id}-${journey_id}.json"
    # Always use a fresh session to avoid reloading prior conversation history (snapshots)
    local claude_session_id
    claude_session_id=$(python3 -c "import uuid; print(uuid.uuid4())")

    # Dynamic max-turns: ceil((steps + 2) * 5.5)
    local test_model="${TEST_MODEL:-sonnet}"
    local max_turns
    max_turns=$(python3 -c "import math; print(math.ceil(($step_count + 2) * 5.5))")

    local claude_attempt=1
    local test_success=false

    while [ "$claude_attempt" -le 2 ]; do
      claude --dangerously-skip-permissions --print \
        --model "$test_model" \
        --max-turns "$max_turns" \
        --session-id "$claude_session_id" \
        --strict-mcp-config --mcp-config "$mcp_config" \
        --append-system-prompt "You are a QA tester. Explore a web app to accomplish the given GOAL. No predefined steps — discover the path yourself.
Instructions:
1. Navigate to the APPLICATION URL and log in
2. Explore the UI to accomplish the GOAL
3. Record every action as a discovered step with scores: intuitive (0-100), feedback_quality (0-100)
4. Note bugs, accessibility issues, confusion points
5. Save screenshots to SCREENSHOTS dir on interesting findings or failures
6. Score the rubric: task_completion, efficiency, error_recovery, learnability, confidence (0-100 each)
7. For rubric scores below 80, include a deduction reason
8. Close the browser when done

Output ONLY this JSON (no markdown fences, no explanation):
{\"goal_achieved\":true,\"discovered_steps\":[{\"step_number\":1,\"action_taken\":\"...\",\"page_url\":\"...\",\"element_interacted\":\"...\",\"score_intuitive\":90,\"score_feedback_quality\":85,\"observation\":\"...\",\"bugs_found\":[],\"screenshot_path\":null}],\"rubric_scores\":{\"task_completion\":75,\"task_completion_deduction\":null,\"efficiency\":80,\"efficiency_deduction\":null,\"error_recovery\":100,\"error_recovery_deduction\":null,\"learnability\":70,\"learnability_deduction\":null,\"confidence\":85,\"confidence_deduction\":null},\"overall_notes\":\"...\"}" \
        -p "$(cat "$prompt_file")" \
        > "$output_file" 2>/dev/null || true

      if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        sed -i '/./,$!d' "$output_file"
        sed -i '/^```/d' "$output_file"

        if python3 -c "import json; data=json.load(open('$output_file')); assert 'rubric_scores' in data" 2>/dev/null; then
          test_success=true
          break
        fi
      fi
      ((claude_attempt++)) || true
    done

    if [ "$test_success" != "true" ]; then
      echo "[W${worker_id}]   FAIL (no valid JSON) general $persona_id × $journey_id" >> "$log_file"
      ((error++)) || true
      continue
    fi

    # Parse and insert results
    local sql_file="$session_dir/.sql-general-${persona_id}-${journey_id}.sql"
    python3 << PARSE_GENERAL_WEOF > "$sql_file"
import json, sys

try:
    data = json.load(open('$output_file'))
    steps = data.get('discovered_steps', [])
    rubric = data.get('rubric_scores', {})
    goal_achieved = data.get('goal_achieved', False)
    total = len(steps)

    tc = rubric.get('task_completion', 0)
    eff = rubric.get('efficiency', 0)
    er = rubric.get('error_recovery', 0)
    learn = rubric.get('learnability', 0)
    conf = rubric.get('confidence', 0)
    overall = (tc + eff + er + learn + conf) // 5

    status = 'pass' if goal_achieved and overall >= 50 else 'fail'
    goal_text_escaped = """$goal_text""".replace("'", "''")

    print(f"""INSERT INTO test_instance (
        session_name, test_run_id, persona_id, mode,
        journey_id,
        goal_text, goal_source,
        overall_status, steps_total, steps_completed,
        score_task_completion, score_efficiency, score_error_recovery,
        score_learnability, score_confidence, score_overall,
        base_url, artifacts_dir, started_at, completed_at
    ) VALUES (
        '$session_name', '$test_run_id', '$persona_id', 'general',
        '$journey_id',
        '{goal_text_escaped}', 'journey:$journey_id',
        '{status}', {total}, {total},
        {tc}, {eff}, {er}, {learn}, {conf}, {overall},
        '$base_url', '$test_artifacts',
        NOW(), NOW()
    ) ON CONFLICT DO NOTHING;""")

    def esc(v):
        if v is None: return ''
        if isinstance(v, (list, dict)): return json.dumps(v).replace("'", "''")
        return str(v).replace("'", "''")

    for s in steps:
        sn = s.get('step_number', 0)
        at = esc(s.get('action_taken', ''))
        ai = esc(s.get('action_intent'))
        pu = esc(s.get('page_url'))
        ei = esc(s.get('element_interacted'))
        si = s.get('score_intuitive')
        sfq = s.get('score_feedback_quality')
        obs = esc(s.get('observation'))
        bugs = json.dumps(s.get('bugs_found', [])).replace("'", "''")
        access = json.dumps(s.get('accessibility_issues', [])).replace("'", "''")
        perf = esc(s.get('performance_notes'))
        sugg = esc(s.get('suggestions'))
        conf_pts = esc(s.get('confusion_points'))
        sspath = esc(s.get('screenshot_path'))

        si_val = f"{si}" if si is not None else "NULL"
        sfq_val = f"{sfq}" if sfq is not None else "NULL"

        print(f"""INSERT INTO general_goal_feedback (
            test_instance_id, step_number,
            action_taken, action_intent, page_url, element_interacted,
            score_intuitive, score_feedback_quality,
            observation, bugs_found, accessibility_issues,
            performance_notes, suggestions, confusion_points,
            screenshot_path
        ) VALUES (
            (SELECT id FROM test_instance WHERE test_run_id='$test_run_id' AND persona_id='$persona_id' AND mode='general' AND goal_source='journey:$journey_id' LIMIT 1),
            {sn},
            '{at}', '{ai}', '{pu}', '{ei}',
            {si_val}, {sfq_val},
            '{obs}', '{bugs}'::jsonb, '{access}'::jsonb,
            '{perf}', '{sugg}', '{conf_pts}',
            '{sspath}'
        );""")

except Exception as e:
    print(f"-- Error: {e}", file=sys.stderr)
PARSE_GENERAL_WEOF

    # Execute SQL with error capture
    if [ -s "$sql_file" ]; then
      local db_err
      db_err=$($db_cmd psql -U "$db_user" -d "$db_name" -f - < "$sql_file" 2>&1) || true
      if echo "$db_err" | grep -qi "error"; then
        echo "[W${worker_id}]   DB INSERT FAILED for general $persona_id × $journey_id: $(echo "$db_err" | head -3)" >> "$log_file"
      fi
      # Store Claude session ID for later resume
      $db_cmd psql -U "$db_user" -d "$db_name" -c \
        "UPDATE test_instance SET claude_session_id='$claude_session_id' WHERE test_run_id='$test_run_id' AND persona_id='$persona_id' AND journey_id='$journey_id' AND mode='general';" 2>/dev/null || true
    else
      echo "[W${worker_id}]   SQL generation produced empty output for general $persona_id × $journey_id" >> "$log_file"
    fi

    # Extract score for summary
    local overall_score
    overall_score=$(python3 -c "
import json
data = json.load(open('$output_file'))
r = data.get('rubric_scores', {})
scores = [r.get('task_completion',0), r.get('efficiency',0), r.get('error_recovery',0), r.get('learnability',0), r.get('confidence',0)]
print(sum(scores) // 5)
" 2>/dev/null) || true

    if [ "${overall_score:-0}" -ge 50 ]; then
      echo "[W${worker_id}]   PASS $persona_id × $journey_id (score ${overall_score}/100)" >> "$log_file"
      ((pass++)) || true
    else
      echo "[W${worker_id}]   FAIL $persona_id × $journey_id (score ${overall_score:-0}/100)" >> "$log_file"
      ((fail++)) || true
    fi

    if [ -n "$overall_score" ]; then
      scores_sum=$((scores_sum + overall_score))
      ((scores_count++)) || true
    fi

    # Clear browser state between persona tests
    local pw_data_dir
    pw_data_dir="$(dirname "$mcp_config")/pw-data-${worker_id}"
    rm -rf "${pw_data_dir:?}/"* 2>/dev/null || true

  done 3< "$batch_file"

  # Write results for aggregation: pass|fail|error|scores_sum|scores_count
  echo "${pass}|${fail}|${error}|${scores_sum}|${scores_count}" > "$result_file"
}
