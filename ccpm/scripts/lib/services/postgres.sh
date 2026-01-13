#!/bin/bash
# PostgreSQL service setup functions
# Deploy via Helm, expose, and configure credentials

# PostgreSQL configuration
POSTGRES_PORT=5432
POSTGRES_CHART="oci://registry-1.docker.io/bitnamicharts/postgresql"

# Deploy PostgreSQL via Helm
# Usage: deploy_postgres <namespace> <project>
deploy_postgres() {
  local namespace=$1
  local project=$2
  local release="${project}-postgresql"

  log_info "Deploying PostgreSQL..."

  # Check if already deployed
  if kubectl get statefulset "$release" -n "$namespace" &>/dev/null; then
    log_skip "PostgreSQL already deployed"
    return 0
  fi

  # Generate password
  local password
  password=$(generate_password 16)

  # Deploy via Helm (--create-namespace handles webhook race condition)
  if helm upgrade --install "$release" "$POSTGRES_CHART" \
    -n "$namespace" --create-namespace \
    --set "auth.username=$project" \
    --set "auth.password=$password" \
    --set "auth.database=$project" \
    --set "primary.persistence.enabled=true" \
    --set "primary.persistence.size=5Gi" \
    --set "primary.persistence.storageClass=local-path" \
    --wait --timeout=300s; then
    log_success "PostgreSQL deployed via Helm"
  else
    log_error "PostgreSQL Helm install failed"
    return 1
  fi
}

# Wait for PostgreSQL to be ready
# Usage: wait_for_postgres <namespace> <project>
wait_for_postgres() {
  local namespace=$1
  local project=$2
  local release="${project}-postgresql"

  log_info "Waiting for PostgreSQL..."

  if wait_for_statefulset "$release" "$namespace" 300; then
    log_success "PostgreSQL is ready"
  else
    log_error "PostgreSQL failed to become ready"
    return 1
  fi
}

# Initialize PostgreSQL (verify connectivity)
# Usage: init_postgres <host> <port> <namespace> <project>
init_postgres() {
  local host=$1
  local port=$2
  local namespace=$3
  local project=$4
  local release="${project}-postgresql"

  log_info "Verifying PostgreSQL connectivity..."

  # Get password from Helm-created secret
  local password
  password=$(get_secret_value "$release" "$namespace" "password")

  if [[ -z "$password" ]]; then
    log_error "Could not retrieve PostgreSQL password from secret"
    return 1
  fi

  log_success "PostgreSQL initialized"
}

# Get PostgreSQL credentials and output for .env
# Usage: output_postgres_credentials <host> <port> <namespace> <project>
output_postgres_credentials() {
  local host=$1
  local port=$2
  local namespace=$3
  local project=$4
  local release="${project}-postgresql"

  # Get password from Helm-created secret
  local password
  password=$(get_secret_value "$release" "$namespace" "password")

  if [[ -z "$password" ]]; then
    log_error "Could not retrieve PostgreSQL password"
    return 1
  fi

  # Store in standardized credentials secret
  store_secret "postgres-credentials" "$namespace" \
    "POSTGRES_HOST=$host" \
    "POSTGRES_PORT=$port" \
    "POSTGRES_DB=$project" \
    "POSTGRES_USER=$project" \
    "POSTGRES_PASSWORD=$password"

  log_success "Stored postgres-credentials secret"

  # Output for .env (to stdout)
  echo "POSTGRES_HOST=$host"
  echo "POSTGRES_PORT=$port"
  echo "POSTGRES_DB=$project"
  echo "POSTGRES_USER=$project"
  echo "POSTGRES_PASSWORD=$password"
}

# Main PostgreSQL setup function
# Usage: setup_postgres <namespace> <project> <expose_mode>
setup_postgres() {
  local namespace=$1
  local project=$2
  local expose_mode=${3:-nodeport}
  local release="${project}-postgresql"

  # Deploy
  deploy_postgres "$namespace" "$project" || return 1

  # Wait
  wait_for_postgres "$namespace" "$project" || return 1

  # Expose
  log_info "Exposing PostgreSQL (nodeport)..."
  local host_port
  host_port=$(expose_service "$release" "$namespace" "$POSTGRES_PORT")
  local host="${host_port%:*}"
  local port="${host_port#*:}"
  log_success "PostgreSQL exposed at $host:$port"

  # Initialize
  init_postgres "$host" "$port" "$namespace" "$project" || return 1

  # Output credentials
  output_postgres_credentials "$host" "$port" "$namespace" "$project"
}
