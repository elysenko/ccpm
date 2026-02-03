#!/bin/bash
# Planner TUI - Interactive Task Management Interface
#
# Run without arguments - all actions handled through the UI.
#
# Key Commands (Main View):
#   ↑/k     Move up
#   ↓/j     Move down
#   Enter   View task details
#   n       New Task (6-phase wizard)
#   c       Mark complete
#   s       Change status
#   p       Change priority
#   a       Archive task
#   v       View archived tasks (toggle)
#   r       Refresh
#   S       Switch session / Filter
#   N       New session
#   q       Quit
#
# Key Commands (Task View):
#   i       INVEST scoring
#   w       W-Framework
#   s       Status
#   p       Priority
#   t       Split task (SPIDR)
#   e       Edit
#   f       Feature Interrogate (launch discovery pipeline)
#   r       Resume existing interrogate session
#   q       Back

# Don't use set -e - interactive reads can return non-zero
# set -e

# No command-line arguments accepted - purely interactive
if [ $# -gt 0 ]; then
  echo "Planner TUI - Interactive Task Management"
  echo ""
  echo "Usage: ./planner-tui.sh"
  echo ""
  echo "All actions are handled through the interactive interface."
  echo "Run without arguments to start."
  exit 0
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'
REVERSE='\033[7m'

# Status colors
status_color() {
  case "$1" in
    pending)     echo -e "${YELLOW}" ;;
    in_progress) echo -e "${BLUE}" ;;
    blocked)     echo -e "${RED}" ;;
    completed)   echo -e "${GREEN}" ;;
    deferred)    echo -e "${DIM}" ;;
    cancelled)   echo -e "${DIM}" ;;
    *)           echo -e "${RESET}" ;;
  esac
}

# Priority colors
priority_color() {
  case "$1" in
    must)   echo -e "${RED}${BOLD}" ;;
    should) echo -e "${YELLOW}" ;;
    could)  echo -e "${CYAN}" ;;
    wont)   echo -e "${DIM}" ;;
    *)      echo -e "${RESET}" ;;
  esac
}

# Database query
db_query() {
  PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 -- \
    psql -U postgres -d cattle_erp -t -A -F '|' -c "$1" 2>/dev/null
}

db_exec() {
  PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 -- \
    psql -U postgres -d cattle_erp -c "$1" 2>/dev/null
}

# Global state
CURRENT_SESSION="ALL"
CURRENT_SESSION_ID=""
SELECTED_INDEX=0
ITEMS=()
ITEM_IDS=()
VIEW_MODE="all"  # "all" or "session"
SHOW_ARCHIVED=false  # Toggle to show archived tasks

# Feature interrogate pipeline step count
TOTAL_PIPELINE_STEPS=14

# Get terminal size
get_term_size() {
  TERM_LINES=$(tput lines)
  TERM_COLS=$(tput cols)
}

# Hide/show cursor
hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }

# Move cursor
move_cursor() { printf '\033[%d;%dH' "$1" "$2"; }

# Clear screen
clear_screen() { printf '\033[2J\033[H'; }

# Load sessions list
load_sessions() {
  SESSIONS=$(db_query "SELECT session_name FROM checklist ORDER BY created_at DESC LIMIT 20;")
}

# Load current session
load_session() {
  if [ -z "$CURRENT_SESSION" ]; then
    CURRENT_SESSION=$(db_query "SELECT session_name FROM checklist ORDER BY created_at DESC LIMIT 1;")
  fi

  if [ -z "$CURRENT_SESSION" ]; then
    return 1
  fi

  CURRENT_SESSION_ID=$(db_query "SELECT id FROM checklist WHERE session_name = '$CURRENT_SESSION';")

  # Load session info
  SESSION_INFO=$(db_query "
    SELECT phase, total_items, completed_items, invest_pass_rate, estimated_points
    FROM checklist WHERE session_name = '$CURRENT_SESSION';
  ")

  SESSION_PHASE=$(echo "$SESSION_INFO" | cut -d'|' -f1)
  SESSION_TOTAL=$(echo "$SESSION_INFO" | cut -d'|' -f2)
  SESSION_COMPLETED=$(echo "$SESSION_INFO" | cut -d'|' -f3)
  SESSION_INVEST=$(echo "$SESSION_INFO" | cut -d'|' -f4)
  SESSION_POINTS=$(echo "$SESSION_INFO" | cut -d'|' -f5)
}

# Load items for current session or all sessions
load_items() {
  ITEMS=()
  ITEM_IDS=()

  # Set archive filter based on SHOW_ARCHIVED
  local archive_filter
  if [ "$SHOW_ARCHIVED" = true ]; then
    archive_filter="ci.archived = TRUE"
  else
    archive_filter="(ci.archived IS NULL OR ci.archived = FALSE)"
  fi

  local data
  if [ "$VIEW_MODE" = "all" ]; then
    # Load ALL items from ALL sessions
    data=$(db_query "
      SELECT
        ci.id,
        ci.item_number,
        COALESCE(ci.title, ''),
        COALESCE(ci.priority, ''),
        COALESCE(ci.status, 'pending'),
        CASE WHEN ci.is_spike THEN 'Y' ELSE '' END,
        COALESCE(ci.invest_total, 0),
        CASE WHEN ci.invest_passed THEN '✓' ELSE '✗' END,
        COALESCE(ci.task_type, ''),
        COALESCE(ci.implementation_approach, '')
      FROM checklist_item ci
      JOIN checklist c ON ci.checklist_id = c.id
      WHERE $archive_filter
      ORDER BY
        CASE ci.priority
          WHEN 'must' THEN 1
          WHEN 'should' THEN 2
          WHEN 'could' THEN 3
          WHEN 'wont' THEN 4
          ELSE 5
        END,
        CASE ci.status
          WHEN 'in_progress' THEN 1
          WHEN 'pending' THEN 2
          WHEN 'blocked' THEN 3
          WHEN 'completed' THEN 4
          WHEN 'deferred' THEN 5
          ELSE 6
        END,
        ci.item_number;
    ")
  else
    # Load items from specific session
    if [ -z "$CURRENT_SESSION_ID" ]; then
      return
    fi
    data=$(db_query "
      SELECT
        ci.id,
        ci.item_number,
        COALESCE(ci.title, ''),
        COALESCE(ci.priority, ''),
        COALESCE(ci.status, 'pending'),
        CASE WHEN ci.is_spike THEN 'Y' ELSE '' END,
        COALESCE(ci.invest_total, 0),
        CASE WHEN ci.invest_passed THEN '✓' ELSE '✗' END,
        COALESCE(ci.task_type, ''),
        COALESCE(ci.implementation_approach, '')
      FROM checklist_item ci
      JOIN checklist c ON ci.checklist_id = c.id
      WHERE ci.checklist_id = $CURRENT_SESSION_ID
        AND $archive_filter
      ORDER BY
        CASE ci.priority
          WHEN 'must' THEN 1
          WHEN 'should' THEN 2
          WHEN 'could' THEN 3
          WHEN 'wont' THEN 4
          ELSE 5
        END,
        ci.item_number;
    ")
  fi

  while IFS= read -r line; do
    if [ -n "$line" ]; then
      ITEMS+=("$line")
      ITEM_IDS+=("${line%%|*}")  # Extract ID before first pipe (faster than cut)
    fi
  done <<< "$data"
}

# Draw header
draw_header() {
  move_cursor 1 1
  printf "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"

  # Show archived indicator if viewing archived
  local archive_label=""
  if [ "$SHOW_ARCHIVED" = true ]; then
    archive_label=" ${YELLOW}[ARCHIVED]${RESET}"
  fi

  if [ "$VIEW_MODE" = "all" ]; then
    printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}PLANNER${RESET} │ View: ${GREEN}ALL SESSIONS${RESET}%s                          ${CYAN}║${RESET}\n" "$archive_label"
    printf "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}\n"
    # Get aggregate stats (respecting archive filter)
    local archive_filter
    if [ "$SHOW_ARCHIVED" = true ]; then
      archive_filter="archived = TRUE"
    else
      archive_filter="(archived IS NULL OR archived = FALSE)"
    fi
    local stats=$(db_query "SELECT COUNT(*), SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) FROM checklist_item WHERE $archive_filter;")
    local total_items=$(echo "$stats" | cut -d'|' -f1)
    local completed_items=$(echo "$stats" | cut -d'|' -f2)
    printf "${CYAN}║${RESET}  Total Tasks: ${WHITE}%-5s${RESET} │ Completed: ${GREEN}%-5s${RESET} │ ${DIM}Press 'S' to filter by session${RESET}  ${CYAN}║${RESET}\n" \
      "${total_items:-0}" "${completed_items:-0}"
  else
    printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}PLANNER${RESET} │ Session: ${YELLOW}%-30s${RESET}%s ${CYAN}║${RESET}\n" "${CURRENT_SESSION:-No session}" "$archive_label"
    printf "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}\n"
    if [ -n "$CURRENT_SESSION" ]; then
      printf "${CYAN}║${RESET}  Phase: ${GREEN}%-10s${RESET} │ Items: ${WHITE}%s/%s${RESET} │ INVEST: ${WHITE}%s%%${RESET} │ Points: ${WHITE}%s${RESET}     ${CYAN}║${RESET}\n" \
        "$SESSION_PHASE" "$SESSION_COMPLETED" "$SESSION_TOTAL" "${SESSION_INVEST:-0}" "${SESSION_POINTS:-0}"
    else
      printf "${CYAN}║${RESET}  ${DIM}No session loaded${RESET}                                                          ${CYAN}║${RESET}\n"
    fi
  fi
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n"
}

# Draw table header
draw_table_header() {
  move_cursor 6 1
  printf "${DIM}─────────────────────────────────────────────────────────────────────────────────${RESET}\n"
  printf " ${BOLD}%-3s │ %-20s │ %-6s │ %-4s │ %-6s │ %-9s │ %-5s${RESET}\n" \
    "ID" "Title" "Type" "Appr" "Prio" "Status" "INVST"
  printf "${DIM}─────────────────────────────────────────────────────────────────────────────────${RESET}\n"
}

# Abbreviate task type for display
abbrev_type() {
  case "$1" in
    user_story)   echo "story" ;;
    spike)        echo "spike" ;;
    tech_debt)    echo "debt" ;;
    bug_fix)      echo "bug" ;;
    enhancement)  echo "enh" ;;
    chore)        echo "chore" ;;
    *)            echo "-" ;;
  esac
}

# Abbreviate approach for display
abbrev_approach() {
  case "$1" in
    feature)       echo "feat" ;;
    troubleshoot)  echo "trbl" ;;
    quick_fix)     echo "qfix" ;;
    investigation) echo "invs" ;;
    *)             echo "-" ;;
  esac
}

# Abbreviate status for display
abbrev_status() {
  case "$1" in
    pending)     echo "pending" ;;
    in_progress) echo "in_prog" ;;
    blocked)     echo "blocked" ;;
    completed)   echo "done" ;;
    deferred)    echo "deferred" ;;
    cancelled)   echo "cancel" ;;
    *)           echo "$1" ;;
  esac
}

# Abbreviate priority for display
abbrev_priority() {
  case "$1" in
    must)   echo "must" ;;
    should) echo "shld" ;;
    could)  echo "cold" ;;
    wont)   echo "wont" ;;
    *)      echo "$1" ;;
  esac
}

# Draw items
draw_items() {
  local start_row=9
  local max_items=$((TERM_LINES - 14))
  local total=${#ITEMS[@]}

  # Calculate visible range
  local start_idx=0
  if [ $SELECTED_INDEX -ge $max_items ]; then
    start_idx=$((SELECTED_INDEX - max_items + 1))
  fi

  for ((i=0; i<max_items && i+start_idx<total; i++)); do
    local idx=$((i + start_idx))
    local item="${ITEMS[$idx]}"
    local row=$((start_row + i))

    move_cursor $row 1

    # Parse item fields using IFS for speed
    IFS='|' read -r id num title priority status spike invest pass task_type impl_approach <<< "$item"

    # Abbreviate fields for display
    local type_abbr=$(abbrev_type "$task_type")
    local appr_abbr=$(abbrev_approach "$impl_approach")
    local stat_abbr=$(abbrev_status "$status")
    local prio_abbr=$(abbrev_priority "$priority")

    # Truncate title
    title="${title:0:18}"
    [ -n "$spike" ] && title="⚡$title"

    # Check if this row is selected
    if [ $idx -eq $SELECTED_INDEX ]; then
      # Selected row - bright white background, black text
      printf "${BOLD}\033[30;47m"  # Black text on white background
      printf " %-3s │ %-20s │ %-6s │ %-4s │ %-6s │ %-9s │ %2s/30" \
        "$id" "$title" "$type_abbr" "$appr_abbr" "$prio_abbr" "$stat_abbr" "$invest"
      printf "${RESET}"
    else
      # Normal row with colors
      local pcolor=$(priority_color "$priority")
      local scolor=$(status_color "$status")
      printf " %-3s │ %-20s │ %-6s │ %-4s │ ${pcolor}%-6s${RESET} │ ${scolor}%-9s${RESET} │ %2s/30" \
        "$id" "$title" "$type_abbr" "$appr_abbr" "$prio_abbr" "$stat_abbr" "$invest"
    fi

    # Clear rest of line
    printf '\033[K\n'
  done

  # Clear remaining rows
  for ((i=total-start_idx; i<max_items; i++)); do
    move_cursor $((start_row + i)) 1
    printf '\033[K\n'
  done
}

# Draw footer with key commands
draw_footer() {
  local footer_row=$((TERM_LINES - 4))

  move_cursor $footer_row 1
  printf "${DIM}─────────────────────────────────────────────────────────────────────────────────${RESET}\n"
  if [ "$SHOW_ARCHIVED" = true ]; then
    printf " ${BOLD}Keys:${RESET} ${CYAN}↑↓${RESET} Navigate │ ${CYAN}Enter${RESET} View │ ${CYAN}a${RESET} Unarchive │ ${CYAN}v${RESET} Active Tasks │ ${CYAN}r${RESET} Refresh │ ${CYAN}q${RESET} Quit\n"
  else
    printf " ${BOLD}Keys:${RESET} ${CYAN}↑↓${RESET} Navigate │ ${CYAN}Enter${RESET} View │ ${CYAN}n${RESET} New │ ${CYAN}c${RESET} Complete │ ${CYAN}s${RESET} Status │ ${CYAN}a${RESET} Archive\n"
    printf "       ${CYAN}p${RESET} Priority │ ${CYAN}v${RESET} Archived │ ${CYAN}S${RESET} Filter │ ${CYAN}N${RESET} New Session │ ${CYAN}r${RESET} Refresh │ ${CYAN}q${RESET} Quit\n"
  fi
  printf "${DIM}─────────────────────────────────────────────────────────────────────────────────${RESET}"
}

# Draw message
draw_message() {
  local msg="$1"
  local color="${2:-$WHITE}"
  local msg_row=$((TERM_LINES - 5))

  move_cursor $msg_row 1
  printf '\033[K'
  printf " ${color}%s${RESET}" "$msg"
}

# Clear message
clear_message() {
  local msg_row=$((TERM_LINES - 5))
  move_cursor $msg_row 1
  printf '\033[K'
}

# Full redraw
redraw() {
  get_term_size
  clear_screen
  draw_header
  draw_table_header
  draw_items
  draw_footer
}

# Read single key
read_key() {
  local key=""
  local extra=""

  IFS= read -rsn1 key 2>/dev/null || return 0

  # Handle Enter key (empty string from read -n1)
  if [[ -z "$key" ]]; then
    echo "ENTER"
    return
  fi

  # Handle escape sequences (arrows)
  if [[ $key == $'\x1b' ]]; then
    # Read the bracket
    IFS= read -rsn1 -t 0.1 extra 2>/dev/null || true
    if [[ $extra == '[' ]]; then
      # Read the actual key code
      IFS= read -rsn1 -t 0.1 extra 2>/dev/null || true
      case "$extra" in
        'A') echo "UP" ;;
        'B') echo "DOWN" ;;
        'C') echo "RIGHT" ;;
        'D') echo "LEFT" ;;
        *)   echo "ESC" ;;
      esac
    else
      echo "ESC"
    fi
  else
    echo "$key"
  fi
}

