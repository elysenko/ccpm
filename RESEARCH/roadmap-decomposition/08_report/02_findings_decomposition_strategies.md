# Findings: Decomposition Strategies

## SQ1: What decomposition strategies work best?

### Key Finding: Vertical Slice is the Default Strategy

**Evidence Grade: A (Multiple independent authoritative sources)**

Vertical slice decomposition is strongly supported by evidence from multiple independent sources including Jimmy Bogard's foundational work, Mike Cohn's SPIDR framework, and the Humanizing Work methodology.

#### Definition
A vertical slice cuts through all layers of the application—from user interface through business logic to database—to deliver a thin but complete piece of functionality. "Instead of coupling across a layer, we couple vertically along a slice. Minimize coupling between slices, and maximize coupling in a slice."

#### Why Vertical Slice Wins

1. **Faster Feedback:** Delivers demo-able functionality earlier, uncovering bad assumptions about how features should work
2. **Reduced Integration Risk:** Integration happens with every slice, not deferred to the end
3. **Parallel Development:** Slices are isolated, enabling multiple teams to work simultaneously
4. **Value Delivery:** Each slice delivers measurable user value

#### When Horizontal Slice is Acceptable

Evidence supports limited use of horizontal slicing:
- **Sprint 0 Architecture:** When extensive foundational layer setup is needed
- **Well-Understood Interfaces:** When layer interactions are very clear
- **Specialist Leverage:** When horizontal work can be parallelized by specialists

Recommended approach: "Horizontal base layer (sprint 0) with vertical slices built on top"

---

## SPIDR Framework (Mike Cohn)

**Evidence Grade: A (Authoritative source)**

The SPIDR acronym provides 5 systematic techniques covering nearly all decomposition scenarios:

### S - Spikes
**When:** Technical uncertainty requires research before splitting
**What:** Time-boxed investigation to answer specific questions
**Example:** Build vs. buy decision for a new component
**Note:** Use only after other techniques evaluated

### P - Paths
**When:** Multiple user workflows exist through a feature
**What:** Split by different paths/journeys
**Example:** Payment via credit card vs. Apple Pay vs. PayPal
**Automatable Heuristic:** Detect OR conditions and alternative flows in requirements

### I - Interface
**When:** Different interfaces require genuinely different implementations
**What:** Split by device/browser/UI complexity
**Example:** Desktop dashboard vs. mobile-optimized view
**Automatable Heuristic:** Detect platform/device mentions in requirements

### D - Data
**When:** Data variations are meaningful (not just different text fields)
**What:** Split by data type when processing differs
**Example:** Image upload vs. video upload (different encoding)
**Automatable Heuristic:** Detect data type mentions with different processing

### R - Rules
**When:** Business rules add complexity that can be deferred
**What:** Build simple version first, add rules later
**Example:** Basic checkout first, then copyright detection, then fraud rules
**Automatable Heuristic:** Detect conditional business logic that can be excluded

---

## User Story Mapping (Jeff Patton)

**Evidence Grade: A (Authoritative source)**

Story mapping provides a complementary visualization approach:

### Structure
- **Top level:** Activities (narrative backbone)
- **Under activities:** User tasks and stories
- **Horizontal line:** Separates MVP from later releases

### Six-Step Process
1. Frame the problem (who, why)
2. Map the big picture (breadth over depth)
3. Explore (other users, edge cases, what can go wrong)
4. Slice out a release strategy
5. Slice out a learning strategy (MVPs for risks)
6. Slice out a development strategy

### Key Principle
"The idea is NOT to gather a set of written requirements, but rather help teams build consensus, a common understanding of user problems."

---

## SAFe Hierarchy

**Evidence Grade: A (Standards body)**

For enterprise contexts, SAFe provides clear decomposition hierarchy:

```
Portfolio Level:  EPIC (strategic initiative)
                    ↓
Large Solution:   CAPABILITY (multi-ART functionality)
                    ↓
Program Level:    FEATURE (deliverable capability)
                    ↓
Team Level:       STORY (sprint-completable work)
```

### Epic Flow Stages
1. **Funnel:** Capture all ideas
2. **Review:** Initial triage for alignment
3. **Analysis:** Lean Business Case creation
4. **Portfolio Backlog:** Prioritized for implementation
5. **Implementation:** Breakdown into features/stories
6. **Done:** Completion criteria met

### Epic Types
- **Business Epics:** Deliver value directly to customer
- **Enabler Epics:** Enhance architectural runway

---

## Synthesis: Decomposition Algorithm

Based on evidence, the recommended decomposition approach:

```
1. IF roadmap item is EPIC-sized:
   a. Create story map to understand activities/tasks
   b. Identify MVP slice (draw the line)
   c. Create capabilities/features from activities above line

2. FOR each feature:
   a. Apply SPIDR techniques in order: R → D → I → P → S
   b. Check: Can each slice be demoed independently?
   c. IF no: re-slice using different technique

3. VALIDATE each PRD:
   a. Vertical slice check: touches all layers?
   b. Value check: stakeholder would care about demo?
   c. Independence check: minimal dependencies on other PRDs?
```

---

## What Would Change Our Mind

If formal empirical studies showed horizontal slicing produces faster delivery in specific contexts (e.g., microservices with clear API contracts), we would add conditional guidance. Current evidence is primarily practitioner-based.
