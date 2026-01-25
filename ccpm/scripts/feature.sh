#!/bin/bash
# feature.sh - Idea to Shipped Code Pipeline with Flow Diagram Verification
#
# This script extends interrogate.sh by adding a visual flow diagram verification
# step that allows users to confirm the discovered user journeys before proceeding.
#
# Individual Steps:
#   ./feature.sh --services [name]        # Step 1: Setup PostgreSQL, MinIO, CloudBeaver
#   ./feature.sh --schema [name]          # Step 2: Create database schema
#   ./feature.sh --repo [name]            # Step 3: Ensure GitHub repo exists
#   ./feature.sh --discover <name>        # Step 4: Run 12-section discovery
#   ./feature.sh --scope <name>           # Step 5: Create scope documents
#   ./feature.sh --flow <name>            # Step 5.5: Show flow diagram + confirm (NEW)
#   ./feature.sh --credentials [name]     # Step 6: Gather credentials
#   ./feature.sh --roadmap <name>         # Step 7: Generate MVP roadmap
#   ./feature.sh --generate-template <name> # Step 8: Generate K8s + code scaffolds
#   ./feature.sh --deploy-skeleton <name> # Step 9: Deploy skeleton application
#   ./feature.sh --decompose <name>       # Step 10: Decompose into PRDs
#   ./feature.sh --batch <name>           # Step 11: Batch process PRDs
#   ./feature.sh --deploy <name>          # Step 12: Deploy full application
#   ./feature.sh --synthetic <name>       # Step 13: Synthetic persona testing
#   ./feature.sh --remediation <name>     # Step 14: Generate remediation PRDs
#
# Pipeline Commands:
#   ./feature.sh [session-name]           # Run full pipeline
#   ./feature.sh --build <name>           # Run full pipeline (explicit)
#   ./feature.sh --resume <name>          # Resume from last step
#   ./feature.sh --resume-from <N> <name> # Resume from specific step
#
# Session Management:
#   ./feature.sh --list                   # List all sessions
#   ./feature.sh --status [name]          # Show session status
#   ./feature.sh --pipeline-status <name> # Show pipeline progress
#
# Pipeline Flow:
#   services → schema → repo → discover → scope → [FLOW VERIFY LOOP] → credentials → roadmap → template → skeleton → decompose → batch → deploy → synthetic → remediation

set -e

# Get script directory for sourcing library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Path to discovery.sh and interrogate.sh
DISCOVERY_SH="$SCRIPT_DIR/pm/discovery.sh"
INTERROGATE_SH="$SCRIPT_DIR/interrogate.sh"

# Path to flow diagram renderer
FLOW_DIAGRAM_JS="$SCRIPT_DIR/flow-diagram.js"

SESSION_NAME="${1:-$(date +%Y%m%d-%H%M%S)}"
SESSION_DIR=".claude/interrogations/$SESSION_NAME"
CONV_FILE="$SESSION_DIR/conversation.md"
SCOPE_DIR=".claude/scopes/$SESSION_NAME"

