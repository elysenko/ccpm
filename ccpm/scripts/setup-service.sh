#!/bin/bash
#
# setup-service.sh - Unified service setup orchestrator
#
# Deploys, exposes, and configures infrastructure services (PostgreSQL, MinIO)
# with NodePort exposure.
#
# Usage: ./setup-service.sh <service> <namespace> [options]
#
# Services:
#   postgres  - PostgreSQL database via Helm
#   minio     - MinIO object storage
#   all       - Both PostgreSQL and MinIO
#
# Options:
#   --project=NAME   Project name (defaults to namespace)
#
# Output:
#   Prints key=value pairs to stdout for .env file
#
# Example:
#   ./setup-service.sh postgres myproject
#   ./setup-service.sh minio myproject --project=myapp
#   ./setup-service.sh all myproject
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/lib/common.sh"

# Default values
PROJECT=""

# Parse arguments
SERVICE=""
NAMESPACE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --project=*)
      PROJECT="${1#*=}"
      shift
      ;;
    -*)
      log_error "Unknown option: $1"
      exit 1
      ;;
    *)
      if [[ -z "$SERVICE" ]]; then
        SERVICE="$1"
      elif [[ -z "$NAMESPACE" ]]; then
        NAMESPACE="$1"
      else
        log_error "Too many arguments"
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate arguments
if [[ -z "$SERVICE" ]] || [[ -z "$NAMESPACE" ]]; then
  echo "Usage: $0 <service> <namespace> [--project=name]"
  echo ""
  echo "Services: postgres, minio, all"
  echo ""
  echo "Options:"
  echo "  --project=NAME   Project name (default: namespace)"
  exit 1
fi

# Default project to namespace if not specified
PROJECT="${PROJECT:-$NAMESPACE}"

# Ensure namespace exists
ensure_namespace "$NAMESPACE"

# Source service-specific functions
case "$SERVICE" in
  postgres)
    source "$SCRIPT_DIR/lib/services/postgres.sh"
    setup_postgres "$NAMESPACE" "$PROJECT"
    ;;
  minio)
    source "$SCRIPT_DIR/lib/services/minio.sh"
    setup_minio "$NAMESPACE" "$PROJECT"
    ;;
  all)
    # Setup both services
    source "$SCRIPT_DIR/lib/services/postgres.sh"
    source "$SCRIPT_DIR/lib/services/minio.sh"

    log_info "Setting up all services for namespace: $NAMESPACE"

    # Setup PostgreSQL
    setup_postgres "$NAMESPACE" "$PROJECT"

    # Setup MinIO
    setup_minio "$NAMESPACE" "$PROJECT"

    log_info "All services ready"
    ;;
  *)
    log_error "Unknown service: $SERVICE"
    echo "Available services: postgres, minio, all"
    exit 1
    ;;
esac