# Prompt for input
prompt_input() {
  local prompt="$1"
  local default="$2"
  local input=""

  show_cursor
  draw_message "$prompt"
  move_cursor $((TERM_LINES - 5)) $((${#prompt} + 3))

  read -r input 2>/dev/null || true
  hide_cursor

  echo "${input:-$default}"
}

# Select from menu
select_menu() {
  local title="$1"
  shift
  local options=("$@")
  local selected=0
  local count=${#options[@]}

  # Hide cursor during menu display
  printf '\033[?25l' > /dev/tty

  while true; do
    # Clear screen and move cursor to top-left
    printf '\033[2J\033[H' > /dev/tty
    # Also clear scrollback to prevent ghosting
    printf '\033[3J' > /dev/tty

    printf "\n ${BOLD}${CYAN}%s${RESET}\n\n" "$title" > /dev/tty

    for ((i=0; i<count; i++)); do
      if [ $i -eq $selected ]; then
        printf " ${REVERSE} %s ${RESET}\n" "${options[$i]}" > /dev/tty
      else
        printf "   %s\n" "${options[$i]}" > /dev/tty
      fi
    done

    printf "\n ${DIM}↑↓ to select, Enter to confirm, q to cancel${RESET}" > /dev/tty
    # Flush output
    printf '' > /dev/tty

    local key
    key=$(read_key)

    case "$key" in
      UP|k)
        [ $selected -gt 0 ] && selected=$((selected - 1))
        ;;
      DOWN|j)
        [ $selected -lt $((count - 1)) ] && selected=$((selected + 1))
        ;;
      ENTER|""|$'\n'|$'\r')
        printf '\033[?25h' > /dev/tty  # Show cursor
        echo "$selected"
        return 0
        ;;
      q|Q)
        printf '\033[?25h' > /dev/tty  # Show cursor
        echo "-1"
        return 1
        ;;
    esac
  done
}

# Action: New task (quick)
action_new_task() {
  local target_session_id

  # If in ALL mode, ask which session to add to
  if [ "$VIEW_MODE" = "all" ]; then
    load_sessions
    local session_list=()
    while IFS= read -r s; do
      [ -n "$s" ] && session_list+=("$s")
    done <<< "$SESSIONS"

    if [ ${#session_list[@]} -eq 0 ]; then
      draw_message "No sessions - create one first with 'N'" "$YELLOW"
      return
    fi

    local session_idx=$(select_menu "Add task to which session?" "${session_list[@]}")
    [ "$session_idx" = "-1" ] && return

    local selected_session="${session_list[$session_idx]}"
    target_session_id=$(db_query "SELECT id FROM checklist WHERE session_name = '$selected_session';")
  else
    target_session_id="$CURRENT_SESSION_ID"
  fi

  show_cursor
  clear_screen
  printf "\n ${BOLD}${CYAN}Create New Task${RESET}\n\n"

  printf " Title: "
  read -r title

  if [ -z "$title" ]; then
    hide_cursor
    return
  fi

  printf " Description (optional): "
  read -r description

  # Select priority
  hide_cursor
  local priorities=("must" "should" "could" "wont")
  local priority_idx=$(select_menu "Select Priority" "${priorities[@]}")
  [ "$priority_idx" = "-1" ] && return
  local priority="${priorities[$priority_idx]}"

  # Get next item number
  local next_num=$(db_query "
    SELECT COALESCE(MAX(item_number), 0) + 1
    FROM checklist_item WHERE checklist_id = $target_session_id;
  ")

  # Insert task
  db_exec "
    INSERT INTO checklist_item (checklist_id, item_number, title, description, priority, status, source)
    VALUES ($target_session_id, $next_num, '${title//\'/\'\'}', '${description//\'/\'\'}', '$priority', 'pending', 'user_added');
  " > /dev/null

  load_items
  draw_message "Created task: $title" "$GREEN"
}

# Action: New Task Wizard (guided 6-phase flow)
action_wizard() {
  local target_session_id

  # If in ALL mode, ask which session to add to
  if [ "$VIEW_MODE" = "all" ]; then
    load_sessions
    local session_list=()
    while IFS= read -r s; do
      [ -n "$s" ] && session_list+=("$s")
    done <<< "$SESSIONS"

    if [ ${#session_list[@]} -eq 0 ]; then
      draw_message "No sessions - create one first with 'N'" "$YELLOW"
      return
    fi

    local session_idx=$(select_menu "Add task to which session?" "${session_list[@]}")
    [ "$session_idx" = "-1" ] && return

    local selected_session="${session_list[$session_idx]}"
    target_session_id=$(db_query "SELECT id FROM checklist WHERE session_name = '$selected_session';")
  else
    target_session_id="$CURRENT_SESSION_ID"
  fi

  show_cursor
  clear_screen

  # ═══════════════════════════════════════════════════════════════════════════════
  # Phase 1: Basic Info
  # ═══════════════════════════════════════════════════════════════════════════════
  printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}NEW TASK WIZARD${RESET} │ Phase 1/6: Basic Info                               ${CYAN}║${RESET}\n"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

  printf " ${BOLD}Title${RESET} (required): "
  read -r title
  if [ -z "$title" ]; then
    hide_cursor
    return
  fi

  # Select task type
  hide_cursor
  local task_types=("User Story - Feature with user value" "Spike - Time-boxed investigation" "Tech Debt - Refactoring/cleanup" "Bug Fix - Defect correction" "Enhancement - Improve existing feature" "Chore - Routine maintenance")
  local type_idx=$(select_menu "Select Task Type" "${task_types[@]}")
  [ "$type_idx" = "-1" ] && return

  local task_type=""
  local is_spike="false"
  local tags=""
  case $type_idx in
    0) task_type="user_story"; tags='["feature"]' ;;
    1) task_type="spike"; is_spike="true"; tags='["spike"]' ;;
    2) task_type="tech_debt"; tags='["tech-debt"]' ;;
    3) task_type="bug_fix"; tags='["bug"]' ;;
    4) task_type="enhancement"; tags='["enhancement"]' ;;
    5) task_type="chore"; tags='["chore"]' ;;
  esac

  show_cursor
  clear_screen
  printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}NEW TASK WIZARD${RESET} │ Phase 1/6: Basic Info                               ${CYAN}║${RESET}\n"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

  printf " ${DIM}Title: %s${RESET}\n" "$title"
  printf " ${DIM}Type: %s${RESET}\n\n" "$task_type"

  printf " ${BOLD}Description${RESET} (multi-line, empty line to finish):\n"
  local description=""
  while true; do
    printf "   "
    read -r line
    [ -z "$line" ] && break
    [ -n "$description" ] && description="$description\n"
    description="${description}${line}"
  done

  # ═══════════════════════════════════════════════════════════════════════════════
  # Phase 2: User Story Format (if applicable)
  # ═══════════════════════════════════════════════════════════════════════════════
  local us_role="" us_goal="" us_benefit=""

  if [ "$task_type" = "user_story" ]; then
    clear_screen
    printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}NEW TASK WIZARD${RESET} │ Phase 2/6: User Story Format                        ${CYAN}║${RESET}\n"
    printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

    printf " ${DIM}Complete the user story template:${RESET}\n\n"

    printf " As a ${BOLD}[role]${RESET}: "
    read -r us_role

    printf " I want ${BOLD}[goal]${RESET}: "
    read -r us_goal

    printf " So that ${BOLD}[benefit]${RESET}: "
    read -r us_benefit
  fi

  # Spike-specific fields
  local spike_question="" spike_timebox=""

  if [ "$is_spike" = "true" ]; then
    clear_screen
    printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}NEW TASK WIZARD${RESET} │ Phase 2/6: Spike Details                            ${CYAN}║${RESET}\n"
    printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

    printf " ${BOLD}Investigation Question${RESET} (what are we trying to learn?):\n   "
    read -r spike_question

    printf "\n ${BOLD}Timebox${RESET} (e.g., 2h, 4h, 1d): "
    read -r spike_timebox
  fi

  # ═══════════════════════════════════════════════════════════════════════════════
  # Phase 3: W-Framework (optional)
  # ═══════════════════════════════════════════════════════════════════════════════
  clear_screen
  printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}NEW TASK WIZARD${RESET} │ Phase 3/6: W-Framework (Enter to skip)              ${CYAN}║${RESET}\n"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

  printf " ${DIM}Answer these to clarify scope (all optional):${RESET}\n\n"

  printf " ${BOLD}Who${RESET} is affected? "
  read -r who_affected

  printf " ${BOLD}What${RESET} is the outcome? "
  read -r what_outcome

  printf " ${BOLD}Why${RESET} is this important? "
  read -r why_important

  printf " ${BOLD}When${RESET} is this needed? "
  read -r when_needed

  printf " ${BOLD}Where${RESET} does this apply? "
  read -r where_applies

  printf " ${BOLD}How${RESET} will we verify? "
  read -r how_verified

  # ═══════════════════════════════════════════════════════════════════════════════
  # Phase 4: INVEST Scoring
  # ═══════════════════════════════════════════════════════════════════════════════
  clear_screen
  printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}NEW TASK WIZARD${RESET} │ Phase 4/6: INVEST Scoring                           ${CYAN}║${RESET}\n"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

  printf " ${DIM}Score each criterion 1-5 (Enter to skip all):${RESET}\n\n"

  local i_ind="" i_neg="" i_val="" i_est="" i_sml="" i_tst=""

  printf " ${BOLD}I${RESET}ndependent (1=dependent, 5=standalone) [1-5]: "
  read -r i_ind
  [[ ! "$i_ind" =~ ^[1-5]$ ]] && i_ind=""

  if [ -n "$i_ind" ]; then
    printf " ${BOLD}N${RESET}egotiable  (1=rigid, 5=flexible)       [1-5]: "
    read -r i_neg
    [[ ! "$i_neg" =~ ^[1-5]$ ]] && i_neg=""

    printf " ${BOLD}V${RESET}aluable    (1=tech only, 5=user value) [1-5]: "
    read -r i_val
    [[ ! "$i_val" =~ ^[1-5]$ ]] && i_val=""

    printf " ${BOLD}E${RESET}stimable   (1=unknown, 5=clear scope)  [1-5]: "
    read -r i_est
    [[ ! "$i_est" =~ ^[1-5]$ ]] && i_est=""

    printf " ${BOLD}S${RESET}mall       (1=epic, 5=hours)           [1-5]: "
    read -r i_sml
    [[ ! "$i_sml" =~ ^[1-5]$ ]] && i_sml=""

    printf " ${BOLD}T${RESET}estable    (1=no criteria, 5=explicit) [1-5]: "
    read -r i_tst
    [[ ! "$i_tst" =~ ^[1-5]$ ]] && i_tst=""
  fi

  # Calculate INVEST total
  local invest_total=0
  [ -n "$i_ind" ] && invest_total=$((invest_total + i_ind))
  [ -n "$i_neg" ] && invest_total=$((invest_total + i_neg))
  [ -n "$i_val" ] && invest_total=$((invest_total + i_val))
  [ -n "$i_est" ] && invest_total=$((invest_total + i_est))
  [ -n "$i_sml" ] && invest_total=$((invest_total + i_sml))
  [ -n "$i_tst" ] && invest_total=$((invest_total + i_tst))

  local invest_passed="false"
  [ $invest_total -ge 18 ] && invest_passed="true"

  if [ $invest_total -gt 0 ]; then
    printf "\n ${BOLD}INVEST Total:${RESET} %d/30 - " "$invest_total"
    if [ "$invest_passed" = "true" ]; then
      printf "${GREEN}PASS${RESET}\n"
    else
      printf "${RED}FAIL${RESET}\n"
      printf " ${YELLOW}Tip: Consider splitting this task or creating a spike first${RESET}\n"
    fi
    sleep 1
  fi

  # ═══════════════════════════════════════════════════════════════════════════════
  # Phase 5: Priority & Estimation
  # ═══════════════════════════════════════════════════════════════════════════════
  hide_cursor
  local priorities=("must - Must have (critical)" "should - Should have (important)" "could - Could have (nice to have)" "wont - Won't have this time")
  local priority_idx=$(select_menu "Phase 5/6: Select MoSCoW Priority" "${priorities[@]}")
  [ "$priority_idx" = "-1" ] && return

  local priority=""
  case $priority_idx in
    0) priority="must" ;;
    1) priority="should" ;;
    2) priority="could" ;;
    3) priority="wont" ;;
  esac

  local story_points=("1 - Trivial" "2 - Simple" "3 - Moderate" "5 - Complex" "8 - Very Complex" "13 - Epic-sized" "21 - Split this!")
  local points_idx=$(select_menu "Story Points (Fibonacci)" "${story_points[@]}")
  [ "$points_idx" = "-1" ] && return

  local story_pts=""
  case $points_idx in
    0) story_pts=1 ;;
    1) story_pts=2 ;;
    2) story_pts=3 ;;
    3) story_pts=5 ;;
    4) story_pts=8 ;;
    5) story_pts=13 ;;
    6) story_pts=21 ;;
  esac

  local complexities=("trivial - Minutes of work" "simple - Straightforward, few files" "moderate - Multiple components" "complex - Many unknowns, cross-cutting")
  local complexity_idx=$(select_menu "Complexity Level" "${complexities[@]}")
  [ "$complexity_idx" = "-1" ] && return

  local complexity=""
  case $complexity_idx in
    0) complexity="trivial" ;;
    1) complexity="simple" ;;
    2) complexity="moderate" ;;
    3) complexity="complex" ;;
  esac

  # Determine implementation_approach based on task_type and complexity
  # Logic from plan:
  #   user_story + complex/moderate → feature
  #   user_story + trivial → quick_fix
  #   spike → investigation
  #   tech_debt + complex → feature
  #   tech_debt + simple → troubleshoot
  #   bug_fix → troubleshoot
  #   enhancement + complex → feature
  #   enhancement + simple → troubleshoot
  #   chore → quick_fix
  local impl_approach=""
  case "$task_type" in
    user_story)
      if [ "$complexity" = "trivial" ]; then
        impl_approach="quick_fix"
      else
        impl_approach="feature"
      fi
      ;;
    spike)
      impl_approach="investigation"
      ;;
    tech_debt)
      if [ "$complexity" = "complex" ]; then
        impl_approach="feature"
      else
        impl_approach="troubleshoot"
      fi
      ;;
    bug_fix)
      impl_approach="troubleshoot"
      ;;
    enhancement)
      if [ "$complexity" = "complex" ]; then
        impl_approach="feature"
      else
        impl_approach="troubleshoot"
      fi
      ;;
    chore)
      impl_approach="quick_fix"
      ;;
  esac

  # ═══════════════════════════════════════════════════════════════════════════════
  # Phase 6: Save
  # ═══════════════════════════════════════════════════════════════════════════════
  show_cursor
  clear_screen
  printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}NEW TASK WIZARD${RESET} │ Phase 6/6: Review & Save                            ${CYAN}║${RESET}\n"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

  printf " ${BOLD}Summary:${RESET}\n"
  printf " ────────────────────────────────────────────────\n"
  printf " Title:      %s\n" "$title"
  printf " Type:       %s\n" "$task_type"
  printf " Approach:   %s\n" "$impl_approach"
  printf " Priority:   %s\n" "$priority"
  printf " Points:     %s\n" "$story_pts"
  printf " Complexity: %s\n" "$complexity"
  [ $invest_total -gt 0 ] && printf " INVEST:     %d/30 (%s)\n" "$invest_total" "$([ "$invest_passed" = "true" ] && echo "PASS" || echo "FAIL")"
  [ -n "$us_role" ] && printf " User Story: As a %s, I want %s...\n" "$us_role" "$us_goal"
  [ -n "$spike_question" ] && printf " Spike Q:    %s\n" "$spike_question"
  printf " ────────────────────────────────────────────────\n\n"

  printf " Save this task? (Y/n): "
  read -r confirm
  hide_cursor

  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    draw_message "Task creation cancelled" "$YELLOW"
    return
  fi

  # Get next item number
  local next_num=$(db_query "
    SELECT COALESCE(MAX(item_number), 0) + 1
    FROM checklist_item WHERE checklist_id = $target_session_id;
  ")

  # Build the INSERT query with all fields (now including task_type and implementation_approach)
  local sql="INSERT INTO checklist_item (
    checklist_id, item_number, title, description, priority, status, source,
    task_type, implementation_approach,
    is_spike, story_points, complexity, tags,
    user_story_role, user_story_goal, user_story_benefit,
    who_affected, what_outcome, why_important, when_needed, where_applies, how_verified,
    spike_question, spike_timebox"

  # Add INVEST fields if populated
  if [ -n "$i_ind" ]; then
    sql="$sql, invest_independent, invest_negotiable, invest_valuable, invest_estimable, invest_small, invest_testable"
  fi

  sql="$sql) VALUES (
    $target_session_id, $next_num, '${title//\'/\'\'}', '${description//\'/\'\'}', '$priority', 'pending', 'wizard',
    '$task_type', '$impl_approach',
    $is_spike, $story_pts, '$complexity', '$tags',
    '${us_role//\'/\'\'}', '${us_goal//\'/\'\'}', '${us_benefit//\'/\'\'}',
    '${who_affected//\'/\'\'}', '${what_outcome//\'/\'\'}', '${why_important//\'/\'\'}', '${when_needed//\'/\'\'}', '${where_applies//\'/\'\'}', '${how_verified//\'/\'\'}',
    '${spike_question//\'/\'\'}', '${spike_timebox//\'/\'\'}')"

  if [ -n "$i_ind" ]; then
    # Remove the closing paren and add INVEST values
    sql="${sql%)*}, ${i_ind:-0}, ${i_neg:-0}, ${i_val:-0}, ${i_est:-0}, ${i_sml:-0}, ${i_tst:-0})"
  fi

  db_exec "$sql" > /dev/null

  # Get the ID of the newly created task
  local new_task_id=$(db_query "
    SELECT id FROM checklist_item
    WHERE checklist_id = $target_session_id
    AND item_number = $next_num;
  ")

  load_items

  # If this is a feature-type task, offer to start the feature pipeline immediately
  if [ "$impl_approach" = "feature" ] && [ -n "$new_task_id" ]; then
    show_cursor
    clear_screen
    printf "\n${BOLD}${GREEN}✓ Task #%s created: %s${RESET}\n\n" "$new_task_id" "$title"
    printf " Implementation approach: ${BOLD}feature${RESET} (full pipeline)\n\n"
    printf " ${BOLD}Start Feature Pipeline now?${RESET}\n"
    printf " This will launch the 9-step feature interrogation process.\n\n"
    printf " [Y] Yes - Start now  [N] No - I'll start later\n\n"
    printf " Choice: "
    read -rsn1 start_choice
    hide_cursor

    if [[ "$start_choice" =~ ^[Yy]$ ]]; then
      view_action_feature_interrogate_full "$new_task_id" "$title"
      return
    fi
  fi

  draw_message "Created task #$new_task_id: $title" "$GREEN"
}

