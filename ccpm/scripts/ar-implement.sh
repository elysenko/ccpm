#!/bin/bash
# ar-implement.sh - Autonomous Recursive Implementation execution script
#
# This script provides database operations for the /ar:implement skill.
# It handles session management, node tracking, and PRD generation.
#
# Usage:
#   source .claude/scripts/ar-implement.sh
#   ar_create_session "inventory-sharing" "Add inventory sharing between organizations"
#   ar_add_node "$SESSION_NAME" "" "Database Schema" "Create sharing tables" "database"
#   ar_mark_atomic "$NODE_ID" 2 1.5 "backend/migrations/027.sql,backend/app/models/sharing.py"
#   ar_generate_prd "$NODE_ID" ".claude/prds/inventory-sharing-001.md" "inventory-sharing-001"
#   ar_complete_session "$SESSION_NAME" "all_atomic"

set -e

# Configuration
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
NAMESPACE="${NAMESPACE:-cattle-erp}"

# Termination limits
MAX_DEPTH="${AR_MAX_DEPTH:-6}"
MAX_ITERATIONS="${AR_MAX_ITERATIONS:-50}"
TIMEOUT_MINUTES="${AR_TIMEOUT_MINUTES:-30}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Database Connection (uses kubectl exec like feature_interrogate.sh)
# =============================================================================

# Load .env file to get database configuration
_ar_load_env() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(cd "$script_dir/../.." && pwd)"
    local env_file="$project_root/.env"

    if [ -f "$env_file" ]; then
        set -a
        source "$env_file"
        set +a
    fi
}

# Initialize database connection variables from .env
_ar_init_db_vars() {
    _ar_load_env

    # Use values from .env or fall back to defaults
    AR_K8S_NAMESPACE="${K8S_NAMESPACE:-cattle-erp}"
    AR_DB_USER="${DB_USER:-postgres}"
    AR_DB_PASSWORD="${DB_PASSWORD:-upj3RsNuqy}"

    # Database name: normalize hyphens to underscores (PostgreSQL convention)
    # .env may have "cattle-erp" but actual DB is "cattle_erp"
    local db_name="${DB_NAME:-cattle_erp}"
    AR_DB_NAME="${db_name//-/_}"

    # Pod name follows pattern: postgresql-{namespace}-0
    AR_DB_POD="postgresql-${AR_K8S_NAMESPACE}-0"
}

# Ensure variables are initialized
_ar_init_db_vars

# Execute SQL query and return result (single value, trimmed)
ar_query() {
    local sql="$1"
    PGPASSWORD="$AR_DB_PASSWORD" kubectl exec -n "$AR_K8S_NAMESPACE" "$AR_DB_POD" -- \
        psql -U "$AR_DB_USER" -d "$AR_DB_NAME" -t -c "$sql" 2>/dev/null | tr -d ' \n' || echo ""
}

# Execute SQL query and return multiple rows
ar_query_rows() {
    local sql="$1"
    PGPASSWORD="$AR_DB_PASSWORD" kubectl exec -n "$AR_K8S_NAMESPACE" "$AR_DB_POD" -- \
        psql -U "$AR_DB_USER" -d "$AR_DB_NAME" -t -c "$sql" 2>/dev/null || echo ""
}

# Execute SQL command (no return value)
ar_exec() {
    local sql="$1"
    PGPASSWORD="$AR_DB_PASSWORD" kubectl exec -n "$AR_K8S_NAMESPACE" "$AR_DB_POD" -- \
        psql -U "$AR_DB_USER" -d "$AR_DB_NAME" -c "$sql" > /dev/null 2>&1
}

# Execute SQL file
ar_exec_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cat "$file" | PGPASSWORD="$AR_DB_PASSWORD" kubectl exec -i -n "$AR_K8S_NAMESPACE" "$AR_DB_POD" -- \
            psql -U "$AR_DB_USER" -d "$AR_DB_NAME" > /dev/null 2>&1
    else
        echo -e "${RED}File not found: $file${NC}" >&2
        return 1
    fi
}

# =============================================================================
# Session Management
# =============================================================================

