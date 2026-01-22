# Methodology Taxonomy: LLM UI Code Generation

## 1. Agent Architecture Patterns

### 1.1 Single-Agent Architecture

**Description**: One LLM handles the entire generation pipeline from prompt to code.

**Characteristics**:
- Maintains continuous context across all steps
- Simpler debugging and predictable behavior
- High reliability for sequential, state-dependent tasks
- Suitable for ~80% of common use cases

**When to Use**:
- Component-level generation (buttons, forms, cards)
- Tasks requiring deep context continuity
- Write-heavy operations
- Resource-constrained environments

**Examples**: Claude Artifacts, basic v0 prompts, Cursor inline edits

**Evidence**: "Single-agent approaches suffice for approximately 80% of common use cases" [S14]

### 1.2 Multi-Agent Architecture

**Description**: Multiple specialized agents collaborate on different aspects of generation.

**Patterns**:

**Manager/Editor/Verifier (Replit)**:
- Manager: Oversees workflow, coordinates agents
- Editor: Handles specific coding tasks
- Verifier: Checks quality, interacts with user for feedback

**Grounding/Planning/Generation (ScreenCoder)**:
- Grounding Agent: Detects and labels UI components
- Planning Agent: Constructs hierarchical layout
- Generation Agent: Produces HTML/CSS via prompt synthesis

**Orchestrator-Worker (LangGraph)**:
- Orchestrator: Distributes tasks dynamically
- Workers: Execute specialized subtasks in parallel

**When to Use**:
- Complex, multi-page applications
- Parallelizable analysis tasks (design interpretation)
- Enterprise-grade projects requiring review stages
- Tasks spanning multiple domains

**Tradeoffs**:
- 15x higher token usage
- Complex coordination logic
- Non-deterministic debugging

**Evidence**: "Multi-agent architecture with Claude Opus 4 as lead agent outperformed single-agent by 90.2%" [S13]

### 1.3 Composite Model Architecture

**Description**: Combines base LLM with specialized processing layers (v0 approach).

**Components**:
1. **Dynamic System Prompt**: Injects current documentation, code samples
2. **Base LLM**: Frontier model (Claude Sonnet, GPT-4) for reasoning
3. **Streaming Post-Processor (LLM Suspense)**: Real-time token manipulation
4. **AutoFix Model**: Fine-tuned model for error correction
5. **Deterministic Fixers**: AST-based linting and validation

**When to Use**:
- Production UI generation requiring high reliability
- When first-pass generation quality is insufficient
- Scenarios with well-defined error categories

**Evidence**: v0 achieves "error-free generation rates well into the 90s" vs 62% baseline [S3]

---

## 2. Generation Strategies

### 2.1 Direct/End-to-End Generation

**Description**: Generate complete UI code in a single pass from input.

**Pros**: Simple, fast, low token cost
**Cons**: Quality degrades with complexity; prone to omission/distortion

**When to Use**: Simple components, quick prototypes

### 2.2 Divide-and-Conquer Generation

**Description**: Segment input (design/screenshot) into parts, generate code for each, then compose.

**DCGen Approach**:
1. Divide screenshot into manageable segments
2. Generate code for each segment
3. Reassemble into complete UI code

**Results**: Up to 15% improvement in visual similarity, 8% in code similarity [S6]

**When to Use**: Complex layouts, multi-section pages, large designs

### 2.3 Hierarchical/Incremental Generation

**Description**: Build UI layer by layer (container → sections → components).

**ScreenCoder Approach**:
1. Ground: Detect and label components (header, navbar, sidebar, content)
2. Plan: Organize into hierarchical layout
3. Generate: Synthesize HTML with placeholders, then fill content

**Anthropic Best Practice**: "Implement steps sequentially, testing each before moving to the next" [S11]

**When to Use**: Complex nested UIs, design systems, component composition

### 2.4 Iterative Refinement

**Description**: Generate initial code, then iteratively improve based on feedback.

**Self-Debugging Loop**:
1. Generate initial code
2. Execute/render and observe errors
3. Provide error feedback to LLM
4. Generate fixes
5. Repeat until success or max iterations

**Evidence**: "Improves baseline accuracy by up to 12%" [S9]

**Decay Warning**: "Most models lose 60-80% of debugging capability within 2-3 attempts" [S10]

---

## 3. Input Processing Approaches

