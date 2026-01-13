#!/bin/bash
# interrogate.sh - Orchestrate structured discovery conversations
#
# Usage:
#   ./interrogate.sh [session-name]           # Start or resume session
#   ./interrogate.sh --list                   # List all sessions
#   ./interrogate.sh --status [name]          # Show session status
#   ./interrogate.sh --extract <name>         # Extract scope document
#   ./interrogate.sh --build <name>           # Full pipeline → Loki Mode build
#
# Pipeline:
#   interrogate → extract-findings → (optional) Loki Mode build

set -e

# Detect CCPM directory (where the skills are defined)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCPM_DIR="${CCPM_DIR:-$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")}"

# Function to run claude with access to CCPM skills
run_claude() {
  local args="$@"
  # Run from CCPM directory so skills are found
  # Explicitly export HOME to ensure Claude uses the right config directory
  export HOME="${HOME:-/home/appuser}"
  (cd "$CCPM_DIR" && claude $args)
}

SESSION_NAME="${1:-$(date +%Y%m%d-%H%M%S)}"
SESSION_DIR=".claude/interrogations/$SESSION_NAME"
CONV_FILE="$SESSION_DIR/conversation.md"
SCOPE_DIR=".claude/scopes/$SESSION_NAME"

# Show help
show_help() {
  cat << 'EOF'
Interrogate - Structured Discovery Conversations

Usage:
  ./interrogate.sh [session-name]           Start or resume a session
  ./interrogate.sh --list                   List all sessions
  ./interrogate.sh --status [name]          Show session status
  ./interrogate.sh --extract <name>         Extract scope document from session
  ./interrogate.sh --build <name>           Full pipeline: interrogate → extract → Loki Mode
  ./interrogate.sh --help                   Show this help

Pipeline Flow:
  1. ./interrogate.sh <name>                Structured Q&A → conversation.md
  2. ./interrogate.sh --extract <name>      Generate scope document
  3. ./interrogate.sh --build <name>        Activate Loki Mode to build app

Or run the full pipeline at once:
  ./interrogate.sh --build <name>           Does all steps automatically

Output Files:
  .claude/interrogations/<name>/conversation.md   Raw Q&A transcript
  .claude/scopes/<name>/00_scope_document.md      Comprehensive scope doc
  .claude/scopes/<name>/01_features.md            Feature catalog
  .claude/scopes/<name>/02_user_journeys.md       User journey maps
  .claude/scopes/<name>/03_nfr_requirements.md    Non-functional requirements
  .claude/scopes/<name>/04_technical_architecture.md   Tech stack, integrations
  .claude/scopes/<name>/05_risk_assessment.md     Risk analysis
  .claude/scopes/<name>/06_gap_analysis.md        Open questions
EOF
}

