---
name: synthesis-notes
created: 2026-01-21T00:00:00Z
---

# Synthesis Notes: AI Agent Mock Input Generation

## Hypothesis Validation

### H1: Context-Based Decision Making is Standard Practice
**CONFIRMED (High Confidence)**
- SWE-Agent, Devin, OpenHands, Aider, Claude Code all implement autonomous decision patterns
- Pattern: Give LLM full context + tools, let it decide within boundaries
- Key: Configurable step limits and tool restrictions

### H2: Convention-Over-Configuration Patterns Are Transferable
**CONFIRMED (Medium-High Confidence)**
- Rails "omakase" philosophy directly applicable
- Naturalize research validates: inference works when consensus exists
- Key insight: Only apply conventions when codebase shows >80% consistency

### H3: Decision Classification Is Feasible
**CONFIRMED (Medium Confidence)**
- NVIDIA classifier demonstrates 11 task categories work
- Simple pattern matching handles ~80% of cases (Y/N, file operations)
- Complex cases need LLM-based classification

### H4: Confidence Scoring Can Gate Auto-Decisions
**PARTIALLY CONFIRMED (Medium Confidence)**
- LLMs are overconfident, scores alone insufficient
- Conformal prediction shows multi-signal approach works
- Recommendation: Combine confidence + reversibility + domain rules

### H5: Safe Defaults Exist for Most Non-Security Decisions
**CONFIRMED (High Confidence)**
- CI/CD ecosystem proves this with -y flags, DEBIAN_FRONTEND
- Key: Defaults must be reversible and logged
- Explicit deny-list for dangerous operations (rm -rf, etc.)

## Core Architecture Patterns Identified

### Pattern 1: Tool-Constrained Autonomy (Claude Code, OpenHands)
```
Config: allowedTools = ["Read", "Write", "Grep"]
Execution: LLM chooses from allowed tools only
Limits: max_steps, timeout, file scope
```

### Pattern 2: Expect-Style Pattern Matching (Traditional)
```
Expect: "Continue? [y/N]"
Send: "y"
Expect: "Enter filename:"
Send: {inferred_or_default_filename}
```

### Pattern 3: Convention Inference (Rails, Naturalize)
```
Analyze: codebase patterns
If consensus > threshold:
  Apply convention
Else:
  Defer or use safe default
```

### Pattern 4: Decision Tree with Fallback (RAGents)
```
Branch: classify input type
  -> Y/N: apply safe default (usually Y for non-destructive)
  -> Path: infer from context or use temp path
  -> Name: follow codebase conventions
  -> Config: use framework defaults
Default: defer to human or skip
```

### Pattern 5: Confidence-Gated Execution (Research)
```
Generate: response + confidence score
If confidence > 0.8 AND reversible:
  Execute
Elif confidence > 0.6:
  Execute with warning log
Else:
  Defer
```

## Decision Categories Taxonomy

| Category | Examples | Auto-Decision Strategy | Confidence |
|----------|----------|----------------------|------------|
| Binary Confirmation | "Continue? [y/N]", "Overwrite? [y/n]" | Yes for non-destructive, No for destructive | High |
| File Path | "Enter output file:", "Config location?" | Infer from context or use temp | Medium |
| Naming | "Name for component:", "Variable name?" | Analyze codebase conventions | Medium |
| Configuration Value | "Port number:", "Timeout seconds?" | Use framework defaults | High |
| Selection from Options | "Choose [1-3]:" | Analyze context, pick most likely | Low-Medium |
| Free-form Text | "Enter description:" | Generate based on context | Low |
| Credentials/Secrets | "API key:", "Password:" | NEVER auto-decide | N/A |

## Safety Boundaries (Never Auto-Decide)

1. **Credentials/Secrets** - API keys, passwords, tokens
2. **Financial Operations** - Payments, transfers, purchases
3. **Destructive Commands** - rm -rf, DROP TABLE, format
4. **System-Wide Changes** - Package manager globals, system config
5. **Network Operations** - Arbitrary outbound connections
6. **Permission Changes** - chmod, chown on system files
7. **Production Deployments** - Deploy to prod environments
8. **License Agreements** - EULA acceptance
9. **Personal Data** - PII collection/sharing
10. **External Service Registration** - Account creation

## Reversibility Framework

| Action Type | Reversibility | Strategy |
|-------------|--------------|----------|
| File Write | High | Git-tracked, backup before |
| File Delete | Medium | Move to trash first |
| Config Change | High | Store previous value |
| Package Install | Medium | Lock file tracks changes |
| Git Commit | High | Can revert |
| Git Push | Low | Harder to undo |
| Database Schema | Low | Requires migration |
| External API Call | None | Cannot undo |

## Audit Trail Requirements (from Research)

Every auto-decision must log:
1. **What** - The decision made
2. **Why** - Reasoning/context that led to decision
3. **Alternatives** - What other options existed
4. **Confidence** - How certain the system was
5. **Reversibility** - How to undo if needed
6. **Timestamp** - When it happened

## Integration Points for CCPM

### 1. fix-problem Command Enhancement
```
Current: fix-problem prompts for user input
Enhanced: fix-problem --auto uses mock-input
```

### 2. New mock-input Skill
```
Input: Raw prompt text + context
Output: Generated response OR defer signal
```

### 3. Decision Registry
```yaml
# .claude/auto-decisions.yml
confirmations:
  "Continue? [y/N]": "y"
  "Overwrite? [y/n]": "n"  # Conservative default
paths:
  output_dir: "${PROJECT_ROOT}/output"
naming:
  infer_from_codebase: true
  fallback_pattern: "kebab-case"
```

### 4. Hooks Integration
```
# Use existing Claude Code hooks framework
PrePrompt: Intercept user prompts
AutoRespond: Generate mock response
PostDecision: Log audit trail
```
