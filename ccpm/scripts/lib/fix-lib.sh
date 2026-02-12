#!/bin/bash
# fix-lib.sh — Library for the autonomous fix loop
#
# Functions: DB failure extraction, synthesis, stall detection, merge coordination
# All functions prefixed with fl_ to avoid naming collisions.
#
# Usage:
#   source "$SCRIPT_DIR/lib/fix-lib.sh"
#
# Required: test-lib.sh must be sourced first (for tl_db_query, tl_log, etc.)
# Required: fix-cluster-map.sh must be sourced first (for FC_* maps)

# ── Include guard ─────────────────────────────────────────────────────────────
[[ -n "${_FIX_LIB_LOADED:-}" ]] && return 0
_FIX_LIB_LOADED=1

# ── Logging ──────────────────────────────────────────────────────────────────
fl_log()         { echo -e "\033[0;35m[fix-loop]\033[0m $*"; }
fl_log_success() { echo -e "\033[0;32m[fix-loop] ✓\033[0m $*"; }
fl_log_error()   { echo -e "\033[0;31m[fix-loop] ✗\033[0m $*" >&2; }
fl_log_warn()    { echo -e "\033[1;33m[fix-loop] !\033[0m $*"; }

# ── Metrics extraction ───────────────────────────────────────────────────────