# Action: Change status
action_change_status() {
  if [ ${#ITEMS[@]} -eq 0 ]; then
    draw_message "No tasks to update" "$YELLOW"
    return
  fi

  local item_id="${ITEM_IDS[$SELECTED_INDEX]}"
  local statuses=("pending" "in_progress" "blocked" "completed" "deferred" "cancelled")

  local status_idx=$(select_menu "Select Status for Task #$item_id" "${statuses[@]}")
  [ "$status_idx" = "-1" ] && return
  local new_status="${statuses[$status_idx]}"

  db_exec "
    UPDATE checklist_item SET
      status = '$new_status',
      updated_at = NOW(),
      completed_at = CASE WHEN '$new_status' = 'completed' THEN NOW() ELSE completed_at END
    WHERE id = $item_id;
  " > /dev/null

  load_items
  draw_message "Status updated to: $new_status" "$GREEN"
}

# Action: Change priority
action_change_priority() {
  if [ ${#ITEMS[@]} -eq 0 ]; then
    draw_message "No tasks to update" "$YELLOW"
    return
  fi

  local item_id="${ITEM_IDS[$SELECTED_INDEX]}"
  local priorities=("must" "should" "could" "wont")

  local priority_idx=$(select_menu "Select Priority for Task #$item_id" "${priorities[@]}")
  [ "$priority_idx" = "-1" ] && return
  local new_priority="${priorities[$priority_idx]}"

  db_exec "
    UPDATE checklist_item SET
      priority = '$new_priority',
      updated_at = NOW()
    WHERE id = $item_id;
  " > /dev/null

  load_items
  draw_message "Priority updated to: $new_priority" "$GREEN"
}

# Action: Mark complete
action_complete() {
  if [ ${#ITEMS[@]} -eq 0 ]; then
    draw_message "No tasks to complete" "$YELLOW"
    return
  fi

  local item_id="${ITEM_IDS[$SELECTED_INDEX]}"

  db_exec "
    UPDATE checklist_item SET
      status = 'completed',
      completed_at = NOW(),
      updated_at = NOW()
    WHERE id = $item_id;
  " > /dev/null

  load_items
  draw_message "Task #$item_id marked complete" "$GREEN"
}

# Action: Archive/Unarchive task
action_archive() {
  if [ ${#ITEMS[@]} -eq 0 ]; then
    draw_message "No tasks to archive" "$YELLOW"
    return
  fi

  local item_id="${ITEM_IDS[$SELECTED_INDEX]}"

  if [ "$SHOW_ARCHIVED" = true ]; then
    # We're viewing archived tasks - unarchive
    db_exec "UPDATE checklist_item SET archived = FALSE, archived_at = NULL, updated_at = NOW() WHERE id = $item_id;" > /dev/null
    load_items
    [ $SELECTED_INDEX -ge ${#ITEMS[@]} ] && SELECTED_INDEX=$((SELECTED_INDEX - 1))
    [ $SELECTED_INDEX -lt 0 ] && SELECTED_INDEX=0
    draw_message "Task #$item_id unarchived" "$GREEN"
  else
    # Normal view - archive the task
    db_exec "UPDATE checklist_item SET archived = TRUE, archived_at = NOW(), updated_at = NOW() WHERE id = $item_id;" > /dev/null
    load_items
    [ $SELECTED_INDEX -ge ${#ITEMS[@]} ] && SELECTED_INDEX=$((SELECTED_INDEX - 1))
    [ $SELECTED_INDEX -lt 0 ] && SELECTED_INDEX=0
    draw_message "Task #$item_id archived" "$GREEN"
  fi
}

# Action: Toggle archived view
action_toggle_archived() {
  if [ "$SHOW_ARCHIVED" = true ]; then
    SHOW_ARCHIVED=false
    draw_message "Showing active tasks" "$GREEN"
  else
    SHOW_ARCHIVED=true
    draw_message "Showing archived tasks" "$YELLOW"
  fi
  SELECTED_INDEX=0
  load_items
}

# Action: Switch session / Toggle view mode
action_switch_session() {
  load_sessions

  # Add "ALL SESSIONS" option at the top
  local session_list=("ALL SESSIONS")
  while IFS= read -r s; do
    [ -n "$s" ] && session_list+=("$s")
  done <<< "$SESSIONS"

  if [ ${#session_list[@]} -eq 1 ]; then
    draw_message "No sessions found" "$YELLOW"
    return
  fi

  local session_idx=$(select_menu "Select View" "${session_list[@]}")
  [ "$session_idx" = "-1" ] && return

  if [ "$session_idx" = "0" ]; then
    # All sessions view
    VIEW_MODE="all"
    CURRENT_SESSION="ALL"
    CURRENT_SESSION_ID=""
  else
    # Specific session view
    VIEW_MODE="session"
    CURRENT_SESSION="${session_list[$session_idx]}"
    load_session
  fi

  SELECTED_INDEX=0
  load_items
}

# Action: New session
action_new_session() {
  local name=$(prompt_input "Session name (blank for auto): ")

  if [ -z "$name" ]; then
    name="sprint-$(date +%Y%m%d-%H%M%S)"
  fi

  # Check if exists
  local existing=$(db_query "SELECT id FROM checklist WHERE session_name = '$name';")
  if [ -n "$existing" ]; then
    draw_message "Session '$name' already exists" "$RED"
    return
  fi

  # Create session
  db_exec "
    INSERT INTO checklist (session_name, title, phase)
    VALUES ('$name', 'Sprint: $name', 'context');
  " > /dev/null

  # Create directory
  mkdir -p ".claude/planner/$name"

  # Create session.md
  cat > ".claude/planner/$name/session.md" << EOF
# Sprint Planning Session: $name

Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Phase: context

---

## Tasks Captured
(to be filled during session)

---

## Metrics
- Total Tasks: 0
- INVEST Pass Rate: 0%
- Story Points: 0
EOF

  CURRENT_SESSION="$name"
  SELECTED_INDEX=0
  load_session
  load_items
  draw_message "Created session: $name" "$GREEN"
}

# Action: View task details
action_view_task() {
  if [ ${#ITEMS[@]} -eq 0 ]; then
    draw_message "No tasks to view" "$YELLOW"
    return
  fi

  local item_id="${ITEM_IDS[$SELECTED_INDEX]}"

  # Fetch full task details with parent title in single query
  # Replace newlines with <NL> marker to allow proper parsing
  local details=$(db_query "
    SELECT
      ci.id,
      REPLACE(ci.title, E'\n', '<NL>'),
      REPLACE(COALESCE(ci.description, ''), E'\n', '<NL>'),
      ci.priority,
      ci.status,
      ci.is_spike,
      ci.invest_independent,
      ci.invest_negotiable,
      ci.invest_valuable,
      ci.invest_estimable,
      ci.invest_small,
      ci.invest_testable,
      ci.invest_total,
      ci.invest_passed,
      REPLACE(COALESCE(ci.who_affected, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.what_outcome, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.why_important, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.when_needed, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.where_applies, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.how_verified, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.user_story_role, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.user_story_goal, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.user_story_benefit, ''), E'\n', '<NL>'),
      ci.spidr_type,
      ci.parent_item_id,
      REPLACE(COALESCE(ci.split_reason, ''), E'\n', '<NL>'),
      ci.story_points,
      ci.complexity,
      ci.acceptance_criteria,
      REPLACE(COALESCE(ci.definition_of_done, ''), E'\n', '<NL>'),
      ci.blocked_by,
      ci.blocks,
      REPLACE(COALESCE(ci.external_dependencies, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.spike_question, ''), E'\n', '<NL>'),
      ci.spike_timebox,
      ci.feature_session,
      REPLACE(COALESCE(ci.notes, ''), E'\n', '<NL>'),
      ci.source,
      ci.assigned_to,
      c.session_name,
      TO_CHAR(ci.created_at, 'YYYY-MM-DD HH24:MI'),
      TO_CHAR(ci.updated_at, 'YYYY-MM-DD HH24:MI'),
      TO_CHAR(ci.completed_at, 'YYYY-MM-DD HH24:MI'),
      ci.task_type,
      ci.implementation_approach,
      ci.feature_step,
      REPLACE(COALESCE(ci.feature_step_name, ''), E'\n', '<NL>'),
      parent.title,
      ci.feature_branch,
      COALESCE(ci.feature_sub_step, 0)
    FROM checklist_item ci
    JOIN checklist c ON ci.checklist_id = c.id
    LEFT JOIN checklist_item parent ON ci.parent_item_id = parent.id
    WHERE ci.id = $item_id;
  ")

  # Parse fields using cut (now safe since newlines are replaced with <NL>)
  local title=$(echo "$details" | cut -d'|' -f2 | sed 's/<NL>/\n/g')
  local description=$(echo "$details" | cut -d'|' -f3 | sed 's/<NL>/\n/g')
  local priority=$(echo "$details" | cut -d'|' -f4)
  local status=$(echo "$details" | cut -d'|' -f5)
  local is_spike=$(echo "$details" | cut -d'|' -f6)
  local i_ind=$(echo "$details" | cut -d'|' -f7)
  local i_neg=$(echo "$details" | cut -d'|' -f8)
  local i_val=$(echo "$details" | cut -d'|' -f9)
  local i_est=$(echo "$details" | cut -d'|' -f10)
  local i_sml=$(echo "$details" | cut -d'|' -f11)
  local i_tst=$(echo "$details" | cut -d'|' -f12)
  local i_tot=$(echo "$details" | cut -d'|' -f13)
  local i_pass=$(echo "$details" | cut -d'|' -f14)
  local who=$(echo "$details" | cut -d'|' -f15 | sed 's/<NL>/\n/g')
  local what=$(echo "$details" | cut -d'|' -f16 | sed 's/<NL>/\n/g')
  local why=$(echo "$details" | cut -d'|' -f17 | sed 's/<NL>/\n/g')
  local when=$(echo "$details" | cut -d'|' -f18 | sed 's/<NL>/\n/g')
  local where=$(echo "$details" | cut -d'|' -f19 | sed 's/<NL>/\n/g')
  local how=$(echo "$details" | cut -d'|' -f20 | sed 's/<NL>/\n/g')
  local us_role=$(echo "$details" | cut -d'|' -f21 | sed 's/<NL>/\n/g')
  local us_goal=$(echo "$details" | cut -d'|' -f22 | sed 's/<NL>/\n/g')
  local us_benefit=$(echo "$details" | cut -d'|' -f23 | sed 's/<NL>/\n/g')
  local spidr_type=$(echo "$details" | cut -d'|' -f24)
  local parent_id=$(echo "$details" | cut -d'|' -f25)
  local split_reason=$(echo "$details" | cut -d'|' -f26 | sed 's/<NL>/\n/g')
  local story_points=$(echo "$details" | cut -d'|' -f27)
  local complexity=$(echo "$details" | cut -d'|' -f28)
  local acceptance=$(echo "$details" | cut -d'|' -f29)
  local dod=$(echo "$details" | cut -d'|' -f30 | sed 's/<NL>/\n/g')
  local blocked_by=$(echo "$details" | cut -d'|' -f31)
  local blocks=$(echo "$details" | cut -d'|' -f32)
  local ext_deps=$(echo "$details" | cut -d'|' -f33 | sed 's/<NL>/\n/g')
  local spike_q=$(echo "$details" | cut -d'|' -f34 | sed 's/<NL>/\n/g')
  local spike_tb=$(echo "$details" | cut -d'|' -f35)
  local feature_sess=$(echo "$details" | cut -d'|' -f36)
  local notes=$(echo "$details" | cut -d'|' -f37 | sed 's/<NL>/\n/g')
  local source=$(echo "$details" | cut -d'|' -f38)
  local assigned=$(echo "$details" | cut -d'|' -f39)
  local session=$(echo "$details" | cut -d'|' -f40)
  local created=$(echo "$details" | cut -d'|' -f41)
  local updated=$(echo "$details" | cut -d'|' -f42)
  local completed_at=$(echo "$details" | cut -d'|' -f43)
  local task_type=$(echo "$details" | cut -d'|' -f44)
  local impl_approach=$(echo "$details" | cut -d'|' -f45)
  local feature_step=$(echo "$details" | cut -d'|' -f46)
  local feature_step_name=$(echo "$details" | cut -d'|' -f47 | sed 's/<NL>/\n/g')
  local parent_title=$(echo "$details" | cut -d'|' -f48)
  local feature_branch=$(echo "$details" | cut -d'|' -f49)
  local feature_sub_step=$(echo "$details" | cut -d'|' -f50)

  # Get child tasks (if any)
  local children=$(db_query "SELECT id, title, status FROM checklist_item WHERE parent_item_id = $item_id;")

  # Display
  clear_screen
  show_cursor

  printf "\n${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}\n"
  printf "${BOLD}${WHITE} TASK #%s: %s${RESET}\n" "$item_id" "$title"
  printf "${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}\n\n"

  # Basic Info
  printf "${BOLD}Basic Info${RESET}\n"
  printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
  printf " Session:    ${YELLOW}%s${RESET}\n" "$session"
  printf " Status:     $(status_color "$status")%s${RESET}\n" "$status"
  printf " Priority:   $(priority_color "$priority")%s${RESET}\n" "$priority"
  [ -n "$task_type" ] && printf " Type:       %s\n" "$task_type"
  if [ -n "$impl_approach" ]; then
    local approach_hint=""
    case "$impl_approach" in
      feature)       approach_hint="→ Use /pm:feature or /pm:interrogate" ;;
      troubleshoot)  approach_hint="→ Use /pm:troubleshoot" ;;
      quick_fix)     approach_hint="→ Edit and implement directly" ;;
      investigation) approach_hint="→ Time-boxed spike investigation" ;;
    esac
    printf " Approach:   ${CYAN}%s${RESET} ${DIM}%s${RESET}\n" "$impl_approach" "$approach_hint"
  fi
  [ -n "$story_points" ] && printf " Points:     %s\n" "$story_points"
  [ -n "$complexity" ] && printf " Complexity: %s\n" "$complexity"
  [ -n "$assigned" ] && printf " Assigned:   %s\n" "$assigned"
  printf " Source:     %s\n" "$source"
  printf " Created:    %s\n" "$created"
  printf " Updated:    %s\n" "$updated"
  [ -n "$completed_at" ] && printf " Completed:  ${GREEN}%s${RESET}\n" "$completed_at"

  # Description
  if [ -n "$description" ]; then
    printf "\n${BOLD}Description${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf " %s\n" "$description"
  fi

  # Spike Info
  if [ "$is_spike" = "t" ]; then
    printf "\n${BOLD}${MAGENTA}⚡ Spike Info${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    [ -n "$spike_q" ] && printf " Question:   %s\n" "$spike_q"
    [ -n "$spike_tb" ] && printf " Timebox:    %s\n" "$spike_tb"
  fi

  # INVEST Scores
  if [ -n "$i_tot" ] && [ "$i_tot" != "0" ]; then
    printf "\n${BOLD}INVEST Scores${RESET} (%s/30 - %s)\n" "$i_tot" "$([ "$i_pass" = "t" ] && echo "${GREEN}PASS${RESET}" || echo "${RED}FAIL${RESET}")"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf " Independent: %s/5  │  Negotiable: %s/5  │  Valuable:  %s/5\n" "${i_ind:-0}" "${i_neg:-0}" "${i_val:-0}"
    printf " Estimable:   %s/5  │  Small:      %s/5  │  Testable:  %s/5\n" "${i_est:-0}" "${i_sml:-0}" "${i_tst:-0}"
  fi

  # W-Framework
  if [ -n "$who" ] || [ -n "$what" ] || [ -n "$why" ]; then
    printf "\n${BOLD}W-Framework${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    [ -n "$who" ] && printf " ${CYAN}Who:${RESET}   %s\n" "$who"
    [ -n "$what" ] && printf " ${CYAN}What:${RESET}  %s\n" "$what"
    [ -n "$why" ] && printf " ${CYAN}Why:${RESET}   %s\n" "$why"
    [ -n "$when" ] && printf " ${CYAN}When:${RESET}  %s\n" "$when"
    [ -n "$where" ] && printf " ${CYAN}Where:${RESET} %s\n" "$where"
    [ -n "$how" ] && printf " ${CYAN}How:${RESET}   %s\n" "$how"
  fi

  # User Story
  if [ -n "$us_role" ] || [ -n "$us_goal" ]; then
    printf "\n${BOLD}User Story${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf " As a ${CYAN}%s${RESET}\n" "${us_role:-...}"
    printf " I want ${CYAN}%s${RESET}\n" "${us_goal:-...}"
    printf " So that ${CYAN}%s${RESET}\n" "${us_benefit:-...}"
  fi

  # Parent/Child Relationships
  if [ -n "$parent_id" ] && [ "$parent_id" != "" ]; then
    printf "\n${BOLD}Parent Task${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf " #%s: %s\n" "$parent_id" "$parent_title"
    [ -n "$spidr_type" ] && printf " Split Type: %s\n" "$spidr_type"
    [ -n "$split_reason" ] && printf " Reason:     %s\n" "$split_reason"
  fi

  if [ -n "$children" ]; then
    printf "\n${BOLD}Child Tasks${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    while IFS='|' read -r cid ctitle cstatus; do
      [ -n "$cid" ] && printf " #%s: %s $(status_color "$cstatus")[%s]${RESET}\n" "$cid" "$ctitle" "$cstatus"
    done <<< "$children"
  fi

  # Dependencies
  if [ "$blocked_by" != "[]" ] || [ "$blocks" != "[]" ] || [ -n "$ext_deps" ]; then
    printf "\n${BOLD}Dependencies${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    [ "$blocked_by" != "[]" ] && printf " Blocked by: %s\n" "$blocked_by"
    [ "$blocks" != "[]" ] && printf " Blocks:     %s\n" "$blocks"
    [ -n "$ext_deps" ] && printf " External:   %s\n" "$ext_deps"
  fi

  # Acceptance Criteria
  if [ "$acceptance" != "[]" ] && [ -n "$acceptance" ]; then
    printf "\n${BOLD}Acceptance Criteria${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf " %s\n" "$acceptance"
  fi

  # Definition of Done
  if [ -n "$dod" ]; then
    printf "\n${BOLD}Definition of Done${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf " %s\n" "$dod"
  fi

  # Feature/Interrogate Session Link
  if [ -n "$feature_sess" ]; then
    printf "\n${BOLD}Interrogate Session${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf " Session: ${GREEN}%s${RESET}\n" "$feature_sess"
    [ -n "$feature_branch" ] && printf " Branch:  ${CYAN}%s${RESET}\n" "$feature_branch"

    # Detect actual step from files (more accurate than database)
    local research_dir=".claude/RESEARCH/${feature_sess}"
    if [ -d "$research_dir" ]; then
      feature_step=0
      feature_step_name=""
      [ -f "$research_dir/repo-analysis.md" ] && feature_step=1 && feature_step_name="Repo Analysis"
      [ -f "$research_dir/feature-input.md" ] && feature_step=2 && feature_step_name="Feature Input"
      [ -f "$research_dir/research-output.md" ] && feature_step=3 && feature_step_name="Context Research"
      [ -f "$research_dir/refined-requirements.md" ] && feature_step=4 && feature_step_name="Refinement"
      [ -f "$research_dir/implementation-research.md" ] && feature_step=5 && feature_step_name="Impl Research"
      [ -f "$research_dir/conversation-summary.md" ] && feature_step=6 && feature_step_name="Summary"
      [ -f "$research_dir/flow-diagram.md" ] && feature_step=7 && feature_step_name="Flow Diagram"
      [ -f "$research_dir/scope-synced.txt" ] && feature_step=8 && feature_step_name="Database Sync"
      [ -f "$research_dir/schema-complete.txt" ] && feature_step=9 && feature_step_name="Data Schema"
      [ -f "$research_dir/migration-complete.txt" ] && feature_step=10 && feature_step_name="Run Migration"
      [ -f "$research_dir/models-integrated.txt" ] && feature_step=11 && feature_step_name="Integrate Models"
      [ -f "$research_dir/api-generated.txt" ] && feature_step=12 && feature_step_name="API Generation"
      [ -f "$research_dir/journeys-generated.txt" ] && feature_step=13 && feature_step_name="Journey Generation"
      [ -f "$research_dir/frontend-complete.txt" ] && feature_step=14 && feature_step_name="Frontend Gen"
    fi

    # Show feature step if tracked
    if [ -n "$feature_step" ] && [ "$feature_step" != "" ] && [ "$feature_step" != "0" ]; then
      local step_color="$WHITE"
      if [ "$feature_step" -ge 7 ]; then
        step_color="$GREEN"      # Late stages (7+)
      elif [ "$feature_step" -ge 4 ]; then
        step_color="$CYAN"       # Mid stages (4-6)
      else
        step_color="$YELLOW"     # Early stages (1-3)
      fi
      printf " Step:    ${step_color}%s/${TOTAL_PIPELINE_STEPS}${RESET}" "$feature_step"
      [ -n "$feature_step_name" ] && printf " - %s" "$feature_step_name"
      printf "\n"
    fi

    # Check session status
    local sess_status=$(check_interrogate_status "$feature_sess")
    case "$sess_status" in
      complete)
        printf " Status:  ${GREEN}Complete${RESET} - Results available\n"
        printf " Files:   .claude/RESEARCH/%s/\n" "$feature_sess"
        ;;
      in_progress)
        printf " Status:  ${YELLOW}In Progress${RESET} - Press 'R' to resume\n"
        ;;
      started)
        printf " Status:  ${CYAN}Started${RESET} - Press 'R' to continue\n"
        ;;
      not_found)
        printf " Status:  ${DIM}Directory not found${RESET}\n"
        ;;
    esac
  fi

  # Notes
  if [ -n "$notes" ]; then
    printf "\n${BOLD}Notes${RESET}\n"
    printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
    printf " %s\n" "$notes"
  fi

  printf "\n${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}\n"
  # Show contextual actions based on task type and session state
  local is_feature_task=""
  [ -n "$feature_sess" ] || [ "$impl_approach" = "feature" ] || [ "$task_type" = "user_story" ] && is_feature_task="1"

  if [ -n "$feature_sess" ]; then
    # Has active session - show full feature options with delete
    printf "${BOLD}Actions:${RESET} ${CYAN}i${RESET} INVEST │ ${CYAN}w${RESET} W-Framework │ ${CYAN}p${RESET} Priority │ ${CYAN}t${RESET} Split │ ${CYAN}e${RESET} Edit\n"
    if [ "$status" != "completed" ]; then
      printf "         ${CYAN}f${RESET} Feature │ ${CYAN}r${RESET} Resume │ ${RED}d${RESET} Delete Progress │ ${CYAN}ESC/q${RESET} Back\n"
    else
      printf "         ${CYAN}f${RESET} Feature │ ${RED}d${RESET} Delete Progress │ ${CYAN}ESC/q${RESET} Back\n"
    fi
  elif [ -n "$is_feature_task" ]; then
    # Feature-type task but no session yet
    printf "${BOLD}Actions:${RESET} ${CYAN}i${RESET} INVEST │ ${CYAN}w${RESET} W-Framework │ ${CYAN}p${RESET} Priority │ ${CYAN}t${RESET} Split │ ${CYAN}e${RESET} Edit\n"
    printf "         ${CYAN}f${RESET} Feature │ ${CYAN}ESC/q${RESET} Back\n"
  else
    # Regular task
    printf "${BOLD}Actions:${RESET} ${CYAN}i${RESET} INVEST │ ${CYAN}w${RESET} W-Framework │ ${CYAN}p${RESET} Priority │ ${CYAN}t${RESET} Split │ ${CYAN}e${RESET} Edit\n"
    printf "         ${CYAN}f${RESET} Interrogate │ ${CYAN}ESC/q${RESET} Back\n"
  fi
  printf "${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}\n"

  # Action loop
  while true; do
    local action
    IFS= read -rsn1 action 2>/dev/null || break

    case "$action" in
      i)
        view_action_invest "$item_id"
        hide_cursor
        return
        ;;
      w)
        view_action_wframework "$item_id"
        hide_cursor
        return
        ;;
      p)
        view_action_priority "$item_id"
        hide_cursor
        return
        ;;
      t)
        view_action_split "$item_id" "$title"
        hide_cursor
        return
        ;;
      e)
        view_action_edit "$item_id"
        hide_cursor
        return
        ;;
      f)
        # Feature status for feature-type tasks, or start interrogate for others
        if [ -n "$feature_sess" ] || [ "$impl_approach" = "feature" ] || [ "$task_type" = "user_story" ]; then
          view_action_feature_status "$item_id" "$feature_sess" "$feature_step" "$feature_step_name" "$status" "$feature_sub_step"
        else
          view_action_interrogate "$item_id" "$title"
        fi
        hide_cursor
        return
        ;;
      r)
        # Only allow resume if task is not completed and has interrogate session
        if [ "$status" != "completed" ] && [ -n "$feature_sess" ]; then
          show_cursor
          view_action_resume_interrogate "$item_id" "$feature_sess"
          hide_cursor
          return
        fi
        ;;
      d)
        # Delete feature progress (only if feature_session exists)
        if [ -n "$feature_sess" ]; then
          show_cursor
          # Get branch name for display
          local feature_branch=$(db_query "SELECT feature_branch FROM checklist_item WHERE id = $item_id;")
          printf "\n${RED}${BOLD}Delete all feature progress?${RESET}\n"
          printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"
          printf "This will:\n"
          [ -n "$feature_branch" ] && printf "  • Delete branch: ${CYAN}%s${RESET}\n" "$feature_branch"
          printf "  • Remove session: ${CYAN}%s${RESET}\n" "$feature_sess"
          printf "  • Delete all session artifacts\n"
          printf "  • Reset task to pending\n\n"
          printf "${RED}Type 'DELETE' to confirm: ${RESET}"
          read -r confirm
          if [ "$confirm" = "DELETE" ]; then
            printf "\n"
            delete_feature_progress "$item_id"
            printf "\n${DIM}Press any key to continue...${RESET}"
            read -rsn1
            hide_cursor
            load_items
            return
          else
            printf "${YELLOW}Cancelled${RESET}\n"
            sleep 1
          fi
          hide_cursor
          return
        else
          printf "\n${YELLOW}No feature session to delete${RESET}\n"
          sleep 1
          return
        fi
        ;;
      q|$'\x1b')
        hide_cursor
        return
        ;;
    esac
  done

  hide_cursor
}

