# Architecture Design: Mock Input Generator

## Overview

The mock-input system uses a three-tier decision architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                       PROMPT INTERCEPTOR                         │
│  Captures prompts from subprocess/tool/LLM requiring input       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SAFETY FILTER (First)                       │
│  Hard deny-list check - credentials, destructive, financial      │
│  If matches: DEFER immediately (never auto-decide)               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     DECISION CLASSIFIER                          │
│  Pattern match prompt to category:                               │
│  - Binary (Y/N)                                                  │
│  - File path                                                     │
│  - Naming choice                                                 │
│  - Configuration value                                           │
│  - Selection (1/2/3)                                            │
│  - Free-form text                                                │
│  - Unclassifiable                                                │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌───────────────────┐ ┌───────────────┐ ┌───────────────┐
│   TIER 1: FAST    │ │  TIER 2: SMART │ │ TIER 3: DEFER │
│  Pattern Matcher  │ │Context Inferencer│ │   Handler    │
│                   │ │                │ │               │
│ Binary → default  │ │ Naming → analyze│ │ Unknown → skip│
│ Config → framework│ │ codebase       │ │ Low conf → log│
│ Overwrite → n     │ │ Path → infer   │ │ Complex → fail│
└───────────────────┘ └───────────────┘ └───────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       AUDIT LOGGER                               │
│  Log: decision, reasoning, alternatives, confidence, reversible  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RESPONSE EMITTER                            │
│  Send response to waiting prompt OR signal deferral              │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Prompt Interceptor

**Purpose:** Capture prompts requiring user input before they block execution.

**Implementation Options:**
- **Expect-style:** Monitor stdout/stderr for prompt patterns
- **Wrapper script:** Intercept stdin/stdout of subprocess
- **Claude Code hooks:** Use pre/post tool execution hooks
- **PTY emulation:** Use pseudo-terminal to capture interactive prompts

**Recommended:** Claude Code hooks framework for integration with existing CCPM infrastructure.

```yaml
# .claude/hooks/prompt-intercept.yml
on: pre_tool_execution
match:
  - "Continue? [y/N]"
  - "Enter * :"
  - "Choose [*]:"
action: mock_input_handler
```

### 2. Safety Filter

**Purpose:** Immediately reject dangerous input requests. No exceptions.

**Hard Deny-List Patterns:**
```python
NEVER_AUTO_DECIDE = [
    r"(api[_-]?key|password|token|secret|credential)",
    r"(rm\s+-rf|DROP\s+TABLE|DELETE\s+FROM|format\s+)",
    r"(deploy|release|publish)\s+(to\s+)?(prod|production)",
    r"(payment|purchase|transfer|charge|billing)",
    r"(chmod|chown|sudo)",
    r"(accept|agree).*(license|eula|terms)",
    r"(email|phone|ssn|social.security|address)",
]
```

**Action on Match:** Return `DEFER` signal. Log attempt. Never proceed.

### 3. Decision Classifier

**Purpose:** Categorize prompt type to route to appropriate handler.

**Classification Rules:**

| Pattern | Category | Tier |
|---------|----------|------|
| `[y/n]`, `[Y/N]`, `yes/no` | Binary | 1 |
| `Continue?`, `Proceed?` | Binary | 1 |
| `Overwrite?`, `Replace?` | Binary (Destructive) | 1 |
| `Enter path:`, `File:`, `Directory:` | File Path | 2 |
| `Name:`, `Enter name:` | Naming | 2 |
| `Port:`, `Timeout:`, `Count:` | Config Value | 1 |
| `Choose [1-n]:`, `Select:` | Selection | 2 |
| `Description:`, `Enter:` (free-form) | Free-form | 3 |
| No match | Unclassifiable | 3 |

**LLM Fallback:** For ambiguous prompts, use LLM to classify with prompt:
```
Classify this prompt into one category:
- BINARY (yes/no question)
- PATH (file or directory path)
- NAMING (name for something)
- CONFIG (configuration value)
- SELECTION (choose from options)
- FREEFORM (arbitrary text)
- UNKNOWN

Prompt: "{prompt_text}"
Category:
```

### 4. Tier 1: Pattern Matcher (Fast Path)

**Purpose:** Handle common prompts with configured defaults.

**Configuration File:**
```yaml
# .claude/auto-decisions.yml
binary:
  default: "y"  # Non-destructive default
  patterns:
    - match: "Overwrite"
      response: "n"  # Conservative for file operations
    - match: "Delete"
      response: "n"
    - match: "Continue"
      response: "y"
    - match: "Install"
      response: "y"

config_values:
  port: 3000
  timeout: 30
  retries: 3

framework_defaults:
  rails:
    database: "sqlite3"
    test_framework: "minitest"
  nextjs:
    src_directory: true
    app_router: true
  go:
    module_path: "github.com/${REPO_OWNER}/${REPO_NAME}"
```

### 5. Tier 2: Context Inferencer (Smart Path)

**Purpose:** Make context-aware decisions based on codebase analysis.

**For Naming Decisions:**
```python
def infer_name(prompt_context, codebase_path):
    # 1. Analyze existing naming patterns
    existing_names = extract_similar_names(codebase_path, prompt_context.type)

    # 2. Check for consensus (>80% same pattern)
    pattern = detect_pattern(existing_names)  # kebab-case, camelCase, etc.
    consensus = calculate_consensus(existing_names, pattern)

    if consensus < 0.8:
        return DEFER  # No clear convention

    # 3. Generate name following pattern
    suggested_name = generate_following_pattern(prompt_context, pattern)

    return Response(
        value=suggested_name,
        confidence=consensus,
        reasoning=f"Following {pattern} convention (consensus: {consensus:.0%})"
    )
```

