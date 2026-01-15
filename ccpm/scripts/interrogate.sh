#!/bin/bash
# interrogate.sh - Orchestrate structured discovery conversations
#
# Usage:
#   ./interrogate.sh [session-name]           # Start or resume session
#   ./interrogate.sh --list                   # List all sessions
#   ./interrogate.sh --status [name]          # Show session status
#   ./interrogate.sh --extract <name>         # Extract scope document
#   ./interrogate.sh --credentials <name>     # Gather credentials for integrations
#   ./interrogate.sh --repo [name]            # Ensure GitHub repo exists
#   ./interrogate.sh --services [name]        # Setup PostgreSQL and MinIO services
#   ./interrogate.sh --build <name>           # Full pipeline → batch process PRDs
#
# Pipeline:
#   services → schema → repo → interrogate → extract → credentials → roadmap → PRDs → batch-process → synthetic-test → remediation

set -e

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
  ./interrogate.sh --credentials <name>     Gather credentials for integrations
  ./interrogate.sh --repo [name]            Ensure GitHub repository exists
  ./interrogate.sh --services [name]        Setup PostgreSQL and MinIO services
  ./interrogate.sh --build <name>           Full pipeline: services → PRDs → batch-process
  ./interrogate.sh --help                   Show this help

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
 10. (auto) Synthetic persona testing       /pm:generate-personas → tests → feedback
 11. (auto) Generate remediation PRDs       /pm:generate-remediation

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
  echo ""

  # Show last exchange
  echo "Last question asked:"
  grep "^\*\*Claude:\*\*" "$conv" 2>/dev/null | tail -1 | sed 's/\*\*Claude:\*\* /  /'

  echo ""

  # Suggest next step based on status
  status=$(grep "^Status:" "$conv" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
  if [ "$status" = "complete" ]; then
    if [ -f "$scope" ]; then
      echo "Next: ./interrogate.sh --build $name  (generate roadmap → PRDs → batch-process)"
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
  claude --print "/pm:extract-findings $name"

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
  claude "/pm:gather-credentials $name"

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

# Full pipeline: services → schema → repo → interrogate → extract → credentials → roadmap → PRDs → batch-process → synthetic-test → remediation
build_full() {
  local name="$1"
  local conv=".claude/interrogations/$name/conversation.md"
  local scope=".claude/scopes/$name/00_scope_document.md"
  local creds_state=".claude/scopes/$name/credentials.yaml"
  local project_name
  project_name=$(basename "$(pwd)")

  echo "=== Full Pipeline: $name ==="
  echo ""
  echo "Pipeline: services → repo → interrogate → extract → credentials → roadmap → PRDs → batch → test → remediation"
  echo ""

  # Step 1: Setup Infrastructure Services
  echo "Step 1: Infrastructure Services (PostgreSQL, MinIO, CloudBeaver)"
  setup_services "$project_name"
  echo "Step 1: Services ✓"

  echo ""

  # Step 2: Create Interview Schema
  echo "Step 2: Create Database Schema"
  if [ -f "./.claude/scripts/create-interview-schema.sh" ]; then
    ./.claude/scripts/create-interview-schema.sh
    echo "Step 2: Schema ✓"
  else
    echo "Step 2: Schema script not found, skipping"
  fi

  echo ""

  # Step 3: Ensure GitHub repo
  echo "Step 3: GitHub Repository"
  ./.claude/scripts/ensure-github-repo.sh
  echo "Step 3: Repository ✓"

  echo ""

  # Step 4: Check/run interrogation
  if [ -f "$conv" ]; then
    status=$(grep "^Status:" "$conv" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    if [ "$status" = "complete" ]; then
      echo "Step 4: Interrogation ✓ (already complete)"
    else
      echo "Step 4: Resuming interrogation..."
      echo "---"
      claude "/pm:interrogate $name"
      echo "---"
    fi
  else
    echo "Step 4: Starting interrogation..."
    mkdir -p ".claude/interrogations/$name"
    echo "---"
    claude "/pm:interrogate $name"
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
  echo "Step 4: Interrogation ✓"
  echo ""

  # Step 5: Extract findings
  if [ -f "$scope" ]; then
    echo "Step 5: Scope document ✓ (already exists)"
    echo ""
    read -p "Regenerate scope document? (y/n): " regen
    if [[ "$regen" == "y" ]]; then
      echo "Regenerating..."
      claude --print "/pm:extract-findings $name"
    fi
  else
    echo "Step 5: Extracting findings..."
    echo "---"
    claude --print "/pm:extract-findings $name"
    echo "---"
  fi

  # Verify scope exists
  if [ ! -f "$scope" ]; then
    echo "❌ Scope document generation failed"
    exit 1
  fi

  echo ""
  echo "Step 5: Scope document ✓"
  echo ""

  # Step 6: Credential Gathering
  if [ -f "$creds_state" ] && [ -f ".env" ]; then
    echo "Step 6: Credentials ✓ (already gathered)"
    echo ""
    read -p "Regather credentials? (y/n): " regather
    if [[ "$regather" == "y" ]]; then
      echo "Regathering..."
      claude "/pm:gather-credentials $name"
    fi
  else
    echo "Step 6: Gathering credentials..."
    echo ""
    echo "Integrations detected in scope document will be configured."
    echo "---"
    claude "/pm:gather-credentials $name"
    echo "---"
  fi

  # Verify credentials exist (optional - warn but don't block)
  if [ ! -f ".env" ]; then
    echo "⚠️  No .env file found"
    echo ""
    read -p "Continue without credentials? (y/n): " continue_anyway
    if [[ "$continue_anyway" != "y" ]]; then
      echo ""
      echo "Pipeline stopped."
      echo "Run: ./interrogate.sh --credentials $name"
      exit 0
    fi
  else
    # Check for deferred credentials
    deferred=$(grep "deferred_credentials:" "$creds_state" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    if [ -n "$deferred" ] && [ "$deferred" != "0" ]; then
      echo "⚠️  $deferred credential(s) deferred"
      read -p "Continue with deferred credentials? (y/n): " continue_defer
      if [[ "$continue_defer" != "y" ]]; then
        echo ""
        echo "Complete credentials: ./interrogate.sh --credentials $name"
        exit 0
      fi
    fi
    echo "Step 6: Credentials ✓"
  fi

  echo ""

  # Step 7: Generate MVP Roadmap
  local roadmap=".claude/scopes/$name/07_roadmap.md"
  if [ -f "$roadmap" ]; then
    echo "Step 7: MVP Roadmap ✓ (already exists)"
    echo ""
    read -p "Regenerate roadmap? (y/n): " regen_roadmap
    if [[ "$regen_roadmap" == "y" ]]; then
      echo "Regenerating roadmap..."
      claude --print "/pm:roadmap-generate $name"
    fi
  else
    echo "Step 7: Generating MVP Roadmap..."
    echo "---"
    claude --print "/pm:roadmap-generate $name"
    echo "---"
  fi

  # Verify roadmap exists
  if [ ! -f "$roadmap" ]; then
    echo "❌ Roadmap generation failed"
    exit 1
  fi

  echo ""
  echo "Step 7: MVP Roadmap ✓"
  echo ""

  # Step 8: Decompose into PRDs
  local prds_dir=".claude/prds"
  echo "Step 8: Decomposing scope into PRDs..."
  echo "---"
  claude --print "/pm:scope-decompose $name --generate"
  echo "---"

  # Count PRDs created
  prd_count=$(ls -1 "$prds_dir"/*.md 2>/dev/null | wc -l)
  if [ "$prd_count" -eq 0 ]; then
    echo "❌ No PRDs generated"
    exit 1
  fi

  echo ""
  echo "Step 8: PRDs generated ✓ ($prd_count PRDs)"
  echo ""

  # Step 9: Batch process PRDs in order
  echo "Step 9: Batch Processing PRDs"
  echo ""
  echo "This will process all PRDs in dependency order:"
  echo "  - Parse each PRD into epics/issues"
  echo "  - Create GitHub issues"
  echo "  - Execute implementation"
  echo ""

  read -p "Start batch processing? (yes/no): " confirm_batch
  if [[ "$confirm_batch" != "yes" ]]; then
    echo ""
    echo "Pipeline stopped before batch processing."
    echo ""
    echo "Your PRDs are ready at: $prds_dir/"
    echo "Roadmap: $roadmap"
    echo ""
    echo "To process PRDs later:"
    echo "  /pm:batch-process"
    exit 0
  fi

  echo ""
  echo "=== Starting Batch Processing ==="
  echo ""

  # Run batch-process
  claude --dangerously-skip-permissions "/pm:batch-process"

  echo ""
  echo "Step 9: Batch Processing ✓"
  echo ""

  # Step 10: Synthetic Persona Testing
  echo "Step 10: Synthetic Persona Testing"
  echo ""
  echo "This will:"
  echo "  - Generate 10 synthetic personas from user journeys"
  echo "  - Create Playwright E2E test suite"
  echo "  - Run tests as each persona"
  echo "  - Generate synthetic user feedback"
  echo "  - Analyze feedback patterns"
  echo ""

  read -p "Run synthetic testing? (yes/no): " confirm_test
  if [[ "$confirm_test" == "yes" ]]; then
    echo ""
    echo "Generating synthetic personas..."
    claude --print "/pm:generate-personas $name --count 10"

    local personas_file=".claude/testing/personas/$name-personas.json"
    if [ ! -f "$personas_file" ]; then
      echo "❌ Persona generation failed"
      exit 1
    fi
    echo "Personas generated ✓"
    echo ""

    echo "Generating Playwright tests..."
    claude --print "/pm:generate-tests $name"

    local playwright_dir=".claude/testing/playwright"
    if [ ! -d "$playwright_dir" ]; then
      echo "❌ Test generation failed"
      exit 1
    fi
    echo "Tests generated ✓"
    echo ""

    # Run Playwright tests
    echo "Running Playwright tests..."
    if [ -f "$playwright_dir/package.json" ]; then
      (cd "$playwright_dir" && npm install 2>/dev/null || true)
      (cd "$playwright_dir" && npx playwright test --reporter=json > test-results.json 2>&1) || true
      echo "Tests executed ✓"
    else
      echo "⚠️  Playwright not configured - skipping test execution"
      echo "   Manual setup: cd $playwright_dir && npm init -y && npm i -D @playwright/test"
      # Create placeholder test results for feedback generation
      echo '{"suites":[],"stats":{"expected":0,"unexpected":0,"flaky":0,"skipped":0}}' > "$playwright_dir/test-results.json"
    fi
    echo ""

    echo "Generating synthetic feedback..."
    claude --print "/pm:generate-feedback $name"

    local feedback_file=".claude/testing/feedback/$name-feedback.json"
    if [ -f "$feedback_file" ]; then
      echo "Feedback generated ✓"
    else
      echo "⚠️  Feedback generation skipped"
    fi
    echo ""

    echo "Analyzing feedback patterns..."
    claude --print "/pm:analyze-feedback $name"

    local analysis_file=".claude/testing/feedback/$name-analysis.md"
    if [ -f "$analysis_file" ]; then
      echo "Analysis complete ✓"
    else
      echo "⚠️  Analysis skipped"
    fi

    echo ""
    echo "Step 10: Synthetic Testing ✓"
    echo ""

    # Step 11: Generate Remediation PRDs
    local issues_file=".claude/testing/feedback/$name-issues.json"
    if [ -f "$issues_file" ]; then
      echo "Step 11: Generating Remediation PRDs"
      echo ""
      echo "Creating PRDs to address feedback issues..."
      echo ""

      read -p "Generate remediation PRDs? (yes/no): " confirm_remediation
      if [[ "$confirm_remediation" == "yes" ]]; then
        claude --print "/pm:generate-remediation $name --max 10"

        echo ""
        echo "Step 11: Remediation PRDs ✓"
        echo ""

        # Count remediation PRDs
        remediation_count=$(ls -1 "$prds_dir"/*-fix-*.md "$prds_dir"/*-improve-*.md "$prds_dir"/*-add-*.md 2>/dev/null | wc -l)
        echo "Remediation PRDs generated: $remediation_count"
        echo ""

        read -p "Process remediation PRDs now? (yes/no): " confirm_remediation_batch
        if [[ "$confirm_remediation_batch" == "yes" ]]; then
          echo ""
          echo "Processing remediation PRDs..."
          claude --dangerously-skip-permissions "/pm:batch-process"
        fi
      else
        echo "Skipping remediation PRD generation."
      fi
    else
      echo "Step 11: Skipped (no issues file)"
    fi
  else
    echo "Skipping synthetic testing."
    echo "Run manually later:"
    echo "  /pm:generate-personas $name"
    echo "  /pm:generate-tests $name"
    echo "  /pm:generate-feedback $name"
    echo "  /pm:analyze-feedback $name"
    echo "  /pm:generate-remediation $name"
  fi

  echo ""
  echo "---"
  echo ""
  echo "=== Pipeline Complete ==="
  echo ""
  echo "Summary:"
  echo "  - Scope: .claude/scopes/$name/"
  echo "  - Roadmap: $roadmap"
  echo "  - PRDs: $prds_dir/ ($prd_count files)"
  if [ -f ".claude/testing/personas/$name-personas.json" ]; then
    echo "  - Personas: .claude/testing/personas/$name-personas.json"
  fi
  if [ -f ".claude/testing/feedback/$name-analysis.md" ]; then
    echo "  - Feedback Analysis: .claude/testing/feedback/$name-analysis.md"
  fi
  echo ""
  echo "Monitor progress:"
  echo "  /pm:status"
  echo "  /pm:epic-status <epic-name>"
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
claude "/pm:interrogate $SESSION_NAME"

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