# Show help
show_help() {
  cat << 'EOF'
Feature Pipeline - Idea to Shipped Code with Flow Verification

Usage:
  ./feature.sh [session-name]             Full pipeline: services → ... → flow verify → ... → deploy
  ./feature.sh --help                     Show this help

Individual Steps (run independently):
   1. ./feature.sh --services [name]       Setup PostgreSQL, MinIO, CloudBeaver
   2. ./feature.sh --schema [name]         Create interview database schema
   3. ./feature.sh --repo [name]           Ensure GitHub repo exists
   4. ./feature.sh --discover <name>       Run 12-section discovery (INTERACTIVE)
   5. ./feature.sh --scope <name>          Create scope documents from discovery
 5.5. ./feature.sh --flow <name>           Show flow diagram + confirm (NEW)
   6. ./feature.sh --credentials [name]    Gather integration credentials
   7. ./feature.sh --roadmap <name>        Generate MVP roadmap
   8. ./feature.sh --generate-template <name> Generate K8s + code scaffolds
   9. ./feature.sh --deploy-skeleton <name>  Deploy skeleton application
  10. ./feature.sh --decompose <name>      Decompose into PRDs
  11. ./feature.sh --batch <name>          Batch process PRDs
  12. ./feature.sh --deploy <name>         Deploy full application
  13. ./feature.sh --synthetic <name>      Synthetic persona testing
  14. ./feature.sh --remediation <name>    Generate remediation PRDs

Pipeline Commands:
  ./feature.sh --build <name>             Run full pipeline from step 1
  ./feature.sh --resume <name>            Resume from last completed step
  ./feature.sh --resume-from <N> <name>   Resume from specific step (1-14)
  ./feature.sh --pipeline-status <name>   Show pipeline progress

Session Management:
  ./feature.sh --list                     List all sessions
  ./feature.sh --status [name]            Show session status

Flow Diagram Verification (Step 5.5):
  After discovery and scope creation, the pipeline shows ASCII flow diagrams
  representing the user journeys. You'll be asked to confirm:

    "Does this flow look right? (yes/no)"
    - If YES: Pipeline continues to credentials gathering
    - If NO:  Loops back to Step 4 (discovery) to refine requirements

  This ensures the system correctly understood your requirements before
  generating PRDs and building code.

Example - Run full pipeline:
  ./feature.sh my-new-app                 # Run full pipeline with verification

Example - Run steps independently:
  ./feature.sh --discover myapp           # Step 4: Run discovery
  ./feature.sh --scope myapp              # Step 5: Generate scope
  ./feature.sh --flow myapp               # Step 5.5: Verify flow diagrams

Output Files:
  .claude/scopes/<name>/sections/             12 discovery section files
  .claude/scopes/<name>/discovery.md          Merged discovery document
  .claude/scopes/<name>/00_scope_document.md  Comprehensive scope doc
  .claude/scopes/<name>/01_features.md        Feature catalog
  .claude/scopes/<name>/02_user_journeys.md   User journey maps
  .claude/scopes/<name>/04_technical_architecture.md   Tech stack, integrations
  .claude/scopes/<name>/07_roadmap.md         MVP roadmap with phases
  .claude/prds/<name>/*.md                    Generated PRDs
EOF
}

# List all sessions - delegate to interrogate.sh
list_sessions() {
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --list
  else
    echo "=== Discovery Sessions ==="
    echo ""
    if [ -d ".claude/scopes" ] && [ "$(ls -A .claude/scopes 2>/dev/null)" ]; then
      for dir in .claude/scopes/*/; do
        if [ -d "$dir" ]; then
          name=$(basename "$dir")
          echo "  $name"
        fi
      done
    else
      echo "No sessions found."
    fi
  fi
}

# Show session status - delegate to interrogate.sh
show_status() {
  local name="${1:-$SESSION_NAME}"

  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --status "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

# Delegate functions to interrogate.sh
run_discover() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --discover "$name"
  else
    echo "❌ interrogate.sh not found at: $INTERROGATE_SH"
    exit 1
  fi
}

create_scope() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --scope "$name"
  else
    echo "❌ interrogate.sh not found at: $INTERROGATE_SH"
    exit 1
  fi
}

setup_services() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --services "$name"
  else
    echo "⚠️ interrogate.sh not found, skipping services"
  fi
}

create_schema() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --schema "$name"
  else
    echo "⚠️ interrogate.sh not found, skipping schema"
  fi
}

ensure_repo() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --repo "$name"
  else
    echo "⚠️ interrogate.sh not found, skipping repo"
  fi
}

gather_credentials() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --credentials "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

generate_roadmap() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --roadmap "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

generate_template() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --generate-template "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

deploy_skeleton() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --deploy-skeleton "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

decompose_prds() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --decompose "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

batch_process() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --batch "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

deploy_app() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --deploy "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

synthetic_testing() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --synthetic "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

generate_remediation() {
  local name="$1"
  if [ -f "$INTERROGATE_SH" ]; then
    "$INTERROGATE_SH" --remediation "$name"
  else
    echo "❌ interrogate.sh not found"
    exit 1
  fi
}

# Flow diagram generation and display (Step 5.5)
show_flow_diagram() {
  local name="$1"

  if [ -z "$name" ]; then
    echo "❌ Session name required"
    echo "Usage: ./feature.sh --flow <session-name>"
    exit 1
  fi

  local scope_dir=".claude/scopes/$name"
  local journeys_file="$scope_dir/02_user_journeys.md"

  if [ ! -f "$journeys_file" ]; then
    echo "❌ User journeys not found: $journeys_file"
    echo ""
    echo "First run: ./feature.sh --scope $name"
    exit 1
  fi

  echo "=== Step 5.5: Flow Diagram ==="
  echo ""

  # Use Claude to generate and display flow diagrams
  claude --dangerously-skip-permissions --print "/pm:flow-diagram $name"
}