**For Path Decisions:**
```python
def infer_path(prompt_context, codebase_path):
    # 1. Check if prompt mentions specific location
    if "test" in prompt_context.lower():
        base = find_test_directory(codebase_path)
    elif "config" in prompt_context.lower():
        base = find_config_directory(codebase_path)
    else:
        base = codebase_path

    # 2. Generate appropriate path
    if prompt_context.expects_directory:
        return os.path.join(base, "generated")
    else:
        extension = infer_extension(prompt_context)
        return os.path.join(base, f"generated.{extension}")
```

**For Selection Decisions:**
```python
def infer_selection(options, prompt_context):
    # 1. Check for "default" or "recommended" indicator
    for i, option in enumerate(options):
        if "default" in option.lower() or "recommended" in option.lower():
            return i + 1

    # 2. Check codebase for existing similar choices
    existing_choice = find_similar_choice(codebase_path, options)
    if existing_choice:
        return existing_choice

    # 3. Use first option as fallback (most common default)
    return 1
```

### 6. Tier 3: Deferral Handler (Safe Path)

**Purpose:** Handle cases where auto-decision is not safe or confident.

**Deferral Strategies:**

| Situation | Strategy |
|-----------|----------|
| Unclassifiable prompt | Skip with warning log |
| Low confidence (<60%) | Use safe default if exists, else skip |
| Free-form text required | Generate placeholder, mark for review |
| Complex multi-step | Break into smaller decisions, defer complex parts |

**Skip Response:**
```python
def handle_defer(prompt_context, reason):
    log_decision(
        prompt=prompt_context.text,
        decision="DEFERRED",
        reason=reason,
        alternatives=["Manual input required", "Skip this step"]
    )

    if prompt_context.allows_skip:
        return Response(value="", action="skip")
    elif prompt_context.allows_abort:
        return Response(value="", action="abort")
    else:
        raise DeferralError(f"Cannot auto-decide: {reason}")
```

### 7. Audit Logger

**Purpose:** Maintain complete audit trail for every decision.

**Log Schema:**
```json
{
  "timestamp": "2026-01-21T10:30:45Z",
  "prompt_id": "uuid-1234",
  "prompt_text": "Continue? [y/N]",
  "classification": "BINARY",
  "tier": 1,
  "decision": "y",
  "confidence": 0.95,
  "reasoning": "Non-destructive binary confirmation, using default 'yes'",
  "alternatives_considered": ["n"],
  "reversible": true,
  "rollback_command": null,
  "context": {
    "command": "npm install",
    "working_dir": "/project",
    "file_being_modified": null
  }
}
```

**Storage:** Append to `.claude/logs/auto-decisions.jsonl` (JSON Lines format)

### 8. Response Emitter

**Purpose:** Send response back to waiting prompt.

**Methods:**
- **PTY write:** Send characters to pseudo-terminal
- **Stdin pipe:** Write to subprocess stdin
- **Expect send:** Use expect-style send command
- **Environment variable:** Set response for tools that read from env

```python
def emit_response(response, method="stdin"):
    if method == "stdin":
        subprocess.stdin.write(f"{response.value}\n")
        subprocess.stdin.flush()
    elif method == "pty":
        os.write(master_fd, f"{response.value}\r".encode())
    elif method == "expect":
        pexpect_child.sendline(response.value)
```

## Configuration Schema

```yaml
# .claude/mock-input.yml
version: 1

enabled: true
log_level: info
log_file: .claude/logs/auto-decisions.jsonl

safety:
  deny_patterns:
    - "password|secret|token|key|credential"
    - "rm -rf|DROP TABLE|DELETE FROM"
    - "deploy.*prod|release.*production"

  max_confidence_for_destructive: 0.9
  require_reversible: true

tier1:
  binary_default: "y"
  binary_destructive_default: "n"
  config_defaults:
    port: 3000
    timeout: 30

tier2:
  convention_consensus_threshold: 0.8
  naming_patterns:
    - name: kebab-case
      regex: "^[a-z]+(-[a-z]+)*$"
    - name: camelCase
      regex: "^[a-z]+([A-Z][a-z]+)*$"
    - name: snake_case
      regex: "^[a-z]+(_[a-z]+)*$"

tier3:
  on_defer: skip  # skip, abort, or placeholder
  placeholder_template: "AUTO_GENERATED_{UUID}"

audit:
  enabled: true
  include_reasoning: true
  include_alternatives: true
  retention_days: 30
```

## Decision Flow Diagram

```
Prompt Received
      │
      ▼
┌───────────────┐
│ Safety Check  │──── Match? ────► DEFER (Never auto-decide)
└───────────────┘
      │ No match
      ▼
┌───────────────┐
│   Classify    │
└───────────────┘
      │
      ├── Binary ────────────► Tier 1 → Default response
      │
      ├── Config Value ──────► Tier 1 → Framework default
      │
      ├── File Path ─────────► Tier 2 → Infer from context
      │
      ├── Naming ────────────► Tier 2 → Analyze conventions
      │
      ├── Selection ─────────► Tier 2 → Find default/similar
      │
      ├── Free-form ─────────► Tier 3 → Placeholder or defer
      │
      └── Unknown ───────────► Tier 3 → Skip or abort
              │
              ▼
        Log Decision
              │
              ▼
        Emit Response
```
