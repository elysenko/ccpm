# Fix Problem

Autonomous problem-fixing agent that gathers context from codebase, logs, and K8s artifacts to diagnose and fix errors. Uses deep research for solutions and retries up to 3 times with different approaches.

## Usage

```
/pm:fix_problem "<error_message>" --desired "<expected_behavior>" [--test "<verification_command>"] [--namespace "<k8s_namespace>"]
```

**Arguments:**
- `error_message` (required): The error output to diagnose and fix
- `--desired` (required): Description of expected correct behavior
- `--test` (optional): Command to verify the fix worked
- `--namespace` (optional): K8s namespace to check for resources/logs

## Workflow

### Phase 1: Parse Input

Extract error details from arguments:
```yaml
error:
  message: {raw error text}
  source: {test|build|runtime|logs|k8s}

desired:
  behavior: {expected behavior description}
  test_command: {verification command if provided}
  namespace: {k8s namespace if provided}
```

### Phase 2: Generate Clarifying Questions

Generate 10-15 questions across four layers:

#### Layer 1: Error Context
1. What is the exact error type? (syntax, runtime, timeout, permission, etc.)
2. What file/line is the error occurring in?
3. What function/method is involved?
4. When did this start happening?

#### Layer 2: Code Context
5. What does the failing code do?
6. What are the inputs/outputs expected?
7. What dependencies are involved?
8. Are there similar patterns elsewhere that work?

#### Layer 3: Environment Context
9. What K8s resources are involved? (if applicable)
10. What environment variables are relevant?
11. What is the deployment state?
12. Are there related log entries?

#### Layer 4: Historical Context
13. Has this code been modified recently?
14. Are there similar past issues in git history?
15. What do the tests expect?

### Phase 3: Answer Questions Autonomously

For each question, use appropriate tools without asking the user:

| Question Type | Primary Tool | Strategy | Fallback |
|---------------|--------------|----------|----------|
| Error type | Pattern match | Parse error message for keywords | Default to "unknown" |
| Error location | Regex | Extract from stack trace `/at .* \((.*):(\d+):\d+\)/` | Grep error text |
| Function | Grep | Find function definition in codebase | Parse stack trace |
| Purpose | Read | Read function and docstring | Infer from name |
| Inputs/outputs | Read | Check type annotations | Analyze test files |
| Dependencies | Read | Check imports, package.json | Parse error message |
| Recent changes | Bash | `git log --oneline -10 -- {file}` | `git log -20` |
| Similar patterns | Grep | Search for similar working code | Check test files |
| K8s state | Bash | `kubectl get pods -n {namespace}` | `kubectl describe` |
| Log entries | Bash | `grep -B5 -A5 "{error}" logs/` | `tail -100 {log}` |
| Test expectations | Read | Find and read test file | Grep for assertions |

**Example context gathering:**
```bash
# Q1: Error type
# Parse: "TypeError: Cannot read properties of undefined (reading 'map')"
# Answer: Runtime error - null/undefined reference

# Q2: Location
# Extract from stack trace
grep -n "renderList" src/**/*.{ts,tsx,js,jsx}

# Q7: Recent changes
git log --oneline -10 -- src/components/Dashboard.tsx

# Q9: K8s state
kubectl get pods -n {namespace} -o wide
kubectl describe pod {failing_pod} -n {namespace}
```

### Phase 4: Synthesize Research Query

Based on gathered context, formulate a research query:

```markdown
## Context Summary
- Error: {classified_error_type}
- Location: {file}:{line}
- Function: {function_name}
- Root Cause Hypothesis: {hypothesis from context}
- Tech Stack: {detected technologies}
- Environment: {k8s/local/etc}

## Generated Research Query
"How to fix {error_type} in {tech_stack} when {root_cause_hypothesis}
best practices defensive programming {year}"
```

### Phase 5: Research Solution

Use WebSearch to find solutions:
```bash
# Search for solutions
WebSearch: "{generated_research_query}"

# Fetch detailed content from top results
WebFetch: {relevant_urls}
```

Extract from research:
- Fix description
- Code patterns to apply
- Files to modify
- Verification steps
- Alternative approaches

### Phase 6: Apply Fix

Write changes to identified files using Edit/Write tools.

### Phase 7: Verify Fix

```bash
if [ -n "{test_command}" ]; then
  {test_command}
  if [ $? -eq 0 ]; then
    echo "✅ Fix verified"
    # Complete
  else
    # Retry with different approach
  fi
fi
```

### Phase 8: Retry Loop (if verification fails)

Maximum 3 attempts with different approaches:

