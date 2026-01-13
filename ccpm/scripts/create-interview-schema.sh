#!/bin/bash
# create-interview-schema.sh - Create PostgreSQL schema for interrogation data
#
# Usage:
#   ./create-interview-schema.sh              # Uses default credentials
#   POSTGRES_PASSWORD=xxx ./create-interview-schema.sh   # With explicit password
#
# Prerequisites:
#   - PostgreSQL database must be running
#   - Credentials in .env or K8s secrets
#   - .claude/schemas/interview_schema.sql must exist

set -e

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
NAMESPACE="${NAMESPACE:-$(basename "$PROJECT_ROOT")}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Creating Interview Database Schema ==="
echo ""

# Load credentials from .env if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "Loading credentials from .env..."
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Try to get credentials from K8s if not in .env
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Attempting to get credentials from Kubernetes..."
    POSTGRES_PASSWORD=$(kubectl get secret postgres-credentials -n "$NAMESPACE" \
        -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d || echo "")
fi

# Set defaults
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-$NAMESPACE}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo -e "${YELLOW}Warning: No POSTGRES_PASSWORD found${NC}"
    echo "Will attempt connection without password (may fail)"
fi

echo "Database: $POSTGRES_DB@$POSTGRES_HOST:$POSTGRES_PORT"
echo ""

# Check if schema file exists
SCHEMA_FILE="$PROJECT_ROOT/.claude/schemas/interview_schema.sql"
if [ ! -f "$SCHEMA_FILE" ]; then
    echo -e "${RED}Error: Schema file not found: $SCHEMA_FILE${NC}"
    exit 1
fi

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL..."
MAX_RETRIES=30
RETRY_COUNT=0
while ! PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo -e "${RED}Error: PostgreSQL not ready after $MAX_RETRIES attempts${NC}"
        exit 1
    fi
    echo "  Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done
echo -e "${GREEN}PostgreSQL is ready${NC}"
echo ""

# Check if schema already exists
EXISTING_TABLES=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'interrogation_sessions'" 2>/dev/null | tr -d ' ')

if [ "$EXISTING_TABLES" -gt 0 ] 2>/dev/null; then
    echo -e "${YELLOW}Schema already exists. Checking for updates...${NC}"

    # Check schema version
    CURRENT_VERSION=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT version FROM schema_versions WHERE schema_name = 'interview_schema' ORDER BY applied_at DESC LIMIT 1" 2>/dev/null | tr -d ' ')

    if [ -n "$CURRENT_VERSION" ]; then
        echo "  Current version: $CURRENT_VERSION"
    fi

    echo -e "${GREEN}Schema is current${NC}"
else
    echo "Creating schema..."
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SCHEMA_FILE"
    echo -e "${GREEN}Schema created successfully${NC}"
fi

# Verify tables exist
echo ""
echo "Verifying schema..."
TABLES=(
    "interrogation_sessions"
    "conversation_turns"
    "turn_extractions"
    "extraction_conflicts"
    "user_journeys"
    "journey_steps_detailed"
    "step_data_flow"
    "step_dependencies"
    "features"
    "feature_journey_mapping"
    "technical_components"
    "step_component_mapping"
    "database_entities"
    "backend_action_traces"
    "trace_layers"
    "entity_operations"
)

MISSING=0
for TABLE in "${TABLES[@]}"; do
    EXISTS=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = '$TABLE'" 2>/dev/null | tr -d ' ')
    if [ "$EXISTS" -eq 0 ] 2>/dev/null; then
        echo -e "  ${RED}x $TABLE${NC}"
        MISSING=$((MISSING + 1))
    else
        echo -e "  ${GREEN}v $TABLE${NC}"
    fi
done

echo ""
if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}Interview schema verified: ${#TABLES[@]} tables${NC}"

    # Show views
    echo ""
    echo "Views created:"
    VIEWS=(
        "journey_full_view"
        "step_technical_summary"
        "extraction_summary"
        "feature_implementation_trace"
        "entity_usage_summary"
    )
    for VIEW in "${VIEWS[@]}"; do
        EXISTS=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
            "SELECT COUNT(*) FROM information_schema.views WHERE table_name = '$VIEW'" 2>/dev/null | tr -d ' ')
        if [ "$EXISTS" -gt 0 ] 2>/dev/null; then
            echo -e "  ${GREEN}v $VIEW${NC}"
        fi
    done

    echo ""
    echo -e "${GREEN}Interview schema ready${NC}"
else
    echo -e "${RED}Missing $MISSING tables${NC}"
    exit 1
fi
