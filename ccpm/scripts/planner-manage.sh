#!/bin/bash
# Planner Management Script
# Manage checklist sessions and items in PostgreSQL
#
# Usage: ./planner-manage.sh <command> [args]
#
# Commands:
#   list                    - List all planning sessions
#   view <session-name>     - View items in a session
#   update <item-id> <status> - Update item status
#   complete <item-id>      - Mark item as completed
#   new [session-name]      - Create a new planning session

set -e

# Database connection
db_query() {
  PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 -- \
    psql -U postgres -d cattle_erp -t -c "$1" 2>/dev/null
}

db_query_formatted() {
  PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 -- \
    psql -U postgres -d cattle_erp -c "$1" 2>/dev/null
}

# Valid statuses
VALID_STATUSES="pending in_progress blocked completed deferred cancelled"

show_usage() {
  cat << 'EOF'
Planner Management Script

Usage: ./planner-manage.sh <command> [args]

Commands:
  list                      List all planning sessions
  view <session-name>       View items in a session (or 'latest' for most recent)
  update <item-id> <status> Update item status
  complete <item-id>        Mark item as completed (shortcut)
  new [session-name]        Create a new planning session

Valid statuses: pending, in_progress, blocked, completed, deferred, cancelled

Examples:
  ./planner-manage.sh list
  ./planner-manage.sh view sprint-20260129-050131
  ./planner-manage.sh view latest
  ./planner-manage.sh update 5 in_progress
  ./planner-manage.sh complete 4
  ./planner-manage.sh new my-sprint
EOF
}

cmd_list() {
  echo "=== Planning Sessions ==="
  echo ""
  db_query_formatted "
    SELECT
      id,
      session_name,
      phase,
      total_items || '/' || completed_items AS \"items\",
      invest_pass_rate || '%' AS \"invest%\",
      TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI') AS created
    FROM checklist
    ORDER BY created_at DESC
    LIMIT 10;
  "
}

cmd_view() {
  local session="$1"

  if [ -z "$session" ]; then
    echo "❌ Session name required"
    echo "Usage: ./planner-manage.sh view <session-name>"
    exit 1
  fi

  # Handle 'latest' keyword
  if [ "$session" = "latest" ]; then
    session=$(db_query "SELECT session_name FROM checklist ORDER BY created_at DESC LIMIT 1;" | tr -d ' ')
    if [ -z "$session" ]; then
      echo "❌ No sessions found"
      exit 1
    fi
    echo "Using latest session: $session"
    echo ""
  fi

  # Check session exists
  local session_id=$(db_query "SELECT id FROM checklist WHERE session_name = '$session';" | tr -d ' ')
  if [ -z "$session_id" ]; then
    echo "❌ Session '$session' not found"
    exit 1
  fi

  echo "=== Session: $session ==="
  echo ""

  # Show session summary
  db_query_formatted "
    SELECT
      phase,
      total_items,
      completed_items,
      invest_pass_rate || '%' AS invest_pass_rate,
      estimated_points AS points
    FROM checklist
    WHERE session_name = '$session';
  "

  echo ""
  echo "=== Items ==="
  echo ""

  db_query_formatted "
    SELECT
      id,
      item_number AS \"#\",
      SUBSTRING(title, 1, 40) AS title,
      priority,
      status,
      CASE WHEN is_spike THEN 'Y' ELSE '' END AS spike,
      invest_total || '/30' AS invest,
      CASE WHEN invest_passed THEN '✓' ELSE '✗' END AS pass
    FROM checklist_item
    WHERE checklist_id = $session_id
    ORDER BY
      CASE priority
        WHEN 'must' THEN 1
        WHEN 'should' THEN 2
        WHEN 'could' THEN 3
        WHEN 'wont' THEN 4
      END,
      item_number;
  "
}

