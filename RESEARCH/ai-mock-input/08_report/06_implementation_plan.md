# Implementation Plan: CCPM Mock-Input Integration

## Overview

This plan describes how to implement the mock-input system as a CCPM skill that integrates with the `fix-problem` command for fully autonomous operation.

## Phase 1: Core Infrastructure (Week 1)

### 1.1 Create Configuration Schema

**File:** `ccpm/config/mock-input-schema.yml`

Define the configuration structure for auto-decisions:

```yaml
# Schema for .claude/mock-input.yml
type: object
properties:
  enabled:
    type: boolean
    default: false  # Opt-in required

  safety:
    type: object
    properties:
      deny_patterns:
        type: array
        items:
          type: string
        default:
          - "password|secret|token|key|credential"
          - "rm -rf|DROP TABLE|DELETE FROM"
          - "deploy.*prod"

  tier1:
    type: object
    properties:
      binary_defaults:
        type: object
        additionalProperties:
          type: string
          enum: ["y", "n"]

  audit:
    type: object
    properties:
      enabled:
        type: boolean
        default: true
      log_file:
        type: string
        default: ".claude/logs/auto-decisions.jsonl"
```

### 1.2 Implement Safety Filter

**File:** `ccpm/scripts/mock-input/safety-filter.sh`

```bash
#!/bin/bash
# Safety filter for mock-input system

PROMPT="$1"
DENY_PATTERNS=(
    "password|secret|token|key|credential|api.?key"
    "rm\s+-rf|DROP\s+TABLE|DELETE\s+FROM|TRUNCATE"
    "deploy.*prod|release.*production|publish.*live"
    "payment|purchase|transfer|billing|charge"
    "chmod|chown|sudo|su\s"
    "accept.*license|agree.*terms|eula"
    "email|phone|ssn|social.security"
)

for pattern in "${DENY_PATTERNS[@]}"; do
    if echo "$PROMPT" | grep -qiE "$pattern"; then
        echo "DENY"
        exit 0
    fi
done

echo "ALLOW"
exit 0
```

### 1.3 Implement Decision Classifier

**File:** `ccpm/scripts/mock-input/classifier.sh`

```bash
#!/bin/bash
# Classify prompt type for routing

PROMPT="$1"

# Binary patterns
if echo "$PROMPT" | grep -qiE '\[y/n\]|\[Y/N\]|yes/no|\(y/n\)'; then
    echo "BINARY"
    exit 0
fi

if echo "$PROMPT" | grep -qiE '^(Continue|Proceed|Confirm)\??'; then
    echo "BINARY"
    exit 0
fi

# Path patterns
if echo "$PROMPT" | grep -qiE 'path:|file:|directory:|folder:|location:'; then
    echo "PATH"
    exit 0
fi

# Naming patterns
if echo "$PROMPT" | grep -qiE 'name:|enter.*name|component.*name|what.*call'; then
    echo "NAMING"
    exit 0
fi

# Config patterns
if echo "$PROMPT" | grep -qiE 'port:|timeout:|count:|number:|value:'; then
    echo "CONFIG"
    exit 0
fi

# Selection patterns
if echo "$PROMPT" | grep -qiE 'choose|select|\[1-[0-9]\]|option'; then
    echo "SELECTION"
    exit 0
fi

# Default: unknown
echo "UNKNOWN"
exit 0
```

## Phase 2: Decision Handlers (Week 2)

### 2.1 Tier 1: Pattern Matcher

**File:** `ccpm/scripts/mock-input/tier1-matcher.sh`

