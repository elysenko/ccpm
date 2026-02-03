#!/bin/bash
# implement.sh - Autonomous Recursive Implementation Pipeline
#
# Implements the full /ar:implement workflow from implement.md:
#   Phase 0:   Initialize Session
#   Phase 0.5: Interrogation (required)
#   Phase 1:   Research & Gap Analysis
#   Phase 2:   Recursive Decomposition
#   Phase 3:   PRD Generation
#   Phase 4:   Integration (batch-process)
#
# Usage:
#   ./implement.sh [feature-description]
#   ./implement.sh --resume <session-name>
#
# Output:
#   .claude/ar/{session}/      - Context files (context.md, progress.md, tree.md)
#   .claude/prds/{session}-*.md - Generated PRDs

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Source helper scripts
source "${SCRIPT_DIR}/ar-context.sh"
source "${SCRIPT_DIR}/ar-implement.sh"

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

# Step tracking
TOTAL_STEPS=6
CURRENT_STEP=0
STEP_START_TIME=0
SESSION_START_TIME=0
declare -a STEP_NAMES=("Initialize" "Interrogate" "Research & Gaps" "Decompose" "Generate PRDs" "Batch Process")
declare -a STEP_STATUS=("pending" "pending" "pending" "pending" "pending" "pending")
declare -a STEP_DURATIONS=(0 0 0 0 0 0)

# Session state
SESSION_NAME=""
SESSION_DIR=""
SESSION_ID=""
FEATURE_DESCRIPTION=""
REFINED_DESCRIPTION=""
RESUME_MODE=false
RESUME_FROM_STEP=1

# Spinner characters
readonly SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPINNER_PID=""

# =============================================================================
# Visual Helpers
# =============================================================================

start_spinner() {
  local message="${1:-Working...}"
  local delay=0.1
  local i=0
  local len=${#SPINNER_CHARS}
  tput civis 2>/dev/null || true
  while true; do
    local char="${SPINNER_CHARS:$i:1}"
    printf "\r${CYAN}%s${NC} %s" "$char" "$message"
    i=$(( (i + 1) % len ))
    sleep "$delay"
  done &
  SPINNER_PID=$!
}

stop_spinner() {
  local message="${1:-Done}"
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi
  tput cnorm 2>/dev/null || true
  printf "\r%-80s\r" " "
  if [[ -n "$message" ]]; then
    echo -e "${GREEN}✓${NC} $message"
  fi
}

cleanup_spinner() {
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  tput cnorm 2>/dev/null || true
}

trap cleanup_spinner EXIT TERM

log() {
  echo -e "${DIM}[$SESSION_NAME]${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*"
}

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

show_banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  cat << 'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║   ██╗███╗   ███╗██████╗ ██╗     ███████╗███╗   ███╗       ║
  ║   ██║████╗ ████║██╔══██╗██║     ██╔════╝████╗ ████║       ║
  ║   ██║██╔████╔██║██████╔╝██║     █████╗  ██╔████╔██║       ║
  ║   ██║██║╚██╔╝██║██╔═══╝ ██║     ██╔══╝  ██║╚██╔╝██║       ║
  ║   ██║██║ ╚═╝ ██║██║     ███████╗███████╗██║ ╚═╝ ██║       ║
  ║   ╚═╝╚═╝     ╚═╝╚═╝     ╚══════╝╚══════╝╚═╝     ╚═╝       ║
  ║              AUTONOMOUS RECURSIVE IMPLEMENTATION          ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
}

show_step_header() {
  local step_num=$1
  local step_title="$2"
  local step_type="${3:-research}"

  CURRENT_STEP=$step_num
  STEP_START_TIME=$(date +%s)
  STEP_STATUS[$((step_num-1))]="in_progress"

  local color="$CYAN"
  local icon="🔍"
  case "$step_type" in
    input)    color="$MAGENTA"; icon="📝" ;;
    research) color="$CYAN";    icon="🔬" ;;
    sync)     color="$GREEN";   icon="💾" ;;
    generate) color="$BLUE";    icon="📄" ;;
  esac

  echo ""
  echo -e "${DIM}────────────────────────────────────────────────────────────${NC}"
  echo -e "${color}${BOLD}  $icon  Step [$step_num/$TOTAL_STEPS] $step_title${NC}"
  echo -e "${DIM}────────────────────────────────────────────────────────────${NC}"
  echo ""
}

complete_step() {
  local step_num=$1
  local message="${2:-Complete}"

  local end_time=$(date +%s)
  local duration=$((end_time - STEP_START_TIME))
  STEP_DURATIONS[$((step_num-1))]=$duration
  STEP_STATUS[$((step_num-1))]="complete"

  echo -e "${GREEN}✓${NC} $message ${DIM}($(format_duration $duration))${NC}"
}

fail_step() {
  local step_num=$1
  local message="${2:-Failed}"

  STEP_STATUS[$((step_num-1))]="failed"
  echo -e "${RED}✗${NC} $message"
}

show_input_mode() {
  local prompt_text="${1:-Enter your response}"
  echo ""
  echo -e "${MAGENTA}${BOLD}  📝 INPUT MODE${NC}"
  echo -e "${DIM}  $prompt_text${NC}"
  echo -e "${DIM}  [Enter] submit line • [Empty line] finish • [Ctrl+C ×2] exit${NC}"
  echo ""
}

input_prompt() {
  echo -ne "${MAGENTA}▸${NC} "
}

dim_path() {
  echo -e "  ${DIM}$1${NC}"
}

