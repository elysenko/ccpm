#!/bin/bash
# question-history.sh - Manage interrogation question history for revert functionality
#
# Usage:
#   source question-history.sh
#   qh_init <session_name>           # Initialize history file
#   qh_log <phase> <slot> <question> <options>  # Log a question
#   qh_get_last                      # Get last question
#   qh_get_previous                  # Get second-to-last question (for revert)
#   qh_revert                        # Remove last question, return previous
#   qh_get_count                     # Get total question count
#   qh_get_answer <index>            # Get answer for question at index
#   qh_set_answer <index> <answer>   # Set answer for question at index

set -e

# Global state
QH_SESSION_NAME=""
QH_HISTORY_FILE=""

# Initialize question history for a session
qh_init() {
  local session_name="$1"

  if [ -z "$session_name" ]; then
    echo "❌ Session name required" >&2
    return 1
  fi

  QH_SESSION_NAME="$session_name"
  local session_dir=".claude/ar/$session_name"
  QH_HISTORY_FILE="$session_dir/question-history.json"

  # Create session directory if needed
  mkdir -p "$session_dir"

  # Initialize history file if it doesn't exist
  if [ ! -f "$QH_HISTORY_FILE" ]; then
    cat > "$QH_HISTORY_FILE" << 'EOF'
{
  "session": "",
  "created": "",
  "questions": []
}
EOF
    # Update session name and created timestamp
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg s "$session_name" --arg c "$now" '.session = $s | .created = $c' "$QH_HISTORY_FILE" > "$tmp_file"
    mv "$tmp_file" "$QH_HISTORY_FILE"
  fi

  echo "$QH_HISTORY_FILE"
}

# Log a question to history
# Usage: qh_log <phase> <slot> <question_text> [options_json]
qh_log() {
  local phase="$1"
  local slot="$2"
  local question_text="$3"
  local options_json="${4:-[]}"

  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "❌ Question history not initialized. Call qh_init first." >&2
    return 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local index
  index=$(jq '.questions | length' "$QH_HISTORY_FILE")

  local tmp_file
  tmp_file=$(mktemp)

  # Add new question entry
  jq --arg phase "$phase" \
     --arg slot "$slot" \
     --arg text "$question_text" \
     --argjson opts "$options_json" \
     --arg ts "$now" \
     --argjson idx "$index" \
     '.questions += [{
       "index": $idx,
       "phase": $phase,
       "slot": $slot,
       "text": $text,
       "options": $opts,
       "answer": null,
       "timestamp": $ts
     }]' "$QH_HISTORY_FILE" > "$tmp_file"

  mv "$tmp_file" "$QH_HISTORY_FILE"
  echo "$index"
}

# Get the last question
qh_get_last() {
  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "❌ Question history not initialized" >&2
    return 1
  fi

  jq '.questions | last // empty' "$QH_HISTORY_FILE"
}

# Get the second-to-last question (for revert)
qh_get_previous() {
  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "❌ Question history not initialized" >&2
    return 1
  fi

  local count
  count=$(jq '.questions | length' "$QH_HISTORY_FILE")

  if [ "$count" -lt 2 ]; then
    echo "❌ No previous question to revert to" >&2
    return 1
  fi

  jq '.questions[-2]' "$QH_HISTORY_FILE"
}

# Revert to previous question (removes last question, returns previous)
qh_revert() {
  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "❌ Question history not initialized" >&2
    return 1
  fi

  local count
  count=$(jq '.questions | length' "$QH_HISTORY_FILE")

  if [ "$count" -lt 1 ]; then
    echo "❌ No questions to revert" >&2
    return 1
  fi

  # Get the question we're reverting to (will be displayed again)
  local previous_question=""
  if [ "$count" -ge 2 ]; then
    previous_question=$(jq '.questions[-2]' "$QH_HISTORY_FILE")
  fi

  # Remove the last question
  local tmp_file
  tmp_file=$(mktemp)
  jq 'del(.questions[-1])' "$QH_HISTORY_FILE" > "$tmp_file"
  mv "$tmp_file" "$QH_HISTORY_FILE"

  # Return the previous question (now last) for re-display
  if [ -n "$previous_question" ]; then
    echo "$previous_question"
  else
    echo "{}"
  fi
}

