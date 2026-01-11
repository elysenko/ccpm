# Scope Discover - Interactive Discovery Session

Conduct structured Q&A to understand a scope/vision. Saves answers incrementally to `discovery.md`.

## Usage
```
/pm:scope-discover <scope-name>
```

## Arguments
- `scope-name` (required): Name for this scope session

## Instructions

You are conducting a product discovery session to understand a user's vision before breaking it into PRDs.

### Session Setup

**Check for existing session:**
```bash
SESSION_DIR=".claude/scopes/$ARGUMENTS"
test -d "$SESSION_DIR" && echo "Resuming existing session" || echo "Starting new session"
```

**Initialize if new:**
```bash
mkdir -p "$SESSION_DIR/prds"
```

**Check for existing discovery.md:**
```bash
test -f "$SESSION_DIR/discovery.md" && cat "$SESSION_DIR/discovery.md"
```

If discovery.md exists with content, summarize what's already been captured and continue from where it left off.

### Discovery Framework

Ask questions in these categories. After EACH answer, append to discovery.md immediately.

#### 1. Vision & Goals
- "What's the big picture? What are you trying to build?"
- "Who are the primary users? What personas will use this?"
- "What does success look like? How will you measure it?"
- "Why is this important now? What's the driver?"

#### 2. Current State
- "What exists today? What's the starting point?"
- "What are the main pain points or gaps you're solving?"
- "Are there existing systems this needs to integrate with?"
- "What technical constraints exist (languages, frameworks, infrastructure)?"

#### 3. Scope Boundaries
- "What's explicitly OUT of scope for this effort?"
- "Are there timeline or resource constraints?"
- "What's the MVP vs nice-to-have?"
- "Are there regulatory or compliance requirements?"

#### 4. Dependencies & Risks
- "Are there external dependencies (APIs, teams, decisions)?"
- "What are the biggest risks or unknowns?"
- "What could block this project?"
- "Are there any security or privacy concerns?"

#### 5. User Journeys
- "Walk me through the main user journey end-to-end"
- "What are the key interactions or touchpoints?"
- "What happens when things go wrong? Error states?"
- "Are there different journeys for different user types?"

### Incremental Persistence

After EACH answer, immediately write to discovery.md:

```bash
cat >> "$SESSION_DIR/discovery.md" << 'EOF'

## {Category}: {Question}

**Answer:** {User's response}

**Key Points:**
- {Extracted point 1}
- {Extracted point 2}

EOF
```

### Discovery.md Format

```markdown
# Discovery: {scope-name}

discovery_complete: false
started: {datetime}
updated: {datetime}

---

## Vision & Goals

### What are you building?
**Answer:** {response}
**Key Points:**
- {point}

### Who are the users?
**Answer:** {response}
**Key Points:**
- {point}

---

## Current State
...

---

## Scope Boundaries
...

---

## Dependencies & Risks
...

---

## User Journeys
...

---

## Summary

### Core Vision
{1-2 sentence summary}

### Primary Users
- {persona 1}
- {persona 2}

### Key Requirements
1. {requirement}
2. {requirement}

### Explicit Out of Scope
- {item}

### Known Risks
- {risk}

### Integrations Needed
- {integration}

discovery_complete: true
```

### Completion Criteria

Discovery is complete when you have:
1. Clear understanding of the vision and goals
2. Identified primary users/personas
3. Documented current state and constraints
4. Defined explicit in-scope and out-of-scope boundaries
5. Captured at least one key user journey
6. Identified major dependencies and risks

### Output

When discovery is complete:

1. Write the summary section to discovery.md
2. Change `discovery_complete: false` to `discovery_complete: true`
3. Output:

```
Discovery complete for: {scope-name}

Summary:
- Vision: {1-sentence}
- Users: {count} personas identified
- Requirements: {count} key requirements
- Out of scope: {count} items
- Risks: {count} identified

Saved to: .claude/scopes/{scope-name}/discovery.md

Next step:
  .claude/scripts/prd-scope.sh {scope-name} --decompose
```

### Important Rules

1. **Write after every answer** - Don't batch writes
2. **Extract key points** - Don't just record raw answers
3. **Ask follow-ups** - Dig deeper when answers are vague
4. **Stay focused** - Don't go down rabbit holes
5. **Summarize at end** - Create the summary section when complete