cmd_update() {
  local item_id="$1"
  local new_status="$2"

  if [ -z "$item_id" ] || [ -z "$new_status" ]; then
    echo "❌ Item ID and status required"
    echo "Usage: ./planner-manage.sh update <item-id> <status>"
    echo "Valid statuses: $VALID_STATUSES"
    exit 1
  fi

  # Validate status
  if ! echo "$VALID_STATUSES" | grep -qw "$new_status"; then
    echo "❌ Invalid status: $new_status"
    echo "Valid statuses: $VALID_STATUSES"
    exit 1
  fi

  # Check item exists
  local item_title=$(db_query "SELECT title FROM checklist_item WHERE id = $item_id;" | xargs)
  if [ -z "$item_title" ]; then
    echo "❌ Item $item_id not found"
    exit 1
  fi

  # Update status
  db_query "
    UPDATE checklist_item SET
      status = '$new_status',
      updated_at = NOW(),
      completed_at = CASE WHEN '$new_status' = 'completed' THEN NOW() ELSE completed_at END
    WHERE id = $item_id;
  "

  echo "✅ Updated item $item_id: '$item_title' → $new_status"

  # If completing a spike with parent, show hint
  if [ "$new_status" = "completed" ]; then
    local spike_info=$(db_query "
      SELECT is_spike, parent_item_id
      FROM checklist_item
      WHERE id = $item_id;
    ")
    local is_spike=$(echo "$spike_info" | awk '{print $1}' | tr -d ' ')
    local parent_id=$(echo "$spike_info" | awk '{print $3}' | tr -d ' ')

    if [ "$is_spike" = "t" ] && [ -n "$parent_id" ] && [ "$parent_id" != "" ]; then
      local parent_title=$(db_query "SELECT title FROM checklist_item WHERE id = $parent_id;" | xargs)
      echo ""
      echo "📋 This spike has parent task: '$parent_title' (id=$parent_id)"
      echo "   Consider running /pm:feature to implement the parent task."
    fi
  fi
}

cmd_complete() {
  local item_id="$1"

  if [ -z "$item_id" ]; then
    echo "❌ Item ID required"
    echo "Usage: ./planner-manage.sh complete <item-id>"
    exit 1
  fi

  cmd_update "$item_id" "completed"
}

cmd_new() {
  local session_name="$1"

  # Auto-generate name if not provided
  if [ -z "$session_name" ]; then
    session_name="sprint-$(date +%Y%m%d-%H%M%S)"
  fi

  # Check if session already exists
  local existing=$(db_query "SELECT id FROM checklist WHERE session_name = '$session_name';" | tr -d ' ')
  if [ -n "$existing" ]; then
    echo "❌ Session '$session_name' already exists (id=$existing)"
    exit 1
  fi

  # Create session directory
  local session_dir=".claude/planner/$session_name"
  mkdir -p "$session_dir"

  # Insert into database
  local new_id=$(db_query "
    INSERT INTO checklist (session_name, title, phase)
    VALUES ('$session_name', 'Sprint: $session_name', 'context')
    RETURNING id;
  " | tr -d ' ')

  # Create initial session.md
  local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$session_dir/session.md" << EOF
# Sprint Planning Session: $session_name

Started: $current_date
Phase: context

---

## Tasks Captured
(to be filled during session)

---

## Context
(gathered during Phase 1)

---

## Metrics
- Total Tasks: 0
- INVEST Pass Rate: 0%
- Story Points: 0
EOF

  echo "✅ Created new session: $session_name (id=$new_id)"
  echo ""
  echo "Session directory: $session_dir"
  echo "Database record created in 'checklist' table"
  echo ""
  echo "Next steps:"
  echo "  1. Run /pm:planner to continue the planning workflow"
  echo "  2. Or manually add items with SQL"
}

# Main command router
case "$1" in
  list)
    cmd_list
    ;;
  view)
    cmd_view "$2"
    ;;
  update)
    cmd_update "$2" "$3"
    ;;
  complete)
    cmd_complete "$2"
    ;;
  new)
    cmd_new "$2"
    ;;
  -h|--help|help)
    show_usage
    ;;
  *)
    if [ -n "$1" ]; then
      echo "❌ Unknown command: $1"
      echo ""
    fi
    show_usage
    exit 1
    ;;
esac
