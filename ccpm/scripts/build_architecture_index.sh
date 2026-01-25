#!/bin/bash
# build_architecture_index.sh - Build deterministic architecture index for diagram generation
#
# Scans the codebase to extract:
# - Frontend components and their API dependencies
# - Backend API endpoints and their table usage
# - Database tables and relationships
#
# Usage: ./build_architecture_index.sh [project_root]
# Output: .claude/cache/architecture/index.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${1:-$(pwd)}"
INDEX_DIR="$PROJECT_ROOT/.claude/cache/architecture"

# Colors for output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
  echo -e "  ${GREEN}▸${NC} $1" >&2
}

# Discover API clients dynamically from api.ts
discover_api_clients() {
  local api_file="$PROJECT_ROOT/frontend/src/api.ts"
  if [ -f "$api_file" ]; then
    # Extract all "export const xxxApi" patterns
    grep -oE 'export const \w+Api' "$api_file" 2>/dev/null | sed 's/export const //' | sort -u
  fi
}

# Build API name to endpoint prefix mapping dynamically
build_api_mapping() {
  local api_name="$1"
  # Convert camelCase API name to endpoint prefix
  # e.g., vendorsApi -> /api/v1/vendors
  #       procurementApi -> /api/v1/procurement
  local prefix
  prefix=$(echo "$api_name" | sed 's/Api$//' | sed 's/\([A-Z]\)/-\L\1/g' | sed 's/^-//')
  echo "/api/v1/$prefix"
}

# Create output directory
mkdir -p "$INDEX_DIR"

# Compute hash of source files for cache invalidation
compute_source_hash() {
  local hash=""
  if [ -d "$PROJECT_ROOT/backend/app" ] && [ -d "$PROJECT_ROOT/frontend/src" ]; then
    hash=$(find "$PROJECT_ROOT/backend/app" "$PROJECT_ROOT/frontend/src" \
      -name "*.py" -o -name "*.tsx" -o -name "*.ts" 2>/dev/null | \
      sort | xargs md5sum 2>/dev/null | md5sum | cut -d' ' -f1)
  fi
  echo "$hash"
}

# Check if rebuild is needed
check_cache() {
  local current_hash
  current_hash=$(compute_source_hash)

  if [ -f "$INDEX_DIR/index.hash" ] && [ -f "$INDEX_DIR/index.yaml" ]; then
    local cached_hash
    cached_hash=$(cat "$INDEX_DIR/index.hash")
    if [ "$cached_hash" = "$current_hash" ]; then
      echo "Architecture index is current (hash: ${current_hash:0:8})"
      return 0
    fi
  fi
  return 1
}