# List all sessions
list_sessions() {
  if [ ! -d ".claude/interrogations" ]; then
    echo "No interrogation sessions found."
    echo "Start one with: ./interrogate.sh [session-name]"
    exit 0
  fi

  echo "Interrogation Sessions:"
  echo ""

  for dir in .claude/interrogations/*/; do
    if [ -d "$dir" ]; then
      name=$(basename "$dir")
      conv_file="$dir/conversation.md"
      scope_file=".claude/scopes/$name/00_scope_document.md"

      if [ -f "$conv_file" ]; then
        # Extract status from frontmatter
        status=$(grep "^Status:" "$conv_file" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
        type=$(grep "^Type:" "$conv_file" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')

        # Count Q&A exchanges
        exchanges=$(grep -c "^\*\*Claude:\*\*" "$conv_file" 2>/dev/null || echo "0")

        # Check if scope exists
        scope_status=""
        if [ -f "$scope_file" ]; then
          scope_status="[scope ✓]"
        fi

        printf "  %-25s %s (%s) - %d exchanges %s\n" "$name" "${status:-unknown}" "${type:-unclassified}" "$exchanges" "$scope_status"
      else
        printf "  %-25s empty\n" "$name"
      fi
    fi
  done

  echo ""
  echo "Commands:"
  echo "  Resume:  ./interrogate.sh <name>"
  echo "  Extract: ./interrogate.sh --extract <name>"
  echo "  Build:   ./interrogate.sh --build <name>"
}

# Show session status
show_status() {
  local name="${1:-$SESSION_NAME}"
  local dir=".claude/interrogations/$name"
  local conv="$dir/conversation.md"
  local scope=".claude/scopes/$name/00_scope_document.md"

  if [ ! -f "$conv" ]; then
    echo "Session not found: $name"
    exit 1
  fi

  echo "=== Session: $name ==="
  echo ""

  # Extract metadata
  grep "^Started:\|^Status:\|^Type:\|^Domain:\|^Completed:" "$conv" 2>/dev/null | head -5

  echo ""
  echo "Exchanges: $(grep -c "^\*\*Claude:\*\*" "$conv" 2>/dev/null || echo "0")"

  # Check scope status
  if [ -f "$scope" ]; then
    echo "Scope: Generated ✓"
  else
    echo "Scope: Not generated"
  fi
  echo ""

  # Show last exchange
  echo "Last question asked:"
  grep "^\*\*Claude:\*\*" "$conv" 2>/dev/null | tail -1 | sed 's/\*\*Claude:\*\* /  /'

  echo ""

  # Suggest next step based on status
  status=$(grep "^Status:" "$conv" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
  if [ "$status" = "complete" ]; then
    if [ -f "$scope" ]; then
      echo "Next: ./interrogate.sh --build $name  (activate Loki Mode)"
    else
      echo "Next: ./interrogate.sh --extract $name"
    fi
  else
    echo "Resume: ./interrogate.sh $name"
  fi
}

# Extract findings to scope document
extract_findings() {
  local name="$1"
  local conv=".claude/interrogations/$name/conversation.md"

  if [ ! -f "$conv" ]; then
    echo "❌ Session not found: $name"
    exit 1
  fi

  # Check if complete
  status=$(grep "^Status:" "$conv" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
  if [ "$status" != "complete" ]; then
    echo "⚠️  Interrogation not complete."
    echo ""
    echo "Resume with: ./interrogate.sh $name"
    echo "Or extract anyway? (y/n): "
    read -r confirm
    if [[ "$confirm" != "y" ]]; then
      exit 0
    fi
  fi

  echo "=== Extracting Findings: $name ==="
  echo ""
  echo "This will generate a comprehensive scope document..."
  echo ""

  # Run extract-findings
  run_claude --dangerously-skip-permissions --print "/pm:extract-findings $name"

  echo ""
  echo "---"
  echo ""

  if [ -f ".claude/scopes/$name/00_scope_document.md" ]; then
    echo "✅ Scope document generated"
    echo ""
    echo "Output: .claude/scopes/$name/"
    echo ""
    echo "Next steps:"
    echo "  1. Review: cat .claude/scopes/$name/00_scope_document.md"
    echo "  2. Build:  ./interrogate.sh --build $name"
  else
    echo "❌ Scope document generation failed"
    echo "Check output above for errors"
  fi
}

# Full pipeline: interrogate → extract → Loki Mode build
build_full() {
  local name="$1"
  local conv=".claude/interrogations/$name/conversation.md"
  local scope=".claude/scopes/$name/00_scope_document.md"

  echo "=== Full Pipeline: $name ==="
  echo ""
  echo "Pipeline: interrogate → extract → Loki Mode build"
  echo ""

  # Step 1: Check/run interrogation
  if [ -f "$conv" ]; then
    status=$(grep "^Status:" "$conv" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    if [ "$status" = "complete" ]; then
      echo "Step 1: Interrogation ✓ (already complete)"
    else
      echo "Step 1: Resuming interrogation..."
      echo "---"
      run_claude --dangerously-skip-permissions "/pm:interrogate $name"
      echo "---"
    fi
  else
    echo "Step 1: Starting interrogation..."
    mkdir -p ".claude/interrogations/$name"
    echo "---"
    run_claude --dangerously-skip-permissions "/pm:interrogate $name"
    echo "---"
  fi

  # Verify interrogation complete
  if [ -f "$conv" ]; then
    status=$(grep "^Status:" "$conv" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    if [ "$status" != "complete" ]; then
      echo ""
      echo "Interrogation not complete. Stopping pipeline."
      echo "Resume with: ./interrogate.sh --build $name"
      exit 0
    fi
  else
    echo "❌ Interrogation failed"
    exit 1
  fi

  echo ""

  # Step 2: Extract findings
  if [ -f "$scope" ]; then
    echo "Step 2: Scope document ✓ (already exists)"
    echo ""
    read -p "Regenerate scope document? (y/n): " regen
    if [[ "$regen" == "y" ]]; then
      echo "Regenerating..."
      run_claude --dangerously-skip-permissions --print "/pm:extract-findings $name"
    fi
  else
    echo "Step 2: Extracting findings..."
    echo "---"
    run_claude --dangerously-skip-permissions --print "/pm:extract-findings $name"
    echo "---"
  fi

  # Verify scope exists
  if [ ! -f "$scope" ]; then
    echo "❌ Scope document generation failed"
    exit 1
  fi

  echo ""
  echo "Step 2: Scope document ✓"
  echo ""

  # Step 3: Loki Mode
  echo "Step 3: Loki Mode Build"
  echo ""
  echo "⚠️  WARNING: Loki Mode is autonomous and will:"
  echo "  - Generate code across multiple files"
  echo "  - Create database schemas and migrations"
  echo "  - Set up infrastructure and deployment"
  echo "  - Run tests and validate functionality"
  echo ""
  echo "This requires --dangerously-skip-permissions flag."
  echo ""

  read -p "Activate Loki Mode? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo ""
    echo "Pipeline stopped before Loki Mode."
    echo ""
    echo "Your scope document is ready at:"
    echo "  .claude/scopes/$name/00_scope_document.md"
    echo ""
    echo "To activate Loki Mode later:"
    echo "  ./build-from-scope.sh $name"
    exit 0
  fi

  echo ""
  echo "=== Activating Loki Mode ==="
  echo ""

  # Prepare Loki Mode prompt
  LOKI_PROMPT=$(cat << EOF
Loki Mode

Build the application defined in this scope document:

$(cat "$scope")

---

Additional context files are in: .claude/scopes/$name/
- 01_features.md - Feature catalog
- 02_user_journeys.md - User journey maps
- 03_nfr_requirements.md - Non-functional requirements
- 04_technical_architecture.md - Tech stack and integrations
- 05_risk_assessment.md - Risk analysis
- 06_gap_analysis.md - Open questions (resolve as needed)

Default tech stack (per CLAUDE.md): Angular, GraphQL, Python, PostgreSQL

Execute full build pipeline including:
1. Architecture and project setup
2. Database schema and migrations
3. Backend API implementation
4. Frontend implementation
5. Integration with external systems
6. Testing (unit, integration, e2e)
7. Documentation
8. Deployment configuration

Begin.
EOF
)

  # Write prompt to temp file
  PROMPT_FILE=$(mktemp)
  echo "$LOKI_PROMPT" > "$PROMPT_FILE"

  # Launch Loki Mode
  echo "Launching Claude Code with Loki Mode..."
  echo "---"
  echo ""

  run_claude --dangerously-skip-permissions < "$PROMPT_FILE"

  # Cleanup
  rm -f "$PROMPT_FILE"

  echo ""
  echo "---"
  echo ""
  echo "=== Pipeline Complete ==="
}

# Handle arguments
case "$1" in
  --help|-h)
    show_help
    exit 0
    ;;
  --list|-l)
    list_sessions
    exit 0
    ;;
  --status|-s)
    show_status "$2"
    exit 0
    ;;
  --extract|-e)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./interrogate.sh --extract <session-name>"
      exit 1
    fi
    extract_findings "$2"
    exit 0
    ;;
  --build|-b)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./interrogate.sh --build <session-name>"
      exit 1
    fi
    build_full "$2"
    exit 0
    ;;
esac

# Default: Initialize or resume session
echo "=== Interrogate: $SESSION_NAME ==="
echo ""

if [ -f "$CONV_FILE" ]; then
  # Check if already complete
  status=$(grep "^Status:" "$CONV_FILE" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
  if [ "$status" = "complete" ]; then
    echo "Session already complete."
    echo ""
    echo "Next steps:"
    echo "  Extract scope: ./interrogate.sh --extract $SESSION_NAME"
    echo "  Full build:    ./interrogate.sh --build $SESSION_NAME"
    echo "  Start fresh:   rm -rf $SESSION_DIR && ./interrogate.sh $SESSION_NAME"
    exit 0
  fi

  echo "Resuming existing session..."
  echo "Conversation file: $CONV_FILE"
  echo ""

  # Show where we left off
  last_q=$(grep "^\*\*Claude:\*\*" "$CONV_FILE" 2>/dev/null | tail -1 | sed 's/\*\*Claude:\*\* //')
  if [ -n "$last_q" ]; then
    echo "Last question: $last_q"
    echo ""
  fi
else
  echo "Starting new session..."
  mkdir -p "$SESSION_DIR"
  echo "Session directory: $SESSION_DIR"
  echo ""
fi

# Launch Claude with the interrogate command
echo "Launching interrogation..."
echo "---"
echo ""

# Run interactively (no --print flag - this is a conversation)
run_claude --dangerously-skip-permissions "/pm:interrogate $SESSION_NAME"

# After completion, show next steps
echo ""
echo "---"
echo ""

if [ -f "$CONV_FILE" ]; then
  status=$(grep "^Status:" "$CONV_FILE" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
  if [ "$status" = "complete" ]; then
    echo "✅ Interrogation complete"
    echo ""
    echo "Conversation saved: $CONV_FILE"
    echo ""
    echo "Next steps:"
    echo "  Extract scope: ./interrogate.sh --extract $SESSION_NAME"
    echo "  Full build:    ./interrogate.sh --build $SESSION_NAME"
  else
    echo "Session paused."
    echo ""
    echo "Resume with: ./interrogate.sh $SESSION_NAME"
  fi
fi
