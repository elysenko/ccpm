#!/bin/bash
# interrogate.sh - Orchestrate structured discovery conversations
#
# Usage:
#   ./interrogate.sh [session-name]           # Start or resume session (full pipeline)
#   ./interrogate.sh --list                   # List all sessions
#   ./interrogate.sh --status [name]          # Show session status
#   ./interrogate.sh --extract <name>         # Extract scope document
#   ./interrogate.sh --credentials <name>     # Gather credentials for integrations
#   ./interrogate.sh --repo [name]            # Ensure GitHub repo exists
#   ./interrogate.sh --services [name]        # Setup PostgreSQL and MinIO services
#   ./interrogate.sh --build <name>           # Full pipeline → batch process PRDs
#   ./interrogate.sh --resume <name>          # Resume pipeline from last completed step
#   ./interrogate.sh --resume-from <N> <name> # Resume from specific step
#   ./interrogate.sh --pipeline-status <name> # Show pipeline progress
#
# Pipeline:
#   services → schema → repo → interrogate → extract → credentials → roadmap → PRDs → batch-process → synthetic-test → remediation

set -e

# Get script directory for sourcing library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SESSION_NAME="${1:-$(date +%Y%m%d-%H%M%S)}"
SESSION_DIR=".claude/interrogations/$SESSION_NAME"
CONV_FILE="$SESSION_DIR/conversation.md"
SCOPE_DIR=".claude/scopes/$SESSION_NAME"