```bash
#!/bin/bash
# Tier 1: Fast pattern matching for common prompts

PROMPT="$1"
CATEGORY="$2"
CONFIG_FILE="${PROJECT_ROOT}/.claude/mock-input.yml"

# Load defaults from config or use built-in defaults
get_binary_default() {
    local prompt="$1"

    # Destructive indicators → NO
    if echo "$prompt" | grep -qiE 'overwrite|delete|remove|erase|replace'; then
        echo "n"
        return
    fi

    # Non-destructive → YES
    echo "y"
}

get_config_default() {
    local prompt="$1"

    case "$prompt" in
        *port*) echo "3000" ;;
        *timeout*) echo "30" ;;
        *retries*) echo "3" ;;
        *workers*) echo "$(nproc)" ;;
        *) echo "DEFER" ;;
    esac
}

case "$CATEGORY" in
    BINARY)
        get_binary_default "$PROMPT"
        ;;
    CONFIG)
        get_config_default "$PROMPT"
        ;;
    *)
        echo "DEFER"
        ;;
esac
```

### 2.2 Tier 2: Context Inferencer

**File:** `ccpm/scripts/mock-input/tier2-inferencer.sh`

```bash
#!/bin/bash
# Tier 2: Context-aware inference

PROMPT="$1"
CATEGORY="$2"
PROJECT_ROOT="$3"

infer_naming() {
    local prompt="$1"
    local project_root="$2"

    # Analyze existing file names for convention
    local kebab_count=$(find "$project_root" -name "*-*" -type f | wc -l)
    local snake_count=$(find "$project_root" -name "*_*" -type f | wc -l)
    local camel_count=$(find "$project_root" -name "*[a-z][A-Z]*" -type f | wc -l)

    local total=$((kebab_count + snake_count + camel_count))

    if [ $total -eq 0 ]; then
        echo "DEFER"
        return
    fi

    # Determine dominant pattern
    local max_count=$kebab_count
    local pattern="kebab-case"

    if [ $snake_count -gt $max_count ]; then
        max_count=$snake_count
        pattern="snake_case"
    fi

    if [ $camel_count -gt $max_count ]; then
        max_count=$camel_count
        pattern="camelCase"
    fi

    # Check consensus (>80%)
    local consensus=$(( (max_count * 100) / total ))
    if [ $consensus -lt 80 ]; then
        echo "DEFER"
        return
    fi

    # Generate name based on pattern
    local base_name="generated"
    case "$pattern" in
        kebab-case) echo "${base_name}-item" ;;
        snake_case) echo "${base_name}_item" ;;
        camelCase) echo "generatedItem" ;;
    esac
}

infer_path() {
    local prompt="$1"
    local project_root="$2"

    # Check for context clues
    if echo "$prompt" | grep -qiE 'test'; then
        if [ -d "$project_root/tests" ]; then
            echo "$project_root/tests"
        elif [ -d "$project_root/__tests__" ]; then
            echo "$project_root/__tests__"
        else
            echo "$project_root/test"
        fi
        return
    fi

    if echo "$prompt" | grep -qiE 'config'; then
        if [ -d "$project_root/config" ]; then
            echo "$project_root/config"
        else
            echo "$project_root"
        fi
        return
    fi

    # Default to temp directory
    echo "${project_root}/tmp"
}

case "$CATEGORY" in
    NAMING)
        infer_naming "$PROMPT" "$PROJECT_ROOT"
        ;;
    PATH)
        infer_path "$PROMPT" "$PROJECT_ROOT"
        ;;
    SELECTION)
        # Default to first option
        echo "1"
        ;;
    *)
        echo "DEFER"
        ;;
esac
```

### 2.3 Audit Logger

**File:** `ccpm/scripts/mock-input/audit-logger.sh`

```bash
#!/bin/bash
# Audit logger for auto-decisions

LOG_FILE="${PROJECT_ROOT}/.claude/logs/auto-decisions.jsonl"
mkdir -p "$(dirname "$LOG_FILE")"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PROMPT="$1"
CATEGORY="$2"
DECISION="$3"
CONFIDENCE="$4"
REASONING="$5"

# Create JSON entry
cat >> "$LOG_FILE" << EOF
{"timestamp":"$TIMESTAMP","prompt":"$(echo "$PROMPT" | sed 's/"/\\"/g')","category":"$CATEGORY","decision":"$DECISION","confidence":$CONFIDENCE,"reasoning":"$REASONING"}
EOF
```