# Get pass/fail/total counts and avg score for a test run.
# Args: session_name test_run_id
# Outputs: pass_count|fail_count|total_count|avg_score
fl_get_test_metrics() {
  local session_name="$1"
  local test_run_id="$2"

  local result
  result=$(echo "
    SELECT
      COALESCE(SUM(CASE WHEN overall_status = 'pass' THEN 1 ELSE 0 END), 0) AS pass_count,
      COALESCE(SUM(CASE WHEN overall_status IN ('fail', 'partial', 'error') THEN 1 ELSE 0 END), 0) AS fail_count,
      COUNT(*) AS total_count,
      COALESCE(AVG(CASE WHEN score_overall IS NOT NULL THEN score_overall END)::int, 0) AS avg_score
    FROM test_instance
    WHERE session_name = '$session_name'
      AND test_run_id = '$test_run_id';
  " | tl_db_query) || true

  echo "$result" | tr -d '[:space:]' | tr '|' '|'
  # Output format: pass_count|fail_count|total_count|avg_score
}

# Get the latest test_run_id for a session.
# Args: session_name
# Outputs: test_run_id string
fl_get_latest_test_run_id() {
  local session_name="$1"
  local result
  result=$(echo "
    SELECT test_run_id FROM test_instance
    WHERE session_name = '$session_name'
    ORDER BY completed_at DESC LIMIT 1;
  " | tl_db_query) || true
  echo "$result" | tr -d '[:space:]'
}

# ── Failure extraction ───────────────────────────────────────────────────────

# Extract all failures from a test run, grouped by cluster.
# Args: session_name test_run_id output_file
# Writes JSON to output_file with structure:
# { "clusters": { "organizations": { "failures": [...] }, ... } }
fl_extract_failures() {
  local session_name="$1"
  local test_run_id="$2"
  local output_file="$3"

  python3 << EXTRACT_EOF > "$output_file"
import json, subprocess, sys

def db_query(sql):
    """Execute SQL via kubectl and return raw output."""
    proc = subprocess.run(
        ['kubectl', 'exec', '-i', '-n', '$TL_DB_NAMESPACE', '$TL_DB_POD', '--',
         'env', 'PGPASSWORD=$TL_DB_PASSWORD',
         'psql', '-U', '$TL_DB_USER', '-d', '$TL_DB_NAME', '-tA'],
        input=sql, capture_output=True, text=True
    )
    return proc.stdout.strip()

# Cluster mapping
cluster_journeys = {
    'organizations': ['J-001','J-002','J-003','J-013'],
    'connections': ['J-004','J-005'],
    'sharing': ['J-006','J-007','J-008'],
    'deals': ['J-009','J-010','J-011'],
    'invoices': ['J-012'],
}
journey_to_cluster = {}
for c, jids in cluster_journeys.items():
    for j in jids:
        journey_to_cluster[j] = c

# Get all failed test instances
rows = db_query("""
    SELECT ti.id, ti.persona_id, ti.journey_id, ti.mode, ti.overall_status,
           ti.steps_total, ti.steps_completed, ti.steps_failed,
           ti.score_task_completion, ti.score_overall, ti.claude_session_id
    FROM test_instance ti
    WHERE ti.session_name = '$session_name'
      AND ti.test_run_id = '$test_run_id'
      AND ti.overall_status IN ('fail', 'partial', 'error')
    ORDER BY ti.journey_id, ti.persona_id;
""")

clusters = {}
for row in rows.split('\n'):
    if not row.strip():
        continue
    parts = row.split('|')
    if len(parts) < 11:
        continue
    ti_id, persona_id, journey_id, mode, status, steps_total, steps_completed, steps_failed, score_tc, score_overall, claude_sid = parts[:11]

    cluster = journey_to_cluster.get(journey_id, 'unknown')
    if cluster not in clusters:
        clusters[cluster] = {'failures': []}

    failure = {
        'test_instance_id': ti_id,
        'persona_id': persona_id,
        'journey_id': journey_id,
        'mode': mode,
        'overall_status': status,
        'steps_total': int(steps_total) if steps_total else 0,
        'steps_completed': int(steps_completed) if steps_completed else 0,
        'steps_failed': int(steps_failed) if steps_failed else 0,
        'score_task_completion': int(score_tc) if score_tc else None,
        'score_overall': int(score_overall) if score_overall else None,
        'claude_session_id': claude_sid if claude_sid else None,
        'step_details': [],
    }

    # Get step-level details for explicit failures
    if mode == 'explicit':
        step_rows = db_query(f"""
            SELECT step_number, step_name, status, failure_reason, failure_category, page_url, screenshot_path
            FROM explicit_journey_feedback
            WHERE test_instance_id = '{ti_id}'
            ORDER BY step_number;
        """)
        for sr in step_rows.split('\n'):
            if not sr.strip():
                continue
            sp = sr.split('|')
            if len(sp) >= 7:
                failure['step_details'].append({
                    'step_number': int(sp[0]) if sp[0] else 0,
                    'step_name': sp[1],
                    'status': sp[2],
                    'failure_reason': sp[3] if sp[3] else None,
                    'failure_category': sp[4] if sp[4] else None,
                    'page_url': sp[5] if sp[5] else None,
                    'screenshot_path': sp[6] if sp[6] else None,
                })

    # Get step-level details for general failures
    elif mode == 'general':
        step_rows = db_query(f"""
            SELECT step_number, action_taken, observation, page_url, confusion_points, screenshot_path
            FROM general_goal_feedback
            WHERE test_instance_id = '{ti_id}'
            ORDER BY step_number;
        """)
        for sr in step_rows.split('\n'):
            if not sr.strip():
                continue
            sp = sr.split('|')
            if len(sp) >= 6:
                failure['step_details'].append({
                    'step_number': int(sp[0]) if sp[0] else 0,
                    'action_taken': sp[1],
                    'observation': sp[2] if sp[2] else None,
                    'page_url': sp[3] if sp[3] else None,
                    'confusion_points': sp[4] if sp[4] else None,
                    'screenshot_path': sp[5] if sp[5] else None,
                })

    clusters[cluster]['failures'].append(failure)

# Trim fields the synthesis agent doesn't need to reduce token consumption
for cluster_data in clusters.values():
    for f in cluster_data['failures']:
        f.pop('claude_session_id', None)
        for sd in f.get('step_details', []):
            sd.pop('screenshot_path', None)
            sd.pop('page_url', None)
            if sd.get('failure_reason') and len(sd['failure_reason']) > 200:
                sd['failure_reason'] = sd['failure_reason'][:200] + '...'

result = {'clusters': clusters}
print(json.dumps(result, indent=2))
EXTRACT_EOF
}

# ── Unfixable tracking ───────────────────────────────────────────────────────

# Load unfixable items from file.
# Args: unfixable_file
# Outputs: JSON content or empty object
fl_load_unfixable() {
  local unfixable_file="$1"
  if [ -f "$unfixable_file" ] && [ -s "$unfixable_file" ]; then
    cat "$unfixable_file"
  else
    echo '{"items":[]}'
  fi
}

# Filter out unfixable journey+mode combos from failures JSON.
# Args: failures_file unfixable_file output_file
fl_filter_unfixable() {
  local failures_file="$1"
  local unfixable_file="$2"
  local output_file="$3"

  python3 << FILTER_EOF > "$output_file"
import json

failures = json.load(open('$failures_file'))
try:
    unfixable = json.load(open('$unfixable_file'))
except (FileNotFoundError, json.JSONDecodeError):
    unfixable = {'items': []}

# Build set of unfixable (journey_id, mode) tuples
skip = set()
for item in unfixable.get('items', []):
    skip.add((item.get('journey_id', ''), item.get('mode', '')))

# Filter
for cluster_name, cluster_data in failures.get('clusters', {}).items():
    cluster_data['failures'] = [
        f for f in cluster_data['failures']
        if (f['journey_id'], f['mode']) not in skip
    ]

# Remove empty clusters
failures['clusters'] = {
    k: v for k, v in failures['clusters'].items()
    if v.get('failures')
}

print(json.dumps(failures, indent=2))
FILTER_EOF
}

# ── Stall detection ──────────────────────────────────────────────────────────

# Append metrics to history file and check for stall.
# Args: history_file iteration pass_count avg_score
# Outputs: "stalled" or "progressing"
fl_check_stall() {
  local history_file="$1"
  local iteration="$2"
  local pass_count="$3"
  local avg_score="$4"

  # Append to history
  echo "${iteration}|${pass_count}|${avg_score}" >> "$history_file"

  # Need at least 3 entries to detect stall (current + 2 previous)
  local lines
  lines=$(wc -l < "$history_file" | tr -d ' ')
  if [ "$lines" -lt 3 ]; then
    echo "progressing"
    return
  fi

  # Read last 3 entries
  python3 << STALL_EOF
import sys

lines = open('$history_file').readlines()
entries = []
for line in lines[-3:]:
    parts = line.strip().split('|')
    if len(parts) >= 3:
        entries.append((int(parts[0]), int(parts[1]), int(parts[2])))

if len(entries) < 3:
    print("progressing")
    sys.exit(0)

# Stall = current pass_count and avg_score are both <= the value from 2 iterations ago
curr_pass, curr_score = entries[2][1], entries[2][2]
prev_pass, prev_score = entries[0][1], entries[0][2]

if curr_pass <= prev_pass and curr_score <= prev_score:
    print("stalled")
else:
    print("progressing")
STALL_EOF
}

# ── Synthesis ────────────────────────────────────────────────────────────────

# Run the synthesis agent to produce per-cluster fix specs.
# Args: failures_file project_root output_file
fl_run_synthesis() {
  local failures_file="$1"
  local project_root="$2"
  local output_file="$3"

  local failures_json
  failures_json=$(cat "$failures_file")

  # Build the synthesis prompt
  local prompt_file
  prompt_file=$(mktemp /tmp/fix-synthesis-prompt.XXXXXX)

  cat > "$prompt_file" << 'SYNTH_STATIC_EOF'
You are a senior full-stack engineer diagnosing test failures in a cattle ERP web application. Your job is to analyze test feedback and produce precise fix specifications.

<context>
The application has:
- Frontend: React + TypeScript + Vite + MUI (frontend/src/)
- Backend: FastAPI + SQLAlchemy (backend/app/)
- Pages exist but some are not imported/routed in App.tsx
- Some API endpoints may be missing or returning errors
</context>

<instructions>
1. Read ALL failure data below
2. For each cluster, analyze the root cause pattern across all failing personas/journeys
3. Use the Read/Glob/Grep tools to examine the actual source files and confirm your diagnosis
4. Produce a JSON fix specification

Key patterns to look for:
- "page not found" / 404 / blank page → missing import or route in App.tsx
- "no nav link" / "cannot find menu item" → missing sidebar entry in App.tsx
- API errors (500, 404) → missing or broken backend endpoint
- Form not working → missing frontend form handler or API integration
- Permission denied → RBAC misconfiguration (mark as unfixable if complex)
</instructions>

<output_format>
Output ONLY valid JSON with this structure (no markdown fences, no explanation):
{
  "fix_specs": [
    {
      "cluster": "organizations",
      "diagnosis": "OrganizationForm and OrganizationSelector pages exist but are not imported or routed in App.tsx",
      "diagnosis_confidence": 0.95,
      "root_cause": "missing_import_and_route",
      "fixes": [
        {
          "fix_description": "Import OrganizationForm and add route /organizations/new in App.tsx",
          "files_to_modify": ["frontend/src/App.tsx"],
          "is_shared_file": true,
          "change_type": "add_import_and_route"
        }
      ],
      "unfixable": false,
      "needs_interrogation": false
    }
  ],
  "summary": "Brief summary of all diagnoses"
}

For each fix:
- diagnosis_confidence: 0.0-1.0 (set needs_interrogation=true if < 0.7)
- is_shared_file: true if file is in the shared list (App.tsx, api.ts, exchangeApi.ts, types/exchange.ts, main_complete.py, task_5_20260130_010555.py)
- unfixable: true if the fix requires infrastructure/external service changes
- If unfixable, add unfixable_reason (one of: third_party_integration, infrastructure, data_dependency, test_environment)
</output_format>
SYNTH_STATIC_EOF

  # Append dynamic data
  cat >> "$prompt_file" << SYNTH_DATA_EOF

<failure_data>
$failures_json
</failure_data>
SYNTH_DATA_EOF

  # Run synthesis agent with tool access for code inspection
  claude --dangerously-skip-permissions --print \
    --tools "Read,Glob,Grep" \
    --append-system-prompt "Output only valid JSON. No markdown fences. No explanation before or after." \
    -p "$(cat "$prompt_file")" \
    > "$output_file" 2>/dev/null || true

  rm -f "$prompt_file"

  # Clean output — extract JSON from potentially mixed output
  if [ -f "$output_file" ] && [ -s "$output_file" ]; then
    sed -i '/./,$!d' "$output_file"
    sed -i '/^```/d' "$output_file"

    # Extract just the JSON object (first { to last })
    python3 << EXTRACT_JSON_EOF
import re, sys

content = open('$output_file').read()

# Find the first { and last } to extract JSON
first_brace = content.find('{')
last_brace = content.rfind('}')

if first_brace >= 0 and last_brace > first_brace:
    json_str = content[first_brace:last_brace+1]
    # Validate it parses
    import json
    try:
        data = json.loads(json_str)
        if 'fix_specs' in data:
            with open('$output_file', 'w') as f:
                json.dump(data, f, indent=2)
            sys.exit(0)
    except json.JSONDecodeError:
        pass

sys.exit(1)
EXTRACT_JSON_EOF
  fi

  # Validate
  if ! python3 -c "import json; d=json.load(open('$output_file')); assert 'fix_specs' in d" 2>/dev/null; then
    fl_log_error "Synthesis produced invalid JSON"
    fl_log_error "Raw output (first 200 chars): $(head -c 200 "$output_file" 2>/dev/null)"
    return 1
  fi
  return 0
}

# ── Fix agent ────────────────────────────────────────────────────────────────

# Run a fix agent for a single cluster.
# Args: cluster fix_spec_json owned_files shared_files project_root output_file log_file
fl_run_fix_agent() {
  local cluster="$1"
  local fix_spec_json="$2"
  local owned_files="$3"
  local shared_files="$4"
  local project_root="$5"
  local output_file="$6"
  local log_file="$7"

  local prompt_file
  prompt_file=$(mktemp "/tmp/fix-agent-${cluster}.XXXXXX")

  cat > "$prompt_file" << FIXAGENT_STATIC_EOF
You are a developer fixing test failures in the "$cluster" feature cluster of a cattle ERP application.

<rules>
- You may freely modify OWNED files listed below
- For SHARED files: read them but do NOT modify them. Instead, describe the exact changes needed in your output JSON under shared_file_changes_needed
- Make minimal, targeted changes. Fix only what's broken
- Preserve existing code patterns and style
- Test your changes make sense by reading the files before and after
</rules>

<owned_files>
$owned_files
</owned_files>

<shared_files>
$shared_files
</shared_files>
FIXAGENT_STATIC_EOF

  cat >> "$prompt_file" << FIXAGENT_DATA_EOF

<fix_spec>
$fix_spec_json
</fix_spec>

<instructions>
1. Read the fix spec above
2. For each fix, read the target file(s) to understand current state
3. Apply fixes to owned files using Edit/Write tools
4. For shared files, describe exact changes (imports to add, routes to add, etc.)
5. Output a JSON summary as your final message
</instructions>

<output_format>
Your final output must be ONLY this JSON (no other text):
{
  "cluster": "$cluster",
  "fixes_applied": [
    {
      "file": "frontend/src/pages/SomeFile.tsx",
      "description": "Fixed missing handler for form submission",
      "lines_changed": 15
    }
  ],
  "shared_file_changes_needed": [
    {
      "file": "frontend/src/App.tsx",
      "change_type": "add_import_and_route",
      "description": "Import SomePage and add Route path=/some-page",
      "import_line": "import SomePage from './pages/SomePage';",
      "route_jsx": "<Route path=\"/some-page\" element={<SomePage />} />",
      "nav_entry": {
        "label": "Some Page",
        "path": "/some-page",
        "icon": "SomeIcon"
      }
    }
  ],
  "fixes_skipped": [],
  "notes": ""
}
</output_format>
FIXAGENT_DATA_EOF

  # Run the fix agent
  claude --dangerously-skip-permissions --print \
    --tools "Read,Edit,Write,Glob,Grep" \
    --append-system-prompt "You are a developer. Make targeted code fixes. Output only valid JSON as your final message." \
    -p "$(cat "$prompt_file")" \
    > "$output_file" 2>"$log_file" || true

  rm -f "$prompt_file"

  # Clean output — extract JSON
  if [ -f "$output_file" ] && [ -s "$output_file" ]; then
    sed -i '/./,$!d' "$output_file"
    sed -i '/^```/d' "$output_file"
    _fl_extract_json "$output_file" "cluster"
  fi
}

# Internal helper: extract JSON from mixed output.
# Args: file key_to_validate
_fl_extract_json() {
  local file="$1"
  local key="${2:-}"

  python3 << EXTRACT_JSON2_EOF || true
import json, sys

content = open('$file').read()
first_brace = content.find('{')
last_brace = content.rfind('}')

if first_brace >= 0 and last_brace > first_brace:
    json_str = content[first_brace:last_brace+1]
    try:
        data = json.loads(json_str)
        key = '$key'
        if not key or key in data:
            with open('$file', 'w') as f:
                json.dump(data, f, indent=2)
            sys.exit(0)
    except json.JSONDecodeError:
        pass
sys.exit(1)
EXTRACT_JSON2_EOF
}

# ── Merge agent ──────────────────────────────────────────────────────────────

# Run the merge agent to apply shared file changes from all fix agents.
# Args: work_dir project_root output_file
# work_dir should contain fix-result-{cluster}.json files
fl_run_merge_agent() {
  local work_dir="$1"
  local project_root="$2"
  local output_file="$3"

  # Collect all shared_file_changes_needed from fix results
  local all_changes
  all_changes=$(python3 << MERGE_COLLECT_EOF
import json, glob, os

changes = []
for f in sorted(glob.glob(os.path.join('$work_dir', 'fix-result-*.json'))):
    try:
        data = json.load(open(f))
        cluster = data.get('cluster', os.path.basename(f))
        for change in data.get('shared_file_changes_needed', []):
            change['from_cluster'] = cluster
            changes.append(change)
    except (json.JSONDecodeError, KeyError):
        continue

print(json.dumps(changes, indent=2))
MERGE_COLLECT_EOF
  )

  if [ -z "$all_changes" ] || [ "$all_changes" = "[]" ]; then
    fl_log "No shared file changes needed"
    echo '{"merged": [], "conflicts": []}' > "$output_file"
    return 0
  fi

  local prompt_file
  prompt_file=$(mktemp /tmp/fix-merge-prompt.XXXXXX)

  cat > "$prompt_file" << 'MERGE_STATIC_EOF'
You are a merge engineer. Multiple fix agents have described changes they need to shared files. Apply ALL of them, resolving any conflicts.

<rules>
- Read each shared file first to understand current state
- Apply all requested changes additively (imports, routes, API methods)
- For App.tsx: add imports at top, routes inside <Routes>, nav entries in sidebar
- For api.ts/exchangeApi.ts: add new API methods
- For main_complete.py: mount new routers
- If two agents request conflicting changes to the same line, prefer the one that adds more functionality
- Use Edit tool for targeted changes, not Write (to preserve existing code)
</rules>
MERGE_STATIC_EOF

  cat >> "$prompt_file" << MERGE_DATA_EOF

<changes_to_apply>
$all_changes
</changes_to_apply>

<instructions>
1. Read each target shared file
2. Apply all changes from all clusters
3. Verify the result compiles/makes sense
4. Output a summary JSON
</instructions>

<output_format>
Your final output must be ONLY this JSON:
{
  "merged": [
    {"file": "frontend/src/App.tsx", "changes_applied": 5, "from_clusters": ["organizations","deals"]}
  ],
  "conflicts": [],
  "notes": ""
}
</output_format>
MERGE_DATA_EOF

  claude --dangerously-skip-permissions --print \
    --tools "Read,Edit,Write,Glob,Grep" \
    --append-system-prompt "You are a merge engineer. Apply code changes precisely. Output only valid JSON as your final message." \
    -p "$(cat "$prompt_file")" \
    > "$output_file" 2>/dev/null || true

  rm -f "$prompt_file"

  # Clean output — extract JSON
  if [ -f "$output_file" ] && [ -s "$output_file" ]; then
    sed -i '/./,$!d' "$output_file"
    sed -i '/^```/d' "$output_file"
    _fl_extract_json "$output_file" "merged"
  fi
}
