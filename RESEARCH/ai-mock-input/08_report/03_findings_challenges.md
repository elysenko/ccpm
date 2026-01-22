# Findings: Challenges and Safety Considerations

## The Safety Imperative

Google's Agent Development Kit documentation states: "The Agent Development Kit offers several mechanisms to establish strict boundaries, ensuring agents only perform actions explicitly allowed."

This reflects industry consensus: autonomous agents must operate within explicit constraints, not with unlimited freedom.

## Dangerous Actions: Never Auto-Decide

### Hard Deny-List (Consensus Across Sources)

| Category | Examples | Why Never Auto-Decide |
|----------|----------|----------------------|
| Credentials | API keys, passwords, tokens | Security breach risk |
| Financial | Payments, purchases, transfers | Legal/financial liability |
| Destructive Commands | `rm -rf`, `DROP TABLE`, `format` | Irreversible data loss |
| System Commands | Global package installs, system config | Environment corruption |
| Production Deploy | Deploy to prod, release to users | Business impact |
| Network | Arbitrary outbound connections | Data exfiltration risk |
| Permissions | `chmod`, `chown` on system files | Privilege escalation |
| Legal | EULA acceptance, license agreements | Contractual liability |
| Personal Data | PII collection, sharing | Privacy/compliance |
| Account Creation | External service registration | Identity binding |

*Sources: [Google ADK Safety](https://google.github.io/adk-docs/safety/), [Claude Code Hooks Guide](https://dev.to/rajeshroyal/hooks-how-to-put-guardrails-on-your-ai-coding-assistant-4gak)*

### Recommended Safety Rules
"Agents must never access or modify files outside the current workspace, must avoid using commands like `rm -rf`, `del /s`, `format`, or any system-level command unless explicitly instructed."

*Source: Google ADK Safety Documentation*

## Prompt Injection Risks

OWASP identifies prompt injection as the #1 LLM threat. In the context of auto-deciding:

**Risk:** If the system auto-responds to prompts, an attacker could craft input that appears as a legitimate prompt but triggers malicious actions.

**Mitigations:**
1. Input validation and sanitization
2. Output constraints (predefined response templates)
3. Behavioral monitoring for anomalies
4. Sandboxed execution environment

"Traditional perimeter defenses fail against prompt injection because the attack vector operates at the semantic layer, not the network or application layer."

*Source: [OWASP Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/), [Obsidian Security](https://www.obsidiansecurity.com/blog/prompt-injection)*

## LLM Confidence Calibration

Research shows significant challenges with LLM confidence scores:

**Finding:** "LLMs, when verbalizing their confidence, tend to be overconfident, potentially imitating human patterns of expressing confidence."

**Implication:** Cannot rely solely on LLM self-reported confidence to gate decisions.

**Finding:** "As model capability scales up, both calibration and failure prediction performance improve, yet still far from ideal performance."

**Implication:** Confidence scoring is useful but insufficient as sole decision gate.

*Source: [Can LLMs Express Their Uncertainty?](https://arxiv.org/abs/2306.13063)*

### Alternative: Conformal Prediction
Research shows conformal prediction can successfully gate robot actions:
- Generate candidate actions
- Calculate confidence for each
- If only one candidate remains after filtering: execute
- If multiple candidates remain: request human input

*Source: Same paper, robot planning section*

## Convention Inference Limitations

### The Consensus Problem
Naturalize research found: "When a codebase does not reflect consensus on a convention, NATURALIZE recommends nothing, because it has not learned anything with sufficient confidence to make recommendations."

**Implication:** Convention-based auto-decisions only work when:
- Codebase has consistent patterns (>80% agreement)
- Framework has well-documented conventions
- The decision falls within known convention categories

### Static vs Dynamic Typing
Research on developer context for AI assistants found: "Developers tend to provide less context when working with statically typed languages such as Go, C#, and Java... This suggests that developers expect stricter syntax and type checking in statically typed languages allow LLMs to infer more information directly from the code."

**Implication:** Auto-decision confidence should be higher for statically-typed codebases where more context is inferrable.

*Source: [Developer Context for AI Assistants](https://arxiv.org/html/2512.18925v1)*

## Synthetic Data Generation Challenges

### Faker Limitations
Faker libraries generate data independently per field: "First names do not match the expected Gender. This is because we generate each column independently of the others."

**Implication:** For related fields (e.g., generating a class name and corresponding file path), need custom logic that maintains consistency.

*Source: [Faker GitHub](https://github.com/joke2k/faker)*

### Property-Based Testing Constraints
"Many participants (17/30) talked about needing to generate values that satisfy some precondition. This can be extremely important for effective testing."

Complex constraints (valid paths, syntactically correct code, semantic relationships) are "extremely unlikely to be generated by a naïve random generator."

**Implication:** Simple Faker-style generation insufficient. Need constraint-aware generation that considers:
- File system state (does directory exist?)
- Codebase conventions (naming patterns)
- Semantic requirements (valid identifiers)

*Source: [Property-Based Testing in Practice](https://andrewhead.info/assets/pdf/pbt-in-practice.pdf)*

## Audit Trail Complexity

### What Must Be Captured

"An agent decision record (ADR) is a comprehensive log that documents the reasoning process behind an AI agent's actions. Key elements include:
- **Reasoning chain:** Demonstrating step-by-step logic proves that the agent followed a defensible process
- **Alternatives considered:** Showing that the agent evaluated multiple options proves it exercised judgment
- **Human oversight trail:** Prove that governance structures remain intact"

### Compliance Burden
"Major frameworks including SOX, GDPR, HIPAA, PCI DSS, and ISO 27001 mandate comprehensive activity logging for automated systems and AI agents."

**Implication:** Audit logging is not optional. Every auto-decision must be traceable.

*Source: [Audit Trails for Agents](https://www.adopt.ai/glossary/audit-trails-for-agents), [CI/CD Audit Trail Best Practices](https://prefactor.tech/blog/audit-trails-in-ci-cd-best-practices-for-ai-agents)*

## Summary: Key Challenges

| Challenge | Impact | Mitigation Strategy |
|-----------|--------|---------------------|
| Dangerous actions | Security/data loss | Hard deny-list, never override |
| Prompt injection | Attack vector | Input validation, sandboxing |
| LLM overconfidence | Wrong decisions | Multi-signal gating |
| No codebase consensus | Bad conventions | Only apply when consensus >80% |
| Related field generation | Inconsistent data | Constraint-aware generation |
| Compliance requirements | Audit overhead | Comprehensive logging framework |
