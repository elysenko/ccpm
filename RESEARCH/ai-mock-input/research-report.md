# AI Agent Mock Input Generation: Deep Research Report

**Research Question:** How can autonomous AI agents handle situations requiring human input by generating contextually-appropriate mock/synthetic decisions, enabling unblocked execution in CI/CD and batch processing scenarios?

**Date:** 2026-01-21
**Confidence Level:** High
**Methodology:** 7-phase Graph of Thoughts deep research with 21 queries across 30 sources

---

## Executive Summary

Autonomous AI coding agents (SWE-Agent, Devin, OpenHands, Aider, Claude Code) already implement robust patterns for making decisions without human input. The key approach is **tool-constrained autonomy**: give the LLM full context and a limited set of allowed tools, let it decide within boundaries, and enforce step limits.

### Key Findings

1. **Decision Types Are Classifiable** - Input prompts can be reliably classified into categories with deterministic resolution strategies
2. **Safety Boundaries Are Well-Defined** - Industry consensus exists on decisions that should never be automated
3. **Reversibility Enables Confidence** - The safest auto-decisions are those that can be undone
4. **Audit Trails Are Non-Negotiable** - Every auto-decision must be logged for debugging and compliance

### Recommended Architecture

A three-tier approach:
1. **Pattern Matcher** (Fast Path): Handle common prompts (Y/N, file overwrite) with configured responses
2. **Context Inferencer** (Smart Path): Use codebase analysis for naming/convention decisions
3. **Deferral Handler** (Safe Path): Skip or use safe defaults when confidence is low

---

## Table of Contents