# Flow diagram verification loop (Step 5.5 with confirmation)
verify_flow() {
  local name="$1"
  local confirmed=false
  local iteration=0
  local max_iterations=5

  while [ "$confirmed" = "false" ] && [ "$iteration" -lt "$max_iterations" ]; do
    iteration=$((iteration + 1))

    echo ""
    echo "============================================="
    echo "  Step 5.5: Flow Diagram Verification"
    echo "  Iteration: $iteration / $max_iterations"
    echo "============================================="
    echo ""

    # Generate and display flow diagram
    claude --dangerously-skip-permissions --print "/pm:flow-diagram $name"

    echo ""
    echo "---"
    echo ""
    echo "The flow diagrams above show the user journeys discovered from your input."
    echo ""
    echo "Does this flow accurately represent what you want to build?"
    echo ""
    read -p "Continue with this flow? (yes/no): " response

    # Normalize response
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)

    case "$response" in
      yes|y|continue|ok|correct|"looks good"|good|proceed|confirm)
        confirmed=true
        echo ""
        echo "✅ Flow confirmed"
        echo ""

        # Record confirmation
        local state_dir=".claude/pipeline/$name"
        mkdir -p "$state_dir"
        echo "flow_verified: true" >> "$state_dir/state.yaml"
        echo "flow_verified_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$state_dir/state.yaml"
        echo "flow_iterations: $iteration" >> "$state_dir/state.yaml"
        ;;
      no|n|wrong|incorrect|redo|retry|change|modify)
        echo ""
        echo "Let's refine the requirements..."
        echo ""
        echo "What needs to change? (Brief description, then press Enter)"
        read -p "> " feedback

        # Record feedback
        local feedback_file=".claude/scopes/$name/flow-feedback-$iteration.md"
        mkdir -p ".claude/scopes/$name"
        cat > "$feedback_file" << EOF
# Flow Feedback - Iteration $iteration
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## User Feedback
$feedback

## Action
Re-running discovery with this feedback incorporated.
EOF

        echo ""
        echo "Re-running discovery with your feedback..."
        echo ""

        # Re-run discovery
        run_discover "$name"

        # Re-create scope
        create_scope "$name"

        # Loop continues - will show diagram again
        ;;
      *)
        echo ""
        echo "Please answer 'yes' to continue or 'no' to refine the requirements."
        # Don't increment iteration for invalid response
        iteration=$((iteration - 1))
        ;;
    esac
  done

  if [ "$confirmed" = "false" ]; then
    echo ""
    echo "⚠️ Maximum iterations ($max_iterations) reached."
    echo "Proceeding with current flow. You can refine later."
    echo ""
  fi
}

# Standalone flow verification (just show + ask once)
verify_flow_standalone() {
  local name="$1"

  if [ -z "$name" ]; then
    echo "❌ Session name required"
    echo "Usage: ./feature.sh --flow <session-name>"
    exit 1
  fi

  local scope_dir=".claude/scopes/$name"
  local journeys_file="$scope_dir/02_user_journeys.md"

  if [ ! -f "$journeys_file" ]; then
    echo "❌ User journeys not found: $journeys_file"
    echo ""
    echo "First run: ./feature.sh --scope $name"
    exit 1
  fi

  echo "=== Flow Diagram Verification: $name ==="
  echo ""

  # Generate and display flow diagram
  claude --dangerously-skip-permissions --print "/pm:flow-diagram $name"

  echo ""
  echo "---"
  echo ""
  echo "Does this flow accurately represent what you want to build?"
  echo ""
  read -p "Confirm flow? (yes/no): " response

  response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)

  case "$response" in
    yes|y|continue|ok|correct|"looks good"|good|proceed|confirm)
      echo ""
      echo "✅ Flow confirmed"
      echo ""
      echo "Next: ./feature.sh --credentials $name"
      ;;
    *)
      echo ""
      echo "Flow not confirmed."
      echo ""
      echo "To refine: ./feature.sh --discover $name"
      echo "Then:      ./feature.sh --scope $name"
      echo "Then:      ./feature.sh --flow $name"
      ;;
  esac
}