# View Action: Update INVEST scores
view_action_invest() {
  local item_id="$1"

  clear_screen
  printf "\n${BOLD}${CYAN}Update INVEST Scores for Task #%s${RESET}\n" "$item_id"
  printf "${DIM}Score each criterion from 1 (poor) to 5 (excellent)${RESET}\n\n"

  show_cursor

  local i_ind i_neg i_val i_est i_sml i_tst

  printf "${BOLD}I${RESET}ndependent (can be done without other tasks)\n"
  printf "  1=Heavily dependent, 3=Some dependencies, 5=Standalone\n"
  printf "  Score [1-5]: "
  read -r i_ind
  [[ ! "$i_ind" =~ ^[1-5]$ ]] && i_ind=""

  printf "\n${BOLD}N${RESET}egotiable (scope can be adjusted)\n"
  printf "  1=Rigid requirements, 3=Some flexibility, 5=Fully negotiable\n"
  printf "  Score [1-5]: "
  read -r i_neg
  [[ ! "$i_neg" =~ ^[1-5]$ ]] && i_neg=""

  printf "\n${BOLD}V${RESET}aluable (delivers user/business value)\n"
  printf "  1=Technical only, 3=Indirect value, 5=Direct user value\n"
  printf "  Score [1-5]: "
  read -r i_val
  [[ ! "$i_val" =~ ^[1-5]$ ]] && i_val=""

  printf "\n${BOLD}E${RESET}stimable (effort can be estimated)\n"
  printf "  1=Too many unknowns, 3=Rough estimate, 5=Clear scope\n"
  printf "  Score [1-5]: "
  read -r i_est
  [[ ! "$i_est" =~ ^[1-5]$ ]] && i_est=""

  printf "\n${BOLD}S${RESET}mall (fits in one sprint)\n"
  printf "  1=Multi-sprint epic, 3=Full sprint, 5=Days or less\n"
  printf "  Score [1-5]: "
  read -r i_sml
  [[ ! "$i_sml" =~ ^[1-5]$ ]] && i_sml=""

  printf "\n${BOLD}T${RESET}estable (clear pass/fail criteria)\n"
  printf "  1=No way to verify, 3=Some criteria, 5=Explicit tests\n"
  printf "  Score [1-5]: "
  read -r i_tst
  [[ ! "$i_tst" =~ ^[1-5]$ ]] && i_tst=""

  # Build update query
  local updates=""
  [ -n "$i_ind" ] && updates="${updates}invest_independent = $i_ind, "
  [ -n "$i_neg" ] && updates="${updates}invest_negotiable = $i_neg, "
  [ -n "$i_val" ] && updates="${updates}invest_valuable = $i_val, "
  [ -n "$i_est" ] && updates="${updates}invest_estimable = $i_est, "
  [ -n "$i_sml" ] && updates="${updates}invest_small = $i_sml, "
  [ -n "$i_tst" ] && updates="${updates}invest_testable = $i_tst, "

  if [ -n "$updates" ]; then
    updates="${updates}updated_at = NOW()"
    db_exec "UPDATE checklist_item SET $updates WHERE id = $item_id;" > /dev/null

    # Calculate new total
    local new_scores=$(db_query "SELECT invest_total, invest_passed FROM checklist_item WHERE id = $item_id;")
    local total=$(echo "$new_scores" | cut -d'|' -f1)
    local passed=$(echo "$new_scores" | cut -d'|' -f2)

    printf "\n${GREEN}✓ INVEST scores updated${RESET}\n"
    printf "  Total: %s/30 - %s\n" "$total" "$([ "$passed" = "t" ] && echo "${GREEN}PASS${RESET}" || echo "${RED}FAIL${RESET}")"

    if [ "$passed" != "t" ]; then
      printf "\n${YELLOW}Tip: Consider splitting this task (press 't' in view)${RESET}\n"
    fi
  else
    printf "\n${YELLOW}No scores entered${RESET}\n"
  fi

  printf "\n${DIM}Press any key to continue...${RESET}"
  read -rsn1
  load_items
}