## Phase 3: CCPM Skill Integration (Week 3)

### 3.1 Create mock-input Command

**File:** `ccpm/commands/pm/mock-input.md`

```markdown
---
name: mock-input
description: Generate mock responses for prompts in autonomous mode
---

# /pm:mock-input

Generate contextually-appropriate responses for user input prompts during autonomous execution.

## Usage

\`\`\`bash
# Process a single prompt
/pm:mock-input "Continue? [y/N]"

# Process with context
/pm:mock-input --context "npm install" "Install peer dependencies? [y/N]"

# Check if prompt should be auto-decided
/pm:mock-input --check-only "Enter API key:"
\`\`\`

## Execution

1. Load configuration from `.claude/mock-input.yml`
2. Run safety filter - deny dangerous prompts
3. Classify prompt type (BINARY, PATH, NAMING, CONFIG, SELECTION, UNKNOWN)
4. Route to appropriate tier:
   - Tier 1: Pattern matching for common prompts
   - Tier 2: Context inference for naming/path decisions
   - Tier 3: Defer for unknown/unsafe prompts
5. Log decision to audit trail
6. Return response or DEFER signal

## Configuration

Create `.claude/mock-input.yml`:

\`\`\`yaml
enabled: true

safety:
  deny_patterns:
    - "password|secret|token"

tier1:
  binary_defaults:
    continue: "y"
    overwrite: "n"

audit:
  enabled: true
\`\`\`

## Output

Returns one of:
- Response value (e.g., "y", "3000", "my-component")
- "DEFER" if prompt should not be auto-decided
- "DENY" if prompt matches safety filter
```

### 3.2 Integrate with fix-problem

**Modify:** `ccpm/commands/pm/fix-problem.md`

Add autonomous mode support:

```markdown
## Autonomous Mode

When running with `--auto` flag, fix-problem uses mock-input to handle prompts:

\`\`\`bash
/pm:fix-problem --auto "Build is failing with TypeScript errors"
\`\`\`

In autonomous mode:
1. All prompts are routed through mock-input
2. Safe defaults are applied where possible
3. Unsafe prompts cause task deferral (not failure)
4. All decisions are logged for review

### Environment Variables

- `CCPM_AUTO_MODE=true` - Enable autonomous mode
- `CCPM_MOCK_INPUT_STRICT=true` - Fail instead of defer on unknown prompts
```

### 3.3 Create Hooks Integration

**File:** `ccpm/hooks/mock-input-hook.yml`

```yaml
# Hook to intercept prompts and auto-respond
name: mock-input-interceptor
description: Intercept prompts in autonomous mode

triggers:
  - event: pre_tool_execution
    conditions:
      - env: CCPM_AUTO_MODE
        equals: "true"

patterns:
  - regex: "\\[y/[Nn]\\]"
    handler: mock-input-binary
  - regex: "Enter .+:"
    handler: mock-input-generic
  - regex: "Choose \\[\\d+-\\d+\\]"
    handler: mock-input-selection

handlers:
  mock-input-binary:
    script: ccpm/scripts/mock-input/tier1-matcher.sh
    args: ["$PROMPT", "BINARY"]

  mock-input-generic:
    script: ccpm/scripts/mock-input/main.sh
    args: ["$PROMPT"]

  mock-input-selection:
    script: ccpm/scripts/mock-input/tier2-inferencer.sh
    args: ["$PROMPT", "SELECTION", "$PROJECT_ROOT"]
```

## Phase 4: Testing and Validation (Week 4)

### 4.1 Unit Tests

**File:** `ccpm/tests/mock-input/test-safety-filter.sh`

