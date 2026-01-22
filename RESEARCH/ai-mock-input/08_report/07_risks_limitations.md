# Risks, Mitigations, and Limitations

## Risk Assessment

### High Priority Risks

#### R1: Security-Sensitive Input Auto-Filled
**Risk:** Safety filter fails to catch a security-sensitive prompt, leading to credential exposure or unauthorized action.

**Likelihood:** Low (with proper deny-list)
**Impact:** Critical

**Mitigations:**
1. Comprehensive deny-list covering all known sensitive patterns
2. Regular security audit of deny patterns
3. Fail-closed design: unknown prompts defer, not proceed
4. Separate audit log for all auto-decisions for post-hoc review
5. Clear documentation that credentials should NEVER be in environment or config

**Residual Risk:** Accept - with mitigations, risk is manageable

#### R2: Cascading Failures from Bad Decision
**Risk:** One incorrect auto-decision triggers a chain of failures that are difficult to diagnose.

**Likelihood:** Medium
**Impact:** High

**Mitigations:**
1. Step limits prevent infinite loops
2. Reversibility check before proceeding
3. Comprehensive audit logging with full context
4. Dry-run mode for testing
5. Easy kill switch (CCPM_AUTO_MODE=false)

**Residual Risk:** Accept - audit trail enables quick diagnosis

### Medium Priority Risks

#### R3: Convention Inference Applies Wrong Pattern
**Risk:** System infers naming convention incorrectly when codebase has mixed patterns.

**Likelihood:** Medium
**Impact:** Medium (usually reversible)

**Mitigations:**
1. 80% consensus threshold before applying conventions
2. Only apply to git-tracked files (reversible)
3. Log reasoning for review
4. Option to disable convention inference entirely

**Residual Risk:** Accept - impact is low and reversible

#### R4: LLM Classifier Misclassifies Prompt
**Risk:** When pattern matching fails and LLM fallback is used, misclassification routes to wrong handler.

**Likelihood:** Medium
**Impact:** Medium

**Mitigations:**
1. Pattern matching handles ~80% of cases without LLM
2. Unknown classification routes to defer (safe default)
3. Confidence threshold for LLM classifications
4. Manual override patterns in config

**Residual Risk:** Accept - deferral is safe fallback

#### R5: Prompt Injection via Crafted Input
**Risk:** Attacker crafts input that appears as legitimate prompt but triggers malicious action.

**Likelihood:** Low
**Impact:** High

**Mitigations:**
1. Input validation before processing
2. Sandboxed execution environment
3. Output constraints (predefined response templates)
4. Behavioral monitoring for anomalies
5. Safety filter runs first, before any classification

**Residual Risk:** Monitor - requires ongoing vigilance

### Lower Priority Risks

#### R6: Too Many Defers Block Execution
**Risk:** Conservative safety settings cause too many prompts to defer, blocking autonomous operation.

**Likelihood:** Medium (initially)
**Impact:** Low (falls back to interactive)

**Mitigations:**
1. Start with conservative settings, tune based on audit log
2. Allow pattern additions via config
3. Monitor defer rate as success metric
4. Provide "what blocked" summary at end of execution

**Residual Risk:** Accept - improves over time

#### R7: Audit Log Grows Too Large
**Risk:** Comprehensive logging fills disk space over time.

**Likelihood:** Medium
**Impact:** Low

**Mitigations:**
1. Log rotation policy (default: 30 days)
2. Configurable retention period
3. JSON Lines format enables easy truncation
4. Option to reduce logging verbosity

**Residual Risk:** Accept - operational concern, not functional

## Limitations

### L1: Cannot Handle Truly Novel Prompts
The system relies on pattern matching and conventions. Prompts that don't fit any known category will always defer. This is by design (fail-safe) but limits full autonomy.

**Workaround:** Extend patterns as new common prompts are identified.

### L2: Convention Inference Requires Existing Codebase
For naming and path decisions, the system analyzes existing code. New/empty projects cannot benefit from convention inference.

**Workaround:** Fall back to framework defaults (Rails, Next.js conventions) or defer.

### L3: No Cross-Project Learning
Each project's configuration is independent. Patterns learned in one project don't transfer to others.

**Workaround:** Share configuration templates across projects.

### L4: Confidence Scores Are Heuristic
The confidence values are based on heuristics (consensus percentage, pattern match quality) not true probability estimates.

**Workaround:** Use conservative thresholds and validate via audit log review.

### L5: Limited to Text-Based Prompts
The system handles text prompts only. GUI dialogs, browser confirmations, or other non-CLI inputs are not supported.

**Workaround:** Use headless/CI-friendly tools that provide CLI interfaces.

### L6: English-Only Pattern Matching
Current patterns assume English prompts. Internationalized tools may not be handled correctly.

**Workaround:** Add locale-specific patterns as needed.

## What Would Change Our Conclusions

| Trigger | Impact |
|---------|--------|
| Major security breach from auto-decision | Re-evaluate entire approach, add more guardrails |
| LLM confidence calibration improves significantly | Can rely more on confidence scores for gating |
| New prompt injection attack vectors discovered | Update safety filter patterns |
| Standardized prompt format emerges | Simplify classification logic |
| Better tools for convention inference | Lower consensus threshold |

## Monitoring Requirements

### Key Metrics to Track

1. **Defer Rate** - Percentage of prompts that defer
   - Target: <20%
   - Action if high: Analyze audit log, add patterns

2. **Decision Accuracy** - Percentage of correct auto-decisions
   - Target: >95%
   - Action if low: Review and fix patterns

3. **Safety Filter Hits** - Prompts blocked by safety filter
   - Target: 0 false negatives
   - Action: Regular security review

4. **Time Savings** - Time saved vs interactive mode
   - Target: Measurable improvement
   - Action: Track in CI/CD metrics

### Audit Review Process

Weekly review of auto-decisions.jsonl:
1. Sample 10% of decisions
2. Verify correctness
3. Identify new patterns to add
4. Check for security concerns
5. Update deny-list if needed