# View Action: Update W-Framework
view_action_wframework() {
  local item_id="$1"

  clear_screen
  printf "\n${BOLD}${CYAN}Update W-Framework for Task #%s${RESET}\n" "$item_id"
  printf "${DIM}Press Enter to skip/keep existing value${RESET}\n\n"

  show_cursor

  printf "${BOLD}Who${RESET} is affected?\n  "
  read -r who

  printf "${BOLD}What${RESET} is the outcome?\n  "
  read -r what

  printf "${BOLD}Why${RESET} is this important?\n  "
  read -r why

  printf "${BOLD}When${RESET} is this needed?\n  "
  read -r when

  printf "${BOLD}Where${RESET} does this apply?\n  "
  read -r where

  printf "${BOLD}How${RESET} will we verify?\n  "
  read -r how

  # Build update query
  local updates=""
  [ -n "$who" ] && updates="${updates}who_affected = '${who//\'/\'\'}', "
  [ -n "$what" ] && updates="${updates}what_outcome = '${what//\'/\'\'}', "
  [ -n "$why" ] && updates="${updates}why_important = '${why//\'/\'\'}', "
  [ -n "$when" ] && updates="${updates}when_needed = '${when//\'/\'\'}', "
  [ -n "$where" ] && updates="${updates}where_applies = '${where//\'/\'\'}', "
  [ -n "$how" ] && updates="${updates}how_verified = '${how//\'/\'\'}', "

  if [ -n "$updates" ]; then
    updates="${updates}updated_at = NOW()"
    db_exec "UPDATE checklist_item SET $updates WHERE id = $item_id;" > /dev/null
    printf "\n${GREEN}✓ W-Framework updated${RESET}\n"
  else
    printf "\n${YELLOW}No changes made${RESET}\n"
  fi

  printf "\n${DIM}Press any key to continue...${RESET}"
  read -rsn1
  load_items
}

# View Action: Change Status (simple status change)
view_action_status() {
  local item_id="$1"

  local statuses=("pending" "in_progress" "blocked" "completed" "deferred" "cancelled")
  local status_idx=$(select_menu "Select New Status" "${statuses[@]}")
  [ "$status_idx" = "-1" ] && return

  local new_status="${statuses[$status_idx]}"

  db_exec "
    UPDATE checklist_item SET
      status = '$new_status',
      updated_at = NOW(),
      completed_at = CASE WHEN '$new_status' = 'completed' THEN NOW() ELSE completed_at END
    WHERE id = $item_id;
  " > /dev/null

  load_items
  draw_message "Status updated to: $new_status" "$GREEN"
}

