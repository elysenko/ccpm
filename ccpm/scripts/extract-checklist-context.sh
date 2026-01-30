#!/bin/bash
# extract-checklist-context.sh
# Extracts full context from checklist tables and formats for /pm:feature consumption
#
# Usage: ./extract-checklist-context.sh <checklist_item_id> [output_file]
# Output: Markdown file with structured context for feature skill

set -e

ITEM_ID="${1:?Usage: extract-checklist-context.sh <checklist_item_id> [output_file]}"
OUTPUT_FILE="${2:-.claude/planner/feature-context-${ITEM_ID}.md}"

echo "Extracting context for checklist_item id=$ITEM_ID..."

# Get main item details
ITEM_JSON=$(PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 -- \
  psql -U postgres -d cattle_erp -t -A -c "
SELECT json_build_object(
  'id', ci.id,
  'title', ci.title,
  'description', ci.description,
  'is_spike', ci.is_spike,
  'spike_question', ci.spike_question,
  'spike_timebox', ci.spike_timebox,
  'who_affected', ci.who_affected,
  'what_outcome', ci.what_outcome,
  'why_important', ci.why_important,
  'when_needed', ci.when_needed,
  'where_applies', ci.where_applies,
  'how_verified', ci.how_verified,
  'invest_total', ci.invest_total,
  'invest_passed', ci.invest_passed,
  'priority', ci.priority,
  'priority_rationale', ci.priority_rationale,
  'story_points', ci.story_points,
  'acceptance_criteria', ci.acceptance_criteria,
  'notes', ci.notes,
  'parent_item_id', ci.parent_item_id
)
FROM checklist_item ci
WHERE ci.id = $ITEM_ID;
")

# Validate extraction
if [ -z "$ITEM_JSON" ] || [ "$ITEM_JSON" = "" ]; then
  echo "❌ Error: Could not find checklist_item with id=$ITEM_ID"
  exit 1
fi

# Get parent item if exists
PARENT_ID=$(echo "$ITEM_JSON" | jq -r '.parent_item_id // empty')
if [ -n "$PARENT_ID" ] && [ "$PARENT_ID" != "null" ]; then
  PARENT_JSON=$(PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 -- \
    psql -U postgres -d cattle_erp -t -A -c "
SELECT json_build_object(
  'id', ci.id,
  'title', ci.title,
  'description', ci.description,
  'who_affected', ci.who_affected,
  'what_outcome', ci.what_outcome,
  'why_important', ci.why_important,
  'when_needed', ci.when_needed,
  'where_applies', ci.where_applies,
  'how_verified', ci.how_verified,
  'invest_total', ci.invest_total,
  'priority', ci.priority,
  'acceptance_criteria', ci.acceptance_criteria
)
FROM checklist_item ci
WHERE ci.id = $PARENT_ID;
")
else
  PARENT_JSON="{}"
fi

# Get session context
SESSION_JSON=$(PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 -- \
  psql -U postgres -d cattle_erp -t -A -c "
SELECT json_build_object(
  'session_name', c.session_name,
  'title', c.title,
  'phase', c.phase,
  'team_context', c.team_context,
  'sprint_context', c.sprint_context,
  'stakeholder_context', c.stakeholder_context
)
FROM checklist c
JOIN checklist_item ci ON ci.checklist_id = c.id
WHERE ci.id = $ITEM_ID;
")

# Get sibling items (other tasks in same checklist)
SIBLINGS_JSON=$(PGPASSWORD=upj3RsNuqy kubectl exec -n cattle-erp postgresql-cattle-erp-0 -- \
  psql -U postgres -d cattle_erp -t -A -c "
SELECT COALESCE(json_agg(json_build_object(
  'id', ci2.id,
  'title', ci2.title,
  'priority', ci2.priority,
  'status', ci2.status,
  'is_spike', ci2.is_spike
)), '[]'::json)
FROM checklist_item ci
JOIN checklist_item ci2 ON ci2.checklist_id = ci.checklist_id
WHERE ci.id = $ITEM_ID AND ci2.id != $ITEM_ID;
")

# Parse JSON values
title=$(echo "$ITEM_JSON" | jq -r '.title // "Unknown"')
description=$(echo "$ITEM_JSON" | jq -r '.description // ""')
is_spike=$(echo "$ITEM_JSON" | jq -r '.is_spike // false')
spike_question=$(echo "$ITEM_JSON" | jq -r '.spike_question // ""')
who=$(echo "$ITEM_JSON" | jq -r '.who_affected // ""')
what=$(echo "$ITEM_JSON" | jq -r '.what_outcome // ""')
why=$(echo "$ITEM_JSON" | jq -r '.why_important // ""')
when=$(echo "$ITEM_JSON" | jq -r '.when_needed // ""')
where=$(echo "$ITEM_JSON" | jq -r '.where_applies // ""')
how=$(echo "$ITEM_JSON" | jq -r '.how_verified // ""')
invest=$(echo "$ITEM_JSON" | jq -r '.invest_total // 0')
priority=$(echo "$ITEM_JSON" | jq -r '.priority // "should"')
acceptance=$(echo "$ITEM_JSON" | jq -r '.acceptance_criteria // "[]"')

# Parent details
parent_title=$(echo "$PARENT_JSON" | jq -r '.title // ""')
parent_desc=$(echo "$PARENT_JSON" | jq -r '.description // ""')
parent_what=$(echo "$PARENT_JSON" | jq -r '.what_outcome // ""')
parent_how=$(echo "$PARENT_JSON" | jq -r '.how_verified // ""')
parent_id=$(echo "$PARENT_JSON" | jq -r '.id // ""')

# Session details
session_name=$(echo "$SESSION_JSON" | jq -r '.session_name // ""')
team_ctx=$(echo "$SESSION_JSON" | jq -r '.team_context // "{}"')
sprint_ctx=$(echo "$SESSION_JSON" | jq -r '.sprint_context // "{}"')
sprint_goal=$(echo "$sprint_ctx" | jq -r '.goal // ""')
team_capacity=$(echo "$team_ctx" | jq -r '.capacity // ""')

# Create output directory
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Write markdown output
cat > "$OUTPUT_FILE" << MARKDOWN
# Feature Context: $title

> Auto-generated from checklist_item id=$ITEM_ID
> Session: $session_name
> Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

---

## Sprint Context

- **Goal:** $sprint_goal
- **Capacity:** $team_capacity
- **Priority:** $priority
- **INVEST Score:** $invest/30

---

## Feature Requirements

### Title
$title

### Description
$description

MARKDOWN

# Add spike section if applicable
if [ "$is_spike" = "true" ]; then
  cat >> "$OUTPUT_FILE" << MARKDOWN
### Spike Question
$spike_question

### Spike Findings
*(To be filled after spike completion)*

MARKDOWN
fi

# Add parent feature context if this is a spike
if [ -n "$parent_title" ] && [ "$parent_title" != "" ] && [ "$parent_title" != "null" ]; then
  cat >> "$OUTPUT_FILE" << MARKDOWN
---

## Parent Feature (Implementation Target)

### Title
$parent_title

### Description
$parent_desc

### Expected Outcome
$parent_what

### Verification Criteria
$parent_how

MARKDOWN
fi

cat >> "$OUTPUT_FILE" << MARKDOWN
---

## W-Framework Analysis

### Who is affected?
$who

### What is the outcome?
$what

### Why is this important?
$why

### When is this needed?
$when

### Where does this apply?
$where

### How will we verify?
$how

---

## Acceptance Criteria

$acceptance

---

## Implementation Guidance

Based on the context above, the feature skill should:

1. **Skip Phase 0 questions** that are already answered above
2. **Use W-Framework data** to populate PRD fields
3. **Reference verification criteria** for test generation
4. **Consider sprint context** (goal: $sprint_goal, capacity: $team_capacity)

### Pre-answered Questions

| Question | Answer |
|----------|--------|
| What to build? | $title |
| Who benefits? | $who |
| Success criteria? | $how |
| Priority level? | $priority |

---

## Related Tasks

MARKDOWN

# List sibling tasks
echo "$SIBLINGS_JSON" | jq -r '.[] | "- **\(.title)** (\(.priority // "no priority"), \(.status // "pending"))"' >> "$OUTPUT_FILE" 2>/dev/null || echo "- No related tasks" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << MARKDOWN

---

## Database Reference

\`\`\`
checklist_item.id = $ITEM_ID
MARKDOWN

if [ -n "$parent_id" ] && [ "$parent_id" != "" ] && [ "$parent_id" != "null" ]; then
  echo "parent_item_id = $parent_id" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << MARKDOWN
session_name = $session_name
\`\`\`
MARKDOWN

echo "✅ Context extracted to: $OUTPUT_FILE"
echo ""
echo "To use with /pm:feature:"
echo "  /pm:feature $OUTPUT_FILE"
