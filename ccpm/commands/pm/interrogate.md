# Interrogate - Structured Discovery Conversation

Guide users through structured discovery questions to extract **Features (the what)** and **User Journeys (the how)**.

## Usage
```
/pm:interrogate [session-name]
```

## Arguments
- `session-name` (optional): Name for this session. Defaults to timestamp.

## Output

**All output is saved to:** `.claude/interrogations/{session-name}/conversation.md`

This file contains the raw, verbatim conversation. No summarization happens here - that's for `/pm:extract-findings`.

## Purpose

The goal of interrogation is to extract TWO key outputs:

1. **Features (The What)** - Discrete capabilities that need to be built
2. **User Journeys (The How)** - Step-by-step flows of how users accomplish goals

Every question you ask should drive toward identifying features or mapping journeys. Context questions (constraints, timeline, etc.) support these goals but are not the end goal themselves.

---

## Instructions

You are conducting a structured interrogation. The output is RAW CONVERSATION - no summarization, no extraction. But your QUESTIONS must drive toward features and user journeys.

### Step 1: Initialize Session

```bash
SESSION_NAME="${ARGUMENTS:-$(date +%Y%m%d-%H%M%S)}"
SESSION_DIR=".claude/interrogations/$SESSION_NAME"
mkdir -p "$SESSION_DIR"
CONV_FILE="$SESSION_DIR/conversation.md"
```

**Output file:** `$CONV_FILE` (`.claude/interrogations/{session-name}/conversation.md`)

**Check if resuming:**

```bash
if [ -f "$CONV_FILE" ]; then
  echo "=== Resuming Session: $SESSION_NAME ==="
fi
```

If conversation.md exists, read it and continue from where it left off. Tell the user:
```
"Resuming session. Here's where we left off: [last question asked]"
```

**If new session, initialize conversation.md:**

```markdown
# Interrogation: {session-name}

Started: {current datetime}
Status: in_progress

---

## Conversation

```

### Step 2: Get Initial Input

Ask:
```
What would you like to explore, build, solve, or decide?
```

**Write to conversation.md immediately:**
```markdown
**Claude:** What would you like to explore, build, solve, or decide?

**User:** {their response}

```

### Step 3: Classify and Announce

Classify the input:

| Type | Triggers |
|------|----------|
| `problem` | issue, bug, broken, failing, error, slow, dropping |
| `solution` | build, create, implement, want to, make, develop |
| `research` | what is, how does, compare, best, learn, understand |
| `feature` | add, enable, support, include, extend, improve |
| `decision` | should we, which, or, versus, choose, decide |
| `process` | how to, steps, workflow, setup, configure, deploy |

| Domain | Triggers |
|--------|----------|
| `technical` | code, API, architecture, system, database, server |
| `business` | revenue, market, strategy, growth, customers, pricing |
| `creative` | design, content, brand, UX, visual, style |
| `research` | learn, understand, compare, analyze, study |
| `operational` | process, workflow, team, resources, budget, timeline |

**Update conversation.md header:**
```markdown
# Interrogation: {session-name}

Started: {datetime}
Type: {classified type}
Domain: {classified domain}
Status: in_progress

---

## Conversation
```

Tell the user:
```
"I'm classifying this as a [TYPE] in the [DOMAIN] domain. My goal is to understand the features you need (the what) and how users will accomplish their goals (the how). Let's dig in."
```

Append this to conversation.md too.

### Step 4: Structured Questioning

Ask questions ONE AT A TIME. After each Q&A exchange, IMMEDIATELY write to conversation.md:

```markdown
**Claude:** {your question}

**User:** {their response}

```

---

#### Layer 1: Context Questions (ask all 5)

These establish context. Keep them quick - don't dwell here.

1. "What specifically are you trying to achieve with this?"
2. "Who is this for? Who will use or benefit from this?"
3. "What constraints exist? (time, budget, technical, organizational)"
4. "What does success look like? How will you measure it?"
5. "What's the timeline or urgency?"

**Probe vague answers:**
- "Can you be more specific?"
- "What would be an example?"
- "What's the most common case?"

---

#### Layer 2: Type-Specific Questions

**problem:**
- What's the impact? Who/what is affected?
- When did this start? Any trigger?
- How are people working around it?
- What's been tried already?

**solution:**
- Why this approach? What led here?
- What alternatives were considered?
- What's the MVP vs nice-to-have?
- What are the biggest risks?

**research:**
- How deep? Overview or comprehensive?
- What output format? Report, comparison, recommendation?
- What decision depends on this?

**feature:**
- What are the primary use cases?
- What edge cases matter?
- Priority vs other work?

**decision:**
- What are all the options?
- What criteria matter most?
- How reversible is it?
- Who decides?

**process:**
- What's the current state?
- Where are the bottlenecks?
- What resources are available?

---

#### Layer 3: Domain-Specific Questions

**technical:**
- Current tech stack?
- Scale requirements?
- Security/compliance needs?
- Integration points?

**business:**
- Expected ROI?
- Key stakeholders?
- Competitive pressure?
- Budget constraints?

**creative:**
- Brand guidelines?
- Target emotion/feeling?
- Examples to emulate?
- What to avoid?

**operational:**
- Team capacity?
- Training needs?
- Rollout strategy?

---

#### Layer 4: Feature Discovery (THE WHAT)

**This is a primary output. Spend time here.**

Ask these questions to extract discrete features:

1. "What specific capabilities does this need to have?"
2. "If you had to list the things users should be able to DO, what would they be?"
3. "What actions or operations are essential?"
4. "What's the most important thing this needs to do? And the second? Third?"
5. "Are there any features you've seen elsewhere that you want to include?"
6. "What should this NOT do? What's explicitly out of scope?"