# Show help
show_help() {
  cat << 'EOF'
Interrogate - Structured Discovery Conversations

Usage:
  ./interrogate.sh [session-name]             Full pipeline (default): services → PRDs → batch-process
  ./interrogate.sh --interrogate-only <name>  Just run the Q&A conversation
  ./interrogate.sh --list                     List all sessions
  ./interrogate.sh --status [name]            Show session status
  ./interrogate.sh --extract <name>           Extract scope document from session
  ./interrogate.sh --credentials <name>       Gather credentials for integrations
  ./interrogate.sh --repo [name]              Ensure GitHub repository exists
  ./interrogate.sh --services [name]          Setup PostgreSQL and MinIO services
  ./interrogate.sh --build <name>             Alias for default (full pipeline)
  ./interrogate.sh --resume <name>            Resume pipeline from last completed step
  ./interrogate.sh --resume-from <N> <name>   Resume from specific step (1-12)
  ./interrogate.sh --pipeline-status <name>   Show pipeline progress
  ./interrogate.sh --help                     Show this help

Pipeline Flow:
   1. ./interrogate.sh --services [name]     Setup PostgreSQL, MinIO, CloudBeaver
   2. (auto) Create interview database schema
   3. ./interrogate.sh --repo [name]         Ensure GitHub repo exists
   4. ./interrogate.sh <name>                Structured Q&A → conversation.md
   5. ./interrogate.sh --extract <name>      Generate scope document
   6. ./interrogate.sh --credentials <name>  Collect integration credentials
   7. (auto) Generate MVP roadmap            /pm:roadmap-generate
   8. (auto) Decompose into PRDs             /pm:scope-decompose --generate
   9. (auto) Batch process PRDs              /pm:batch-process
  10. (auto) Deploy to Kubernetes            /pm:deploy
  11. (auto) Synthetic persona testing       /pm:generate-personas → tests → feedback
  12. (auto) Generate remediation PRDs       /pm:generate-remediation

Resume Options:
  --resume <name>             Continue from where pipeline stopped
  --resume-from <N> <name>    Start from specific step (1-12)

Self-Healing:
  When a step fails, the pipeline automatically invokes /pm:fix_problem
  to diagnose and fix the issue. Up to 3 fix attempts are made before
  escalating to manual intervention.

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
  .claude/scopes/<name>/07_roadmap.md             MVP roadmap with phases
  .claude/scopes/<name>/credentials.yaml          Credential collection metadata
  .claude/prds/*.md                               Generated PRDs
  .claude/testing/personas/<name>-personas.json   Synthetic test personas
  .claude/testing/playwright/                     E2E test suite
  .claude/testing/feedback/<name>-feedback.json   Synthetic user feedback
  .claude/testing/feedback/<name>-analysis.md     Feedback analysis report
  .env                                            Environment credentials (gitignored)
  .env.template                                   Template for sharing

Pipeline State:
  .claude/pipeline/<name>/state.yaml             Pipeline progress tracking
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
      pipeline_state=".claude/pipeline/$name/state.yaml"

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

        # Check pipeline status
        pipeline_info=""
        if [ -f "$pipeline_state" ]; then
          last_step=$(grep "^last_completed_step:" "$pipeline_state" 2>/dev/null | cut -d: -f2 | tr -d ' ')
          pipe_status=$(grep "^status:" "$pipeline_state" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
          if [ "$pipe_status" = "complete" ]; then
            pipeline_info="[pipeline ✓]"
          elif [ -n "$last_step" ] && [ "$last_step" != "0" ]; then
            pipeline_info="[step $last_step/11]"
          fi
        fi

        printf "  %-25s %s (%s) - %d exchanges %s %s\n" "$name" "${status:-unknown}" "${type:-unclassified}" "$exchanges" "$scope_status" "$pipeline_info"
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
  echo "  Resume:  ./interrogate.sh --resume <name>"
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

  # Check credential status
  local creds_state=".claude/scopes/$name/credentials.yaml"
  if [ -f "$creds_state" ] && [ -f ".env" ]; then
    deferred=$(grep "deferred_credentials:" "$creds_state" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    if [ -n "$deferred" ] && [ "$deferred" != "0" ]; then
      echo "Credentials: Gathered (⚠️ $deferred deferred)"
    else
      echo "Credentials: Gathered ✓"
    fi
  else
    echo "Credentials: Not gathered"
  fi

  # Check pipeline status
  local pipeline_state=".claude/pipeline/$name/state.yaml"
  if [ -f "$pipeline_state" ]; then
    echo ""
    echo "Pipeline:"
    local pipe_status
    pipe_status=$(grep "^status:" "$pipeline_state" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    local last_step
    last_step=$(grep "^last_completed_step:" "$pipeline_state" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    echo "  Status: $pipe_status"
    echo "  Progress: Step $last_step/11"
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
      if [ -f "$pipeline_state" ]; then
        local pipe_status
        pipe_status=$(grep "^status:" "$pipeline_state" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
        if [ "$pipe_status" = "complete" ]; then
          echo "Pipeline complete!"
        else
          echo "Next: ./interrogate.sh --resume $name"
        fi
      else
        echo "Next: ./interrogate.sh --build $name  (generate roadmap → PRDs → batch-process)"
      fi
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
  claude --dangerously-skip-permissions --print "/pm:extract-findings $name"

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

# Gather credentials for integrations
gather_credentials() {
  local name="$1"
  local scope=".claude/scopes/$name/04_technical_architecture.md"
  local creds_state=".claude/scopes/$name/credentials.yaml"

  if [ ! -f "$scope" ]; then
    echo "❌ Scope not found: $name"
    echo ""
    echo "First run: ./interrogate.sh --extract $name"
    exit 1
  fi

  echo "=== Gathering Credentials: $name ==="
  echo ""
  echo "This will collect credentials for integrations in your scope document..."
  echo ""

  # Run gather-credentials command
  claude --dangerously-skip-permissions "/pm:gather-credentials $name"

  echo ""
  echo "---"
  echo ""

  if [ -f ".env" ] && [ -f "$creds_state" ]; then
    echo "✅ Credentials gathered"
    echo ""
    echo "Files created:"
    echo "  .env (actual values - gitignored)"
    echo "  .env.template (template for sharing)"
    echo "  $creds_state (metadata)"
    echo ""
    echo "Next steps:"
    echo "  1. Review .env for accuracy"
    echo "  2. Build: ./interrogate.sh --build $name"
  else
    echo "⚠️  Credential gathering incomplete"
    echo ""
    echo "Resume with: ./interrogate.sh --credentials $name"
  fi
}

# Ensure GitHub repository exists
ensure_repo() {
  local repo_name="${1:-$(basename "$(pwd)")}"

  echo "=== Ensure GitHub Repository ==="
  echo ""

  # Run the ensure-github-repo script
  ./.claude/scripts/ensure-github-repo.sh "$repo_name"
}

# Setup infrastructure services (PostgreSQL, MinIO)
setup_services() {
  local project_name="${1:-$(basename "$(pwd)")}"

  echo "=== Setup Infrastructure Services ==="
  echo ""
  echo "Project: $project_name"
  echo "Namespace: $project_name"
  echo ""

  # Run setup-service.sh for all services
  ./.claude/scripts/setup-service.sh all "$project_name" --project="$project_name"

  echo ""
  echo "---"
  echo ""

  # Pull credentials into .env
  echo "Pulling credentials into .env..."
  NAMESPACE="$project_name" ./.claude/scripts/setup-env-from-k8s.sh

  echo ""
  echo "✅ Services ready"
  echo "   PostgreSQL: $project_name namespace"
  echo "   MinIO: $project_name namespace"
}

# Full pipeline using pipeline-lib.sh
build_full() {
  local name="$1"
  local start_step="${2:-1}"

  echo "=== Full Pipeline: $name ==="
  echo ""
  echo "Pipeline: services → repo → interrogate → extract → credentials → roadmap → PRDs → batch → test → remediation"
  echo ""

  # Source the pipeline library
  source "$SCRIPT_DIR/pipeline-lib.sh"

  # Initialize state
  init_pipeline_state "$name"

  # Run pipeline from start step
  run_pipeline_from "$start_step"

  # Show final summary
  local prds_dir=".claude/prds"
  local prd_count
  prd_count=$(ls -1 "$prds_dir"/*.md 2>/dev/null | wc -l)
  local roadmap=".claude/scopes/$name/07_roadmap.md"

  echo ""
  echo "=== Pipeline Summary ==="
  echo ""
  echo "  - Scope: .claude/scopes/$name/"
  if [ -f "$roadmap" ]; then
    echo "  - Roadmap: $roadmap"
  fi
  echo "  - PRDs: $prds_dir/ ($prd_count files)"
  if [ -f ".claude/testing/personas/$name-personas.json" ]; then
    echo "  - Personas: .claude/testing/personas/$name-personas.json"
  fi
  if [ -f ".claude/testing/feedback/$name-analysis.md" ]; then
    echo "  - Feedback Analysis: .claude/testing/feedback/$name-analysis.md"
  fi
  echo "  - State: .claude/pipeline/$name/state.yaml"
  echo ""
  echo "Monitor progress:"
  echo "  /pm:status"
  echo "  /pm:epic-status <epic-name>"
}

# Resume pipeline from last completed step
resume_pipeline() {
  local name="$1"
  local pipeline_state=".claude/pipeline/$name/state.yaml"

  if [ ! -f "$pipeline_state" ]; then
    echo "❌ No pipeline state found for: $name"
    echo ""
    echo "Start fresh with: ./interrogate.sh --build $name"
    exit 1
  fi

  # Get last completed step
  local last_step
  last_step=$(grep "^last_completed_step:" "$pipeline_state" 2>/dev/null | cut -d: -f2 | tr -d ' ')

  if [ -z "$last_step" ] || [ "$last_step" = "0" ]; then
    echo "No steps completed yet. Starting from step 1."
    build_full "$name" 1
  elif [ "$last_step" = "11" ]; then
    echo "Pipeline already complete for: $name"
    echo ""
    echo "To restart: ./interrogate.sh --resume-from 1 $name"
    exit 0
  else
    local next_step=$((last_step + 1))
    echo "Resuming from step $next_step (last completed: $last_step)"
    echo ""
    build_full "$name" "$next_step"
  fi
}

# Resume from specific step
resume_from_step() {
  local step="$1"
  local name="$2"

  if [ -z "$step" ] || [ -z "$name" ]; then
    echo "❌ Usage: ./interrogate.sh --resume-from <step> <session-name>"
    echo "   Example: ./interrogate.sh --resume-from 5 my-app"
    exit 1
  fi

  if [ "$step" -lt 1 ] || [ "$step" -gt 12 ]; then
    echo "❌ Invalid step number: $step (must be 1-12)"
    exit 1
  fi

  echo "Starting from step $step for session: $name"
  echo ""
  build_full "$name" "$step"
}

# Show pipeline status using library
show_pipeline_status() {
  local name="$1"

  if [ -z "$name" ]; then
    echo "❌ Session name required"
    echo "Usage: ./interrogate.sh --pipeline-status <session-name>"
    exit 1
  fi

  # Source the pipeline library
  source "$SCRIPT_DIR/pipeline-lib.sh"

  # Initialize to load state
  init_pipeline_state "$name"

  # Show status
  show_pipeline_status
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
  --credentials|-c)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./interrogate.sh --credentials <session-name>"
      exit 1
    fi
    gather_credentials "$2"
    exit 0
    ;;
  --repo|-r)
    ensure_repo "$2"
    exit 0
    ;;
  --services)
    setup_services "$2"
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
  --resume)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./interrogate.sh --resume <session-name>"
      exit 1
    fi
    resume_pipeline "$2"
    exit 0
    ;;
  --resume-from)
    resume_from_step "$2" "$3"
    exit 0
    ;;
  --pipeline-status)
    show_pipeline_status "$2"
    exit 0
    ;;
  --interrogate-only|-i)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./interrogate.sh --interrogate-only <session-name>"
      exit 1
    fi
    SESSION_NAME="$2"
    SESSION_DIR=".claude/interrogations/$SESSION_NAME"
    CONV_FILE="$SESSION_DIR/conversation.md"
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
        echo "  Full build:    ./interrogate.sh $SESSION_NAME"
        echo "  Start fresh:   rm -rf $SESSION_DIR && ./interrogate.sh --interrogate-only $SESSION_NAME"
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
    claude --dangerously-skip-permissions "/pm:interrogate $SESSION_NAME"

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
        echo "  Full build:    ./interrogate.sh $SESSION_NAME"
      else
        echo "Session paused."
        echo ""
        echo "Resume with: ./interrogate.sh --interrogate-only $SESSION_NAME"
      fi
    fi
    exit 0
    ;;
esac

# Default: Run full build pipeline (--build is now the default)
build_full "$SESSION_NAME"