# Create a new decomposition session
# Returns: session_id
ar_create_session() {
    local session_name="$1"
    local original_request="$2"

    # Escape single quotes
    original_request="${original_request//\'/\'\'}"

    local session_id
    session_id=$(ar_query "SELECT create_decomposition_session('$session_name', '$original_request')")

    if [ -n "$session_id" ]; then
        echo -e "${GREEN}Created session: $session_name (ID: $session_id)${NC}" >&2
        echo "$session_id"
    else
        echo -e "${RED}Failed to create session${NC}" >&2
        return 1
    fi
}

# Get session status
ar_get_session_status() {
    local session_name="$1"

    ar_query "SELECT status FROM decomposition_sessions WHERE session_name = '$session_name'"
}

# Get session statistics
ar_get_session_stats() {
    local session_name="$1"

    ar_query_rows "SELECT total_nodes, leaf_nodes, max_depth, prds_generated, status FROM decomposition_sessions WHERE session_name = '$session_name'"
}

# Complete a session
ar_complete_session() {
    local session_name="$1"
    local termination_reason="$2"
    local status="${3:-completed}"

    ar_exec "SELECT complete_decomposition_session('$session_name', '$termination_reason', '$status')"

    echo -e "${GREEN}Session completed: $session_name ($termination_reason)${NC}" >&2
}

# =============================================================================
# Node Management
# =============================================================================

# Add a node to the decomposition tree
# Returns: node_id
ar_add_node() {
    local session_name="$1"
    local parent_id="$2"  # Empty string for root node
    local name="$3"
    local description="$4"
    local gap_type="${5:-other}"
    local research_query="${6:-}"
    local parent_context="${7:-}"        # Context summary from parent
    local codebase_context="${8:-}"      # JSON with codebase findings

    # Sanitize for SQL: escape quotes, remove newlines, truncate
    name="${name//\'/\'\'}"
    description="${description//\'/\'\'}"
    # Research query can be very long with special chars - truncate and sanitize
    research_query="${research_query:0:500}"  # Truncate to 500 chars
    research_query="${research_query//$'\n'/ }"  # Replace newlines with spaces
    research_query="${research_query//\'/\'\'}"  # Escape quotes
    research_query="${research_query//\\/\\\\}"  # Escape backslashes
    parent_context="${parent_context//$'\n'/ }"
    parent_context="${parent_context//\'/\'\'}"
    codebase_context="${codebase_context//\'/\'\'}"

    local parent_arg
    if [ -z "$parent_id" ] || [ "$parent_id" = "null" ]; then
        parent_arg="NULL"
    else
        parent_arg="$parent_id"
    fi

    # SQL function only takes 6 params: session_name, parent_id, name, description, gap_type, research_query
    local node_id
    node_id=$(ar_query "SELECT add_decomposition_node('$session_name', $parent_arg, '$name', '$description', '$gap_type', '$research_query')")

    if [ -n "$node_id" ]; then
        echo -e "${BLUE}  Added node: $name (ID: $node_id)${NC}" >&2
        echo "$node_id"
    else
        echo -e "${RED}Failed to add node: $name${NC}" >&2
        return 1
    fi
}

# Mark a node as atomic
ar_mark_atomic() {
    local node_id="$1"
    local estimated_files="$2"
    local estimated_hours="$3"
    local files_affected="$4"  # Comma-separated list
    local complexity="${5:-moderate}"

    # Convert comma-separated to PostgreSQL array
    local files_array
    if [ -n "$files_affected" ]; then
        files_array="ARRAY[$(echo "$files_affected" | sed "s/,/','/g" | sed "s/^/'/;s/$/'/")]"
    else
        files_array="ARRAY[]::TEXT[]"
    fi

    ar_exec "SELECT mark_node_atomic($node_id, $estimated_files, $estimated_hours, $files_array, '$complexity')"

    echo -e "${GREEN}  Marked atomic: node $node_id ($estimated_files files)${NC}" >&2
}

# Update node status
ar_update_node_status() {
    local node_id="$1"
    local status="$2"
    local reason="${3:-}"

    local reason_sql=""
    if [ -n "$reason" ]; then
        reason="${reason//\'/\'\'}"
        reason_sql=", decomposition_reason = '$reason'"
    fi

    ar_exec "UPDATE decomposition_nodes SET status = '$status'$reason_sql, updated_at = NOW() WHERE id = $node_id"
}