1. [Current State of AI Agent Decision-Making](#1-current-state-of-ai-agent-decision-making)
2. [Decision Classification Taxonomy](#2-decision-classification-taxonomy)
3. [Safety Boundaries](#3-safety-boundaries)
4. [Architecture Design](#4-architecture-design)
5. [Decision Tree](#5-decision-tree)
6. [Implementation Plan for CCPM](#6-implementation-plan-for-ccpm)
7. [Risks and Limitations](#7-risks-and-limitations)
8. [References](#8-references)

---

## 1. Current State of AI Agent Decision-Making

### Existing Agent Architectures

| Agent | Autonomy Level | Key Mechanism | Human Escalation |
|-------|---------------|---------------|------------------|
| SWE-Agent | High | LLM decides within tool constraints | Step limit |
| OpenHands | High | Non-interactive with configurable limits | Timeout |
| Aider | Configurable | --yes-always flag | --dry-run |
| Claude Code | Configurable | Tool allowlists | --allowedTools |
| Devin | Confidence-gated | Green/Yellow/Red flagging | Red tasks |
| AutoGPT | Maximum | Self-prompting | None (problematic) |

**Consensus:** The most successful approaches use **configurable, constrained autonomy** rather than unlimited self-direction.

### Key Patterns Identified

**Pattern 1: Tool-Constrained Autonomy (Claude Code, SWE-Agent, OpenHands)**
```yaml
Config: allowedTools = ["Read", "Write", "Grep"]
Execution: LLM chooses from allowed tools only
Limits: max_steps=100, timeout, file scope
```

**Pattern 2: Explicit Auto-Accept Flags (Aider)**
```bash
aider --yes-always --message "add docstrings" file.py
```

**Pattern 3: Confidence-Gated Escalation (Devin)**
- Green tasks: Proceed autonomously
- Yellow tasks: Proceed with logging
- Red tasks: Request human review

**Pattern 4: Convention Inference (Rails, Naturalize)**
- Analyze codebase patterns
- Only apply when consensus > 80%
- Fall back to safe defaults otherwise

### CI/CD Non-Interactive Patterns

Standard mechanisms exist for handling interactive prompts in CI:

```yaml
# apt-get
env:
  DEBIAN_FRONTEND: noninteractive
run: sudo apt-get install -y package

# npm
run: npm ci  # CI-specific, no prompts

# GitHub CLI
run: gh config set prompt disabled
```

The **Expect utility** provides a classic pattern for automating interactive prompts:
```expect
spawn ./installer
expect "Continue? [y/N]"
send "y\r"
expect eof
```

---

## 2. Decision Classification Taxonomy

### Prompt Categories

| Category | Examples | Auto-Decision Strategy | Confidence |
|----------|----------|----------------------|------------|
| **Binary Confirmation** | "Continue? [y/N]", "Overwrite? [y/n]" | Yes for non-destructive, No for destructive | High |
| **File Path** | "Enter output file:", "Config location?" | Infer from context or use temp | Medium |
| **Naming** | "Name for component:", "Variable name?" | Analyze codebase conventions | Medium |
| **Configuration Value** | "Port number:", "Timeout seconds?" | Use framework defaults | High |
| **Selection** | "Choose [1-3]:" | Select marked default or first option | Low-Medium |
| **Free-form Text** | "Enter description:" | Generate placeholder or defer | Low |
| **Credentials** | "API key:", "Password:" | **NEVER auto-decide** | N/A |

### Classification Logic

```python
def classify_prompt(prompt_text):
    # Binary patterns
    if re.search(r'\[y/n\]|\[Y/N\]|yes/no', prompt_text, re.I):
        return "BINARY"

    # Path patterns
    if re.search(r'path:|file:|directory:|folder:|location:', prompt_text, re.I):
        return "PATH"

    # Naming patterns
    if re.search(r'name:|enter.*name|component.*name', prompt_text, re.I):
        return "NAMING"

    # Config patterns
    if re.search(r'port:|timeout:|count:|number:|value:', prompt_text, re.I):
        return "CONFIG"

    # Selection patterns
    if re.search(r'choose|select|\[1-[0-9]\]|option', prompt_text, re.I):
        return "SELECTION"

    return "UNKNOWN"
```

---

## 3. Safety Boundaries

### Never Auto-Decide List (Industry Consensus)

| Category | Examples | Rationale |
|----------|----------|-----------|
| **Credentials** | API keys, passwords, tokens | Security breach risk |
| **Financial** | Payments, purchases, transfers | Legal/financial liability |
| **Destructive Commands** | `rm -rf`, `DROP TABLE`, `format` | Irreversible data loss |
| **System Commands** | Global package installs, system config | Environment corruption |
| **Production Deploy** | Deploy to prod, release to users | Business impact |
| **Network** | Arbitrary outbound connections | Data exfiltration risk |
| **Permissions** | `chmod`, `chown` on system files | Privilege escalation |
| **Legal** | EULA acceptance, license agreements | Contractual liability |
| **Personal Data** | PII collection, sharing | Privacy/compliance |
| **Account Creation** | External service registration | Identity binding |

### Safety Filter Implementation

```python
NEVER_AUTO_DECIDE = [
    r"(api[_-]?key|password|token|secret|credential)",
    r"(rm\s+-rf|DROP\s+TABLE|DELETE\s+FROM|format\s+)",
    r"(deploy|release|publish)\s+(to\s+)?(prod|production)",
    r"(payment|purchase|transfer|charge|billing)",
    r"(chmod|chown|sudo)",
    r"(accept|agree).*(license|eula|terms)",
]

def safety_check(prompt):
    for pattern in NEVER_AUTO_DECIDE:
        if re.search(pattern, prompt, re.I):
            return "DENY"
    return "ALLOW"
```

### Reversibility Framework

| Action Type | Reversibility | Strategy |
|-------------|--------------|----------|
| File Write | High | Git-tracked, backup before |
| File Delete | Medium | Move to trash first |
| Config Change | High | Store previous value |
| Package Install | Medium | Lock file tracks changes |
| Git Commit | High | Can revert |
| Git Push | Low | Harder to undo main |
| Database Schema | Low | Requires migration |
| External API Call | None | Cannot undo |

---

## 4. Architecture Design

### System Architecture

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
│  Binary, Path, Naming, Config, Selection, Free-form, Unknown     │
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
```

### Configuration Schema

```yaml
# .claude/mock-input.yml
version: 1
enabled: true

safety:
  deny_patterns:
    - "password|secret|token|key|credential"
    - "rm -rf|DROP TABLE|DELETE FROM"
    - "deploy.*prod|release.*production"

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

tier3:
  on_defer: skip  # skip, abort, or placeholder

audit:
  enabled: true
  log_file: ".claude/logs/auto-decisions.jsonl"
```

### Audit Log Schema

```json
{
  "timestamp": "2026-01-21T10:30:45Z",
  "prompt_text": "Continue? [y/N]",
  "classification": "BINARY",
  "tier": 1,
  "decision": "y",
  "confidence": 0.95,
  "reasoning": "Non-destructive binary confirmation, using default 'yes'",
  "alternatives_considered": ["n"],
  "reversible": true,
  "context": {
    "command": "npm install",
    "working_dir": "/project"
  }
}
```

---

## 5. Decision Tree

### Master Decision Flow

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
      ├── Binary ────────────► Default response (y/n based on context)
      │
      ├── Config Value ──────► Framework default (3000, 30, etc.)
      │
      ├── File Path ─────────► Infer from context or use temp
      │
      ├── Naming ────────────► Analyze conventions (if consensus > 80%)
      │
      ├── Selection ─────────► Find default option or use first
      │
      ├── Free-form ─────────► Placeholder or defer
      │
      └── Unknown ───────────► Skip or abort
```

### Binary Decision Rules

| Prompt Pattern | Response | Rationale |
|----------------|----------|-----------|
| "Continue?" | YES | Non-destructive progress |
| "Proceed?" | YES | Non-destructive progress |
| "Install?" | YES | Usually safe, reversible |
| "Overwrite?" | NO | Destructive, conservative |
| "Delete?" | NO | Destructive, conservative |
| "Replace?" | NO | Destructive, conservative |

**Exception:** If file is git-tracked (reversible), "Overwrite?" can be YES.

### Confidence Thresholds

| Threshold | Action |
|-----------|--------|
| > 0.9 | Auto-decide, minimal logging |
| 0.7 - 0.9 | Auto-decide, full logging |
| 0.5 - 0.7 | Auto-decide with warning flag |
| < 0.5 | Defer |

---

## 6. Implementation Plan for CCPM

### Phase 1: Core Infrastructure (Week 1)

1. Create configuration schema (`ccpm/config/mock-input-schema.yml`)
2. Implement safety filter (`ccpm/scripts/mock-input/safety-filter.sh`)
3. Implement decision classifier (`ccpm/scripts/mock-input/classifier.sh`)

### Phase 2: Decision Handlers (Week 2)

1. Tier 1 pattern matcher for common prompts
2. Tier 2 context inferencer for naming/paths
3. Audit logger for all decisions

### Phase 3: CCPM Integration (Week 3)

1. Create `/pm:mock-input` command
2. Integrate with `fix-problem --auto` mode
3. Add hooks for prompt interception

### Phase 4: Testing (Week 4)

1. Unit tests for safety filter
2. Integration tests for full flow
3. Manual test scenarios

### Phase 5: Rollout (Week 5)

1. Alpha: Internal CCPM CI/CD
2. Beta: Opt-in with `enabled: false` default
3. GA: Enable by default for new projects

### File Structure

```
ccpm/
├── commands/pm/
│   └── mock-input.md          # Main command
├── scripts/mock-input/
│   ├── main.sh                # Entry point
│   ├── safety-filter.sh       # Security checks
│   ├── classifier.sh          # Prompt classification
│   ├── tier1-matcher.sh       # Pattern matching
│   ├── tier2-inferencer.sh    # Context inference
│   └── audit-logger.sh        # Audit logging
├── config/
│   └── mock-input-schema.yml  # Config schema
└── hooks/
    └── mock-input-hook.yml    # Hook integration
```

### Integration with fix-problem

```bash
# Current usage
/pm:fix-problem "Build is failing"

# Enhanced autonomous mode
/pm:fix-problem --auto "Build is failing with TypeScript errors"
```

Environment variables:
- `CCPM_AUTO_MODE=true` - Enable autonomous mode
- `CCPM_MOCK_INPUT_STRICT=true` - Fail instead of defer on unknown prompts

---

## 7. Risks and Limitations

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Security-sensitive input auto-filled | Low | Critical | Hard-coded deny-list, fail-closed |
| Cascading failures from bad decision | Medium | High | Step limits, audit trail, dry-run |
| Convention inference wrong | Medium | Medium | 80% consensus threshold, reversibility |
| LLM classifier misclassifies | Medium | Medium | Pattern matching first, defer on unknown |
| Prompt injection attack | Low | High | Input validation, sandboxing |

### Limitations

1. **Cannot handle truly novel prompts** - Unknown categories always defer
2. **Convention inference requires existing codebase** - Empty projects use framework defaults
3. **No cross-project learning** - Each project configured independently
4. **Confidence scores are heuristic** - Not true probability estimates
5. **Limited to text-based prompts** - GUI dialogs not supported
6. **English-only pattern matching** - Internationalized tools may fail

### What Would Change Our Conclusions

| Trigger | Impact |
|---------|--------|
| Major security breach from auto-decision | Re-evaluate approach, add more guardrails |
| LLM confidence calibration improves significantly | Can rely more on confidence scores |
| New prompt injection vectors discovered | Update safety filter patterns |
| Standardized prompt format emerges | Simplify classification logic |

---

## 8. References

### AI Agent Frameworks
- [SWE-agent GitHub](https://github.com/SWE-agent/SWE-agent) - Princeton/NeurIPS 2024 autonomous coding agent
- [OpenHands GitHub](https://github.com/OpenHands/OpenHands) - AI-driven development platform
- [Aider GitHub](https://github.com/Aider-AI/aider) - AI pair programming in terminal
- [Aider Scripting Docs](https://aider.chat/docs/scripting.html) - Non-interactive usage guide
- [Claude Code GitHub](https://github.com/anthropics/claude-code) - Anthropic's agentic coding tool
- [Claude Code Headless Mode](https://www.claudecode101.com/en/tutorial/advanced/headless-mode) - CI/CD integration
- [Devin AI](https://devin.ai/) - Cognition's AI software engineer

### Safety and Security
- [Google ADK Safety](https://google.github.io/adk-docs/safety/) - Agent Development Kit safety mechanisms
- [OWASP Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/) - LLM security guidelines
- [Claude Code Guardrails](https://dev.to/rajeshroyal/hooks-how-to-put-guardrails-on-your-ai-coding-assistant-4gak) - Hooks for safety

### Convention Over Configuration
- [Ruby on Rails Doctrine](https://rubyonrails.org/doctrine) - Original CoC philosophy
- [Convention Over Configuration (Wikipedia)](https://en.wikipedia.org/wiki/Convention_over_configuration) - Overview
- [Next.js Project Structure](https://nextjs.org/docs/app/getting-started/project-structure) - File conventions
- [Naturalize Paper](https://homepages.inf.ed.ac.uk/csutton/publications/naturalize.pdf) - Microsoft Research on convention inference

### Synthetic Data and Testing
- [Faker Python](https://github.com/joke2k/faker) - Fake data generation
- [Property-Based Testing in Practice](https://andrewhead.info/assets/pdf/pbt-in-practice.pdf) - Academic research

### Audit and Compliance
- [Audit Trails for Agents](https://www.adopt.ai/glossary/audit-trails-for-agents) - Best practices
- [CI/CD Audit Trail Best Practices](https://prefactor.tech/blog/audit-trails-in-ci-cd-best-practices-for-ai-agents) - Compliance guidance

### LLM Confidence
- [Can LLMs Express Their Uncertainty?](https://arxiv.org/abs/2306.13063) - Academic paper on confidence calibration

### CI/CD Patterns
- [GitHub Actions Non-Interactive](https://www.yellowduck.be/posts/avoid-tzdata-prompts-in-github-actions) - DEBIAN_FRONTEND
- [CLI Guidelines](https://clig.dev/) - Best practices for CLI tools
- [Expect Utility](https://linuxconfig.org/how-to-automate-interactive-cli-commands-with-expect) - Interactive automation

---

## Appendix: Full Research Artifacts

All research artifacts are available in:
```
./RESEARCH/ai-mock-input/
├── 00_research_contract.md     # Scope definition
├── 01_research_plan.md         # Query strategy
├── 01a_perspectives.md         # Expert viewpoints
├── 01b_hypotheses.md           # Testable hypotheses
├── 02_query_log.csv            # 21 queries executed
├── 03_source_catalog.csv       # 30 sources graded
├── 04_evidence_ledger.csv      # Claims and evidence
├── 05_contradictions_log.md    # Resolved tensions
├── 07_working_notes/           # Synthesis notes
├── 08_report/                  # Report sections
└── 09_qa/                      # QA audit results
```

---

*Report generated using 7-phase Graph of Thoughts deep research methodology. All C1 claims verified against multiple independent sources. QA audit passed with no hallucinations detected.*
