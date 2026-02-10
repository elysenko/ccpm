#!/bin/bash
# feature_interrogate.sh - Interactive Feature Discovery with Flow Verification
#
# An interactive shell script that guides users through feature discovery
# using Claude's research skills, culminating in a verified flow diagram.
#
# Usage:
#   ./feature_interrogate.sh [session-name]
#
# Pipeline (18 steps):
#   1. repo-research     → Understand the repository structure
#   2. user-input        → Get feature description from user
#   3. context-research  → Deep research (/dr) to understand the domain (NEW)
#   4. dr-refine         → Ask INFORMED clarifying questions (uses step 3 research)
#   5. impl-research     → Research implementation patterns
#   6. summary           → Save conversation summary
#   7. flow-diagram      → Generate and verify flow diagrams
#   8. db-sync           → Sync to database/scope documents
#   9. data-schema       → Generate data models and migrations
#  10. run-migration     → Apply migration SQL to PostgreSQL
#  11. integrate-models  → Copy SQLAlchemy models into backend and register
#  12. api-generation    → Generate FastAPI router + schemas (self-refine loop)
#  13. journey-gen       → Generate user journeys (delegates to generate-journeys.sh)
#  14. frontend-types    → Generate TypeScript type definitions
#  15. frontend-api      → Generate API client from router contract
#  16. frontend-pages    → Generate page components with validation + retry
#  17. frontend-integrate → Copy files to codebase, add routes + nav to App.tsx
#  18. build-deploy      → Build Docker images, push to registry, deploy to K8s
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
readonly NC='\033[0m'

# Box drawing characters
readonly BOX_H='─'
readonly BOX_V='│'
readonly BOX_TL='┌'
readonly BOX_TR='┐'
readonly BOX_BL='└'
readonly BOX_BR='┘'
readonly BOX_L='├'
readonly BOX_R='┤'

# Step tracking
TOTAL_STEPS=19
CURRENT_STEP=0
STEP_START_TIME=0
SESSION_START_TIME=0
declare -a STEP_NAMES=("Repo Analysis" "Feature Input" "Context Research" "Refinement" "Impl Research" "Summary" "Flow Diagram" "Database Sync" "Data Schema" "Run Migration" "Integrate Models" "API Generation" "Journey Gen" "Frontend Types" "Frontend API" "Frontend Pages" "Frontend Integrate" "Build & Deploy" "Test Personas")
declare -a STEP_STATUS=("pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending")
declare -a STEP_DURATIONS=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

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