# Update node research summary
ar_update_node_research() {
    local node_id="$1"
    local research_summary="$2"

    research_summary="${research_summary//\'/\'\'}"

    ar_exec "UPDATE decomposition_nodes SET research_summary = '$research_summary', status = 'researching', updated_at = NOW() WHERE id = $node_id"
}

# Get pending nodes for decomposition
ar_get_pending_nodes() {
    local session_name="$1"

    ar_query_rows "SELECT id, name, layer, parent_id FROM get_pending_nodes('$session_name')"
}

# Get node details
ar_get_node() {
    local node_id="$1"

    ar_query_rows "SELECT id, name, description, layer, is_atomic, status, gap_type FROM decomposition_nodes WHERE id = $node_id"
}

# Get all atomic nodes for PRD generation
ar_get_atomic_nodes() {
    local session_name="$1"

    ar_query_rows "SELECT id, name, description, gap_type, estimated_files, files_affected, layer FROM decomposition_atomic_nodes WHERE session_name = '$session_name' AND status = 'atomic'"
}

# =============================================================================
# PRD Generation
# =============================================================================

# Record PRD generation for a node
ar_record_prd() {
    local node_id="$1"
    local prd_path="$2"
    local prd_name="$3"

    ar_exec "SELECT record_prd_generation($node_id, '$prd_path', '$prd_name')"

    echo -e "${GREEN}  Generated PRD: $prd_name${NC}" >&2
}

# Generate PRD content for a node
ar_generate_prd_content() {
    local session_name="$1"
    local node_id="$2"
    local prd_number="$3"

    # Get node details
    local node_data
    node_data=$(ar_query_rows "SELECT name, description, gap_type, estimated_files, estimated_hours, files_affected, layer, complexity FROM decomposition_nodes WHERE id = $node_id")

    # Parse node data
    local name description gap_type estimated_files estimated_hours files_affected layer complexity
    IFS='|' read -r name description gap_type estimated_files estimated_hours files_affected layer complexity <<< "$(echo "$node_data" | tr -d ' ' | head -1)"

    # Get current datetime
    local created_at
    created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Get parent PRD if exists
    local parent_prd
    parent_prd=$(ar_query "SELECT prd_name FROM decomposition_nodes WHERE id = (SELECT parent_id FROM decomposition_nodes WHERE id = $node_id)")

    # Build dependencies section
    local dependencies=""
    if [ -n "$parent_prd" ]; then
        dependencies="dependencies:
  - $parent_prd"
    fi

    # Build files section
    local files_section=""
    if [ -n "$files_affected" ] && [ "$files_affected" != "{}" ]; then
        # Parse PostgreSQL array format {file1,file2}
        files_affected="${files_affected#\{}"
        files_affected="${files_affected%\}}"
        files_section="### Files Affected
$(echo "$files_affected" | tr ',' '\n' | sed 's/^/- /')"
    fi

    # Generate PRD content
    cat << EOF
---
name: ${session_name}-$(printf "%03d" "$prd_number")
description: ${name}
status: backlog
created: ${created_at}
${dependencies}
---

# PRD: ${name}

## Executive Summary

${description}

## Problem Statement

Gap identified during recursive decomposition of "${session_name}".

- **Gap Type**: ${gap_type}
- **Layer**: ${layer}
- **Complexity**: ${complexity:-moderate}

## Requirements

### Functional Requirements

${description}

${files_section}

### Estimated Effort

- **Files**: ${estimated_files:-1-3}
- **Hours**: ${estimated_hours:-2-4}

## Success Criteria

- [ ] Implementation complete
- [ ] Tests passing
- [ ] Code reviewed

## Dependencies

$(if [ -n "$parent_prd" ]; then echo "- $parent_prd"; else echo "None"; fi)

---
Generated by /ar:implement
EOF
}

# =============================================================================
# Termination Checks
# =============================================================================