# Full pipeline with flow verification
build_full() {
  local name="$1"
  local start_step="${2:-1}"

  echo "=== Feature Pipeline: $name ==="
  echo ""
  echo "Pipeline: services → schema → repo → discover → scope → [FLOW VERIFY] → credentials → roadmap → template → skeleton → decompose → batch → deploy → synthetic → remediation"
  echo ""

  # Step 1: Services
  if [ "$start_step" -le 1 ]; then
    echo "--- Step 1: Setup Services ---"
    setup_services "$name"
    update_pipeline_state "$name" 1
  fi

  # Step 2: Schema
  if [ "$start_step" -le 2 ]; then
    echo "--- Step 2: Create Schema ---"
    create_schema "$name"
    update_pipeline_state "$name" 2
  fi

  # Step 3: Repo
  if [ "$start_step" -le 3 ]; then
    echo "--- Step 3: Ensure Repo ---"
    ensure_repo "$name"
    update_pipeline_state "$name" 3
  fi

  # Step 4: Discovery
  if [ "$start_step" -le 4 ]; then
    echo "--- Step 4: Discovery ---"
    run_discover "$name"
    update_pipeline_state "$name" 4
  fi

  # Step 5: Scope
  if [ "$start_step" -le 5 ]; then
    echo "--- Step 5: Create Scope ---"
    create_scope "$name"
    update_pipeline_state "$name" 5
  fi

  # Step 5.5: Flow Diagram Verification Loop (NEW)
  if [ "$start_step" -le 5 ]; then
    verify_flow "$name"
  fi

  # Step 6: Credentials
  if [ "$start_step" -le 6 ]; then
    echo "--- Step 6: Gather Credentials ---"
    gather_credentials "$name"
    update_pipeline_state "$name" 6
  fi

  # Step 7: Roadmap
  if [ "$start_step" -le 7 ]; then
    echo "--- Step 7: Generate Roadmap ---"
    generate_roadmap "$name"
    update_pipeline_state "$name" 7
  fi

  # Step 8: Template
  if [ "$start_step" -le 8 ]; then
    echo "--- Step 8: Generate Templates ---"
    generate_template "$name"
    update_pipeline_state "$name" 8
  fi

  # Step 9: Skeleton
  if [ "$start_step" -le 9 ]; then
    echo "--- Step 9: Deploy Skeleton ---"
    deploy_skeleton "$name"
    update_pipeline_state "$name" 9
  fi

  # Step 10: Decompose
  if [ "$start_step" -le 10 ]; then
    echo "--- Step 10: Decompose into PRDs ---"
    decompose_prds "$name"
    update_pipeline_state "$name" 10
  fi

  # Step 11: Batch
  if [ "$start_step" -le 11 ]; then
    echo "--- Step 11: Batch Process PRDs ---"
    batch_process "$name"
    update_pipeline_state "$name" 11
  fi

  # Step 12: Deploy
  if [ "$start_step" -le 12 ]; then
    echo "--- Step 12: Deploy Application ---"
    deploy_app "$name"
    update_pipeline_state "$name" 12
  fi

  # Step 13: Synthetic Testing
  if [ "$start_step" -le 13 ]; then
    echo "--- Step 13: Synthetic Testing ---"
    synthetic_testing "$name"
    update_pipeline_state "$name" 13
  fi

  # Step 14: Remediation
  if [ "$start_step" -le 14 ]; then
    echo "--- Step 14: Generate Remediation ---"
    generate_remediation "$name"
    update_pipeline_state "$name" 14
  fi

  # Final summary
  echo ""
  echo "=== Pipeline Complete ==="
  echo ""
  echo "Session: $name"
  echo ""
  echo "Outputs:"
  echo "  - Scope: .claude/scopes/$name/"
  [ -f ".claude/scopes/$name/07_roadmap.md" ] && echo "  - Roadmap: .claude/scopes/$name/07_roadmap.md"
  echo "  - PRDs: .claude/prds/$name/"
  [ -f ".claude/testing/personas/$name-personas.json" ] && echo "  - Personas: .claude/testing/personas/$name-personas.json"
  [ -f ".claude/testing/feedback/$name-analysis.md" ] && echo "  - Feedback: .claude/testing/feedback/$name-analysis.md"
}

# Update pipeline state file
update_pipeline_state() {
  local name="$1"
  local step="$2"
  local state_dir=".claude/pipeline/$name"
  local state_file="$state_dir/state.yaml"

  mkdir -p "$state_dir"

  if [ ! -f "$state_file" ]; then
    cat > "$state_file" << EOF
name: $name
status: in_progress
started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_completed_step: $step
updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
  else
    # Update existing file
    sed -i "s/^last_completed_step:.*/last_completed_step: $step/" "$state_file"
    sed -i "s/^updated:.*/updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")/" "$state_file"
  fi
}