# View Action: Feature Implementation Status (for tasks with interrogate session)
view_action_feature_status() {
  local item_id="$1"
  local feature_session="$2"
  local current_step="$3"
  local current_step_name="$4"
  local task_status="$5"
  local feature_sub_step="${6:-0}"

  show_cursor
  clear_screen

  # Handle case when no session exists yet
  if [ -z "$feature_session" ]; then
    local title=$(db_query "SELECT title FROM checklist_item WHERE id = $item_id;")
    printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}FEATURE IMPLEMENTATION${RESET}                                                    ${CYAN}║${RESET}\n"
    printf "${BOLD}${CYAN}║${RESET}  ${DIM}No active session${RESET}                                                         ${CYAN}║${RESET}\n"
    printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

    printf "${BOLD}Task:${RESET} %s\n\n" "$title"
    printf "No feature implementation session has been started for this task.\n\n"
    printf "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}\n"
    printf "${BOLD}Actions:${RESET} ${CYAN}y${RESET} Start Feature Pipeline │ ${CYAN}ESC/q${RESET} Back\n"
    printf "${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}\n"

    while true; do
      local action
      IFS= read -rsn1 action 2>/dev/null || break

      # Handle escape sequences - drain and ignore
      if [[ "$action" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 _ 2>/dev/null || true
        continue
      fi

      case "$action" in
        y|Y)
          hide_cursor
          view_action_feature_interrogate_full "$item_id" "$title"
          return
          ;;
        q)
          hide_cursor
          return
          ;;
      esac
    done
    hide_cursor
    return
  fi

  printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}FEATURE IMPLEMENTATION STATUS${RESET}                                            ${CYAN}║${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  Session: ${GREEN}%-60s${RESET}   ${CYAN}║${RESET}\n" "$feature_session"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

  local research_dir=".claude/RESEARCH/${feature_session}"

  # Define pipeline steps with their file indicators (TOTAL_PIPELINE_STEPS)
  local -a step_names=(
    "Repo Analysis"
    "Feature Input"
    "Context Research"
    "Refinement"
    "Impl Research"
    "Summary"
    "Flow Diagram"
    "Database Sync"
    "Data Schema"
    "Run Migration"
    "Integrate Models"
    "API Generation"
    "Journey Generation"
    "Frontend Gen"
  )

  local -a step_files=(
    "repo-analysis.md"
    "feature-input.md"
    "pre-context.md"
    "refined-requirements.md"
    "research-output.md"
    "summary.md"
    "flow-confirmed.txt"
    "scope-synced.txt"
    "schema-complete.txt"
    "migration-complete.txt"
    "models-integrated.txt"
    "api-generated.txt"
    "journeys-generated.txt"
    "frontend-complete.txt"
  )

  printf "${BOLD}Pipeline Progress:${RESET}\n"
  printf "${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n\n"

  local highest_complete=0
  local i

  for i in $(seq 1 $TOTAL_PIPELINE_STEPS); do
    local idx=$((i - 1))
    local name="${step_names[$idx]}"
    local file="${step_files[$idx]}"
    local step_marker=""
    local step_color=""
    local step_status=""

    # Check if this step's file exists
    local is_complete=false
    if [ -f "$research_dir/$file" ]; then
      step_marker="✓"
      step_color="$GREEN"
      step_status="Complete"
      highest_complete=$i
      is_complete=true
    elif [ "$i" -eq "$((highest_complete + 1))" ]; then
      step_marker="▶"
      step_color="$YELLOW"
      step_status="In Progress"
    else
      step_marker="○"
      step_color="$DIM"
      step_status="Pending"
    fi

    # Highlight current step from DB if available (only if not already complete)
    if [ "$is_complete" = "false" ] && [ -n "$current_step" ] && [ "$current_step" = "$i" ]; then
      step_marker="▶"
      step_color="$CYAN"
      step_status="Current"
    fi

    # For step 4 (Refinement), show sub-step (rounds) if available
    local sub_step_info=""
    if [ "$i" = "4" ] && [ -n "$feature_sub_step" ] && [ "$feature_sub_step" -gt 0 ]; then
      sub_step_info=" (round $feature_sub_step)"
    fi

    printf "  ${step_color}%s${RESET} ${BOLD}Step %d:${RESET} %-20s ${step_color}[%s%s]${RESET}\n" \
      "$step_marker" "$i" "$name" "$step_status" "$sub_step_info"
  done

  printf "\n${DIM}───────────────────────────────────────────────────────────────────────────────${RESET}\n"

  # Overall status
  local overall_status
  if [ "$highest_complete" -ge $TOTAL_PIPELINE_STEPS ]; then
    overall_status="${GREEN}Complete${RESET}"
  elif [ "$highest_complete" -ge 7 ]; then
    overall_status="${CYAN}Finalizing${RESET}"
  elif [ "$highest_complete" -ge 4 ]; then
    overall_status="${YELLOW}In Progress${RESET}"
  elif [ "$highest_complete" -ge 1 ]; then
    overall_status="${YELLOW}Started${RESET}"
  else
    overall_status="${DIM}Not Started${RESET}"
  fi

  printf "\n ${BOLD}Overall:${RESET} %s (%d/${TOTAL_PIPELINE_STEPS} steps complete)\n" "$overall_status" "$highest_complete"
  printf " ${BOLD}Files:${RESET}   %s\n" "$research_dir"

  printf "\n${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}\n"

  if [ "$highest_complete" -lt $TOTAL_PIPELINE_STEPS ] && [ "$task_status" != "completed" ]; then
    printf "${BOLD}Actions:${RESET} ${CYAN}r${RESET} Resume │ ${CYAN}s${RESET} Select Step │ ${CYAN}t${RESET} Change Status │ ${CYAN}ESC/q${RESET} Back\n"
  elif [ "$highest_complete" -gt 0 ]; then
    printf "${BOLD}Actions:${RESET} ${CYAN}s${RESET} Re-run Step │ ${CYAN}t${RESET} Change Status │ ${CYAN}ESC/q${RESET} Back\n"
  else
    printf "${BOLD}Actions:${RESET} ${CYAN}t${RESET} Change Task Status │ ${CYAN}ESC/q${RESET} Back\n"
  fi
  printf "${CYAN}═══════════════════════════════════════════════════════════════════════════════${RESET}\n"

  # Action loop
  while true; do
    local action
    IFS= read -rsn1 action 2>/dev/null || break

    # Handle escape key - drain any extra bytes and return
    if [[ "$action" == $'\x1b' ]]; then
      read -rsn2 -t 0.1 _ 2>/dev/null || true
      hide_cursor
      return
    fi

    case "$action" in
      r)
        if [ "$highest_complete" -lt $TOTAL_PIPELINE_STEPS ] && [ "$task_status" != "completed" ]; then
          hide_cursor
          view_action_resume_interrogate "$item_id" "$feature_session"
          return
        fi
        ;;
      s|S)
        # Select step to run/re-run
        hide_cursor
        view_action_select_step "$item_id" "$feature_session" "$highest_complete"
        return
        ;;
      t)
        hide_cursor
        view_action_status "$item_id"
        return
        ;;
      q)
        hide_cursor
        return
        ;;
    esac
  done

  hide_cursor
}

# View Action: Change Priority
view_action_priority() {
  local item_id="$1"

  local priorities=("must" "should" "could" "wont")
  local priority_idx=$(select_menu "Select New Priority" "${priorities[@]}")
  [ "$priority_idx" = "-1" ] && return

  local new_priority="${priorities[$priority_idx]}"

  show_cursor
  clear_screen
  printf "\n${BOLD}Priority Rationale${RESET}\n"
  printf "Why this priority? (optional): "
  read -r rationale
  hide_cursor

  local rationale_sql=""
  [ -n "$rationale" ] && rationale_sql=", priority_rationale = '${rationale//\'/\'\'}'"

  db_exec "
    UPDATE checklist_item SET
      priority = '$new_priority'
      $rationale_sql,
      updated_at = NOW()
    WHERE id = $item_id;
  " > /dev/null

  load_items
  draw_message "Priority updated to: $new_priority" "$GREEN"
}

# View Action: Split Task (SPIDR)
view_action_split() {
  local item_id="$1"
  local parent_title="$2"

  local split_types=("spike - Create investigation task" "path - Split by user journey" "interface - Split by API/UI/mobile" "data - Split by CRUD operation" "rules - Split by business rule")
  local type_idx=$(select_menu "SPIDR Split Pattern" "${split_types[@]}")
  [ "$type_idx" = "-1" ] && return

  local spidr_type=$(echo "${split_types[$type_idx]}" | cut -d' ' -f1)

  show_cursor
  clear_screen
  printf "\n${BOLD}${CYAN}Create Split: %s${RESET}\n\n" "$spidr_type"

  printf "New task title: "
  read -r new_title
  [ -z "$new_title" ] && return

  printf "Description: "
  read -r new_desc

  printf "Split reason: "
  read -r split_reason

  # Extra fields for spike
  local spike_question=""
  local spike_timebox=""
  local is_spike="false"

  if [ "$spidr_type" = "spike" ]; then
    is_spike="true"
    printf "Spike question to answer: "
    read -r spike_question
    printf "Timebox (e.g., 2h, 1d): "
    read -r spike_timebox
  fi

  hide_cursor

  # Get checklist_id, parent task_type, and next item number
  local parent_info=$(db_query "SELECT checklist_id, task_type FROM checklist_item WHERE id = $item_id;")
  local checklist_id=$(echo "$parent_info" | cut -d'|' -f1)
  local parent_task_type=$(echo "$parent_info" | cut -d'|' -f2)
  local next_num=$(db_query "SELECT COALESCE(MAX(item_number), 0) + 1 FROM checklist_item WHERE checklist_id = $checklist_id;")

  # Determine task_type and implementation_approach for split
  local split_task_type="$parent_task_type"
  local split_impl_approach=""
  if [ "$spidr_type" = "spike" ]; then
    split_task_type="spike"
    split_impl_approach="investigation"
  elif [ -n "$parent_task_type" ]; then
    # Inherit from parent with reasonable defaults
    case "$parent_task_type" in
      user_story|enhancement) split_impl_approach="feature" ;;
      bug_fix|tech_debt) split_impl_approach="troubleshoot" ;;
      chore) split_impl_approach="quick_fix" ;;
      *) split_impl_approach="feature" ;;
    esac
  fi

  # Insert child task
  db_exec "
    INSERT INTO checklist_item (
      checklist_id, item_number, title, description,
      parent_item_id, spidr_type, split_reason,
      is_spike, spike_question, spike_timebox,
      task_type, implementation_approach,
      priority, status, source
    ) VALUES (
      $checklist_id, $next_num, '${new_title//\'/\'\'}', '${new_desc//\'/\'\'}',
      $item_id, '$spidr_type', '${split_reason//\'/\'\'}',
      $is_spike, '${spike_question//\'/\'\'}', '${spike_timebox//\'/\'\'}',
      $([ -n "$split_task_type" ] && echo \"'$split_task_type'\" || echo "NULL"), $([ -n "$split_impl_approach" ] && echo \"'$split_impl_approach'\" || echo "NULL"),
      'must', 'pending', 'split'
    );
  " > /dev/null

  load_items
  draw_message "Created $spidr_type split: $new_title" "$GREEN"
}

# View Action: Edit task details
view_action_edit() {
  local item_id="$1"

  # Get current values (escape newlines for proper parsing)
  local current=$(db_query "
    SELECT
      REPLACE(COALESCE(title, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(description, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(notes, ''), E'\n', '<NL>'),
      story_points
    FROM checklist_item WHERE id = $item_id;
  ")
  local cur_title=$(echo "$current" | cut -d'|' -f1 | sed 's/<NL>/\n/g')
  local cur_desc=$(echo "$current" | cut -d'|' -f2 | sed 's/<NL>/\n/g')
  local cur_notes=$(echo "$current" | cut -d'|' -f3 | sed 's/<NL>/\n/g')
  local cur_points=$(echo "$current" | cut -d'|' -f4)

  show_cursor
  clear_screen
  printf "\n${BOLD}${CYAN}Edit Task #%s${RESET}\n\n" "$item_id"

  printf "Current title: %s\n" "$cur_title"
  printf "New title (blank to keep): "
  read -r new_title

  printf "\nCurrent description: %s\n" "${cur_desc:0:50}..."
  printf "New description (blank to keep): "
  read -r new_desc

  printf "\nStory points [1,2,3,5,8,13,21] (current: %s): " "${cur_points:-none}"
  read -r new_points

  printf "\nNotes (append): "
  read -r new_notes

  hide_cursor

  # Build update
  local updates=""
  [ -n "$new_title" ] && updates="${updates}title = '${new_title//\'/\'\'}', "
  [ -n "$new_desc" ] && updates="${updates}description = '${new_desc//\'/\'\'}', "
  [[ "$new_points" =~ ^(1|2|3|5|8|13|21)$ ]] && updates="${updates}story_points = $new_points, "
  [ -n "$new_notes" ] && updates="${updates}notes = COALESCE(notes, '') || E'\n' || '${new_notes//\'/\'\'}', "

  if [ -n "$updates" ]; then
    updates="${updates}updated_at = NOW()"
    db_exec "UPDATE checklist_item SET $updates WHERE id = $item_id;" > /dev/null
    printf "\n${GREEN}✓ Task updated${RESET}\n"
  else
    printf "\n${YELLOW}No changes made${RESET}\n"
  fi

  printf "\n${DIM}Press any key to continue...${RESET}"
  read -rsn1
  load_items
}

# View Action: Launch Feature Interrogate (full discovery pipeline)
view_action_interrogate() {
  local item_id="$1"
  local title="$2"

  show_cursor
  clear_screen
  printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}\n"
  printf "${BOLD}${CYAN}║${RESET}  ${BOLD}${WHITE}FEATURE INTERROGATE${RESET} │ Task #%s                                       ${CYAN}║${RESET}\n" "$item_id"
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n\n"

  printf " ${BOLD}Task:${RESET} %s\n\n" "$title"

  printf " ${DIM}This will launch the 10-phase feature discovery pipeline:${RESET}\n"
  printf "   1. Repo Familiarization   6. Summary\n"
  printf "   2. Feature Input          7. Flow Diagram Loop\n"
  printf "   3. Requirement Refinement 8. Database Sync\n"
  printf "   4. Deep Research          9. Schema Generation\n"
  printf "   5. Impl Research         10. Run Migration\n\n"

  printf " ${BOLD}Options:${RESET}\n"
  printf "   ${CYAN}f${RESET} - Full discovery (all 10 phases)\n"
  printf "   ${CYAN}c${RESET} - Generate context file only (for /pm:feature)\n"
  printf "   ${CYAN}q${RESET} - Cancel\n\n"

  printf " Select option: "
  read -rsn1 option

  case "$option" in
    f|F)
      # Launch full interrogate
      view_action_feature_interrogate_full "$item_id" "$title"
      ;;
    c|C)
      # Generate context file only (legacy behavior)
      view_action_feature_context "$item_id" "$title"
      ;;
    *)
      hide_cursor
      return
      ;;
  esac
}