# Check if session should terminate
ar_should_terminate() {
    local session_name="$1"
    local start_time="$2"

    # Get current stats
    local stats
    stats=$(ar_get_session_stats "$session_name")

    local total_nodes max_depth
    total_nodes=$(echo "$stats" | cut -d'|' -f1 | tr -d ' ')
    max_depth=$(echo "$stats" | cut -d'|' -f3 | tr -d ' ')

    # Check max iterations
    if [ "${total_nodes:-0}" -ge "$MAX_ITERATIONS" ]; then
        echo "max_iterations"
        return 0
    fi

    # Check max depth
    if [ "${max_depth:-0}" -ge "$MAX_DEPTH" ]; then
        echo "max_depth"
        return 0
    fi

    # Check timeout
    local current_time elapsed_minutes
    current_time=$(date +%s)
    elapsed_minutes=$(( (current_time - start_time) / 60 ))

    if [ "$elapsed_minutes" -ge "$TIMEOUT_MINUTES" ]; then
        echo "timeout"
        return 0
    fi

    # Check if all nodes are atomic
    local pending_count
    pending_count=$(ar_query "SELECT COUNT(*) FROM decomposition_nodes WHERE session_name = '$session_name' AND is_atomic = FALSE AND status NOT IN ('skipped', 'failed')")

    if [ "${pending_count:-0}" -eq 0 ]; then
        echo "all_atomic"
        return 0
    fi

    echo ""
    return 1
}

# =============================================================================
# Gap Analysis Operations
# =============================================================================

# Update node with gap analysis results
ar_update_gap_analysis() {
    local node_id="$1"
    local gap_signals="$2"        # JSON: {"linguistic_score": 0.35, "slot_score": 0.65, ...}
    local slot_analysis="$3"      # JSON: {"goal": {...}, "trigger": {...}, ...}
    local auto_resolved="$4"      # Comma-separated: "pattern1,pattern2"
    local blocking="$5"           # Comma-separated: "gap1,gap2"
    local nice_to_know="$6"       # Comma-separated: "gap1,gap2"

    # Convert comma-separated to PostgreSQL arrays
    local auto_arr blocking_arr nice_arr

    if [ -n "$auto_resolved" ]; then
        auto_arr="ARRAY[$(echo "$auto_resolved" | sed "s/,/','/g" | sed "s/^/'/;s/$/'/" )]"
    else
        auto_arr="ARRAY[]::TEXT[]"
    fi

    if [ -n "$blocking" ]; then
        blocking_arr="ARRAY[$(echo "$blocking" | sed "s/,/','/g" | sed "s/^/'/;s/$/'/" )]"
    else
        blocking_arr="ARRAY[]::TEXT[]"
    fi

    if [ -n "$nice_to_know" ]; then
        nice_arr="ARRAY[$(echo "$nice_to_know" | sed "s/,/','/g" | sed "s/^/'/;s/$/'/" )]"
    else
        nice_arr="ARRAY[]::TEXT[]"
    fi

    # Escape JSON
    gap_signals="${gap_signals//\'/\'\'}"
    slot_analysis="${slot_analysis//\'/\'\'}"

    ar_exec "SELECT update_node_gap_analysis($node_id, '$gap_signals'::jsonb, '$slot_analysis'::jsonb, $auto_arr, $blocking_arr, $nice_arr)"

    echo -e "${BLUE}  Updated gap analysis: node $node_id${NC}" >&2
}

# Record a decision made during decomposition
ar_record_decision() {
    local node_id="$1"
    local decision="$2"
    local rationale="$3"

    decision="${decision//\'/\'\'}"
    rationale="${rationale//\'/\'\'}"

    ar_exec "SELECT record_node_decision($node_id, '$decision', '$rationale')"

    echo -e "${BLUE}  Recorded decision: $decision${NC}" >&2
}

# Get node with full context for agent handoff
ar_get_node_context() {
    local node_id="$1"

    ar_query_rows "SELECT * FROM get_node_with_context($node_id)"
}

# Get confidence score for a session (average across nodes)
ar_get_session_confidence() {
    local session_name="$1"

    ar_query "SELECT ROUND(AVG((gap_signals->>'confidence_score')::numeric), 2) FROM decomposition_nodes WHERE session_name = '$session_name' AND gap_signals IS NOT NULL"
}