show_progress_summary() {
  echo ""
  echo -e "${DIM}┌──────────────────────────────────────────────────────────┐${NC}"
  echo -e "${DIM}│${NC}  ${BOLD}Progress${NC}                                                ${DIM}│${NC}"
  echo -e "${DIM}├──────────────────────────────────────────────────────────┤${NC}"

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
      failed)
        status_icon="✗"
        status_color="$RED"
        ;;
    esac

    printf "${DIM}│${NC}  ${status_color}%s${NC} %-25s%s%*s${DIM}│${NC}\n" \
      "$status_icon" "${STEP_NAMES[$i]}" "$duration_str" $((30 - ${#duration_str})) ""
  done

  echo -e "${DIM}└──────────────────────────────────────────────────────────┘${NC}"
}

# =============================================================================
# Phase 0: Initialize Session
# =============================================================================

init_session() {
  local feature="${1:-}"

  # Generate session name from feature or timestamp
  if [ -n "$feature" ]; then
    SESSION_NAME=$(echo "$feature" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | head -c 50)
    [ -z "$SESSION_NAME" ] && SESSION_NAME="implement-$(date +%Y%m%d-%H%M%S)"
  else
    SESSION_NAME="implement-$(date +%Y%m%d-%H%M%S)"
  fi

  SESSION_DIR="${PROJECT_ROOT}/.claude/ar/${SESSION_NAME}"
  FEATURE_DESCRIPTION="$feature"

  log "Initializing session: $SESSION_NAME"

  # Check schema exists
  if ! ar_check_schema; then
    log_error "Database schema missing. Run: .claude/ccpm/ccpm/scripts/create-decomposition-schema.sh"
    exit 1
  fi

  # Initialize context files
  ar_init_context_dir "$SESSION_NAME" "$FEATURE_DESCRIPTION"

  # Create database session
  SESSION_ID=$(ar_create_session "$SESSION_NAME" "$FEATURE_DESCRIPTION")
  if [ -z "$SESSION_ID" ]; then
    log_error "Failed to create database session"
    exit 1
  fi

  # Ensure PRD directory exists
  mkdir -p "${PROJECT_ROOT}/.claude/prds"

  log_success "Session initialized: $SESSION_NAME (ID: $SESSION_ID)"
}

# =============================================================================
# Phase 0.5: Interrogation
# =============================================================================

interrogation_phase() {
  show_step_header 2 "Interrogation" "input"

  log "Collecting implementation-critical information..."

  # Check if we should skip interrogation
  local word_count=0
  if [ -n "$FEATURE_DESCRIPTION" ]; then
    word_count=$(echo "$FEATURE_DESCRIPTION" | wc -w)
  fi

  # If description is detailed enough (>200 words with clear specs), skip
  if [ "$word_count" -gt 200 ]; then
    local has_specs=false
    if echo "$FEATURE_DESCRIPTION" | grep -qiE "(input|output|endpoint|database|table|api|crud)"; then
      has_specs=true
    fi
    if [ "$has_specs" = true ]; then
      log "Detailed specifications found ($word_count words) - skipping interrogation"
      REFINED_DESCRIPTION="$FEATURE_DESCRIPTION"
      ar_write_context "$SESSION_NAME" "specification" "$FEATURE_DESCRIPTION"
      ar_write_progress "$SESSION_NAME" "in_progress" "research" "" "" "0"
      complete_step 2 "Skipped (detailed spec provided)"
      return
    fi
  fi

  # If no feature description yet, get it
  if [ -z "$FEATURE_DESCRIPTION" ]; then
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

  # Interactive interrogation using Claude
  if ! command -v claude &> /dev/null; then
    log_warn "Claude CLI not found - using feature description as-is"
    REFINED_DESCRIPTION="$FEATURE_DESCRIPTION"
    ar_write_context "$SESSION_NAME" "specification" "$FEATURE_DESCRIPTION"
    ar_write_progress "$SESSION_NAME" "in_progress" "research" "" "" "0"
    complete_step 2 "Skipped (no Claude CLI)"
    return
  fi

  # 4-Phase Question Hierarchy interrogation
  local conversation_round=0
  local max_rounds=15
  local conversation_history=""
  local confidence=0

  # Dialogue state slots
  local slots_filled=0
  declare -A slots=(
    [goal]=""
    [scope]=""
    [input_spec]=""
    [output_spec]=""
    [happy_path]=""
    [error_handling]=""
    [constraints]=""
  )

  # =========================================================================
  # Pre-interrogation research - gather codebase context (cached)
  # =========================================================================
  local cache_file="${PROJECT_ROOT}/.claude/cache/codebase-context.txt"
  local cache_age_limit=3600  # 1 hour in seconds
  local pre_research=""

  # Check if cache exists and is fresh
  if [ -f "$cache_file" ]; then
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [ "$cache_age" -lt "$cache_age_limit" ]; then
      echo -e "  ${DIM}Using cached codebase context (${cache_age}s old)${NC}"
      pre_research=$(cat "$cache_file")
    fi
  fi

  # Generate if no cache or stale
  if [ -z "$pre_research" ]; then
    echo ""
    echo -e "  ${DIM}Gathering codebase context (caching for 1hr)...${NC}"

    start_spinner "Analyzing codebase patterns..."

    # Full codebase scan - find files with classes/functions
    local existing_patterns=""
    existing_patterns=$(grep -r -l --include="*.py" --include="*.tsx" --include="*.ts" \
      -E "(class|def|function|const)" backend/app frontend/src 2>/dev/null | head -20 | tr '\n' ', ')

    # Check database models
    local db_models=""
    db_models=$(ls -1 backend/app/models/*.py 2>/dev/null | xargs -I {} basename {} .py | tr '\n' ', ')

    # Check API endpoints
    local api_endpoints=""
    api_endpoints=$(ls -1 backend/app/api/v1/*.py 2>/dev/null | xargs -I {} basename {} .py | tr '\n' ', ')

    # Check frontend pages
    local frontend_pages=""
    frontend_pages=$(ls -1 frontend/src/pages/*.tsx 2>/dev/null | xargs -I {} basename {} .tsx | tr '\n' ', ')

    pre_research="## Codebase Context (Pre-scanned)
**Database Models:** ${db_models:-none found}
**API Endpoints:** ${api_endpoints:-none found}
**Frontend Pages:** ${frontend_pages:-none found}
**Key Source Files:** ${existing_patterns:-none found}

This context helps inform questions about integration points and existing patterns."

    stop_spinner "Codebase context gathered"

    # Save to cache
    mkdir -p "${PROJECT_ROOT}/.claude/cache"
    echo "$pre_research" > "$cache_file"
  fi

  # Save to session context
  ar_write_context "$SESSION_NAME" "codebase" "$pre_research"

  echo ""
  echo -e "  ${DIM}Starting 4-phase interrogation...${NC}"
  echo -e "  ${DIM}Phases: Context → Behavior → Edge Cases → Verification${NC}"
  echo ""

  local user_confirmed_proceed=false
  local skip_increment=false

  while [ "$conversation_round" -lt "$max_rounds" ] && [ "$user_confirmed_proceed" = false ]; do
    # Increment round counter unless we just did an undo
    if [ "$skip_increment" = false ]; then
      conversation_round=$((conversation_round + 1))
    fi
    skip_increment=false

    echo -e "  ${YELLOW}Round $conversation_round${NC} ${DIM}('proceed' = continue, Ctrl+R = undo, empty = done)${NC}"
    echo ""

    # Build context for this round
    local phase="context"
    if [ "$conversation_round" -gt 2 ]; then phase="behavior"; fi
    if [ "$conversation_round" -gt 5 ]; then phase="edge_cases"; fi
    if [ "$conversation_round" -gt 8 ]; then phase="verification"; fi

    # Build XML context prompt per implement.md spec
    local context_prompt
    if [ -z "$conversation_history" ]; then
      # Initial interrogation prompt - uses LLM prompt engineering best practices
      context_prompt="<role>
You are a senior requirements analyst with expertise in extracting precise
specifications from stakeholders. You excel at asking targeted questions that
uncover hidden assumptions, edge cases, and constraints that developers often
miss until implementation.
</role>

<context>
  <session>$SESSION_NAME</session>
  <feature>$FEATURE_DESCRIPTION</feature>
  <user_role>developer</user_role>
  <context_file>.claude/ar/$SESSION_NAME/context.md</context_file>
  <current_phase>$phase</current_phase>
</context>

<codebase_context>
$pre_research
</codebase_context>

<task>
Extract a complete feature specification by filling dialogue state slots through
targeted questioning. Each slot captures a critical aspect that prevents
rework during implementation.

Use the codebase context above to ask informed questions about integration
with existing models, endpoints, and pages.
</task>

<instructions>
SYNTHESIZE a complete specification from available artifacts first. Only ask
questions when you genuinely cannot derive the answer from codebase patterns,
domain context, or prior conversation.

Priority order:
1. **SYNTHESIZE** - Analyze codebase patterns to fill slots with concrete values
2. **CLARIFY** - Ask ONE targeted question only when genuinely blocked
3. **CONFIRM** - Present complete specification for user approval

When you CAN derive the answer from codebase context:
- State your decision with rationale citing the pattern you found
- Do NOT present A/B/C options when the codebase already has a convention

When you genuinely CANNOT derive the answer:
- Ask ONE specific question explaining what artifact is missing
- Focus on implementation details unique to this user's needs
</instructions>

<slots_to_fill>
- goal: Primary objective (what success looks like)
- scope: Boundaries (what's included AND explicitly excluded)
- input_spec: Data inputs (types, sources, validation rules)
- output_spec: Expected outputs (format, destination, side effects)
- happy_path: Success scenario (step-by-step flow when everything works)
- error_handling: Failure handling (what happens when things go wrong)
- constraints: Non-functional requirements (performance, security, compatibility)
</slots_to_fill>

<examples>
<example type=\"synthesis\">
Based on the codebase context showing existing FastAPI endpoints with HTTPException
error handling, I'll use the same pattern for this feature:

**Error Handling:** Return 4xx/5xx HTTPException with specific error messages
(following pattern in backend/app/api/v1/*.py)

This matches your existing conventions. Does this work for your use case?
</example>

<example type=\"clarification_needed\">
The codebase doesn't have an existing pattern for batch processing limits.
What's the maximum batch size this feature should support?
</example>
</examples>

<output_format>
When confidence reaches 60%+, present a verification summary:

## Feature Specification

**Goal:** {goal}
**Scope:** {scope}

**Inputs:** {input_spec}
**Outputs:** {output_spec}
**Happy Path:** {happy_path}
**Error Handling:** {error_handling}
**Constraints:** {constraints}

**Confidence:** {confidence}%

Reply 'proceed' to start research phase.
</output_format>"
    else
      # Continuation prompt with conversation history
      context_prompt="<role>
You are a senior requirements analyst continuing a specification interview.
Maintain context from the conversation and build toward a complete specification.
</role>

<context>
  <session>$SESSION_NAME</session>
  <feature>$FEATURE_DESCRIPTION</feature>
  <current_phase>$phase</current_phase>
  <slots_filled>$slots_filled/7</slots_filled>
  <confidence>$confidence%</confidence>
</context>

<previous_conversation>
$conversation_history
</previous_conversation>

<task>
Continue the requirements interview. Based on what has been discussed:

1. Identify which slots remain unfilled or unclear
2. Ask the single most valuable clarifying question, OR
3. If confidence is 60%+, present the verification summary for approval
</task>

<instructions>
- SYNTHESIZE answers from codebase patterns and conversation context
- Only ask questions when genuinely blocked (explain what artifact is missing)
- Do NOT present A/B/C option tables when you can derive the answer
- When presenting the summary, ensure every slot has a concrete value with rationale
</instructions>

<output_format>
Either SYNTHESIZE the remaining slots with rationale, OR present:

## Feature Specification

**Goal:** {goal}
**Scope:** {scope}

**Inputs:** {input_spec}
**Outputs:** {output_spec}
**Happy Path:** {happy_path}
**Error Handling:** {error_handling}
**Constraints:** {constraints}

**Confidence:** {confidence}%

Reply 'proceed' to start research phase.
</output_format>"
    fi

    # Get Claude's question
    local claude_response
    claude_response=$(claude --dangerously-skip-permissions --print "$context_prompt" 2>&1) || {
      log_error "Interrogation had issues"
    }

    echo "$claude_response"
    echo ""

    # Update conversation history
    conversation_history="${conversation_history}
Claude: $claude_response
"

    # Check if Claude provided a final spec
    if echo "$claude_response" | grep -qiE "(specification summary|final specification|implementation ready|all slots filled)"; then
      REFINED_DESCRIPTION="$claude_response"
      confidence=80
      break
    fi

    # Get user response
    echo -e "  ${DIM}Your response (Ctrl+R to undo):${NC}"
    local user_response=""
    local line=""

    # Bind Ctrl+R to insert "undo" (save original binding first)
    local old_binding
    old_binding=$(bind -p 2>/dev/null | grep '\\C-r' | head -1) || true
    bind '"\C-r": "undo\n"' 2>/dev/null || true

    while true; do
      input_prompt
      read -e line
      if [ -z "$line" ]; then
        if [ -z "$user_response" ]; then
          break  # Empty response = done
        else
          break  # End of multi-line response
        fi
      fi
      if [ -n "$user_response" ]; then
        user_response="$user_response
$line"
      else
        user_response="$line"
      fi
    done

    # Restore original Ctrl+R binding (reverse-i-search)
    bind '"\C-r": reverse-search-history' 2>/dev/null || true

    if [ -z "$user_response" ]; then
      echo -e "  ${GREEN}Exiting interrogation${NC}"
      break
    fi

    # Check for "undo" command - remove last exchange and re-ask
    if echo "$user_response" | grep -qiE "^undo$|^back$|^go back$|^redo$"; then
      if [ "$conversation_round" -gt 1 ]; then
        echo -e "  ${YELLOW}↩ Undoing last response...${NC}"
        # Remove last Claude: and User: exchange from history
        # Find the second-to-last "Claude:" and truncate there
        local prev_history
        prev_history=$(echo "$conversation_history" | tac | sed '1,/^Claude:/d' | tac)
        if [ -n "$prev_history" ]; then
          conversation_history="$prev_history"
        else
          conversation_history=""
        fi
        conversation_round=$((conversation_round - 1))
        skip_increment=true  # Don't increment on next loop iteration
        echo -e "  ${DIM}Going back to round $conversation_round${NC}"
        echo ""
        continue
      else
        echo -e "  ${DIM}Already at round 1, nothing to undo${NC}"
        skip_increment=true
        continue
      fi
    fi

    # Check for "proceed" confirmation
    if echo "$user_response" | grep -qiE "^proceed$|^yes.*proceed|^let.*proceed|^ready.*proceed"; then
      user_confirmed_proceed=true
      echo -e "  ${GREEN}User confirmed 'proceed' - moving to research phase${NC}"
      break
    fi

    conversation_history="${conversation_history}
User: $user_response
"

    # Simple slot filling detection
    slots_filled=0
    for slot in "${!slots[@]}"; do
      if echo "$conversation_history" | grep -qi "$slot"; then
        slots_filled=$((slots_filled + 1))
      fi
    done

    confidence=$((slots_filled * 14))  # ~14% per slot
    echo ""
    echo -e "  ${DIM}Progress: $slots_filled/7 slots (~$confidence% confidence)${NC}"
    echo ""
  done

  # Generate final specification if not already done
  if [ -z "$REFINED_DESCRIPTION" ] || [ "$confidence" -lt 60 ]; then
    log "Generating specification summary..."
    REFINED_DESCRIPTION=$(claude --dangerously-skip-permissions --print "<role>
You are a technical writer who converts interview notes into precise,
implementation-ready specifications. You excel at removing ambiguity and
filling gaps with reasonable defaults.
</role>

<context>
<conversation>
$conversation_history
</conversation>
</context>

<task>
Synthesize the conversation into a complete feature specification. Fill any
gaps with reasonable defaults based on common patterns, but mark assumptions
with [ASSUMED] so they can be verified.
</task>

<output_format>
## Feature Specification

**Goal:** {concrete objective with success criteria}

**Scope:**
- Included: {what's in scope}
- Excluded: {what's explicitly out of scope}

**Inputs:** {data sources, formats, validation rules}

**Outputs:** {expected results, formats, destinations}

**Happy Path:**
1. {step 1}
2. {step 2}
3. {step N}

**Error Handling:**
- {error condition}: {response}
- {error condition}: {response}

**Constraints:**
- Performance: {requirements or 'standard'}
- Security: {requirements or 'standard'}
- Compatibility: {requirements or 'none'}
</output_format>" 2>&1) || {
      REFINED_DESCRIPTION="$FEATURE_DESCRIPTION"
    }
  fi

  # Save to context
  ar_write_context "$SESSION_NAME" "specification" "$REFINED_DESCRIPTION"
  ar_write_progress "$SESSION_NAME" "in_progress" "research" "" "" "0"

  # Save to file
  cat > "$SESSION_DIR/specification.md" << EOF
---
name: $SESSION_NAME-specification
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
type: specification
confidence: $confidence%
---

# Feature Specification

## Original Request
$FEATURE_DESCRIPTION

## Refined Specification
$REFINED_DESCRIPTION
EOF

  complete_step 2 "Specification captured ($confidence% confidence)"
  dim_path "Saved: $SESSION_DIR/specification.md"
}

# =============================================================================
# Phase 1: Research & Gap Analysis
# =============================================================================

research_and_gap_analysis() {
  show_step_header 3 "Research & Gap Analysis" "research"

  local spec_to_research="${REFINED_DESCRIPTION:-$FEATURE_DESCRIPTION}"

  # Step 1: Deep research
  log "Running deep research..."

  if command -v claude &> /dev/null; then
    start_spinner "Researching implementation patterns..."

    # Research query structured with XML tags per LLM prompt engineering research
    # (see ~/ccpm/RESEARCH/llm-prompt-engineering/research-report.md)
    # Key findings applied:
    #   - XML tags improve Claude's parsing accuracy (90% confidence)
    #   - Role prompting is the most powerful system prompt technique
    #   - High-level instructions outperform prescriptive step-by-step
    #   - Context is finite - keep focused, avoid redundant detail
    #   - Be explicit about desired output format
    local research_query="<role>
You are a senior software architect performing implementation research for a
production codebase. You analyze existing code patterns and identify exactly
what needs to change to implement a new feature.
</role>

<task>
Research the codebase thoroughly and produce an implementation analysis for
the feature described below. Focus on concrete findings: existing patterns,
files that need modification, and dependencies between changes.
</task>

<feature_specification>
$spec_to_research
</feature_specification>

<codebase_context>
<stack>FastAPI (Python 3.11+, async/await), React + TypeScript + Vite + Material-UI, PostgreSQL with SQLAlchemy 2.0, Dual-mode auth (Keycloak SSO + Native JWT)</stack>
<backend_models>backend/app/models/*.py</backend_models>
<backend_api>backend/app/api/v1/*.py</backend_api>
<migrations>backend/migrations/*.sql</migrations>
<frontend_pages>frontend/src/pages/*.tsx</frontend_pages>
<frontend_components>frontend/src/components/*.tsx</frontend_components>
<core_services>backend/app/core/*.py</core_services>
</codebase_context>

<research_questions>
1. Database layer: What tables, columns, or migrations are needed? Identify existing models to extend vs new models to create.
2. API layer: What endpoints need to be created or modified? Show how they fit existing router patterns.
3. Frontend layer: What pages or components are affected? Identify reusable patterns from existing code.
4. Integration points: What existing services does this connect to? Map auth, database, and cross-module dependencies.
5. Implementation order: What must be built first? Identify blocking dependencies and reusable patterns.
</research_questions>

<output_format>
Provide concrete, actionable findings organized by layer. For each layer:
- List specific files to create or modify
- Show relevant existing patterns to follow
- Note any architectural decisions required
Avoid vague recommendations. Every finding should reference a specific file or pattern.
</output_format>"

    # Direct Claude call instead of /dr skill.
    # /dr spawns nested agents (7-phase GoT with web search) which:
    #   1. Takes 30+ minutes for codebase-only analysis
    #   2. Can hang on nested agent chains with --print
    #   3. Does web research that's unnecessary for codebase analysis
    # Direct --print with the structured prompt is faster and more reliable.
    local research_output
    research_output=$(timeout 300 claude --dangerously-skip-permissions --print "$research_query" 2>&1) || {
      stop_spinner ""
      log_error "Research had issues (exit code: $?)"
      research_output="Research incomplete"
    }

    stop_spinner "Research complete"

    # Save research
    echo "$research_output" > "$SESSION_DIR/research.md"
    ar_write_context "$SESSION_NAME" "research" "$(echo "$research_output" | head -50)"

    # Create root node
    local root_node_id
    root_node_id=$(ar_add_node "$SESSION_NAME" "" "$SESSION_NAME" "$spec_to_research" "other" "$research_query")

    # Log action
    ar_log_action "$SESSION_NAME" "research_complete" "$root_node_id" '{"status":"complete"}'

    # Step 2: Gap analysis with explicit DB loop
    log "Running multi-signal gap analysis..."

    # Step 2a: Check codebase for existing patterns (for auto-resolve)
    log "Scanning codebase for existing patterns..."
    local codebase_patterns=""

    # Find existing models
    if [ -d "backend/app/models" ]; then
      codebase_patterns+="Existing models: $(ls -1 backend/app/models/*.py 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ', ')\n"
    fi

    # Find existing API endpoints
    if [ -d "backend/app/api/v1" ]; then
      codebase_patterns+="Existing APIs: $(ls -1 backend/app/api/v1/*.py 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ', ')\n"
    fi

    # Find existing migrations
    if [ -d "backend/migrations" ]; then
      local last_migration
      last_migration=$(ls -1 backend/migrations/*.sql 2>/dev/null | tail -1 | xargs -n1 basename 2>/dev/null)
      codebase_patterns+="Last migration: $last_migration\n"
    fi

    echo -e "$codebase_patterns" > "$SESSION_DIR/codebase-patterns.txt"

    # Step 2b: Get gaps from Claude with multi-signal detection
    local gap_prompt="<role>
You are a senior software architect performing gap analysis. You identify
what's missing between a feature specification and its implementation
requirements, prioritizing gaps that would block development if undiscovered.
</role>

<context>
  <session>$SESSION_NAME</session>
  <feature_spec>$spec_to_research</feature_spec>
  <context_file>.claude/ar/$SESSION_NAME/context.md</context_file>
</context>

<research_findings>
$research_output
</research_findings>

<codebase_patterns>
$codebase_patterns
</codebase_patterns>

<task>
Identify gaps between the feature specification and what's needed for
implementation. Each gap represents a question that must be answered or
a decision that must be made before coding can proceed confidently.
</task>

<instructions>
Apply multi-signal detection to find gaps systematically:

1. **Linguistic signals** (score 0.0-1.0): Look for ambiguity markers like
   'might', 'could', 'maybe', 'TBD', 'depends', 'optionally'. Higher score
   means more ambiguity detected.

2. **Slot-filling signals** (score 0.0-1.0): Check if required fields are
   defined (input format, output structure, error handling). Higher score
   means more slots are empty or vague.

3. **Codebase signals** (score 0.0-1.0): Compare against existing patterns
   in the codebase. Higher score means the feature deviates from established
   patterns without clear justification.

4. **Confidence signals** (score 0.0-1.0): Self-consistency check - does the
   specification contradict itself or leave critical paths undefined? Higher
   score means lower confidence.

Classify each gap by type (determines who can resolve it):
- **requirements**: Missing input/output/success criteria (ask product owner)
- **constraint**: Unknown performance/size/rate limits (ask architect)
- **edge_case**: Undefined failure/empty/concurrent scenarios (design decision)
- **integration**: Missing API contracts/auth/data flow (ask team leads)
- **verification**: No acceptance tests/metrics defined (derive from requirements)

Classify blocking status (determines if work can proceed):
- **BLOCKING (true)**: Cannot write tests, cannot estimate, has multiple
  valid interpretations, or missing critical integration details
- **NICE-TO-KNOW (false)**: Has codebase precedent to follow, has industry
  default to apply, or is an optimization that can be deferred
</instructions>

<examples>
<example type=\"blocking_gap\">
- name: auth_token_format
  type: integration
  blocking: true
  description: API spec doesn't define expected auth token format (JWT vs API key)
  resolution: ASK_USER
  linguistic_score: 0.8
  slot_score: 1.0
  codebase_score: 0.3
  confidence_score: 0.9
</example>

<example type=\"auto_resolved_gap\">
- name: date_format
  type: requirements
  blocking: false
  description: Date format not specified for timestamps
  resolution: AUTO_RESOLVED:codebase uses ISO8601 consistently (see utils/date.ts)
  linguistic_score: 0.4
  slot_score: 0.6
  codebase_score: 0.0
  confidence_score: 0.3
</example>
</examples>

<output_format>
Output YAML list of gaps (maximum 10, prioritized by blocking status and
combined score):

- name: gap_identifier_snake_case
  type: requirements|constraint|edge_case|integration|verification
  blocking: true|false
  description: clear statement of what information is missing
  resolution: how to resolve OR 'ASK_USER' OR 'AUTO_RESOLVED:pattern_name'
  linguistic_score: 0.0-1.0
  slot_score: 0.0-1.0
  codebase_score: 0.0-1.0
  confidence_score: 0.0-1.0
</output_format>"

    local gaps_yaml
    gaps_yaml=$(claude --dangerously-skip-permissions --print "$gap_prompt" 2>&1) || {
      log_error "Gap analysis had issues"
      gaps_yaml=""
    }

    echo "$gaps_yaml" > "$SESSION_DIR/gaps.yaml"

    # Parse gaps and create nodes in DB - EXPLICIT LOOP
    log "Processing gaps into database..."

    local gap_count=0
    local blocking_count=0
    local auto_resolved_count=0
    local current_gap_name=""
    local current_gap_type=""
    local current_gap_desc=""
    local current_blocking=""
    local current_resolution=""
    local current_linguistic="0.5"
    local current_slot="0.5"
    local current_codebase="0.5"
    local current_confidence="0.5"

    while IFS= read -r line; do
      # Start of new gap
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
        # Save previous gap if exists
        if [ -n "$current_gap_name" ]; then
          gap_count=$((gap_count + 1))
          [ "$current_blocking" = "true" ] && blocking_count=$((blocking_count + 1))

          # Check for auto-resolved
          local auto_resolved=""
          if [[ "$current_resolution" =~ AUTO_RESOLVED:(.+) ]]; then
            auto_resolved="${BASH_REMATCH[1]}"
            auto_resolved_count=$((auto_resolved_count + 1))
            log "  Gap $gap_count: $current_gap_name ($current_gap_type) [AUTO-RESOLVED: $auto_resolved]"
          else
            log "  Gap $gap_count: $current_gap_name ($current_gap_type)"
          fi

          # Calculate weighted gap score per implement.md formula:
          # Gap Score = 0.25*Linguistic + 0.30*SlotState + 0.20*Codebase + 0.25*Confidence
          local gap_score
          gap_score=$(echo "scale=2; 0.25*$current_linguistic + 0.30*$current_slot + 0.20*$current_codebase + 0.25*$current_confidence" | bc 2>/dev/null || echo "0.50")

          # Insert into database explicitly
          local gap_node_id
          gap_node_id=$(ar_add_node "$SESSION_NAME" "$root_node_id" "$current_gap_name" "$current_gap_desc" "$current_gap_type" "" "")

          # Update gap analysis for node with multi-signal scores
          ar_update_gap_analysis "$gap_node_id" \
            "{\"linguistic_score\":$current_linguistic,\"slot_score\":$current_slot,\"codebase_score\":$current_codebase,\"confidence_score\":$current_confidence,\"gap_score\":$gap_score}" \
            '{}' \
            "$auto_resolved" \
            "$([ "$current_blocking" = "true" ] && echo "$current_gap_name")" \
            "$([ "$current_blocking" != "true" ] && echo "$current_gap_name")"
        fi

        current_gap_name="${BASH_REMATCH[1]}"
        current_gap_type="other"
        current_gap_desc=""
        current_blocking="false"
        current_resolution=""
        current_linguistic="0.5"
        current_slot="0.5"
        current_codebase="0.5"
        current_confidence="0.5"
        continue
      fi

      # Parse type
      if [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.*) ]]; then
        current_gap_type="${BASH_REMATCH[1]}"
        continue
      fi

      # Parse blocking
      if [[ "$line" =~ ^[[:space:]]*blocking:[[:space:]]*(.*) ]]; then
        current_blocking="${BASH_REMATCH[1]}"
        continue
      fi

      # Parse description
      if [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.*) ]]; then
        current_gap_desc="${BASH_REMATCH[1]}"
        continue
      fi

      # Parse resolution
      if [[ "$line" =~ ^[[:space:]]*resolution:[[:space:]]*(.*) ]]; then
        current_resolution="${BASH_REMATCH[1]}"
        continue
      fi

      # Parse multi-signal scores
      if [[ "$line" =~ ^[[:space:]]*linguistic_score:[[:space:]]*([0-9.]+) ]]; then
        current_linguistic="${BASH_REMATCH[1]}"
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]*slot_score:[[:space:]]*([0-9.]+) ]]; then
        current_slot="${BASH_REMATCH[1]}"
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]*codebase_score:[[:space:]]*([0-9.]+) ]]; then
        current_codebase="${BASH_REMATCH[1]}"
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]*confidence_score:[[:space:]]*([0-9.]+) ]]; then
        current_confidence="${BASH_REMATCH[1]}"
        continue
      fi
    done < "$SESSION_DIR/gaps.yaml"

    # Don't forget the last gap
    if [ -n "$current_gap_name" ]; then
      gap_count=$((gap_count + 1))
      [ "$current_blocking" = "true" ] && blocking_count=$((blocking_count + 1))

      # Check for auto-resolved
      local auto_resolved=""
      if [[ "$current_resolution" =~ AUTO_RESOLVED:(.+) ]]; then
        auto_resolved="${BASH_REMATCH[1]}"
        auto_resolved_count=$((auto_resolved_count + 1))
        log "  Gap $gap_count: $current_gap_name ($current_gap_type) [AUTO-RESOLVED: $auto_resolved]"
      else
        log "  Gap $gap_count: $current_gap_name ($current_gap_type)"
      fi

      # Calculate weighted gap score
      local gap_score
      gap_score=$(echo "scale=2; 0.25*$current_linguistic + 0.30*$current_slot + 0.20*$current_codebase + 0.25*$current_confidence" | bc 2>/dev/null || echo "0.50")

      local gap_node_id
      gap_node_id=$(ar_add_node "$SESSION_NAME" "$root_node_id" "$current_gap_name" "$current_gap_desc" "$current_gap_type" "" "")

      ar_update_gap_analysis "$gap_node_id" \
        "{\"linguistic_score\":$current_linguistic,\"slot_score\":$current_slot,\"codebase_score\":$current_codebase,\"confidence_score\":$current_confidence,\"gap_score\":$gap_score}" \
        '{}' \
        "$auto_resolved" \
        "$([ "$current_blocking" = "true" ] && echo "$current_gap_name")" \
        "$([ "$current_blocking" != "true" ] && echo "$current_gap_name")"
    fi

    # Update context with gap summary
    local gap_summary="| Gap | Type | Blocking | Auto-Resolved | Status |
|-----|------|----------|---------------|--------|"

    # Query gaps from DB for summary
    local db_gaps
    db_gaps=$(ar_query_rows "SELECT name, gap_type, COALESCE(array_length(blocking_gaps, 1), 0) > 0, COALESCE(array_length(auto_resolved_gaps, 1), 0) > 0 FROM decomposition_nodes WHERE session_name = '$SESSION_NAME' AND parent_id IS NOT NULL")

    while IFS='|' read -r name gap_type is_blocking is_auto_resolved; do
      [ -z "$name" ] && continue
      name=$(echo "$name" | tr -d ' ')
      gap_type=$(echo "$gap_type" | tr -d ' ')
      is_blocking=$(echo "$is_blocking" | tr -d ' ')
      is_auto_resolved=$(echo "$is_auto_resolved" | tr -d ' ')
      local blocking_label="No"
      local auto_label="No"
      [ "$is_blocking" = "t" ] && blocking_label="Yes"
      [ "$is_auto_resolved" = "t" ] && auto_label="Yes"
      gap_summary="$gap_summary
| $name | $gap_type | $blocking_label | $auto_label | pending |"
    done <<< "$db_gaps"

    ar_write_context "$SESSION_NAME" "gaps" "$gap_summary"
    ar_write_progress "$SESSION_NAME" "in_progress" "decomposition" "$root_node_id" "$SESSION_NAME" "0"

    log_success "Found $gap_count gaps ($blocking_count blocking, $auto_resolved_count auto-resolved)"
  else
    log_warn "Claude CLI not available - creating stub gaps"
    local root_node_id
    root_node_id=$(ar_add_node "$SESSION_NAME" "" "$SESSION_NAME" "$spec_to_research" "other" "")
    ar_add_node "$SESSION_NAME" "$root_node_id" "Database Schema" "Define data models" "database" ""
    ar_add_node "$SESSION_NAME" "$root_node_id" "API Endpoints" "Create REST endpoints" "api" ""
    ar_add_node "$SESSION_NAME" "$root_node_id" "Frontend Components" "Build UI components" "frontend" ""
  fi

  complete_step 3 "Gap analysis complete"
  dim_path "Saved: $SESSION_DIR/research.md"
  dim_path "Saved: $SESSION_DIR/gaps.yaml"
}

# =============================================================================
# Phase 2: Recursive Decomposition
# =============================================================================
#
# Research-based atomicity and decomposition criteria:
#
# ATOMICITY HARD THRESHOLDS (any exceeded = must decompose):
#   - Time: >16 hours
#   - Files: >10 files
#   - Lines: >400 lines of change
#   - Acceptance criteria: >9 criteria
#   - Cognitive concepts: >5 distinct concepts
#
# OPTIMAL ATOMIC RANGE:
#   - Time: 4-16 hours (ideal: 8 hours, "fits in a day")
#   - Files: 1-10 files (ideal: 3-5)
#   - Lines: 50-400 lines
#   - Acceptance criteria: 3-9 criteria
#
# INVEST CRITERIA (all should pass for truly atomic tasks):
#   - Independent: Can be developed without blocking others
#   - Negotiable: Approach is flexible
#   - Valuable: Delivers demonstrable value
#   - Estimable: Clear enough to estimate confidently
#   - Small: Fits in single sprint/iteration
#   - Testable: Has clear acceptance criteria
#
# SPIDR DECOMPOSITION TECHNIQUE (vertical slicing):
#   - Spike: Research/prototype tasks
#   - Paths: User workflow paths (happy, error, edge)
#   - Interfaces: Input/output channels (API, UI, CLI)
#   - Data: Data variations (single vs batch, formats)
#   - Rules: Business rule complexity (basic, advanced)
#
# OPTIMAL SUBTASK COUNT: 4-7 per level (max 9)
#
# References:
#   - INVEST criteria (Bill Wake, 2003)
#   - Story splitting patterns (Richard Lawrence)
#   - Cognitive load theory (Miller, 1956: 7±2 chunks)
# =============================================================================

recursive_decomposition() {
  show_step_header 4 "Recursive Decomposition" "research"

  local start_time=$(date +%s)
  local iteration=0
  local max_iterations=${AR_MAX_ITERATIONS:-50}

  log "Starting decomposition loop..."

  while true; do
    iteration=$((iteration + 1))

    # Check termination conditions
    local termination_reason
    termination_reason=$(ar_should_terminate "$SESSION_NAME" "$start_time")

    if [ -n "$termination_reason" ]; then
      log "Termination: $termination_reason"
      break
    fi

    # Get pending nodes from DB - EXPLICIT LOOP
    local pending_nodes
    pending_nodes=$(ar_get_pending_nodes "$SESSION_NAME")

    if [ -z "$pending_nodes" ]; then
      log "No more pending nodes"
      break
    fi

    log "Iteration $iteration: Processing pending nodes..."

    # Process each pending node explicitly
    while IFS='|' read -r node_id name layer parent_id; do
      [ -z "$node_id" ] && continue
      node_id=$(echo "$node_id" | tr -d ' ')
      name=$(echo "$name" | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      layer=$(echo "$layer" | tr -d ' ')

      log "  Checking node $node_id: $name (layer $layer)"

      # Get full node details for context
      local node_details
      node_details=$(ar_get_node "$node_id")
      local node_description
      node_description=$(echo "$node_details" | cut -d'|' -f3 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # Check atomicity with XML context pattern per implement.md
      # Enhanced with research-based criteria (INVEST, vertical slicing, SPIDR)
      # Prompt follows LLM engineering best practices (role, explicit criteria, examples)
      if command -v claude &> /dev/null; then
        local atomicity_check
        atomicity_check=$(claude --dangerously-skip-permissions --print "<role>
You are a technical lead evaluating work items for sprint planning. You determine
whether tasks are atomic (ready for implementation) or need further decomposition.
Your decisions are based on team capacity, cognitive load limits, and engineering
best practices for story sizing.
</role>

<context>
  <session>$SESSION_NAME</session>
  <current_node>
    <id>$node_id</id>
    <name>$name</name>
    <description>$node_description</description>
    <layer>$layer</layer>
  </current_node>
  <scope>
    <context_file>.claude/ar/$SESSION_NAME/context.md</context_file>
  </scope>
</context>

<task>
Evaluate if this task is ATOMIC (implementable as a single work unit) or needs
decomposition into smaller pieces.

<instructions>
Apply these criteria to determine atomicity. Each threshold exists for a specific
engineering reason:

## HARD THRESHOLDS (any exceeded forces decomposition):
These limits are based on cognitive load research and sprint planning best practices:

- **>16 hours**: Exceeds a 2-day timebox; estimation accuracy degrades beyond this
- **>10 files**: Cross-cutting changes increase merge conflict risk exponentially
- **>400 lines**: Code review effectiveness drops sharply above this threshold
- **>9 acceptance criteria**: Testing becomes unwieldy; likely multiple stories
- **>5 concepts**: Exceeds working memory limits (Miller's 7±2 rule)

## OPTIMAL ATOMIC RANGE:
Where confidence in estimation and implementation is highest:

- Time: 4-16 hours (ideal: 8 hours = fits in a day with meetings)
- Files: 1-10 files (ideal: 3-5 = focused, reviewable change)
- Lines: 50-400 lines (ideal: 100-200 = substantial but digestible)
- Acceptance criteria: 3-9 (ideal: 5-7 = testable without being trivial)

## INVEST VALIDATION:
Score each criterion (1 point each, 6 total):

- **Independent**: Can start without waiting for other tasks (enables parallelism)
- **Negotiable**: HOW is flexible even if WHAT is fixed (avoids overspecification)
- **Valuable**: Delivers something testable/demoable (no half-built states)
- **Estimable**: Can confidently say 'this takes X hours' (reduces planning risk)
- **Small**: Fits in sprint with buffer for issues (enables predictability)
- **Testable**: Has concrete pass/fail criteria (enables CI/CD)

## LINGUISTIC RED FLAGS:
These patterns usually indicate hidden complexity:

- 'and'/'or'/'but' connecting concepts → likely separate stories
- Multiple verbs (create AND update AND delete) → likely separate CRUD stories
- Vague words (manage, handle, process) → needs refinement before sizing
</instructions>

Output YAML:
is_atomic: true|false
estimated_files: N
estimated_hours: N
estimated_lines: N
files_affected: [list of files with paths]
acceptance_criteria_count: N
complexity: simple|moderate|complex
invest_score: N (0-6, one point per INVEST criterion met)
linguistic_flags: [list of red flags found, or 'none']
rationale: brief explanation of decision

<examples>
<example type=\"atomic\">
Task: Add email validation to user registration form
is_atomic: true
estimated_files: 3
estimated_hours: 4
estimated_lines: 80
files_affected: [frontend/src/components/RegisterForm.tsx, frontend/src/utils/validation.ts, frontend/src/components/RegisterForm.test.tsx]
acceptance_criteria_count: 4
complexity: simple
invest_score: 6
linguistic_flags: [none]
rationale: Single responsibility (validate email), focused scope (3 files), clear acceptance criteria
</example>

<example type=\"needs_decomposition\">
Task: Implement user management system with roles and permissions
is_atomic: false
estimated_files: 15
estimated_hours: 40
estimated_lines: 1200
files_affected: [multiple backend and frontend files]
acceptance_criteria_count: 18
complexity: complex
invest_score: 2
linguistic_flags: [contains 'and' connecting roles AND permissions, vague 'management system']
rationale: Multiple responsibilities, exceeds all thresholds, should split by SPIDR
subtasks:
  - name: Create user roles database schema
    description: Add roles table and user_roles junction table
    slice_type: data
    dependencies: [none]
  - name: Implement role assignment API
    description: CRUD endpoints for assigning roles to users
    slice_type: interface
    dependencies: [Create user roles database schema]
  - name: Add role-based route guards
    description: Protect frontend routes based on user roles
    slice_type: path
    dependencies: [Implement role assignment API]
  - name: Create admin role management UI
    description: Interface for admins to manage user roles
    slice_type: interface
    dependencies: [Implement role assignment API]
</example>
</examples>

If NOT atomic, decompose using VERTICAL SLICING (end-to-end thin slices preferred
over horizontal layers because they deliver testable value incrementally).

## SPIDR DECOMPOSITION TECHNIQUE:
Split tasks by the dimension that creates the most independent, valuable slices:

- **Spike**: Separate when unknowns need research before implementation
- **Paths**: Split when happy path, error handling, and edge cases are distinct
- **Interfaces**: Split when API, UI, and CLI can be delivered independently
- **Data**: Split when single-item vs batch processing differ significantly
- **Rules**: Split when basic rules work without advanced/exception rules

<output_format>
Provide 4-7 subtasks (optimal cognitive load, max 9). Each subtask should be
a vertical slice that delivers testable value:

subtasks:
  - name: subtask name (use imperative verb: Create, Implement, Add)
    description: what this subtask accomplishes (concrete outcome)
    slice_type: spike|path|interface|data|rule
    dependencies: [other subtask names this needs, or 'none']
</output_format>
</task>" 2>&1) || {
          log_error "Atomicity check failed for node $node_id"
          continue
        }

        # Parse atomicity result with enhanced fields from research
        local is_atomic=false
        local estimated_files=1
        local estimated_hours=2
        local estimated_lines=100
        local files_affected=""
        local complexity="moderate"
        local invest_score=0
        local acceptance_criteria_count=0
        local linguistic_flags=""
        local rationale=""

        # Core atomicity decision
        if echo "$atomicity_check" | grep -qi "is_atomic:[[:space:]]*true"; then
          is_atomic=true
        fi

        # Parse numeric fields
        if [[ "$atomicity_check" =~ estimated_files:[[:space:]]*([0-9]+) ]]; then
          estimated_files="${BASH_REMATCH[1]}"
        fi

        if [[ "$atomicity_check" =~ estimated_hours:[[:space:]]*([0-9.]+) ]]; then
          estimated_hours="${BASH_REMATCH[1]}"
        fi

        if [[ "$atomicity_check" =~ estimated_lines:[[:space:]]*([0-9]+) ]]; then
          estimated_lines="${BASH_REMATCH[1]}"
        fi

        if [[ "$atomicity_check" =~ acceptance_criteria_count:[[:space:]]*([0-9]+) ]]; then
          acceptance_criteria_count="${BASH_REMATCH[1]}"
        fi

        if [[ "$atomicity_check" =~ invest_score:[[:space:]]*([0-6]) ]]; then
          invest_score="${BASH_REMATCH[1]}"
        fi

        if [[ "$atomicity_check" =~ complexity:[[:space:]]*(simple|moderate|complex) ]]; then
          complexity="${BASH_REMATCH[1]}"
        fi

        # Extract files_affected array
        if [[ "$atomicity_check" =~ files_affected:[[:space:]]*\[([^\]]+)\] ]]; then
          files_affected="${BASH_REMATCH[1]}"
          files_affected=$(echo "$files_affected" | tr -d '"' | tr -d "'" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ',')
        fi

        # Extract linguistic flags
        if [[ "$atomicity_check" =~ linguistic_flags:[[:space:]]*\[([^\]]+)\] ]]; then
          linguistic_flags="${BASH_REMATCH[1]}"
        fi

        # Extract rationale
        if [[ "$atomicity_check" =~ rationale:[[:space:]]*(.+) ]]; then
          rationale="${BASH_REMATCH[1]}"
        fi

        # Apply hard threshold overrides (research-based)
        # These override AI decision if thresholds exceeded
        local threshold_override=false
        if [ "$estimated_hours" -gt 16 ] 2>/dev/null; then
          log "    [!] Hard threshold: >16 hours -> forcing decomposition"
          is_atomic=false
          threshold_override=true
        fi
        if [ "$estimated_files" -gt 10 ] 2>/dev/null; then
          log "    [!] Hard threshold: >10 files -> forcing decomposition"
          is_atomic=false
          threshold_override=true
        fi
        if [ "$estimated_lines" -gt 400 ] 2>/dev/null; then
          log "    [!] Hard threshold: >400 lines -> forcing decomposition"
          is_atomic=false
          threshold_override=true
        fi
        if [ "$acceptance_criteria_count" -gt 9 ] 2>/dev/null; then
          log "    [!] Hard threshold: >9 acceptance criteria -> forcing decomposition"
          is_atomic=false
          threshold_override=true
        fi

        # INVEST score warning (6 = all criteria met)
        if [ "$invest_score" -lt 4 ] 2>/dev/null && [ "$is_atomic" = true ]; then
          log "    [!] Low INVEST score ($invest_score/6) - may need refinement"
        fi

        if [ "$is_atomic" = true ]; then
          log "    -> Atomic: $estimated_files files, $estimated_hours hrs, ~$estimated_lines lines (INVEST: $invest_score/6)"
          ar_mark_atomic "$node_id" "$estimated_files" "$estimated_hours" "$files_affected" "$complexity"
        else
          log "    -> Decomposing using vertical slicing (SPIDR technique)..."

          # Build parent context for children (key insight from implement.md)
          local parent_context="Parent: $name
Description: $node_description
Layer: $layer
Session: $SESSION_NAME"

          # Enhanced subtask parsing with SPIDR fields (slice_type, dependencies)
          local subtask_num=0
          local in_subtasks=false
          local current_subtask_name=""
          local current_subtask_desc=""
          local current_slice_type="other"
          local current_dependencies=""

          # Collect all subtasks first for dependency ordering
          declare -a subtask_names=()
          declare -a subtask_descs=()
          declare -a subtask_types=()
          declare -a subtask_deps=()

          while IFS= read -r line; do
            # Detect subtasks section
            if [[ "$line" =~ ^subtasks: ]]; then
              in_subtasks=true
              continue
            fi

            # Parse subtask entries with SPIDR fields
            if [ "$in_subtasks" = true ]; then
              if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
                # Save previous subtask if exists
                if [ -n "$current_subtask_name" ]; then
                  subtask_names+=("$current_subtask_name")
                  subtask_descs+=("$current_subtask_desc")
                  subtask_types+=("$current_slice_type")
                  subtask_deps+=("$current_dependencies")
                fi
                current_subtask_name="${BASH_REMATCH[1]}"
                current_subtask_desc=""
                current_slice_type="other"
                current_dependencies=""
                continue
              fi

              if [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.*) ]]; then
                current_subtask_desc="${BASH_REMATCH[1]}"
                continue
              fi

              # Parse SPIDR slice_type
              if [[ "$line" =~ ^[[:space:]]*slice_type:[[:space:]]*(spike|path|interface|data|rule) ]]; then
                current_slice_type="${BASH_REMATCH[1]}"
                continue
              fi

              # Parse dependencies
              if [[ "$line" =~ ^[[:space:]]*dependencies:[[:space:]]*\[([^\]]*)\] ]]; then
                current_dependencies="${BASH_REMATCH[1]}"
                continue
              fi
              if [[ "$line" =~ ^[[:space:]]*dependencies:[[:space:]]*(none|\'none\') ]]; then
                current_dependencies=""
                continue
              fi
            fi

            # Fallback: simple list format (- subtask name)
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.+) ]] && [ "$in_subtasks" = false ]; then
              local subtask="${BASH_REMATCH[1]}"
              subtask=$(echo "$subtask" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              [ -z "$subtask" ] && continue
              subtask_names+=("$subtask")
              subtask_descs+=("Subtask of $name")
              subtask_types+=("other")
              subtask_deps+=("")
            fi
          done <<< "$atomicity_check"

          # Don't forget last subtask
          if [ -n "$current_subtask_name" ]; then
            subtask_names+=("$current_subtask_name")
            subtask_descs+=("$current_subtask_desc")
            subtask_types+=("$current_slice_type")
            subtask_deps+=("$current_dependencies")
          fi

          # Check subtask count is in optimal range (4-7, max 9)
          local subtask_count=${#subtask_names[@]}
          if [ "$subtask_count" -gt 9 ]; then
            log_warn "    [!] $subtask_count subtasks exceeds optimal max (9) - consider grouping"
          elif [ "$subtask_count" -lt 2 ]; then
            log_warn "    [!] Only $subtask_count subtask - decomposition may be unnecessary"
          fi

          # Create nodes with SPIDR metadata
          for i in "${!subtask_names[@]}"; do
            subtask_num=$((subtask_num + 1))
            local st_name="${subtask_names[$i]}"
            local st_desc="${subtask_descs[$i]}"
            local st_type="${subtask_types[$i]}"
            local st_deps="${subtask_deps[$i]}"

            # Log with slice type indicator
            local type_icon=""
            case "$st_type" in
              spike)     type_icon="🔬" ;;
              path)      type_icon="🛤️" ;;
              interface) type_icon="🔌" ;;
              data)      type_icon="📊" ;;
              rule)      type_icon="📋" ;;
              *)         type_icon="📦" ;;
            esac

            log "      $type_icon Child $subtask_num: $st_name [$st_type]"

            # Enhance description with SPIDR context
            local enhanced_desc="$st_desc"
            if [ -n "$st_deps" ] && [ "$st_deps" != "none" ]; then
              enhanced_desc="$st_desc (depends on: $st_deps)"
            fi

            # Use slice_type as layer categorization
            ar_add_node "$SESSION_NAME" "$node_id" "$st_name" "$enhanced_desc" "$st_type" "" "$parent_context"
          done

          # Mark parent as decomposed with SPIDR info
          ar_update_node_status "$node_id" "decomposed" "Split into $subtask_num subtasks (vertical slices)"
        fi
      else
        # Without Claude, mark everything as atomic
        ar_mark_atomic "$node_id" 2 2 "" "moderate"
      fi
    done <<< "$pending_nodes"

    # Update progress
    ar_write_progress "$SESSION_NAME" "in_progress" "decomposition" "" "" "$layer"

    # Safety check
    if [ "$iteration" -ge "$max_iterations" ]; then
      log_warn "Max iterations reached ($max_iterations)"
      break
    fi
  done

  # Generate tree visualization
  ar_generate_tree_from_db "$SESSION_NAME"

  # Get final stats
  local stats
  stats=$(ar_get_session_stats "$SESSION_NAME")
  local total_nodes leaf_nodes max_depth
  total_nodes=$(echo "$stats" | cut -d'|' -f1 | tr -d ' ')
  leaf_nodes=$(echo "$stats" | cut -d'|' -f2 | tr -d ' ')
  max_depth=$(echo "$stats" | cut -d'|' -f3 | tr -d ' ')

  complete_step 4 "Decomposition complete ($total_nodes nodes, $leaf_nodes atomic, depth $max_depth)"
  dim_path "Tree: $SESSION_DIR/tree.md"
}

# =============================================================================
# Phase 3: PRD Generation
# =============================================================================

generate_prds() {
  show_step_header 5 "Generate PRDs" "generate"

  local prd_dir="${PROJECT_ROOT}/.claude/prds"
  mkdir -p "$prd_dir"

  # Get all atomic nodes from DB - EXPLICIT LOOP
  local atomic_nodes
  atomic_nodes=$(ar_get_atomic_nodes "$SESSION_NAME")

  if [ -z "$atomic_nodes" ]; then
    log_warn "No atomic nodes found for PRD generation"
    complete_step 5 "Skipped (no atomic nodes)"
    return
  fi

  local prd_count=0
  local prd_paths=""

  log "Generating PRDs for atomic nodes..."

  while IFS='|' read -r node_id name description gap_type estimated_files files_affected layer; do
    [ -z "$node_id" ] && continue
    node_id=$(echo "$node_id" | tr -d ' ')
    name=$(echo "$name" | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    prd_count=$((prd_count + 1))
    local prd_name="${SESSION_NAME}-$(printf '%03d' $prd_count)"
    local prd_path="${prd_dir}/${prd_name}.md"

    log "  PRD $prd_count: $prd_name - $name"

    # Generate PRD content
    ar_generate_prd_content "$SESSION_NAME" "$node_id" "$prd_count" > "$prd_path"

    # Record in DB
    ar_record_prd "$node_id" "$prd_path" "$prd_name"

    prd_paths="$prd_paths$prd_path
"
  done <<< "$atomic_nodes"

  # Save PRD list
  echo "$prd_paths" > "$SESSION_DIR/prd-list.txt"

  ar_write_progress "$SESSION_NAME" "in_progress" "prd_generation" "" "" "0"

  complete_step 5 "Generated $prd_count PRDs"
  dim_path "PRDs: .claude/prds/${SESSION_NAME}-*.md"
}

# =============================================================================
# Phase 4: Integration (Batch Process)
# =============================================================================

batch_process() {
  show_step_header 6 "Batch Process PRDs" "sync"

  local prd_list="$SESSION_DIR/prd-list.txt"

  if [ ! -f "$prd_list" ]; then
    log_warn "No PRD list found"
    complete_step 6 "Skipped (no PRDs)"
    return
  fi

  local prd_count
  prd_count=$(wc -l < "$prd_list" | tr -d ' ')

  log "Processing $prd_count PRDs..."

  # Check if /pm:batch-process is available
  if command -v claude &> /dev/null; then
    echo ""
    echo -e "  ${CYAN}${BOLD}Generated PRDs ready for processing:${NC}"
    echo ""
    cat "$prd_list" | head -10 | sed 's/^/    /'
    [ "$prd_count" -gt 10 ] && echo "    ... and $((prd_count - 10)) more"
    echo ""
    echo -e "  ${BOLD}To process these PRDs, run:${NC}"
    echo -e "  ${CYAN}/pm:batch-process .claude/prds/${SESSION_NAME}-*.md${NC}"
    echo ""
    echo -e "  ${DIM}Or process individually with /pm:decompose${NC}"
    echo ""

    # Mark session complete
    ar_complete_session "$SESSION_NAME" "prd_generated" "completed"

    # Update progress
    ar_write_progress "$SESSION_NAME" "completed" "integration" "" "" "0"
  else
    log_warn "Claude CLI not available for batch processing"
  fi

  complete_step 6 "PRDs ready for processing"
}

# =============================================================================
# Final Summary
# =============================================================================

show_final_summary() {
  local total_duration=$(($(date +%s) - SESSION_START_TIME))

  echo ""
  echo ""
  echo -e "${GREEN}${BOLD}"
  cat << 'COMPLETE'
  ╔═══════════════════════════════════════════════════════════╗
  ║                                                           ║
  ║              ✓  IMPLEMENTATION PLAN COMPLETE              ║
  ║                                                           ║
  ╚═══════════════════════════════════════════════════════════╝
COMPLETE
  echo -e "${NC}"

  echo -e "  ${BOLD}Session:${NC} $SESSION_NAME"
  echo -e "  ${BOLD}Duration:${NC} $(format_duration $total_duration)"
  echo ""

  # Show progress summary
  show_progress_summary

  # Get stats from DB
  local stats
  stats=$(ar_get_session_stats "$SESSION_NAME")
  local total_nodes leaf_nodes max_depth prds_generated
  total_nodes=$(echo "$stats" | cut -d'|' -f1 | tr -d ' ')
  leaf_nodes=$(echo "$stats" | cut -d'|' -f2 | tr -d ' ')
  max_depth=$(echo "$stats" | cut -d'|' -f3 | tr -d ' ')
  prds_generated=$(echo "$stats" | cut -d'|' -f4 | tr -d ' ')

  local confidence
  confidence=$(ar_get_session_confidence "$SESSION_NAME")
  local blocking_count
  blocking_count=$(ar_get_blocking_gap_count "$SESSION_NAME")
  local auto_resolved
  auto_resolved=$(ar_get_auto_resolved_count "$SESSION_NAME")

  echo ""
  echo -e "  ${BOLD}Decomposition Stats${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
  echo -e "  Total Nodes:    ${total_nodes:-0}"
  echo -e "  Atomic (PRDs):  ${leaf_nodes:-0}"
  echo -e "  Max Depth:      ${max_depth:-0}"
  echo -e "  Confidence:     ${confidence:-0}%"
  # Calculate nice-to-know (non-blocking) count
  local nice_to_know_count
  nice_to_know_count=$(ar_query "SELECT SUM(COALESCE(array_length(nice_to_know_gaps, 1), 0)) FROM decomposition_nodes WHERE session_name = '$SESSION_NAME'" 2>/dev/null || echo "0")

  echo ""
  echo -e "  ${BOLD}Gap Analysis${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
  echo -e "  Blocking Gaps:      ${blocking_count:-0}"
  echo -e "  Auto-Resolved:      ${auto_resolved:-0}"
  echo -e "  Nice-to-know:       ${nice_to_know_count:-0}"
  echo ""

  echo -e "  ${BOLD}Output Files${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
  echo ""
  echo -e "  ${CYAN}Context:${NC} ${DIM}.claude/ar/${SESSION_NAME}/${NC}"
  echo -e "    ${DIM}├─ context.md${NC}"
  echo -e "    ${DIM}├─ progress.md${NC}"
  echo -e "    ${DIM}├─ tree.md${NC}"
  echo -e "    ${DIM}└─ specification.md${NC}"
  echo ""
  echo -e "  ${CYAN}PRDs:${NC} ${DIM}.claude/prds/${SESSION_NAME}-*.md${NC}"
  echo ""

  echo -e "  ${BOLD}Next Steps${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
  echo -e "  ${WHITE}1.${NC} Review PRDs in .claude/prds/"
  echo -e "  ${WHITE}2.${NC} Run ${CYAN}/pm:batch-process .claude/prds/${SESSION_NAME}-*.md${NC}"
  echo -e "  ${WHITE}3.${NC} Or process individually: ${CYAN}/pm:decompose${NC}"
  echo ""

  echo -e "  ${BOLD}Database Query${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
  echo -e "  ${DIM}SELECT * FROM decomposition_sessions WHERE session_name = '${SESSION_NAME}';${NC}"
  echo -e "  ${DIM}SELECT * FROM decomposition_nodes WHERE session_name = '${SESSION_NAME}';${NC}"
  echo ""
}

# =============================================================================
# Main
# =============================================================================

show_help() {
  cat << 'HELP'
Usage: implement.sh [OPTIONS] [feature-description]

Autonomous Recursive Implementation - decompose features into atomic PRDs.

Options:
  -h, --help              Show this help
  -r, --resume <session>  Resume an interrupted session
  -l, --list              List existing sessions

Arguments:
  feature-description     Description of the feature to implement
                         If omitted, will prompt interactively

Examples:
  ./implement.sh "Add inventory sharing between organizations"
  ./implement.sh --resume inventory-sharing
  ./implement.sh  # Interactive mode

Output:
  .claude/ar/{session}/      Context files
  .claude/prds/{session}-*.md Generated PRDs
HELP
}

list_sessions() {
  local ar_dir="${PROJECT_ROOT}/.claude/ar"
  if [ -d "$ar_dir" ]; then
    echo "Existing sessions:"
    ls -1 "$ar_dir" 2>/dev/null | while read -r session; do
      local status
      status=$(ar_get_session_status "$session" 2>/dev/null || echo "unknown")
      echo "  - $session ($status)"
    done
  else
    echo "No sessions found"
  fi
}

main() {
  SESSION_START_TIME=$(date +%s)

  # Parse arguments
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
      --resume|-r)
        if [ -z "${2:-}" ]; then
          echo "Error: --resume requires a session name"
          exit 1
        fi
        SESSION_NAME="$2"
        RESUME_MODE=true
        if ! ar_context_exists "$SESSION_NAME"; then
          echo "Error: Session '$SESSION_NAME' not found"
          list_sessions
          exit 1
        fi
        shift 2
        ;;
      *)
        FEATURE_DESCRIPTION="$1"
        shift
        ;;
    esac
  done

  # Show banner
  show_banner

  echo -e "  ${DIM}[Ctrl+C ×2] exit at any time${NC}"
  echo ""

  # Handle resume vs new session
  if [ "$RESUME_MODE" = true ]; then
    SESSION_DIR="${PROJECT_ROOT}/.claude/ar/${SESSION_NAME}"
    RESUME_FROM_STEP=$(ar_read_progress_phase "$SESSION_NAME")

    case "$RESUME_FROM_STEP" in
      setup|interrogation) RESUME_FROM_STEP=2 ;;
      research) RESUME_FROM_STEP=3 ;;
      decomposition) RESUME_FROM_STEP=4 ;;
      prd_generation) RESUME_FROM_STEP=5 ;;
      integration|completed) RESUME_FROM_STEP=6 ;;
      *) RESUME_FROM_STEP=1 ;;
    esac

    log "Resuming session: $SESSION_NAME from step $RESUME_FROM_STEP"

    # Load feature description from context
    if [ -f "$SESSION_DIR/specification.md" ]; then
      FEATURE_DESCRIPTION=$(grep -A100 "## Original Request" "$SESSION_DIR/specification.md" | head -20 | tail -19)
      REFINED_DESCRIPTION=$(grep -A100 "## Refined Specification" "$SESSION_DIR/specification.md" | head -50 | tail -49)
    fi
  else
    # Phase 0: Initialize
    show_step_header 1 "Initialize Session" "sync"
    init_session "$FEATURE_DESCRIPTION"
    complete_step 1 "Session initialized"
    RESUME_FROM_STEP=2
  fi

  # Run pipeline from resume point
  if [ "$RESUME_FROM_STEP" -le 2 ]; then
    interrogation_phase
  else
    echo -e "  ${DIM}Step 2: Interrogation - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 3 ]; then
    research_and_gap_analysis
  else
    echo -e "  ${DIM}Step 3: Research & Gaps - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 4 ]; then
    recursive_decomposition
  else
    echo -e "  ${DIM}Step 4: Decomposition - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 5 ]; then
    generate_prds
  else
    echo -e "  ${DIM}Step 5: Generate PRDs - skipped (already complete)${NC}"
  fi

  if [ "$RESUME_FROM_STEP" -le 6 ]; then
    batch_process
  else
    echo -e "  ${DIM}Step 6: Batch Process - skipped (already complete)${NC}"
  fi

  show_final_summary
}

# Run main with all arguments
main "$@"