# Full feature_interrogate.sh integration
view_action_feature_interrogate_full() {
  local item_id="$1"
  local title="$2"

  # Check for existing session in DB
  local existing_data=$(db_query "SELECT feature_session, feature_step, feature_branch FROM checklist_item WHERE id = $item_id;")
  local existing_session=$(echo "$existing_data" | cut -d'|' -f1)
  local existing_step=$(echo "$existing_data" | cut -d'|' -f2)
  local existing_branch=$(echo "$existing_data" | cut -d'|' -f3)

  local session_name=""
  local research_dir=""
  local start_from_step=""

  if [ -n "$existing_session" ] && [ -d ".claude/RESEARCH/$existing_session" ]; then
    # Resume existing session
    session_name="$existing_session"
    research_dir=".claude/RESEARCH/${session_name}"
    start_from_step="${existing_step:-1}"
    printf "\n${CYAN}Resuming existing session: %s (step %s)${RESET}\n" "$session_name" "$start_from_step"
  else
    # Generate new session name
    session_name="task-${item_id}-$(date +%Y%m%d-%H%M%S)"
    research_dir=".claude/RESEARCH/${session_name}"
    start_from_step=""
    printf "\n${CYAN}Starting new session: %s${RESET}\n" "$session_name"
  fi

  # Create feature branch from current branch
  # Slugify: lowercase, replace spaces/special chars with hyphens, max 50 chars
  local slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-50)
  local feature_branch="feature/${item_id}-${slug}"
  local current_branch=$(git branch --show-current 2>/dev/null || echo "main")

  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$feature_branch" 2>/dev/null; then
    printf "\n${YELLOW}Branch already exists: %s${RESET}\n" "$feature_branch"
    printf "Checking out existing branch...\n"
    git checkout "$feature_branch" 2>/dev/null || {
      printf "${RED}Failed to checkout branch${RESET}\n"
      printf "\n${DIM}Press any key to continue...${RESET}"
      read -rsn1
      hide_cursor
      load_items
      return
    }
  else
    # Create new feature branch
    printf "\n${CYAN}Creating feature branch: %s${RESET}\n" "$feature_branch"
    git checkout -b "$feature_branch" 2>/dev/null || {
      printf "${RED}Failed to create branch${RESET}\n"
      printf "\n${DIM}Press any key to continue...${RESET}"
      read -rsn1
      hide_cursor
      load_items
      return
    }
  fi
  printf "${GREEN}✓ On branch: %s${RESET}\n" "$feature_branch"

  # Create research directory and pre-context file
  mkdir -p "$research_dir"

  # Get session and task data (escape newlines for proper parsing)
  local session=$(db_query "SELECT c.session_name FROM checklist c JOIN checklist_item ci ON ci.checklist_id = c.id WHERE ci.id = $item_id;")
  local data=$(db_query "
    SELECT
      REPLACE(COALESCE(ci.title, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.description, ''), E'\n', '<NL>'),
      ci.priority,
      ci.invest_total,
      REPLACE(COALESCE(ci.who_affected, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.what_outcome, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.why_important, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.when_needed, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.where_applies, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.how_verified, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.acceptance_criteria::text, ''), E'\n', '<NL>'),
      ci.story_points,
      REPLACE(COALESCE(ci.user_story_role, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.user_story_goal, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.user_story_benefit, ''), E'\n', '<NL>')
    FROM checklist_item ci
    JOIN checklist c ON ci.checklist_id = c.id
    WHERE ci.id = $item_id;
  ")

  local f_title=$(echo "$data" | cut -d'|' -f1 | sed 's/<NL>/\n/g')
  local f_desc=$(echo "$data" | cut -d'|' -f2 | sed 's/<NL>/\n/g')
  local f_priority=$(echo "$data" | cut -d'|' -f3)
  local f_invest=$(echo "$data" | cut -d'|' -f4)
  local f_who=$(echo "$data" | cut -d'|' -f5 | sed 's/<NL>/\n/g')
  local f_what=$(echo "$data" | cut -d'|' -f6 | sed 's/<NL>/\n/g')
  local f_why=$(echo "$data" | cut -d'|' -f7 | sed 's/<NL>/\n/g')
  local f_when=$(echo "$data" | cut -d'|' -f8 | sed 's/<NL>/\n/g')
  local f_where=$(echo "$data" | cut -d'|' -f9 | sed 's/<NL>/\n/g')
  local f_how=$(echo "$data" | cut -d'|' -f10 | sed 's/<NL>/\n/g')
  local f_ac=$(echo "$data" | cut -d'|' -f11 | sed 's/<NL>/\n/g')
  local f_points=$(echo "$data" | cut -d'|' -f12)
  local f_us_role=$(echo "$data" | cut -d'|' -f13 | sed 's/<NL>/\n/g')
  local f_us_goal=$(echo "$data" | cut -d'|' -f14 | sed 's/<NL>/\n/g')
  local f_us_benefit=$(echo "$data" | cut -d'|' -f15 | sed 's/<NL>/\n/g')

  # Create pre-seeded context file for feature_interrogate.sh
  cat > "$research_dir/pre-context.md" << EOF
# Pre-seeded Context from Planner

## Task Reference
- checklist_item.id: $item_id
- planner_session: $session
- interrogate_session: $session_name

## Feature Description
**$f_title**

$f_desc

## User Story
$([ -n "$f_us_role" ] && echo "As a **$f_us_role**, I want **$f_us_goal** so that **$f_us_benefit**.")

## W-Framework (Pre-answered)
- **Who:** $f_who
- **What:** $f_what
- **Why:** $f_why
- **When:** $f_when
- **Where:** $f_where
- **How to verify:** $f_how

## Sprint Context
- **Priority:** $f_priority
- **INVEST Score:** ${f_invest:-0}/30
- **Story Points:** ${f_points:-TBD}

## Acceptance Criteria
$f_ac
EOF

  # Update checklist_item with session and branch link BEFORE launching
  db_exec "
    UPDATE checklist_item SET
      feature_session = '$session_name',
      feature_branch = '$feature_branch',
      status = 'in_progress',
      updated_at = NOW()
    WHERE id = $item_id;
  " > /dev/null

  printf "\n${GREEN}✓ Pre-context created: %s/pre-context.md${RESET}\n" "$research_dir"
  printf "\n${BOLD}Launching feature_interrogate.sh...${RESET}\n"
  printf "${DIM}Session: %s${RESET}\n\n" "$session_name"

  sleep 1

  # Check if feature_interrogate.sh exists
  local interrogate_script="./.claude/scripts/feature_interrogate.sh"
  if [ ! -f "$interrogate_script" ]; then
    interrogate_script="./.claude/ccpm/ccpm/scripts/feature_interrogate.sh"
  fi
  if [ ! -f "$interrogate_script" ]; then
    interrogate_script="./feature_interrogate.sh"
  fi
  if [ ! -f "$interrogate_script" ]; then
    printf "\n${RED}✗ feature_interrogate.sh not found${RESET}\n"
    printf "  Expected at: .claude/ccpm/ccpm/scripts/feature_interrogate.sh\n"
    printf "\n${DIM}Press any key to continue...${RESET}"
    read -rsn1
    hide_cursor
    load_items
    return
  fi

  # Launch feature_interrogate.sh with session name
  # Export the pre-context path so interrogate can use it
  export PLANNER_PRECONTEXT="$research_dir/pre-context.md"
  export PLANNER_ITEM_ID="$item_id"

  clear_screen
  if [ -n "$start_from_step" ] && [ "$start_from_step" -gt 1 ]; then
    "$interrogate_script" "$session_name" --start-from-step "$start_from_step"
  else
    "$interrogate_script" "$session_name"
  fi
  local exit_code=$?

  unset PLANNER_PRECONTEXT
  unset PLANNER_ITEM_ID

  # After completion, sync results back to checklist_item
  sync_interrogate_results "$item_id" "$session_name"

  printf "\n${DIM}Press any key to continue...${RESET}"
  read -rsn1
  hide_cursor
  load_items
}

# Delete feature progress: branch, session directories, and reset DB
delete_feature_progress() {
  local item_id="$1"

  # Get session and branch info
  local data=$(db_query "SELECT feature_session, feature_branch FROM checklist_item WHERE id = $item_id;")
  local session=$(echo "$data" | cut -d'|' -f1)
  local branch=$(echo "$data" | cut -d'|' -f2)

  if [ -z "$session" ] && [ -z "$branch" ]; then
    printf "${YELLOW}No feature session or branch to delete${RESET}\n"
    return 1
  fi

  # 1. Switch to main branch first if on the feature branch
  local current=$(git branch --show-current 2>/dev/null)
  if [ -n "$branch" ] && [ "$current" = "$branch" ]; then
    printf "Switching from feature branch to main...\n"
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || {
      printf "${RED}Failed to switch to main branch${RESET}\n"
      return 1
    }
  fi

  # 2. Delete the feature branch (force delete to discard changes)
  if [ -n "$branch" ] && git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    printf "Deleting branch: %s\n" "$branch"
    git branch -D "$branch" 2>/dev/null && printf "${GREEN}✓ Branch deleted${RESET}\n" || printf "${YELLOW}Could not delete branch${RESET}\n"
  fi

  # 3. Delete session directories
  if [ -n "$session" ]; then
    if [ -d ".claude/RESEARCH/$session" ]; then
      printf "Removing: .claude/RESEARCH/%s\n" "$session"
      rm -rf ".claude/RESEARCH/$session"
    fi
    if [ -d ".claude/scopes/$session" ]; then
      printf "Removing: .claude/scopes/%s\n" "$session"
      rm -rf ".claude/scopes/$session"
    fi
    if [ -d ".claude/cache/diagram-cache/$session" ]; then
      printf "Removing: .claude/cache/diagram-cache/%s\n" "$session"
      rm -rf ".claude/cache/diagram-cache/$session"
    fi
  fi

  # 4. Reset database columns
  db_exec "
    UPDATE checklist_item SET
      feature_session = NULL,
      feature_branch = NULL,
      feature_step = NULL,
      feature_sub_step = NULL,
      feature_step_name = NULL,
      status = 'pending',
      updated_at = NOW()
    WHERE id = $item_id;
  " > /dev/null

  printf "${GREEN}✓ Feature progress deleted - task reset to pending${RESET}\n"
  return 0
}

# Sync results from feature_interrogate back to checklist_item
sync_interrogate_results() {
  local item_id="$1"
  local session_name="$2"

  local research_dir=".claude/RESEARCH/${session_name}"
  local scope_dir=".claude/scopes/${session_name}"
  local required_elements="$research_dir/required-elements.yaml"
  local flow_diagram="$research_dir/flow-diagram.md"
  local flow_confirmed="$research_dir/flow-confirmed.txt"

  printf "\n${BOLD}Syncing interrogate results...${RESET}\n"

  # Detect which step the interrogation reached based on files created
  # Steps: 1-Repo Analysis, 2-Feature Input, 3-Context Research, 4-Refinement,
  #        5-Impl Research, 6-Summary, 7-Flow Diagram, 8-Database Sync, 9-Data Schema, 10-Run Migration
  local feature_step=1
  local feature_step_name="Repo Analysis"

  if [ -f "$research_dir/repo-analysis.md" ]; then
    feature_step=1; feature_step_name="Repo Analysis"
  fi
  if [ -f "$research_dir/feature-input.md" ]; then
    feature_step=2; feature_step_name="Feature Input"
  fi
  if [ -f "$research_dir/research-output.md" ]; then
    feature_step=3; feature_step_name="Context Research"
  fi
  if [ -f "$research_dir/refined-requirements.md" ]; then
    feature_step=4; feature_step_name="Refinement"
  fi
  if [ -f "$research_dir/implementation-research.md" ]; then
    feature_step=5; feature_step_name="Impl Research"
  fi
  if [ -f "$research_dir/conversation-summary.md" ]; then
    feature_step=6; feature_step_name="Summary"
  fi
  if [ -f "$flow_diagram" ]; then
    feature_step=7; feature_step_name="Flow Diagram"
  fi
  if [ -f "$research_dir/scope-synced.txt" ]; then
    feature_step=8; feature_step_name="Database Sync"
  fi
  if [ -f "$research_dir/schema-complete.txt" ]; then
    feature_step=9; feature_step_name="Data Schema"
  fi
  if [ -f "$research_dir/migration-complete.txt" ]; then
    feature_step=10; feature_step_name="Run Migration"
  fi
  if [ -f "$research_dir/models-integrated.txt" ]; then
    feature_step=11; feature_step_name="Integrate Models"
  fi
  if [ -f "$research_dir/api-generated.txt" ]; then
    feature_step=12; feature_step_name="API Generation"
  fi
  if [ -f "$research_dir/journeys-generated.txt" ]; then
    feature_step=13; feature_step_name="Journey Generation"
  fi
  if [ -f "$research_dir/frontend-complete.txt" ]; then
    feature_step=14; feature_step_name="Frontend Gen"
  fi

  # Count sub-step for refinement (round number)
  local feature_sub_step=0
  if [ -f "$research_dir/refinement-session.md" ]; then
    feature_sub_step=$(grep -c "^### Round.*User" "$research_dir/refinement-session.md" 2>/dev/null || echo "0")
  fi

  # Update feature_step and feature_sub_step in database
  db_exec "
    UPDATE checklist_item SET
      feature_step = $feature_step,
      feature_sub_step = $feature_sub_step,
      feature_step_name = '${feature_step_name}',
      updated_at = NOW()
    WHERE id = $item_id;
  " > /dev/null

  # Check completion status
  if [ -f "$flow_confirmed" ]; then
    printf "  ${GREEN}✓ Session completed (Step %s: %s)${RESET}\n" "$feature_step" "$feature_step_name"
  else
    printf "  ${YELLOW}○ Session at Step %s: %s (can resume later)${RESET}\n" "$feature_step" "$feature_step_name"
  fi

  # Parse required-elements.yaml if exists
  if [ -f "$required_elements" ]; then
    printf "  ${GREEN}✓ Found required-elements.yaml${RESET}\n"

    # Extract acceptance criteria from YAML (simple grep for now)
    local extracted_criteria=$(grep -A 100 "acceptance_criteria:" "$required_elements" 2>/dev/null | head -50)

    if [ -n "$extracted_criteria" ]; then
      # Update acceptance_criteria in DB
      local clean_criteria=$(echo "$extracted_criteria" | tr '\n' ' ' | sed "s/'/''/g")
      db_exec "
        UPDATE checklist_item SET
          notes = COALESCE(notes, '') || E'\n\n[Interrogate Criteria Extracted: $session_name]',
          updated_at = NOW()
        WHERE id = $item_id;
      " > /dev/null
    fi
  else
    printf "  ${DIM}○ No required-elements.yaml found${RESET}\n"
  fi

  # Store flow diagram reference (only if not already present)
  if [ -f "$flow_diagram" ]; then
    printf "  ${GREEN}✓ Found flow-diagram.md${RESET}\n"
    # Check if flow diagram link already exists in notes
    local existing_notes=$(db_query "SELECT notes FROM checklist_item WHERE id = $item_id;")
    if [[ "$existing_notes" != *"[Flow Diagram:"* ]]; then
      db_exec "
        UPDATE checklist_item SET
          notes = COALESCE(notes, '') || E'\n\n[Flow Diagram: $research_dir/flow-diagram.md]',
          updated_at = NOW()
        WHERE id = $item_id;
      " > /dev/null
    fi
  fi

  # Link scope directory
  if [ -d "$scope_dir" ]; then
    printf "  ${GREEN}✓ Scope directory created${RESET}\n"
  fi

  printf "  ${GREEN}✓ Database updated${RESET}\n"
}