# Get blocking gap count for a session
ar_get_blocking_gap_count() {
    local session_name="$1"

    ar_query "SELECT SUM(COALESCE(array_length(blocking_gaps, 1), 0)) FROM decomposition_nodes WHERE session_name = '$session_name'"
}

# Get auto-resolved gap count for a session
ar_get_auto_resolved_count() {
    local session_name="$1"

    ar_query "SELECT SUM(COALESCE(array_length(auto_resolved_gaps, 1), 0)) FROM decomposition_nodes WHERE session_name = '$session_name'"
}

# =============================================================================
# Audit Logging
# =============================================================================

# Log an action to the audit trail
ar_log_action() {
    local session_name="$1"
    local action="$2"
    local node_id="${3:-}"
    local details="${4:-{}}"
    local layer="${5:-}"

    local node_sql=""
    if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
        node_sql=", node_id = $node_id"
    fi

    local layer_sql=""
    if [ -n "$layer" ]; then
        layer_sql=", layer = $layer"
    fi

    # Escape details JSON
    details="${details//\'/\'\'}"

    ar_exec "INSERT INTO decomposition_audit_log (session_name, action, details$node_sql$layer_sql) VALUES ('$session_name', '$action', '$details'::jsonb)"
}

# =============================================================================
# Tree Visualization
# =============================================================================

# Print decomposition tree
ar_print_tree() {
    local session_name="$1"

    echo ""
    echo "=== Decomposition Tree: $session_name ==="

    # Get tree data
    local tree_sql="
        WITH RECURSIVE tree AS (
            SELECT id, name, layer, is_atomic, status, prd_name, 0 AS depth
            FROM decomposition_nodes
            WHERE session_name = '$session_name' AND parent_id IS NULL
            UNION ALL
            SELECT n.id, n.name, n.layer, n.is_atomic, n.status, n.prd_name, t.depth + 1
            FROM decomposition_nodes n
            JOIN tree t ON n.parent_id = t.id
            WHERE n.session_name = '$session_name'
        )
        SELECT REPEAT('  ', depth) || CASE WHEN is_atomic THEN '[A] ' ELSE '[-] ' END || name || ' (' || status || ')' || COALESCE(' -> ' || prd_name, '')
        FROM tree
        ORDER BY depth, id
    "

    ar_query_rows "$tree_sql" | while read -r line; do
        if [[ "$line" == *"[A]"* ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ "$line" == *"prd_generated"* ]]; then
            echo -e "${BLUE}$line${NC}"
        else
            echo "$line"
        fi
    done

    echo ""
}

# =============================================================================
# Initialization
# =============================================================================

# Initialize schema if needed
ar_init_schema() {
    local schema_script="$PROJECT_ROOT/.claude/ccpm/ccpm/scripts/create-decomposition-schema.sh"

    if [ -f "$schema_script" ]; then
        echo "Initializing decomposition schema..."
        bash "$schema_script"
    else
        echo -e "${YELLOW}Warning: Schema script not found at $schema_script${NC}" >&2
    fi
}

# Check if schema exists
ar_check_schema() {
    local exists
    exists=$(ar_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'decomposition_sessions'")

    if [ "${exists:-0}" -eq 0 ]; then
        echo -e "${RED}Decomposition schema not found. Run: .claude/ccpm/ccpm/scripts/create-decomposition-schema.sh${NC}" >&2
        return 1
    fi

    return 0
}

# =============================================================================
# Main Entry Point (when run directly)
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "AR Implement Execution Script"
    echo ""
    echo "Usage: source .claude/scripts/ar-implement.sh"
    echo ""
    echo "Functions available:"
    echo "  ar_create_session <name> <request>     - Create new session"
    echo "  ar_add_node <session> <parent> <name> <desc> [type] [query]  - Add node"
    echo "  ar_mark_atomic <node_id> <files> <hours> <file_list> [complexity]  - Mark atomic"
    echo "  ar_record_prd <node_id> <path> <name>  - Record PRD generation"
    echo "  ar_complete_session <name> <reason>    - Complete session"
    echo "  ar_print_tree <session>                - Print tree structure"
    echo "  ar_check_schema                        - Verify schema exists"
    echo ""

    # Check schema
    ar_check_schema || exit 1

    echo -e "${GREEN}Schema verified. Ready to use.${NC}"
fi
