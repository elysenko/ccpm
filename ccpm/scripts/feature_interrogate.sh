#!/bin/bash
# feature_interrogate.sh - Interactive Feature Discovery with Flow Verification
#
# An interactive shell script that guides users through feature discovery
# using Claude's research skills, culminating in a verified flow diagram.
#
# Usage:
#   ./feature_interrogate.sh [session-name]
#
# Pipeline:
#   repo-research → user-input → dr-refine → dr-research → summary → flow-diagram-loop → db-sync
#
# Output:
#   .claude/RESEARCH/{session}/ - Research files
#   .claude/scopes/{session}/   - Scope documents for database sync

set -euo pipefail

# Enable better line editing for read commands
# This enables: arrow keys, Ctrl+A/E, Alt+Backspace (word delete), Ctrl+W, etc.
if [[ -t 0 ]]; then
  # Bind Alt+Backspace to backward-kill-word if not already set
  bind '"\e\x7f": backward-kill-word' 2>/dev/null || true
  # Bind Ctrl+Left/Right for word movement
  bind '"\e[1;5D": backward-word' 2>/dev/null || true
  bind '"\e[1;5C": forward-word' 2>/dev/null || true
  # macOS Option+Left/Right
  bind '"\eb": backward-word' 2>/dev/null || true
  bind '"\ef": forward-word' 2>/dev/null || true
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly ITALIC='\033[3m'
readonly NC='\033[0m'

# Box drawing characters
readonly BOX_H='─'
readonly BOX_V='│'
readonly BOX_TL='┌'
readonly BOX_TR='┐'
readonly BOX_BL='└'
readonly BOX_BR='┘'
readonly BOX_T='┬'
readonly BOX_B='┴'
readonly BOX_L='├'
readonly BOX_R='┤'
readonly BOX_X='┼'

# Step tracking
TOTAL_STEPS=7
CURRENT_STEP=0
STEP_START_TIME=0
SESSION_START_TIME=0
declare -a STEP_NAMES=("Repo Analysis" "Feature Input" "Refinement" "Research" "Summary" "Flow Diagram" "Database Sync")
declare -a STEP_STATUS=("pending" "pending" "pending" "pending" "pending" "pending" "pending")
declare -a STEP_DURATIONS=(0 0 0 0 0 0 0)

# Spinner characters (braille pattern for smooth animation)
readonly SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

# Spinner PID for cleanup
SPINNER_PID=""

# Start spinner animation in background
# Usage: start_spinner "message"
start_spinner() {
  local message="${1:-Working...}"
  local delay=0.1
  local i=0
  local len=${#SPINNER_CHARS}

  # Hide cursor
  tput civis 2>/dev/null || true

  while true; do
    local char="${SPINNER_CHARS:$i:1}"
    printf "\r${CYAN}%s${NC} %s" "$char" "$message"
    i=$(( (i + 1) % len ))
    sleep "$delay"
  done &
  SPINNER_PID=$!
}

# Stop spinner and show completion
# Usage: stop_spinner [success_message]
stop_spinner() {
  local message="${1:-Done}"

  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi

  # Show cursor again
  tput cnorm 2>/dev/null || true

  # Clear the spinner line and show completion
  printf "\r%-80s\r" " "
  if [[ -n "$message" ]]; then
    echo -e "${GREEN}✓${NC} $message"
  fi
}

# Cleanup spinner on exit/interrupt
cleanup_spinner() {
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  tput cnorm 2>/dev/null || true
}

# Double Ctrl+C to exit
LAST_INTERRUPT_TIME=0
INTERRUPT_THRESHOLD=1  # seconds

handle_interrupt() {
  local current_time
  current_time=$(date +%s)
  local time_diff=$((current_time - LAST_INTERRUPT_TIME))

  # Clean up spinner first
  cleanup_spinner

  if [ "$time_diff" -le "$INTERRUPT_THRESHOLD" ]; then
    # Second Ctrl+C within threshold - exit
    echo ""
    echo -e "${YELLOW}Exiting...${NC}"
    exit 130
  else
    # First Ctrl+C - warn user
    LAST_INTERRUPT_TIME=$current_time
    echo ""
    echo -e "${YELLOW}Press Ctrl+C again to exit${NC}"
  fi
}

# Trap signals
trap handle_interrupt INT
trap cleanup_spinner EXIT TERM

# ═══════════════════════════════════════════════════════════════════════════════
# Visual Helper Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Draw a horizontal line
draw_line() {
  local width="${1:-60}"
  local char="${2:-$BOX_H}"
  printf '%*s' "$width" '' | tr ' ' "$char"
  echo ""
}

# Draw a box around text
draw_box() {
  local text="$1"
  local width="${2:-60}"
  local padding=$(( (width - ${#text} - 2) / 2 ))

  echo -e "${CYAN}${BOX_TL}$(printf '%*s' $((width-2)) '' | tr ' ' "$BOX_H")${BOX_TR}${NC}"
  echo -e "${CYAN}${BOX_V}${NC}$(printf '%*s' $padding '')${BOLD}${WHITE}$text${NC}$(printf '%*s' $((width - padding - ${#text} - 2)) '')${CYAN}${BOX_V}${NC}"
  echo -e "${CYAN}${BOX_BL}$(printf '%*s' $((width-2)) '' | tr ' ' "$BOX_H")${BOX_BR}${NC}"
}

# Show ASCII banner
show_banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  cat << 'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║                                                           ║
  ║   ███████╗███████╗ █████╗ ████████╗██╗   ██╗██████╗ ███████╗║
  ║   ██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║   ██║██╔══██╗██╔════╝║
  ║   █████╗  █████╗  ███████║   ██║   ██║   ██║██████╔╝█████╗  ║
  ║   ██╔══╝  ██╔══╝  ██╔══██║   ██║   ██║   ██║██╔══██╗██╔══╝  ║
  ║   ██║     ███████╗██║  ██║   ██║   ╚██████╔╝██║  ██║███████╗║
  ║   ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝║
  ║                                                           ║
  ║            I N T E R R O G A T E                          ║
  ║                                                           ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
}

# Format duration in human readable format
format_duration() {
  local seconds=$1
  if [ "$seconds" -lt 60 ]; then
    echo "${seconds}s"
  elif [ "$seconds" -lt 3600 ]; then
    echo "$((seconds / 60))m $((seconds % 60))s"
  else
    echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
  fi
}

# Show step header with progress
show_step_header() {
  local step_num=$1
  local step_title="$2"
  local step_type="${3:-research}"  # research, input, sync

  CURRENT_STEP=$step_num
  STEP_START_TIME=$(date +%s)
  STEP_STATUS[$((step_num-1))]="in_progress"

  # Choose color based on step type
  local color="$CYAN"
  local icon="🔍"
  case "$step_type" in
    input)    color="$MAGENTA"; icon="📝" ;;
    research) color="$CYAN";    icon="🔬" ;;
    sync)     color="$GREEN";   icon="💾" ;;
    verify)   color="$YELLOW";  icon="✓" ;;
  esac

  echo ""
  echo -e "${DIM}$(draw_line 60)${NC}"
  echo -e "${color}${BOLD}  $icon  Step [$step_num/$TOTAL_STEPS] $step_title${NC}"
  echo -e "${DIM}$(draw_line 60)${NC}"
  echo ""
}

# Complete a step and show duration
complete_step() {
  local step_num=$1
  local message="${2:-Complete}"

  local end_time=$(date +%s)
  local duration=$((end_time - STEP_START_TIME))
  STEP_DURATIONS[$((step_num-1))]=$duration
  STEP_STATUS[$((step_num-1))]="complete"

  echo -e "${GREEN}✓${NC} $message ${DIM}($(format_duration $duration))${NC}"
}

