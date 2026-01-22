#!/usr/bin/env bash
# sync-interview-to-db.sh - Parse markdown files and sync to database
#
# Reads interrogation output (conversation.md, scope files) and inserts
# into database tables. Idempotent - uses upsert logic.
#
# Usage:
#   ./sync-interview-to-db.sh <session-name>
#   ./sync-interview-to-db.sh <session-name> --dry-run   # Show what would be inserted
#   ./sync-interview-to-db.sh <session-name> --force     # Re-sync even if complete

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Globals
SESSION=""
DRY_RUN=false
FORCE=false
CONV_FILE=""
SCOPE_DIR=""

# Counters
FEATURES_SYNCED=0
JOURNEYS_SYNCED=0
USER_TYPES_SYNCED=0
INTEGRATIONS_SYNCED=0
CONCERNS_SYNCED=0

usage() {
  cat << 'EOF'
Sync Interview to Database - Parse markdown and insert to PostgreSQL

Usage:
  ./sync-interview-to-db.sh <session-name>
  ./sync-interview-to-db.sh <session-name> --dry-run
  ./sync-interview-to-db.sh <session-name> --force

Options:
  --dry-run    Show what would be inserted without executing
  --force      Re-sync even if session appears complete

Sources (in order of preference):
  1. .claude/scopes/<session>/01_features.md (structured)
  2. .claude/scopes/<session>/02_user_journeys.md (structured)
  3. .claude/interrogations/<session>/conversation.md (raw)

Target Tables:
  - feature
  - journey
  - journey_steps_detailed
  - user_type
  - user_type_feature
  - integration
  - cross_cutting_concern
EOF
  exit 1
}

log() {
  echo -e "${BLUE}[sync]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[sync] ✓${NC} $1"
}

log_error() {
  echo -e "${RED}[sync] ✗${NC} $1" >&2
}

log_warn() {
  echo -e "${YELLOW}[sync] ⚠${NC} $1"
}

log_dry() {
  echo -e "${YELLOW}[dry-run]${NC} $1"
}

# Load database credentials from .env
load_db_credentials() {
  if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/.env"
    set +a
  fi

  # Set defaults
  POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
  POSTGRES_PORT="${POSTGRES_PORT:-5432}"
  POSTGRES_USER="${POSTGRES_USER:-postgres}"
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
  POSTGRES_DB="${POSTGRES_DB:-$(basename "${PROJECT_ROOT}")}"
}

# Execute SQL query
db_exec() {
  local -r sql="$1"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "SQL: ${sql:0:100}..."
    return 0
  fi

  PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h "${POSTGRES_HOST}" \
    -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -c "${sql}" 2>/dev/null
}

# Execute SQL query and return result
db_query() {
  local -r sql="$1"

  PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h "${POSTGRES_HOST}" \
    -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -t -A -c "${sql}" 2>/dev/null || echo ""
}

# Escape string for SQL
sql_escape() {
  local -r str="$1"
  echo "${str}" | sed "s/'/''/g"
}

# Check if database is accessible
check_db_connection() {
  log "Checking database connection..."

  if ! db_query "SELECT 1" > /dev/null; then
    log_error "Cannot connect to database"
    log_error "Host: ${POSTGRES_HOST}:${POSTGRES_PORT}"
    log_error "Database: ${POSTGRES_DB}"
    exit 1
  fi

  log_success "Database connected"
}