# Generate context file only (for /pm:feature)
view_action_feature_context() {
  local item_id="$1"
  local title="$2"

  # Get session name
  local session=$(db_query "SELECT c.session_name FROM checklist c JOIN checklist_item ci ON ci.checklist_id = c.id WHERE ci.id = $item_id;")

  # Generate feature context file
  local context_file=".claude/planner/feature-context-${item_id}.md"
  local current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  mkdir -p ".claude/planner"

  # Get full task data (escape newlines for proper parsing)
  local data=$(db_query "
    SELECT
      REPLACE(COALESCE(ci.title, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.description, ''), E'\n', '<NL>'),
      ci.priority,
      ci.invest_total,
      REPLACE(COALESCE(ci.who_affected, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.what_outcome, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.why_important, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.when_needed, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.where_applies, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.how_verified, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(ci.acceptance_criteria::text, ''), E'\n', '<NL>'),
      REPLACE(COALESCE(c.sprint_context, ''), E'\n', '<NL>')
    FROM checklist_item ci
    JOIN checklist c ON ci.checklist_id = c.id
    WHERE ci.id = $item_id;
  ")

  local f_title=$(echo "$data" | cut -d'|' -f1 | sed 's/<NL>/\n/g')
  local f_desc=$(echo "$data" | cut -d'|' -f2 | sed 's/<NL>/\n/g')
  local f_priority=$(echo "$data" | cut -d'|' -f3)
  local f_invest=$(echo "$data" | cut -d'|' -f4)
  local f_who=$(echo "$data" | cut -d'|' -f5 | sed 's/<NL>/\n/g')
  local f_what=$(echo "$data" | cut -d'|' -f6 | sed 's/<NL>/\n/g')
  local f_why=$(echo "$data" | cut -d'|' -f7 | sed 's/<NL>/\n/g')
  local f_when=$(echo "$data" | cut -d'|' -f8 | sed 's/<NL>/\n/g')
  local f_where=$(echo "$data" | cut -d'|' -f9 | sed 's/<NL>/\n/g')
  local f_how=$(echo "$data" | cut -d'|' -f10 | sed 's/<NL>/\n/g')
  local f_ac=$(echo "$data" | cut -d'|' -f11 | sed 's/<NL>/\n/g')

  cat > "$context_file" << EOF
# Feature Context: $f_title

> Auto-generated from checklist_item id=$item_id
> Session: $session
> Generated: $current_date

---

## Sprint Context

- **Priority:** $f_priority
- **INVEST Score:** ${f_invest:-0}/30

---

## Feature Requirements

### Title
$f_title

### Description
$f_desc

---

## W-Framework Analysis

### Who is affected?
$f_who

### What is the outcome?
$f_what

### Why is this important?
$f_why

### When is this needed?
$f_when

### Where does this apply?
$f_where

### How will we verify?
$f_how

---

## Acceptance Criteria

$f_ac

---

## Implementation Guidance

Based on the context above, the feature skill should:

1. **Skip Phase 0 questions** that are already answered above
2. **Use W-Framework data** to populate PRD fields
3. **Reference verification criteria** for test generation

### Pre-answered Questions

| Question | Answer |
|----------|--------|
| What to build? | $f_title |
| Who benefits? | $f_who |
| Success criteria? | $f_how |
| Priority level? | $f_priority |

---

## Database Reference

\`\`\`
checklist_item.id = $item_id
session_name = $session
\`\`\`
EOF

  # Update task with feature link
  db_exec "
    UPDATE checklist_item SET
      feature_session = 'feature-context-$item_id',
      status = 'in_progress',
      updated_at = NOW()
    WHERE id = $item_id;
  " > /dev/null

  printf "\n${GREEN}✓ Feature context generated: %s${RESET}\n" "$context_file"
  printf "\nTo run the feature pipeline:\n"
  printf "  ${CYAN}/pm:feature %s${RESET}\n" "$context_file"

  printf "\n${DIM}Press any key to continue...${RESET}"
  read -rsn1
  hide_cursor
  load_items
}

# Check interrogate session status
check_interrogate_status() {
  local session_name="$1"

  if [ -z "$session_name" ]; then
    echo "none"
    return
  fi

  local research_dir=".claude/RESEARCH/${session_name}"

  if [ ! -d "$research_dir" ]; then
    echo "not_found"
    return
  fi

  # Check for final step completion - true end of pipeline
  if [ -f "$research_dir/frontend-complete.txt" ]; then
    echo "complete"
  elif [ -f "$research_dir/pre-context.md" ]; then
    echo "in_progress"
  else
    echo "started"
  fi
}

# Select a step to run/re-run
view_action_select_step() {
  local item_id="$1"
  local feature_session="$2"
  local highest_complete="$3"

  # Build step menu options
  local -a step_names=(
    "Step 1: Repo Analysis"
    "Step 2: Feature Input"
    "Step 3: Context Research"
    "Step 4: Refinement"
    "Step 5: Impl Research"
    "Step 6: Summary"
    "Step 7: Flow Diagram"
    "Step 8: Database Sync"
    "Step 9: Data Schema"
    "Step 10: Run Migration"
    "Step 11: Integrate Models"
    "Step 12: API Generation"
    "Step 13: Journey Generation"
    "Step 14: Frontend Gen"
  )

  # Build menu with status indicators
  local -a menu_options=()
  local next_step=$((highest_complete + 1))

  # First option: Continue from next step (if not complete)
  if [ "$highest_complete" -lt $TOTAL_PIPELINE_STEPS ]; then
    menu_options+=("▶ Continue from ${step_names[$highest_complete]} [default]")
  fi

  # Add completed steps (in reverse order for easy re-running)
  for ((i=highest_complete; i>=1; i--)); do
    menu_options+=("↻ Re-run ${step_names[$((i-1))]}")
  done

  # Add option to start from beginning
  menu_options+=("⟳ Start over from Step 1")

  hide_cursor
  local step_idx=$(select_menu "Select Pipeline Step" "${menu_options[@]}")

  if [ "$step_idx" = "-1" ]; then
    return
  fi

  # Determine which step to run
  local selected_step

  if [ "$highest_complete" -lt $TOTAL_PIPELINE_STEPS ]; then
    # First option is "continue"
    if [ "$step_idx" = "0" ]; then
      selected_step=$next_step
    elif [ "$step_idx" = "$((${#menu_options[@]} - 1))" ]; then
      # Last option is "start over"
      selected_step=1
    else
      # Re-run a completed step (reverse index)
      selected_step=$((highest_complete - step_idx + 1))
    fi
  else
    # All complete - no "continue" option
    if [ "$step_idx" = "$((${#menu_options[@]} - 1))" ]; then
      selected_step=1
    else
      selected_step=$((highest_complete - step_idx))
    fi
  fi

  show_cursor
  clear_screen
  printf "\n${BOLD}Running from Step %d: %s${RESET}\n\n" "$selected_step" "${step_names[$((selected_step-1))]}"

  # Check if feature_interrogate.sh exists (try multiple paths)
  local interrogate_script="./.claude/ccpm/ccpm/scripts/feature_interrogate.sh"
  if [ ! -f "$interrogate_script" ]; then
    interrogate_script="./.claude/scripts/feature_interrogate.sh"
  fi
  if [ ! -f "$interrogate_script" ]; then
    interrogate_script="./feature_interrogate.sh"
  fi
  if [ ! -f "$interrogate_script" ]; then
    printf "${RED}✗ feature_interrogate.sh not found${RESET}\n"
    printf "${DIM}Press any key to continue...${RESET}"
    read -rsn1
    return
  fi

  # Export context
  local research_dir=".claude/RESEARCH/${feature_session}"
  export PLANNER_PRECONTEXT="$research_dir/pre-context.md"
  export PLANNER_ITEM_ID="$item_id"

  # Run from selected step
  "$interrogate_script" "$feature_session" --start-from-step "$selected_step"

  unset PLANNER_PRECONTEXT
  unset PLANNER_ITEM_ID

  # Sync results
  sync_interrogate_results "$item_id" "$feature_session"

  printf "\n${DIM}Press any key to continue...${RESET}"
  read -rsn1
  load_items
}

# Resume existing interrogate session
view_action_resume_interrogate() {
  local item_id="$1"
  local feature_session="$2"

  clear_screen
  show_cursor

  if [ -z "$feature_session" ]; then
    printf "\n${YELLOW}No interrogate session to resume${RESET}\n"
    printf "${DIM}Press any key to continue...${RESET}"
    read -rsn1
    return
  fi

  # Get current step from database
  local feature_step=$(db_query "SELECT COALESCE(feature_step, 1) FROM checklist_item WHERE id = $item_id;")

  local status=$(check_interrogate_status "$feature_session")

  case "$status" in
    complete)
      printf "\n${GREEN}Session already complete: %s${RESET}\n" "$feature_session"
      printf "View results in: .claude/RESEARCH/%s/\n" "$feature_session"
      printf "\n${DIM}Press any key to continue...${RESET}"
      read -rsn1
      return
      ;;
    not_found)
      printf "\n${RED}Session directory not found: %s${RESET}\n" "$feature_session"
      printf "\n${YELLOW}The session was recorded but files don't exist.${RESET}\n"
      printf "Press ${CYAN}n${RESET} to start a new session, or any other key to cancel: "
      read -rsn1 choice
      if [[ "$choice" =~ ^[Nn]$ ]]; then
        # Clear the stale session reference
        db_exec "UPDATE checklist_item SET feature_session = NULL, feature_step = NULL, feature_step_name = NULL WHERE id = $item_id;" > /dev/null
        # Get title for new session
        local title=$(db_query "SELECT title FROM checklist_item WHERE id = $item_id;")
        hide_cursor
        view_action_feature_interrogate_full "$item_id" "$title"
        return
      fi
      return
      ;;
  esac

  printf "\n${BOLD}Resuming session: %s${RESET}\n\n" "$feature_session"

  # Check if feature_interrogate.sh exists
  local interrogate_script="./.claude/scripts/feature_interrogate.sh"
  if [ ! -f "$interrogate_script" ]; then
    interrogate_script="./.claude/ccpm/ccpm/scripts/feature_interrogate.sh"
  fi
  if [ ! -f "$interrogate_script" ]; then
    interrogate_script="./feature_interrogate.sh"
  fi
  if [ ! -f "$interrogate_script" ]; then
    printf "${RED}✗ feature_interrogate.sh not found${RESET}\n"
    printf "${DIM}Press any key to continue...${RESET}"
    read -rsn1
    return
  fi

  # Export context
  local research_dir=".claude/RESEARCH/${feature_session}"
  export PLANNER_PRECONTEXT="$research_dir/pre-context.md"
  export PLANNER_ITEM_ID="$item_id"

  clear_screen
  # Detect first incomplete step by checking marker files
  local -a step_files=(
    "repo-analysis.md"
    "feature-input.md"
    "pre-context.md"
    "refined-requirements.md"
    "research-output.md"
    "summary.md"
    "flow-confirmed.txt"
    "scope-synced.txt"
    "schema-complete.txt"
    "migration-complete.txt"
    "models-integrated.txt"
    "api-generated.txt"
    "journeys-generated.txt"
    "frontend-complete.txt"
  )

  local next_step=1
  for i in $(seq 1 $TOTAL_PIPELINE_STEPS); do
    local idx=$((i - 1))
    local file_path="$research_dir/${step_files[$idx]}"
    if [ -f "$file_path" ]; then
      next_step=$((i + 1))
    else
      break
    fi
  done
  # Cap at max step
  if [ "$next_step" -gt $TOTAL_PIPELINE_STEPS ]; then
    next_step=$TOTAL_PIPELINE_STEPS
  fi

  if [ "$next_step" -gt 1 ]; then
    printf "${DIM}Resuming from step %s${RESET}\n" "$next_step"
    "$interrogate_script" "$feature_session" --start-from-step "$next_step"
  else
    "$interrogate_script" "$feature_session"
  fi

  unset PLANNER_PRECONTEXT
  unset PLANNER_ITEM_ID

  # Sync results
  sync_interrogate_results "$item_id" "$feature_session"

  printf "\n${DIM}Press any key to continue...${RESET}"
  read -rsn1
  load_items
}

# Action: Edit task
action_edit_task() {
  if [ ${#ITEMS[@]} -eq 0 ]; then
    draw_message "No tasks to edit" "$YELLOW"
    return
  fi

  local item_id="${ITEM_IDS[$SELECTED_INDEX]}"
  local item="${ITEMS[$SELECTED_INDEX]}"
  local current_title=$(echo "$item" | cut -d'|' -f3)

  show_cursor
  clear_screen
  printf "\n ${BOLD}${CYAN}Edit Task #%s${RESET}\n\n" "$item_id"
  printf " Current title: %s\n\n" "$current_title"
  printf " New title (blank to keep): "
  read -r new_title
  hide_cursor

  if [ -n "$new_title" ]; then
    db_exec "
      UPDATE checklist_item SET
        title = '${new_title//\'/\'\'}',
        updated_at = NOW()
      WHERE id = $item_id;
    " > /dev/null

    load_items
    draw_message "Task #$item_id updated" "$GREEN"
  fi
}

# Cleanup on exit
cleanup() {
  show_cursor
  clear_screen
  printf "Goodbye!\n"
}

# Main loop
main() {
  trap cleanup EXIT
  hide_cursor

  # Start in "ALL SESSIONS" view by default
  VIEW_MODE="all"
  CURRENT_SESSION="ALL"

  # Check if any sessions exist
  local session_count=$(db_query "SELECT COUNT(*) FROM checklist;")
  if [ "${session_count:-0}" -eq 0 ]; then
    # No sessions - prompt to create
    show_cursor
    printf "\n ${YELLOW}No planning sessions found.${RESET}\n"
    printf " Create a new session? (Y/n): "
    read -r create
    hide_cursor

    if [[ ! "$create" =~ ^[Nn]$ ]]; then
      action_new_session
      VIEW_MODE="all"
      CURRENT_SESSION="ALL"
    else
      exit 0
    fi
  fi

  load_items
  redraw

  while true; do
    local key
    key=$(read_key)

    # Skip if read failed
    [ -z "$key" ] && continue

    case "$key" in
      UP|k)
        if [ $SELECTED_INDEX -gt 0 ]; then
          SELECTED_INDEX=$((SELECTED_INDEX - 1))
        fi
        draw_items
        ;;
      DOWN|j)
        if [ $SELECTED_INDEX -lt $((${#ITEMS[@]} - 1)) ]; then
          SELECTED_INDEX=$((SELECTED_INDEX + 1))
        fi
        draw_items
        ;;
      ENTER)
        # Enter key - view task details (same as 'v')
        action_view_task
        redraw
        ;;
      n|w)
        action_wizard
        redraw
        ;;
      c)
        action_complete
        redraw
        ;;
      s)
        action_change_status
        redraw
        ;;
      p)
        action_change_priority
        redraw
        ;;
      a)
        action_archive
        redraw
        ;;
      v)
        action_toggle_archived
        redraw
        ;;
      r)
        load_session
        load_items
        redraw
        draw_message "Refreshed" "$GREEN"
        ;;
      S)
        action_switch_session
        redraw
        ;;
      N)
        action_new_session
        redraw
        ;;
      q|Q)
        break
        ;;
    esac
  done
}

main