# Show progress summary
show_progress_summary() {
  echo ""
  echo -e "${DIM}${BOX_TL}$(printf '%*s' 58 '' | tr ' ' "$BOX_H")${BOX_TR}${NC}"
  echo -e "${DIM}${BOX_V}${NC}  ${BOLD}Progress${NC}                                                ${DIM}${BOX_V}${NC}"
  echo -e "${DIM}${BOX_L}$(printf '%*s' 58 '' | tr ' ' "$BOX_H")${BOX_R}${NC}"

  for i in "${!STEP_NAMES[@]}"; do
    local status_icon="○"
    local status_color="$DIM"
    local duration_str=""

    case "${STEP_STATUS[$i]}" in
      complete)
        status_icon="●"
        status_color="$GREEN"
        duration_str=" ${DIM}($(format_duration ${STEP_DURATIONS[$i]}))${NC}"
        ;;
      in_progress)
        status_icon="◐"
        status_color="$YELLOW"
        ;;
    esac

    printf "${DIM}${BOX_V}${NC}  ${status_color}%s${NC} %-20s%s%*s${DIM}${BOX_V}${NC}\n" \
      "$status_icon" "${STEP_NAMES[$i]}" "$duration_str" $((35 - ${#duration_str})) ""
  done

  echo -e "${DIM}${BOX_BL}$(printf '%*s' 58 '' | tr ' ' "$BOX_H")${BOX_BR}${NC}"
}

# Show input mode indicator
show_input_mode() {
  local prompt_text="${1:-Enter your response}"
  echo ""
  echo -e "${MAGENTA}${BOLD}  📝 INPUT MODE${NC}"
  echo -e "${DIM}  $prompt_text${NC}"
  echo -e "${DIM}  [Enter] submit line • [Empty line] finish • [Ctrl+C ×2] exit${NC}"
  echo ""
}

# Styled input prompt
input_prompt() {
  echo -ne "${MAGENTA}▸${NC} "
}

# Print dim file path
dim_path() {
  echo -e "${DIM}$1${NC}"
}

# Generate HTML wrapper for mermaid diagram
# Usage: generate_html_diagram <markdown_file> <output_html> <title>
generate_html_diagram() {
  local md_file="$1"
  local html_file="$2"
  local title="${3:-Flow Diagram}"

  # Extract mermaid content from markdown (between ```mermaid and ```)
  # Write awk script to temp file to avoid backtick escaping issues
  local awk_script
  awk_script=$(mktemp)
  cat > "$awk_script" << 'AWKEOF'
/^```mermaid$/{flag=1;next}
/^```$/{if(flag){flag=0;exit}}
flag
AWKEOF

  local mermaid_content
  mermaid_content=$(awk -f "$awk_script" "$md_file" 2>/dev/null || echo "")
  rm -f "$awk_script"

  if [ -z "$mermaid_content" ]; then
    log_error "No mermaid diagram found in $md_file"
    return 1
  fi

  # Generate HTML with embedded mermaid.js
  cat > "$html_file" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title</title>
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: #eee;
      min-height: 100vh;
      padding: 2rem;
    }
    .container {
      max-width: 1400px;
      margin: 0 auto;
    }
    h1 {
      color: #B89C4C;
      margin-bottom: 0.5rem;
      font-size: 1.75rem;
    }
    .subtitle {
      color: #888;
      margin-bottom: 2rem;
      font-size: 0.9rem;
    }
    .diagram-wrapper {
      background: #fff;
      border-radius: 12px;
      padding: 2rem;
      box-shadow: 0 10px 40px rgba(0,0,0,0.3);
      overflow-x: auto;
    }
    .mermaid {
      display: flex;
      justify-content: center;
    }
    .footer {
      margin-top: 2rem;
      text-align: center;
      color: #666;
      font-size: 0.8rem;
    }
    .footer a {
      color: #B89C4C;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>$title</h1>
    <p class="subtitle">Generated $(date -u +"%Y-%m-%d %H:%M UTC")</p>
    <div class="diagram-wrapper">
      <pre class="mermaid">
$mermaid_content
      </pre>
    </div>
    <p class="footer">
      Generated by <a href="#">Feature Interrogate</a> | KC Cattle Company ERP
    </p>
  </div>
  <script>
    mermaid.initialize({
      startOnLoad: true,
      theme: 'default',
      flowchart: {
        useMaxWidth: true,
        htmlLabels: true,
        curve: 'basis'
      }
    });
  </script>
</body>
</html>
HTMLEOF

  log "HTML diagram generated: $html_file"
  return 0
}

# Show keyboard hints
show_hints() {
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
  echo -e "${DIM}  [Enter] submit • [Ctrl+C ×2] exit${NC}"
  echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

# Load architecture index for diagram vocabulary
# Returns the architecture index content or a fallback message
load_architecture_context() {
  local index_file="$PROJECT_ROOT/.claude/cache/architecture/index.yaml"
  local builder="$SCRIPT_DIR/build_architecture_index.sh"

  # Ensure index is built/current
  if [ -x "$builder" ]; then
    "$builder" "$PROJECT_ROOT" >/dev/null 2>&1 || true
  fi

  if [ -f "$index_file" ]; then
    # Return the index content
    cat "$index_file"
  else
    echo "# No architecture index available - use generic component names"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Diagram Verification Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Pre-validate Mermaid syntax with fast regex checks (catches ~80% of issues)
# Usage: prevalidate_mermaid "$mermaid_code"
# Returns: 0 if valid, 1 with error messages if invalid
prevalidate_mermaid() {
  local code="$1"
  local errors=()

  # Check for diagram type declaration
  if ! echo "$code" | head -1 | grep -qE "^(graph|flowchart|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt|pie|gitGraph)"; then
    errors+=("Missing diagram type declaration (e.g., flowchart TD)")
  fi

  # Check for reserved word 'end' used as node ID (common mistake)
  # Match 'end' as a standalone node, not inside subgraph 'end' statements
  # Filter out valid 'end' statements first, then check for 'end' used as node
  local filtered_code
  filtered_code=$(echo "$code" | grep -vE "^[[:space:]]*end[[:space:]]*$")
  if echo "$filtered_code" | grep -qE '(^|[[:space:]]|>|])end([[:space:]]|\[|\(|$)'; then
    errors+=("Reserved word 'end' used as node ID - use 'End' or 'done' instead")
  fi

  # Check subgraph balance
  local subgraph_count
  local end_count
  subgraph_count=$(echo "$code" | grep -c "subgraph " 2>/dev/null | tr -d '[:space:]' || echo "0")
  end_count=$(echo "$code" | grep -cE "^[[:space:]]*end[[:space:]]*$" 2>/dev/null | tr -d '[:space:]' || echo "0")
  # Default to 0 if empty
  [ -z "$subgraph_count" ] && subgraph_count=0
  [ -z "$end_count" ] && end_count=0
  if [ "$subgraph_count" -gt 0 ] && [ "$subgraph_count" -ne "$end_count" ]; then
    errors+=("Unbalanced subgraphs: $subgraph_count 'subgraph' vs $end_count 'end' statements")
  fi

  # Check bracket balance
  local open_brackets
  local close_brackets
  open_brackets=$(echo "$code" | tr -cd '[' | wc -c | tr -d ' ')
  close_brackets=$(echo "$code" | tr -cd ']' | wc -c | tr -d ' ')
  if [ "$open_brackets" -ne "$close_brackets" ]; then
    errors+=("Unbalanced brackets: $open_brackets '[' vs $close_brackets ']'")
  fi

  # Check parenthesis balance
  local open_parens
  local close_parens
  open_parens=$(echo "$code" | tr -cd '(' | wc -c | tr -d ' ')
  close_parens=$(echo "$code" | tr -cd ')' | wc -c | tr -d ' ')
  if [ "$open_parens" -ne "$close_parens" ]; then
    errors+=("Unbalanced parentheses: $open_parens '(' vs $close_parens ')'")
  fi

  # Check for common arrow syntax errors
  if echo "$code" | grep -qE "->-|-->->|<--<|>-->"; then
    errors+=("Invalid arrow syntax detected (e.g., ->-, -->->)")
  fi

  # Check for unclosed quotes in labels
  local quote_count
  quote_count=$(echo "$code" | tr -cd '"' | wc -c | tr -d ' ')
  if [ $((quote_count % 2)) -ne 0 ]; then
    errors+=("Unclosed double quote in diagram")
  fi

  # Return results
  if [ ${#errors[@]} -gt 0 ]; then
    printf '%s\n' "${errors[@]}"
    return 1
  fi
  return 0
}

# Extract entity names (node IDs, table references) from a diagram file
# Usage: extract_diagram_entities "$diagram_file"
# Output: One entity per line
extract_diagram_entities() {
  local file="$1"

  # Extract mermaid content first
  local mermaid_content
  mermaid_content=$(awk '/^```mermaid$/,/^```$/' "$file" 2>/dev/null | grep -v '^```' || cat "$file")

  {
    # Extract node IDs (words followed by [ or ( or {)
    echo "$mermaid_content" | grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[\[\(\{]' | \
      sed 's/[[:space:]]*//g; s/[\[\(\{]$//' | sort -u

    # Extract CRUD references
    echo "$mermaid_content" | grep -oE 'CRUD:[[:space:]]*[A-Za-z_]+' | \
      sed 's/CRUD:[[:space:]]*//' | sort -u

    # Extract table references from database notation [(table_name)]
    echo "$mermaid_content" | grep -oE '\[\([A-Za-z_]+\)\]' | \
      sed 's/\[[(]//g; s/[)]\]//g' | sort -u

    # Extract explicit table names from comments or labels
    echo "$mermaid_content" | grep -oE 'table:[[:space:]]*[A-Za-z_]+' | \
      sed 's/table:[[:space:]]*//' | sort -u
  } | sort -u | grep -v '^$'
}

# Normalize entity name for matching
# Usage: normalize_name "EntityName"
# Output: normalized lowercase name without underscores
# NOTE: Removed trailing 's' removal - causes overstemming (address→addres, status→statu)
normalize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/_//g'
}

# Check if query is a subsequence of candidate (case-insensitive)
# Used for fuzzy matching abbreviations like "inv" matching "inventory_items"
# Usage: is_subsequence_match "query" "candidate"
# Returns: 0 if match, 1 if no match
is_subsequence_match() {
  local query="$1"
  local candidate="$2"
  query=$(echo "$query" | tr '[:upper:]' '[:lower:]')
  candidate=$(echo "$candidate" | tr '[:upper:]' '[:lower:]')

  local q_len=${#query}
  local q_idx=0

  for (( i=0; i<${#candidate}; i++ )); do
    if [[ "${candidate:$i:1}" == "${query:$q_idx:1}" ]]; then
      ((q_idx++))
      [[ $q_idx -eq $q_len ]] && return 0
    fi
  done
  return 1
}

# Check if an entity exists in the architecture index
# Uses subsequence matching for abbreviation support (e.g., "inv" matches "inventory_items")
# Usage: check_entity_against_index "entity_name" "index_file"
# Output: "EXISTING" or "NEW"
check_entity_against_index() {
  local entity="$1"
  local index_file="$2"

  if [ ! -f "$index_file" ]; then
    echo "NEW"
    return
  fi

  # Fast path: Try exact match first (case-insensitive word boundary)
  if grep -qi "\b$entity\b" "$index_file"; then
    echo "EXISTING"
    return
  fi

  # Extract all known entity names from the index file
  local known_entities
  known_entities=$(grep -oE '[a-z_][a-z0-9_]*' "$index_file" 2>/dev/null | sort -u)

  # Try subsequence match against known entities
  # This handles abbreviations like "inv" -> "inventory_items"
  # and pluralization like "items" -> "inventory_items"
  while IFS= read -r known_entity; do
    [ -z "$known_entity" ] && continue
    # Skip very short entries (likely noise)
    [ ${#known_entity} -lt 3 ] && continue

    # Check if entity is a subsequence of known_entity (abbreviation match)
    if is_subsequence_match "$entity" "$known_entity"; then
      echo "EXISTING"
      return
    fi

    # Check if known_entity is a subsequence of entity (reverse match)
    if is_subsequence_match "$known_entity" "$entity"; then
      echo "EXISTING"
      return
    fi

    # Check normalized versions (handles underscores and case)
    local entity_norm known_norm
    entity_norm=$(normalize_name "$entity")
    known_norm=$(normalize_name "$known_entity")
    if [ "$entity_norm" = "$known_norm" ]; then
      echo "EXISTING"
      return
    fi
  done <<< "$known_entities"

  echo "NEW"
}

# Verify diagram covers the original request (semantic check using LLM)
# Uses adversarial framing to counter LLM agreeableness bias
# Usage: verify_request_coverage "$diagram_content" "$original_request"
# Returns: 0 if coverage complete, 1 with issues if problems found
verify_request_coverage() {
  local diagram="$1"
  local original_request="$2"

  if ! command -v claude &> /dev/null; then
    # Skip semantic check if Claude not available
    return 0
  fi

  local prompt="You are a critical code reviewer. Your job is to find problems.

ORIGINAL FEATURE REQUEST:
$original_request

GENERATED MERMAID DIAGRAM:
$diagram

TASK: List any ways the diagram FAILS to address the feature request.
Be adversarial - actively look for missing pieces.

If the diagram fully addresses all aspects of the request, respond with exactly:
COVERAGE_COMPLETE

Otherwise, list specific issues:
1. Missing user flows mentioned in request
2. Missing data operations implied by request
3. Wrong or missing tables/endpoints for the feature domain
4. Missing layer connections (UI→API→DB)"

  local response
  response=$(claude --dangerously-skip-permissions --print "$prompt" 2>&1) || {
    # If Claude fails, skip this check
    return 0
  }

  if echo "$response" | grep -q "COVERAGE_COMPLETE"; then
    return 0
  else
    echo "$response"
    return 1
  fi
}

# Main verification function with auto-regeneration loop
# Usage: verify_and_regenerate "$diagram_file" "$index_file" "$original_request" "$session_dir"
# Returns: 0 if valid (possibly after fixes), 1 if still invalid after max retries
verify_and_regenerate() {
  local diagram_file="$1"
  local index_file="$2"
  local original_request="$3"
  local session_dir="$4"
  local max_retries=3
  local retry=0

  while [ $retry -lt $max_retries ]; do
    local errors=""
    local new_entities=()

    # Extract mermaid content
    local mermaid_content
    mermaid_content=$(awk '/^```mermaid$/,/^```$/' "$diagram_file" 2>/dev/null | grep -v '^```' || echo "")

    if [ -z "$mermaid_content" ]; then
      log_warn "No mermaid content found in diagram file"
      return 1
    fi

    # Step 1: Syntax pre-validation (fast)
    local syntax_errors
    if ! syntax_errors=$(prevalidate_mermaid "$mermaid_content" 2>&1); then
      errors="SYNTAX ERRORS:\n$syntax_errors\n\n"
    fi

    # Step 2: Schema alignment check - collect NEW entities
    if [ -f "$index_file" ]; then
      while IFS= read -r entity; do
        [ -z "$entity" ] && continue
        local status
        status=$(check_entity_against_index "$entity" "$index_file")
        if [ "$status" = "NEW" ]; then
          new_entities+=("$entity")
        fi
      done < <(extract_diagram_entities "$diagram_file")
    fi

    # Step 3: Semantic coverage check (only if syntax passes to save API calls)
    if [ -z "$errors" ]; then
      local coverage_errors
      if ! coverage_errors=$(verify_request_coverage "$mermaid_content" "$original_request" 2>&1); then
        if [ -n "$coverage_errors" ]; then
          errors="COVERAGE ISSUES:\n$coverage_errors\n\n"
        fi
      fi
    fi

    # All checks passed
    if [ -z "$errors" ]; then
      # Annotate NEW entities with green styling if any were found
      if [ ${#new_entities[@]} -gt 0 ]; then
        log "Annotating ${#new_entities[@]} new entities in diagram"

        # Add classDef and class statements for new entities
        local annotation=""
        annotation+="\n    %% NEW ENTITIES (proposed additions to architecture)\n"
        annotation+="    classDef newEntity fill:#e6ffe6,stroke:#00aa00,stroke-width:2px\n"
        for e in "${new_entities[@]}"; do
          annotation+="    class $e newEntity\n"
        done

        # Insert before the closing ``` if present
        if grep -q '```$' "$diagram_file"; then
          sed -i "s/\`\`\`$/${annotation}\`\`\`/" "$diagram_file"
        else
          echo -e "$annotation" >> "$diagram_file"
        fi

        # Save new entities list for reference
        printf '%s\n' "${new_entities[@]}" > "$session_dir/new-entities.txt"
        log "New entities saved to new-entities.txt: ${new_entities[*]}"
      fi

      log_success "Diagram validation passed"
      return 0
    fi

    # Issues found - attempt regeneration
    retry=$((retry + 1))
    if [ $retry -ge $max_retries ]; then
      break
    fi

    log_warn "Issues found (attempt $retry/$max_retries). Regenerating..."

    # Save the issues for debugging
    echo -e "Validation attempt $retry:\n$errors" >> "$session_dir/validation-log.txt"

    # Regenerate with specific feedback about errors
    if command -v claude &> /dev/null; then
      local fix_prompt="Fix these issues in the Mermaid diagram:

CURRENT DIAGRAM:
$mermaid_content

ISSUES FOUND:
$(echo -e "$errors")

ORIGINAL FEATURE REQUEST:
$original_request

Generate a corrected Mermaid flowchart that fixes ALL the issues above.
Output ONLY the corrected diagram in a mermaid code block."

      # Save current diagram as backup
      cp "$diagram_file" "$diagram_file.backup-$retry"

      # Regenerate
      claude --dangerously-skip-permissions --print "$fix_prompt" 2>&1 > "$diagram_file" || {
        log_error "Regeneration failed, restoring backup"
        cp "$diagram_file.backup-$retry" "$diagram_file"
      }
    else
      log_warn "Claude CLI not available for auto-fix"
      break
    fi
  done

  # Max retries reached
  log_warn "Max retries ($max_retries) reached. Manual review recommended."
  echo -e "Final validation errors:\n$errors" >> "$session_dir/validation-log.txt"
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Diagram Caching Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Cache a diagram to persistent storage for historical record
# Usage: cache_diagram "source_file" "session_name" "diagram_type" "iteration"
# diagram_type: flow, user-journey, sequence, state, suite
# Returns: 0 on success, 1 on failure
cache_diagram() {
  local source_file="$1"
  local session_name="$2"
  local diagram_type="${3:-flow}"
  local iteration="${4:-1}"

  # Validate source exists
  if [ ! -f "$source_file" ]; then
    return 1
  fi

  # Create cache directory structure
  local cache_base="$PROJECT_ROOT/.claude/cache/diagrams"
  local cache_dir="$cache_base/$session_name"
  mkdir -p "$cache_dir"

  # Generate timestamp for unique filename
  local timestamp
  timestamp=$(date -u +"%Y%m%d-%H%M%S")

  # Determine file extension
  local ext="${source_file##*.}"

  # Create cached filename: {type}-iter{N}-{timestamp}.{ext}
  local cached_filename="${diagram_type}-iter${iteration}-${timestamp}.${ext}"
  local cached_path="$cache_dir/$cached_filename"

  # Copy the diagram
  cp "$source_file" "$cached_path"

  # Create/update metadata file for this session
  local meta_file="$cache_dir/metadata.yaml"

  # Append to metadata (create if doesn't exist)
  if [ ! -f "$meta_file" ]; then
    cat > "$meta_file" << EOF
session: $session_name
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
diagrams: []
EOF
  fi

  # Append diagram entry to metadata
  cat >> "$meta_file" << EOF

- file: $cached_filename
  type: $diagram_type
  iteration: $iteration
  cached_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
  source: $(basename "$source_file")
  size_bytes: $(wc -c < "$source_file" | tr -d ' ')
EOF

  # Also maintain a global index of all cached diagrams
  local global_index="$cache_base/index.log"
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | $session_name | $diagram_type | iter$iteration | $cached_filename" >> "$global_index"

  # Symlink to "latest" for each type within session
  local latest_link="$cache_dir/${diagram_type}-latest.${ext}"
  ln -sf "$cached_filename" "$latest_link" 2>/dev/null || true

  return 0
}

# Cache all diagrams from a session directory
# Usage: cache_session_diagrams "session_dir" "session_name"
cache_session_diagrams() {
  local session_dir="$1"
  local session_name="$2"
  local cached_count=0

  # Cache flow diagram iterations
  for f in "$session_dir"/flow-diagram-iter-*.md; do
    [ -f "$f" ] || continue
    local iter
    iter=$(echo "$f" | grep -oE 'iter-[0-9]+' | grep -oE '[0-9]+')
    if cache_diagram "$f" "$session_name" "flow" "$iter"; then
      ((cached_count++))
    fi
  done

  # Cache HTML versions too
  for f in "$session_dir"/flow-diagram-iter-*.html; do
    [ -f "$f" ] || continue
    local iter
    iter=$(echo "$f" | grep -oE 'iter-[0-9]+' | grep -oE '[0-9]+')
    cache_diagram "$f" "$session_name" "flow-html" "$iter" || true
  done

  # Cache confirmed flow diagram
  if [ -f "$session_dir/flow-diagram.md" ]; then
    cache_diagram "$session_dir/flow-diagram.md" "$session_name" "flow-confirmed" "final"
  fi

  # Cache supplementary diagrams
  for dtype in user-journey sequence state; do
    if [ -f "$session_dir/${dtype}-diagram.md" ]; then
      cache_diagram "$session_dir/${dtype}-diagram.md" "$session_name" "$dtype" "1"
    fi
  done

  # Cache the combined suite HTML
  if [ -f "$session_dir/feature-diagrams.html" ]; then
    cache_diagram "$session_dir/feature-diagrams.html" "$session_name" "suite-html" "1"
  fi

  echo "$cached_count"
}

# List cached diagrams for a session or all sessions
# Usage: list_cached_diagrams [session_name]
list_cached_diagrams() {
  local session_name="${1:-}"
  local cache_base="$PROJECT_ROOT/.claude/cache/diagrams"

  if [ ! -d "$cache_base" ]; then
    echo "No cached diagrams found"
    return 0
  fi

  if [ -n "$session_name" ]; then
    # List diagrams for specific session
    local cache_dir="$cache_base/$session_name"
    if [ -d "$cache_dir" ]; then
      echo "Cached diagrams for '$session_name':"
      ls -la "$cache_dir" | grep -v "^total\|^d\|metadata\|index" | awk '{print "  " $NF " (" $5 " bytes)"}'
    else
      echo "No cached diagrams for session '$session_name'"
    fi
  else
    # List all sessions with diagram counts
    echo "Cached diagram sessions:"
    for d in "$cache_base"/*/; do
      [ -d "$d" ] || continue
      local sname
      sname=$(basename "$d")
      local count
      count=$(find "$d" -maxdepth 1 -type f \( -name "*.md" -o -name "*.html" \) | wc -l | tr -d ' ')
      echo "  $sname: $count diagrams"
    done

    # Show global stats
    if [ -f "$cache_base/index.log" ]; then
      local total
      total=$(wc -l < "$cache_base/index.log" | tr -d ' ')
      echo ""
      echo "Total cached: $total diagrams"
    fi
  fi
}

# Session variables
SESSION_NAME=""
SESSION_DIR=""
SCOPE_DIR=""
FEATURE_DESCRIPTION=""
REFINED_DESCRIPTION=""
RESUME_MODE=false
RESUME_FROM_STEP=1

# Show help
show_help() {
  cat << 'EOF'
Feature Interrogate - Interactive Feature Discovery

Usage:
  ./feature_interrogate.sh [session-name]
  ./feature_interrogate.sh --resume <session-name>
  ./feature_interrogate.sh --list
  ./feature_interrogate.sh --help

Options:
  session-name        Name for this discovery session (default: feature-YYYYMMDD-HHMMSS)
  --resume, -r        Resume an existing session from where it left off
  --list, -l          List all existing sessions with their progress
  --help, -h          Show this help message

Pipeline Steps:
  1. Repo Familiarization  - Understand the current repository via /dr
  2. Feature Input         - Prompt user to describe the feature
  3. Requirement Refinement- Use /dr-refine to clarify requirements
  4. Deep Research         - Research user flows and open source tools
  5. Conversation Summary  - Save discovery summary
  6. Flow Diagram Loop     - Generate and verify flow diagram
  7. Database Sync         - Persist to PostgreSQL

Output Files:
  .claude/RESEARCH/{session}/
  ├── repo-analysis.md        - Repository understanding
  ├── feature-input.md        - Original user request
  ├── refined-requirements.md - After /dr-refine clarification
  ├── research-output.md      - /dr research results
  ├── summary.md              - Complete conversation summary
  ├── flow-feedback.md        - User feedback during iterations
  └── flow-confirmed.txt      - Confirmation marker

  .claude/scopes/{session}/
  ├── 00_scope_document.md    - Main scope document
  ├── 01_features.md          - Features extracted
  └── 02_user_journeys.md     - User journeys extracted

Examples:
  ./feature_interrogate.sh user-auth-feature   # New session with name
  ./feature_interrogate.sh                     # New session (auto-name)
  ./feature_interrogate.sh --list              # List existing sessions
  ./feature_interrogate.sh --resume feature-20260124-231602  # Resume session
EOF
  exit 0
}

# List existing sessions with progress
list_sessions() {
  local research_dir=".claude/RESEARCH"

  if [ ! -d "$research_dir" ]; then
    echo "No sessions found."
    exit 0
  fi

  local sessions=($(ls -1d "$research_dir"/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null || true))

  if [ ${#sessions[@]} -eq 0 ]; then
    echo "No sessions found."
    exit 0
  fi

  echo ""
  echo -e "${BOLD}Existing Sessions:${NC}"
  echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
  printf "  ${BOLD}%-30s %s${NC}\n" "SESSION" "PROGRESS"
  echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"

  for session in "${sessions[@]}"; do
    local session_dir="$research_dir/$session"
    local completed=0
    local total=7

    # Check each step's completion
    [ -f "$session_dir/repo-analysis.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/feature-input.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/refined-requirements.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/research-output.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/summary.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/flow-confirmed.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/scope-synced.txt" ] && completed=$((completed + 1))

    # Progress bar
    local bar=""
    for ((i=1; i<=total; i++)); do
      if [ $i -le $completed ]; then
        bar+="${GREEN}█${NC}"
      else
        bar+="${DIM}░${NC}"
      fi
    done

    local status_text=""
    if [ $completed -eq $total ]; then
      status_text="${GREEN}Complete${NC}"
    elif [ $completed -eq 0 ]; then
      status_text="${DIM}Not started${NC}"
    else
      status_text="${YELLOW}Step $((completed + 1))${NC}"
    fi

    printf "  %-30s " "$session"
    echo -e "$bar $completed/$total $status_text"
  done

  echo ""
  echo -e "${DIM}Resume with: ./feature_interrogate.sh --resume <session-name>${NC}"
  echo ""
  exit 0
}

# Detect completed steps and return the next step to run
detect_completed_steps() {
  local session_dir="$1"

  # Check steps in reverse order to find where to resume
  if [ -f "$session_dir/scope-synced.txt" ]; then
    echo 8  # All complete
  elif [ -f "$session_dir/flow-confirmed.txt" ]; then
    echo 7  # Resume from step 7 (db sync)
  elif [ -f "$session_dir/summary.md" ]; then
    echo 6  # Resume from step 6 (flow diagram)
  elif [ -f "$session_dir/research-output.md" ]; then
    echo 5  # Resume from step 5 (summary)
  elif [ -f "$session_dir/refined-requirements.md" ]; then
    echo 4  # Resume from step 4 (research)
  elif [ -f "$session_dir/feature-input.md" ]; then
    echo 3  # Resume from step 3 (refine)
  elif [ -f "$session_dir/repo-analysis.md" ]; then
    echo 2  # Resume from step 2 (feature input)
  else
    echo 1  # Start from beginning
  fi
}

# Load session data for resume
load_session_data() {
  local session_dir="$1"

  # Load feature description if it exists
  if [ -f "$session_dir/feature-input.md" ]; then
    # Extract content after frontmatter
    FEATURE_DESCRIPTION=$(sed '1,/^---$/d; 1,/^---$/d' "$session_dir/feature-input.md" | sed 's/^# Initial Feature Request//' | sed '/^$/d' | head -20)
  fi

  # Load refined description if it exists
  if [ -f "$session_dir/refined-requirements.md" ]; then
    # Extract the "After Clarification" section
    REFINED_DESCRIPTION=$(sed -n '/^## After Clarification/,/^## /p' "$session_dir/refined-requirements.md" | sed '1d;$d' | head -20)
  fi
}

log() {
  echo -e "  ${BLUE}▸${NC} $1"
}

log_success() {
  echo -e "  ${GREEN}✓${NC} $1"
}

log_error() {
  echo -e "  ${RED}✗${NC} $1" >&2
}

log_warn() {
  echo -e "  ${YELLOW}⚠${NC} $1"
}

log_step() {
  echo ""
  echo -e "${DIM}$(printf '%60s' '' | tr ' ' '─')${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${DIM}$(printf '%60s' '' | tr ' ' '─')${NC}"
  echo ""
}

log_separator() {
  echo ""
  echo -e "${DIM}  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─${NC}"
  echo ""
}

# Initialize session directories
init_session() {
  local name="$1"

  SESSION_NAME="$name"
  SESSION_DIR=".claude/RESEARCH/$SESSION_NAME"
  SCOPE_DIR=".claude/scopes/$SESSION_NAME"
  SESSION_START_TIME=$(date +%s)

  mkdir -p "$SESSION_DIR"
  mkdir -p "$SCOPE_DIR"

  echo -e "  ${BOLD}Session:${NC} $SESSION_NAME"
  echo -e "  ${DIM}Research: $SESSION_DIR${NC}"
  echo -e "  ${DIM}Scope:    $SCOPE_DIR${NC}"
  echo ""
}

# Helper: Generate repo diagram suite (Architecture, ERD, User Flows, API Sequence, User Journeys)
generate_repo_architecture_diagram() {
  if [ ! -x "$SCRIPT_DIR/generate_repo_diagrams.sh" ]; then
    log_warn "Diagram suite script not found"
    return 1
  fi

  log "Generating diagram suite (Architecture, ERD, User Flows, API Sequence, User Journeys)..."
  "$SCRIPT_DIR/generate_repo_diagrams.sh" "$SESSION_DIR" 2>/dev/null || {
    log_warn "Diagram suite generation failed"
    return 1
  }

  if [ -f "$SESSION_DIR/repo-diagrams.md" ]; then
    dim_path "  Saved: $SESSION_DIR/repo-diagrams.md"

    if [ -f "$SESSION_DIR/repo-diagrams.html" ]; then
      echo ""
      echo -e "  ${CYAN}${BOLD}View diagram suite:${NC}"
      echo -e "  ${CYAN}http://ubuntu.desmana-truck.ts.net:32082/$SESSION_NAME/repo-diagrams.html${NC}"
      echo ""
      echo -e "  ${DIM}Tabs: Architecture | ERD | User Flows | API Sequence | User Journeys${NC}"
      echo ""
    fi
  fi
}

# Step 1: Understand the repository (with caching)
familiarize_repo() {
  show_step_header 1 "Understanding This Repository" "research"

  # Cache location (persistent across sessions)
  local cache_dir=".claude/cache"
  local cache_file="$cache_dir/repo-analysis.md"
  local cache_hash_file="$cache_dir/repo-analysis.hash"

  mkdir -p "$cache_dir"

  # Get current git state
  local current_hash
  current_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  local cached_hash=""

  if [ -f "$cache_hash_file" ]; then
    cached_hash=$(cat "$cache_hash_file")
  fi

  # Check if we can use cached analysis
  if [ -f "$cache_file" ] && [ "$current_hash" = "$cached_hash" ]; then
    # No changes since last analysis - use cache
    cp "$cache_file" "$SESSION_DIR/repo-analysis.md"
    complete_step 1 "Using cached analysis (no changes)"
    dim_path "  Saved: $SESSION_DIR/repo-analysis.md"

    # Generate repo architecture diagram even when using cache
    generate_repo_architecture_diagram
    return 0
  fi

  if ! command -v claude &> /dev/null; then
    log_error "Claude CLI not found"
    echo "Repository analysis skipped - Claude CLI not available" > "$SESSION_DIR/repo-analysis.md"
    return 1
  fi

  # Check if we can do incremental update
  if [ -f "$cache_file" ] && [ -n "$cached_hash" ] && [ "$cached_hash" != "unknown" ]; then
    # Get diff since last analysis
    local diff_stat
    diff_stat=$(git diff --stat "$cached_hash" HEAD 2>/dev/null || echo "")
    local files_changed
    files_changed=$(git diff --name-only "$cached_hash" HEAD 2>/dev/null | wc -l)

    if [ "$files_changed" -eq 0 ]; then
      # No file changes (maybe just commit messages) - use cache
      cp "$cache_file" "$SESSION_DIR/repo-analysis.md"
      echo "$current_hash" > "$cache_hash_file"
      complete_step 1 "Using cached analysis (no file changes)"
      dim_path "  Saved: $SESSION_DIR/repo-analysis.md"
      generate_repo_architecture_diagram
      return 0
    elif [ "$files_changed" -lt 50 ]; then
      # Incremental update - analyze only changed files
      log "Incremental update: ${YELLOW}$files_changed files${NC} changed since last analysis"

      start_spinner "Updating repository analysis (incremental - $files_changed files changed)..."

      local changed_files
      changed_files=$(git diff --name-only "$cached_hash" HEAD 2>/dev/null | head -100)

      # Create incremental analysis query
      local incremental_query="Update this repository analysis based on recent changes.

PREVIOUS ANALYSIS:
$(cat "$cache_file")

FILES CHANGED SINCE LAST ANALYSIS:
$changed_files

DIFF SUMMARY:
$diff_stat

Provide an updated analysis incorporating these changes. Keep the same format but note any architectural changes, new components, or significant modifications."

      claude --dangerously-skip-permissions --print "$incremental_query" > "$SESSION_DIR/repo-analysis.md" 2>&1 || {
        stop_spinner ""
        log_error "Incremental analysis failed, falling back to cached version"
        cp "$cache_file" "$SESSION_DIR/repo-analysis.md"
        generate_repo_architecture_diagram
        return 0
      }

      stop_spinner "Repository analysis updated (incremental)"

      # Update cache
      cp "$SESSION_DIR/repo-analysis.md" "$cache_file"
      echo "$current_hash" > "$cache_hash_file"
      complete_step 1 "Repository updated (incremental)"
      dim_path "  Saved: $SESSION_DIR/repo-analysis.md"
      generate_repo_architecture_diagram
      return 0
    fi
  fi

  # Full analysis needed (no cache or too many changes)
  log "Full repository analysis required ${DIM}(no cache or >50 files changed)${NC}"
  start_spinner "Analyzing repository structure and patterns (this may take a few minutes)..."

  local repo_query="Analyze this repository: What is its purpose, tech stack, architecture patterns, and key directories? Provide a concise summary."

  claude --dangerously-skip-permissions --print "/dr $repo_query" > "$SESSION_DIR/repo-analysis.md" 2>&1 || {
    stop_spinner ""
    log_error "Repository analysis failed"
    echo "N/A - Analysis could not be completed" > "$SESSION_DIR/repo-analysis.md"
    return 1
  }

  stop_spinner "Repository analysis complete"

  # Update cache
  cp "$SESSION_DIR/repo-analysis.md" "$cache_file"
  echo "$current_hash" > "$cache_hash_file"

  complete_step 1 "Repository analysis complete"
  dim_path "  Saved: $SESSION_DIR/repo-analysis.md"

  # Generate repo architecture diagram
  generate_repo_architecture_diagram
}

# Step 2: Get feature description from user
get_feature_input() {
  show_step_header 2 "Feature Description" "input"

  show_input_mode "What feature would you like to implement? (describe your idea - empty line to continue)"

  # Read multi-line input until empty line
  local input=""
  local line=""
  local first_line=true

  while true; do
    input_prompt
    read -e line
    if [ -z "$line" ] && [ -n "$input" ]; then
      break
    fi
    if [ -n "$input" ]; then
      input="$input
$line"
    else
      input="$line"
    fi
  done

  FEATURE_DESCRIPTION="$input"

  # Save initial input
  cat > "$SESSION_DIR/feature-input.md" << EOF
---
name: $SESSION_NAME
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
type: feature-request
---

# Initial Feature Request

$FEATURE_DESCRIPTION
EOF

  complete_step 2 "Feature description captured"
  dim_path "  Saved: $SESSION_DIR/feature-input.md"
}

# Step 3: Refine requirements
refine_requirements() {
  show_step_header 3 "Refining Requirements" "input"

  log "Claude will ask clarifying questions in a multi-turn conversation..."

  if command -v claude &> /dev/null; then
    # Build context with repo architecture info if available
    local arch_context=""
    if [ -f "$SESSION_DIR/repo-analysis.md" ]; then
      arch_context="

CURRENT REPOSITORY ARCHITECTURE (from Step 1 analysis):
$(cat "$SESSION_DIR/repo-analysis.md")

When asking clarifying questions, consider how the feature fits into this existing architecture.
"
    fi

    # Initialize conversation loop variables
    local conversation_round=0
    local max_rounds=10
    local conversation_history=""
    local full_session=""

    # Initialize refinement session file with header
    cat > "$SESSION_DIR/refinement-session.md" << EOF
---
name: $SESSION_NAME-refinement
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
type: refinement-session
---

# Refinement Session

## Feature Request
$FEATURE_DESCRIPTION

## Conversation

EOF

    echo ""

    # Conversational refinement loop
    while [ "$conversation_round" -lt "$max_rounds" ]; do
      conversation_round=$((conversation_round + 1))

      # Show round indicator
      echo -e "  ${YELLOW}Round $conversation_round${NC} ${DIM}(empty line = done with Q&A)${NC}"
      echo ""

      # Create context file for this round
      local refine_context_file
      refine_context_file=$(mktemp)

      if [ -z "$conversation_history" ]; then
        # First round - initial context
        cat > "$refine_context_file" << EOF
Feature Request: $FEATURE_DESCRIPTION
$arch_context
Please ask clarifying questions to refine this feature request. Consider:
- How it integrates with the existing architecture
- What components already exist that can be leveraged
- What new components would need to be created

Ask 2-3 focused questions to better understand the requirements.
EOF
      else
        # Subsequent rounds - include conversation history
        cat > "$refine_context_file" << EOF
Feature Request: $FEATURE_DESCRIPTION
$arch_context

PREVIOUS CONVERSATION:
$conversation_history

Based on the user's responses above, either:
1. Ask follow-up questions if you need more clarity
2. Or if you have complete clarity, output a "## Final Specification" section summarizing all requirements

IMPORTANT:
- Do NOT ask "Should I run /dr?" or offer next steps
- Do NOT ask "Ready to proceed?"
- When done, just output the final specification and stop
- Keep questions focused and practical
EOF
      fi

      # Run Claude and capture output
      local claude_response
      claude_response=$(claude --dangerously-skip-permissions "/dr-refine $(cat "$refine_context_file")" 2>&1) || {
        log_error "Refinement session had issues"
      }

      # Display Claude's response with streaming effect
      echo "$claude_response"
      echo ""

      # Append to session file
      echo "### Round $conversation_round - Claude" >> "$SESSION_DIR/refinement-session.md"
      echo "" >> "$SESSION_DIR/refinement-session.md"
      echo "$claude_response" >> "$SESSION_DIR/refinement-session.md"
      echo "" >> "$SESSION_DIR/refinement-session.md"

      # Append to conversation history
      conversation_history="${conversation_history}
Claude: $claude_response
"

      rm -f "$refine_context_file"

      # Check if Claude indicates refinement is complete
      if echo "$claude_response" | grep -qiE "complete clarity|final specification|ready to proceed|should I run|would you like me to proceed|shall I proceed"; then
        echo ""
        echo -e "  ${GREEN}${BOLD}Refinement complete - Claude has enough clarity${NC}"
        echo ""

        # Extract the specification from Claude's response (everything after "Final Specification" or similar)
        REFINED_DESCRIPTION="$claude_response"

        # Save refined requirements automatically
        cat > "$SESSION_DIR/refined-requirements.md" << AUTOEOF
---
name: $SESSION_NAME-refined
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
type: refined-requirements
---

# Refined Requirements

## Original Request
$FEATURE_DESCRIPTION

## After Clarification
$REFINED_DESCRIPTION

## Full Conversation
See refinement-session.md for the complete Q&A transcript.
AUTOEOF

        complete_step 3 "Requirements refined (auto-completed after $conversation_round rounds)"
        dim_path "  Saved: $SESSION_DIR/refined-requirements.md"
        dim_path "  Saved: $SESSION_DIR/refinement-session.md"

        # Extract domain context for diagram generation
        if [ -x "$SCRIPT_DIR/extract_domain_context.sh" ]; then
          log "Extracting domain context..."
          "$SCRIPT_DIR/extract_domain_context.sh" "$REFINED_DESCRIPTION" "$SESSION_DIR/domain-context.yaml" 2>/dev/null || {
            log_warn "Domain context extraction skipped"
          }
          if [ -f "$SESSION_DIR/domain-context.yaml" ]; then
            dim_path "  Saved: $SESSION_DIR/domain-context.yaml"
          fi
        fi

        return 0
      fi

      # Get user response
      log_separator
      show_input_mode "Your response (empty line = done with Q&A)"

      local user_response=""
      local line=""

      while true; do
        input_prompt
        read -e line
        if [ -z "$line" ]; then
          # Empty line entered
          if [ -z "$user_response" ]; then
            # First empty line with no input = done
            break
          else
            # Empty line after some input = end of this response
            break
          fi
        fi
        if [ -n "$user_response" ]; then
          user_response="$user_response
$line"
        else
          user_response="$line"
        fi
      done

      # Check if user wants to exit (empty response)
      if [ -z "$user_response" ]; then
        echo -e "  ${GREEN}Exiting Q&A loop${NC}"
        break
      fi

      # Append user response to session file
      echo "### Round $conversation_round - User" >> "$SESSION_DIR/refinement-session.md"
      echo "" >> "$SESSION_DIR/refinement-session.md"
      echo "$user_response" >> "$SESSION_DIR/refinement-session.md"
      echo "" >> "$SESSION_DIR/refinement-session.md"

      # Append to conversation history
      conversation_history="${conversation_history}
User: $user_response
"

      echo ""
    done

    # Check if we hit max rounds
    if [ "$conversation_round" -ge "$max_rounds" ]; then
      echo -e "  ${YELLOW}Reached maximum $max_rounds rounds${NC}"
    fi

    log_separator

    # Ask user to summarize the refined requirements
    show_input_mode "Based on the clarification above, summarize your refined requirements (empty line to continue)"

    local refined=""
    local line=""

    while true; do
      input_prompt
      read -e line
      if [ -z "$line" ] && [ -n "$refined" ]; then
        break
      fi
      if [ -n "$refined" ]; then
        refined="$refined
$line"
      else
        refined="$line"
      fi
    done

    REFINED_DESCRIPTION="$refined"

    # Save refined requirements
    cat > "$SESSION_DIR/refined-requirements.md" << EOF
---
name: $SESSION_NAME-refined
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
type: refined-requirements
---

# Refined Requirements

## Original Request
$FEATURE_DESCRIPTION

## After Clarification
$REFINED_DESCRIPTION

## Full Conversation
See refinement-session.md for the complete Q&A transcript.
EOF

    complete_step 3 "Requirements refined ($conversation_round rounds)"
    dim_path "  Saved: $SESSION_DIR/refined-requirements.md"
    dim_path "  Saved: $SESSION_DIR/refinement-session.md"
  else
    log_error "Claude CLI not found - skipping refinement"
    REFINED_DESCRIPTION="$FEATURE_DESCRIPTION"
    echo "$FEATURE_DESCRIPTION" > "$SESSION_DIR/refined-requirements.md"
    complete_step 3 "Skipped (no Claude CLI)"
  fi

  # Extract domain context for improved diagram generation
  if [ -x "$SCRIPT_DIR/extract_domain_context.sh" ]; then
    local requirements_text="${REFINED_DESCRIPTION:-$FEATURE_DESCRIPTION}"
    log "Extracting domain context..."
    "$SCRIPT_DIR/extract_domain_context.sh" "$requirements_text" "$SESSION_DIR/domain-context.yaml" 2>/dev/null || {
      log_warn "Domain context extraction skipped"
    }
    if [ -f "$SESSION_DIR/domain-context.yaml" ]; then
      dim_path "  Saved: $SESSION_DIR/domain-context.yaml"
    fi
  fi
}

# Step 4: Deep research
research_feature() {
  show_step_header 4 "Researching Implementation" "research"

  local feature_to_research="${REFINED_DESCRIPTION:-$FEATURE_DESCRIPTION}"

  # Load context from previous steps
  local tech_stack=""
  local entities=""

  if [ -f "$SESSION_DIR/repo-analysis.md" ]; then
    tech_stack=$(grep -A8 -i "tech stack\|technology\|stack\|framework" "$SESSION_DIR/repo-analysis.md" 2>/dev/null | head -10)
  fi

  if [ -f "$SESSION_DIR/domain-context.yaml" ]; then
    entities=$(grep -A15 "entities:" "$SESSION_DIR/domain-context.yaml" 2>/dev/null | head -15)
  fi

  # Build context-aware research query
  local research_query="For implementing '$feature_to_research'"

  if [ -n "$tech_stack" ]; then
    research_query="$research_query in a codebase using:
$tech_stack"
  fi

  if [ -n "$entities" ]; then
    research_query="$research_query

Working with these domain entities:
$entities"
  fi

  research_query="$research_query

Research:
1. USER FLOWS: Typical user journeys for this feature
2. LIBRARIES: Specific tools/packages compatible with this tech stack
3. PATTERNS: Architecture patterns that fit the existing codebase
4. PITFALLS: Common mistakes to avoid

Focus on practical, production-ready approaches. Skip generic advice."

  if command -v claude &> /dev/null; then
    # Start spinner while research runs
    start_spinner "Researching user flows and open source tools..."

    claude --dangerously-skip-permissions --print "/dr $research_query" > "$SESSION_DIR/research-output.md" 2>&1 || {
      stop_spinner ""
      log_error "Research had issues"
      echo "Research incomplete - see partial output" >> "$SESSION_DIR/research-output.md"
    }

    stop_spinner ""
    complete_step 4 "Research complete"
    dim_path "  Saved: $SESSION_DIR/research-output.md"

    # Show brief excerpt
    echo ""
    echo -e "  ${DIM}Research highlights:${NC}"
    head -20 "$SESSION_DIR/research-output.md" 2>/dev/null | sed 's/^/  /' || true
    echo -e "  ${DIM}...${NC}"
  else
    log_error "Claude CLI not found - skipping research"
    echo "Research skipped - Claude CLI not available" > "$SESSION_DIR/research-output.md"
    complete_step 4 "Skipped (no Claude CLI)"
  fi
}

# Step 5: Save conversation summary
save_summary() {
  show_step_header 5 "Saving Conversation Summary" "sync"

  local current_date
  current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$SESSION_DIR/summary.md" << EOF
---
name: $SESSION_NAME
created: $current_date
status: in-progress
type: discovery-summary
---

# Feature Discovery Summary: $SESSION_NAME

## Session Info
- Created: $current_date
- Status: In Progress

## Initial Request
$(cat "$SESSION_DIR/feature-input.md" 2>/dev/null | sed '1,/^---$/d; 1,/^---$/d' || echo "N/A")

## Refined Requirements
$(cat "$SESSION_DIR/refined-requirements.md" 2>/dev/null | sed '1,/^---$/d; 1,/^---$/d' || echo "See refinement-session.md")

## Research Findings
See: research-output.md

## Repository Context
See: repo-analysis.md

## Flow Diagram
See: flow-diagram.md (if confirmed)

## Session Files
- feature-input.md - Original user request
- refined-requirements.md - After clarification
- refinement-session.md - Full clarification conversation
- research-output.md - /dr research results
- repo-analysis.md - Repository understanding
- flow-feedback.md - User feedback during diagram iterations
- flow-confirmed.txt - Confirmation marker
EOF

  complete_step 5 "Summary saved"
  dim_path "  Saved: $SESSION_DIR/summary.md"
}

# Step 6: Flow diagram verification loop (two-phase: system flow first, then supplementary)
flow_diagram_loop() {
  show_step_header 6 "Flow Diagram Verification" "verify"

  local confirmed=false
  local iteration=0
  local max_iterations=10
  local current_level=1

  # Check for resume - load previous iteration if exists
  local resume_pending=false
  if [ -f "$SESSION_DIR/flow-iteration.txt" ]; then
    local saved_iteration
    saved_iteration=$(cat "$SESSION_DIR/flow-iteration.txt")
    if [ "$saved_iteration" -gt 0 ] 2>/dev/null; then
      # Check if this iteration was already generated but not confirmed
      if [ -f "$SESSION_DIR/flow-diagram-iter-$saved_iteration.md" ]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}Found unconfirmed diagram (iteration $saved_iteration)${NC}"

        # Show previous feedback if any
        if [ -f "$SESSION_DIR/flow-feedback.md" ]; then
          echo -e "  ${DIM}Previous feedback:${NC}"
          tail -5 "$SESSION_DIR/flow-feedback.md" | sed 's/^/     /'
        fi

        echo -e "  ${CYAN}Regenerating diagram with current context...${NC}"
        echo ""

        # Remove old diagram files to force fresh regeneration
        rm -f "$SESSION_DIR/flow-diagram-iter-"*.md 2>/dev/null
        rm -f "$SESSION_DIR/flow-diagram-iter-"*.html 2>/dev/null

        # Reset iteration counter (will start at 1 in the loop)
        iteration=0
        echo "1" > "$SESSION_DIR/flow-iteration.txt"
      fi
    fi
  fi

  # Load context
  local requirements_context=""
  if [ -f "$SESSION_DIR/refined-requirements.md" ]; then
    requirements_context="$(cat "$SESSION_DIR/refined-requirements.md")"
  else
    requirements_context="$FEATURE_DESCRIPTION"
  fi

  local repo_context=""
  if [ -f ".claude/cache/repo-diagrams.md" ]; then
    repo_context="$(head -100 ".claude/cache/repo-diagrams.md")"
  fi

  local domain_context=""
  if [ -f "$SESSION_DIR/domain-context.yaml" ]; then
    domain_context="$(cat "$SESSION_DIR/domain-context.yaml")"
  fi

  # Load architecture index for diagram vocabulary
  local architecture_context=""
  architecture_context=$(load_architecture_context)
  if [ -n "$architecture_context" ] && [ "$architecture_context" != "# No architecture index available - use generic component names" ]; then
    log "Loaded architecture index with known components, endpoints, and tables"
  fi

  # Data Layer Interrogation - gather info for consistent API→Table mapping
  local data_layer_context=""
  if [ ! -f "$SESSION_DIR/data-layer-answers.md" ]; then
    echo ""
    echo -e "  ${CYAN}${BOLD}Data Layer Questions${NC} ${DIM}(helps ensure consistent diagrams)${NC}"
    echo ""

    # Infer primary entities from requirements using Claude
    local inferred_entities=""
    if command -v claude &> /dev/null; then
      log "Analyzing requirements for data entities..."
      inferred_entities=$(claude --dangerously-skip-permissions --print "Based on this feature description, list the main data things (nouns) that will be stored/managed. Just list them comma-separated, no explanation:

Feature: $SESSION_NAME
Requirements: $requirements_context

Example output: listings, offers, pricing agreements" 2>/dev/null | tail -1 | tr -d '\r') || true
    fi

    # Question 1: Confirm inferred entities
    if [ -n "$inferred_entities" ]; then
      echo -e "  ${BOLD}1. This feature appears to manage: ${CYAN}$inferred_entities${NC}"
      echo -e "     ${DIM}Press Enter to confirm, or type corrections${NC}"
      echo -ne "     ${MAGENTA}Entities:${NC} "
      read -e data_entities_input
      if [ -z "$data_entities_input" ]; then
        data_entities="$inferred_entities"
      else
        data_entities="$data_entities_input"
      fi
    else
      echo -e "  ${BOLD}1. What main things does this feature store/manage?${NC}"
      echo -e "     ${DIM}(e.g., \"listings, offers\" or \"orders, payments\")${NC}"
      echo -ne "     ${MAGENTA}Entities:${NC} "
      read -e data_entities
    fi

    # Question 2: Infer connections to existing data
    local inferred_references=""
    if command -v claude &> /dev/null; then
      log "Analyzing for connections to existing data..."
      # Extract just table names from architecture context for cleaner prompt
      local existing_tables=""
      existing_tables=$(echo "$architecture_context" | grep -oE "[a-z_]+:" | sed 's/://g' | sort -u | head -20 | tr '\n' ', ' | sed 's/,$//')

      if [ -n "$existing_tables" ]; then
        inferred_references=$(claude --dangerously-skip-permissions --print "Which of these EXISTING tables would '$data_entities' need foreign keys to?

Existing tables: $existing_tables

Reply with ONLY a comma-separated list of table names, or 'none'.
Example: vendors, inventory_items
Example: none" 2>/dev/null | tail -1 | tr -d '\r') || true
      fi
    fi

    # Question 2: Confirm inferred connections
    echo ""
    if [ -n "$inferred_references" ] && [ "$inferred_references" != "none" ]; then
      echo -e "  ${BOLD}2. Which existing tables does this need to reference?${NC}"
      echo -e "     ${DIM}Detected: ${CYAN}$inferred_references${NC}"
      echo -e "     ${DIM}Press Enter to confirm, or type corrections (or 'none')${NC}"
      echo -ne "     ${MAGENTA}References:${NC} "
      read -e data_references_input
      if [ -z "$data_references_input" ]; then
        data_references="$inferred_references"
      else
        data_references="$data_references_input"
      fi
    elif [ "$inferred_references" = "none" ]; then
      echo -e "  ${BOLD}2. This appears to be standalone ${DIM}(no connections to existing data)${NC}"
      echo -e "     ${DIM}Press Enter to confirm, or list what it connects to${NC}"
      echo -ne "     ${MAGENTA}Connects to:${NC} "
      read -e data_references_input
      if [ -z "$data_references_input" ]; then
        data_references="none (standalone)"
      else
        data_references="$data_references_input"
      fi
    else
      echo -e "  ${BOLD}2. Does this connect to existing data?${NC}"
      echo -e "     ${DIM}(e.g., \"vendors, inventory\" or \"none\")${NC}"
      echo -ne "     ${MAGENTA}Connects to:${NC} "
      read -e data_references
    fi

    # Question 3: Infer operations from requirements
    local inferred_operations=""
    if command -v claude &> /dev/null; then
      log "Analyzing for user operations..."
      inferred_operations=$(claude --dangerously-skip-permissions --print "What operations can users perform on '$data_entities' based on these requirements?

Requirements: $requirements_context

Reply with ONLY a comma-separated list from: create, view, edit, delete, search, export, import
Example: create, view, edit, delete
Example: view, search" 2>/dev/null | tail -1 | tr -d '\r') || true
    fi

    echo ""
    if [ -n "$inferred_operations" ]; then
      echo -e "  ${BOLD}3. What can users do with this data?${NC}"
      echo -e "     ${DIM}Detected: ${CYAN}$inferred_operations${NC}"
      echo -e "     ${DIM}Press Enter to confirm, or type corrections${NC}"
      echo -ne "     ${MAGENTA}Actions:${NC} "
      read -e data_operations_input
      if [ -z "$data_operations_input" ]; then
        data_operations="$inferred_operations"
      else
        data_operations="$data_operations_input"
      fi
    else
      echo -e "  ${BOLD}3. What can users do with this data?${NC}"
      echo -e "     ${DIM}(e.g., \"create, view, edit, delete\" or \"view only\")${NC}"
      echo -ne "     ${MAGENTA}Actions:${NC} "
      read -e data_operations
    fi

    # Question 4: Infer access patterns
    local inferred_access=""
    if command -v claude &> /dev/null && [ -n "$data_references" ] && [ "$data_references" != "none (standalone)" ] && [ "$data_references" != "none" ]; then
      log "Analyzing access patterns..."
      inferred_access=$(claude --dangerously-skip-permissions --print "When displaying '$data_entities', which related data from '$data_references' would typically be shown together?

Reply with a short phrase like: vendor name, category
Or: none (displayed standalone)" 2>/dev/null | tail -1 | tr -d '\r' | cut -c1-60) || true
    fi

    echo ""
    if [ -n "$inferred_access" ]; then
      echo -e "  ${BOLD}4. When viewing, what related info is shown together?${NC}"
      echo -e "     ${DIM}Detected: ${CYAN}$inferred_access${NC}"
      echo -e "     ${DIM}Press Enter to confirm, or type corrections${NC}"
      echo -ne "     ${MAGENTA}Shows with:${NC} "
      read -e data_access_input
      if [ -z "$data_access_input" ]; then
        data_access_pattern="$inferred_access"
      else
        data_access_pattern="$data_access_input"
      fi
    else
      echo -e "  ${BOLD}4. When viewing, what related info is shown together?${NC}"
      echo -e "     ${DIM}(e.g., \"vendor name\" or \"none\")${NC}"
      echo -ne "     ${MAGENTA}Shows with:${NC} "
      read -e data_access_pattern
    fi

    # Save answers
    cat > "$SESSION_DIR/data-layer-answers.md" << ANSWERS_EOF
## Data Layer Context

### Primary Entities
$data_entities

### References to Existing Entities
$data_references

### Operations
$data_operations

### Access Patterns
$data_access_pattern
ANSWERS_EOF

    echo ""
    log "Data layer context saved"
  fi

  # Load data layer answers into context
  if [ -f "$SESSION_DIR/data-layer-answers.md" ]; then
    data_layer_context="$(cat "$SESSION_DIR/data-layer-answers.md")"
  fi

  # Phase 1: Generate and confirm system flow diagram
  while [ "$confirmed" = "false" ] && [ "$iteration" -lt "$max_iterations" ]; do
    iteration=$((iteration + 1))

    echo ""
    echo -e "  ${YELLOW}${BOLD}Iteration $iteration${NC} ${DIM}(max: $max_iterations) - System Flow${NC}"
    echo ""

    local feedback_context=""
    if [ -f "$SESSION_DIR/flow-feedback.md" ]; then
      feedback_context="$(cat "$SESSION_DIR/flow-feedback.md")"
    fi

    # Skip generation if resuming and this diagram already exists
    if [ "$resume_pending" = true ] && [ -f "$SESSION_DIR/flow-diagram-iter-$iteration.md" ]; then
      log "Using existing diagram from previous session"
      resume_pending=false  # Only skip once

      # Regenerate HTML in case it's missing
      if [ ! -f "$SESSION_DIR/flow-diagram-iter-$iteration.html" ]; then
        generate_html_diagram "$SESSION_DIR/flow-diagram-iter-$iteration.md" "$SESSION_DIR/flow-diagram-iter-$iteration.html" "System Flow: $SESSION_NAME (Iteration $iteration)" || true
      fi
    elif command -v claude &> /dev/null; then
      log "Generating system flow diagram..."

      local context_file
      context_file=$(mktemp)
      cat > "$context_file" << PROMPT_EOF
<role>
You are a senior software architect specializing in system visualization. You create precise, accurate Mermaid diagrams that reflect actual system architecture using established component vocabulary.
</role>

<task>
Generate a Mermaid system flow diagram for the feature described below. The diagram should show how data flows through the system from frontend to backend to database.
</task>

<feature>
Name: $SESSION_NAME
</feature>

<requirements>
$requirements_context
</requirements>

<architecture_index>
This index contains all known components in the codebase. Use these exact names when the component exists. The 'relationships' section shows which frontend components connect to which APIs, and which APIs access which tables.

$architecture_context
</architecture_index>

<repository_context>
$repo_context
</repository_context>

<domain_context>
$domain_context
</domain_context>

<data_layer_context>
User-provided answers about the data layer for this specific feature:

$data_layer_context

Use this context to determine:
- Which tables are PRIMARY (the entities being managed)
- Which tables are SECONDARY (referenced via FK)
- What operations each endpoint performs
</data_layer_context>

<previous_feedback>
$feedback_context
</previous_feedback>

<instructions>
Create a flowchart TD (top-down) with three layers:
- Frontend: Page/component that initiates the flow
- Backend: API endpoints processing the request
- Data: Database tables being read/written

Use exact component names from the architecture_index when they exist. The relationships section maps frontend components to their API dependencies and APIs to their table dependencies.

When the feature requires elements not in the index, prefix them with [NEW] to indicate they need to be created (e.g., "[NEW] ReportsPage"). This helps distinguish existing infrastructure from proposed additions.

Keep the diagram focused: maximum 12 nodes across 3 subgraphs. Show data flow direction with descriptive edge labels.
</instructions>

<data_layer_rules>
When deciding whether to use existing tables, add columns to existing tables, or create new tables:

USE AN EXISTING TABLE when the architecture_index shows:
- A table that stores the same entity type (e.g., inventory data goes to inventory_items)
- The API endpoint already has a documented relationship to that table
- The data is an attribute of an existing entity (not a new entity)

ADD COLUMNS TO EXISTING TABLE (mark with [NEW COLUMN]) when ALL of these are true:
- Data fully depends on the table's primary key
- Data is mandatory (rarely NULL)
- Data shares the same lifecycle as the parent entity
- Data has same security/access requirements
- The table has fewer than 40 columns

CREATE A NEW TABLE (mark with [NEW]) when ANY of these are true:
- Data has its own unique identifier/lifecycle (it's a new entity, not an attribute)
- Data has a one-to-many or many-to-many relationship with existing tables
- Data would be NULL for more than 50% of parent records (sparse optional data)
- Data has different access control requirements than the parent
- Data represents a distinct business concept (e.g., "agreements" vs "listings")

API-TO-TABLE MAPPING:
- Each distinct resource noun in the API path typically maps to its own table
- /marketplace/listings → marketplace_listings table
- /marketplace/listings/{id}/offers → marketplace_offers table (separate, with FK)
- Nested sub-resources with their own IDs → separate tables with foreign keys
- Query/filter parameters → columns in the appropriate table

CONSISTENCY CHECK:
- If an endpoint like /api/v1/X/Y exists, look for tables named X or Y in the index first
- Prefer connecting to domain-specific tables (marketplace_* for marketplace features)
- Avoid connecting unrelated domains (marketplace API should not go directly to inventory_items unless explicitly bridging)
</data_layer_rules>

<backend_to_data_connections>
Every arrow from Backend to Data Layer MUST be labeled with the relationship type:

LABEL SCHEMA:
- "CRUD: {table}" - Primary table this endpoint manages (one per endpoint)
- "FK: {field}" - Foreign key lookup/validation (e.g., "FK: vendor_id")
- "JOIN: {table}" - Related data fetched together with primary
- "writes" - Insert/update operation (for POST/PUT/PATCH)
- "reads" - Select operation (for GET)

REASONING REQUIREMENT:
Before drawing Backend→Data arrows, identify for each endpoint:
1. PRIMARY TABLE: The resource noun in the URL path (e.g., /items → items table)
2. SECONDARY TABLES: Foreign key references the endpoint needs to validate or join

Example reasoning:
- Endpoint: POST /api/v1/orders
- PRIMARY: orders table (the resource being created)
- SECONDARY: vendors table (FK lookup to validate vendor_id), inventory_items (FK to validate item availability)

STRICT RULES:
- Each endpoint has exactly ONE primary table connection labeled "CRUD: {table}"
- Secondary connections are labeled with their purpose (FK, JOIN)
- If the architecture_index shows existing relationships, use those exactly
- New endpoints follow the resource-noun-to-table mapping
</backend_to_data_connections>

<syntax_guidance>
Mermaid syntax requirements for valid rendering:
- Use "done" or "complete" instead of "end" as node IDs (reserved word)
- Wrap labels containing parentheses or brackets in quotes: A["Label (info)"]
- Keep node IDs as simple alphanumeric identifiers
</syntax_guidance>

<example>
A well-structured system flow diagram with labeled Backend→Data connections:
\`\`\`mermaid
flowchart TD
    subgraph frontend[Frontend]
        A[InventoryPage]
        B["[NEW] BulkImportModal"]
    end
    subgraph backend[Backend]
        C["/api/v1/inventory/items"]
        D["[NEW] /api/v1/inventory/bulk-import"]
    end
    subgraph data[Data Layer]
        E[(inventory_items)]
        F[(inventory_categories)]
        G["[NEW] import_batches"]
    end
    A -->|"GET items"| C
    B -->|"POST bulk data"| D
    C -->|"CRUD: inventory_items"| E
    C -->|"JOIN: categories"| F
    D -->|"CRUD: import_batches"| G
    D -->|"writes"| E

    classDef newNode fill:#e1f5fe,stroke:#01579b
    class B,D,G newNode
\`\`\`

Reasoning shown:
- /api/v1/inventory/items: PRIMARY=inventory_items (resource noun), SECONDARY=inventory_categories (joined for display)
- /api/v1/inventory/bulk-import: PRIMARY=import_batches (tracks the batch), SECONDARY=inventory_items (where items are written)
</example>

<output_format>
First, show your table reasoning, then the diagram:

ENDPOINT TABLE MAPPING:
- {endpoint}: PRIMARY={table} ({reason}), SECONDARY={tables} ({reasons})
- ...

\`\`\`mermaid
flowchart TD
    ...
\`\`\`
</output_format>
PROMPT_EOF

      claude --dangerously-skip-permissions --print "$(cat "$context_file")" 2>&1 | tee "$SESSION_DIR/flow-diagram-iter-$iteration.md" || {
        log_error "Flow diagram generation had issues"
      }
      rm -f "$context_file"

      # Verify and auto-regenerate if needed
      echo ""
      log "Validating diagram..."
      local arch_index="$PROJECT_ROOT/.claude/cache/architecture/index.yaml"
      if verify_and_regenerate \
          "$SESSION_DIR/flow-diagram-iter-$iteration.md" \
          "$arch_index" \
          "$requirements_context" \
          "$SESSION_DIR"; then
        log "Diagram passed all validation checks"
      else
        log_warn "Diagram has validation issues - showing for manual review"
      fi
    else
      log_error "Claude CLI not found"
      break
    fi

    # Generate HTML preview
    # Save each iteration with distinct name, plus a "latest" copy for easy access
    if generate_html_diagram "$SESSION_DIR/flow-diagram-iter-$iteration.md" "$SESSION_DIR/flow-diagram-iter-$iteration.html" "System Flow: $SESSION_NAME (Iteration $iteration)"; then
      # Also copy to flow-diagram.html as "latest" for convenience
      cp "$SESSION_DIR/flow-diagram-iter-$iteration.html" "$SESSION_DIR/flow-diagram.html"
      echo ""
      echo -e "  ${CYAN}${BOLD}Preview:${NC}"
      echo -e "  ${CYAN}http://ubuntu.desmana-truck.ts.net:32082/$SESSION_NAME/flow-diagram-iter-$iteration.html${NC}"
      echo -e "  ${DIM}(also at flow-diagram.html)${NC}"

      # Cache diagrams for historical record (even if later deleted)
      cache_diagram "$SESSION_DIR/flow-diagram-iter-$iteration.md" "$SESSION_NAME" "flow" "$iteration" || true
      cache_diagram "$SESSION_DIR/flow-diagram-iter-$iteration.html" "$SESSION_NAME" "flow-html" "$iteration" || true
    fi

    # Save iteration number for resume functionality
    echo "$iteration" > "$SESSION_DIR/flow-iteration.txt"

    log_separator

    echo -e "  ${BOLD}Does this system flow diagram correctly represent the feature?${NC}"
    echo ""
    echo -e "  ${DIM}Options: yes (confirm), no/[feedback] (refine), done (accept & continue)${NC}"
    echo -ne "  ${MAGENTA}Response:${NC} "
    read -e response
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

    case "$response" in
      yes|y|correct|good|ok|done|finish)
        confirmed=true
        cp "$SESSION_DIR/flow-diagram-iter-$iteration.md" "$SESSION_DIR/flow-diagram.md"
        # Clear iteration tracker since flow is confirmed
        rm -f "$SESSION_DIR/flow-iteration.txt"
        echo -e "  ${GREEN}System flow confirmed${NC}"
        # Cache the confirmed diagram
        cache_diagram "$SESSION_DIR/flow-diagram.md" "$SESSION_NAME" "flow-confirmed" "final" || true
        ;;
      *)
        if [ -n "$response" ] && [ "$response" != "no" ]; then
          echo "" >> "$SESSION_DIR/flow-feedback.md"
          echo "## Iteration $iteration Feedback" >> "$SESSION_DIR/flow-feedback.md"
          echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$SESSION_DIR/flow-feedback.md"
          echo "$response" >> "$SESSION_DIR/flow-feedback.md"
          echo "" >> "$SESSION_DIR/flow-feedback.md"
          log "Feedback recorded. Refining..."
        else
          echo ""
          echo -e "  ${DIM}What needs to change?${NC}"
          input_prompt
          read -e feedback
          if [ -n "$feedback" ]; then
            echo "" >> "$SESSION_DIR/flow-feedback.md"
            echo "## Iteration $iteration Feedback" >> "$SESSION_DIR/flow-feedback.md"
            echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$SESSION_DIR/flow-feedback.md"
            echo "$feedback" >> "$SESSION_DIR/flow-feedback.md"
            echo "" >> "$SESSION_DIR/flow-feedback.md"
            log "Feedback recorded. Refining..."
          fi
        fi
        ;;
    esac
  done

  # Phase 2: Generate supplementary diagrams (User Journey, Sequence, State)
  if [ "$confirmed" = "true" ]; then
    echo ""
    log_separator
    echo -e "  ${BOLD}Generating supplementary diagrams...${NC}"
    echo -e "  ${DIM}(User Journey, Sequence, State)${NC}"
    echo ""

    if [ -x "$SCRIPT_DIR/generate_feature_diagrams.sh" ]; then
      "$SCRIPT_DIR/generate_feature_diagrams.sh" "$SESSION_DIR" "$SESSION_NAME" || {
        log_warn "Supplementary diagram generation had issues"
      }

      if [ -f "$SESSION_DIR/feature-diagrams.html" ]; then
        echo ""
        echo -e "  ${CYAN}${BOLD}View complete diagram suite:${NC}"
        echo -e "  ${CYAN}http://ubuntu.desmana-truck.ts.net:32082/$SESSION_NAME/feature-diagrams.html${NC}"
        echo ""
        echo -e "  ${DIM}Tabs: System Flow | User Journey | Sequence | State${NC}"
        echo ""

        echo -e "  ${BOLD}Review all diagrams. Confirm or provide feedback:${NC}"
        echo -ne "  ${MAGENTA}Confirm (yes/feedback):${NC} "
        read -e suite_response
        suite_response=$(echo "$suite_response" | tr '[:upper:]' '[:lower:]')

        if [ "$suite_response" != "yes" ] && [ "$suite_response" != "y" ] && [ -n "$suite_response" ]; then
          echo "" >> "$SESSION_DIR/flow-feedback.md"
          echo "## Diagram Suite Feedback" >> "$SESSION_DIR/flow-feedback.md"
          echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$SESSION_DIR/flow-feedback.md"
          echo "$suite_response" >> "$SESSION_DIR/flow-feedback.md"
          echo "" >> "$SESSION_DIR/flow-feedback.md"

          log "Feedback saved. Regenerating suite..."
          "$SCRIPT_DIR/generate_feature_diagrams.sh" "$SESSION_DIR" "$SESSION_NAME" || true

          echo ""
          echo -e "  ${CYAN}Updated: http://ubuntu.desmana-truck.ts.net:32082/$SESSION_NAME/feature-diagrams.html${NC}"

          # Cache the regenerated suite
          cache_diagram "$SESSION_DIR/feature-diagrams.html" "$SESSION_NAME" "suite-html" "2" || true
        fi

        # Cache supplementary diagrams after generation
        for dtype in user-journey sequence state; do
          [ -f "$SESSION_DIR/${dtype}-diagram.md" ] && \
            cache_diagram "$SESSION_DIR/${dtype}-diagram.md" "$SESSION_NAME" "$dtype" "1" || true
        done
        [ -f "$SESSION_DIR/feature-diagrams.html" ] && \
          cache_diagram "$SESSION_DIR/feature-diagrams.html" "$SESSION_NAME" "suite-html" "1" || true
      fi
    fi

    # Create confirmation marker
    cat > "$SESSION_DIR/flow-confirmed.txt" << EOF
Diagrams confirmed at iteration $iteration
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
System Flow: yes
Diagram Suite: $([ -f "$SESSION_DIR/feature-diagrams.html" ] && echo "yes" || echo "no")
EOF

    # Cache all session diagrams for permanent record
    log "Caching diagrams..."
    local cached_count
    cached_count=$(cache_session_diagrams "$SESSION_DIR" "$SESSION_NAME")
    echo -e "  ${DIM}Cached $cached_count diagrams to .claude/cache/diagrams/$SESSION_NAME/${NC}"

    complete_step 6 "Diagrams confirmed"
    dim_path "  System Flow: $SESSION_DIR/flow-diagram.md"
    dim_path "  Suite: $SESSION_DIR/feature-diagrams.html"
  else
    log_error "Max iterations ($max_iterations) reached"
    complete_step 6 "Max iterations reached"
  fi
}

# Step 7: Sync to database
sync_to_database() {
  show_step_header 7 "Syncing to Database" "sync"

  local current_date
  current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Transform research output into scope document format
  log "Creating scope documents..."

  # Create main scope document
  cat > "$SCOPE_DIR/00_scope_document.md" << EOF
---
name: $SESSION_NAME
created: $current_date
updated: $current_date
status: in-progress
type: scope
---

# Scope Document: $SESSION_NAME

## Overview
$(cat "$SESSION_DIR/refined-requirements.md" 2>/dev/null | sed '1,/^---$/d; 1,/^---$/d' || echo "See feature-input.md")

## Research Findings
$(cat "$SESSION_DIR/research-output.md" 2>/dev/null | head -200 || echo "See research-output.md in RESEARCH directory")

## Repository Context
$(cat "$SESSION_DIR/repo-analysis.md" 2>/dev/null | head -100 || echo "See repo-analysis.md in RESEARCH directory")
EOF

  dim_path "    Created: 00_scope_document.md"

  # Create features document
  cat > "$SCOPE_DIR/01_features.md" << EOF
---
name: $SESSION_NAME-features
created: $current_date
updated: $current_date
type: features
---

# Features

## Initial Request
$(cat "$SESSION_DIR/feature-input.md" 2>/dev/null | sed '1,/^---$/d; 1,/^---$/d' || echo "N/A")

## Research-Derived Features
$(grep -A 100 "USER FLOWS\|FEATURES\|CAPABILITIES\|FUNCTIONALITY" "$SESSION_DIR/research-output.md" 2>/dev/null | head -100 || echo "See research-output.md")
EOF

  dim_path "    Created: 01_features.md"

  # Create user journeys document
  cat > "$SCOPE_DIR/02_user_journeys.md" << EOF
---
name: $SESSION_NAME-journeys
created: $current_date
updated: $current_date
type: user-journeys
---

# User Journeys

$(grep -A 100 "USER FLOWS\|JOURNEYS\|INTERACTION\|WORKFLOW" "$SESSION_DIR/research-output.md" 2>/dev/null | head -100 || echo "See research-output.md")

## Flow Diagram
$(cat "$SESSION_DIR/flow-diagram.md" 2>/dev/null | head -200 || echo "See flow diagram in RESEARCH directory")
EOF

  dim_path "    Created: 02_user_journeys.md"

  # Run the database sync script if available
  local sync_script="$SCRIPT_DIR/sync-interview-to-db.sh"
  local db_synced=false

  if [ -f "$sync_script" ]; then
    log "Syncing to PostgreSQL..."

    if "$sync_script" "$SESSION_NAME"; then
      db_synced=true
    else
      log_error "Database sync had issues (non-fatal)"
    fi
  else
    # Try alternate location
    sync_script="./.claude/scripts/sync-interview-to-db.sh"
    if [ -f "$sync_script" ]; then
      if "$sync_script" "$SESSION_NAME"; then
        db_synced=true
      else
        log_error "Database sync had issues (non-fatal)"
      fi
    else
      echo -e "  ${DIM}Database sync skipped (sync script not found)${NC}"
    fi
  fi

  if [ "$db_synced" = "true" ]; then
    complete_step 7 "Database sync complete"
  else
    complete_step 7 "Scope documents created (DB sync skipped)"
  fi
}

# Show final summary
show_final_summary() {
  local total_duration=$(($(date +%s) - SESSION_START_TIME))

  echo ""
  echo ""
  echo -e "${GREEN}${BOLD}"
  cat << 'COMPLETE'
  ╔═══════════════════════════════════════════════════════════╗
  ║                                                           ║
  ║              ✓  DISCOVERY COMPLETE                        ║
  ║                                                           ║
  ╚═══════════════════════════════════════════════════════════╝
COMPLETE
  echo -e "${NC}"

  echo -e "  ${BOLD}Session:${NC} $SESSION_NAME"
  echo -e "  ${BOLD}Duration:${NC} $(format_duration $total_duration)"
  echo ""

  # Show progress summary
  show_progress_summary

  echo ""
  echo -e "  ${BOLD}Output Files${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
  echo ""
  echo -e "  ${CYAN}Research:${NC} ${DIM}$SESSION_DIR/${NC}"
  if [ -d "$SESSION_DIR" ]; then
    ls -1 "$SESSION_DIR/" 2>/dev/null | head -6 | sed "s/^/    ${DIM}├─ /" | sed "s/$/${NC}/"
    local count=$(ls -1 "$SESSION_DIR/" 2>/dev/null | wc -l)
    if [ "$count" -gt 6 ]; then
      echo -e "    ${DIM}└─ ... and $((count - 6)) more${NC}"
    fi
  fi
  echo ""
  echo -e "  ${CYAN}Scope:${NC} ${DIM}$SCOPE_DIR/${NC}"
  if [ -d "$SCOPE_DIR" ]; then
    ls -1 "$SCOPE_DIR/" 2>/dev/null | sed "s/^/    ${DIM}├─ /" | sed "s/$/${NC}/"
  fi

  echo ""
  echo -e "  ${BOLD}Next Steps${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
  echo -e "  ${WHITE}1.${NC} Review scope documents"
  echo -e "  ${WHITE}2.${NC} Run ${CYAN}/pm:decompose $SESSION_NAME${NC} to create PRDs"
  echo -e "  ${WHITE}3.${NC} Query database for features/journeys"
  echo ""
}

# Main function
main() {
  # Parse arguments
  case "${1:-}" in
    --help|-h)
      show_help
      ;;
    --list|-l)
      list_sessions
      ;;
    --resume|-r)
      if [ -z "${2:-}" ]; then
        echo "Error: --resume requires a session name"
        echo "Usage: ./feature_interrogate.sh --resume <session-name>"
        echo ""
        echo "Available sessions:"
        list_sessions
        exit 1
      fi
      SESSION_NAME="$2"
      RESUME_MODE=true
      # Verify session exists
      if [ ! -d ".claude/RESEARCH/$SESSION_NAME" ]; then
        echo "Error: Session '$SESSION_NAME' not found"
        echo ""
        echo "Available sessions:"
        list_sessions
        exit 1
      fi
      ;;
    "")
      # Generate default session name
      SESSION_NAME="feature-$(date +%Y%m%d-%H%M%S)"
      ;;
    *)
      SESSION_NAME="$1"
      ;;
  esac

  # Show banner
  show_banner

  # Show keyboard hints
  echo -e "  ${DIM}[Ctrl+C ×2] exit at any time${NC}"
  echo ""

  # Initialize session
  init_session "$SESSION_NAME"

  # Handle resume mode
  if [ "$RESUME_MODE" = true ]; then
    RESUME_FROM_STEP=$(detect_completed_steps "$SESSION_DIR")

    if [ "$RESUME_FROM_STEP" -ge 8 ]; then
      echo -e "  ${GREEN}Session already complete!${NC}"
      echo ""
      show_final_summary
      exit 0
    fi

    echo -e "  ${YELLOW}Resuming from Step $RESUME_FROM_STEP${NC}"
    echo ""

    # Load existing session data
    load_session_data "$SESSION_DIR"

    # Mark completed steps
    for ((i=1; i<RESUME_FROM_STEP; i++)); do
      STEP_STATUS[$((i-1))]="skipped"
    done
  else
    RESUME_FROM_STEP=1
  fi

  # Run pipeline steps (skip completed ones in resume mode)
  if [ "$RESUME_FROM_STEP" -le 1 ]; then
    familiarize_repo
  else
    echo -e "  ${DIM}Step 1: Repo Analysis - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 2 ]; then
    get_feature_input
  else
    echo -e "  ${DIM}Step 2: Feature Input - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 3 ]; then
    refine_requirements
  else
    echo -e "  ${DIM}Step 3: Refinement - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 4 ]; then
    research_feature
  else
    echo -e "  ${DIM}Step 4: Research - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 5 ]; then
    save_summary
  else
    echo -e "  ${DIM}Step 5: Summary - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 6 ]; then
    flow_diagram_loop
  else
    echo -e "  ${DIM}Step 6: Flow Diagram - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 7 ]; then
    sync_to_database
  else
    echo -e "  ${DIM}Step 7: Database Sync - skipped (already complete)${NC}"
  fi

  show_final_summary
}

# Run main with all arguments
main "$@"