# Resume pipeline from last step
resume_pipeline() {
  local name="$1"
  local state_file=".claude/pipeline/$name/state.yaml"

  if [ ! -f "$state_file" ]; then
    echo "❌ No pipeline state found for: $name"
    echo ""
    echo "Start fresh with: ./feature.sh --build $name"
    exit 1
  fi

  local last_step
  last_step=$(grep "^last_completed_step:" "$state_file" 2>/dev/null | cut -d: -f2 | tr -d ' ')

  if [ -z "$last_step" ] || [ "$last_step" = "0" ]; then
    echo "No steps completed yet. Starting from step 1."
    build_full "$name" 1
  elif [ "$last_step" = "14" ]; then
    echo "Pipeline already complete for: $name"
    echo ""
    echo "To restart: ./feature.sh --resume-from 1 $name"
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
    echo "❌ Usage: ./feature.sh --resume-from <step> <session-name>"
    echo "   Example: ./feature.sh --resume-from 5 my-app"
    exit 1
  fi

  if [ "$step" -lt 1 ] || [ "$step" -gt 14 ]; then
    echo "❌ Invalid step number: $step (must be 1-14)"
    exit 1
  fi

  echo "Starting from step $step for session: $name"
  echo ""
  build_full "$name" "$step"
}

# Show pipeline status
show_pipeline_status() {
  local name="$1"

  if [ -z "$name" ]; then
    echo "❌ Session name required"
    echo "Usage: ./feature.sh --pipeline-status <session-name>"
    exit 1
  fi

  local state_file=".claude/pipeline/$name/state.yaml"

  if [ ! -f "$state_file" ]; then
    echo "No pipeline state found for: $name"
    return
  fi

  echo "=== Pipeline Status: $name ==="
  echo ""

  local status last_step started updated
  status=$(grep "^status:" "$state_file" 2>/dev/null | cut -d: -f2 | tr -d ' ')
  last_step=$(grep "^last_completed_step:" "$state_file" 2>/dev/null | cut -d: -f2 | tr -d ' ')
  started=$(grep "^started:" "$state_file" 2>/dev/null | cut -d: -f2- | tr -d ' ')
  updated=$(grep "^updated:" "$state_file" 2>/dev/null | cut -d: -f2- | tr -d ' ')

  echo "Status: $status"
  echo "Progress: Step $last_step / 14"
  echo "Started: $started"
  echo "Updated: $updated"
  echo ""

  # Show step names
  local steps=("Services" "Schema" "Repo" "Discover" "Scope" "Credentials" "Roadmap" "Template" "Skeleton" "Decompose" "Batch" "Deploy" "Synthetic" "Remediation")

  for i in "${!steps[@]}"; do
    local step_num=$((i + 1))
    local step_name="${steps[$i]}"
    local status_icon="○"

    if [ "$step_num" -le "$last_step" ]; then
      status_icon="✓"
    elif [ "$step_num" -eq "$((last_step + 1))" ]; then
      status_icon="→"
    fi

    # Note: Step 5.5 (Flow Verify) is between steps 5 and 6
    if [ "$step_num" -eq 6 ] && [ "$last_step" -ge 5 ]; then
      local flow_verified
      flow_verified=$(grep "^flow_verified:" "$state_file" 2>/dev/null | cut -d: -f2 | tr -d ' ')
      if [ "$flow_verified" = "true" ]; then
        echo "  5.5. ✓ Flow Verify"
      elif [ "$last_step" -eq 5 ]; then
        echo "  5.5. → Flow Verify"
      else
        echo "  5.5. ○ Flow Verify"
      fi
    fi

    printf "  %2d. %s %s\n" "$step_num" "$status_icon" "$step_name"
  done
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
  --discover|-d)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./feature.sh --discover <session-name>"
      exit 1
    fi
    run_discover "$2"
    exit 0
    ;;
  --scope|-e)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./feature.sh --scope <session-name>"
      exit 1
    fi
    create_scope "$2"
    exit 0
    ;;
  --flow|-f)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./feature.sh --flow <session-name>"
      exit 1
    fi
    verify_flow_standalone "$2"
    exit 0
    ;;
  --credentials|-c)
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
  --schema)
    create_schema "$2"
    exit 0
    ;;
  --roadmap)
    generate_roadmap "$2"
    exit 0
    ;;
  --generate-template)
    generate_template "$2"
    exit 0
    ;;
  --deploy-skeleton)
    deploy_skeleton "$2"
    exit 0
    ;;
  --decompose|--prds)
    decompose_prds "$2"
    exit 0
    ;;
  --batch)
    batch_process "$2"
    exit 0
    ;;
  --deploy)
    deploy_app "$2"
    exit 0
    ;;
  --synthetic|--test)
    synthetic_testing "$2"
    exit 0
    ;;
  --remediation|--fix)
    generate_remediation "$2"
    exit 0
    ;;
  --build|-b)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./feature.sh --build <session-name>"
      exit 1
    fi
    build_full "$2"
    exit 0
    ;;
  --resume)
    if [ -z "$2" ]; then
      echo "❌ Error: Session name required"
      echo "Usage: ./feature.sh --resume <session-name>"
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
esac

# Default: Run full build pipeline
build_full "$SESSION_NAME"