**For each capability mentioned, probe deeper:**
- "Tell me more about [capability]. What exactly should happen?"
- "What inputs does that need? What outputs?"
- "What happens if something goes wrong?"
- "Who can do this action? Everyone or specific roles?"

**Drive toward concrete feature statements:**
- "So if I understand correctly, you need a feature that [does X]?"
- "Let me confirm: users should be able to [action] which results in [outcome]?"

Record their confirmation or correction.

---

#### Layer 5: User Journey Mapping (THE HOW)

**This is a primary output. Spend time here.**

Ask these questions to map user journeys:

1. "Walk me through how someone would use this from start to finish."
2. "What's the very first thing a user does? Then what?"
3. "What triggers someone to use this? What problem are they facing in that moment?"
4. "After they complete the main task, what happens next?"
5. "Are there different types of users who would use this differently?"

**For each user type identified, map their journey:**
- "Let's focus on [user type]. What's their goal?"
- "Step by step, what do they do to accomplish that goal?"
- "At each step, what do they see? What decisions do they make?"
- "Where might they get stuck or confused?"
- "What happens when they're done?"

**Probe for the complete flow:**
- "What happens before this step?"
- "What happens after?"
- "Is there any branching? Different paths depending on [condition]?"
- "What about error cases? What if [thing] fails?"

**Drive toward concrete journey statements:**
- "So the journey is: [User] wants to [goal], so they [step 1], then [step 2], then [step 3], resulting in [outcome]?"

Record their confirmation or correction.

---

### Step 5: Handle "I Don't Know"

When user says "I don't know", "not sure", etc:

1. **Offer to research:**
   ```
   "I can research that. Want me to look up [topic]?"
   ```

2. **If yes, do a web search** and present 2-3 options.

3. **Record the entire exchange** in conversation.md:
   ```markdown
   **Claude:** What auth provider should this use?

   **User:** I don't know, what are the options?

   **Claude:** I can research that. For B2B SaaS with SSO needs, the main options are:
   1. Auth0 - Full-featured, enterprise SSO, expensive
   2. WorkOS - Developer-focused, simpler, usage-based pricing
   3. Clerk - Modern DX, less enterprise features

   Based on what you've said about needing SSO, I'd lean toward WorkOS. Thoughts?

   **User:** WorkOS sounds good, let's go with that.

   ```

4. **If user defers**, record that too:
   ```markdown
   **User:** Let's figure that out later.

   **Claude:** Noted - we'll need to decide on auth provider before implementation.

   ```

---

### Step 6: Completeness Check

**Before finishing, verify you have captured:**

**Features (The What):**
- [ ] Are discrete features/capabilities identified?
- [ ] Is each feature clearly defined (what it does, who can use it)?
- [ ] Is scope clear (what's in, what's out)?
- [ ] Is priority understood (MVP vs nice-to-have)?

**User Journeys (The How):**
- [ ] Are user types identified?
- [ ] Is at least one complete journey mapped per user type?
- [ ] Are the steps concrete and sequential?
- [ ] Are decision points and branches identified?
- [ ] Are error/edge cases considered?

**Context:**
- [ ] Is the objective clear?
- [ ] Are constraints defined?
- [ ] Are success criteria measurable?

**If gaps remain in features or journeys, ask targeted follow-ups.** Don't end until you have concrete features and at least one clear user journey.

---

### Step 7: Close Session

When interrogation is complete:

1. **Update conversation.md status:**
   ```markdown
   ---

   Status: complete
   Completed: {current datetime}
   ```

2. **Tell the user:**
   ```
   Interrogation complete.

   Conversation saved to: .claude/interrogations/{session-name}/conversation.md

   I've captured:
   - {N} features identified
   - {N} user journeys mapped

   Next step - extract findings and create action plan:
     /pm:extract-findings {session-name}
   ```

---

### Writing Rules

**CRITICAL: Write to conversation.md after EVERY exchange.**

Output file: `.claude/interrogations/{session-name}/conversation.md`

Don't wait until the end. If session dies mid-way, the conversation up to that point is preserved.

Format:
```markdown
**Claude:** {what you said}

**User:** {what they said}

```

Keep it verbatim. Don't summarize. Don't extract key points. Just record the dialogue.

---

### Resuming Sessions

If conversation.md exists when starting:
1. Read it
2. Find the last question asked
3. Check which layers are complete
4. Continue from there
5. Tell user: "Resuming session. Last we discussed: [topic]. Let's continue."

---

## Important Rules

1. **One question at a time** - Never batch questions
2. **Record everything** - Every exchange goes to `.claude/interrogations/{session-name}/conversation.md`
3. **Write immediately** - Don't wait until end of session
4. **Probe vague answers** - Push for specifics
5. **Research unknowns** - Don't just accept "I don't know"
6. **Stay structured** - Follow Layer 1 → 2 → 3 → 4 → 5 progression
7. **Be conversational** - Natural dialogue, not interrogation
8. **Preserve verbatim** - No summarization, raw transcript only
9. **Drive to features** - Every line of inquiry should help identify a feature
10. **Drive to journeys** - Every line of inquiry should help map a journey

---

## Primary Outputs

The conversation should capture enough information for `/pm:extract-findings` to produce:

| Output | What It Is | How You Get It |
|--------|------------|----------------|
| **Features** | Discrete capabilities | Layer 4 questions - "What should users be able to DO?" |
| **User Journeys** | Step-by-step flows | Layer 5 questions - "Walk me through how someone uses this" |
| **Constraints** | Limitations | Layer 1 questions - "What constraints exist?" |
| **Success Criteria** | How to measure | Layer 1 questions - "What does success look like?" |
| **Unknowns** | Gaps to research | Anywhere user says "I don't know" |

**Features and User Journeys are the primary outputs. Everything else supports them.**