# Get total question count
qh_get_count() {
  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "0"
    return 0
  fi

  jq '.questions | length' "$QH_HISTORY_FILE"
}

# Get answer for question at index
qh_get_answer() {
  local index="$1"

  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "❌ Question history not initialized" >&2
    return 1
  fi

  jq --argjson idx "$index" '.questions[$idx].answer // empty' "$QH_HISTORY_FILE"
}

# Set answer for question at index
qh_set_answer() {
  local index="$1"
  local answer="$2"

  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "❌ Question history not initialized" >&2
    return 1
  fi

  local tmp_file
  tmp_file=$(mktemp)
  jq --argjson idx "$index" --arg ans "$answer" \
     '.questions[$idx].answer = $ans' "$QH_HISTORY_FILE" > "$tmp_file"
  mv "$tmp_file" "$QH_HISTORY_FILE"
}

# Get question at specific index
qh_get_at() {
  local index="$1"

  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "❌ Question history not initialized" >&2
    return 1
  fi

  jq --argjson idx "$index" '.questions[$idx] // empty' "$QH_HISTORY_FILE"
}

# Show full history (for debugging)
qh_show() {
  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "❌ Question history not initialized" >&2
    return 1
  fi

  echo "=== Question History: $QH_SESSION_NAME ==="
  echo ""

  local count
  count=$(jq '.questions | length' "$QH_HISTORY_FILE")

  if [ "$count" -eq 0 ]; then
    echo "No questions recorded yet."
    return 0
  fi

  jq -r '.questions[] | "[\(.index)] Phase: \(.phase) | Slot: \(.slot)\n    Q: \(.text | .[0:80])...\n    A: \(.answer // "pending")\n"' "$QH_HISTORY_FILE"
}

# Format question for display (re-ask after revert)
qh_format_for_display() {
  local question_json="$1"

  if [ -z "$question_json" ] || [ "$question_json" = "{}" ]; then
    echo ""
    return 0
  fi

  local phase
  phase=$(echo "$question_json" | jq -r '.phase')
  local text
  text=$(echo "$question_json" | jq -r '.text')
  local options
  options=$(echo "$question_json" | jq -r '.options')

  echo "**Phase: $phase**"
  echo ""
  echo "$text"

  # If options exist and not empty array
  if [ "$options" != "[]" ] && [ "$options" != "null" ]; then
    echo ""
    echo "$options" | jq -r '.[] | "| \(.label) | \(.description) |"' 2>/dev/null || true
  fi
}

# Export current slots state from history
qh_export_slots() {
  if [ -z "$QH_HISTORY_FILE" ] || [ ! -f "$QH_HISTORY_FILE" ]; then
    echo "{}"
    return 0
  fi

  # Build slots object from answered questions
  jq '[.questions | .[] | select(.answer != null) | {(.slot): .answer}] | add // {}' "$QH_HISTORY_FILE"
}

# CLI interface when run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "$1" in
    init)
      qh_init "$2"
      ;;
    log)
      qh_init "$2"
      qh_log "$3" "$4" "$5" "${6:-[]}"
      ;;
    last)
      qh_init "$2"
      qh_get_last
      ;;
    previous)
      qh_init "$2"
      qh_get_previous
      ;;
    revert)
      qh_init "$2"
      qh_revert
      ;;
    count)
      qh_init "$2"
      qh_get_count
      ;;
    answer)
      qh_init "$2"
      if [ -n "$4" ]; then
        qh_set_answer "$3" "$4"
      else
        qh_get_answer "$3"
      fi
      ;;
    show)
      qh_init "$2"
      qh_show
      ;;
    slots)
      qh_init "$2"
      qh_export_slots
      ;;
    *)
      echo "Question History Manager"
      echo ""
      echo "Usage: $0 <command> <session> [args...]"
      echo ""
      echo "Commands:"
      echo "  init <session>                    Initialize history for session"
      echo "  log <session> <phase> <slot> <q>  Log a question"
      echo "  last <session>                    Get last question"
      echo "  previous <session>                Get second-to-last question"
      echo "  revert <session>                  Revert to previous question"
      echo "  count <session>                   Get question count"
      echo "  answer <session> <idx> [answer]   Get/set answer at index"
      echo "  show <session>                    Show full history"
      echo "  slots <session>                   Export filled slots"
      ;;
  esac
fi