# Fail a step and record duration
fail_step() {
  local step_num=$1
  local message="${2:-Failed}"

  local end_time=$(date +%s)
  local duration=$((end_time - STEP_START_TIME))
  STEP_DURATIONS[$((step_num-1))]=$duration
  STEP_STATUS[$((step_num-1))]="failed"

  log_error "Step $step_num failed: $message"
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

# Normalize diagram output to ensure consistent format
# Strips any explanatory prose and extracts only the expected sections
# ROBUST: Handles LLM output that starts with preamble text before the required format
# Usage: normalize_diagram_output <input_file> <output_file>
normalize_diagram_output() {
  local input_file="$1"
  local output_file="$2"

  if [ ! -f "$input_file" ]; then
    log_error "Input file not found: $input_file"
    return 1
  fi

  # STEP 1: Check if ENDPOINT TABLE MAPPING exists anywhere in the file (not just at start)
  local mapping_line
  mapping_line=$(grep -n "^ENDPOINT TABLE MAPPING:" "$input_file" 2>/dev/null | head -1 | cut -d: -f1)

  if [ -n "$mapping_line" ]; then
    # Found mapping header - extract from that line onwards
    # This handles the case where LLM adds preamble text before the required format
    tail -n +"$mapping_line" "$input_file" | awk '
      BEGIN { in_mapping = 1; in_mermaid = 0 }

      # First line should be the ENDPOINT TABLE MAPPING header
      NR == 1 {
        print
        next
      }

      # If we find mermaid block, switch to mermaid mode
      /^```mermaid/ {
        in_mapping = 0
        in_mermaid = 1
        print
        next
      }

      # End of mermaid block - stop processing
      in_mermaid && /^```$/ {
        print
        exit 0
      }

      # Print content in mapping section (lines starting with -)
      in_mapping && /^-/ {
        print
        next
      }

      # Empty line in mapping section continues it
      in_mapping && /^$/ {
        print
        next
      }

      # Any other line in mapping section ends it
      in_mapping && !/^-/ && !/^$/ {
        # Check if this is the start of mermaid block
        if (/^```mermaid/) {
          in_mapping = 0
          in_mermaid = 1
          print
        }
        next
      }

      # Print content inside mermaid block
      in_mermaid {
        print
        next
      }
    ' > "$output_file"

    # Verify the output has both mapping and mermaid content
    if grep -q '^```mermaid' "$output_file" 2>/dev/null; then
      log "Output normalized: found ENDPOINT TABLE MAPPING at line $mapping_line"
      return 0
    fi
  fi

  # STEP 2: Fallback - try to find mapping header with different spacing/formatting
  # Some LLMs output "ENDPOINT TABLE MAPPING:" with leading spaces or without colon
  mapping_line=$(grep -niE "^[[:space:]]*ENDPOINT[[:space:]]+TABLE[[:space:]]+MAPPING" "$input_file" 2>/dev/null | head -1 | cut -d: -f1)

  if [ -n "$mapping_line" ]; then
    log_warn "Found mapping header with non-standard formatting at line $mapping_line"
    # Create compliant output starting from that line
    echo "ENDPOINT TABLE MAPPING:" > "$output_file"
    # Skip the malformed header line and extract rest
    tail -n +"$((mapping_line + 1))" "$input_file" | awk '
      BEGIN { in_mapping = 1; in_mermaid = 0 }
      /^```mermaid/ { in_mapping = 0; in_mermaid = 1; print; next }
      in_mermaid && /^```$/ { print; exit 0 }
      in_mapping && /^[[:space:]]*-/ { print; next }
      in_mapping && /^$/ { print; next }
      in_mapping { if (/^```mermaid/) { in_mapping = 0; in_mermaid = 1; print } next }
      in_mermaid { print; next }
    ' >> "$output_file"

    if grep -q '^```mermaid' "$output_file" 2>/dev/null; then
      return 0
    fi
  fi

  # STEP 3: Last resort - extract just the mermaid block and generate synthetic mapping
  log_warn "Output normalization: ENDPOINT TABLE MAPPING not found, extracting mermaid block only"

  # Extract just the mermaid block (handles various edge cases)
  # Use awk -v to pass patterns containing backticks
  awk -v ms='^```mermaid$' -v me='^```$' '
    $0 ~ ms { in_block = 1; print; next }
    in_block && $0 ~ me { print; exit 0 }
    in_block { print }
  ' "$input_file" > "$output_file.mermaid"

  if [ -s "$output_file.mermaid" ]; then
    # Create a minimal compliant output with synthetic mapping
    # Extract endpoint info from the mermaid content itself
    {
      echo "ENDPOINT TABLE MAPPING:"
      # Try to extract API endpoint info from the mermaid content
      grep -oE '/api/v1/[a-z_/{}\-]+' "$output_file.mermaid" 2>/dev/null | sort -u | while read -r endpoint; do
        echo "- $endpoint: PRIMARY=(extracted from diagram)"
      done
      # If no endpoints found, add placeholder
      if ! grep -q '/api/v1/' "$output_file.mermaid" 2>/dev/null; then
        echo "- (extracted from non-compliant output - endpoints not detected)"
      fi
      echo ""
      cat "$output_file.mermaid"
    } > "$output_file"
    rm -f "$output_file.mermaid"
    log_warn "Created synthetic mapping from mermaid content"
    return 0
  fi

  # STEP 4: Complete failure - no mermaid block found
  log_error "Output normalization failed: No mermaid block found"
  # Keep raw output but mark it as failed
  {
    echo "ENDPOINT TABLE MAPPING:"
    echo "- ERROR: LLM output did not contain valid mermaid diagram"
    echo ""
    printf '%s\n' '```mermaid'
    echo 'flowchart TD'
    echo '    ERROR["LLM output parsing failed - check raw output file"]'
    printf '%s\n' '```'
  } > "$output_file"
  rm -f "$output_file.mermaid" 2>/dev/null
  return 1
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
      tr -d '[]()' | sort -u

    # Extract explicit table names from comments or labels
    echo "$mermaid_content" | grep -oE 'table:[[:space:]]*[A-Za-z_]+' | \
      sed 's/table:[[:space:]]*//' | sort -u
  } | sort -u | grep -v '^$'
}

# Extract connections (edges) from a Mermaid diagram
# Handles multiple edge syntaxes: -->, -.->,--, ==>, labeled arrows, etc.
# Also handles node definitions with labels: A[text] --> B[text]
# Usage: extract_diagram_connections "$mermaid_content"
# Output: One connection per line in format: source|target|label
extract_diagram_connections() {
  local content="$1"
  # Normalize CRLF to LF
  content=$(echo "$content" | tr -d '\r')

  echo "$content" | while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*%% ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Skip subgraph/end/classDef/class/style declarations
    [[ "$line" =~ ^[[:space:]]*(subgraph|end|classDef|class|style|direction)[[:space:]] ]] && continue
    [[ "$line" =~ ^[[:space:]]*(graph|flowchart)[[:space:]] ]] && continue

    # Pre-process: strip node labels to simplify pattern matching
    # Converts: A["Label"] --> B[(db)] to: A --> B
    # Handles: [], (), {}, [[]], [()], etc.
    # Note: Don't use 'local' here - we're in a subshell from the pipe
    stripped_line="$line"
    # Remove bracketed content after node IDs (multiple passes for nested)
    stripped_line=$(echo "$stripped_line" | sed 's/\[\[[^]]*\]\]//g')  # [[text]]
    stripped_line=$(echo "$stripped_line" | sed 's/\[([^)]*)\]//g')    # [(text)]
    stripped_line=$(echo "$stripped_line" | sed 's/\[[^]]*\]//g')       # [text]
    stripped_line=$(echo "$stripped_line" | sed 's/([^)]*)//g')         # (text)
    stripped_line=$(echo "$stripped_line" | sed 's/{[^}]*}//g')         # {text}

    # Handle labeled arrows: A -->|"text"| B or A -->|text| B
    # Captures: source, arrow, label, target
    if [[ "$stripped_line" =~ ([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*([-=.]+\>)[[:space:]]*\|\"?([^|\"]*?)\"?\|[[:space:]]*([A-Za-z_][A-Za-z0-9_]*) ]]; then
      echo "${BASH_REMATCH[1]}|${BASH_REMATCH[4]}|${BASH_REMATCH[3]}"
      continue
    fi

    # Handle labeled arrows with text on arrow: A -- text --> B or A -. text .-> B
    if [[ "$stripped_line" =~ ([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*([-=.]+)[[:space:]]+([^-=.>]+)[[:space:]]+([-=.]*\>)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*) ]]; then
      # Note: Don't use 'local' here - we're in a subshell from the pipe
      label="${BASH_REMATCH[3]}"
      label=$(echo "$label" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')  # trim
      echo "${BASH_REMATCH[1]}|${BASH_REMATCH[5]}|$label"
      continue
    fi

    # Handle unlabeled arrows: A --> B, A -.-> B, A ==> B, A -- B, A --- B
    # Supports: -->, -.->,-.->, ==>, ---, --, <-->, <-.->
    if [[ "$stripped_line" =~ ([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(<?[-=.]+>?)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*) ]]; then
      # Capture values before inner regex (which resets BASH_REMATCH)
      src="${BASH_REMATCH[1]}"
      arrow="${BASH_REMATCH[2]}"
      tgt="${BASH_REMATCH[3]}"
      # Check it's actually an arrow (has - or = or .)
      if [[ "$arrow" =~ [-=.] ]]; then
        echo "$src|$tgt|"
      fi
      continue
    fi
  done | sort -u
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

# Normalize a connection endpoint for fuzzy matching
# Removes API prefixes, component suffixes, and normalizes case
# Usage: normalize_connection_endpoint "OrganizationPage" -> "organization"
# Usage: normalize_connection_endpoint "/api/v1/organizations" -> "organizations"
normalize_connection_endpoint() {
  local input="$1"
  local normalized="$input"

  # Remove API version prefixes
  normalized="${normalized#/api/v1/}"
  normalized="${normalized#/api/v2/}"
  normalized="${normalized#/api/}"

  # Remove common component suffixes
  normalized="${normalized%Page}"
  normalized="${normalized%Manager}"
  normalized="${normalized%Editor}"
  normalized="${normalized%Browser}"
  normalized="${normalized%Tracker}"
  normalized="${normalized%Dashboard}"
  normalized="${normalized%Component}"
  normalized="${normalized%Panel}"
  normalized="${normalized%View}"
  normalized="${normalized%API}"
  normalized="${normalized%Service}"

  # Normalize to lowercase, remove underscores/hyphens
  normalized=$(echo "$normalized" | tr '[:upper:]' '[:lower:]' | tr -d '_-')

  echo "$normalized"
}

# Check if two connection endpoints match (with fuzzy matching)
# Handles different naming conventions between requirements and diagrams
# Usage: connection_endpoints_match "OrganizationPage" "ORG" -> true
# Returns: 0 if match, 1 if no match
connection_endpoints_match() {
  local expected="$1"
  local actual="$2"

  # Exact match (case-insensitive)
  if [[ "${expected,,}" == "${actual,,}" ]]; then
    return 0
  fi

  # Normalize both endpoints
  local exp_norm
  local act_norm
  exp_norm=$(normalize_connection_endpoint "$expected")
  act_norm=$(normalize_connection_endpoint "$actual")

  # Exact match after normalization
  [[ "$exp_norm" == "$act_norm" ]] && return 0

  # Substring match (either direction)
  [[ "$exp_norm" == *"$act_norm"* ]] && return 0
  [[ "$act_norm" == *"$exp_norm"* ]] && return 0

  # Subsequence match using existing function
  is_subsequence_match "$exp_norm" "$act_norm" && return 0
  is_subsequence_match "$act_norm" "$exp_norm" && return 0

  # Handle plural/singular variations
  local exp_singular="${exp_norm%s}"
  local act_singular="${act_norm%s}"
  [[ "$exp_singular" == "$act_norm" ]] && return 0
  [[ "$exp_norm" == "$act_singular" ]] && return 0
  [[ "$exp_singular" == "$act_singular" ]] && return 0

  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Checklist-Based Diagram Validation Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Extract required elements from requirements into a YAML checklist (LLM - once per session)
# This provides a deterministic source of truth for validation instead of LLM judgment
# Usage: extract_required_elements "$requirements_file" "$output_file"
# Returns: 0 on success, 1 on failure
extract_required_elements() {
  local requirements_file="$1"
  local output_file="$2"

  if [ ! -f "$requirements_file" ]; then
    log_warn "Requirements file not found: $requirements_file"
    return 1
  fi

  if ! command -v claude &> /dev/null; then
    log_warn "Claude CLI not available for checklist extraction"
    return 1
  fi

  local prompt="Extract REQUIRED elements from this specification.

OUTPUT FORMAT (YAML only - no other text):
tables:
  - table_name_1
  - table_name_2
endpoints:
  - /api/v1/resource1
  - /api/v1/resource2
components:
  - ComponentName1
  - ComponentName2
connections:
  - source: ComponentName1
    target: /api/v1/resource1
    type: calls
  - source: /api/v1/resource1
    target: table_name_1
    type: reads

RULES:
- tables: Main database tables only (NOT junction tables unless explicitly mentioned)
- endpoints: Main resource paths only (NOT sub-routes like /{id}, /request, /confirm)
- components: Distinct page/component names only (frontend UI elements)
- connections: Data flow between elements (REQUIRED for architecture validation)

CONNECTION TYPES:
- calls: Frontend component calls API endpoint
- reads: API endpoint reads from database table
- writes: API endpoint writes to database table
- creates: API endpoint creates records in table
- deletes: API endpoint deletes from table
- triggers: One component triggers another (e.g., webhook, event)

IMPORTANT:
- Extract ONLY what is explicitly required in the spec
- Do NOT infer or add related elements
- Resource-level only (e.g., /api/v1/organizations, NOT /api/v1/organizations/{id})
- If a category has no items, use empty list: []
- Connections MUST show the data flow path: Component -> API -> Database

EXAMPLE (for reference):
tables:
  - organizations
endpoints:
  - /api/v1/organizations
components:
  - OrganizationPage
connections:
  - source: OrganizationPage
    target: /api/v1/organizations
    type: calls
  - source: /api/v1/organizations
    target: organizations
    type: reads

SPECIFICATION:
$(cat "$requirements_file")

Output ONLY the YAML - no explanations, no markdown code blocks."

  local response
  response=$(claude --dangerously-skip-permissions --print "$prompt" 2>&1) || {
    log_error "Failed to extract required elements"
    return 1
  }

  # Clean the response - remove any markdown code blocks if present
  response=$(echo "$response" | sed '/^```/d' | sed '/^yaml$/d')

  # Validate it looks like YAML
  if ! echo "$response" | grep -qE '^(tables|endpoints|components):'; then
    log_error "Invalid response format - expected YAML with tables/endpoints/components"
    echo "Response was: $response"
    return 1
  fi

  # Save the checklist
  echo "$response" > "$output_file"
  log "Required elements checklist saved to: $output_file"
  return 0
}

# Second extraction pass with conservative prompt (explicit mentions only)
# Used for dual-LLM verification to catch hallucinations
# Usage: extract_required_elements_conservative "$requirements_file" "$output_file"
extract_required_elements_conservative() {
  local requirements_file="$1"
  local output_file="$2"

  if [ ! -f "$requirements_file" ]; then
    return 1
  fi

  if ! command -v claude &> /dev/null; then
    return 1
  fi

  local prompt="Extract ONLY EXPLICITLY MENTIONED elements from this specification.

OUTPUT FORMAT (YAML only - no other text):
tables:
  - name: table_name
    evidence: \"quoted text from spec that mentions this\"
endpoints:
  - name: /api/v1/resource
    evidence: \"quoted text from spec that mentions this\"
components:
  - name: ComponentName
    evidence: \"quoted text from spec that mentions this\"
connections:
  - source: ComponentName
    target: /api/v1/resource
    type: calls

STRICT RULES:
- ONLY include items that are EXPLICITLY NAMED or DESCRIBED in the specification
- Every item MUST have evidence: a direct quote from the spec that justifies inclusion
- Do NOT infer tables from endpoint names (unless spec explicitly says 'store in X table')
- Do NOT assume components exist (unless spec says 'add to X page' or 'create X component')
- If unsure whether something is required, DO NOT include it
- When in doubt, leave it out

This is the CONSERVATIVE pass - we want high precision, not high recall.

SPECIFICATION:
$(cat "$requirements_file")

Output ONLY the YAML - no explanations, no markdown code blocks."

  local response
  response=$(claude --dangerously-skip-permissions --print "$prompt" 2>&1) || {
    return 1
  }

  # Clean the response
  response=$(echo "$response" | sed '/^```/d' | sed '/^yaml$/d')

  # Validate format
  if ! echo "$response" | grep -qE '^(tables|endpoints|components):'; then
    return 1
  fi

  echo "$response" > "$output_file"
  return 0
}

# Compare two checklists and produce merged result with confidence scores
# Items in both = high confidence, items in only one = low confidence (flagged)
# Usage: compare_checklists "$checklist_a" "$checklist_b" "$output_file"
compare_checklists() {
  local checklist_a="$1"
  local checklist_b="$2"
  local output_file="$3"

  local high_confidence=()
  local low_confidence=()

  # Extract tables from both
  local tables_a tables_b
  tables_a=$(grep -A 100 '^tables:' "$checklist_a" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-\s*(name:)?' | sed 's/.*name:[[:space:]]*//' | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"' | tr -d "'" | grep -v '^$' || echo "")
  tables_b=$(grep -A 100 '^tables:' "$checklist_b" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-\s*(name:)?' | sed 's/.*name:[[:space:]]*//' | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"' | tr -d "'" | grep -v '^$' || echo "")

  # Find consensus and discrepancies for tables
  while IFS= read -r table; do
    [ -z "$table" ] && continue
    local normalized
    normalized=$(echo "$table" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')
    if echo "$tables_b" | tr '[:upper:]' '[:lower:]' | tr '_' ' ' | grep -qi "$normalized"; then
      high_confidence+=("TABLE:$table:BOTH")
    else
      low_confidence+=("TABLE:$table:ONLY_LIBERAL")
    fi
  done <<< "$tables_a"

  # Check for items only in conservative (high trust)
  while IFS= read -r table; do
    [ -z "$table" ] && continue
    local normalized
    normalized=$(echo "$table" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')
    if ! echo "$tables_a" | tr '[:upper:]' '[:lower:]' | tr '_' ' ' | grep -qi "$normalized"; then
      high_confidence+=("TABLE:$table:ONLY_CONSERVATIVE")
    fi
  done <<< "$tables_b"

  # Extract endpoints from both
  local endpoints_a endpoints_b
  endpoints_a=$(grep -A 100 '^endpoints:' "$checklist_a" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-\s*(name:)?' | sed 's/.*name:[[:space:]]*//' | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"' | tr -d "'" | grep -v '^$' || echo "")
  endpoints_b=$(grep -A 100 '^endpoints:' "$checklist_b" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-\s*(name:)?' | sed 's/.*name:[[:space:]]*//' | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"' | tr -d "'" | grep -v '^$' || echo "")

  while IFS= read -r endpoint; do
    [ -z "$endpoint" ] && continue
    # Extract resource name for comparison
    local resource
    resource=$(echo "$endpoint" | sed 's|.*/||' | sed 's/{.*}//')
    if echo "$endpoints_b" | grep -qi "$resource"; then
      high_confidence+=("ENDPOINT:$endpoint:BOTH")
    else
      low_confidence+=("ENDPOINT:$endpoint:ONLY_LIBERAL")
    fi
  done <<< "$endpoints_a"

  while IFS= read -r endpoint; do
    [ -z "$endpoint" ] && continue
    local resource
    resource=$(echo "$endpoint" | sed 's|.*/||' | sed 's/{.*}//')
    if ! echo "$endpoints_a" | grep -qi "$resource"; then
      high_confidence+=("ENDPOINT:$endpoint:ONLY_CONSERVATIVE")
    fi
  done <<< "$endpoints_b"

  # Extract components from both
  local components_a components_b
  components_a=$(grep -A 100 '^components:' "$checklist_a" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-\s*(name:)?' | sed 's/.*name:[[:space:]]*//' | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"' | tr -d "'" | grep -v '^$' || echo "")
  components_b=$(grep -A 100 '^components:' "$checklist_b" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-\s*(name:)?' | sed 's/.*name:[[:space:]]*//' | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"' | tr -d "'" | grep -v '^$' || echo "")

  while IFS= read -r component; do
    [ -z "$component" ] && continue
    local base
    base=$(echo "$component" | sed 's/Page$//' | sed 's/Component$//' | tr '[:upper:]' '[:lower:]')
    if echo "$components_b" | sed 's/Page$//' | sed 's/Component$//' | tr '[:upper:]' '[:lower:]' | grep -qi "$base"; then
      high_confidence+=("COMPONENT:$component:BOTH")
    else
      low_confidence+=("COMPONENT:$component:ONLY_LIBERAL")
    fi
  done <<< "$components_a"

  while IFS= read -r component; do
    [ -z "$component" ] && continue
    local base
    base=$(echo "$component" | sed 's/Page$//' | sed 's/Component$//' | tr '[:upper:]' '[:lower:]')
    if ! echo "$components_a" | sed 's/Page$//' | sed 's/Component$//' | tr '[:upper:]' '[:lower:]' | grep -qi "$base"; then
      high_confidence+=("COMPONENT:$component:ONLY_CONSERVATIVE")
    fi
  done <<< "$components_b"

  # Write comparison results
  {
    echo "# Checklist Comparison Results"
    echo "# BOTH = High confidence (found by both passes)"
    echo "# ONLY_CONSERVATIVE = High confidence (explicit evidence)"
    echo "# ONLY_LIBERAL = Low confidence (may be hallucination)"
    echo ""
    echo "high_confidence:"
    for item in "${high_confidence[@]}"; do
      echo "  - $item"
    done
    echo ""
    echo "low_confidence:"
    for item in "${low_confidence[@]}"; do
      echo "  - $item"
    done
  } > "$output_file"

  # Return count of low confidence items
  echo "${#low_confidence[@]}"
}

# Validate checklist entities against original requirements text
# Checks if each entity can be grounded in the requirements
# Usage: validate_checklist_against_requirements "$checklist_file" "$requirements_file" "$output_file"
validate_checklist_against_requirements() {
  local checklist_file="$1"
  local requirements_file="$2"
  local output_file="$3"

  if [ ! -f "$checklist_file" ] || [ ! -f "$requirements_file" ]; then
    return 1
  fi

  local requirements_text
  requirements_text=$(cat "$requirements_file" | tr '[:upper:]' '[:lower:]')

  local grounded=()
  local ungrounded=()

  # Check tables
  while IFS= read -r table; do
    [ -z "$table" ] && continue
    table=$(echo "$table" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
    [ -z "$table" ] && continue

    # Check if table name or its parts appear in requirements
    local search_terms
    search_terms=$(echo "$table" | tr '_' '\n' | tr '[:upper:]' '[:lower:]')
    local found=false
    while IFS= read -r term; do
      [ -z "$term" ] && continue
      [ ${#term} -lt 3 ] && continue
      if echo "$requirements_text" | grep -qi "$term"; then
        found=true
        break
      fi
    done <<< "$search_terms"

    if [ "$found" = true ]; then
      grounded+=("TABLE:$table")
    else
      ungrounded+=("TABLE:$table:NOT_IN_REQUIREMENTS")
    fi
  done < <(grep -A 100 '^tables:' "$checklist_file" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-' | head -50)

  # Check endpoints
  while IFS= read -r endpoint; do
    [ -z "$endpoint" ] && continue
    endpoint=$(echo "$endpoint" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
    [ -z "$endpoint" ] && continue

    # Extract resource name from endpoint
    local resource
    resource=$(echo "$endpoint" | sed 's|.*/||' | sed 's/{.*}//' | tr '_' ' ' | tr '-' ' ')

    if echo "$requirements_text" | grep -qi "$resource"; then
      grounded+=("ENDPOINT:$endpoint")
    else
      # Try singular
      local singular
      singular=$(echo "$resource" | sed 's/s$//')
      if echo "$requirements_text" | grep -qi "$singular"; then
        grounded+=("ENDPOINT:$endpoint")
      else
        ungrounded+=("ENDPOINT:$endpoint:NOT_IN_REQUIREMENTS")
      fi
    fi
  done < <(grep -A 100 '^endpoints:' "$checklist_file" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-' | head -50)

  # Check components
  while IFS= read -r component; do
    [ -z "$component" ] && continue
    component=$(echo "$component" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
    [ -z "$component" ] && continue

    # Extract base name without suffixes
    local base
    base=$(echo "$component" | \
      sed 's/Page$//' | sed 's/Manager$//' | sed 's/Editor$//' | \
      sed 's/Component$//' | sed 's/Modal$//' | sed 's/Dialog$//' | \
      tr '[:upper:]' ' ' | tr -s ' ' | sed 's/^ //' | tr '[:upper:]' '[:lower:]')

    local found=false
    for word in $base; do
      [ ${#word} -lt 3 ] && continue
      if echo "$requirements_text" | grep -qi "$word"; then
        found=true
        break
      fi
    done

    if [ "$found" = true ]; then
      grounded+=("COMPONENT:$component")
    else
      ungrounded+=("COMPONENT:$component:NOT_IN_REQUIREMENTS")
    fi
  done < <(grep -A 100 '^components:' "$checklist_file" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^\s*-' | head -50)

  # Write validation results
  {
    echo "# Requirements Grounding Validation"
    echo "# Checks if checklist entities appear in original requirements"
    echo ""
    echo "grounded:"
    for item in "${grounded[@]}"; do
      echo "  - $item"
    done
    echo ""
    echo "ungrounded:"
    for item in "${ungrounded[@]}"; do
      echo "  - $item"
    done
    echo ""
    echo "summary:"
    echo "  total: $((${#grounded[@]} + ${#ungrounded[@]}))"
    echo "  grounded: ${#grounded[@]}"
    echo "  ungrounded: ${#ungrounded[@]}"
  } > "$output_file"

  # Return count of ungrounded items
  echo "${#ungrounded[@]}"
}

# Main verified extraction function - orchestrates dual-LLM + validation
# Usage: extract_required_elements_verified "$requirements_file" "$output_file" "$session_dir"
# Returns: 0 on success, creates verified checklist with confidence annotations
extract_required_elements_verified() {
  local requirements_file="$1"
  local output_file="$2"
  local session_dir="$3"

  if [ ! -f "$requirements_file" ]; then
    log_warn "Requirements file not found: $requirements_file"
    return 1
  fi

  if ! command -v claude &> /dev/null; then
    log_warn "Claude CLI not available for checklist extraction"
    return 1
  fi

  local liberal_checklist="$session_dir/checklist-liberal.yaml"
  local conservative_checklist="$session_dir/checklist-conservative.yaml"
  local comparison_file="$session_dir/checklist-comparison.yaml"
  local grounding_file="$session_dir/checklist-grounding.yaml"

  # Phase 1: Liberal extraction (original prompt - captures more)
  log "Phase 1: Liberal extraction pass..."
  if ! extract_required_elements "$requirements_file" "$liberal_checklist"; then
    log_warn "Liberal extraction failed, falling back to single-pass mode"
    # Fall back to simple extraction
    extract_required_elements "$requirements_file" "$output_file"
    return $?
  fi

  # Phase 2: Conservative extraction (only explicit mentions)
  log "Phase 2: Conservative extraction pass..."
  if ! extract_required_elements_conservative "$requirements_file" "$conservative_checklist"; then
    log_warn "Conservative extraction failed, using liberal-only mode"
    cp "$liberal_checklist" "$output_file"
    return 0
  fi

  # Phase 3: Compare checklists
  log "Phase 3: Comparing extraction results..."
  local low_confidence_count
  low_confidence_count=$(compare_checklists "$liberal_checklist" "$conservative_checklist" "$comparison_file")
  log "Comparison complete: $low_confidence_count items flagged as low confidence"

  # Phase 4: Validate against requirements text
  log "Phase 4: Validating against requirements text..."
  local ungrounded_count
  ungrounded_count=$(validate_checklist_against_requirements "$liberal_checklist" "$requirements_file" "$grounding_file")
  log "Grounding check complete: $ungrounded_count items not found in requirements"

  # Phase 5: Generate final verified checklist with annotations
  log "Phase 5: Generating verified checklist..."
  generate_verified_checklist "$liberal_checklist" "$comparison_file" "$grounding_file" "$output_file"

  # Report summary
  if [ "$low_confidence_count" -gt 0 ] || [ "$ungrounded_count" -gt 0 ]; then
    log_warn "Checklist verification found potential issues:"
    [ "$low_confidence_count" -gt 0 ] && log_warn "  - $low_confidence_count items only found by liberal pass (may be inferred)"
    [ "$ungrounded_count" -gt 0 ] && log_warn "  - $ungrounded_count items not explicitly mentioned in requirements"
    log "Review: $session_dir/checklist-comparison.yaml and $session_dir/checklist-grounding.yaml"
  else
    log_success "Checklist verified: all items confirmed by both passes and grounded in requirements"
  fi

  return 0
}

# Generate final checklist with confidence annotations
# Merges liberal checklist with verification results
# Usage: generate_verified_checklist "$liberal" "$comparison" "$grounding" "$output"
generate_verified_checklist() {
  local liberal_checklist="$1"
  local comparison_file="$2"
  local grounding_file="$3"
  local output_file="$4"

  # Read low-confidence items from comparison
  local low_conf_items=""
  if [ -f "$comparison_file" ]; then
    low_conf_items=$(grep -A 100 '^low_confidence:' "$comparison_file" 2>/dev/null | sed '/^[a-z_]*:/,$d' | grep -v '^$' || echo "")
  fi

  # Read ungrounded items
  local ungrounded_items=""
  if [ -f "$grounding_file" ]; then
    ungrounded_items=$(grep -A 100 '^ungrounded:' "$grounding_file" 2>/dev/null | sed '/^[a-z_]*:/,$d' | grep -v '^$' || echo "")
  fi

  # Start output with header
  {
    echo "# Verified Required Elements Checklist"
    echo "# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "# Verification: dual-LLM + requirements grounding"
    echo "#"
    echo "# Confidence levels:"
    echo "#   (no annotation) = High confidence (both passes + grounded)"
    echo "#   [INFERRED] = Only found by liberal pass (may be implied, not explicit)"
    echo "#   [UNGROUNDED] = Not found in requirements text (potential hallucination)"
    echo ""
  } > "$output_file"

  # Process tables
  echo "tables:" >> "$output_file"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^tables: ]] && continue
    [[ ! "$line" =~ ^[[:space:]]*- ]] && [[ "$line" =~ ^[a-z]+: ]] && break

    local table_name
    table_name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'" | head -c 100)
    [ -z "$table_name" ] && continue

    local annotation=""
    if echo "$low_conf_items" | grep -qi "TABLE:$table_name:ONLY_LIBERAL"; then
      annotation=" # [INFERRED]"
    fi
    if echo "$ungrounded_items" | grep -qi "TABLE:$table_name"; then
      annotation=" # [UNGROUNDED]"
    fi

    echo "  - name: $table_name$annotation" >> "$output_file"
  done < <(grep -A 100 '^tables:' "$liberal_checklist" 2>/dev/null | head -60)

  # Process endpoints
  echo "endpoints:" >> "$output_file"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^endpoints: ]] && continue
    [[ ! "$line" =~ ^[[:space:]]*- ]] && [[ "$line" =~ ^[a-z]+: ]] && break

    local endpoint_name
    endpoint_name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'" | head -c 100)
    [ -z "$endpoint_name" ] && continue

    local annotation=""
    local resource
    resource=$(echo "$endpoint_name" | sed 's|.*/||' | sed 's/{.*}//')
    if echo "$low_conf_items" | grep -qi "ENDPOINT:.*$resource.*:ONLY_LIBERAL"; then
      annotation=" # [INFERRED]"
    fi
    if echo "$ungrounded_items" | grep -qi "ENDPOINT:.*$resource"; then
      annotation=" # [UNGROUNDED]"
    fi

    echo "  - name: $endpoint_name$annotation" >> "$output_file"
  done < <(grep -A 100 '^endpoints:' "$liberal_checklist" 2>/dev/null | head -60)

  # Process components
  echo "components:" >> "$output_file"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^components: ]] && continue
    [[ ! "$line" =~ ^[[:space:]]*- ]] && [[ "$line" =~ ^[a-z]+: ]] && break

    local component_name
    component_name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/.*name:[[:space:]]*//' | tr -d '"' | tr -d "'" | head -c 100)
    [ -z "$component_name" ] && continue

    local annotation=""
    local base
    base=$(echo "$component_name" | sed 's/Page$//' | sed 's/Component$//')
    if echo "$low_conf_items" | grep -qi "COMPONENT:.*$base.*:ONLY_LIBERAL"; then
      annotation=" # [INFERRED]"
    fi
    if echo "$ungrounded_items" | grep -qi "COMPONENT:.*$base"; then
      annotation=" # [UNGROUNDED]"
    fi

    echo "  - name: $component_name$annotation" >> "$output_file"
  done < <(grep -A 100 '^components:' "$liberal_checklist" 2>/dev/null | head -60)

  # Copy connections section as-is (connections are harder to verify programmatically)
  echo "connections:" >> "$output_file"
  grep -A 200 '^connections:' "$liberal_checklist" 2>/dev/null | tail -n +2 | while IFS= read -r line; do
    [[ "$line" =~ ^[a-z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]] ]] && break
    echo "$line" >> "$output_file"
  done

  return 0
}

# Validate extracted diagram elements against the required elements checklist
# Uses fuzzy matching at resource level (not sub-routes)
# Usage: validate_against_checklist "$checklist_file" "$extracted_elements"
# Returns: 0 if all required elements found, 1 with missing items if gaps
validate_against_checklist() {
  local checklist_file="$1"
  local extracted_elements="$2"
  local missing=()

  if [ ! -f "$checklist_file" ]; then
    log_warn "Checklist file not found: $checklist_file"
    return 0  # Skip validation if no checklist
  fi

  # Normalize extracted elements for comparison
  local extracted_normalized
  extracted_normalized=$(echo "$extracted_elements" | tr '[:upper:]' '[:lower:]' | tr '_' ' ' | tr '-' ' ')

  # Check tables (fuzzy - handles underscores, plurals, case)
  while IFS= read -r table; do
    [ -z "$table" ] && continue
    table=$(echo "$table" | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '[:space:]')
    [ -z "$table" ] && continue

    local normalized
    normalized=$(echo "$table" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')

    # Try exact match first, then fuzzy
    if ! echo "$extracted_normalized" | grep -qi "$normalized"; then
      # Try without common suffixes
      local base
      base=$(echo "$normalized" | sed 's/s$//')
      if ! echo "$extracted_normalized" | grep -qi "$base"; then
        missing+=("TABLE: $table")
      fi
    fi
  done < <(grep -A 100 '^tables:' "$checklist_file" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^[[:space:]]*-' | head -50)

  # Check endpoints (resource level - extract base resource name)
  while IFS= read -r endpoint; do
    [ -z "$endpoint" ] && continue
    endpoint=$(echo "$endpoint" | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '[:space:]')
    [ -z "$endpoint" ] && continue

    # Extract resource name from endpoint (last path segment, without parameters)
    local resource
    resource=$(echo "$endpoint" | sed 's|.*/||' | sed 's/{.*}//' | tr '_' ' ' | tr '-' ' ' | tr '[:upper:]' '[:lower:]')
    [ -z "$resource" ] && continue

    if ! echo "$extracted_normalized" | grep -qi "$resource"; then
      # Try singular form
      local singular
      singular=$(echo "$resource" | sed 's/s$//')
      if ! echo "$extracted_normalized" | grep -qi "$singular"; then
        missing+=("ENDPOINT: $endpoint")
      fi
    fi
  done < <(grep -A 100 '^endpoints:' "$checklist_file" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^[[:space:]]*-' | head -50)

  # Check components (fuzzy - strip common suffixes)
  while IFS= read -r component; do
    [ -z "$component" ] && continue
    component=$(echo "$component" | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '[:space:]')
    [ -z "$component" ] && continue

    # Strip common suffixes and convert to search-friendly format
    local base
    base=$(echo "$component" | \
      sed 's/Page$//' | sed 's/Manager$//' | sed 's/Editor$//' | \
      sed 's/Browser$//' | sed 's/Tracker$//' | sed 's/Dashboard$//' | \
      sed 's/Component$//' | sed 's/Panel$//' | sed 's/View$//' | \
      tr '[:upper:]' '[:lower:]' | tr '_' ' ' | tr '-' ' ')

    if ! echo "$extracted_normalized" | grep -qi "$base"; then
      missing+=("COMPONENT: $component")
    fi
  done < <(grep -A 100 '^components:' "$checklist_file" 2>/dev/null | sed '/^[a-z]*:/,$d' | grep -E '^[[:space:]]*-' | head -50)

  if [ ${#missing[@]} -eq 0 ]; then
    echo "COVERAGE_COMPLETE"
    return 0
  else
    echo "Missing required elements:"
    printf '%s\n' "${missing[@]}"
    return 1
  fi
}

# Validate diagram connections against required connections from checklist
# Ensures proper data flow: Component -> API -> Database (not Component -> Database directly)
# Usage: validate_diagram_connections "$mermaid_content" "$session_dir"
# Returns: 0 if all connections valid, 1 with missing connections if gaps found
validate_diagram_connections() {
  local mermaid_content="$1"
  local session_dir="$2"
  local checklist_file="$session_dir/required-elements.yaml"
  local missing_connections=()
  local wrong_connections=()

  # Skip if no checklist or no connections section
  if [ ! -f "$checklist_file" ]; then
    echo "CONNECTIONS_VALID"
    return 0
  fi

  # Check if checklist has connections section
  if ! grep -q '^connections:' "$checklist_file"; then
    echo "CONNECTIONS_VALID"
    return 0
  fi

  # Extract actual connections from diagram
  local actual_connections
  actual_connections=$(extract_diagram_connections "$mermaid_content")

  # Parse expected connections from checklist YAML
  # Format in YAML:
  # connections:
  #   - source: ComponentName
  #     target: /api/v1/resource
  #     type: calls
  local in_connections=false
  local current_source=""
  local current_target=""
  local current_type=""

  while IFS= read -r line; do
    # Start of connections section
    if [[ "$line" =~ ^connections: ]]; then
      in_connections=true
      continue
    fi

    # End of connections section (another top-level key)
    if [[ "$in_connections" == true ]] && [[ "$line" =~ ^[a-z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
      in_connections=false
      continue
    fi

    # Skip if not in connections section
    [[ "$in_connections" != true ]] && continue

    # New connection entry (starts with -)
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*source: ]]; then
      # Process previous connection if exists
      if [[ -n "$current_source" ]] && [[ -n "$current_target" ]]; then
        if ! find_matching_connection "$current_source" "$current_target" "$actual_connections"; then
          missing_connections+=("$current_source -> $current_target ($current_type)")
        fi
      fi
      # Start new connection
      current_source=$(echo "$line" | sed 's/.*source:[[:space:]]*//' | tr -d '"' | tr -d "'")
      current_target=""
      current_type=""
      continue
    fi

    # Parse target
    if [[ "$line" =~ ^[[:space:]]+target: ]]; then
      current_target=$(echo "$line" | sed 's/.*target:[[:space:]]*//' | tr -d '"' | tr -d "'")
      continue
    fi

    # Parse type
    if [[ "$line" =~ ^[[:space:]]+type: ]]; then
      current_type=$(echo "$line" | sed 's/.*type:[[:space:]]*//' | tr -d '"' | tr -d "'")
      continue
    fi
  done < "$checklist_file"

  # Process last connection
  if [[ -n "$current_source" ]] && [[ -n "$current_target" ]]; then
    if ! find_matching_connection "$current_source" "$current_target" "$actual_connections"; then
      missing_connections+=("$current_source -> $current_target ($current_type)")
    fi
  fi

  # Report results
  if [ ${#missing_connections[@]} -eq 0 ]; then
    echo "CONNECTIONS_VALID"
    return 0
  else
    echo "Missing required connections:"
    printf '  - %s\n' "${missing_connections[@]}"
    return 1
  fi
}

# Helper: Find if a connection exists in actual connections (with fuzzy matching)
# Usage: find_matching_connection "source" "target" "$actual_connections"
# Returns: 0 if found, 1 if not found
find_matching_connection() {
  local expected_source="$1"
  local expected_target="$2"
  local actual_connections="$3"

  while IFS='|' read -r actual_source actual_target actual_label; do
    [[ -z "$actual_source" ]] && continue

    # Check if both endpoints match (using fuzzy matching)
    if connection_endpoints_match "$expected_source" "$actual_source" && \
       connection_endpoints_match "$expected_target" "$actual_target"; then
      return 0
    fi
  done <<< "$actual_connections"

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

# Verify diagram covers the original request using checklist-based validation
# Two-phase approach:
#   1. Extract checklist from requirements ONCE per session (LLM)
#   2. Validate diagram elements against checklist (programmatic - deterministic)
# This prevents infinite loops caused by LLM judgment on "adequate" coverage
# Usage: verify_request_coverage "$diagram_content" "$session_dir"
# Returns: 0 if coverage complete, 1 with missing items if gaps found
verify_request_coverage() {
  local diagram="$1"
  local session_dir="$2"

  local requirements_file="$session_dir/refined-requirements.md"
  local checklist_file="$session_dir/required-elements.yaml"

  # Fallback to feature description if refined requirements don't exist
  if [ ! -f "$requirements_file" ]; then
    requirements_file="$session_dir/raw-request.md"
  fi

  # Generate checklist once per session using verified extraction
  if [ ! -f "$checklist_file" ]; then
    log "Generating verified checklist (dual-LLM + requirements grounding)..."
    if ! extract_required_elements_verified "$requirements_file" "$checklist_file" "$session_dir"; then
      log_warn "Verified extraction failed, falling back to simple extraction..."
      if ! extract_required_elements "$requirements_file" "$checklist_file"; then
        log_warn "Could not generate checklist, skipping coverage check"
        return 0
      fi
    fi
    log "Checklist saved: $(wc -l < "$checklist_file") lines"
  fi

  # Extract elements from diagram (programmatic - no hallucination)
  local extracted=""

  # Extract node IDs (e.g., NOTIF, ORGAPI, etc.)
  extracted+=$(echo "$diagram" | grep -oE '^\s*[A-Z_][A-Z0-9_]*\[' | sed 's/\[$//' | sed 's/^\s*//')
  extracted+=$'\n'

  # Extract API endpoints
  extracted+=$(echo "$diagram" | grep -oE '/api/v1/[a-z_/{}\-]+')
  extracted+=$'\n'

  # Extract labeled elements (node labels in quotes)
  extracted+=$(echo "$diagram" | grep -oE '\["[^"]+"\]' | sed 's/\["//g; s/"\]//g; s/\[NEW\] //g')
  extracted+=$'\n'

  # Extract database notation [(table)]
  extracted+=$(echo "$diagram" | grep -oE '\[\([a-z_]+' | sed 's/\[(//')
  extracted+=$'\n'

  # Extract subgraph names
  extracted+=$(echo "$diagram" | grep -oE 'subgraph\s+[a-z_]+' | sed 's/subgraph\s*//')
  extracted+=$'\n'

  # Extract connection labels (what flows between components)
  extracted+=$(echo "$diagram" | grep -oE '\|"[^"]+"\|' | sed 's/|"//g; s/"|//g')

  # Validate against checklist (deterministic - no LLM judgment)
  validate_against_checklist "$checklist_file" "$extracted"
}

# Main verification function with auto-regeneration loop
# Uses checklist-based validation for deterministic coverage checking
# Usage: verify_and_regenerate "$diagram_file" "$index_file" "$session_dir"
# Returns: 0 if valid (possibly after fixes), 1 if still invalid after max retries
verify_and_regenerate() {
  local diagram_file="$1"
  local index_file="$2"
  local session_dir="$3"
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

    # Step 3: Coverage check using checklist-based validation (deterministic)
    # Uses session_dir to find/generate the required-elements.yaml checklist
    if [ -z "$errors" ]; then
      local coverage_errors
      if ! coverage_errors=$(verify_request_coverage "$mermaid_content" "$session_dir" 2>&1); then
        if [ -n "$coverage_errors" ] && [ "$coverage_errors" != "COVERAGE_COMPLETE" ]; then
          errors="COVERAGE ISSUES:\n$coverage_errors\n\n"
        fi
      fi
    fi

    # Step 3.5: Connection validation - verify proper data flow paths
    # Catches wrong wiring like Component -> Database (bypassing API)
    if [ -z "$errors" ]; then
      local conn_errors
      if ! conn_errors=$(validate_diagram_connections "$mermaid_content" "$session_dir" 2>&1); then
        if [ -n "$conn_errors" ] && [ "$conn_errors" != "CONNECTIONS_VALID" ]; then
          errors+="CONNECTION ISSUES:\n$conn_errors\n\n"
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
      # Load requirements context from session
      local requirements_context=""
      if [ -f "$session_dir/refined-requirements.md" ]; then
        requirements_context=$(cat "$session_dir/refined-requirements.md")
      elif [ -f "$session_dir/raw-request.md" ]; then
        requirements_context=$(cat "$session_dir/raw-request.md")
      fi

      # IMPORTANT: Fix prompt uses exact same format requirements as main prompt
      # The output format section is placed FIRST to maximize compliance
      local fix_prompt_file
      fix_prompt_file=$(mktemp)
      cat > "$fix_prompt_file" << FIX_PROMPT_EOF
ENDPOINT TABLE MAPPING:
- [YOUR FIRST ENDPOINT]: PRIMARY=[table], SECONDARY=[tables or none]

Complete the mapping above and add the diagram below. Follow this EXACT format.

===REQUIRED OUTPUT FORMAT===
Line 1: ENDPOINT TABLE MAPPING:
Lines 2-N: - /api/v1/path: PRIMARY=tablename, SECONDARY=other_tables
Blank line
$(printf '%s' '```mermaid')
[Your corrected diagram]
$(printf '%s' '```')

NO OTHER TEXT. No explanations. No commentary. Start your response with the mapping.
===END FORMAT===

CURRENT DIAGRAM TO FIX:
$mermaid_content

ISSUES TO FIX:
$(echo -e "$errors")

FEATURE CONTEXT:
$requirements_context

RULES:
- Add missing elements from COVERAGE ISSUES
- Fix incorrect elements
- Keep correct elements unchanged
- Use T_ prefix for tables, _API suffix for endpoints
- Use 2-3 letter frontend component IDs

OUTPUT NOW (start with 'ENDPOINT TABLE MAPPING:'):
FIX_PROMPT_EOF
      local fix_prompt
      fix_prompt=$(cat "$fix_prompt_file")
      rm -f "$fix_prompt_file"

      # Save current diagram as backup
      cp "$diagram_file" "$diagram_file.backup-$retry"

      # Regenerate to a temp file first
      local raw_output="$diagram_file.raw-$retry"
      claude --dangerously-skip-permissions --print "$fix_prompt" 2>&1 > "$raw_output" || {
        log_error "Regeneration failed, restoring backup"
        cp "$diagram_file.backup-$retry" "$diagram_file"
        rm -f "$raw_output"
        continue
      }

      # Normalize the output to strip any non-conforming text
      normalize_diagram_output "$raw_output" "$diagram_file"
      rm -f "$raw_output"
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

Pipeline Steps (17):
  1. Repo Familiarization  - Understand the current repository via /dr
  2. Feature Input         - Prompt user to describe the feature
  3. Context Research      - Deep research to understand the domain
  4. Refinement            - Ask clarifying questions
  5. Impl Research         - Research implementation patterns
  6. Summary               - Save conversation summary
  7. Flow Diagram          - Generate and verify flow diagram
  8. Database Sync         - Persist to PostgreSQL
  9. Data Schema           - Generate domain model, migration, SQLAlchemy models
  10. Run Migration        - Apply migration SQL to PostgreSQL
  11. Integrate Models     - Copy models into backend, register in __init__.py
  12. API Generation       - Generate FastAPI router + Pydantic schemas
  13. Journey Generation   - Generate user journeys via generate-journeys.sh
  14. Frontend Types       - Generate TypeScript type definitions
  15. Frontend API         - Generate API client from router contract
  16. Frontend Pages       - Generate page components with validation + retry
  17. Frontend Integrate   - Copy files to codebase, add routes + nav to App.tsx

Output Files:
  .claude/RESEARCH/{session}/
  ├── repo-analysis.md        - Repository understanding
  ├── feature-input.md        - Original user request
  ├── refined-requirements.md - After /dr-refine clarification
  ├── research-output.md      - /dr research results
  ├── summary.md              - Complete conversation summary
  ├── flow-feedback.md        - User feedback during iterations
  ├── flow-confirmed.txt      - Confirmation marker
  ├── schema-migration.sql    - PostgreSQL migration DDL
  ├── schema-sqlalchemy.py    - SQLAlchemy model definitions
  ├── api-router.py           - Generated FastAPI router
  ├── api-schemas.py          - Generated Pydantic schemas
  └── journeys.json           - Generated user journeys

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
    local total=12

    # Check each step's completion
    [ -f "$session_dir/repo-analysis.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/feature-input.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/refined-requirements.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/research-output.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/summary.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/flow-confirmed.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/scope-synced.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/schema-complete.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/migration-complete.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/models-integrated.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/api-generated.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/journeys-generated.txt" ] && completed=$((completed + 1))

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
  if [ -f "$session_dir/personas-generated.txt" ]; then
    echo 20  # All 19 steps done — resume past end
  elif [ -f "$session_dir/build-deployed.txt" ]; then
    echo 19  # Steps 1-18 done, resume from step 19 (personas)
  elif [ -f "$session_dir/frontend-integrated.txt" ]; then
    echo 17  # Resume from step 18 (build & deploy)
  elif [ -f "$session_dir/frontend-complete.txt" ]; then
    echo 16  # Resume from step 17 (integrate)
  elif [ -f "$session_dir/api-client-generated.txt" ]; then
    echo 15  # Resume from step 16 (pages)
  elif [ -f "$session_dir/types-generated.txt" ]; then
    echo 14  # Resume from step 15 (api client)
  elif [ -f "$session_dir/journeys-generated.txt" ]; then
    echo 13  # Resume from step 14 (types)
  elif [ -f "$session_dir/api-generated.txt" ]; then
    echo 12  # Steps 1-11 skip, resume from step 12 (step 13 runs fresh)
  elif [ -f "$session_dir/models-integrated.txt" ]; then
    echo 11  # Steps 1-10 skip, resume from step 11 (step 12 runs fresh)
  elif [ -f "$session_dir/migration-complete.txt" ]; then
    echo 10  # Steps 1-9 skip, resume from step 10 (step 11 runs fresh)
  elif [ -f "$session_dir/schema-complete.txt" ]; then
    echo 9  # Steps 1-8 skip, resume from step 9 (step 10 runs fresh)
  elif [ -f "$session_dir/scope-synced.txt" ]; then
    echo 8  # Resume from step 8 (data schema)
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

  # Load preliminary research if it exists
  if [ -f "$session_dir/preliminary-research.md" ]; then
    PRELIMINARY_RESEARCH=$(sed '1,/^---$/d; 1,/^---$/d' "$session_dir/preliminary-research.md" | head -100)
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

log_separator() {
  echo ""
  echo -e "${DIM}  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─${NC}"
  echo ""
}

# Prompt user to continue or restart a step with existing files
# Usage: prompt_step_resume step_num "description" file1 [file2 ...]
# Returns: 0 = continue (files preserved), 1 = restart (files deleted)
prompt_step_resume() {
  local step_num="$1"
  local description="$2"
  shift 2
  local files=("$@")

  # Check if any of the files exist
  local existing_files=()
  for f in "${files[@]}"; do
    if [ -f "$f" ]; then
      existing_files+=("$f")
    fi
  done

  # No existing files, nothing to prompt
  if [ ${#existing_files[@]} -eq 0 ]; then
    return 1  # Signal: start fresh
  fi

  echo ""
  echo -e "  ${YELLOW}Found existing $description${NC}"
  echo ""
  echo "  [R] Resume with existing progress"
  echo "  [D] Delete and restart from scratch"
  echo ""
  printf "  Choice [R/d]: "
  read -r choice

  if [[ "$choice" =~ ^[Dd]$ ]]; then
    # Delete: remove existing files and restart
    for f in "${existing_files[@]}"; do
      rm -f "$f"
    done
    echo -e "  ${DIM}Deleted previous progress${NC}"
    return 1  # Signal: restart
  else
    echo -e "  ${GREEN}Resuming with existing progress${NC}"
    return 0  # Signal: continue
  fi
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

# Step 2: Get feature description from user (or use pre-context if available)
get_feature_input() {
  show_step_header 2 "Feature Description" "input"

  # Check if pre-context.md exists (created by planner-tui.sh)
  local pre_context="$SESSION_DIR/pre-context.md"
  if [ -f "$pre_context" ]; then
    echo -e "  ${GREEN}✓ Found pre-seeded context from planner${NC}"
    echo ""

    # Extract the feature description from pre-context
    # Look for content between "## Feature Description" and the next "##" section
    local extracted=""
    extracted=$(sed -n '/^## Feature Description/,/^## /p' "$pre_context" | sed '1d;$d' | sed '/^$/d')

    if [ -n "$extracted" ]; then
      echo -e "  ${CYAN}Feature from planner:${NC}"
      echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
      echo "$extracted" | sed 's/^/  /'
      echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
      echo ""
      echo -e "  ${YELLOW}Press Enter to use this, or type new description:${NC}"
      echo ""

      input_prompt
      read -e line

      if [ -z "$line" ]; then
        # Use the extracted content
        FEATURE_DESCRIPTION="$extracted"
      else
        # User wants to provide their own - read multi-line
        local input="$line"
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
      fi
    else
      # Couldn't extract, fall through to manual input
      echo -e "  ${YELLOW}Pre-context found but couldn't extract description${NC}"
      show_input_mode "What feature would you like to implement? (describe your idea - empty line to continue)"

      local input=""
      local line=""
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
    fi
  else
    # No pre-context, get manual input
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
  fi

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

# Step 3: Preliminary research on user's feature description
# This helps Claude understand what the user is talking about BEFORE asking clarifying questions
preliminary_research() {
  show_step_header 3 "Context Research" "research"

  log "Running deep research to understand the feature domain..."
  echo ""
  echo -e "  ${DIM}This research will help inform better clarifying questions.${NC}"
  echo ""

  if ! command -v claude &> /dev/null; then
    log_error "Claude CLI not found - skipping preliminary research"
    PRELIMINARY_RESEARCH=""
    echo "Preliminary research skipped - Claude CLI not available" > "$SESSION_DIR/preliminary-research.md"
    complete_step 3 "Skipped (no Claude CLI)"
    return
  fi

  # Build a focused research query based on the feature description
  local research_query="Research the following feature concept to understand the domain, terminology, and implementation patterns:

FEATURE REQUEST:
$FEATURE_DESCRIPTION

RESEARCH GOALS:
1. **Domain Understanding**: What domain/industry is this feature from? What are the key concepts and terminology?
2. **Similar Implementations**: How do other systems typically implement this type of feature?
3. **Technical Components**: What are the typical components needed (APIs, data models, UI elements)?
4. **Best Practices**: What are common patterns and anti-patterns for this type of feature?
5. **Integration Points**: How does this typically integrate with existing systems?

FOCUS: Provide practical context that would help ask better clarifying questions about implementation specifics."

  # Start spinner while research runs
  start_spinner "Researching feature domain and patterns..."

  local research_output
  research_output=$(claude --dangerously-skip-permissions --print "/dr $research_query" 2>&1) || {
    stop_spinner ""
    log_error "Preliminary research had issues"
    research_output="Research incomplete - see partial output"
  }

  stop_spinner ""

  # Store for use in refine_requirements
  PRELIMINARY_RESEARCH="$research_output"

  # Save to file
  cat > "$SESSION_DIR/preliminary-research.md" << EOF
---
name: $SESSION_NAME-preliminary-research
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
type: preliminary-research
---

# Preliminary Research

## Original Feature Request
$FEATURE_DESCRIPTION

## Research Findings
$research_output
EOF

  complete_step 3 "Context research complete"
  dim_path "  Saved: $SESSION_DIR/preliminary-research.md"

  # Show brief excerpt
  echo ""
  echo -e "  ${DIM}Research highlights:${NC}"
  echo "$research_output" | head -15 | sed 's/^/  /' || true
  echo -e "  ${DIM}...${NC}"
  echo ""
}

# Step 4: Refine requirements (now uses preliminary research)
refine_requirements() {
  show_step_header 4 "Refining Requirements" "input"

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

    # Add preliminary research context (from Step 3)
    local research_context=""
    if [ -n "${PRELIMINARY_RESEARCH:-}" ]; then
      research_context="

PRELIMINARY RESEARCH (from Step 3 - domain context):
$(echo "$PRELIMINARY_RESEARCH" | head -100)

Use this research to ask INFORMED, SPECIFIC questions. You now understand the domain - ask about implementation details, edge cases, and specific requirements rather than basic clarifying questions.
"
    elif [ -f "$SESSION_DIR/preliminary-research.md" ]; then
      research_context="

PRELIMINARY RESEARCH (from Step 3 - domain context):
$(sed '1,/^---$/d; 1,/^---$/d' "$SESSION_DIR/preliminary-research.md" | head -100)

Use this research to ask INFORMED, SPECIFIC questions. You now understand the domain - ask about implementation details, edge cases, and specific requirements rather than basic clarifying questions.
"
    fi

    # Initialize conversation loop variables
    local conversation_round=0
    local max_rounds=25  # High enough to never hit; user exits anytime with empty line
    local conversation_history=""
    local full_session=""

    # Check for existing refinement session - prompt continue/restart
    if prompt_step_resume 4 "refinement session" "$SESSION_DIR/refinement-session.md"; then
      # Continue: load conversation history from existing file
      conversation_history=$(sed -n '/^## Conversation/,$p' "$SESSION_DIR/refinement-session.md" | tail -n +2)

      # Count existing rounds to resume from correct number
      local existing_rounds=$(grep -c "^### Round" "$SESSION_DIR/refinement-session.md" 2>/dev/null || echo "0")
      conversation_round=$((existing_rounds / 2))  # Each round has Claude + User entries

      echo -e "  ${DIM}Loaded $conversation_round rounds from previous session${NC}"
      echo ""
    else
      # Restart: create fresh refinement session file
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
    fi

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
        # First round - initial context WITH preliminary research
        cat > "$refine_context_file" << EOF
Feature Request: $FEATURE_DESCRIPTION
$arch_context
$research_context

Based on the research above, you now understand the domain and common patterns for this type of feature.

Ask SPECIFIC, INFORMED clarifying questions that focus on:
- Implementation details unique to THIS user's needs
- Edge cases and error handling preferences
- Integration specifics with THEIR existing system
- Performance/scale requirements
- UI/UX preferences

Do NOT ask basic "what do you mean by X" questions - the research has given you context.
Ask 2-3 targeted questions to nail down implementation specifics.
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
      # Note: Using --print with direct prompt, NOT /dr-refine skill
      # (skills using AskUserQuestion don't work in captured output mode)
      local claude_response
      claude_response=$(claude --dangerously-skip-permissions --print "$(cat "$refine_context_file")

Output 2-3 specific clarifying questions to gather requirements. Format each as a numbered question. Be direct and practical." 2>&1) || {
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

        complete_step 4 "Requirements refined (auto-completed after $conversation_round rounds)"
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

    complete_step 4 "Requirements refined ($conversation_round rounds)"
    dim_path "  Saved: $SESSION_DIR/refined-requirements.md"
    dim_path "  Saved: $SESSION_DIR/refinement-session.md"
  else
    log_error "Claude CLI not found - skipping refinement"
    REFINED_DESCRIPTION="$FEATURE_DESCRIPTION"
    echo "$FEATURE_DESCRIPTION" > "$SESSION_DIR/refined-requirements.md"
    complete_step 4 "Skipped (no Claude CLI)"
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

# Step 5: Deep research (implementation patterns)
research_feature() {
  show_step_header 5 "Researching Implementation" "research"

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
    complete_step 5 "Research complete"
    dim_path "  Saved: $SESSION_DIR/research-output.md"

    # Show brief excerpt
    echo ""
    echo -e "  ${DIM}Research highlights:${NC}"
    head -20 "$SESSION_DIR/research-output.md" 2>/dev/null | sed 's/^/  /' || true
    echo -e "  ${DIM}...${NC}"
  else
    log_error "Claude CLI not found - skipping research"
    echo "Research skipped - Claude CLI not available" > "$SESSION_DIR/research-output.md"
    complete_step 5 "Skipped (no Claude CLI)"
  fi
}

# Step 5: Save conversation summary
save_summary() {
  show_step_header 6 "Saving Conversation Summary" "sync"

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

  complete_step 6 "Summary saved"
  dim_path "  Saved: $SESSION_DIR/summary.md"
}

# Step 6: Flow diagram verification loop (two-phase: system flow first, then supplementary)
flow_diagram_loop() {
  show_step_header 7 "Flow Diagram Verification" "verify"

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

  # Data Layer Interrogation - auto-analyze for consistent API→Table mapping
  local data_layer_context=""
  if [ ! -f "$SESSION_DIR/data-layer-answers.md" ]; then
    echo ""
    echo -e "  ${CYAN}${BOLD}Analyzing Data Layer${NC} ${DIM}(auto-inferring from requirements)${NC}"
    echo ""

    local data_entities=""
    local data_references=""
    local data_operations=""
    local data_access_pattern=""

    # Infer primary entities from requirements using Claude
    if command -v claude &> /dev/null; then
      log "Analyzing requirements for data entities..."
      data_entities=$(claude --dangerously-skip-permissions --print "Based on this feature description, list the main data things (nouns) that will be stored/managed. Just list them comma-separated, no explanation:

Feature: $SESSION_NAME
Requirements: $requirements_context

Example output: listings, offers, pricing agreements" 2>/dev/null | tail -1 | tr -d '\r') || true
      [ -n "$data_entities" ] && echo -e "  ${DIM}Entities:${NC} $data_entities"
    fi

    # Infer connections to existing data
    if command -v claude &> /dev/null && [ -n "$data_entities" ]; then
      log "Analyzing for connections to existing data..."
      local existing_tables=""
      existing_tables=$(echo "$architecture_context" | grep -oE "[a-z_]+:" | sed 's/://g' | sort -u | head -20 | tr '\n' ', ' | sed 's/,$//')

      if [ -n "$existing_tables" ]; then
        data_references=$(claude --dangerously-skip-permissions --print "Which of these EXISTING tables would '$data_entities' need foreign keys to?

Existing tables: $existing_tables

Reply with ONLY a comma-separated list of table names, or 'none'.
Example: vendors, inventory_items
Example: none" 2>/dev/null | tail -1 | tr -d '\r') || true
      fi
      [ -z "$data_references" ] && data_references="none"
      echo -e "  ${DIM}References:${NC} $data_references"
    fi

    # Infer operations from requirements
    if command -v claude &> /dev/null && [ -n "$data_entities" ]; then
      log "Analyzing for user operations..."
      data_operations=$(claude --dangerously-skip-permissions --print "What operations can users perform on '$data_entities' based on these requirements?

Requirements: $requirements_context

Reply with ONLY a comma-separated list from: create, view, edit, delete, search, export, import
Example: create, view, edit, delete
Example: view, search" 2>/dev/null | tail -1 | tr -d '\r') || true
      [ -z "$data_operations" ] && data_operations="create, view, edit, delete"
      echo -e "  ${DIM}Operations:${NC} $data_operations"
    fi

    # Infer access patterns
    if command -v claude &> /dev/null && [ -n "$data_references" ] && [ "$data_references" != "none" ]; then
      log "Analyzing access patterns..."
      data_access_pattern=$(claude --dangerously-skip-permissions --print "When displaying '$data_entities', which related data from '$data_references' would typically be shown together?

Reply with a short phrase like: vendor name, category
Or: none (displayed standalone)" 2>/dev/null | tail -1 | tr -d '\r' | cut -c1-60) || true
    fi
    [ -z "$data_access_pattern" ] && data_access_pattern="none"
    echo -e "  ${DIM}Access pattern:${NC} $data_access_pattern"

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
    log "Data layer context auto-generated"
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
Create a flowchart TD (top-down) with EXACTLY this structure:

LAYER 1 - Frontend (1-3 nodes only):
- Main page component: {PREFIX}[PageName]
- Optional modal/form: {PREFIX}_MODAL[ModalName] or {PREFIX}_FORM[FormName]

LAYER 2 - Backend (1-3 nodes only):
- Primary API endpoint: {PREFIX}_API["/api/v1/..."]
- Optional secondary endpoints if distinct resources

LAYER 3 - Data (1-3 tables only):
- Primary table: T_{ABBREV}[(table_name)]
- Foreign key tables only if explicitly referenced

TOTAL: 3-9 nodes maximum. Each endpoint connects to exactly ONE primary table.

Use exact component names from the architecture_index when they exist. Prefix new components with [NEW].

CRITICAL: Do NOT add intermediate processing nodes (like "Validate", "Generate", "Store").
Show only: Page -> API -> Table with labeled edges.
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

<deterministic_naming>
CRITICAL: Use EXACTLY these naming conventions for consistent output:

NODE ID RULES (follow precisely):
- Frontend components: 2-3 uppercase letters (OM, RM, VE, MB, TD, ST)
- Backend endpoints: Same prefix + "_API" suffix (ORG_API, REL_API, VIS_API, MKT_API, TRF_API, SOLD_API)
- Database tables: "T_" prefix + abbreviated name (T_ORG, T_UO, T_TR, T_IV, T_IT, T_INV)

SUBGRAPH RULES (follow precisely):
- Use singular form: "Frontend" not "Frontends"
- Exactly 3 subgraphs: frontend, backend, data
- No nested subgraphs inside data layer
- Format: subgraph name[Label]

EDGE LABEL RULES (follow precisely):
- Always quote API paths: ["/api/v1/path"]
- FK references use column name: |item_id| not |belongs to|
- CRUD labels: |"CRUD: tablename"|
- Action labels: |"GET"| |"POST"| |"reads"| |"writes"|

QUOTING RULES:
- API paths always quoted: ["/api/v1/organizations"]
- Labels with special chars quoted: ["[NEW] ComponentName"]
- Table names in database notation: [(tablename)]
</deterministic_naming>

<example>
A well-structured system flow diagram using EXACT naming conventions:
\`\`\`mermaid
flowchart TD
    subgraph frontend[Frontend]
        IP[InventoryPage]
        BI["[NEW] BulkImportModal"]
    end
    subgraph backend[Backend]
        INV_API["/api/v1/inventory/items"]
        BULK_API["[NEW] /api/v1/inventory/bulk-import"]
    end
    subgraph data[Data Layer]
        T_INV[(inventory_items)]
        T_CAT[(inventory_categories)]
        T_BATCH["[NEW] (import_batches)"]
    end
    IP -->|"GET"| INV_API
    BI -->|"POST"| BULK_API
    INV_API -->|"CRUD: inventory_items"| T_INV
    INV_API -->|"JOIN: category_id"| T_CAT
    BULK_API -->|"CRUD: import_batches"| T_BATCH
    BULK_API -->|"writes"| T_INV

    classDef newNode fill:#e1f5fe,stroke:#01579b
    class BI,BULK_API,T_BATCH newNode
\`\`\`

Notice the EXACT naming pattern:
- Frontend: 2-letter IDs (IP, BI)
- Backend: PREFIX_API suffix (INV_API, BULK_API)
- Database: T_ prefix (T_INV, T_CAT, T_BATCH)
- All paths quoted, all edge labels quoted
</example>

<frontend_subgraph_schema>
MANDATORY: Frontend subgraph components MUST follow this EXACT pattern:

For any page with a form that stores state:
1. PAGE node: {PREFIX}[PageName] - The main page component
2. FORM node: {PREFIX}_FORM[{PageName} Form] - The form component (use "Form" suffix)
3. STATE node: {PREFIX}_STATE[Auth State|Form State|etc] - State storage (use "State" suffix)

EXACT LABELS (use these verbatim):
- Login forms: LP_FORM[Login Form], LP_STATE[Auth State]
- Search forms: {X}_FORM[Search Form], {X}_STATE[Search State]
- Edit forms: {X}_FORM[Edit Form], {X}_STATE[Form State]

DO NOT use alternative labels like:
- "Credentials Form" (use "Login Form")
- "Token Storage" (use "Auth State")
- "Input Form" (use the specific type + "Form")
</frontend_subgraph_schema>

<edge_label_schema>
MANDATORY: Edge labels MUST use these EXACT formats:

HTTP REQUEST LABELS (choose one, use verbatim):
- |"POST email, password"| - for login/auth (comma-separated params)
- |"POST {resource}"| - for creation
- |"GET"| - for retrieval
- |"PUT {resource}"| - for update
- |"DELETE"| - for deletion

DATABASE RESULT LABELS (use verbatim):
- |"user record"| - for user lookups
- |"item record"| - for item lookups
- |"{entity} record"| - pattern for other entities

PROCESSING LABELS (use verbatim):
- |"bcrypt verify"| - for password verification
- |"access_token, token_type"| - for JWT response
- |"store token"| - for token storage

DO NOT use alternatives like:
- "POST email/password" (use "POST email, password")
- "valid credentials" (use "bcrypt verify")
- "access_token" alone (use "access_token, token_type")
</edge_label_schema>

<flow_pattern_schema>
MANDATORY: Success-only flows (do not show error paths):

For authentication flows, use this EXACT pattern:
LP --> LP_FORM
LP_FORM -->|"POST email, password"| AUTH_API
AUTH_API -->|"SELECT by email"| T_USERS
T_USERS -->|"user record"| PWD_VERIFY
PWD_VERIFY -->|"bcrypt verify"| JWT_GEN
JWT_GEN -->|"access_token, token_type"| LP_STATE
LP_STATE -->|"store token"| LP

DO NOT add error handling arrows like:
- PWD_VERIFY -->|"invalid credentials"| LP_FORM
- AUTH_API -->|"error"| LP_FORM

Show the happy path only. Error handling is implementation detail.
</flow_pattern_schema>

<output_format>
###OUTPUT_START###

Your response MUST begin with EXACTLY this marker and format:

ENDPOINT TABLE MAPPING:

- /api/v1/{path}: PRIMARY={table} ({reason})

\`\`\`mermaid
flowchart TD
    subgraph frontend[Frontend]
        ...
    end
    subgraph backend[Backend]
        ...
    end
    subgraph data[Data Layer]
        ...
    end
    ...connections...
\`\`\`

###OUTPUT_END###

STRICT REQUIREMENTS:
1. First line of response: "ENDPOINT TABLE MAPPING:"
2. No text before "ENDPOINT TABLE MAPPING:"
3. No text after the closing \`\`\`
4. Use EXACT labels from frontend_subgraph_schema
5. Use EXACT labels from edge_label_schema
6. Follow EXACT flow pattern from flow_pattern_schema
</output_format>

<final_reminder>
BEFORE YOU RESPOND, verify:
[ ] Response starts with "ENDPOINT TABLE MAPPING:" (nothing before it)
[ ] Frontend uses: {X}[Page], {X}_FORM[...Form], {X}_STATE[...State]
[ ] Edge labels match the edge_label_schema EXACTLY
[ ] Flow shows happy path only (no error arrows)
[ ] Response ends with closing \`\`\` (nothing after it)
</final_reminder>
PROMPT_EOF

      claude --dangerously-skip-permissions --print "$(cat "$context_file")" 2>&1 | tee "$SESSION_DIR/flow-diagram-iter-$iteration.raw.md" || {
        log_error "Flow diagram generation had issues"
      }
      rm -f "$context_file"

      # Normalize output: extract only ENDPOINT TABLE MAPPING section and mermaid block
      # This strips any explanatory prose that the LLM might have added
      normalize_diagram_output "$SESSION_DIR/flow-diagram-iter-$iteration.raw.md" "$SESSION_DIR/flow-diagram-iter-$iteration.md"

      # Verify and auto-regenerate if needed (uses checklist-based validation)
      echo ""
      start_spinner "Validating diagram (syntax, schema, coverage)..."
      local arch_index="$PROJECT_ROOT/.claude/cache/architecture/index.yaml"
      if verify_and_regenerate \
          "$SESSION_DIR/flow-diagram-iter-$iteration.md" \
          "$arch_index" \
          "$SESSION_DIR"; then
        stop_spinner ""
        log_success "Diagram passed all validation checks"
      else
        stop_spinner ""
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

    complete_step 7 "Diagrams confirmed"
    dim_path "  System Flow: $SESSION_DIR/flow-diagram.md"
    dim_path "  Suite: $SESSION_DIR/feature-diagrams.html"
  else
    log_error "Max iterations ($max_iterations) reached"
    complete_step 7 "Max iterations reached"
  fi
}

# Step 7: Sync to database
sync_to_database() {
  show_step_header 8 "Syncing to Database" "sync"

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
    complete_step 8 "Database sync complete"
  else
    complete_step 8 "Scope documents created (DB sync skipped)"
  fi
}

# =============================================================================
# Step 8: Data Schema Generation
# Generates PostgreSQL migrations and SQLAlchemy models from feature research
# =============================================================================

generate_data_schema() {
  show_step_header 9 "Generating Data Schema" "sync"

  local max_attempts=3
  local attempt=0
  local passed=false
  local accuracy_threshold=90

  # Check prerequisites
  if [ ! -f "$SESSION_DIR/refined-requirements.md" ]; then
    log_error "Missing refined-requirements.md - run earlier steps first"
    fail_step 9 "Missing prerequisites"
    return 1
  fi

  # Gather context
  log "Gathering schema context..."
  local context_file="$SESSION_DIR/.schema-context.txt"
  gather_schema_context_data "$context_file"

  while [ $attempt -lt $max_attempts ] && [ "$passed" = "false" ]; do
    attempt=$((attempt + 1))
    log "Attempt $attempt/$max_attempts..."

    # Phase 1: Generate domain model
    log "Analyzing domain model..."
    if ! generate_domain_model_file "$context_file"; then
      log_error "Domain model generation failed"
      continue
    fi

    # Phase 2: Generate migration DDL
    log "Generating PostgreSQL migration..."
    if ! generate_migration_ddl_file; then
      log_error "Migration generation failed"
      continue
    fi

    # Phase 3: Generate SQLAlchemy models
    log "Generating SQLAlchemy models..."
    if ! generate_sqlalchemy_models_file; then
      log_error "SQLAlchemy model generation failed"
      continue
    fi

    # Phase 4: Validate
    log "Validating schema quality..."
    local score
    score=$(validate_schema_files)

    # Save validation report
    save_validation_report "$score" "$attempt" "$max_attempts" "$accuracy_threshold"

    if [ "$score" -ge "$accuracy_threshold" ]; then
      passed=true
      echo -e "  ${GREEN}Score: $score% (threshold: $accuracy_threshold%)${NC}"
    else
      echo -e "  ${YELLOW}Score: $score% (below threshold: $accuracy_threshold%)${NC}"
      if [ $attempt -lt $max_attempts ]; then
        log "Regenerating with validation feedback..."
      fi
    fi
  done

  if [ "$passed" = "true" ]; then
    # Mark completion
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$SESSION_DIR/schema-complete.txt"

    complete_step 9 "Schema generated (score: $score%)"
    dim_path "  Domain Model: $SESSION_DIR/domain-model.md"
    dim_path "  Migration: $SESSION_DIR/schema-migration.sql"
    dim_path "  Models: $SESSION_DIR/schema-sqlalchemy.py"
  else
    log_error "Schema generation failed after $max_attempts attempts"
    fail_step 9 "Validation failed ($score% < $accuracy_threshold%)"
    return 1
  fi
}

# Gather context data for schema generation
gather_schema_context_data() {
  local context_file="$1"

  # Read refined requirements (strip frontmatter if present)
  local requirements=""
  if [ -f "$SESSION_DIR/refined-requirements.md" ]; then
    requirements=$(sed '1{/^---$/!q;};1,/^---$/d;1,/^---$/d' "$SESSION_DIR/refined-requirements.md" 2>/dev/null)
    [ -z "$requirements" ] && requirements=$(cat "$SESSION_DIR/refined-requirements.md" 2>/dev/null)
  fi

  # Read flow diagram for entity hints
  local flow_diagram=""
  if [ -f "$SESSION_DIR/flow-diagram.md" ]; then
    flow_diagram=$(cat "$SESSION_DIR/flow-diagram.md" 2>/dev/null | head -100)
  fi

  # Extract existing table names for FK validation
  local existing_tables="users, vendors, customers, inventory_items, cattle"
  if [ -d "backend/migrations" ]; then
    local tables_from_migrations
    tables_from_migrations=$(grep -h "CREATE TABLE" backend/migrations/*.sql 2>/dev/null | \
      sed 's/.*CREATE TABLE IF NOT EXISTS \([a-z_]*\).*/\1/' | \
      sort -u | tr '\n' ', ' | sed 's/,$//')
    [ -n "$tables_from_migrations" ] && existing_tables="$tables_from_migrations"
  fi

  # Get research highlights
  local research_entities=""
  if [ -f "$SESSION_DIR/research-output.md" ]; then
    research_entities=$(grep -i -E "entity|table|model|database|store|record|data" \
      "$SESSION_DIR/research-output.md" 2>/dev/null | head -30)
  fi

  # Write context file using printf to avoid heredoc issues
  {
    printf "## Feature Requirements\n%s\n\n" "$requirements"
    printf "## System Flow\n%s\n\n" "$flow_diagram"
    printf "## Existing Database Tables (for FK references)\n%s\n\n" "$existing_tables"
    printf "## Research Highlights\n%s\n\n" "$research_entities"
    printf "## Domain Context\nThis is a Cattle ERP system with:\n"
    printf '%s\n' "- Users (id, email, username) - authentication/authorization"
    printf '%s\n' "- Vendors (id, name, contact_email) - suppliers"
    printf '%s\n' "- Customers (id, name, contact_email) - buyers"
    printf '%s\n' "- Cattle tracking, inventory, procurement workflows"
    printf '%s\n' "- Kanban boards for order processing"
  } > "$context_file"
}

# Strip markdown code fences from a file (```lang ... ```)
strip_code_fences() {
  local file="$1"
  if [ ! -f "$file" ]; then return 1; fi
  # Remove lines that are only code fences (```sql, ```python, ```, etc.)
  sed -i '/^```[a-z]*[[:space:]]*$/d' "$file"
}

# Generate domain model using Claude
generate_domain_model_file() {
  local context_file="$1"
  local domain_model_file="$SESSION_DIR/domain-model.md"
  local prompt_file="$SESSION_DIR/.domain-prompt.txt"

  # Build prompt using printf
  {
    printf "You are a database architect analyzing feature requirements to extract domain entities.\n\n"
    printf "<context>\n"
    cat "$context_file"
    printf "</context>\n\n"
    printf "<task>\n"
    printf "Analyze the requirements and extract:\n"
    printf "1. **Entities** - Tables needed with their purpose\n"
    printf "2. **Attributes** - Columns with types and constraints\n"
    printf "3. **Relationships** - FKs with cardinality (1:1, 1:N, N:M)\n"
    printf "4. **Indexes** - Which columns need indexing and why\n"
    printf "</task>\n\n"
    printf "<output_format>\n"
    printf "# Domain Model: {Feature Name}\n\n"
    printf "## Entities\n\n"
    printf "### {EntityName}\n"
    printf -- "- **Purpose**: {brief description}\n"
    printf -- "- **Table Name**: {snake_case_plural}\n\n"
    printf "| Column | Type | Constraints | Description |\n"
    printf "|--------|------|-------------|-------------|\n"
    printf "| id | UUID | PK, DEFAULT gen_random_uuid() | Primary key |\n\n"
    printf "**Relationships:**\n"
    printf "| Related Entity | Type | FK Column | ON DELETE |\n"
    printf "</output_format>\n"
  } > "$prompt_file"

  # Call Claude
  if ! command -v claude &>/dev/null; then
    log_error "Claude CLI not available"
    return 1
  fi
  if ! claude --print --tools "" < "$prompt_file" > "$domain_model_file" 2>/dev/null; then
    log_error "Claude CLI call failed for domain model"
    return 1
  fi
  strip_code_fences "$domain_model_file"
  if [ ! -s "$domain_model_file" ]; then
    log_error "Domain model generation produced empty output"
    return 1
  fi
  return 0
}

# Generate PostgreSQL migration DDL
generate_migration_ddl_file() {
  local migration_file="$SESSION_DIR/schema-migration.sql"
  local domain_model="$SESSION_DIR/domain-model.md"
  local prompt_file="$SESSION_DIR/.migration-prompt.txt"

  # Build prompt
  {
    printf "You are a PostgreSQL database architect generating production-ready migrations.\n\n"
    printf "CONVENTIONS:\n"
    printf -- "- UUID PRIMARY KEY DEFAULT gen_random_uuid()\n"
    printf -- "- TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP\n"
    printf -- "- CREATE TABLE IF NOT EXISTS\n"
    printf -- "- CREATE INDEX IF NOT EXISTS\n"
    printf -- "- snake_case naming\n\n"
    printf "<domain_model>\n"
    cat "$domain_model" 2>/dev/null
    printf "</domain_model>\n\n"
    printf "Generate ONLY valid PostgreSQL SQL. No markdown. Start with: -- Migration\n"
  } > "$prompt_file"

  if ! command -v claude &>/dev/null; then
    log_error "Claude CLI not available"
    return 1
  fi
  if ! claude --print --tools "" < "$prompt_file" > "$migration_file" 2>/dev/null; then
    log_error "Claude CLI call failed for migration DDL"
    return 1
  fi
  strip_code_fences "$migration_file"
  if [ ! -s "$migration_file" ]; then
    log_error "Migration DDL generation produced empty output"
    return 1
  fi
  return 0
}

# Generate SQLAlchemy models
generate_sqlalchemy_models_file() {
  local model_file="$SESSION_DIR/schema-sqlalchemy.py"
  local domain_model="$SESSION_DIR/domain-model.md"
  local migration_file="$SESSION_DIR/schema-migration.sql"
  local prompt_file="$SESSION_DIR/.models-prompt.txt"

  # Build prompt
  {
    printf "Generate SQLAlchemy 2.0 models for FastAPI.\n\n"
    printf "CONVENTIONS:\n"
    printf -- "- Inherit from app.core.database.Base\n"
    printf -- "- UUID primary keys with uuid.uuid4 default\n"
    printf -- "- DateTime(timezone=True) for timestamps\n\n"
    printf "<domain_model>\n"
    cat "$domain_model" 2>/dev/null
    printf "</domain_model>\n\n"
    printf "<migration>\n"
    cat "$migration_file" 2>/dev/null
    printf "</migration>\n\n"
    printf "Output ONLY valid Python code. Start with imports.\n"
  } > "$prompt_file"

  if ! command -v claude &>/dev/null; then
    log_error "Claude CLI not available"
    return 1
  fi
  if ! claude --print --tools "" < "$prompt_file" > "$model_file" 2>/dev/null; then
    log_error "Claude CLI call failed for SQLAlchemy models"
    return 1
  fi
  strip_code_fences "$model_file"
  if [ ! -s "$model_file" ]; then
    log_error "SQLAlchemy model generation produced empty output"
    return 1
  fi
  return 0
}

# Validate schema files and return score
validate_schema_files() {
  local migration_file="$SESSION_DIR/schema-migration.sql"
  local total_checks=10
  local passed_checks=0

  # Check migration file exists and has content
  if [ -s "$migration_file" ]; then
    ((passed_checks++))

    # Check for CREATE TABLE
    grep -q "CREATE TABLE" "$migration_file" 2>/dev/null && ((passed_checks++))

    # Check for IF NOT EXISTS
    grep -q "IF NOT EXISTS" "$migration_file" 2>/dev/null && ((passed_checks++))

    # Check for UUID PRIMARY KEY
    grep -q "UUID PRIMARY KEY" "$migration_file" 2>/dev/null && ((passed_checks++))

    # Check for timestamps
    grep -q "created_at" "$migration_file" 2>/dev/null && ((passed_checks++))
    grep -q "updated_at" "$migration_file" 2>/dev/null && ((passed_checks++))

    # Check for TIMESTAMP WITH TIME ZONE
    grep -q "TIMESTAMP WITH TIME ZONE" "$migration_file" 2>/dev/null && ((passed_checks++))

    # Check for indexes
    grep -q "CREATE INDEX" "$migration_file" 2>/dev/null && ((passed_checks++))

    # Check for foreign keys
    grep -q "REFERENCES" "$migration_file" 2>/dev/null && ((passed_checks++))

    # Check for proper header
    grep -q "^-- Migration" "$migration_file" 2>/dev/null && ((passed_checks++))
  fi

  echo $((passed_checks * 100 / total_checks))
}

# Save validation report
save_validation_report() {
  local score="$1"
  local attempt="$2"
  local max_attempts="$3"
  local threshold="$4"
  local current_date
  current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local status="NEEDS REVISION"
  [ "$score" -ge "$threshold" ] && status="PASSED"

  {
    printf "# Schema Validation Report\n\n"
    printf "**Generated:** %s\n" "$current_date"
    printf "**Attempt:** %s/%s\n" "$attempt" "$max_attempts"
    printf "**Score:** %s%%\n" "$score"
    printf "**Threshold:** %s%%\n" "$threshold"
    printf "**Status:** %s\n\n" "$status"
    printf "## Files Generated\n\n"
    printf -- "- domain-model.md - Entity analysis\n"
    printf -- "- schema-migration.sql - PostgreSQL DDL\n"
    printf -- "- schema-sqlalchemy.py - Python models\n"
  } > "$SESSION_DIR/schema-validation.md"
}

# ============================================================================
# Step 10: Run Migration
# ============================================================================

# Apply generated migration SQL to PostgreSQL
run_migration() {
  show_step_header 10 "Run Migration" "sync"

  # Check prerequisites
  if [ ! -f "$SESSION_DIR/schema-migration.sql" ]; then
    log_error "Missing schema-migration.sql - run step 9 (Data Schema) first"
    fail_step 10 "Missing prerequisites (schema-migration.sql)"
    return 1
  fi

  # Database connection settings (same as generate-journeys.sh)
  local db_namespace="cattle-erp"
  local db_pod="postgresql-cattle-erp-0"
  local db_name="cattle_erp"
  local db_user="postgres"
  local db_pass="upj3RsNuqy"

  # Determine next migration number
  log "Determining next migration number..."
  local next_num="001"
  if [ -d "backend/migrations" ]; then
    local last_num
    last_num=$(ls -1 backend/migrations/[0-9]*.sql 2>/dev/null | \
      sed 's|.*/||' | sed 's/_.*//' | sort -n | tail -1 || echo "000")
    if [ -n "$last_num" ] && [ "$last_num" != "000" ]; then
      # Remove leading zeros for arithmetic, then re-pad
      last_num=$((10#$last_num))
      next_num=$(printf "%03d" $((last_num + 1)))
    fi
  fi

  # Convert session name to snake_case for migration filename
  local session_snake
  session_snake=$(echo "$SESSION_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
  local migration_file="backend/migrations/${next_num}_${session_snake}.sql"

  # Copy migration SQL
  log "Copying migration to $migration_file..."
  mkdir -p backend/migrations
  cp "$SESSION_DIR/schema-migration.sql" "$migration_file"

  # Apply migration via kubectl
  log "Applying migration to PostgreSQL..."
  local apply_output
  if apply_output=$(kubectl exec -n "$db_namespace" "$db_pod" -i -- \
    env PGPASSWORD="$db_pass" psql -U "$db_user" -d "$db_name" -f - < "$migration_file" 2>&1); then
    log "Migration applied successfully"
  else
    log_error "Migration apply returned errors (may be idempotent):"
    echo -e "  ${DIM}$apply_output${NC}" | head -5
    # Don't fail hard - IF NOT EXISTS makes re-runs safe
    log "Continuing (idempotent migrations are expected to warn on re-run)"
  fi

  # Verify tables exist by checking information_schema
  log "Verifying tables..."
  local expected_tables
  expected_tables=$(grep -oP 'CREATE TABLE(?:\s+IF NOT EXISTS)?\s+\K[a-z_]+' "$SESSION_DIR/schema-migration.sql" 2>/dev/null || true)

  local verified_count=0
  local expected_count=0
  for table in $expected_tables; do
    expected_count=$((expected_count + 1))
    local exists
    exists=$(kubectl exec -n "$db_namespace" "$db_pod" -- \
      env PGPASSWORD="$db_pass" psql -U "$db_user" -d "$db_name" -tAc \
      "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='$table'" 2>/dev/null || echo "0")
    exists=$(echo "$exists" | tr -d '[:space:]')
    if [ "$exists" = "1" ]; then
      verified_count=$((verified_count + 1))
    else
      log_error "Table '$table' not found in database"
    fi
  done

  if [ "$expected_count" -eq 0 ]; then
    log "No CREATE TABLE statements found (migration may be ALTER-only)"
    verified_count=0
    expected_count=0
  fi

  # Write marker file
  {
    echo "migration_file=$migration_file"
    echo "tables_expected=$expected_count"
    echo "tables_verified=$verified_count"
    echo "verified_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "$SESSION_DIR/migration-complete.txt"

  complete_step 10 "Migration applied ($verified_count/$expected_count tables verified)"
  dim_path "  Migration: $migration_file"
}

# ============================================================================
# Step 11: Integrate Models
# ============================================================================

# Copy SQLAlchemy models into backend and register in __init__.py
integrate_models() {
  show_step_header 11 "Integrate Models" "sync"

  # Check prerequisites
  if [ ! -f "$SESSION_DIR/schema-sqlalchemy.py" ]; then
    log_error "Missing schema-sqlalchemy.py - run step 9 (Data Schema) first"
    fail_step 11 "Missing prerequisites (schema-sqlalchemy.py)"
    return 1
  fi

  local init_file="backend/app/models/__init__.py"
  if [ ! -f "$init_file" ]; then
    log_error "Missing $init_file - backend structure not found"
    fail_step 11 "Missing $init_file"
    return 1
  fi

  # Convert session name to snake_case for model filename
  local session_snake
  session_snake=$(echo "$SESSION_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
  local model_file="backend/app/models/${session_snake}.py"

  # Copy model file
  log "Copying models to $model_file..."
  cp "$SESSION_DIR/schema-sqlalchemy.py" "$model_file"

  # Extract class names (SQLAlchemy model classes)
  log "Extracting model class names..."
  local class_names
  class_names=$(grep -oP 'class\s+\K\w+(?=\s*\()' "$model_file" 2>/dev/null || true)

  if [ -z "$class_names" ]; then
    log_error "No model classes found in $model_file"
    fail_step 11 "No model classes found"
    return 1
  fi

  local class_list=""
  local class_count=0
  for cls in $class_names; do
    class_list="${class_list:+$class_list, }$cls"
    class_count=$((class_count + 1))
  done
  log "Found $class_count classes: $class_list"

  # Add import line to __init__.py (before __all__)
  log "Registering in $init_file..."
  local import_line="from app.models.${session_snake} import ${class_list}"

  # Check if import already exists
  if grep -qF "from app.models.${session_snake} import" "$init_file" 2>/dev/null; then
    log "Import already exists in $init_file, updating..."
    # Replace existing import line
    sed -i "s|^from app\.models\.${session_snake} import.*|${import_line}|" "$init_file"
  else
    # Insert import before __all__
    sed -i "/^__all__ = \[/i\\${import_line}" "$init_file"
  fi

  # Add class names to __all__ list (before closing bracket)
  for cls in $class_names; do
    if ! grep -qF "\"$cls\"" "$init_file" 2>/dev/null; then
      # Insert before the closing ]
      sed -i "/^\]$/i\\    \"${cls}\"," "$init_file"
    fi
  done

  # Validate syntax of both files
  log "Validating Python syntax..."
  local syntax_valid=true

  if ! python3 -m py_compile "$model_file" 2>/dev/null; then
    log_error "Syntax error in $model_file"
    syntax_valid=false
  fi

  if ! python3 -m py_compile "$init_file" 2>/dev/null; then
    log_error "Syntax error in $init_file"
    syntax_valid=false
  fi

  if [ "$syntax_valid" = "false" ]; then
    fail_step 11 "Python syntax validation failed"
    return 1
  fi

  # Write marker file
  {
    echo "model_file=$model_file"
    echo "classes=$class_list"
    echo "syntax_valid=true"
    echo "verified_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "$SESSION_DIR/models-integrated.txt"

  complete_step 11 "Models integrated ($class_count classes)"
  dim_path "  Model file: $model_file"
  dim_path "  Registered in: $init_file"
}

# ============================================================================
# Step 12: API Generation
# ============================================================================

# Generate FastAPI router and Pydantic schemas using Claude CLI self-refine loop
generate_api_code() {
  show_step_header 12 "API Generation" "sync"

  # Check prerequisites
  if [ ! -f "$SESSION_DIR/schema-sqlalchemy.py" ]; then
    log_error "Missing schema-sqlalchemy.py - run step 9 first"
    fail_step 12 "Missing prerequisites (schema-sqlalchemy.py)"
    return 1
  fi

  local config_file=".claude/configs/framework-configs/fastapi.yaml"
  local accuracy_threshold=80
  local max_iterations=3

  # Read config if available
  if [ -f "$config_file" ]; then
    local cfg_threshold
    cfg_threshold=$(sed -n '/^validation:/,/^[a-z]/p' "$config_file" 2>/dev/null | grep 'threshold:' | head -1 | sed 's/.*threshold: *//')
    [ -n "$cfg_threshold" ] && accuracy_threshold="$cfg_threshold"

    local cfg_max_iter
    cfg_max_iter=$(sed -n '/^validation:/,/^[a-z]/p' "$config_file" 2>/dev/null | grep 'max_iterations:' | head -1 | sed 's/.*max_iterations: *//')
    [ -n "$cfg_max_iter" ] && max_iterations="$cfg_max_iter"
  fi

  # Convert session name to snake_case
  local session_snake
  session_snake=$(echo "$SESSION_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')

  mkdir -p "$SESSION_DIR/generated-api"
  local router_output="$SESSION_DIR/generated-api/router.py"
  local schemas_output="$SESSION_DIR/generated-api/schemas.py"

  # Gather context for prompt
  log "Gathering API generation context..."
  local context_file="$SESSION_DIR/.api-context.txt"
  {
    echo "=== REQUIREMENTS ==="
    if [ -f "$SESSION_DIR/refined-requirements.md" ]; then
      sed '1{/^---$/!q;};1,/^---$/d;1,/^---$/d' "$SESSION_DIR/refined-requirements.md" 2>/dev/null | head -80
    fi

    echo ""
    echo "=== DOMAIN MODEL ==="
    if [ -f "$SESSION_DIR/domain-model.md" ]; then
      head -100 "$SESSION_DIR/domain-model.md" 2>/dev/null
    fi

    echo ""
    echo "=== SQLALCHEMY MODELS ==="
    cat "$SESSION_DIR/schema-sqlalchemy.py" 2>/dev/null

    echo ""
    echo "=== ENDPOINT TABLE MAPPING ==="
    if [ -f "$SESSION_DIR/flow-diagram.md" ]; then
      # Extract endpoint mapping table if present
      sed -n '/ENDPOINT.*TABLE\|endpoint.*mapping\|API.*Route/I,/^$/p' "$SESSION_DIR/flow-diagram.md" 2>/dev/null | head -40
    fi

    echo ""
    echo "=== EXISTING ROUTER EXAMPLE ==="
    # Show a real router as example for style consistency
    local example_files=("inventory.py" "vendors.py")
    for ef in "${example_files[@]}"; do
      if [ -f "backend/app/api/v1/$ef" ]; then
        echo "--- $ef (first 100 lines) ---"
        head -100 "backend/app/api/v1/$ef" 2>/dev/null
        break
      fi
    done

    echo ""
    echo "=== FRAMEWORK CONFIG ==="
    if [ -f "$config_file" ]; then
      cat "$config_file" 2>/dev/null
    fi
  } > "$context_file"

  local iteration=0
  local passed=false
  local score=0

  while [ "$iteration" -lt "$max_iterations" ] && [ "$passed" = "false" ]; do
    iteration=$((iteration + 1))
    log "Generation attempt $iteration/$max_iterations..."

    # Build prompt for Claude CLI
    local prompt_file="$SESSION_DIR/.api-prompt.md"
    local feedback=""
    if [ "$iteration" -gt 1 ] && [ -f "$SESSION_DIR/.api-validation-feedback.txt" ]; then
      feedback=$(cat "$SESSION_DIR/.api-validation-feedback.txt" 2>/dev/null)
    fi

    {
      cat << 'PROMPT_HEADER'
You are generating a FastAPI router and Pydantic schemas for a cattle ERP system.

## Output Format
You MUST output EXACTLY two code blocks:

1. First block: The router file (```python ... ```)
2. Second block: The schemas file (```python ... ```)

Separate them with a line containing only: --- SCHEMAS ---

## Requirements
- Use SQLAlchemy 2.0 async patterns (select(), await db.execute())
- All handlers MUST be async def
- Use Depends(require_privilege("entity.action")) for auth
- Use Depends(get_db) for database sessions
- All UUID fields: convert with str(obj.id) in responses
- Return dicts (not Pydantic models) from handlers
- Include proper error handling with HTTPException
- Add docstrings to all handlers
- Follow the existing router patterns from the codebase examples

PROMPT_HEADER

      if [ -n "$feedback" ]; then
        echo ""
        echo "## IMPORTANT: Previous Attempt Feedback"
        echo "The previous generation scored below threshold. Fix these issues:"
        echo "$feedback"
        echo ""
      fi

      echo ""
      echo "## Context"
      echo '```'
      cat "$context_file" 2>/dev/null
      echo '```'
    } > "$prompt_file"

    # Call Claude CLI
    local claude_output="$SESSION_DIR/.api-claude-output.txt"
    log "Calling Claude CLI for API generation..."
    if ! claude -p "$(cat "$prompt_file")" --output-format text > "$claude_output" 2>/dev/null; then
      log_error "Claude CLI call failed"
      continue
    fi

    # Parse output: split at "--- SCHEMAS ---" marker
    # Extract first python code block as router
    local in_router=false
    local in_schemas=false
    local past_separator=false

    > "$router_output"
    > "$schemas_output"

    while IFS= read -r line; do
      if [[ "$line" == *"--- SCHEMAS ---"* ]]; then
        past_separator=true
        in_router=false
        continue
      fi

      if [ "$past_separator" = "false" ]; then
        # Router section
        if [[ "$line" == '```python'* ]] && [ "$in_router" = "false" ]; then
          in_router=true
          continue
        elif [[ "$line" == '```' ]] && [ "$in_router" = "true" ]; then
          in_router=false
          continue
        elif [ "$in_router" = "true" ]; then
          echo "$line" >> "$router_output"
        fi
      else
        # Schemas section
        if [[ "$line" == '```python'* ]] && [ "$in_schemas" = "false" ]; then
          in_schemas=true
          continue
        elif [[ "$line" == '```' ]] && [ "$in_schemas" = "true" ]; then
          in_schemas=false
          continue
        elif [ "$in_schemas" = "true" ]; then
          echo "$line" >> "$schemas_output"
        fi
      fi
    done < "$claude_output"

    # Fallback: if no separator found, try to split at second code block
    if [ ! -s "$schemas_output" ] && [ -s "$router_output" ]; then
      log "No separator found, attempting fallback split..."
      # Re-parse: first code block = router, second = schemas
      local block_count=0
      > "$router_output"
      > "$schemas_output"
      local current_target="$router_output"
      local in_block=false

      while IFS= read -r line; do
        if [[ "$line" == '```python'* ]] && [ "$in_block" = "false" ]; then
          ((block_count++))
          in_block=true
          if [ "$block_count" -ge 2 ]; then
            current_target="$schemas_output"
          fi
          continue
        elif [[ "$line" == '```' ]] && [ "$in_block" = "true" ]; then
          in_block=false
          continue
        elif [ "$in_block" = "true" ]; then
          echo "$line" >> "$current_target"
        fi
      done < "$claude_output"
    fi

    # Validate: check that we have content
    if [ ! -s "$router_output" ]; then
      log_error "Router output is empty"
      echo "Router output was empty - ensure you output two python code blocks" > "$SESSION_DIR/.api-validation-feedback.txt"
      continue
    fi

    # Validate generated code
    log "Validating generated API code..."
    score=0
    local total_points=0
    local feedback_lines=""
    local blocking_fail=false

    # Check 1: Syntax (20 points, blocking)
    total_points=$((total_points + 20))
    if python3 -m py_compile "$router_output" 2>/dev/null; then
      score=$((score + 20))
    else
      feedback_lines="${feedback_lines}FAIL: Router has Python syntax errors\n"
      blocking_fail=true
    fi

    if [ -s "$schemas_output" ]; then
      if ! python3 -m py_compile "$schemas_output" 2>/dev/null; then
        feedback_lines="${feedback_lines}FAIL: Schemas file has Python syntax errors\n"
      fi
    fi

    # Check 2: Router declaration (10 points)
    total_points=$((total_points + 10))
    if grep -q "router = APIRouter" "$router_output" 2>/dev/null; then
      score=$((score + 10))
    else
      feedback_lines="${feedback_lines}FAIL: Missing 'router = APIRouter()' declaration\n"
    fi

    # Check 3: Async handlers (10 points)
    total_points=$((total_points + 10))
    if grep -q "async def" "$router_output" 2>/dev/null; then
      score=$((score + 10))
    else
      feedback_lines="${feedback_lines}FAIL: No async def handlers found\n"
    fi

    # Check 4: Auth decorator (10 points)
    total_points=$((total_points + 10))
    if grep -q "require_privilege" "$router_output" 2>/dev/null; then
      score=$((score + 10))
    else
      feedback_lines="${feedback_lines}FAIL: Missing require_privilege auth decorator\n"
    fi

    # Check 5: FastAPI imports (10 points)
    total_points=$((total_points + 10))
    if grep -q "from fastapi import" "$router_output" 2>/dev/null; then
      score=$((score + 10))
    else
      feedback_lines="${feedback_lines}FAIL: Missing FastAPI imports\n"
    fi

    # Check 6: DB dependency (10 points)
    total_points=$((total_points + 10))
    if grep -q "Depends(get_db)" "$router_output" 2>/dev/null; then
      score=$((score + 10))
    else
      feedback_lines="${feedback_lines}FAIL: Missing Depends(get_db) database dependency\n"
    fi

    # Check 7: Error handling (10 points)
    total_points=$((total_points + 10))
    if grep -q "HTTPException" "$router_output" 2>/dev/null; then
      score=$((score + 10))
    else
      feedback_lines="${feedback_lines}FAIL: Missing HTTPException error handling\n"
    fi

    # Check 8: Docstrings (10 points)
    total_points=$((total_points + 10))
    if grep -q '"""' "$router_output" 2>/dev/null; then
      score=$((score + 10))
    else
      feedback_lines="${feedback_lines}FAIL: Missing docstrings on handlers\n"
    fi

    # Check 9: UUID conversion (10 points)
    total_points=$((total_points + 10))
    if grep -qP 'str\([a-z_]+\.id\)' "$router_output" 2>/dev/null; then
      score=$((score + 10))
    else
      feedback_lines="${feedback_lines}WARN: No str(obj.id) UUID conversion found\n"
    fi

    # Normalize score to percentage
    if [ "$total_points" -gt 0 ]; then
      score=$(( (score * 100) / total_points ))
    fi

    # Save feedback for next iteration
    echo -e "$feedback_lines" > "$SESSION_DIR/.api-validation-feedback.txt"

    if [ "$blocking_fail" = "true" ]; then
      echo -e "  ${YELLOW}Score: $score% (BLOCKING: syntax error)${NC}"
      continue
    fi

    if [ "$score" -ge "$accuracy_threshold" ]; then
      passed=true
      echo -e "  ${GREEN}Score: $score% (threshold: $accuracy_threshold%)${NC}"
    else
      echo -e "  ${YELLOW}Score: $score% (below threshold: $accuracy_threshold%)${NC}"
      if [ "$iteration" -lt "$max_iterations" ]; then
        log "Retrying with validation feedback..."
      fi
    fi
  done

  if [ "$passed" = "true" ]; then
    # Copy to backend locations
    local dest_router="backend/app/api/v1/${session_snake}.py"
    local dest_schemas="backend/app/schemas/${session_snake}.py"

    mkdir -p "backend/app/api/v1"
    mkdir -p "backend/app/schemas"
    cp "$router_output" "$dest_router"
    if [ -s "$schemas_output" ]; then
      cp "$schemas_output" "$dest_schemas"
    fi

    # Register router in main_complete.py
    local main_file="backend/app/main_complete.py"
    if [ -f "$main_file" ]; then
      # Check if router already registered
      if ! grep -qF "from app.api.v1 import ${session_snake}" "$main_file" 2>/dev/null; then
        log "Registering router in main_complete.py..."

        # Find the last "except ImportError" in the router registration block and insert before it
        # Use the pattern: add a new try/except block after the gorgias router block
        local registration_block
        registration_block=$(cat << REGEOF

# Try to import ${session_snake} router (generated by feature_interrogate)
try:
    from app.api.v1 import ${session_snake}
    app.include_router(${session_snake}.router, prefix="/api/v1/${session_snake}", tags=["${session_snake}"])
    logger.info("✓ ${SESSION_NAME} API router registered")
except ImportError as e:
    logger.warning(f"${SESSION_NAME} API router not loaded: {e}")
REGEOF
)
        # Insert after the last router registration block (after gorgias)
        # Find the line with "DEPENDENCY INJECTION" section header and insert before it
        sed -i "/^# ====.*DEPENDENCY INJECTION/i\\${registration_block//$'\n'/\\n}" "$main_file" 2>/dev/null || \
          log "Could not auto-register router - add manually to main_complete.py"
      else
        log "Router already registered in main_complete.py"
      fi
    fi

    # Write marker file
    {
      echo "status: passed"
      echo "router_file: $dest_router"
      echo "schemas_file: $dest_schemas"
      echo "score: $score"
      echo "iterations: $iteration"
      echo "generated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    } > "$SESSION_DIR/api-generated.txt"

    complete_step 12 "API generated (score: $score%, iterations: $iteration)"
    dim_path "  Router: $dest_router"
    dim_path "  Schemas: $dest_schemas"
  else
    log_error "API generation failed after $iteration attempts (score: $score%)"
    fail_step 12 "Validation failed ($score% < $accuracy_threshold%)"
    return 1
  fi
}

# ============================================================================
# Step 13: Journey Generation
# ============================================================================

# Generate user journeys by delegating to generate-journeys.sh
generate_journey_steps() {
  show_step_header 13 "Journey Generation" "sync"

  # Check prerequisites
  if [ ! -f "$SESSION_DIR/refined-requirements.md" ]; then
    log_error "Missing refined-requirements.md - run earlier steps first"
    fail_step 13 "Missing prerequisites (refined-requirements.md)"
    return 1
  fi

  local journey_script="${SCRIPT_DIR}/generate-journeys.sh"
  if [ ! -f "$journey_script" ]; then
    log_error "Missing generate-journeys.sh at $journey_script"
    fail_step 13 "Missing generate-journeys.sh"
    return 1
  fi

  # Run generate-journeys.sh
  # NOTE: generate-journeys.sh mixes log output with return values on stdout.
  # We ignore stdout entirely and verify results by checking output files.
  log "Delegating to generate-journeys.sh..."
  if bash "$journey_script" "$SESSION_NAME" "$SESSION_DIR" > /dev/null 2>&1; then
    log "generate-journeys.sh completed"
  else
    log "generate-journeys.sh exited with non-zero status"
    # Don't fail immediately - check if outputs were generated anyway
  fi

  # Verify outputs
  local journeys_found=false
  local journey_count=0

  if [ -f "$SESSION_DIR/journeys.json" ]; then
    journeys_found=true
    # Count journeys in JSON
    journey_count=$(python3 -c "
import json, sys
try:
    data = json.load(open('$SESSION_DIR/journeys.json'))
    if isinstance(data, list):
        print(len(data))
    elif isinstance(data, dict) and 'journeys' in data:
        print(len(data['journeys']))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
  fi

  # Also check the report
  local report_exists=false
  if [ -f "$SESSION_DIR/journey-generation-report.md" ]; then
    report_exists=true
  fi

  if [ "$journeys_found" = "true" ] && [ "$journey_count" -gt 0 ]; then
    # Write marker file (we write this, not generate-journeys.sh)
    {
      echo "journeys_file=$SESSION_DIR/journeys.json"
      echo "journey_count=$journey_count"
      echo "report_exists=$report_exists"
      echo "generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    } > "$SESSION_DIR/journeys-generated.txt"

    complete_step 13 "Journeys generated ($journey_count journeys)"
    dim_path "  Journeys: $SESSION_DIR/journeys.json"
    if [ "$report_exists" = "true" ]; then
      dim_path "  Report: $SESSION_DIR/journey-generation-report.md"
    fi
  else
    log_error "Journey generation failed - no journeys found in output"
    fail_step 13 "No journeys generated"
    return 1
  fi
}

# ============================================================================
# Step 14: Frontend Component Generation (Platform-Agnostic)
# ============================================================================

# Global frontend detection state
PLATFORM_CONFIG_FILE=""
PLATFORM_NAME=""
PLATFORM_LANGUAGE=""
STACK_BACKEND=""
STACK_FRONTEND=""
STACK_DATABASE=""
STACK_AUTH=""
STACK_INFRA=""

# Build full-stack technology profile from prior artifacts
build_stack_profile() {
  local profile_file="$SESSION_DIR/.stack-profile.txt"
  local scope_doc="$SCOPE_DIR/00_scope_document.md"
  local repo_analysis="$SESSION_DIR/repo-analysis.md"

  log "Building technology stack profile..."

  # Primary source: scope document Tech Stack table
  if [ -f "$scope_doc" ]; then
    local stack_section
    stack_section=$(sed -n '/## Tech Stack/,/^## /p' "$scope_doc" 2>/dev/null | sed '$d')
    if [ -n "$stack_section" ]; then
      STACK_BACKEND=$(echo "$stack_section" | grep -i "backend" | sed 's/.*|[[:space:]]*//' | sed 's/[[:space:]]*|.*//' | head -1)
      STACK_FRONTEND=$(echo "$stack_section" | grep -i "frontend" | sed 's/.*|[[:space:]]*//' | sed 's/[[:space:]]*|.*//' | head -1)
      STACK_DATABASE=$(echo "$stack_section" | grep -i "database\|storage" | sed 's/.*|[[:space:]]*//' | sed 's/[[:space:]]*|.*//' | head -1)
      STACK_AUTH=$(echo "$stack_section" | grep -i "auth" | sed 's/.*|[[:space:]]*//' | sed 's/[[:space:]]*|.*//' | head -1)
      STACK_INFRA=$(echo "$stack_section" | grep -i "infra\|deploy" | sed 's/.*|[[:space:]]*//' | sed 's/[[:space:]]*|.*//' | head -1)
    fi
  fi

  # Fallback: repo analysis
  if [ -z "$STACK_FRONTEND" ] && [ -f "$repo_analysis" ]; then
    STACK_FRONTEND=$(grep -i "frontend\|react\|vue\|angular\|svelte\|flutter\|swift" "$repo_analysis" 2>/dev/null | head -3 | tr '\n' ' ')
    STACK_BACKEND=$(grep -i "backend\|fastapi\|django\|express\|flask" "$repo_analysis" 2>/dev/null | head -3 | tr '\n' ' ')
  fi

  # Detect DB type from migration DDL if available
  if [ -f "$SESSION_DIR/schema-migration.sql" ]; then
    if grep -qi "gen_random_uuid\|SERIAL\|TIMESTAMP WITH TIME ZONE" "$SESSION_DIR/schema-migration.sql" 2>/dev/null; then
      [ -z "$STACK_DATABASE" ] && STACK_DATABASE="PostgreSQL"
    fi
  fi

  # Detect ORM from schema file
  local stack_orm=""
  if [ -f "$SESSION_DIR/schema-sqlalchemy.py" ]; then
    stack_orm="SQLAlchemy 2.0"
  fi

  # Write profile for prompt injection
  {
    printf "## Full-Stack Technology Profile\n\n"
    printf "| Layer | Technology |\n"
    printf "|-------|------------|\n"
    printf "| Frontend | %s |\n" "${STACK_FRONTEND:-Unknown}"
    printf "| Backend | %s |\n" "${STACK_BACKEND:-Unknown}"
    printf "| Database | %s |\n" "${STACK_DATABASE:-Unknown}"
    printf "| ORM | %s |\n" "${stack_orm:-Unknown}"
    printf "| Auth | %s |\n" "${STACK_AUTH:-Unknown}"
    printf "| Infrastructure | %s |\n" "${STACK_INFRA:-Unknown}"
  } > "$profile_file"

  log_success "Stack profile built"
}

# Detect frontend platform from available configs
detect_frontend_platform() {
  local configs_dir="$PROJECT_ROOT/.claude/configs/platform-configs"

  # Ensure configs directory exists
  if [ ! -d "$configs_dir" ]; then
    log_error "No platform configs found at .claude/configs/platform-configs/"
    log_error "Create a config file (e.g., react-mui.yaml) to enable frontend generation"
    return 1
  fi

  # Tier 1: Match STACK_FRONTEND keywords against config detection.tech_stack_keywords
  local frontend_lower
  frontend_lower=$(echo "$STACK_FRONTEND" | tr '[:upper:]' '[:lower:]')

  for config_file in "$configs_dir"/*.yaml; do
    [ -f "$config_file" ] || continue
    local keywords
    keywords=$(sed -n '/^detection:/,/^[a-z]/p' "$config_file" | grep -A 20 "tech_stack_keywords:" | grep '^ *- ' | sed 's/^ *- *//;s/"//g')
    while IFS= read -r keyword; do
      [ -z "$keyword" ] && continue
      if echo "$frontend_lower" | grep -qi "$keyword"; then
        PLATFORM_CONFIG_FILE="$config_file"
        PLATFORM_NAME=$(grep '^name:' "$config_file" | head -1 | sed 's/name: *//;s/"//g')
        PLATFORM_LANGUAGE=$(grep '^language:' "$config_file" | head -1 | sed 's/language: *//;s/"//g')
        log_success "Platform detected: $PLATFORM_NAME (from stack profile)"
        return 0
      fi
    done <<< "$keywords"
  done

  # Tier 2: Scan manifest files
  if detect_from_manifests "$configs_dir"; then
    return 0
  fi

  # Tier 3: Count file extensions
  if detect_from_files "$configs_dir"; then
    return 0
  fi

  # No match found
  local available_configs
  available_configs=$(ls "$configs_dir"/*.yaml 2>/dev/null | xargs -I{} basename {} .yaml | tr '\n' ', ' | sed 's/,$//')
  log_error "Could not detect frontend platform"
  log_error "Available configs: $available_configs"
  log_error "Ensure your project has a frontend or add a new config to .claude/configs/platform-configs/"
  return 1
}

# Helper: detect platform from manifest files (package.json, Podfile, etc.)
detect_from_manifests() {
  local configs_dir="$1"

  for config_file in "$configs_dir"/*.yaml; do
    [ -f "$config_file" ] || continue
    local manifest_section
    manifest_section=$(sed -n '/manifests:/,/^  [a-z]/p' "$config_file" 2>/dev/null)

    # Extract manifest file paths and patterns
    local manifest_files
    manifest_files=$(echo "$manifest_section" | grep 'file:' | sed 's/.*file: *//;s/"//g')
    while IFS= read -r manifest_file; do
      [ -z "$manifest_file" ] && continue
      if [ -f "$PROJECT_ROOT/$manifest_file" ]; then
        # Check if patterns match in manifest
        local patterns
        patterns=$(echo "$manifest_section" | grep -A 10 "$manifest_file" | grep '^ *- ' | grep -v 'file:' | sed 's/^ *- *//;s/"//g')
        local all_match=true
        while IFS= read -r pattern; do
          [ -z "$pattern" ] && continue
          if ! grep -q "$pattern" "$PROJECT_ROOT/$manifest_file" 2>/dev/null; then
            all_match=false
            break
          fi
        done <<< "$patterns"
        if [ "$all_match" = "true" ] && [ -n "$patterns" ]; then
          PLATFORM_CONFIG_FILE="$config_file"
          PLATFORM_NAME=$(grep '^name:' "$config_file" | head -1 | sed 's/name: *//;s/"//g')
          PLATFORM_LANGUAGE=$(grep '^language:' "$config_file" | head -1 | sed 's/language: *//;s/"//g')
          log_success "Platform detected: $PLATFORM_NAME (from manifest)"
          return 0
        fi
      fi
    done <<< "$manifest_files"
  done

  return 1
}

# Helper: detect platform from file extensions
detect_from_files() {
  local configs_dir="$1"

  for config_file in "$configs_dir"/*.yaml; do
    [ -f "$config_file" ] || continue
    local extensions
    extensions=$(sed -n '/file_extensions:/,/^  [a-z]/p' "$config_file" 2>/dev/null | grep '^ *- ' | sed 's/^ *- *//;s/"//g')
    while IFS= read -r ext; do
      [ -z "$ext" ] && continue
      local count
      count=$(find "$PROJECT_ROOT" -name "*${ext}" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l)
      if [ "$count" -gt 5 ]; then
        PLATFORM_CONFIG_FILE="$config_file"
        PLATFORM_NAME=$(grep '^name:' "$config_file" | head -1 | sed 's/name: *//;s/"//g')
        PLATFORM_LANGUAGE=$(grep '^language:' "$config_file" | head -1 | sed 's/language: *//;s/"//g')
        log_success "Platform detected: $PLATFORM_NAME (from file extensions: ${count} ${ext} files)"
        return 0
      fi
    done <<< "$extensions"
  done

  return 1
}

# Extract [NEW] component names from flow diagram
extract_new_components() {
  local flow_file="$SESSION_DIR/flow-diagram.md"
  [ ! -f "$flow_file" ] && return

  local in_frontend=false
  while IFS= read -r line; do
    if echo "$line" | grep -qi "subgraph.*frontend"; then
      in_frontend=true; continue
    fi
    if [ "$in_frontend" = "true" ] && echo "$line" | grep -q "^ *end$"; then
      in_frontend=false; continue
    fi
    if [ "$in_frontend" = "true" ] && echo "$line" | grep -q "\[NEW\]"; then
      local component=""
      # Try label pattern: OP["[NEW] OrganizationsPage"] -> OrganizationsPage
      component=$(echo "$line" | sed -n 's/.*\["\[NEW\] *\([^"]*\)"\].*/\1/p')
      # Fallback to node ID if label pattern didn't match
      if [ -z "$component" ]; then
        component=$(echo "$line" | sed 's/^[[:space:]]*//;s/\[.*//')
      fi
      # Remove spaces for valid PascalCase filename
      component=$(echo "$component" | tr -d ' ')
      [ -n "$component" ] && echo "$component"
    fi
  done < "$flow_file"
}

# Extract existing code patterns from config-specified example files
extract_existing_patterns() {
  local config_file="$1"
  local output=""

  # Extract example file paths and line counts from config
  local example_section
  example_section=$(sed -n '/^examples:/,/^[a-z]/p' "$config_file" 2>/dev/null)
  local file_paths
  file_paths=$(echo "$example_section" | grep 'path:' | sed 's/.*path: *//;s/"//g')
  local file_lines
  file_lines=$(echo "$example_section" | grep 'lines:' | sed 's/.*lines: *//;s/"//g')

  local idx=0
  while IFS= read -r fpath; do
    [ -z "$fpath" ] && continue
    local full_path="$PROJECT_ROOT/$fpath"
    local max_lines
    max_lines=$(echo "$file_lines" | sed -n "$((idx+1))p")
    [ -z "$max_lines" ] && max_lines=100

    if [ -f "$full_path" ]; then
      output+=$(printf "\n### Example: %s\n\`\`\`\n" "$fpath")
      output+=$(head -n "$max_lines" "$full_path")
      output+=$(printf "\n\`\`\`\n")
    fi
    ((idx++))
  done <<< "$file_paths"

  echo "$output"
}

# Gather all frontend generation context from prior artifacts
gather_frontend_context() {
  local context_file="$SESSION_DIR/.frontend-context.txt"
  log "Gathering full-stack context for frontend generation..."

  {
    # 1. Stack profile
    if [ -f "$SESSION_DIR/.stack-profile.txt" ]; then
      cat "$SESSION_DIR/.stack-profile.txt"
      printf "\n\n"
    fi

    # 2. Platform config (raw YAML for Claude to interpret)
    if [ -f "$PLATFORM_CONFIG_FILE" ]; then
      printf "## Platform Configuration\n\n"
      printf '```yaml\n'
      cat "$PLATFORM_CONFIG_FILE"
      printf '\n```\n\n'
    fi

    # 3. Existing code patterns (from config-specified examples)
    if [ -f "$PLATFORM_CONFIG_FILE" ]; then
      local patterns
      patterns=$(extract_existing_patterns "$PLATFORM_CONFIG_FILE")
      if [ -n "$patterns" ]; then
        printf "## Existing Code Patterns\n%s\n\n" "$patterns"
      fi
    fi

    # 4. API contract from generated router
    if [ -f "$SESSION_DIR/generated-api/router.py" ]; then
      printf "## Generated API Router (Backend Contract)\n\n"
      printf '```python\n'
      head -200 "$SESSION_DIR/generated-api/router.py"
      printf '\n```\n\n'
    fi

    # 5. Pydantic schemas (request/response shapes)
    if [ -f "$SESSION_DIR/generated-api/schemas.py" ]; then
      printf "## Generated Pydantic Schemas\n\n"
      printf '```python\n'
      head -200 "$SESSION_DIR/generated-api/schemas.py"
      printf '\n```\n\n'
    fi

    # 6. Database schema for type derivation
    if [ -f "$SESSION_DIR/schema-migration.sql" ]; then
      printf "## Database Schema (DDL)\n\n"
      printf '```sql\n'
      head -100 "$SESSION_DIR/schema-migration.sql"
      printf '\n```\n\n'
    fi

    # 7. Domain model entities
    if [ -f "$SESSION_DIR/domain-model.md" ]; then
      printf "## Domain Model\n\n"
      head -100 "$SESSION_DIR/domain-model.md"
      printf "\n\n"
    fi

    # 8. Flow diagram (component list, endpoint mapping)
    if [ -f "$SESSION_DIR/flow-diagram.md" ]; then
      printf "## Flow Diagram\n\n"
      cat "$SESSION_DIR/flow-diagram.md"
      printf "\n\n"
    fi

    # 9. User journeys
    if [ -f "$SESSION_DIR/journeys.json" ]; then
      printf "## User Journeys\n\n"
      printf '```json\n'
      cat "$SESSION_DIR/journeys.json"
      printf '\n```\n\n'
    fi

    # 10. Feature requirements
    if [ -f "$SESSION_DIR/refined-requirements.md" ]; then
      printf "## Feature Requirements\n\n"
      sed '1{/^---$/!q;};1,/^---$/d;1,/^---$/d' "$SESSION_DIR/refined-requirements.md" 2>/dev/null | head -100
      printf "\n\n"
    fi

    # 11. Domain context from step 4
    if [ -f "$SESSION_DIR/domain-context.yaml" ]; then
      printf "## Domain Context\n\n"
      printf '```yaml\n'
      head -80 "$SESSION_DIR/domain-context.yaml"
      printf '\n```\n\n'
    fi

  } > "$context_file"

  local context_lines
  context_lines=$(wc -l < "$context_file")
  log_success "Context assembled ($context_lines lines from available artifacts)"
}

# Generate TypeScript interfaces / frontend type definitions
generate_frontend_types() {
  local output_dir="$SESSION_DIR/generated-frontend/models"
  mkdir -p "$output_dir"

  local prompt_file="$SESSION_DIR/.frontend-types-prompt.txt"
  local context_file="$SESSION_DIR/.frontend-context.txt"

  # Read file extension from config
  local file_ext
  file_ext=$(grep 'file_extension:' "$PLATFORM_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*file_extension: *//;s/"//g')
  [ -z "$file_ext" ] && file_ext=".tsx"
  # Types files use .ts not .tsx
  local types_ext="${file_ext/x/}"
  [ -z "$types_ext" ] && types_ext=".ts"

  # System prompt: role-based, explains WHY output must be code
  local system_prompt="You are a TypeScript code generator. Your output is piped directly into a .ts file and must be valid code that compiles. Start with import or export statements. The output goes straight to disk with no post-processing, so any prose will cause a syntax error."

  {
    printf "<output_format>\n"
    printf "Your output is saved directly to a %s file. Start with import or export statements.\n" "$types_ext"
    printf "Even if similar code exists in the codebase, generate fresh code based on the schemas and contracts below.\n"
    printf "</output_format>\n\n"
    printf "<context>\n"
    cat "$context_file"
    printf "</context>\n\n"
    printf "<task>\n"
    printf "Generate type definitions that match the backend API contract and database schema.\n"
    printf "Map backend field types to native frontend types:\n"
    printf -- "- UUID -> string\n"
    printf -- "- TIMESTAMP -> string (ISO format)\n"
    printf -- "- BOOLEAN -> boolean\n"
    printf -- "- INTEGER/NUMERIC -> number\n"
    printf -- "- VARCHAR/TEXT -> string\n"
    printf -- "- JSONB -> Record<string, unknown>\n"
    printf -- "- Enum types -> native %s enum types or union types\n\n" "$PLATFORM_LANGUAGE"
    printf "Include interfaces for:\n"
    printf "1. Entity types (matching DB schema columns)\n"
    printf "2. Create/Update request types (omitting auto-generated fields like id, created_at)\n"
    printf "3. API response types (if different from entities)\n"
    printf "4. Enum types for any constrained fields\n"
    printf "</task>\n\n"
    printf "<reminder>\n"
    printf "Output raw TypeScript code starting with import/export. The file is saved directly to disk.\n"
    printf "</reminder>\n"
  } > "$prompt_file"

  log "Generating type definitions..."
  if command -v claude &>/dev/null; then
    local attempt
    for attempt in 1 2 3; do
      claude --dangerously-skip-permissions --print --append-system-prompt "$system_prompt" --tools "" < "$prompt_file" > "$output_dir/types${types_ext}" 2>"$SESSION_DIR/.frontend-types-stderr.txt" || true
      if [ -s "$output_dir/types${types_ext}" ]; then
        # Strip leading blank lines, then markdown code fences
        sed -i '/./,$!d' "$output_dir/types${types_ext}"
        sed -i '1{/^```/d}' "$output_dir/types${types_ext}"
        sed -i '${/^```$/d}' "$output_dir/types${types_ext}"
        # Prose detection: first non-blank line must start with code token
        local first_line
        first_line=$(grep -m1 '[^[:space:]]' "$output_dir/types${types_ext}" 2>/dev/null || echo "")
        if echo "$first_line" | grep -qE '^(import |export |//|/\*|interface |type |enum |const |class )'; then
          log_success "Type definitions generated"
          return 0
        else
          log_warn "Prose detected in types output (attempt $attempt/3), retrying..."
          rm -f "$output_dir/types${types_ext}"
        fi
      else
        log_warn "Empty output for types (attempt $attempt/3), retrying..."
      fi
    done
    log_error "Type generation failed after 3 attempts"
    return 1
  fi

  log_warn "Type generation skipped (claude CLI not available)"
  printf "// Type definitions placeholder\n// Run with claude CLI for full generation\n" > "$output_dir/types${types_ext}"
  return 0
}

# Generate API client module
generate_frontend_api_client() {
  local output_dir="$SESSION_DIR/generated-frontend/api"
  mkdir -p "$output_dir"

  local prompt_file="$SESSION_DIR/.frontend-api-prompt.txt"
  local context_file="$SESSION_DIR/.frontend-context.txt"

  local file_ext
  file_ext=$(grep 'file_extension:' "$PLATFORM_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*file_extension: *//;s/"//g')
  [ -z "$file_ext" ] && file_ext=".tsx"
  local api_ext="${file_ext/x/}"
  [ -z "$api_ext" ] && api_ext=".ts"

  # System prompt: role-based, explains WHY output must be code
  local system_prompt="You are a TypeScript code generator. Your output is piped directly into a .ts file and must be valid code that compiles. Start with import or export statements. The output goes straight to disk with no post-processing, so any prose will cause a syntax error."

  {
    printf "<output_format>\n"
    printf "Your output is saved directly to a %s file. Start with import statements.\n" "$api_ext"
    printf "Even if similar code exists in the codebase, generate fresh code based on the schemas and contracts below.\n"
    printf "</output_format>\n\n"
    printf "<context>\n"
    cat "$context_file"
    printf "</context>\n\n"
    printf "<task>\n"
    printf "Generate an API client module that:\n"
    printf "1. Matches the actual backend endpoint paths and HTTP methods from the generated API router\n"
    printf "2. Uses the project's existing API client pattern (see Existing Code Patterns above)\n"
    printf "3. Includes proper %s types for request params and response data\n" "$PLATFORM_LANGUAGE"
    printf "4. Handles the authentication mechanism described in the stack profile\n"
    printf "5. Follows the api_client_pattern from the platform config\n\n"
    printf "Each API function should:\n"
    printf -- "- Map to a specific backend endpoint\n"
    printf -- "- Accept typed parameters\n"
    printf -- "- Return typed responses\n"
    printf "</task>\n\n"
    printf "<reminder>\n"
    printf "Output raw TypeScript code starting with import/export. The file is saved directly to disk.\n"
    printf "</reminder>\n"
  } > "$prompt_file"

  log "Generating API client..."
  if command -v claude &>/dev/null; then
    local attempt
    for attempt in 1 2 3; do
      claude --dangerously-skip-permissions --print --append-system-prompt "$system_prompt" --tools "" < "$prompt_file" > "$output_dir/api${api_ext}" 2>"$SESSION_DIR/.frontend-api-stderr.txt" || true
      if [ -s "$output_dir/api${api_ext}" ]; then
        # Strip leading blank lines, then markdown code fences
        sed -i '/./,$!d' "$output_dir/api${api_ext}"
        sed -i '1{/^```/d}' "$output_dir/api${api_ext}"
        sed -i '${/^```$/d}' "$output_dir/api${api_ext}"
        # Prose detection: first non-blank line must start with code token
        local first_line
        first_line=$(grep -m1 '[^[:space:]]' "$output_dir/api${api_ext}" 2>/dev/null || echo "")
        if echo "$first_line" | grep -qE '^(import |export |//|/\*|const |async |let |var |function )'; then
          log_success "API client generated"
          return 0
        else
          log_warn "Prose detected in API client output (attempt $attempt/3), retrying..."
          rm -f "$output_dir/api${api_ext}"
        fi
      else
        log_warn "Empty output for API client (attempt $attempt/3), retrying..."
      fi
    done
    log_error "API client generation failed after 3 attempts"
    return 1
  fi

  log_warn "API client generation skipped (claude CLI not available)"
  printf "// API client placeholder\n// Run with claude CLI for full generation\n" > "$output_dir/api${api_ext}"
  return 0
}

# Generate frontend page components
generate_frontend_pages() {
  local output_dir="$SESSION_DIR/generated-frontend"
  mkdir -p "$output_dir"

  # Track which files are adopted from the existing codebase (not LLM-generated)
  : > "$SESSION_DIR/.frontend-adopted-files.txt"

  local context_file="$SESSION_DIR/.frontend-context.txt"

  local file_ext
  file_ext=$(grep 'file_extension:' "$PLATFORM_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*file_extension: *//;s/"//g')
  [ -z "$file_ext" ] && file_ext=".tsx"

  # Get component list from flow diagram
  local components
  components=$(extract_new_components)

  if [ -z "$components" ]; then
    # Fallback: derive component name from session name
    local session_pascal
    session_pascal=$(echo "$SESSION_NAME" | sed 's/-\([a-z]\)/\U\1/g;s/^\([a-z]\)/\U\1/' | sed 's/_\([a-z]\)/\U\1/g')
    components="${session_pascal}Page"
    log_warn "No [NEW] components found in flow diagram, generating: $components"
  fi

  local generated_count=0
  while IFS= read -r component; do
    [ -z "$component" ] && continue

    # Skip if already generated and valid (preserved across targeted retry)
    if [ -s "$output_dir/${component}${file_ext}" ]; then
      log "Skipping $component (already exists, passed validation)"
      ((generated_count++)) || true
      continue
    fi

    # Check if existing codebase already has this page component
    local existing_page="$PROJECT_ROOT/frontend/src/pages/${component}.tsx"
    if [ -f "$existing_page" ]; then
      cp "$existing_page" "$output_dir/${component}${file_ext}"
      echo "${component}${file_ext}" >> "$SESSION_DIR/.frontend-adopted-files.txt"
      log_success "Adopted existing: ${component}${file_ext} ($(wc -l < "$existing_page") lines)"
      ((generated_count++)) || true
      continue  # skip claude generation for this component
    fi

    local prompt_file="$SESSION_DIR/.frontend-page-${component}-prompt.txt"

    # Extract journey steps relevant to this component (if journeys.json exists)
    local journey_context=""
    if [ -f "$SESSION_DIR/journeys.json" ]; then
      journey_context=$(grep -i "$component" "$SESSION_DIR/journeys.json" 2>/dev/null | head -20 || true)
    fi

    # System prompt: role-based, explains WHY output must be code
    local system_prompt="You are a TypeScript code generator. Your output is piped directly into a .tsx file and must be valid code that compiles. Start with import statements. The output goes straight to disk with no post-processing, so any prose will cause a syntax error."

    {
      printf "<output_format>\n"
      printf "Your output is saved directly to a %s file. Start with import statements.\n" "$file_ext"
      printf "Even if similar code exists in the codebase, generate fresh code based on the schemas and contracts below.\n"
      printf "Export the component as default.\n"
      printf "</output_format>\n\n"
      printf "<context>\n"
      cat "$context_file"
      printf "</context>\n\n"
      if [ -n "$journey_context" ]; then
        printf "<journey_context>\n"
        printf "Relevant user journey steps for this component:\n%s\n" "$journey_context"
        printf "</journey_context>\n\n"
      fi
      # Include generated types if available
      if [ -f "$output_dir/models/types${file_ext/x/}" ]; then
        printf "<generated_types>\n"
        cat "$output_dir/models/types${file_ext/x/}"
        printf "\n</generated_types>\n\n"
      fi
      # Include generated API client if available
      local api_ext="${file_ext/x/}"
      if [ -f "$output_dir/api/api${api_ext}" ]; then
        printf "<generated_api_client>\n"
        cat "$output_dir/api/api${api_ext}"
        printf "\n</generated_api_client>\n\n"
      fi
      printf "<task>\n"
      printf "Generate the '%s' page component.\n\n" "$component"
      printf "Requirements:\n"
      printf -- "- Follow the platform conventions from the config\n"
      printf -- "- Match the existing code patterns from example files\n"
      printf -- "- Use the generated types and API client\n"
      printf -- "- GET endpoints → list/table views with search and filters\n"
      printf -- "- POST endpoints → create forms with validation\n"
      printf -- "- PUT/PATCH endpoints → edit forms with pre-populated data\n"
      printf -- "- DELETE endpoints → confirmation dialogs\n"
      printf -- "- Include loading, error, and empty states\n"
      printf -- "- Include CRUD operations where applicable\n"
      printf "</task>\n\n"
      printf "<reminder>\n"
      printf "Output raw TypeScript/TSX code starting with import statements. The file is saved directly to disk.\n"
      printf "</reminder>\n"
    } > "$prompt_file"

    log "Generating component: $component..."
    if command -v claude &>/dev/null; then
      claude --dangerously-skip-permissions --print --append-system-prompt "$system_prompt" --tools "" < "$prompt_file" > "$output_dir/${component}${file_ext}" 2>"$SESSION_DIR/.frontend-page-${component}-stderr.txt" || true
      if [ -s "$output_dir/${component}${file_ext}" ]; then
        # Strip leading blank lines, then markdown code fences
        sed -i '/./,$!d' "$output_dir/${component}${file_ext}"
        sed -i '1{/^```/d}' "$output_dir/${component}${file_ext}"
        sed -i '${/^```$/d}' "$output_dir/${component}${file_ext}"
        # Prose detection: first non-blank line must start with code token
        local first_code_line
        first_code_line=$(grep -m1 '[^[:space:]]' "$output_dir/${component}${file_ext}" 2>/dev/null || echo "")
        if echo "$first_code_line" | grep -qE '^(import |export |//|/\*|const |async |let |var |function |interface |type |enum |class )'; then
          log_success "Generated: ${component}${file_ext}"
          ((generated_count++)) || true
        else
          log_warn "Prose detected in ${component}${file_ext}, discarding"
          rm -f "$output_dir/${component}${file_ext}"
        fi
      else
        log_error "Failed to generate: $component"
      fi
    else
      log_warn "Skipped $component (claude CLI not available)"
      printf "// %s component placeholder\n// Run with claude CLI for full generation\n" "$component" > "$output_dir/${component}${file_ext}"
    fi
  done <<< "$components"

  log_success "Generated $generated_count page component(s)"
}

# Validate generated frontend files with two-tier per-file checks
# Tier 1: Fast structural guard (line count, code tokens, exports)
# Tier 2: TypeScript compilation via tsc (filters module-resolution noise)
validate_frontend_files() {
  local output_dir="$SESSION_DIR/generated-frontend"
  local valid_count=0
  local total_count=0
  local invalid_files=""
  local check_results=""

  # Load adopted files list (files copied from working codebase, not LLM-generated)
  local adopted_files=""
  if [ -f "$SESSION_DIR/.frontend-adopted-files.txt" ]; then
    adopted_files=$(cat "$SESSION_DIR/.frontend-adopted-files.txt")
  fi

  # Locate tsc binary for Tier 2 checks
  local tsc_bin="$PROJECT_ROOT/frontend/node_modules/.bin/tsc"
  local has_tsc=false
  if [ -x "$tsc_bin" ]; then
    has_tsc=true
  fi

  # Validate each generated file individually
  while IFS= read -r -d '' gen_file; do
    local basename_file
    basename_file=$(basename "$gen_file")
    local line_count
    line_count=$(wc -l < "$gen_file")
    ((total_count++)) || true

    # --- Tier 1: Fast structural guard ---
    local tier1_pass=true
    local tier1_reason=""

    # Check 1: File has >= 10 lines
    if [ "$line_count" -lt 10 ]; then
      tier1_pass=false
      tier1_reason="only $line_count lines (minimum 10)"
    fi

    # Check 2: First non-blank line starts with code token
    if [ "$tier1_pass" = "true" ]; then
      local first_code_line
      first_code_line=$(grep -m1 '[^[:space:]]' "$gen_file" 2>/dev/null || echo "")
      if ! echo "$first_code_line" | grep -qE '^(import |export |//|/\*|interface |type |enum |const |class )'; then
        tier1_pass=false
        tier1_reason="first line is not a code token"
      fi
    fi

    # Check 3: File contains at least one export statement
    if [ "$tier1_pass" = "true" ]; then
      if ! grep -qE '^export ' "$gen_file" 2>/dev/null; then
        tier1_pass=false
        tier1_reason="no export statement found"
      fi
    fi

    if [ "$tier1_pass" = "false" ]; then
      check_results+=$(printf "  FAIL: %s (%s)\n" "$basename_file" "$tier1_reason")
      invalid_files+="${basename_file}"$'\n'
      continue
    fi

    # --- Tier 2: TypeScript compilation check ---
    # Skip tsc for adopted files (copied from working codebase, known-good code
    # that may fail tsc in isolation due to missing ambient types like vite-env.d.ts)
    local is_adopted=false
    if echo "$adopted_files" | grep -qxF "$basename_file" 2>/dev/null; then
      is_adopted=true
    fi

    if [ "$has_tsc" = "true" ] && [ "$is_adopted" = "false" ]; then
      local tsc_errors
      # Run tsc, filter out module-resolution errors (TS2307/TS2792/TS2875)
      # which are expected since files are outside the project src/ tree
      tsc_errors=$("$tsc_bin" --noEmit --skipLibCheck --jsx react-jsx --target es2020 \
        --module esnext --moduleResolution bundler --isolatedModules \
        "$gen_file" 2>&1 | grep -v 'TS2307\|TS2792\|TS2875' | grep 'error TS' || true)

      if [ -n "$tsc_errors" ]; then
        local error_count
        error_count=$(echo "$tsc_errors" | wc -l)
        check_results+=$(printf "  FAIL: %s (%d TypeScript errors)\n" "$basename_file" "$error_count")
        invalid_files+="${basename_file}"$'\n'
        # Save error details for debugging
        echo "$tsc_errors" > "$SESSION_DIR/.frontend-tsc-${basename_file%.*}.txt"
        continue
      fi
    fi

    # File passed all checks
    local pass_label="$line_count lines"
    if [ "$is_adopted" = "true" ]; then
      pass_label="$line_count lines, adopted"
    fi
    check_results+=$(printf "  PASS: %s (%s)\n" "$basename_file" "$pass_label")
    ((valid_count++)) || true
  done < <(find "$output_dir" -maxdepth 1 -type f \( -name "*.tsx" -o -name "*.ts" \) -not -name "*.d.ts" -print0 2>/dev/null)

  # Calculate percentage: valid_files / total_files * 100
  local score=0
  if [ "$total_count" -gt 0 ]; then
    score=$((valid_count * 100 / total_count))
  fi

  # Store results as globals (not local) for report and targeted retry
  # This function must NOT be called via $() command substitution,
  # because subshells discard global variable assignments.
  FRONTEND_CHECK_RESULTS="$check_results"
  FRONTEND_VALID_FILES="$valid_count"
  FRONTEND_TOTAL_FILES="$total_count"
  FRONTEND_INVALID_FILES="$invalid_files"
  FRONTEND_SCORE="$score"
}

# Save frontend generation report
save_frontend_report() {
  local score="$1"
  local iterations="$2"
  local current_date
  current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Main generation report
  {
    printf "# Frontend Generation Report\n\n"
    printf "**Generated:** %s\n" "$current_date"
    printf "**Platform:** %s\n" "$PLATFORM_NAME"
    printf "**Language:** %s\n" "$PLATFORM_LANGUAGE"
    printf "**Config:** %s\n" "$(basename "$PLATFORM_CONFIG_FILE")"
    printf "**Iterations:** %s\n" "$iterations"
    printf "**Score:** %s%%\n\n" "$score"
    printf "## Validation Results\n\n"
    printf '```\n'
    printf "%s\n" "${FRONTEND_CHECK_RESULTS:-No checks run}"
    printf "Score: %s/%s files valid (%s%%)\n" "${FRONTEND_VALID_FILES:-0}" "${FRONTEND_TOTAL_FILES:-0}" "$score"
    printf '```\n\n'
    printf "## Files Generated\n\n"
    if [ -d "$SESSION_DIR/generated-frontend" ]; then
      find "$SESSION_DIR/generated-frontend" -type f | sort | while read -r f; do
        local relpath="${f#"$SESSION_DIR/"}"
        printf -- "- %s\n" "$relpath"
      done
    fi
  } > "$SESSION_DIR/frontend-generation-report.md"

  # Integration report (where to place files)
  local pages_dir components_dir api_file route_file
  pages_dir=$(grep 'pages_dir:' "$PLATFORM_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*pages_dir: *//;s/"//g')
  components_dir=$(grep 'components_dir:' "$PLATFORM_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*components_dir: *//;s/"//g')
  api_file=$(grep 'api_file:' "$PLATFORM_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*api_file: *//;s/"//g')
  route_file=$(grep 'route_file:' "$PLATFORM_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*route_file: *//;s/"//g')

  {
    printf "# Integration Guide\n\n"
    printf "## Generated Files → Project Locations\n\n"
    printf "| Generated File | Copy To |\n"
    printf "|---------------|---------|\n"
    if [ -d "$SESSION_DIR/generated-frontend/models" ]; then
      printf "| generated-frontend/models/* | %s |\n" "${pages_dir:-frontend/src/types}"
    fi
    if [ -d "$SESSION_DIR/generated-frontend/api" ]; then
      printf "| generated-frontend/api/* | Merge into %s |\n" "${api_file:-frontend/src/api.ts}"
    fi
    for page_file in "$SESSION_DIR/generated-frontend"/*.*; do
      [ -f "$page_file" ] || continue
      local basename_file
      basename_file=$(basename "$page_file")
      # Skip directories we already handled
      [[ "$basename_file" == *.md ]] && continue
      printf "| generated-frontend/%s | %s/%s |\n" "$basename_file" "${pages_dir:-frontend/src/pages}" "$basename_file"
    done
    printf "\n## Registration Steps\n\n"
    printf "1. Add route to %s\n" "${route_file:-your route file}"
    printf "2. Add navigation menu entry\n"
    printf "3. Register API client functions (if not auto-imported)\n"
  } > "$SESSION_DIR/generated-frontend/integration-report.md"
}

# Step 14: Frontend Types Generation
generate_frontend_types_step() {
  show_step_header 14 "Frontend Types" "gen"

  # Check prerequisites
  if [ ! -f "$SESSION_DIR/flow-diagram.md" ]; then
    log_error "Missing flow-diagram.md - run earlier steps first"
    fail_step 14 "Missing prerequisites (flow-diagram.md)"
    return 1
  fi

  # Phase 1: Build stack profile
  build_stack_profile

  # Phase 2: Detect platform
  if ! detect_frontend_platform; then
    fail_step 14 "Platform detection failed"
    return 1
  fi
  log_success "Platform detected: $PLATFORM_NAME"

  # Phase 3: Gather context
  gather_frontend_context

  # Clean stale output from previous failed runs
  rm -f "$SESSION_DIR/generated-frontend/models/types.ts"

  # Check if existing codebase already has types we can adopt
  local existing_types=""
  for f in "$PROJECT_ROOT/frontend/src/types/"*.ts; do
    [ -f "$f" ] || continue
    if grep -q "Organization\|Deal\|Invoice\|SharingRule" "$f" 2>/dev/null; then
      existing_types="$f"; break
    fi
  done

  if [ -n "$existing_types" ]; then
    mkdir -p "$SESSION_DIR/generated-frontend/models"
    cp "$existing_types" "$SESSION_DIR/generated-frontend/models/types.ts"
    log_success "Adopted existing types from $(basename "$existing_types")"
  else
    # Phase 4: Generate types
    generate_frontend_types
  fi

  local types_file="$SESSION_DIR/generated-frontend/models/types.ts"
  if [ -s "$types_file" ] && head -1 "$types_file" | grep -qE '^(import |export |//|/\*|interface |type |enum )'; then
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$SESSION_DIR/types-generated.txt"
    complete_step 14 "Types generated (platform: $PLATFORM_NAME)"
  else
    fail_step 14 "Type generation produced invalid output"
    return 1
  fi
}

# Step 15: Frontend API Client Generation
generate_frontend_api_client_step() {
  show_step_header 15 "Frontend API Client" "gen"

  # Ensure platform is detected (may be resuming)
  if [ -z "$PLATFORM_CONFIG_FILE" ]; then
    build_stack_profile
    if ! detect_frontend_platform; then
      fail_step 15 "Platform detection failed"
      return 1
    fi
  fi

  mkdir -p "$SESSION_DIR/generated-frontend"

  # Ensure context is available
  if [ ! -f "$SESSION_DIR/.frontend-context.txt" ]; then
    gather_frontend_context
  fi

  # Clean stale output from previous failed runs
  rm -f "$SESSION_DIR/generated-frontend/api/api.ts"

  # Check if existing codebase already has an API client we can adopt
  local existing_api=""
  for f in "$PROJECT_ROOT/frontend/src/"*Api.ts; do
    [ -f "$f" ] || continue
    if grep -q "organizations\|deals\|sharing" "$f" 2>/dev/null; then
      existing_api="$f"; break
    fi
  done

  if [ -n "$existing_api" ]; then
    mkdir -p "$SESSION_DIR/generated-frontend/api"
    cp "$existing_api" "$SESSION_DIR/generated-frontend/api/api.ts"
    log_success "Adopted existing API client from $(basename "$existing_api")"
  else
    generate_frontend_api_client
  fi

  local api_file="$SESSION_DIR/generated-frontend/api/api.ts"
  if [ -s "$api_file" ] && head -1 "$api_file" | grep -qE '^(import |export |//|/\*|const |async )'; then
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$SESSION_DIR/api-client-generated.txt"
    complete_step 15 "API client generated"
  else
    fail_step 15 "API client generation produced invalid output"
    return 1
  fi
}

# Step 16: Frontend Pages Generation (with validation + retry)
generate_frontend_pages_step() {
  show_step_header 16 "Frontend Pages" "gen"

  local max_iterations=5
  local iteration=0
  local passed=false
  local accuracy_threshold=95

  # Ensure platform is detected (may be resuming)
  if [ -z "$PLATFORM_CONFIG_FILE" ]; then
    build_stack_profile
    if ! detect_frontend_platform; then
      fail_step 16 "Platform detection failed"
      return 1
    fi
  fi

  # Ensure context is available
  if [ ! -f "$SESSION_DIR/.frontend-context.txt" ]; then
    gather_frontend_context
  fi

  # Clean stale page files from previous failed runs (preserve types and api dirs)
  find "$SESSION_DIR/generated-frontend" -maxdepth 1 -name "*.tsx" -delete 2>/dev/null || true
  find "$SESSION_DIR/generated-frontend" -maxdepth 1 -name "*.ts" -not -name "*.d.ts" -delete 2>/dev/null || true

  # Read threshold from config
  local config_threshold
  config_threshold=$(sed -n '/^validation:/,/^[a-z]/p' "$PLATFORM_CONFIG_FILE" 2>/dev/null | grep 'threshold:' | head -1 | sed 's/.*threshold: *//')
  [ -n "$config_threshold" ] && accuracy_threshold="$config_threshold"

  # Read max iterations from config
  local config_max_iter
  config_max_iter=$(sed -n '/^validation:/,/^[a-z]/p' "$PLATFORM_CONFIG_FILE" 2>/dev/null | grep 'max_iterations:' | head -1 | sed 's/.*max_iterations: *//')
  [ -n "$config_max_iter" ] && max_iterations="$config_max_iter"

  # Get component list
  local components
  components=$(extract_new_components)
  if [ -z "$components" ]; then
    local session_pascal
    session_pascal=$(echo "$SESSION_NAME" | sed 's/-\([a-z]\)/\U\1/g;s/^\([a-z]\)/\U\1/' | sed 's/_\([a-z]\)/\U\1/g')
    components="${session_pascal}Page"
    log_warn "No [NEW] components found in flow diagram, generating: $components"
  fi

  local total_components
  total_components=$(echo "$components" | grep -c '[^[:space:]]' || echo "0")

  # Initialize globals before loop (required by set -u)
  FRONTEND_INVALID_FILES=""
  FRONTEND_SCORE=0

  # Generate + Validate loop
  local score=0
  while [ "$iteration" -lt "$max_iterations" ] && [ "$passed" = "false" ]; do
    iteration=$((iteration + 1))
    log "Generation attempt $iteration/$max_iterations..."

    # Targeted retry: only delete files that failed validation (preserve passing files)
    # Also skip adopted files — they come from the working codebase and can't be regenerated
    local adopted_list=""
    if [ -f "$SESSION_DIR/.frontend-adopted-files.txt" ]; then
      adopted_list=$(cat "$SESSION_DIR/.frontend-adopted-files.txt")
    fi
    if [ "$iteration" -gt 1 ] && [ -n "$FRONTEND_INVALID_FILES" ]; then
      while IFS= read -r invalid_name; do
        [ -z "$invalid_name" ] && continue
        if echo "$adopted_list" | grep -qxF "$invalid_name" 2>/dev/null; then
          log_warn "Skipping adopted file: $invalid_name (not regeneratable)"
          continue
        fi
        rm -f "$SESSION_DIR/generated-frontend/$invalid_name"
        log "Removed invalid: $invalid_name"
      done <<< "$FRONTEND_INVALID_FILES"
    elif [ "$iteration" -gt 1 ]; then
      # Fallback: no invalid file list available, clean all page files
      find "$SESSION_DIR/generated-frontend" -maxdepth 1 -name "*.tsx" -delete 2>/dev/null || true
      find "$SESSION_DIR/generated-frontend" -maxdepth 1 -name "*.ts" -not -name "*.d.ts" -delete 2>/dev/null || true
      log "Cleared previous page output for retry"
    fi

    # Generate pages with progress counter
    generate_frontend_pages

    # Validate (called directly, not via $(), to preserve global variables)
    log "Validating generated code..."
    validate_frontend_files
    score="$FRONTEND_SCORE"

    if [ "$score" -ge "$accuracy_threshold" ]; then
      passed=true
      echo -e "  ${GREEN}Score: $score% (threshold: $accuracy_threshold%)${NC}"
    else
      echo -e "  ${YELLOW}Score: $score% (below threshold: $accuracy_threshold%)${NC}"
      if [ "$iteration" -lt "$max_iterations" ]; then
        log "Retrying with fresh generation..."
      fi
    fi
  done

  if [ "$passed" = "true" ]; then
    # Save reports
    save_frontend_report "$score" "$iteration"

    # Mark completion
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$SESSION_DIR/frontend-complete.txt"

    complete_step 16 "Frontend pages generated (score: $score%, ${total_components} components)"
    dim_path "  Output: $SESSION_DIR/generated-frontend/"
    dim_path "  Report: $SESSION_DIR/frontend-generation-report.md"
  else
    save_frontend_report "$score" "$iteration"
    log_error "Frontend page generation failed after $iteration attempts"
    fail_step 16 "Validation failed ($score% < $accuracy_threshold%)"
    return 1
  fi
}

# Step 17: Frontend Integration (copy files to codebase, update App.tsx)
integrate_frontend_step() {
  show_step_header 17 "Frontend Integration" "sync"

  local gen_dir="$SESSION_DIR/generated-frontend"
  local integrated_files=""
  local integration_errors=0

  if [ ! -d "$gen_dir" ]; then
    fail_step 17 "No generated-frontend directory found"
    return 1
  fi

  # 1. Copy types
  if [ -f "$gen_dir/models/types.ts" ]; then
    local types_dest="$PROJECT_ROOT/frontend/src/types"
    mkdir -p "$types_dest"
    local types_filename="${SESSION_NAME}.ts"
    # Convert hyphens/underscores for valid module name
    types_filename=$(echo "$types_filename" | sed 's/-/_/g')
    cp "$gen_dir/models/types.ts" "$types_dest/$types_filename"
    if [ -f "$types_dest/$types_filename" ]; then
      log_success "Types → frontend/src/types/$types_filename"
      integrated_files+="frontend/src/types/$types_filename\n"
    else
      log_error "Failed to copy types"
      ((integration_errors++)) || true
    fi
  fi

  # 2. Copy API client
  if [ -f "$gen_dir/api/api.ts" ]; then
    local api_dest="$PROJECT_ROOT/frontend/src"
    local api_filename="${SESSION_NAME}Api.ts"
    # Convert to camelCase for file naming
    api_filename=$(echo "$SESSION_NAME" | sed 's/-\([a-z]\)/\U\1/g;s/^\([a-z]\)/\U\1/' | sed 's/_\([a-z]\)/\U\1/g')
    api_filename="${api_filename}Api.ts"
    # Make first char lowercase for camelCase
    api_filename="$(echo "${api_filename:0:1}" | tr '[:upper:]' '[:lower:]')${api_filename:1}"
    cp "$gen_dir/api/api.ts" "$api_dest/$api_filename"
    if [ -f "$api_dest/$api_filename" ]; then
      log_success "API client → frontend/src/$api_filename"
      integrated_files+="frontend/src/$api_filename\n"
    else
      log_error "Failed to copy API client"
      ((integration_errors++)) || true
    fi
  fi

  # 3. Copy page components and integrate into App.tsx
  local app_tsx="$PROJECT_ROOT/frontend/src/App.tsx"
  local pages_dir="$PROJECT_ROOT/frontend/src/pages"
  mkdir -p "$pages_dir"

  for page_file in "$gen_dir"/*.tsx; do
    [ -f "$page_file" ] || continue
    local page_basename
    page_basename=$(basename "$page_file")
    local component_name="${page_basename%.tsx}"

    # Copy the page file
    cp "$page_file" "$pages_dir/$page_basename"
    if [ -f "$pages_dir/$page_basename" ]; then
      log_success "Page → frontend/src/pages/$page_basename"
      integrated_files+="frontend/src/pages/$page_basename\n"
    else
      log_error "Failed to copy $page_basename"
      ((integration_errors++)) || true
      continue
    fi

    # Only integrate routable pages (ending in "Page")
    if [[ "$component_name" != *Page ]]; then
      log "Skipping App.tsx integration for $component_name (sub-component)"
      continue
    fi

    # Skip if App.tsx doesn't exist
    if [ ! -f "$app_tsx" ]; then
      log_warn "App.tsx not found, skipping route integration"
      continue
    fi

    # Skip if already imported
    if grep -q "import.*$component_name" "$app_tsx" 2>/dev/null; then
      log "Import for $component_name already exists in App.tsx"
      continue
    fi

    # Derive route path from component name (OrganizationsPage → /organizations)
    local route_path
    route_path=$(echo "$component_name" | sed 's/Page$//' | sed 's/\([A-Z]\)/-\L\1/g' | sed 's/^-//')
    local nav_label
    nav_label=$(echo "$component_name" | sed 's/Page$//' | sed 's/\([A-Z]\)/ \1/g' | sed 's/^ //')

    # Add import line after existing page imports
    # Find the last page import line number
    local last_import_line
    last_import_line=$(grep -n "import.*from.*'./pages/" "$app_tsx" 2>/dev/null | tail -1 | cut -d: -f1)
    if [ -z "$last_import_line" ]; then
      last_import_line=$(grep -n "^import" "$app_tsx" 2>/dev/null | tail -1 | cut -d: -f1)
    fi
    if [ -n "$last_import_line" ]; then
      sed -i "${last_import_line}a\\import ${component_name} from './pages/${component_name}';" "$app_tsx"
      log_success "Added import for $component_name in App.tsx"
    fi

    # Add Route element before the catch-all redirect
    local redirect_line
    redirect_line=$(grep -n '<Route path="\*"' "$app_tsx" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -z "$redirect_line" ]; then
      redirect_line=$(grep -n 'Navigate.*to=' "$app_tsx" 2>/dev/null | tail -1 | cut -d: -f1)
    fi
    if [ -n "$redirect_line" ]; then
      sed -i "${redirect_line}i\\                <Route path=\"/${route_path}\" element={<${component_name} />} />" "$app_tsx"
      log_success "Added route /${route_path} for $component_name"
    fi

    # Add nav ListItem before Settings in the drawer menu
    local settings_line
    settings_line=$(grep -n 'Settings' "$app_tsx" 2>/dev/null | grep -i 'listitemtext\|ListItem' | head -1 | cut -d: -f1)
    if [ -n "$settings_line" ]; then
      # Find the parent ListItem opening tag (search backwards)
      local nav_insert_line
      nav_insert_line=$(head -n "$settings_line" "$app_tsx" | grep -n '<ListItem' | tail -1 | cut -d: -f1)
      if [ -n "$nav_insert_line" ]; then
        sed -i "${nav_insert_line}i\\                  <ListItem disablePadding>\\
                    <ListItemButton component={Link} to=\"/${route_path}\">\\
                      <ListItemIcon><ViewListIcon /></ListItemIcon>\\
                      <ListItemText primary=\"${nav_label}\" />\\
                    </ListItemButton>\\
                  </ListItem>" "$app_tsx"
        log_success "Added nav entry for $nav_label"
      fi
    fi
  done

  # Check for duplicate imports in App.tsx
  if [ -f "$app_tsx" ]; then
    local dup_imports
    dup_imports=$(grep "^import" "$app_tsx" | sort | uniq -d)
    if [ -n "$dup_imports" ]; then
      log_warn "Duplicate imports found in App.tsx (may need manual cleanup)"
    fi
  fi

  # Write marker file
  if [ "$integration_errors" -eq 0 ]; then
    {
      date -u +"%Y-%m-%dT%H:%M:%SZ"
      echo ""
      echo "Integrated files:"
      echo -e "$integrated_files"
    } > "$SESSION_DIR/frontend-integrated.txt"

    complete_step 17 "Frontend integrated into codebase"
  else
    log_error "Integration completed with $integration_errors error(s)"
    fail_step 17 "Integration had errors"
    return 1
  fi
}

# Step 18 helper: Generate build.sh when none exists
generate_build_sh() {
  log "No build.sh found — generating from project structure..."

  # Gather project context for the prompt
  local context=""
  if [ -f "$SESSION_DIR/repo-analysis.md" ]; then
    context=$(head -80 "$SESSION_DIR/repo-analysis.md")
  fi

  local dockerfiles=""
  for df in "$PROJECT_ROOT"/Dockerfile "$PROJECT_ROOT"/*/Dockerfile; do
    [ -f "$df" ] && dockerfiles+="  ${df#"$PROJECT_ROOT"/}"$'\n'
  done

  local k8s_manifests=""
  for mf in "$PROJECT_ROOT"/k8s/*.yaml "$PROJECT_ROOT"/k8s/*.yml; do
    [ -f "$mf" ] && k8s_manifests+="  ${mf#"$PROJECT_ROOT"/}"$'\n'
  done

  local prompt_file="$SESSION_DIR/.gen-build-prompt.txt"

  # Static template (no expansion)
  cat > "$prompt_file" << 'GEN_STATIC'
Generate a production build.sh script for this project.
Output ONLY the raw bash script — no markdown fences, no explanation.

Requirements:
- Use nerdctl (NOT docker) for container builds
- Use --insecure-registry flag for nerdctl push (HTTP registry)
- Configure containerd hosts.toml for plain HTTP access before pushing
- Run database migrations via kubectl exec if migration SQL files exist
- Apply all K8s manifests from k8s/ directory
- Load env vars from parent directory ../.env if it exists, fallback to ./.env
- Create k8s namespace if it doesn't exist
- Create k8s secrets from .env if needed
- Include set -eo pipefail at the top
- Make script idempotent (safe to re-run)
GEN_STATIC

  # Dynamic context (with expansion)
  cat >> "$prompt_file" << GEN_DYNAMIC

Registry: ubuntu.desmana-truck.ts.net:30500

Dockerfiles found:
${dockerfiles:-  (none found)}

K8s manifests found:
${k8s_manifests:-  (none found)}

Project analysis:
$context
GEN_DYNAMIC

  local generated
  generated=$(claude --dangerously-skip-permissions --print \
    --append-system-prompt "You are a build script generator. Output ONLY raw bash starting with #!/bin/bash. Never output prose, explanations, or markdown. Your stdout is piped directly into a .sh file." \
    -p "$(cat "$prompt_file")" 2>&1) || true

  if [ -z "$generated" ]; then
    log_error "Failed to generate build.sh — empty response from Claude"
    return 1
  fi

  # Strip leading blank lines and markdown fences, then validate
  local cleaned
  cleaned=$(echo "$generated" | sed '/./,$!d' | sed '/^```/d' | sed '/^bash$/d')
  if ! validate_bash_output "$cleaned"; then
    log_error "Generated output is not valid bash"
    return 1
  fi
  echo "$cleaned" > "$PROJECT_ROOT/build.sh"
  chmod +x "$PROJECT_ROOT/build.sh"
  log "Generated build.sh ($(wc -l < "$PROJECT_ROOT/build.sh") lines)"
}

# Validate that a string is valid bash before writing to build.sh
validate_bash_output() {
  local content="$1"
  local tmp_file="$SESSION_DIR/.build-validate.tmp"

  # Must start with shebang or set command (not prose)
  local first_line
  first_line=$(echo "$content" | head -1)
  if [[ ! "$first_line" =~ ^#!.*/bash ]] && [[ ! "$first_line" =~ ^set\ - ]]; then
    log_warn "Output doesn't start with shebang or 'set -' — likely prose, not a script"
    return 1
  fi

  # Must pass bash -n syntax check
  echo "$content" > "$tmp_file"
  if ! bash -n "$tmp_file" 2>/dev/null; then
    log_warn "Output fails bash -n syntax check — not a valid script"
    rm -f "$tmp_file"
    return 1
  fi

  rm -f "$tmp_file"
  return 0
}

# Step 18 helper: Review existing build.sh for updates needed after pipeline
review_build_sh_updates() {
  log "Reviewing build.sh for needed updates..."

  # Summarize what the pipeline generated
  local artifacts=""
  [ -f "$SESSION_DIR/schema-complete.txt" ] && artifacts+="- New database migration SQL files generated\n"
  [ -f "$SESSION_DIR/models-integrated.txt" ] && artifacts+="- New SQLAlchemy models integrated into backend\n"
  [ -f "$SESSION_DIR/api-generated.txt" ] && artifacts+="- New FastAPI router and schemas generated\n"
  [ -f "$SESSION_DIR/frontend-integrated.txt" ] && artifacts+="- New frontend pages and routes integrated into frontend/src/\n"

  if [ -z "$artifacts" ]; then
    log "No pipeline artifacts that could affect build.sh"
    return 0
  fi

  local prompt_file="$SESSION_DIR/.review-build-prompt.txt"

  cat > "$prompt_file" << REVIEW_PROMPT
Read the file $PROJECT_ROOT/build.sh using the Read tool, then determine if it needs updates for these new pipeline artifacts:
$(echo -e "$artifacts")

If build.sh already handles these generically (e.g., builds from Dockerfile, runs all migrations from a directory), output exactly: NO_CHANGES_NEEDED

If updates ARE needed, output ONLY the complete updated bash script starting with #!/bin/bash — no markdown fences, no explanation. Your output is piped directly into build.sh.
REVIEW_PROMPT

  local response
  response=$(claude --dangerously-skip-permissions --print \
    --append-system-prompt "You are a build script editor. Output ONLY raw bash or the sentinel NO_CHANGES_NEEDED. Never output prose, explanations, or markdown. Your stdout is piped directly into a .sh file." \
    --tools "Read" \
    -p "$(cat "$prompt_file")" 2>&1) || true

  if [ -z "$response" ]; then
    log_warn "Empty response from review — continuing with current build.sh"
    return 0
  fi

  if echo "$response" | grep -q "NO_CHANGES_NEEDED"; then
    log "build.sh is up to date — no changes needed"
  else
    local cleaned
    cleaned=$(echo "$response" | sed '/./,$!d' | sed '/^```/d' | sed '/^bash$/d')
    if validate_bash_output "$cleaned"; then
      cp "$PROJECT_ROOT/build.sh" "$PROJECT_ROOT/build.sh.bak"
      echo "$cleaned" > "$PROJECT_ROOT/build.sh"
      chmod +x "$PROJECT_ROOT/build.sh"
      log "Updated build.sh with pipeline changes (backup: build.sh.bak)"
    else
      log_warn "Review returned invalid bash — keeping current build.sh unchanged"
    fi
  fi
}

# Step 18 helper: Deep-research a build failure and attempt to fix build.sh
research_and_fix_build_failure() {
  local log_file="$1"
  local error_tail
  error_tail=$(tail -30 "$log_file" 2>/dev/null)

  log "Researching build failure with /dr..."

  local research_query="Verify this build.sh will correctly build Docker images with nerdctl, push to the local HTTP registry at ubuntu.desmana-truck.ts.net:30500, deploy to the local Kubernetes cluster (namespace: cattle-erp), and expose services over NodePort. The script is currently failing. Last 30 lines of output:

$error_tail

Diagnose the root cause and suggest specific fixes."

  local research_output
  research_output=$(claude --dangerously-skip-permissions --print "/dr $research_query" 2>&1) || true

  if [ -z "$research_output" ]; then
    log_warn "/dr returned empty — continuing with retries"
    return 0
  fi

  echo "$research_output" > "$SESSION_DIR/.build-failure-research.md"
  log "Research saved to .build-failure-research.md"

  # Ask Claude to apply the research findings to fix build.sh
  local fix_prompt_file="$SESSION_DIR/.fix-build-prompt.txt"

  cat > "$fix_prompt_file" << FIX_PROMPT
Read these two files using the Read tool:
1. $SESSION_DIR/.build-failure-research.md (research findings)
2. $PROJECT_ROOT/build.sh (failing build script)

Apply the research findings to fix the build script.
Output ONLY the complete fixed bash script starting with #!/bin/bash.
Your output is piped directly into build.sh — no markdown fences, no explanation.
FIX_PROMPT

  local fixed
  fixed=$(claude --dangerously-skip-permissions --print \
    --append-system-prompt "You are a build script fixer. Output ONLY raw bash. Never output prose, explanations, or markdown. Your stdout is piped directly into a .sh file." \
    --tools "Read" \
    -p "$(cat "$fix_prompt_file")" 2>&1) || true

  if [ -n "$fixed" ] && [ "$(echo "$fixed" | wc -l)" -gt 5 ]; then
    local cleaned
    cleaned=$(echo "$fixed" | sed '/./,$!d' | sed '/^```/d' | sed '/^bash$/d')
    if validate_bash_output "$cleaned"; then
      cp "$PROJECT_ROOT/build.sh" "$PROJECT_ROOT/build.sh.pre-fix"
      echo "$cleaned" > "$PROJECT_ROOT/build.sh"
      chmod +x "$PROJECT_ROOT/build.sh"
      log "Applied /dr fixes to build.sh (backup: build.sh.pre-fix)"
    else
      log_warn "/dr fix output is not valid bash — restoring from backup"
      if [ -f "$PROJECT_ROOT/build.sh.bak" ]; then
        cp "$PROJECT_ROOT/build.sh.bak" "$PROJECT_ROOT/build.sh"
        log "Restored build.sh from .bak"
      fi
    fi
  else
    log_warn "Could not apply fixes automatically — continuing with retries"
  fi
}

# Step 18: Build & Deploy
build_and_deploy_step() {
  show_step_header 18 "Build & Deploy" "deploy"

  local build_log="$SESSION_DIR/.build-deploy.log"
  local max_retries=3

  # Generate build.sh if missing, or review existing for updates
  if [ ! -x "$PROJECT_ROOT/build.sh" ]; then
    generate_build_sh || {
      fail_step 18 "Could not generate build.sh"
      return 1
    }
  else
    review_build_sh_updates
  fi

  # Run build.sh with retry loop
  local attempt=1
  while [ "$attempt" -le "$max_retries" ]; do
    log "Build attempt $attempt/$max_retries..."

    if "$PROJECT_ROOT/build.sh" > "$build_log" 2>&1; then
      date -u +"%Y-%m-%dT%H:%M:%SZ" > "$SESSION_DIR/build-deployed.txt"
      complete_step 18 "Build and deploy completed (attempt $attempt)"
      dim_path "  Log: $build_log"
      return 0
    fi

    log_error "Attempt $attempt failed"
    tail -5 "$build_log" 2>/dev/null | while IFS= read -r line; do
      log_error "  $line"
    done

    # On 2nd failure, deep-research and attempt to fix
    if [ "$attempt" -eq 1 ]; then
      research_and_fix_build_failure "$build_log"
    fi

    ((attempt++)) || true
  done

  # All retries exhausted
  log_error "build.sh failed after $max_retries attempts"
  dim_path "  Full log: $build_log"
  dim_path "  Research: $SESSION_DIR/.build-failure-research.md"
  fail_step 18 "Build and deploy failed"
  return 1
}

# ============================================================================
# Step 19: Generate Test Personas
# ============================================================================

generate_personas_step() {
  show_step_header 19 "Test Personas" "sync"

  local db_cmd="PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 --"
  local personas_json="$SESSION_DIR/personas.json"
  local personas_backup=".claude/testing/personas/${SESSION_NAME}-personas.json"
  local api_base="http://ubuntu.desmana-truck.ts.net:32080"

  # ── Phase A: Run migrations ──────────────────────────────────────────────
  local persona_table_exists
  persona_table_exists=$($db_cmd psql -U postgres -d cattle_erp -tAc \
    "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='persona');" 2>/dev/null) || true

  if [ "$persona_table_exists" != "t" ]; then
    log "Running persona migrations..."
    for mig in backend/migrations/037_persona_table.sql backend/migrations/038_test_results_table.sql; do
      if [ -f "$PROJECT_ROOT/$mig" ]; then
        $db_cmd psql -U postgres -d cattle_erp -f - < "$PROJECT_ROOT/$mig" 2>/dev/null || true
      fi
    done
    log_success "Persona tables created"
  else
    log "Persona tables already exist — skipping migrations"
  fi

  # ── Phase B: Ensure RBAC groups exist ────────────────────────────────────
  # Create persona-specific RBAC groups if they don't exist
  local group_count
  group_count=$($db_cmd psql -U postgres -d cattle_erp -tAc \
    "SELECT count(*) FROM user_groups WHERE name LIKE 'persona-%';" 2>/dev/null) || true

  if [ "${group_count:-0}" -lt 5 ]; then
    log "Creating persona RBAC groups..."
    $db_cmd psql -U postgres -d cattle_erp -c "
DO \$\$
DECLARE
  admin_id UUID;
BEGIN
  SELECT id INTO admin_id FROM users WHERE email = 'admin@cattle-erp.com' LIMIT 1;
  IF admin_id IS NULL THEN
    SELECT id INTO admin_id FROM users WHERE is_admin = true LIMIT 1;
  END IF;

  -- Create groups (idempotent via ON CONFLICT)
  INSERT INTO user_groups (name, description, is_active, created_by) VALUES
    ('persona-ranch-owners', 'Ranch owners with full admin access', true, admin_id),
    ('persona-ranch-operations', 'Ranch foremen and feedlot operators', true, admin_id),
    ('persona-ranch-hands', 'Ranch hands with limited access', true, admin_id),
    ('persona-buyers', 'Livestock buyers', true, admin_id),
    ('persona-office-staff', 'Office managers and administrators', true, admin_id),
    ('persona-read-only', 'Read-only access for external reps', true, admin_id)
  ON CONFLICT (name) DO NOTHING;
END \$\$;
" 2>/dev/null || true
    log_success "RBAC groups created"
  else
    log "Persona RBAC groups already exist — skipping"
  fi

  # ── Phase C: Confirm journeys ────────────────────────────────────────────
  local unconfirmed
  unconfirmed=$($db_cmd psql -U postgres -d cattle_erp -tAc \
    "SELECT count(*) FROM journey WHERE session_name='$SESSION_NAME' AND confirmation_status != 'confirmed';" 2>/dev/null) || true

  if [ "${unconfirmed:-0}" -gt 0 ]; then
    log "Confirming $unconfirmed journeys..."
    $db_cmd psql -U postgres -d cattle_erp -c \
      "UPDATE journey SET confirmation_status='confirmed' WHERE session_name='$SESSION_NAME';" 2>/dev/null || true
    log_success "Journeys confirmed"
  else
    log "All journeys already confirmed"
  fi

  # ── Phase D: Generate personas JSON via Claude ───────────────────────────
  if [ ! -f "$personas_json" ]; then
    log "Generating 10 cattle-industry personas via Claude..."

    # Collect journey IDs from DB or file
    local journey_ids=""
    if [ -f "$SESSION_DIR/journeys.json" ]; then
      journey_ids=$(python3 -c "
import json, sys
try:
    data = json.load(open('$SESSION_DIR/journeys.json'))
    journeys = data if isinstance(data, list) else data.get('journeys', [])
    ids = [j.get('id', j.get('journey_id', '')) for j in journeys if isinstance(j, dict)]
    print(', '.join(ids[:20]))
except:
    print('J-001, J-002, J-003')
" 2>/dev/null) || true
    fi
    [ -z "$journey_ids" ] && journey_ids="J-001, J-002, J-003"

    # Build the persona generation prompt
    local prompt_file="$SESSION_DIR/.persona-prompt.txt"
    cat > "$prompt_file" << PERSONA_PROMPT_EOF
You are a QA persona generator for a cattle ERP system called "KC Cattle Company."

Generate exactly 10 test personas as a JSON object with a "personas" array. Each persona must match this schema:

PERSONA ROLES AND RBAC:
| # | ID | Role | Group | Granted Privileges | Denied Privileges |
|---|-----|------|-------|-------------------|-------------------|
| 1 | persona-01 | Ranch Owner/Manager | persona-ranch-owners | all privileges | (none) |
| 2 | persona-02 | Ranch Foreman | persona-ranch-operations | inventory.*, vendors.*, orders.*, kanban.* | users.delete |
| 3 | persona-03 | Ranch Hand | persona-ranch-hands | inventory.view, kanban.view | inventory.delete, vendors.*, orders.edit |
| 4 | persona-04 | Livestock Buyer | persona-buyers | inventory.view, orders.*, kanban.edit | inventory.edit, vendors.delete |
| 5 | persona-05 | Feedlot Operator | persona-ranch-operations | inventory.*, orders.*, kanban.*, vendors.* | users.* |
| 6 | persona-06 | Auction House Rep | persona-read-only | inventory.view, orders.view | orders.edit, inventory.edit |
| 7 | persona-07 | Veterinarian | persona-read-only | inventory.view, reports.view | inventory.delete, orders.* |
| 8 | persona-08 | Office Manager | persona-office-staff | inventory.*, vendors.*, orders.*, reports.* | users.delete |
| 9 | persona-09 | New Hire (Edge Case) | persona-ranch-hands | inventory.view | everything else |
| 10 | persona-10 | Multi-Ranch Manager (Edge Case) | persona-ranch-owners | all privileges (multi-org) | (none) |

AVAILABLE JOURNEYS: $journey_ids

EACH PERSONA MUST HAVE:
- id: "persona-NN" format
- name: Realistic cattle-industry name
- role: From the table above
- demographics: { age (18-80), techProficiency (low/medium/high), industry: "cattle", companySize (small/medium/enterprise), devicePreference (desktop/mobile/both), accessibilityNeeds: [] }
- behavioral: { goals (1-5 items), painPoints (1-5), preferredWorkflow, patienceLevel (low/medium/high), errorTolerance (low/medium/high), commonMistakes (1-5) }
- journeys: { primary: ["J-NNN" IDs], secondary: [], frequency (daily/weekly/monthly/occasional), sessionDuration (short/medium/long) }
- testData: { email: "test+persona-NN@cattle-erp.com", password: "TestPersona!NN", profileData: { displayName: "..." } }
- feedback: { style (detailed/brief/frustrated/enthusiastic), complaintThreshold (1-10), praiseThreshold (1-10), likelyComplaints: [...], likelyPraises: [...], verbosity (minimal/moderate/verbose) }
- metadata: { userType (primary/secondary/admin/edge_case), generatedFrom: "session: $SESSION_NAME", createdAt: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" }

Output ONLY valid JSON. No markdown fences, no explanation. Start with { and end with }.
PERSONA_PROMPT_EOF

    local persona_output="$SESSION_DIR/.persona-raw-output.json"
    local claude_attempt=1
    local max_claude_attempts=3
    local generation_success=false

    while [ "$claude_attempt" -le "$max_claude_attempts" ]; do
      log "Claude generation attempt $claude_attempt/$max_claude_attempts..."

      claude --dangerously-skip-permissions --print \
        --append-system-prompt "You are a QA persona generator. Output ONLY valid JSON. No markdown, no explanation." \
        -p "$(cat "$prompt_file")" \
        > "$persona_output" 2>/dev/null || true

      # Strip leading blank lines and markdown fences
      if [ -f "$persona_output" ] && [ -s "$persona_output" ]; then
        sed -i '/./,$!d' "$persona_output"
        sed -i '/^```/d' "$persona_output"

        # Validate JSON
        if python3 -c "import json; data=json.load(open('$persona_output')); assert 'personas' in data and len(data['personas']) >= 8" 2>/dev/null; then
          cp "$persona_output" "$personas_json"
          generation_success=true
          log_success "Personas JSON generated and validated"
          break
        else
          log_error "Invalid JSON output on attempt $claude_attempt"
        fi
      else
        log_error "Empty output on attempt $claude_attempt"
      fi

      ((claude_attempt++)) || true
    done

    if [ "$generation_success" != "true" ]; then
      fail_step 19 "Failed to generate valid personas JSON after $max_claude_attempts attempts"
      return 1
    fi
  else
    log "Personas JSON already exists — skipping generation"
  fi

  # ── Phase E: Register test users via API ─────────────────────────────────
  local test_user_count
  test_user_count=$($db_cmd psql -U postgres -d cattle_erp -tAc \
    "SELECT count(*) FROM users WHERE email LIKE 'test+persona%';" 2>/dev/null) || true

  if [ "${test_user_count:-0}" -lt 10 ]; then
    log "Registering test user accounts..."

    local registered=0
    local skipped=0

    # Parse personas and register each one
    python3 -c "
import json, sys
data = json.load(open('$personas_json'))
personas = data.get('personas', data if isinstance(data, list) else [])
for p in personas:
    td = p.get('testData', {})
    email = td.get('email', '')
    password = td.get('password', '')
    name = p.get('name', 'Test User')
    parts = name.split(' ', 1)
    first = parts[0] if parts else 'Test'
    last = parts[1] if len(parts) > 1 else 'User'
    pid = p.get('id', 'unknown')
    username = pid.replace('-', '_')
    print(f'{email}|{password}|{username}|{first}|{last}|{pid}')
" 2>/dev/null | while IFS='|' read -r email password username first last pid; do
      [ -z "$email" ] && continue

      # Check if user already exists
      local exists
      exists=$($db_cmd psql -U postgres -d cattle_erp -tAc \
        "SELECT count(*) FROM users WHERE email='$email';" 2>/dev/null) || true

      if [ "${exists:-0}" -gt 0 ]; then
        ((skipped++)) || true
        continue
      fi

      # Register via API
      local reg_response
      reg_response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$api_base/api/v1/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\",\"username\":\"$username\",\"first_name\":\"$first\",\"last_name\":\"$last\"}" \
        2>/dev/null) || true

      if [ "$reg_response" = "200" ] || [ "$reg_response" = "201" ]; then
        ((registered++)) || true
      elif [ "$reg_response" = "400" ]; then
        # Already exists
        ((skipped++)) || true
      else
        log_error "Failed to register $email (HTTP $reg_response)"
      fi
    done

    log_success "Test users registered"
  else
    log "Test users already registered ($test_user_count found) — skipping"
  fi

  # ── Phase F: Assign RBAC group memberships ──────────────────────────────
  local membership_count
  membership_count=$($db_cmd psql -U postgres -d cattle_erp -tAc \
    "SELECT count(*) FROM user_group_members ugm
     JOIN users u ON u.id = ugm.user_id
     WHERE u.email LIKE 'test+persona%';" 2>/dev/null) || true

  if [ "${membership_count:-0}" -lt 10 ]; then
    log "Assigning RBAC group memberships..."
    $db_cmd psql -U postgres -d cattle_erp -c "
DO \$\$
DECLARE
  admin_id UUID;
  persona_rec RECORD;
  target_group_id UUID;
  target_user_id UUID;
  group_map TEXT[][] := ARRAY[
    ['test+persona-01@cattle-erp.com', 'persona-ranch-owners'],
    ['test+persona-02@cattle-erp.com', 'persona-ranch-operations'],
    ['test+persona-03@cattle-erp.com', 'persona-ranch-hands'],
    ['test+persona-04@cattle-erp.com', 'persona-buyers'],
    ['test+persona-05@cattle-erp.com', 'persona-ranch-operations'],
    ['test+persona-06@cattle-erp.com', 'persona-read-only'],
    ['test+persona-07@cattle-erp.com', 'persona-read-only'],
    ['test+persona-08@cattle-erp.com', 'persona-office-staff'],
    ['test+persona-09@cattle-erp.com', 'persona-ranch-hands'],
    ['test+persona-10@cattle-erp.com', 'persona-ranch-owners']
  ];
  i INTEGER;
BEGIN
  SELECT id INTO admin_id FROM users WHERE is_admin = true LIMIT 1;

  FOR i IN 1..array_length(group_map, 1) LOOP
    SELECT id INTO target_user_id FROM users WHERE email = group_map[i][1] LIMIT 1;
    SELECT id INTO target_group_id FROM user_groups WHERE name = group_map[i][2] LIMIT 1;

    IF target_user_id IS NOT NULL AND target_group_id IS NOT NULL THEN
      INSERT INTO user_group_members (user_id, group_id, assigned_by)
      VALUES (target_user_id, target_group_id, admin_id)
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END \$\$;
" 2>/dev/null || true
    log_success "RBAC group memberships assigned"
  else
    log "RBAC memberships already assigned ($membership_count found) — skipping"
  fi

  # ── Phase G: Insert personas into DB ─────────────────────────────────────
  local persona_db_count
  persona_db_count=$($db_cmd psql -U postgres -d cattle_erp -tAc \
    "SELECT count(*) FROM persona WHERE session_name='$SESSION_NAME';" 2>/dev/null) || true

  if [ "${persona_db_count:-0}" -lt 10 ]; then
    log "Inserting personas into database..."

    python3 -c "
import json, subprocess, sys

data = json.load(open('$personas_json'))
personas = data.get('personas', data if isinstance(data, list) else [])
session = '$SESSION_NAME'

values = []
for p in personas:
    pid = p.get('id', '')
    name = p.get('name', '').replace(\"'\", \"''\")
    role = p.get('role', '').replace(\"'\", \"''\")
    demo = json.dumps(p.get('demographics', {})).replace(\"'\", \"''\")
    behav = json.dumps(p.get('behavioral', {})).replace(\"'\", \"''\")
    journ = json.dumps(p.get('journeys', {})).replace(\"'\", \"''\")
    tdata = json.dumps(p.get('testData', {})).replace(\"'\", \"''\")
    fb = json.dumps(p.get('feedback', {})).replace(\"'\", \"''\")
    meta = json.dumps(p.get('metadata', {})).replace(\"'\", \"''\")
    values.append(
        f\"('{session}', '{pid}', '{name}', '{role}', '{demo}', '{behav}', '{journ}', '{tdata}', '{fb}', '{meta}')\"
    )

sql = '''INSERT INTO persona (session_name, persona_id, name, role, demographics, behavioral, journeys, test_data, feedback_preferences, metadata)
VALUES ''' + ',\n'.join(values) + '''
ON CONFLICT (session_name, persona_id) DO UPDATE SET
  name = EXCLUDED.name,
  role = EXCLUDED.role,
  demographics = EXCLUDED.demographics,
  behavioral = EXCLUDED.behavioral,
  journeys = EXCLUDED.journeys,
  test_data = EXCLUDED.test_data,
  feedback_preferences = EXCLUDED.feedback_preferences,
  metadata = EXCLUDED.metadata;'''

print(sql)
" 2>/dev/null | $db_cmd psql -U postgres -d cattle_erp 2>/dev/null || true

    log_success "Personas inserted into database"
  else
    log "Personas already in database ($persona_db_count found) — skipping"
  fi

  # ── Write backup and marker ──────────────────────────────────────────────
  mkdir -p "$(dirname "$PROJECT_ROOT/$personas_backup")" 2>/dev/null || true
  cp "$personas_json" "$PROJECT_ROOT/$personas_backup" 2>/dev/null || true

  # Final count verification
  local final_persona_count
  final_persona_count=$($db_cmd psql -U postgres -d cattle_erp -tAc \
    "SELECT count(*) FROM persona WHERE session_name='$SESSION_NAME';" 2>/dev/null) || true
  local final_user_count
  final_user_count=$($db_cmd psql -U postgres -d cattle_erp -tAc \
    "SELECT count(*) FROM users WHERE email LIKE 'test+persona%';" 2>/dev/null) || true

  # Write marker file
  {
    echo "personas_file=$personas_json"
    echo "persona_count=${final_persona_count:-0}"
    echo "test_users_registered=${final_user_count:-0}"
    echo "backup_file=$personas_backup"
    echo "generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "$SESSION_DIR/personas-generated.txt"

  complete_step 19 "Test personas generated (${final_persona_count:-0} personas, ${final_user_count:-0} test users)"
  dim_path "  Personas: $personas_json"
  dim_path "  Backup: $personas_backup"
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
  echo -e "  ${WHITE}1.${NC} Review generated API and frontend code"
  echo -e "  ${WHITE}2.${NC} Run ${CYAN}./build.sh${NC} to build and deploy"
  echo -e "  ${WHITE}3.${NC} Run ${CYAN}/pm:decompose $SESSION_NAME${NC} to create PRDs"
  echo -e "  ${WHITE}4.${NC} Query database for features/journeys"
  echo ""
}

# Main function
main() {
  # Parse arguments
  local start_from_step=""

  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --help|-h)
        show_help
        exit 0
        ;;
      --list|-l)
        list_sessions
        exit 0
        ;;
      --start-from-step)
        if [ -z "${2:-}" ]; then
          echo "Error: --start-from-step requires a step number (1-$TOTAL_STEPS)"
          exit 1
        fi
        start_from_step="$2"
        shift 2
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
        shift 2
        ;;
      "")
        # Generate default session name
        SESSION_NAME="feature-$(date +%Y%m%d-%H%M%S)"
        shift
        ;;
      *)
        SESSION_NAME="$1"
        shift
        ;;
    esac
  done

  # Default session name if not set
  if [ -z "$SESSION_NAME" ]; then
    SESSION_NAME="feature-$(date +%Y%m%d-%H%M%S)"
  fi

  # Show banner
  show_banner

  # Show keyboard hints
  echo -e "  ${DIM}[Ctrl+C ×2] exit at any time${NC}"
  echo ""

  # Initialize session
  init_session "$SESSION_NAME"

  # Handle resume mode
  if [ -n "$start_from_step" ]; then
    # Explicit step provided via --start-from-step
    RESUME_FROM_STEP="$start_from_step"
    echo -e "  ${YELLOW}Starting from Step $RESUME_FROM_STEP${NC}"
    echo ""

    # Load existing session data
    load_session_data "$SESSION_DIR"

    # Mark earlier steps as skipped
    for ((i=1; i<RESUME_FROM_STEP; i++)); do
      STEP_STATUS[$((i-1))]="skipped"
    done
  elif [ "$RESUME_MODE" = true ]; then
    RESUME_FROM_STEP=$(detect_completed_steps "$SESSION_DIR")

    if [ "$RESUME_FROM_STEP" -gt "$TOTAL_STEPS" ]; then
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
    preliminary_research
  else
    echo -e "  ${DIM}Step 3: Context Research - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 4 ]; then
    refine_requirements
  else
    echo -e "  ${DIM}Step 4: Refinement - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 5 ]; then
    research_feature
  else
    echo -e "  ${DIM}Step 5: Impl Research - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 6 ]; then
    save_summary
  else
    echo -e "  ${DIM}Step 6: Summary - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 7 ]; then
    flow_diagram_loop
  else
    echo -e "  ${DIM}Step 7: Flow Diagram - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 8 ]; then
    sync_to_database
  else
    echo -e "  ${DIM}Step 8: Database Sync - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 9 ]; then
    generate_data_schema
  else
    echo -e "  ${DIM}Step 9: Data Schema - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 10 ]; then
    run_migration
  else
    echo -e "  ${DIM}Step 10: Run Migration - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 11 ]; then
    integrate_models
  else
    echo -e "  ${DIM}Step 11: Integrate Models - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 12 ]; then
    generate_api_code
  else
    echo -e "  ${DIM}Step 12: API Generation - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 13 ]; then
    generate_journey_steps
  else
    echo -e "  ${DIM}Step 13: Journey Gen - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 14 ]; then
    generate_frontend_types_step
  else
    echo -e "  ${DIM}Step 14: Frontend Types - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 15 ]; then
    generate_frontend_api_client_step
  else
    echo -e "  ${DIM}Step 15: Frontend API - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 16 ]; then
    generate_frontend_pages_step
  else
    echo -e "  ${DIM}Step 16: Frontend Pages - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 17 ]; then
    integrate_frontend_step
  else
    echo -e "  ${DIM}Step 17: Frontend Integrate - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 18 ]; then
    build_and_deploy_step
  else
    echo -e "  ${DIM}Step 18: Build & Deploy - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 19 ]; then
    generate_personas_step
  else
    echo -e "  ${DIM}Step 19: Test Personas - skipped (already complete)${NC}"
  fi

  show_final_summary
}

# Run main with all arguments
main "$@"
