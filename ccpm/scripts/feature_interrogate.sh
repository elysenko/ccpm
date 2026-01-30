#!/bin/bash
# feature_interrogate.sh - Interactive Feature Discovery with Flow Verification
#
# An interactive shell script that guides users through feature discovery
# using Claude's research skills, culminating in a verified flow diagram.
#
# Usage:
#   ./feature_interrogate.sh [session-name]
#
# Pipeline (9 steps):
#   1. repo-research     → Understand the repository structure
#   2. user-input        → Get feature description from user
#   3. context-research  → Deep research (/dr) to understand the domain (NEW)
#   4. dr-refine         → Ask INFORMED clarifying questions (uses step 3 research)
#   5. impl-research     → Research implementation patterns
#   6. summary           → Save conversation summary
#   7. flow-diagram      → Generate and verify flow diagrams
#   8. db-sync           → Sync to database/scope documents
#   9. data-schema       → Generate data models and migrations
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
TOTAL_STEPS=9
CURRENT_STEP=0
STEP_START_TIME=0
SESSION_START_TIME=0
declare -a STEP_NAMES=("Repo Analysis" "Feature Input" "Context Research" "Refinement" "Impl Research" "Summary" "Flow Diagram" "Database Sync" "Data Schema")
declare -a STEP_STATUS=("pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending")
declare -a STEP_DURATIONS=(0 0 0 0 0 0 0 0 0)

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
    local total=8

    # Check each step's completion
    [ -f "$session_dir/repo-analysis.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/feature-input.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/refined-requirements.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/research-output.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/summary.md" ] && completed=$((completed + 1))
    [ -f "$session_dir/flow-confirmed.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/scope-synced.txt" ] && completed=$((completed + 1))
    [ -f "$session_dir/schema-complete.txt" ] && completed=$((completed + 1))

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
  if [ -f "$session_dir/schema-complete.txt" ]; then
    echo 9  # All complete (8 steps done)
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
  echo "  [C] Continue with existing progress"
  echo "  [R] Restart this step from scratch"
  echo ""
  printf "  Choice [C/r]: "
  read -r choice

  if [[ "$choice" =~ ^[Rr]$ ]]; then
    # Restart: delete existing files
    for f in "${existing_files[@]}"; do
      rm -f "$f"
    done
    echo -e "  ${DIM}Cleared previous progress${NC}"
    return 1  # Signal: restart
  else
    echo -e "  ${GREEN}Continuing with existing progress${NC}"
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
    ((attempt++))
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
    printf "- Users (id, email, username) - authentication/authorization\n"
    printf "- Vendors (id, name, contact_email) - suppliers\n"
    printf "- Customers (id, name, contact_email) - buyers\n"
    printf "- Cattle tracking, inventory, procurement workflows\n"
    printf "- Kanban boards for order processing\n"
  } > "$context_file"
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
    printf "- **Purpose**: {brief description}\n"
    printf "- **Table Name**: {snake_case_plural}\n\n"
    printf "| Column | Type | Constraints | Description |\n"
    printf "|--------|------|-------------|-------------|\n"
    printf "| id | UUID | PK, DEFAULT gen_random_uuid() | Primary key |\n\n"
    printf "**Relationships:**\n"
    printf "| Related Entity | Type | FK Column | ON DELETE |\n"
    printf "</output_format>\n"
  } > "$prompt_file"

  # Call Claude
  if command -v claude &>/dev/null; then
    claude --dangerously-skip-permissions --print < "$prompt_file" > "$domain_model_file" 2>/dev/null
    [ -s "$domain_model_file" ] && return 0
  fi

  # Fallback: create placeholder
  printf "# Domain Model\n\nGeneration pending - run with claude CLI available.\n" > "$domain_model_file"
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
    printf "- UUID PRIMARY KEY DEFAULT gen_random_uuid()\n"
    printf "- TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP\n"
    printf "- CREATE TABLE IF NOT EXISTS\n"
    printf "- CREATE INDEX IF NOT EXISTS\n"
    printf "- snake_case naming\n\n"
    printf "<domain_model>\n"
    cat "$domain_model" 2>/dev/null
    printf "</domain_model>\n\n"
    printf "Generate ONLY valid PostgreSQL SQL. No markdown. Start with: -- Migration\n"
  } > "$prompt_file"

  if command -v claude &>/dev/null; then
    claude --dangerously-skip-permissions --print < "$prompt_file" > "$migration_file" 2>/dev/null
    [ -s "$migration_file" ] && return 0
  fi

  # Fallback placeholder
  printf "-- Migration: placeholder\n-- Run with claude CLI for full generation\n" > "$migration_file"
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
    printf "- Inherit from app.core.database.Base\n"
    printf "- UUID primary keys with uuid.uuid4 default\n"
    printf "- DateTime(timezone=True) for timestamps\n\n"
    printf "<domain_model>\n"
    cat "$domain_model" 2>/dev/null
    printf "</domain_model>\n\n"
    printf "<migration>\n"
    cat "$migration_file" 2>/dev/null
    printf "</migration>\n\n"
    printf "Output ONLY valid Python code. Start with imports.\n"
  } > "$prompt_file"

  if command -v claude &>/dev/null; then
    claude --dangerously-skip-permissions --print < "$prompt_file" > "$model_file" 2>/dev/null
    [ -s "$model_file" ] && return 0
  fi

  # Fallback placeholder
  printf "# SQLAlchemy models placeholder\n# Run with claude CLI for full generation\n" > "$model_file"
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
    printf "- domain-model.md - Entity analysis\n"
    printf "- schema-migration.sql - PostgreSQL DDL\n"
    printf "- schema-sqlalchemy.py - Python models\n"
  } > "$SESSION_DIR/schema-validation.md"
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
          echo "Error: --start-from-step requires a step number (1-9)"
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

    if [ "$RESUME_FROM_STEP" -ge 9 ]; then
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

  show_final_summary
}

# Run main with all arguments
main "$@"