# Parse features from 01_features.md (structured format)
parse_features_structured() {
  local -r file="$1"

  log "Parsing features from: ${file}"

  local in_details=false
  local current_id=""
  local current_name=""
  local current_desc=""
  local current_priority="medium"
  local current_complexity="medium"

  while IFS= read -r line; do
    # Detect feature header: ### F-001: Name
    if [[ "${line}" =~ ^###[[:space:]]+(F-[0-9]+):[[:space:]]*(.+)$ ]]; then
      # Save previous feature if exists
      if [[ -n "${current_id}" ]]; then
        insert_feature "${current_id}" "${current_name}" "${current_desc}" "${current_priority}" "${current_complexity}"
      fi

      current_id="${BASH_REMATCH[1]}"
      current_name="${BASH_REMATCH[2]}"
      current_desc=""
      current_priority="medium"
      current_complexity="medium"
      in_details=true
      continue
    fi

    # Parse description
    if [[ "${in_details}" == "true" ]] && [[ "${line}" =~ ^\*\*Description:\*\*[[:space:]]*(.+)$ ]]; then
      current_desc="${BASH_REMATCH[1]}"
      continue
    fi

    # Parse priority
    if [[ "${in_details}" == "true" ]] && [[ "${line}" =~ ^\*\*Priority:\*\*[[:space:]]*(.+)$ ]]; then
      current_priority="${BASH_REMATCH[1]}"
      continue
    fi

    # Parse complexity
    if [[ "${in_details}" == "true" ]] && [[ "${line}" =~ ^\*\*Complexity:\*\*[[:space:]]*(.+)$ ]]; then
      current_complexity="${BASH_REMATCH[1]}"
      continue
    fi

    # End of feature section
    if [[ "${in_details}" == "true" ]] && [[ "${line}" =~ ^---$ ]]; then
      in_details=false
    fi
  done < "${file}"

  # Save last feature
  if [[ -n "${current_id}" ]]; then
    insert_feature "${current_id}" "${current_name}" "${current_desc}" "${current_priority}" "${current_complexity}"
  fi
}

# Parse features from conversation.md (raw format)
# Looks for patterns like: [F-001] Name - Description
parse_features_raw() {
  local -r file="$1"

  log "Parsing features from conversation: ${file}"

  local feature_num=1

  while IFS= read -r line; do
    # Pattern: [F-001] Name - Description
    if [[ "${line}" =~ ^\[?(F-[0-9]+)\]?[[:space:]]+([^-]+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
      local id="${BASH_REMATCH[1]}"
      local name="${BASH_REMATCH[2]}"
      local desc="${BASH_REMATCH[3]}"
      name=$(echo "${name}" | xargs)  # trim
      desc=$(echo "${desc}" | xargs)
      insert_feature "${id}" "${name}" "${desc}" "medium" "medium"
      continue
    fi

    # Pattern: N. [F-001] Name - Description (numbered list)
    if [[ "${line}" =~ ^[0-9]+\.[[:space:]]+\[?(F-[0-9]+)\]?[[:space:]]+([^-]+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
      local id="${BASH_REMATCH[1]}"
      local name="${BASH_REMATCH[2]}"
      local desc="${BASH_REMATCH[3]}"
      name=$(echo "${name}" | xargs)
      desc=$(echo "${desc}" | xargs)
      insert_feature "${id}" "${name}" "${desc}" "medium" "medium"
      continue
    fi

    # Pattern: N. Name - Description (generate ID)
    if [[ "${line}" =~ ^[0-9]+\.[[:space:]]+([^-]+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
      # Check if we're in a Features section
      local name="${BASH_REMATCH[1]}"
      local desc="${BASH_REMATCH[2]}"
      name=$(echo "${name}" | xargs)
      desc=$(echo "${desc}" | xargs)

      # Skip if looks like a journey (has "Actor:" or "Goal:")
      if [[ "${line}" =~ Actor:|Goal: ]]; then
        continue
      fi

      local id
      id=$(printf "F-%03d" "${feature_num}")
      insert_feature "${id}" "${name}" "${desc}" "medium" "medium"
      ((feature_num++))
    fi
  done < "${file}"
}

# Insert feature into database
insert_feature() {
  local -r feature_id="$1"
  local -r name="$2"
  local -r description="$3"
  local -r priority="$4"
  local -r complexity="$5"

  local -r escaped_name=$(sql_escape "${name}")
  local -r escaped_desc=$(sql_escape "${description}")

  local sql="SELECT upsert_feature(
    '${SESSION}',
    '${escaped_name}',
    '${escaped_desc}',
    'sync'
  );"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "INSERT feature: ${feature_id} - ${name}"
  else
    db_exec "${sql}"
    log "  Feature: ${feature_id} - ${name}"
  fi

  ((FEATURES_SYNCED++))
}

# Parse journeys from 02_user_journeys.md (structured format)
parse_journeys_structured() {
  local -r file="$1"

  log "Parsing journeys from: ${file}"

  local current_id=""
  local current_name=""
  local current_actor=""
  local current_trigger=""
  local current_goal=""
  local in_journey=false

  while IFS= read -r line; do
    # Detect journey header: ### J-001: Name
    if [[ "${line}" =~ ^###[[:space:]]+(J-[0-9]+):[[:space:]]*(.+)$ ]]; then
      # Save previous journey if exists
      if [[ -n "${current_id}" ]]; then
        insert_journey "${current_id}" "${current_name}" "${current_actor}" "${current_trigger}" "${current_goal}"
      fi

      current_id="${BASH_REMATCH[1]}"
      current_name="${BASH_REMATCH[2]}"
      current_actor=""
      current_trigger=""
      current_goal=""
      in_journey=true
      continue
    fi

    # Parse actor
    if [[ "${in_journey}" == "true" ]] && [[ "${line}" =~ ^\*\*Actor:\*\*[[:space:]]*(.+)$ ]]; then
      current_actor="${BASH_REMATCH[1]}"
      continue
    fi

    # Parse trigger
    if [[ "${in_journey}" == "true" ]] && [[ "${line}" =~ ^\*\*Trigger:\*\*[[:space:]]*(.+)$ ]]; then
      current_trigger="${BASH_REMATCH[1]}"
      continue
    fi

    # Parse goal
    if [[ "${in_journey}" == "true" ]] && [[ "${line}" =~ ^\*\*Goal:\*\*[[:space:]]*(.+)$ ]]; then
      current_goal="${BASH_REMATCH[1]}"
      continue
    fi

    # End of journey section
    if [[ "${in_journey}" == "true" ]] && [[ "${line}" =~ ^---$ ]]; then
      in_journey=false
    fi
  done < "${file}"

  # Save last journey
  if [[ -n "${current_id}" ]]; then
    insert_journey "${current_id}" "${current_name}" "${current_actor}" "${current_trigger}" "${current_goal}"
  fi
}

# Parse journeys from conversation.md (raw format)
parse_journeys_raw() {
  local -r file="$1"

  log "Parsing journeys from conversation: ${file}"

  local journey_num=1

  while IFS= read -r line; do
    # Pattern: [J-001] Name (Actor: X)
    if [[ "${line}" =~ ^\[?(J-[0-9]+)\]?[[:space:]]+([^(]+)\(Actor:[[:space:]]*([^)]+)\) ]]; then
      local id="${BASH_REMATCH[1]}"
      local name="${BASH_REMATCH[2]}"
      local actor="${BASH_REMATCH[3]}"
      name=$(echo "${name}" | xargs)
      actor=$(echo "${actor}" | xargs)
      insert_journey "${id}" "${name}" "${actor}" "" ""
      continue
    fi

    # Pattern: N. [J-001] Name (Actor: X)
    if [[ "${line}" =~ ^[0-9]+\.[[:space:]]+\[?(J-[0-9]+)\]?[[:space:]]+([^(]+)\(Actor:[[:space:]]*([^)]+)\) ]]; then
      local id="${BASH_REMATCH[1]}"
      local name="${BASH_REMATCH[2]}"
      local actor="${BASH_REMATCH[3]}"
      name=$(echo "${name}" | xargs)
      actor=$(echo "${actor}" | xargs)
      insert_journey "${id}" "${name}" "${actor}" "" ""
      continue
    fi

    # Pattern with Goal on same line
    if [[ "${line}" =~ Goal:[[:space:]]*(.+)$ ]] && [[ -n "${current_journey_name:-}" ]]; then
      # Update last journey with goal
      local goal="${BASH_REMATCH[1]}"
      goal=$(echo "${goal}" | xargs)
      # Note: would need to track and update, simplified for now
    fi
  done < "${file}"
}

# Insert journey into database
insert_journey() {
  local -r journey_id="$1"
  local -r name="$2"
  local -r actor="$3"
  local -r trigger="$4"
  local -r goal="$5"

  local -r escaped_name=$(sql_escape "${name}")
  local -r escaped_actor=$(sql_escape "${actor}")
  local -r escaped_trigger=$(sql_escape "${trigger}")
  local -r escaped_goal=$(sql_escape "${goal}")

  local sql="SELECT upsert_journey(
    '${SESSION}',
    '${escaped_name}',
    '${escaped_actor}',
    '${escaped_trigger}',
    '${escaped_goal}',
    'sync'
  );"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "INSERT journey: ${journey_id} - ${name} (${actor})"
  else
    db_exec "${sql}"
    log "  Journey: ${journey_id} - ${name} (${actor})"
  fi

  ((JOURNEYS_SYNCED++))
}

# Parse cross-cutting concerns from conversation or NFR file
parse_cross_cutting_concerns() {
  local -r file="$1"

  log "Parsing cross-cutting concerns from: ${file}"

  local auth_method=""
  local scaling=""
  local deployment=""

  while IFS= read -r line; do
    # Auth patterns
    if [[ "${line}" =~ [Aa]uth.*:[[:space:]]*(.+)$ ]] || [[ "${line}" =~ [Aa]uthentication.*:[[:space:]]*(.+)$ ]]; then
      auth_method="${BASH_REMATCH[1]}"
      auth_method=$(echo "${auth_method}" | xargs)
    fi

    # Scale patterns
    if [[ "${line}" =~ [Ss]cale.*:[[:space:]]*(.+)$ ]] || [[ "${line}" =~ [Uu]sers.*:[[:space:]]*(.+)$ ]]; then
      scaling="${BASH_REMATCH[1]}"
      scaling=$(echo "${scaling}" | xargs)
    fi

    # Deployment patterns
    if [[ "${line}" =~ [Dd]eploy.*:[[:space:]]*(.+)$ ]] || [[ "${line}" =~ [Tt]arget.*:[[:space:]]*(.+)$ ]]; then
      deployment="${BASH_REMATCH[1]}"
      deployment=$(echo "${deployment}" | xargs)
    fi
  done < "${file}"

  # Insert concerns
  if [[ -n "${auth_method}" ]]; then
    insert_cross_cutting_concern "authentication" "{\"method\": \"${auth_method}\"}"
  fi

  if [[ -n "${scaling}" ]]; then
    insert_cross_cutting_concern "scaling" "{\"expected_users\": \"${scaling}\"}"
  fi

  if [[ -n "${deployment}" ]]; then
    insert_cross_cutting_concern "deployment" "{\"target\": \"${deployment}\"}"
  fi
}

# Insert cross-cutting concern
insert_cross_cutting_concern() {
  local -r concern_type="$1"
  local -r config="$2"

  local -r escaped_config=$(sql_escape "${config}")

  local sql="INSERT INTO cross_cutting_concern (session_name, concern_type, config)
VALUES ('${SESSION}', '${concern_type}', '${escaped_config}'::jsonb)
ON CONFLICT (session_name, concern_type) DO UPDATE
SET config = EXCLUDED.config, updated_at = NOW();"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "INSERT concern: ${concern_type}"
  else
    db_exec "${sql}"
    log "  Concern: ${concern_type}"
  fi

  ((CONCERNS_SYNCED++))
}

# Parse integrations from conversation
parse_integrations() {
  local -r file="$1"

  log "Parsing integrations from: ${file}"

  # Common integration keywords
  local -a integrations=()

  while IFS= read -r line; do
    # Look for common platforms
    if [[ "${line}" =~ [Ss]tripe ]]; then
      integrations+=("Stripe|payment")
    fi
    if [[ "${line}" =~ [Pp]ay[Pp]al ]]; then
      integrations+=("PayPal|payment")
    fi
    if [[ "${line}" =~ [Ss]hopify ]]; then
      integrations+=("Shopify|ecommerce")
    fi
    if [[ "${line}" =~ [Ss]lack ]]; then
      integrations+=("Slack|communication")
    fi
    if [[ "${line}" =~ [Ss]end[Gg]rid|SES ]]; then
      integrations+=("Email|communication")
    fi
    if [[ "${line}" =~ [Ss]alesforce ]]; then
      integrations+=("Salesforce|crm")
    fi
    if [[ "${line}" =~ [Hh]ub[Ss]pot ]]; then
      integrations+=("HubSpot|crm")
    fi
    if [[ "${line}" =~ [Zz]endesk ]]; then
      integrations+=("Zendesk|support")
    fi
    if [[ "${line}" =~ [Ii]ntercom ]]; then
      integrations+=("Intercom|support")
    fi
    if [[ "${line}" =~ [Zz]apier ]]; then
      integrations+=("Zapier|automation")
    fi
  done < "${file}"

  # Remove duplicates and insert
  local -A seen=()
  local integration
  for integration in "${integrations[@]}"; do
    local platform="${integration%%|*}"
    local purpose="${integration##*|}"

    if [[ -z "${seen[${platform}]:-}" ]]; then
      seen["${platform}"]=1
      insert_integration "${platform}" "${purpose}"
    fi
  done
}

# Insert integration
insert_integration() {
  local -r platform="$1"
  local -r purpose="$2"

  local -r escaped_platform=$(sql_escape "${platform}")
  local -r escaped_purpose=$(sql_escape "${purpose}")

  local sql="INSERT INTO integration (session_name, platform, direction, purpose, status)
VALUES ('${SESSION}', '${escaped_platform}', 'bidirectional', '${escaped_purpose}', 'confirmed')
ON CONFLICT (session_name, platform) DO UPDATE
SET purpose = EXCLUDED.purpose, updated_at = NOW();"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "INSERT integration: ${platform} (${purpose})"
  else
    db_exec "${sql}"
    log "  Integration: ${platform} (${purpose})"
  fi

  ((INTEGRATIONS_SYNCED++))
}

# Parse user types from conversation
parse_user_types() {
  local -r file="$1"

  log "Parsing user types from: ${file}"

  local -a user_types=()

  while IFS= read -r line; do
    # Look for role/user type patterns
    if [[ "${line}" =~ [Rr]oles?.*:[[:space:]]*(.+)$ ]]; then
      local roles="${BASH_REMATCH[1]}"
      # Split by comma
      IFS=',' read -ra parts <<< "${roles}"
      local part
      for part in "${parts[@]}"; do
        part=$(echo "${part}" | xargs | sed 's/^and //')
        if [[ -n "${part}" ]] && [[ "${part}" != "etc" ]]; then
          user_types+=("${part}")
        fi
      done
    fi

    # Common user types mentioned
    if [[ "${line}" =~ [Aa]dmin ]]; then
      user_types+=("Admin")
    fi
    if [[ "${line}" =~ [Cc]ustomer ]]; then
      user_types+=("Customer")
    fi
    if [[ "${line}" =~ [Ss]eller ]]; then
      user_types+=("Seller")
    fi
    if [[ "${line}" =~ [Bb]uyer ]]; then
      user_types+=("Buyer")
    fi
    if [[ "${line}" =~ [Mm]anager ]]; then
      user_types+=("Manager")
    fi
  done < "${file}"

  # Remove duplicates and insert
  local -A seen=()
  local user_type
  for user_type in "${user_types[@]}"; do
    user_type=$(echo "${user_type}" | xargs)
    local lower_type="${user_type,,}"

    if [[ -z "${seen[${lower_type}]:-}" ]] && [[ -n "${user_type}" ]]; then
      seen["${lower_type}"]=1
      insert_user_type "${user_type}"
    fi
  done
}

# Insert user type
insert_user_type() {
  local -r name="$1"

  local -r escaped_name=$(sql_escape "${name}")

  local sql="INSERT INTO user_type (session_name, name, description)
VALUES ('${SESSION}', '${escaped_name}', 'Synced from interrogation')
ON CONFLICT (session_name, name) DO NOTHING;"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_dry "INSERT user_type: ${name}"
  else
    db_exec "${sql}"
    log "  User type: ${name}"
  fi

  ((USER_TYPES_SYNCED++))
}

# Mark session as synced
mark_session_synced() {
  # Update conversation.md with sync status
  if [[ -f "${CONV_FILE}" ]] && [[ "${DRY_RUN}" != "true" ]]; then
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if ! grep -q "^DB Synced:" "${CONV_FILE}"; then
      echo "" >> "${CONV_FILE}"
      echo "---" >> "${CONV_FILE}"
      echo "DB Synced: ${now}" >> "${CONV_FILE}"
      echo "Features: ${FEATURES_SYNCED}" >> "${CONV_FILE}"
      echo "Journeys: ${JOURNEYS_SYNCED}" >> "${CONV_FILE}"
      echo "User Types: ${USER_TYPES_SYNCED}" >> "${CONV_FILE}"
      echo "Integrations: ${INTEGRATIONS_SYNCED}" >> "${CONV_FILE}"
      echo "Concerns: ${CONCERNS_SYNCED}" >> "${CONV_FILE}"
    fi
  fi
}

# Main sync logic
run_sync() {
  echo ""
  echo "========================================"
  echo "Sync Interview to Database: ${SESSION}"
  echo "========================================"
  echo ""

  # Check for existing sync (unless --force)
  if [[ "${FORCE}" != "true" ]] && [[ -f "${CONV_FILE}" ]]; then
    if grep -q "^DB Synced:" "${CONV_FILE}"; then
      log_warn "Session already synced. Use --force to re-sync."
      return 0
    fi
  fi

  # Determine source files
  local features_file="${SCOPE_DIR}/01_features.md"
  local journeys_file="${SCOPE_DIR}/02_user_journeys.md"
  local nfr_file="${SCOPE_DIR}/04_nfr_requirements.md"

  # Parse features
  if [[ -f "${features_file}" ]]; then
    parse_features_structured "${features_file}"
  elif [[ -f "${CONV_FILE}" ]]; then
    parse_features_raw "${CONV_FILE}"
  else
    log_warn "No feature source found"
  fi

  # Parse journeys
  if [[ -f "${journeys_file}" ]]; then
    parse_journeys_structured "${journeys_file}"
  elif [[ -f "${CONV_FILE}" ]]; then
    parse_journeys_raw "${CONV_FILE}"
  else
    log_warn "No journey source found"
  fi

  # Parse cross-cutting concerns
  if [[ -f "${nfr_file}" ]]; then
    parse_cross_cutting_concerns "${nfr_file}"
  elif [[ -f "${CONV_FILE}" ]]; then
    parse_cross_cutting_concerns "${CONV_FILE}"
  fi

  # Parse integrations and user types from conversation
  if [[ -f "${CONV_FILE}" ]]; then
    parse_integrations "${CONV_FILE}"
    parse_user_types "${CONV_FILE}"
  fi

  # Mark as synced
  mark_session_synced

  # Summary
  echo ""
  echo "========================================"
  echo "Sync Complete"
  echo "========================================"
  echo ""
  echo "  Features:     ${FEATURES_SYNCED}"
  echo "  Journeys:     ${JOURNEYS_SYNCED}"
  echo "  User Types:   ${USER_TYPES_SYNCED}"
  echo "  Integrations: ${INTEGRATIONS_SYNCED}"
  echo "  Concerns:     ${CONCERNS_SYNCED}"
  echo ""

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_warn "Dry run - no changes made"
  else
    log_success "Data synced to database"
  fi
}

# Main entry point
main() {
  (($# < 1)) && usage

  # Parse arguments
  while (($# > 0)); do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --help|-h)
        usage
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        ;;
      *)
        if [[ -z "${SESSION}" ]]; then
          SESSION="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "${SESSION}" ]]; then
    log_error "Session name required"
    usage
  fi

  # Set paths
  CONV_FILE="${PROJECT_ROOT}/.claude/interrogations/${SESSION}/conversation.md"
  SCOPE_DIR="${PROJECT_ROOT}/.claude/scopes/${SESSION}"

  # Check at least one source exists
  if [[ ! -f "${CONV_FILE}" ]] && [[ ! -d "${SCOPE_DIR}" ]]; then
    log_error "No source files found for session: ${SESSION}"
    log_error "Expected: ${CONV_FILE}"
    log_error "      or: ${SCOPE_DIR}/"
    exit 1
  fi

  # Load credentials and check connection
  load_db_credentials
  check_db_connection

  # Run sync
  run_sync
}

main "$@"
