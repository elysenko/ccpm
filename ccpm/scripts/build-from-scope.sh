#!/bin/bash
# build-from-scope.sh - Activate Loki Mode to build application from scope document
#
# Usage:
#   ./build-from-scope.sh <scope-name>         # Build from existing scope
#   ./build-from-scope.sh --full <session>     # Full pipeline: interrogate → extract → build
#
# Prerequisites:
#   - Scope document must exist in .claude/scopes/<name>/00_scope_document.md
#   - Claude Code must be available
#   - Requires --dangerously-skip-permissions flag for Loki Mode

set -e

SCOPE_NAME="$1"
FULL_PIPELINE=false

# Show help
show_help() {
  cat << 'EOF'
Build From Scope - Activate Loki Mode to build application

Usage:
  ./build-from-scope.sh <scope-name>         Build from existing scope document
  ./build-from-scope.sh --full <session>     Full pipeline: interrogate → extract → build
  ./build-from-scope.sh --help               Show this help

Prerequisites:
  - For existing scope: .claude/scopes/<name>/00_scope_document.md must exist
  - For full pipeline: Will create scope from interrogation session
  - Credentials: .env file with integration credentials
  - Loki Mode requires: --dangerously-skip-permissions flag

Full Pipeline Flow:
  1. setup-services             → PostgreSQL, MinIO, CloudBeaver
  2. create-interview-schema    → Interview database tables
  3. ensure-github-repo         → GitHub repository
  4. /pm:interrogate <session>  → conversation.md
  5. /pm:extract-findings       → scope document
  6. /pm:gather-credentials     → .env credentials
  7. Loki Mode                  → built application

Examples:
  ./build-from-scope.sh invoice-system
  ./build-from-scope.sh --full new-project

WARNING: Loki Mode is autonomous and will make significant changes to your codebase.
EOF
}

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  show_help
  exit 0
fi

# Check for full pipeline flag
if [[ "$1" == "--full" ]]; then
  FULL_PIPELINE=true
  SCOPE_NAME="$2"
fi

# Validate arguments
if [[ -z "$SCOPE_NAME" ]]; then
  echo "❌ Error: Scope name required"
  echo ""
  echo "Usage: ./build-from-scope.sh <scope-name>"
  echo "       ./build-from-scope.sh --full <session-name>"
  echo ""
  echo "Available scopes:"
  ls -1 .claude/scopes/ 2>/dev/null || echo "  (none)"
  exit 1
fi

SCOPE_DIR=".claude/scopes/$SCOPE_NAME"
SCOPE_DOC="$SCOPE_DIR/00_scope_document.md"
CONV_DIR=".claude/interrogations/$SCOPE_NAME"
CONV_FILE="$CONV_DIR/conversation.md"

