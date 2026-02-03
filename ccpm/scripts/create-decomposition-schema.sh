#!/bin/bash
# create-decomposition-schema.sh - Create PostgreSQL schema for decomposition data
#
# Usage:
#   ./create-decomposition-schema.sh              # Uses default credentials
#   POSTGRES_PASSWORD=xxx ./create-decomposition-schema.sh   # With explicit password
#
# Prerequisites:
#   - PostgreSQL database must be running
#   - Interview schema must exist (decomposition references sessions)
#   - Credentials in .env or K8s secrets
#   - .claude/ccpm/ccpm/schemas/decomposition_schema.sql must exist

set -e

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
NAMESPACE="${NAMESPACE:-$(basename "$PROJECT_ROOT")}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Creating Decomposition Database Schema ==="
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

# Check if schema file exists - try multiple locations
SCHEMA_FILE=""
POSSIBLE_PATHS=(
    "$PROJECT_ROOT/.claude/ccpm/ccpm/schemas/decomposition_schema.sql"
    "$PROJECT_ROOT/.claude/schemas/decomposition_schema.sql"
    "$SCRIPT_DIR/../schemas/decomposition_schema.sql"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCHEMA_FILE="$path"
        break
    fi
done

if [ -z "$SCHEMA_FILE" ]; then
    echo -e "${RED}Error: Schema file not found${NC}"
    echo "Searched in:"
    for path in "${POSSIBLE_PATHS[@]}"; do
        echo "  - $path"
    done
    exit 1
fi

echo "Using schema file: $SCHEMA_FILE"
echo ""

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

# Check if decomposition schema already exists
EXISTING_DECOMP=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'decomposition_sessions'" 2>/dev/null | tr -d ' ')

if [ "$EXISTING_DECOMP" -gt 0 ] 2>/dev/null; then
    echo -e "${YELLOW}Decomposition schema already exists${NC}"
    echo "Checking for updates..."

    # Apply schema (idempotent - uses IF NOT EXISTS)
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SCHEMA_FILE" 2>&1 | grep -v "NOTICE" || true

    echo -e "${GREEN}Schema updated${NC}"
else
    echo "Creating decomposition schema..."
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SCHEMA_FILE"
    echo -e "${GREEN}Schema created successfully${NC}"
fi

# Verify tables exist
echo ""
echo "Verifying schema..."
TABLES=(
    "decomposition_sessions"
    "decomposition_nodes"
    "decomposition_audit_log"
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
    echo -e "${GREEN}Decomposition schema verified: ${#TABLES[@]} tables${NC}"

    # Show views
    echo ""
    echo "Views created:"
    VIEWS=(
        "decomposition_session_summary"
        "decomposition_node_tree"
        "decomposition_atomic_nodes"
    )
    for VIEW in "${VIEWS[@]}"; do
        EXISTS=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
            "SELECT COUNT(*) FROM information_schema.views WHERE table_name = '$VIEW'" 2>/dev/null | tr -d ' ')
        if [ "$EXISTS" -gt 0 ] 2>/dev/null; then
            echo -e "  ${GREEN}v $VIEW${NC}"
        fi
    done

    # Show functions
    echo ""
    echo "Functions created:"
    FUNCTIONS=(
        "create_decomposition_session"
        "add_decomposition_node"
        "mark_node_atomic"
        "record_prd_generation"
        "complete_decomposition_session"
        "get_pending_nodes"
        "get_decomposition_tree"
    )
    for FUNC in "${FUNCTIONS[@]}"; do
        EXISTS=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
            "SELECT COUNT(*) FROM pg_proc WHERE proname = '$FUNC'" 2>/dev/null | tr -d ' ')
        if [ "$EXISTS" -gt 0 ] 2>/dev/null; then
            echo -e "  ${GREEN}v $FUNC${NC}"
        fi
    done

    echo ""
    echo -e "${GREEN}Decomposition schema ready${NC}"
else
    echo -e "${RED}Missing $MISSING tables${NC}"
    exit 1
fi
