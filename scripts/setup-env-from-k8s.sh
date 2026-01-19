#!/bin/bash
# Setup environment from Kubernetes secrets
# This script pulls secrets from a namespace and populates .env file

set -e

NAMESPACE="${NAMESPACE:-}"
ENV_FILE="${ENV_FILE:-.env}"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

# Check required args
if [[ -z "$NAMESPACE" ]]; then
  echo "Usage: NAMESPACE=<namespace> [PROJECT_DIR=<path>] $0"
  exit 1
fi

echo "Setting up .env from Kubernetes secrets..."
echo "  Namespace: $NAMESPACE"
echo "  Target: $PROJECT_DIR/$ENV_FILE"

# Backup .env before making changes
backup_env() {
    if [ -f "$PROJECT_DIR/$ENV_FILE" ]; then
        local backup_file="$PROJECT_DIR/$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$PROJECT_DIR/$ENV_FILE" "$backup_file"
        echo "  Backup created: $(basename $backup_file)"

        # Clean old backups (keep last 5)
        ls -t "$PROJECT_DIR/$ENV_FILE.backup."* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    fi
}

# Create .env from example if it doesn't exist
if [ ! -f "$PROJECT_DIR/$ENV_FILE" ]; then
    echo "  Creating $ENV_FILE from .env.example..."
    if [ -f "$PROJECT_DIR/.env.example" ]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/$ENV_FILE"
    else
        # Create minimal .env if no example exists
        touch "$PROJECT_DIR/$ENV_FILE"
    fi
else
    # Backup existing .env
    backup_env
fi

# Function to get secret value from k8s
get_secret() {
    local secret_name=$1
    local key=$2
    kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d || echo ""
}

# Function to update or add env var in .env file
update_env_var() {
    local key=$1
    local value=$2

    if [ -z "$value" ]; then
        echo "  Skipping $key (secret not found)"
        return
    fi

    # Escape special characters for sed (but not forward slashes in URLs)
    local escaped_value=$(echo "$value" | sed 's/[&\\]/\\&/g')

    if grep -q "^${key}=" "$PROJECT_DIR/$ENV_FILE"; then
        # Update existing - use different delimiter to avoid issues with URLs
        sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$PROJECT_DIR/$ENV_FILE"
        echo "  Updated $key"
    else
        # Add new - direct write to avoid escaping issues
        echo "${key}=${value}" >> "$PROJECT_DIR/$ENV_FILE"
        echo "  Added $key"
    fi
}

# Pull PostgreSQL credentials from standardized secret
echo ""
echo "Fetching PostgreSQL credentials..."
POSTGRES_HOST=$(get_secret "postgres-credentials" "POSTGRES_HOST")
POSTGRES_PORT=$(get_secret "postgres-credentials" "POSTGRES_PORT")
POSTGRES_DB=$(get_secret "postgres-credentials" "POSTGRES_DB")
POSTGRES_USER=$(get_secret "postgres-credentials" "POSTGRES_USER")
POSTGRES_PASSWORD=$(get_secret "postgres-credentials" "POSTGRES_PASSWORD")

if [ -n "$POSTGRES_HOST" ]; then
    update_env_var "POSTGRES_HOST" "$POSTGRES_HOST"
    update_env_var "POSTGRES_PORT" "${POSTGRES_PORT:-5432}"
    update_env_var "POSTGRES_DB" "${POSTGRES_DB:-$NAMESPACE}"
    update_env_var "POSTGRES_USER" "${POSTGRES_USER:-postgres}"
    update_env_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"

    # Also create DATABASE_URL for frameworks that use it
    DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    update_env_var "DATABASE_URL" "$DATABASE_URL"
fi

# Pull MinIO credentials from standardized secret
echo ""
echo "Fetching MinIO credentials..."
MINIO_ENDPOINT=$(get_secret "minio-credentials" "MINIO_ENDPOINT")
MINIO_CONSOLE_URL=$(get_secret "minio-credentials" "MINIO_CONSOLE_URL")
MINIO_BUCKET=$(get_secret "minio-credentials" "MINIO_BUCKET")
MINIO_ACCESS_KEY=$(get_secret "minio-credentials" "MINIO_ACCESS_KEY")
MINIO_SECRET_KEY=$(get_secret "minio-credentials" "MINIO_SECRET_KEY")

if [ -n "$MINIO_ENDPOINT" ]; then
    update_env_var "MINIO_ENDPOINT" "$MINIO_ENDPOINT"
    if [ -n "$MINIO_CONSOLE_URL" ]; then
        update_env_var "MINIO_CONSOLE_URL" "$MINIO_CONSOLE_URL"
    fi
    update_env_var "MINIO_BUCKET" "${MINIO_BUCKET:-$NAMESPACE}"
    if [ -n "$MINIO_ACCESS_KEY" ]; then
        update_env_var "MINIO_ACCESS_KEY" "$MINIO_ACCESS_KEY"
        update_env_var "AWS_ACCESS_KEY_ID" "$MINIO_ACCESS_KEY"
    fi
    if [ -n "$MINIO_SECRET_KEY" ]; then
        update_env_var "MINIO_SECRET_KEY" "$MINIO_SECRET_KEY"
        update_env_var "AWS_SECRET_ACCESS_KEY" "$MINIO_SECRET_KEY"
    fi
fi

# Set project metadata
echo ""
echo "Setting project metadata..."
update_env_var "PROJECT_NAME" "$NAMESPACE"
update_env_var "NAMESPACE" "$NAMESPACE"

echo ""
echo "Environment setup complete!"
echo "  File: $PROJECT_DIR/$ENV_FILE"
echo ""
echo "Secrets loaded from Kubernetes:"
echo "  - postgres-credentials (POSTGRES_HOST, POSTGRES_PASSWORD, etc.)"
echo "  - minio-credentials (MINIO_ENDPOINT, MINIO_ACCESS_KEY, etc.)"
echo ""
echo "To reload secrets, run: NAMESPACE=$NAMESPACE PROJECT_DIR=$PROJECT_DIR $0"