# Full pipeline: services → schema → repo → interrogate → extract → credentials → Loki Mode
if [[ "$FULL_PIPELINE" == "true" ]]; then
  echo "=== Full Pipeline Mode ==="
  echo ""
  echo "Pipeline: services → schema → repo → interrogate → extract → credentials → Loki Mode"
  echo ""

  # Step 1: Setup infrastructure services
  echo "Step 1: Infrastructure Services (PostgreSQL, MinIO, CloudBeaver)..."
  project_name=$(basename "$(pwd)")
  ./.claude/scripts/setup-service.sh all "$project_name" --project="$project_name"
  echo ""
  echo "Pulling credentials into .env..."
  NAMESPACE="$project_name" ./.claude/scripts/setup-env-from-k8s.sh
  echo "Step 1: Services ✓"

  # Step 2: Create Interview Schema
  echo ""
  echo "Step 2: Database Schema..."
  if [ -f "./.claude/scripts/create-interview-schema.sh" ]; then
    ./.claude/scripts/create-interview-schema.sh
    echo "Step 2: Schema ✓"
  else
    echo "Step 2: Schema script not found, skipping"
  fi

  # Step 3: Ensure GitHub repo
  echo ""
  echo "Step 3: GitHub Repository..."
  ./.claude/scripts/ensure-github-repo.sh
  echo "Step 3: Repository ✓"

  # Step 4: Check if interrogation exists, if not run it
  echo ""
  if [[ -f "$CONV_FILE" ]]; then
    status=$(grep "^Status:" "$CONV_FILE" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
    if [[ "$status" != "complete" ]]; then
      echo "Step 4: Completing interrogation..."
      echo "---"
      ./.claude/scripts/interrogate.sh "$SCOPE_NAME"
      echo "---"
    else
      echo "Step 4: Interrogation already complete ✓"
    fi
  else
    echo "Step 4: Running interrogation..."
    echo "---"
    ./.claude/scripts/interrogate.sh "$SCOPE_NAME"
    echo "---"
  fi
  echo "Step 4: Interrogation ✓"

  # Step 5: Extract findings and generate scope document
  echo ""
  echo "Step 5: Extracting findings and generating scope document..."
  echo "---"
  claude --print "/pm:extract-findings $SCOPE_NAME"
  echo "---"

  # Verify scope document was created
  if [[ ! -f "$SCOPE_DOC" ]]; then
    echo "❌ Error: Scope document was not generated"
    echo "Check .claude/scopes/$SCOPE_NAME/ for partial output"
    exit 1
  fi

  echo ""
  echo "Step 5: Scope document generated ✓"

  # Step 6: Gather credentials
  CREDS_STATE="$SCOPE_DIR/credentials.yaml"
  if [[ -f "$CREDS_STATE" ]] && [[ -f ".env" ]]; then
    echo "Step 6: Credentials already gathered ✓"
  else
    echo ""
    echo "Step 6: Gathering credentials..."
    echo "---"
    claude "/pm:gather-credentials $SCOPE_NAME"
    echo "---"
    echo "Step 6: Credentials gathered ✓"
  fi
fi

# Verify scope document exists
if [[ ! -f "$SCOPE_DOC" ]]; then
  echo "❌ Error: Scope document not found: $SCOPE_DOC"
  echo ""
  echo "Either:"
  echo "  1. Run extract-findings first: /pm:extract-findings $SCOPE_NAME"
  echo "  2. Use full pipeline: ./build-from-scope.sh --full $SCOPE_NAME"
  exit 1
fi

# Show scope summary
echo ""
echo "=== Build From Scope: $SCOPE_NAME ==="
echo ""
echo "Scope Document: $SCOPE_DOC"
echo ""

# Extract some stats from scope document
features=$(grep -c "^### Feature\|^| F-" "$SCOPE_DOC" 2>/dev/null || echo "?")
journeys=$(grep -c "^### Journey\|^| J-" "$SCOPE_DOC" 2>/dev/null || echo "?")
risks=$(grep -c "^| R-" "$SCOPE_DOC" 2>/dev/null || echo "?")

echo "Scope Summary:"
echo "  Features: ~$features"
echo "  Journeys: ~$journeys"
echo "  Risks: ~$risks"
echo ""

# Validate credentials
CREDS_STATE="$SCOPE_DIR/credentials.yaml"
if [[ -f ".env" ]] && [[ -f "$CREDS_STATE" ]]; then
  # Check for deferred credentials
  deferred=$(grep "deferred_credentials:" "$CREDS_STATE" 2>/dev/null | cut -d: -f2 | tr -d ' ')
  total=$(grep "total_credentials:" "$CREDS_STATE" 2>/dev/null | cut -d: -f2 | tr -d ' ')

  echo "Credentials:"
  echo "  Total: $total"
  if [[ -n "$deferred" ]] && [[ "$deferred" != "0" ]]; then
    echo "  ⚠️  Deferred: $deferred"
    echo ""
    read -p "Continue with deferred credentials? (yes/no): " continue_defer
    if [[ "$continue_defer" != "yes" ]]; then
      echo ""
      echo "Complete credentials first: ./interrogate.sh --credentials $SCOPE_NAME"
      exit 0
    fi
  else
    echo "  Status: Complete ✓"
  fi
  echo ""
else
  echo "⚠️  Credentials not gathered"
  echo ""
  echo "Integrations in your scope document may require credentials."
  echo "Run: ./interrogate.sh --credentials $SCOPE_NAME"
  echo ""
  read -p "Continue without credentials? (yes/no): " continue_anyway
  if [[ "$continue_anyway" != "yes" ]]; then
    exit 0
  fi
  echo ""
fi

# Check GitHub repo is configured
if ! git remote get-url origin &> /dev/null; then
  echo "⚠️  No remote origin configured"
  echo ""
  read -p "Set up GitHub repository? (y/n): " setup_repo
  if [[ "$setup_repo" == "y" ]]; then
    ./.claude/scripts/ensure-github-repo.sh
    echo ""
  fi
fi

# Warning about Loki Mode
echo "⚠️  WARNING: Loki Mode Activation"
echo ""
echo "Loki Mode is an autonomous multi-agent system that will:"
echo "  - Generate code across multiple files"
echo "  - Create database schemas and migrations"
echo "  - Set up infrastructure and deployment"
echo "  - Run tests and validate functionality"
echo ""
echo "This requires --dangerously-skip-permissions flag."
echo ""

# Confirm before proceeding
read -p "Proceed with Loki Mode build? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "=== Activating Loki Mode ==="
echo ""

# Prepare Loki Mode prompt
LOKI_PROMPT=$(cat << EOF
Loki Mode

Build the application defined in this scope document:

$(cat "$SCOPE_DOC")

---

Additional context files are in: .claude/scopes/$SCOPE_NAME/
- 01_features.md - Feature catalog
- 02_user_journeys.md - User journey maps
- 03_nfr_requirements.md - Non-functional requirements
- 04_technical_architecture.md - Tech stack and integrations
- 05_risk_assessment.md - Risk analysis
- 06_gap_analysis.md - Open questions (resolve as needed)
- credentials.yaml - Credential collection metadata

Credentials are pre-configured in .env file. Use environment variables for integration credentials.
Template available in .env.template for reference.

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

# Write prompt to temp file for claude
PROMPT_FILE=$(mktemp)
echo "$LOKI_PROMPT" > "$PROMPT_FILE"

# Launch Claude with Loki Mode
# Note: User must have --dangerously-skip-permissions configured
echo "Launching Claude Code with Loki Mode..."
echo "---"
echo ""

claude --dangerously-skip-permissions < "$PROMPT_FILE"

# Cleanup
rm -f "$PROMPT_FILE"

echo ""
echo "---"
echo ""
echo "=== Loki Mode Complete ==="
echo ""
echo "Review the generated application and run any remaining tasks."