```bash
#!/bin/bash
# Test safety filter

source ./ccpm/scripts/mock-input/safety-filter.sh

# Test: Should deny password prompts
result=$(echo "Enter password:" | safety_filter)
assert_equals "DENY" "$result" "Should deny password prompts"

# Test: Should deny API key prompts
result=$(echo "Enter your API key:" | safety_filter)
assert_equals "DENY" "$result" "Should deny API key prompts"

# Test: Should allow safe prompts
result=$(echo "Continue? [y/N]" | safety_filter)
assert_equals "ALLOW" "$result" "Should allow safe prompts"

# Test: Should deny destructive commands
result=$(echo "Run rm -rf? [y/N]" | safety_filter)
assert_equals "DENY" "$result" "Should deny destructive commands"
```

### 4.2 Integration Tests

**File:** `ccpm/tests/mock-input/test-integration.sh`

```bash
#!/bin/bash
# Integration test for mock-input system

# Test: Full flow for binary prompt
export CCPM_AUTO_MODE=true
result=$(./ccpm/scripts/mock-input/main.sh "Continue? [y/N]")
assert_equals "y" "$result" "Should return y for continue prompt"

# Test: Full flow with audit logging
./ccpm/scripts/mock-input/main.sh "Install packages? [y/N]"
assert_file_contains ".claude/logs/auto-decisions.jsonl" "Install packages"

# Test: Defer for unknown prompt
result=$(./ccpm/scripts/mock-input/main.sh "What is the meaning of life?")
assert_equals "DEFER" "$result" "Should defer unknown prompts"
```

### 4.3 Manual Test Scenarios

| Scenario | Input | Expected | Actual | Pass |
|----------|-------|----------|--------|------|
| Binary safe | "Continue? [y/N]" | "y" | | |
| Binary destructive | "Overwrite file? [y/N]" | "n" | | |
| Security deny | "Enter API key:" | "DENY" | | |
| Path inference | "Test directory:" | "tests/" or similar | | |
| Naming with consensus | "Component name:" | Follows pattern | | |
| Unknown defer | "Free text input:" | "DEFER" | | |

## Phase 5: Documentation and Rollout (Week 5)

### 5.1 User Documentation

Create:
- `docs/mock-input-guide.md` - User guide
- `docs/mock-input-config.md` - Configuration reference
- `docs/mock-input-safety.md` - Safety considerations

### 5.2 Rollout Plan

1. **Alpha** (Internal): Enable for CCPM repository CI/CD
2. **Beta** (Opt-in): Release with `enabled: false` default
3. **GA** (General): Enable by default for new projects

### 5.3 Monitoring

Track:
- Defer rate (should decrease over time as patterns improve)
- Accuracy (review audit logs for incorrect decisions)
- Safety filter hits (ensure no false negatives)

## File Structure Summary

```
ccpm/
├── commands/pm/
│   ├── mock-input.md          # Main command
│   └── fix-problem.md         # Updated with --auto
├── scripts/mock-input/
│   ├── main.sh                # Entry point
│   ├── safety-filter.sh       # Security checks
│   ├── classifier.sh          # Prompt classification
│   ├── tier1-matcher.sh       # Pattern matching
│   ├── tier2-inferencer.sh    # Context inference
│   └── audit-logger.sh        # Audit logging
├── config/
│   └── mock-input-schema.yml  # Config schema
├── hooks/
│   └── mock-input-hook.yml    # Hook integration
└── tests/mock-input/
    ├── test-safety-filter.sh
    ├── test-classifier.sh
    └── test-integration.sh
```

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Defer rate | <20% | Audit log analysis |
| Accuracy | >95% | Manual review of decisions |
| Safety filter false negative | 0% | Security audit |
| CI/CD unblock rate | >80% | Pipeline success rate |

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Wrong decision causes build failure | Reversibility + audit trail + easy disable |
| Security-sensitive prompt bypasses filter | Regular security review of deny patterns |
| Too many defers blocks execution | Improve patterns based on audit log analysis |
| Convention inference wrong | Only apply with >80% consensus |
