---
allowed-tools: Bash, Read, LS
---

# Flow Diagram

Generate ASCII user flow diagram from an interrogation session.

## Usage
```
/pm:flow-diagram <session-name>
```

## Arguments
- `session-name`: Name of the interrogation session (from `/pm:interrogate`)

## Description

Reads journey data from a completed interrogation session and generates visual ASCII flowcharts showing user journeys. Use this after `/pm:interrogate` to visually verify the user flows before proceeding.

## Preflight Checks

1. **Validate session exists:**
   - Check if `.claude/interrogations/$ARGUMENTS/conversation.md` exists
   - If not found: "Session '$ARGUMENTS' not found. Run `/pm:interrogate $ARGUMENTS` first."
   - List available sessions if any exist

2. **Verify Node.js available:**
   - Run: `node --version`
   - If fails: "Node.js required for diagram rendering"

## Instructions

### 1. Read Session Data

Read the conversation file at `.claude/interrogations/$ARGUMENTS/conversation.md` and extract:
- Confirmed journeys (from the confirmation phase)
- Journey steps and goals
- Actor information

Look for the "User Journeys" section in the confirmation output:
```markdown
## User Journeys
1. [J-001] {name} (Actor: {actor})
   Goal: {goal}
```

### 2. Build Flow Graphs

For each journey, construct a graph representing the user flow:

**Node type mapping:**
- Journey trigger/start → `start` node
- Each step in the journey → `process` node
- Validation/decision points → `decision` node
- Goal achieved → `end` node

**Example journey to graph:**

Journey: "Browse and Purchase" (Actor: Buyer)
Goal: Find and buy a handmade product
Steps: Browse → Search → View Product → Add to Cart → Checkout → Payment → Confirmation

```javascript
{
  "title": "Browse and Purchase",
  "nodes": [
    { "id": "start", "label": "Buyer visits site", "type": "start" },
    { "id": "browse", "label": "Browse Products", "type": "process" },
    { "id": "search", "label": "Search/Filter", "type": "process" },
    { "id": "view", "label": "View Product", "type": "process" },
    { "id": "cart", "label": "Add to Cart", "type": "process" },
    { "id": "checkout", "label": "Checkout", "type": "process" },
    { "id": "payment", "label": "Payment Valid", "type": "decision" },
    { "id": "confirm", "label": "Order Confirmed", "type": "process" },
    { "id": "error", "label": "Payment Error", "type": "process" },
    { "id": "end", "label": "Purchase Complete", "type": "end" }
  ],
  "edges": [
    { "from": "start", "to": "browse" },
    { "from": "browse", "to": "search" },
    { "from": "search", "to": "view" },
    { "from": "view", "to": "cart" },
    { "from": "cart", "to": "checkout" },
    { "from": "checkout", "to": "payment" },
    { "from": "payment", "to": "confirm", "label": "yes" },
    { "from": "payment", "to": "error", "label": "no" },
    { "from": "confirm", "to": "end" },
    { "from": "error", "to": "checkout" }
  ]
}
```

### 3. Infer Steps from Journey Goal

If detailed steps are not available, infer logical steps from:
- The journey name and goal
- Common patterns for that type of journey
- The features that relate to this journey

Keep flows simple (5-8 steps max) focusing on the happy path with key decision points.

### 4. Render Each Journey

For each journey, pipe the JSON graph to the renderer:

```bash
echo '<json_graph>' | node .claude/ccpm/ccpm/scripts/flow-diagram.js
```

### 5. Output Format

Display all journey diagrams with clear separation:

```
=== Flow Diagrams: {session-name} ===

## Journey 1: {journey_name}
Actor: {actor}
Goal: {goal}

{ASCII flow diagram}

---

## Journey 2: {journey_name}
Actor: {actor}
Goal: {goal}

{ASCII flow diagram}

---

... (repeat for each journey)

=== End of Flow Diagrams ===

These diagrams represent the user journeys from your interrogation session.
Review them to verify the flows are correct before proceeding.

Next step: /pm:extract-findings {session-name}
```

## Example Output

```
=== Flow Diagrams: ecommerce-handmade ===

## Journey 1: Browse and Purchase
Actor: Buyer
Goal: Find and buy a handmade product

            User Flow: Browse and Purchase

                  ╭───────────────────╮
                  │ Buyer visits site │
                  ╰─────────┬─────────╯
                            │
                            ▼
                  ┌───────────────────┐
                  │  Browse Products  │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │   Search/Filter   │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │   View Product    │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │   Add to Cart     │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │     Checkout      │
                  └─────────┬─────────┘
                            │
                            ▼
                  ◇───────────────────◇
                  │  Payment Valid?   │
                  ◇─────────┬─────────◇
                       yes  │  no
             ┌──────────────┴──────────────┐
             ▼                             ▼
   ┌───────────────────┐         ┌───────────────────┐
   │  Order Confirmed  │         │   Payment Error   │
   └─────────┬─────────┘         └─────────┬─────────┘
             │                             │
             └─────────────┬───────────────┘
                           ▼
                  ╭───────────────────╮
                  │ Purchase Complete │
                  ╰───────────────────╯

---

## Journey 2: List a Product
Actor: Seller
Goal: Add a new product for sale

... (diagram for this journey)

=== End of Flow Diagrams ===
```

## Error Handling

- **Session not found**: List available sessions in `.claude/interrogations/`
- **No journeys found**: "No confirmed journeys in session. Complete the interrogation first."
- **Render error**: Show Node.js error message

## Notes

- Diagrams focus on the happy path with key decision points
- Complex journeys are simplified to 5-8 main steps
- Decision nodes (◇) represent validation/branching points
- Use this to verify flows before running `/pm:extract-findings`