### 3.1 Text-Only Prompting

**Description**: Natural language descriptions drive generation.

**Best Practices**:
- Be specific: "button with green background and white text" vs "a button"
- Include constraints: framework, styling approach, component library
- Provide context: existing code patterns, design system rules

### 3.2 Screenshot/Visual Input

**Description**: Use UI screenshots as generation input.

**Challenges** (DCGen findings):
- Element omission: Missing components
- Element distortion: Inaccurate rendering
- Element misarrangement: Wrong positioning

**Solutions**:
- Segment images into smaller pieces
- Use vision-language models for component detection
- Combine with text descriptions for disambiguation

### 3.3 Structured Design Input

**Description**: Use structured design data (Figma JSON, design tokens).

**Figma MCP Workflow**:
1. MCP client queries Figma API
2. Server returns structured JSON with component hierarchy
3. LLM receives deterministic context for code generation

**AI4UI Grammar**: LLM-friendly Figma grammar encoding "intent, screen states, transitions, validation rules, edge cases, accessibility notes" [S8]

**Advantage**: "Structured JSON—not screenshots" provides "deterministic context for more accurate code generation" [S18]

---

## 4. Output Optimization Patterns

### 4.1 Constrained Output (Component Libraries)

**Description**: Limit output to predefined component vocabulary.

**Recommended Stack**:
- **Components**: shadcn/ui
- **Styling**: Tailwind CSS
- **Framework**: React + TypeScript
- **Icons**: Lucide React
- **Charts**: Recharts

**Why shadcn/ui**:
- "Open code and consistent API allow AI models to read, understand, and generate new components" [S19]
- Components are in user's codebase, giving "AI full context"
- Composable patterns make generation reliable

### 4.2 TypeScript Over JavaScript

**Description**: Use TypeScript for better LLM feedback loops.

**Benefits**:
- "Compiler acts like a strict senior engineer"
- Type errors provide "specific, localized guidance"
- "Type system plus tests create a dual feedback loop"

**Custom Instructions**: "Always use TypeScript, avoid using `any` type" [S22]

### 4.3 Streaming Error Correction

**Description**: Fix errors as code is being generated, not just afterward.

**v0 LLM Suspense Examples**:
- Replace invalid icon names with closest matches (embedding search, <100ms)
- Substitute long URLs with tokens
- Fix common syntax patterns in-stream

**Post-Streaming Autofixers**:
- Ensure React Query hooks wrap in QueryClientProvider
- Complete missing package.json dependencies
- Repair JSX and TypeScript errors

---

## 5. Execution Environments

### 5.1 WebContainer (Browser-Based)

**Description**: Run Node.js in browser via WebAssembly.

**Characteristics**:
- Sub-200ms startup, no cold starts
- Client-side execution (no server costs)
- Offline capable
- Security via browser sandbox

**Used By**: StackBlitz, Bolt.new

### 5.2 Firecracker MicroVMs (E2B)

**Description**: Lightweight VMs for isolated execution.

**Characteristics**:
- <200ms startup
- Hardware-level isolation
- Multi-language support
- 24-hour session limits

### 5.3 gVisor Containers (Modal)

**Description**: User-space kernel for container isolation.

**Characteristics**:
- Sub-second cold starts
- Strong Python ML workload support
- Auto-scaling
- Higher cold start latency than Firecracker

### 5.4 Local Docker

**Description**: Standard containerization on local/cloud infrastructure.

**Characteristics**:
- Full control and customization
- Slower cold starts
- Manual scaling
- No session limits

---

## 6. Context Management Strategies

### 6.1 Project-Level Context Files

**Description**: Maintain files that are automatically included in agent context.

**CLAUDE.md Pattern**:
- Document common bash commands
- Code style guidelines
- Testing workflows
- Project-specific quirks

**Cursor Rules**: "Capture domain-specific context including workflows, formatting and other conventions"

### 6.2 Dynamic Context Discovery

**Description**: Agent retrieves only needed information dynamically.

**Cursor Approach**:
- Move away from large static context upfront
- Agent dynamically fetches files as needed
- Uses files as primary interface for LLM tools

### 6.3 RAG for Documentation

**Description**: Retrieve relevant documentation based on task.

**v0 Approach**:
- Detect AI-related intent via embeddings + keyword matching
- Inject current framework documentation into prompt
- Maintain hand-curated code sample directories
