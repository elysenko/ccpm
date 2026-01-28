# Claude Prompt Syntax Rules

Rules for writing effective prompts for Claude, based on LLM prompt engineering research.

## XML Tags

Claude was trained with XML tags, making them highly effective for structure.

### Benefits
- Clearer parsing of prompt sections
- Reduced misinterpretation errors
- Easier extraction of specific response parts

### Recommended Tags

Use semantically meaningful names:

```xml
<task>What to do</task>
<context>Background information</context>
<instructions>Step-by-step guidance</instructions>
<constraints>Rules and limitations</constraints>
<example>Demonstration</example>
<output_format>Expected response structure</output_format>
```

### Best Practices

```xml
<!-- Good: Clear structure -->
<task>
Fix the bug in the login function.
</task>

<context>
The function is in auth.py line 42.
Users report intermittent failures.
</context>

<constraints>
- Do not change the function signature
- Maintain backward compatibility
</constraints>

<output_format>
Provide the fixed code in a python code block.
</output_format>
```

## Be Explicit

Claude 4.x follows instructions precisely. Vague requests get vague results.

### Less Effective

```
Create a dashboard
```

### More Effective

```
Create an analytics dashboard with:
- Line chart showing daily active users
- Bar chart showing revenue by product
- Table of top 10 customers by spend
- Date range selector (default: last 30 days)
```

## Provide Context for Constraints

Explain WHY rules matter, not just WHAT they are.

### Less Effective

```
Never use ellipses
```

### More Effective

```
Never use ellipses because the text-to-speech engine
cannot pronounce them, causing awkward pauses.
```

## Tell What TO Do

Positive instructions outperform negative ones.

### Less Effective

```
Don't include implementation details in steps.
Don't use technical jargon.
```

### More Effective

```
Write steps in user-focused language.
Use domain terms the business user would recognize.
Example: "submit the form" not "POST to /api/users"
```

## Few-Shot Examples

For complex or novel formats, include 2-5 examples.

### Structure

```xml
<examples>
<example>
<input>User wants to reset password</input>
<output>
Feature: Password Reset
  Scenario: User resets password via email
    Given I am on the login page
    When I click "Forgot Password"
    ...
</output>
</example>

<example>
<input>User wants to update profile</input>
<output>
Feature: Profile Management
  Scenario: User updates display name
    Given I am logged in
    ...
</output>
</example>
</examples>
```

### Tips
- Place best example last (recency bias)
- Cover edge cases in examples
- Keep examples diverse but relevant

## Output Format Control

Be explicit about expected response format.

### For Code

```xml
<output_format>
Output ONLY a single code block.
Start with triple backticks and the language name.
End with triple backticks on its own line.
No explanations before or after the code.
</output_format>
```

### For Structured Data

```xml
<output_format>
Respond with ONLY a JSON object:
{
  "score": <0-100>,
  "passed": <true|false>,
  "issues": ["issue1", "issue2"]
}
No markdown, no explanation, just valid JSON.
</output_format>
```

## Role Prompting

Assigning a role improves domain-specific accuracy.

```xml
<role>
You are a senior QA engineer with 10 years of experience
writing Gherkin acceptance criteria. You prioritize:
- Behavior-driven scenarios (not implementation)
- Edge case coverage
- Clear, testable steps
</role>
```

## Avoid Over-Engineering

Claude 4.x tends to add unnecessary complexity.

### Add This Constraint

```
Avoid over-engineering. Only make changes directly requested.
Keep solutions simple and focused.

Do not:
- Add features not asked for
- Create abstractions for one-time operations
- Add "nice to have" error handling for impossible scenarios
```

## Extended Thinking

For complex reasoning, use graduated triggers:

| Phrase | Depth |
|--------|-------|
| `think` | Basic reasoning |
| `think hard` | Moderate complexity |
| `think harder` | High complexity |
| `ultrathink` | Maximum depth |

### When to Use

- Complex mathematical problems
- Multi-step coding tasks
- Architectural decisions
- Debugging intricate issues

### When to Skip

- Simple, direct tasks
- Format conversion
- Straightforward edits

## Prompt Template

Complete template incorporating all rules:

```xml
<role>
[Domain expert persona]
</role>

<task>
[Clear, specific objective]
</task>

<context>
[Relevant background information]
</context>

<instructions>
1. [First step]
2. [Second step]
3. [Third step]
</instructions>

<constraints>
- [Rule with explanation of WHY]
- [Another rule with context]
</constraints>

<examples>
<example>
[Input/output demonstration]
</example>
</examples>

<output_format>
[Explicit format specification]
</output_format>
```

## References

Based on research from:
- Anthropic Claude documentation
- LLM prompt engineering best practices (2025-2026)
- Empirical testing with Claude 4.x models