| Attempt | Approach | Description |
|---------|----------|-------------|
| 1 | **Direct Fix** | Apply most obvious fix from research |
| 2 | **Defensive Approach** | Add null checks, validation, error handling |
| 3 | **Alternative Pattern** | Try different implementation approach entirely |
| Escalate | **Human Handoff** | Document findings, stop with full context |

**Approach variation examples:**

```javascript
// Attempt 1: Direct Fix
data?.map(item => ...) ?? []

// Attempt 2: Defensive Approach
if (!data) {
  console.warn('Data is null/undefined');
  return [];
}
if (!Array.isArray(data)) {
  console.warn('Data is not an array:', typeof data);
  return [];
}
return data.map(item => item?.value ?? null);

// Attempt 3: Alternative Pattern
const safeData = Array.isArray(data) ? data : [];
return safeData.flatMap(item =>
  item?.value != null ? [item.value] : []
);
```

### Phase 9: Error Classification

Classify errors to determine retry strategy:

**Transient Errors - Retry with Exponential Backoff:**
- timeout, ETIMEDOUT, timed out
- connection refused, ECONNREFUSED
- 503 Service Unavailable
- 429 Too Many Requests
- network error, socket hang up

**Fixable Errors - Retry with Different Approach:**
- SyntaxError, syntax error
- TypeError, type error
- Cannot read property, undefined is not
- ImportError, ModuleNotFoundError
- ReferenceError, is not defined
- null pointer, NullPointerException

**Permanent Errors - Escalate Immediately (No Retry):**
- Authentication failed, 401 Unauthorized
- Permission denied, 403 Forbidden
- Invalid API key, token expired
- Schema violation, constraint violation

## Output

### Success
```markdown
## Fix Applied ✅

### Error Summary
- **Type**: {error_classification}
- **Location**: {file}:{line}
- **Function**: {function_name}

### Root Cause
{hypothesis_with_evidence}

### Context Gathered
{summarized_answers_to_key_questions}

### Fix Applied
- **Approach**: Attempt {N} - {approach_name}
- **Files Modified**:
  - {file1}: {change_description}
  - {file2}: {change_description}

### Verification
- **Command**: {test_command}
- **Result**: PASS ✅
- **Retries Used**: {count}/3

### Research Sources
- {source1}
- {source2}
```

### Failure (After 3 Retries)
```markdown
## Fix Failed ❌ - Escalate to Human

### Error Summary
- **Type**: {error_classification}
- **Location**: {file}:{line}
- **Classification**: {transient|fixable|permanent}

### Attempts Made
1. **Direct Fix**: {description} - {why_it_failed}
2. **Defensive Approach**: {description} - {why_it_failed}
3. **Alternative Pattern**: {description} - {why_it_failed}

### Context Gathered
{full_context_summary}

### Suggested Next Steps
1. {suggestion_based_on_findings}
2. {alternative_investigation_path}
3. Manual review of: {specific_files_or_configs}

### Raw Error Output
{last_error_output}
```

## Important Rules

1. **Never ask humans** - Answer ALL questions using tools
2. **Classify errors first** - Determine if retry is appropriate
3. **Vary approaches** - Each retry must try something meaningfully different
4. **Document everything** - Full audit trail of context gathered
5. **Fail gracefully** - If 3 retries fail, escalate with complete context
6. **Idempotent operations** - Changes should be safe to retry
7. **Git safety** - Consider `git stash` before making changes

## Integration with Pipeline

When called from `interrogate.sh` pipeline:

```bash
# Pipeline calls fix_problem on failure
if ! execute_step 10; then  # deploy failed
  for attempt in 1 2 3; do
    /pm:fix_problem "{last_error}" \
      --desired "Deployment completes successfully with all pods running" \
      --test "kubectl get pods -n {namespace} | grep -v Running | grep -v Completed | wc -l | grep -q '^0$'" \
      --namespace "{namespace}"

    if [ $? -eq 0 ]; then
      break  # Fixed, continue pipeline
    fi
  done
fi
```

## Relationship with Other Commands

| Command | Purpose |
|---------|---------|
| `/pm:deploy` | Deploy to K8s (may trigger fix_problem on failure) |
| `/pm:batch-process` | Process PRDs (may trigger fix_problem on failure) |
| `/dr` | Deep research (called internally for solutions) |
| `/pm:generate-remediation` | Create PRDs for issues found |

## Notes

- Uses `/dr` pattern for solution research
- Modeled after Kubernetes reconciliation loops
- Each retry gathers fresh context (error may have changed)
- Logs all attempts to `.claude/fixes/{timestamp}.md` for audit trail