# Extract frontend components
extract_frontend_components() {
  log "Extracting frontend components..."

  local pages_dir="$PROJECT_ROOT/frontend/src/pages"
  local components_dir="$PROJECT_ROOT/frontend/src/components"

  # Discover available API clients dynamically
  local available_apis
  available_apis=$(discover_api_clients | tr '\n' '|' | sed 's/|$//')

  echo "frontend:"
  echo "  components:"

  # Extract pages
  if [ -d "$pages_dir" ]; then
    for file in "$pages_dir"/*.tsx; do
      [ -f "$file" ] || continue
      local name=$(basename "$file" .tsx)
      local rel_path="frontend/src/pages/$(basename "$file")"

      # Extract API imports dynamically using discovered API names
      local apis=""
      if [ -n "$available_apis" ]; then
        apis=$(grep -oE "($available_apis)" "$file" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//') || true
      fi

      echo "    - id: $name"
      echo "      file: $rel_path"
      echo "      type: page"
      if [ -n "$apis" ]; then
        echo "      apis: [$apis]"
      fi
    done
  fi

  # Extract components
  if [ -d "$components_dir" ]; then
    for file in "$components_dir"/*.tsx; do
      [ -f "$file" ] || continue
      local name=$(basename "$file" .tsx)
      local rel_path="frontend/src/components/$(basename "$file")"

      local apis=""
      if [ -n "$available_apis" ]; then
        apis=$(grep -oE "($available_apis)" "$file" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//') || true
      fi

      echo "    - id: $name"
      echo "      file: $rel_path"
      echo "      type: component"
      if [ -n "$apis" ]; then
        echo "      apis: [$apis]"
      fi
    done
  fi
}

# Build model class to table name mapping (used by multiple functions)
# Call this once and store in global associative array
declare -A MODEL_TO_TABLE
build_model_to_table_mapping() {
  local models_dir="$PROJECT_ROOT/backend/app/models"

  if [ -d "$models_dir" ]; then
    while IFS= read -r model_file || [ -n "$model_file" ]; do
      [ -f "$model_file" ] || continue
      local model_basename
      model_basename=$(basename "$model_file" .py)
      [ "$model_basename" = "__init__" ] && continue

      # Extract class names and their table names
      while IFS= read -r line || [ -n "$line" ]; do
        local class_name table_name
        class_name=$(echo "$line" | grep -oE 'class ([A-Za-z]+)' | sed 's/class //') || true
        [ -z "$class_name" ] && continue

        # Find the __tablename__ for this class
        table_name=$(grep -A10 "class $class_name" "$model_file" 2>/dev/null | grep '__tablename__' | head -1 | grep -oE '"[^"]*"' | tr -d '"') || true

        if [ -n "$table_name" ]; then
          MODEL_TO_TABLE["$class_name"]="$table_name"
        fi
      done < <(grep '^class ' "$model_file" 2>/dev/null || true)
    done < <(find "$models_dir" -name "*.py" -type f 2>/dev/null)
  fi
}

# Get tables used by a specific API file
get_tables_for_api_file() {
  local file="$1"
  local tables=""

  for class_name in "${!MODEL_TO_TABLE[@]}"; do
    if grep -q "\b$class_name\b" "$file" 2>/dev/null; then
      local table="${MODEL_TO_TABLE[$class_name]}"
      if [ -n "$table" ]; then
        tables="$tables$table,"
      fi
    fi
  done

  # Remove trailing comma and deduplicate
  echo "$tables" | sed 's/,$//' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//'
}

# Extract backend endpoints
extract_backend_endpoints() {
  log "Extracting backend API endpoints..."

  local api_dir="$PROJECT_ROOT/backend/app/api/v1"

  echo ""
  echo "backend:"
  echo "  endpoints:"

  if [ -d "$api_dir" ]; then
    for file in "$api_dir"/*.py; do
      [ -f "$file" ] || continue
      local module=$(basename "$file" .py)
      [ "$module" = "__init__" ] && continue

      local rel_path="backend/app/api/v1/$(basename "$file")"

      # Get tables used by this API module
      local module_tables
      module_tables=$(get_tables_for_api_file "$file")

      # Extract router prefix
      local prefix=""
      prefix=$(grep -oE 'prefix="[^"]*"' "$file" 2>/dev/null | head -1 | sed 's/prefix="//;s/"//') || true
      [ -z "$prefix" ] && prefix="/$module"

      # Extract routes with methods
      while IFS= read -r line || [ -n "$line" ]; do
        local method
        method=$(echo "$line" | grep -oE '@router\.(get|post|put|delete|patch)' | sed 's/@router\.//' | tr '[:lower:]' '[:upper:]') || true
        local path
        path=$(echo "$line" | grep -oE '"[^"]*"' | head -1 | tr -d '"') || true

        [ -z "$method" ] && continue

        # Build full path
        local full_path="/api/v1$prefix$path"
        full_path=$(echo "$full_path" | sed 's|//|/|g')

        echo "    - path: $full_path"
        echo "      method: $method"
        echo "      file: $rel_path"
        echo "      module: $module"
        if [ -n "$module_tables" ]; then
          echo "      tables: [$module_tables]"
        fi
      done < <(grep -E '@router\.(get|post|put|delete|patch)' "$file" 2>/dev/null || true)
    done
  fi
}

# Extract columns for a model class from its file
extract_columns_for_class() {
  local file="$1"
  local class_name="$2"
  local columns=""

  # Get the content from class definition to next class or end of file
  local class_content
  class_content=$(sed -n "/^class $class_name/,/^class [A-Z]/p" "$file" 2>/dev/null) || true

  # If no second class found, get from class definition to end of file
  if [ -z "$class_content" ]; then
    class_content=$(sed -n "/^class $class_name/,\$p" "$file" 2>/dev/null) || true
  fi

  # Extract SQLAlchemy Column definitions: name = Column(...)
  local col_columns
  col_columns=$(echo "$class_content" | grep "= Column(" 2>/dev/null | sed 's/=.*//' | xargs 2>/dev/null) || true

  # Extract SQLAlchemy 2.0 Mapped columns: name: Mapped[...] = mapped_column(...)
  local mapped_columns
  mapped_columns=$(echo "$class_content" | grep ": Mapped\[" 2>/dev/null | sed 's/:.*//' | xargs 2>/dev/null) || true

  # Combine and deduplicate
  columns=$(echo "$col_columns $mapped_columns" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')

  echo "$columns"
}

# Extract database tables
extract_database_tables() {
  log "Extracting database tables..."

  local models_dir="$PROJECT_ROOT/backend/app/models"
  local migrations_dir="$PROJECT_ROOT/backend/migrations"

  echo ""
  echo "database:"
  echo "  tables:"

  # Extract from SQLAlchemy models (authoritative)
  if [ -d "$models_dir" ]; then
    for file in "$models_dir"/*.py; do
      [ -f "$file" ] || continue
      local model_file=$(basename "$file" .py)
      [ "$model_file" = "__init__" ] && continue

      local rel_path="backend/app/models/$(basename "$file")"

      # Extract __tablename__ definitions
      while IFS= read -r line || [ -n "$line" ]; do
        local table
        table=$(echo "$line" | grep -oE '__tablename__\s*=\s*"[^"]*"' | sed 's/__tablename__\s*=\s*"//;s/"$//') || true
        [ -z "$table" ] && continue

        # Extract class name (line before __tablename__)
        local class_name
        class_name=$(grep -B5 "__tablename__.*$table" "$file" 2>/dev/null | grep -oE '^class [A-Za-z]+' | tail -1 | sed 's/class //') || true

        # Extract columns for this model
        local columns
        columns=$(extract_columns_for_class "$file" "$class_name")

        echo "    - name: $table"
        echo "      model: $class_name"
        echo "      file: $rel_path"
        echo "      module: $model_file"
        if [ -n "$columns" ]; then
          echo "      columns: [$columns]"
        fi
      done < <(grep '__tablename__' "$file" 2>/dev/null || true)
    done
  fi
}

# Extract relationships between layers
extract_relationships() {
  log "Extracting cross-layer relationships..."

  echo ""
  echo "relationships:"
  echo "  # Frontend -> API mappings"
  echo "  frontend_to_api:"

  local pages_dir="$PROJECT_ROOT/frontend/src/pages"

  # Discover available API clients dynamically
  local api_clients
  api_clients=$(discover_api_clients)

  if [ -d "$pages_dir" ]; then
    for file in "$pages_dir"/*.tsx; do
      [ -f "$file" ] || continue
      local name=$(basename "$file" .tsx)

      # Map API clients to endpoints dynamically
      local endpoints=""

      # Check each discovered API client
      while IFS= read -r api_name || [ -n "$api_name" ]; do
        [ -z "$api_name" ] && continue
        if grep -q "$api_name" "$file" 2>/dev/null; then
          local endpoint
          endpoint=$(build_api_mapping "$api_name")
          endpoints="$endpoints $endpoint"
        fi
      done <<< "$api_clients"

      endpoints=$(echo "$endpoints" | xargs | tr ' ' ',')

      if [ -n "$endpoints" ]; then
        echo "    $name: [$endpoints]"
      fi
    done
  fi

  echo ""
  echo "  # API -> Database mappings (based on model imports)"
  echo "  api_to_tables:"

  local api_dir="$PROJECT_ROOT/backend/app/api/v1"
  local models_dir="$PROJECT_ROOT/backend/app/models"

  # Build model class to table name mapping dynamically
  declare -A model_to_tables
  if [ -d "$models_dir" ]; then
    while IFS= read -r model_file || [ -n "$model_file" ]; do
      [ -f "$model_file" ] || continue
      local model_basename
      model_basename=$(basename "$model_file" .py)
      [ "$model_basename" = "__init__" ] && continue

      # Extract class names and their table names
      while IFS= read -r line || [ -n "$line" ]; do
        local class_name table_name
        # Parse lines like: class VendorCategory -> vendors_categories
        class_name=$(echo "$line" | grep -oE 'class ([A-Za-z]+)' | sed 's/class //') || true
        [ -z "$class_name" ] && continue

        # Find the __tablename__ for this class in the same file
        table_name=$(grep -A10 "class $class_name" "$model_file" 2>/dev/null | grep '__tablename__' | head -1 | grep -oE '"[^"]*"' | tr -d '"') || true

        if [ -n "$table_name" ]; then
          model_to_tables["$class_name"]="$table_name"
        fi
      done < <(grep '^class ' "$model_file" 2>/dev/null || true)
    done < <(find "$models_dir" -name "*.py" -type f 2>/dev/null)
  fi

  if [ -d "$api_dir" ]; then
    for file in "$api_dir"/*.py; do
      [ -f "$file" ] || continue
      local module=$(basename "$file" .py)
      [ "$module" = "__init__" ] && continue

      local tables=""

      # Dynamically check for model imports and usage
      for class_name in "${!model_to_tables[@]}"; do
        if grep -q "$class_name" "$file" 2>/dev/null; then
          local table="${model_to_tables[$class_name]}"
          if [ -n "$table" ]; then
            tables="$tables $table"
          fi
        fi
      done

      tables=$(echo "$tables" | xargs | tr ' ' ',' | sort -u)

      if [ -n "$tables" ]; then
        echo "    $module: [$tables]"
      fi
    done
  fi
}

# Generate complete index
generate_index() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local hash
  hash=$(compute_source_hash)

  log "Generating architecture index..."

  # Build model-to-table mapping first (needed by extract_backend_endpoints)
  build_model_to_table_mapping
  log "Mapped ${#MODEL_TO_TABLE[@]} model classes to tables"

  {
    echo "# Architecture Index - Auto-generated"
    echo "# DO NOT EDIT MANUALLY - Regenerate with: ./build_architecture_index.sh"
    echo ""
    echo "version: 1"
    echo "generated: $timestamp"
    echo "hash: $hash"
    echo ""

    extract_frontend_components
    extract_backend_endpoints
    extract_database_tables
    extract_relationships

  } > "$INDEX_DIR/index.yaml"

  # Save hash for cache validation
  echo "$hash" > "$INDEX_DIR/index.hash"

  log "Index saved to: .claude/cache/architecture/index.yaml"
}

# Main execution
main() {
  echo "Building architecture index for: $PROJECT_ROOT"

  # Check cache - rebuild only if needed
  if check_cache; then
    exit 0
  fi

  # Show discovered API clients
  local api_count
  api_count=$(discover_api_clients | wc -l)
  log "Discovered $api_count API clients dynamically"

  generate_index

  # Count extracted elements
  local components tables endpoints
  components=$(grep -c "^    - id:" "$INDEX_DIR/index.yaml" 2>/dev/null || echo "0")
  endpoints=$(grep -c "^    - path:" "$INDEX_DIR/index.yaml" 2>/dev/null || echo "0")
  tables=$(grep -c "^    - name:" "$INDEX_DIR/index.yaml" 2>/dev/null || echo "0")

  echo ""
  echo "Index complete:"
  echo "  - $components frontend components"
  echo "  - $endpoints API endpoints"
  echo "  - $tables database tables"
}

main "$@"
