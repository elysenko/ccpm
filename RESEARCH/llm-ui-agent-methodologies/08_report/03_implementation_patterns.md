# Implementation Patterns: Building an LLM UI Generation Agent

## Pattern 1: Constrained Output Stack

### Problem
Unconstrained CSS/HTML generation leads to inconsistent code, hallucinated classes, and maintenance nightmares.

### Solution
Constrain all output to a predefined component library and styling system.

### Recommended Stack
```
Framework: React 18 + TypeScript
Components: shadcn/ui
Styling: Tailwind CSS
Icons: Lucide React
Charts: Recharts
```

### Implementation

**System Prompt Fragment**:
```
You generate React components using:
- shadcn/ui components (Button, Card, Dialog, etc.)
- Tailwind CSS for styling (no custom CSS)
- TypeScript with strict types
- Lucide React for icons

Never use:
- Arbitrary CSS classes
- Inline styles
- Components not in shadcn/ui
- Any type in TypeScript
```

**Validation Layer**:
```typescript
// Post-generation validation
function validateOutput(code: string): ValidationResult {
  // 1. Check for forbidden patterns
  if (code.includes('style={{')) {
    return { valid: false, error: 'Inline styles not allowed' };
  }

  // 2. Verify component imports are from allowed libraries
  const imports = extractImports(code);
  for (const imp of imports) {
    if (!ALLOWED_SOURCES.includes(imp.source)) {
      return { valid: false, error: `Unauthorized import: ${imp.source}` };
    }
  }

  // 3. TypeScript compilation check
  const compileResult = compileTypeScript(code);
  if (!compileResult.success) {
    return { valid: false, error: compileResult.errors[0] };
  }

  return { valid: true };
}
```

**Evidence**: v0 and Claude Artifacts both use this stack; shadcn's "AI-first design philosophy" makes it ideal for LLM generation [S19, S27].

---

## Pattern 2: Streaming Self-Correction (AutoFix)

### Problem
LLMs generate faulty code ~10% of the time. Post-generation fixes are slow and disruptive.

### Solution
Implement real-time error detection and correction during streaming output.

### Architecture (v0 Model)

```
[LLM Streaming Output]
        ↓
[Stream Buffer]
        ↓
[Pattern Detector] → [Quick Fixes] → [Output Stream]
        ↓
[Error Collector]
        ↓ (after stream complete)
[Post-Stream Autofixers]
        ↓
[Final Output]
```

### Implementation

**Streaming Pattern Detector**:
```typescript
class StreamingAutoFix {
  private iconIndex: VectorDatabase;
  private buffer: string = '';

  async processToken(token: string): Promise<string> {
    this.buffer += token;

    // Check for icon imports
    const iconMatch = this.buffer.match(/from ['"]lucide-react['"].*?(\w+Icon)/);
    if (iconMatch) {
      const iconName = iconMatch[1];
      if (!this.iconExists(iconName)) {
        // Find closest match via embedding search
        const closest = await this.iconIndex.findClosest(iconName);
        return token.replace(iconName, closest);
      }
    }

    return token;
  }

  private iconExists(name: string): boolean {
    return LUCIDE_ICONS.includes(name);
  }
}
```

**Post-Stream AST Fixer**:
```typescript
async function postStreamFix(code: string): Promise<string> {
  const ast = parse(code);

  // Fix 1: Ensure QueryClientProvider wrapping
  if (usesReactQuery(ast) && !hasQueryProvider(ast)) {
    code = wrapWithQueryProvider(code);
  }

  // Fix 2: Complete package.json dependencies
  const missing = findMissingDependencies(ast);
  if (missing.length > 0) {
    await addDependencies(missing);
  }

  // Fix 3: TypeScript error repair
  const tsErrors = await compileAndGetErrors(code);
  if (tsErrors.length > 0) {
    code = await repairTypeScriptErrors(code, tsErrors);
  }

  return code;
}
```

**Evidence**: v0's AutoFix achieves "error-free generation rates well into the 90s" vs 62% baseline [S3].

---

## Pattern 3: Hierarchical Generation

### Problem
Whole-page generation causes element omission, distortion, and misarrangement—especially for complex layouts.

### Solution
Break complex UIs into segments, generate each independently, then compose.

### DCGen Approach

```
[Full Screenshot/Design]
        ↓
[Segment Detector]
        ↓
[Header] [Sidebar] [Main Content] [Footer]
    ↓        ↓           ↓           ↓
[Generate] [Generate] [Generate] [Generate]
    ↓        ↓           ↓           ↓
[Compose with Layout Validation]
        ↓
[Complete UI Code]
```

### Implementation

**Segment Detection**:
```typescript
interface UISegment {
  type: 'header' | 'sidebar' | 'content' | 'footer' | 'card' | 'form';
  bounds: { x: number; y: number; width: number; height: number };
  children?: UISegment[];
}

async function detectSegments(image: Buffer): Promise<UISegment[]> {
  // Use vision model for component detection
  const response = await llm.analyze(image, `
    Identify all major UI sections in this screenshot.
    For each section, return:
    - type: header/sidebar/content/footer/card/form
    - bounds: x, y, width, height in pixels
    Return as JSON array.
  `);

  return JSON.parse(response);
}
```

**Per-Segment Generation**:
```typescript
async function generateSegment(
  segment: UISegment,
  croppedImage: Buffer
): Promise<string> {
  const prompt = `
    Generate a React component for this ${segment.type} section.
    Use shadcn/ui and Tailwind CSS.
    The component should be self-contained.

    [Image attached]
  `;

  return await llm.generate(prompt, { image: croppedImage });
}
```

**Composition**:
```typescript
function composeSegments(segments: GeneratedSegment[]): string {
  const header = segments.find(s => s.type === 'header');
  const sidebar = segments.find(s => s.type === 'sidebar');
  const content = segments.find(s => s.type === 'content');
  const footer = segments.find(s => s.type === 'footer');

  return `
    export default function Page() {
      return (
        <div className="min-h-screen flex flex-col">
          ${header ? `<header>${header.code}</header>` : ''}
          <div className="flex flex-1">
            ${sidebar ? `<aside className="w-64">${sidebar.code}</aside>` : ''}
            <main className="flex-1">${content?.code || ''}</main>
          </div>
          ${footer ? `<footer>${footer.code}</footer>` : ''}
        </div>
      );
    }
  `;
}
```

**Evidence**: DCGen achieves "up to 15% improvement in visual similarity" with this approach [S6].

---

## Pattern 4: Multi-Agent Workflow

### Problem
Single agents struggle with complex, multi-faceted tasks. Error rates compound in long sequences.

### Solution
Specialize agents for distinct responsibilities; coordinate via orchestrator.

### Replit-Style Architecture

```
[User Request]
        ↓
[Manager Agent]
    ├── Decomposes task into subtasks
    ├── Assigns to specialized agents
    └── Collects and integrates results
        ↓
[Editor Agent(s)]
    ├── Focused coding tasks
    └── Minimal tool access (constrained scope)
        ↓
[Verifier Agent]
    ├── Checks code quality
    ├── Runs tests
    └── Falls back to user for ambiguity
        ↓
[Checkpoint: Auto-commit]
        ↓
[Next iteration or completion]
```

### Implementation with LangGraph

```python
from langgraph.graph import StateGraph, END
from typing import TypedDict

class UIGenerationState(TypedDict):
    task: str
    design_analysis: str | None
    component_plan: list[str] | None
    generated_code: dict[str, str]
    errors: list[str]
    iteration: int

# Define agents
async def design_analyzer(state: UIGenerationState):
    """Grounding agent: analyzes design and identifies components"""
    analysis = await llm.analyze(state["task"], """
        Analyze this UI design and identify:
        1. Major sections (header, sidebar, content, etc.)
        2. Individual components (buttons, forms, cards)
        3. Layout structure (grid, flex, responsive breakpoints)
        4. Color scheme and typography patterns
    """)
    return {"design_analysis": analysis}

async def planner(state: UIGenerationState):
    """Planning agent: creates component hierarchy"""
    plan = await llm.plan(state["design_analysis"], """
        Create a component hierarchy for this UI:
        1. List all components needed (top-down)
        2. Define props for each component
        3. Specify parent-child relationships
        4. Identify shared state requirements
    """)
    return {"component_plan": plan}

async def coder(state: UIGenerationState):
    """Generation agent: writes code for each component"""
    code = {}
    for component in state["component_plan"]:
        code[component] = await llm.generate(component, """
            Generate React + TypeScript + shadcn/ui code for this component.
            Follow the design analysis for styling.
        """)
    return {"generated_code": code}

async def verifier(state: UIGenerationState):
    """Verification agent: checks code quality"""
    errors = []
    for name, code in state["generated_code"].items():
        result = await validate_and_compile(code)
        if not result.success:
            errors.append(f"{name}: {result.error}")
    return {"errors": errors, "iteration": state["iteration"] + 1}

def should_continue(state: UIGenerationState):
    if not state["errors"]:
        return END
    if state["iteration"] > 3:
        return END
    return "coder"  # Retry

# Build graph
workflow = StateGraph(UIGenerationState)
workflow.add_node("analyzer", design_analyzer)
workflow.add_node("planner", planner)
workflow.add_node("coder", coder)
workflow.add_node("verifier", verifier)

workflow.set_entry_point("analyzer")
workflow.add_edge("analyzer", "planner")
workflow.add_edge("planner", "coder")
workflow.add_edge("coder", "verifier")
workflow.add_conditional_edges("verifier", should_continue)

app = workflow.compile()
```

**Evidence**: ScreenCoder's three-agent system achieves "state-of-the-art results across all metrics" [S7].

---

## Pattern 5: Design-to-Code Pipeline (Figma MCP)

### Problem
Manual translation of designs to code is slow and error-prone. Screenshots lose structured information.

### Solution
Use Model Context Protocol (MCP) to provide LLMs with structured design data.

### Architecture

```
[Figma Design]
        ↓
[Figma MCP Server]
    ├── get_code: Returns code-focused representation
    ├── get_images: Returns images for nodes
    └── get_variables: Returns design tokens
        ↓
[MCP Client (in IDE/Agent)]
        ↓
[LLM with Structured Context]
        ↓
[Generated Code]
```

### Implementation

**MCP Client Setup (Cursor/Claude Code)**:
```json
// .mcp.json
{
  "mcpServers": {
    "figma": {
      "command": "npx",
      "args": ["-y", "@anthropic/figma-mcp-server"],
      "env": {
        "FIGMA_ACCESS_TOKEN": "${FIGMA_ACCESS_TOKEN}"
      }
    }
  }
}
```

**Agent Using Figma MCP**:
```typescript
async function generateFromFigma(nodeId: string): Promise<string> {
  // Get structured design data via MCP
  const designData = await mcp.call('figma', 'get_code', {
    nodeId,
    format: 'react_tailwind'
  });

  // Get design variables (colors, spacing, typography)
  const variables = await mcp.call('figma', 'get_variables', { nodeId });

  // Generate with full context
  const code = await llm.generate(`
    Generate React component from this Figma design:

    Design Structure:
    ${JSON.stringify(designData, null, 2)}

    Design Variables:
    ${JSON.stringify(variables, null, 2)}

    Use shadcn/ui components and Tailwind CSS.
    Apply the design variables as Tailwind config or CSS variables.
  `);

  return code;
}
```

**Evidence**: Figma MCP provides "deterministic context for more accurate code generation" vs screenshots [S18].

---

## Pattern 6: Execution Sandbox

### Problem
AI-generated code needs to run for verification, but executing untrusted code is dangerous.

### Solution
Use isolated sandbox environments for safe code execution.

### WebContainer Approach (Browser-Based)

```typescript
import { WebContainer } from '@webcontainer/api';

async function runInSandbox(code: string): Promise<ExecutionResult> {
  // Boot WebContainer
  const webcontainer = await WebContainer.boot();

  // Mount files
  await webcontainer.mount({
    'src': {
      directory: {
        'App.tsx': { file: { contents: code } },
        'index.tsx': { file: { contents: ENTRY_POINT } }
      }
    },
    'package.json': { file: { contents: PACKAGE_JSON } },
    'vite.config.ts': { file: { contents: VITE_CONFIG } }
  });

  // Install dependencies
  const installProcess = await webcontainer.spawn('npm', ['install']);
  await installProcess.exit;

  // Start dev server
  const serverProcess = await webcontainer.spawn('npm', ['run', 'dev']);

  // Get preview URL
  webcontainer.on('server-ready', (port, url) => {
    return { previewUrl: url, success: true };
  });

  // Listen for errors
  serverProcess.output.pipeTo(new WritableStream({
    write(data) {
      if (data.includes('error')) {
        return { success: false, error: data };
      }
    }
  }));
}
```

### E2B Approach (Cloud MicroVMs)

```typescript
import { Sandbox } from 'e2b';

async function runInE2BSandbox(code: string): Promise<ExecutionResult> {
  const sandbox = await Sandbox.create('base');

  // Write code
  await sandbox.filesystem.write('/app/component.tsx', code);

  // Run TypeScript compiler
  const compileResult = await sandbox.process.startAndWait({
    cmd: 'npx tsc --noEmit /app/component.tsx'
  });

  if (compileResult.exitCode !== 0) {
    return { success: false, error: compileResult.stderr };
  }

  // Run tests if available
  const testResult = await sandbox.process.startAndWait({
    cmd: 'npx vitest run --reporter=json'
  });

  await sandbox.close();

  return {
    success: testResult.exitCode === 0,
    output: testResult.stdout
  };
}
```

**Evidence**: WebContainers provide "unmatched user experience, no latency, faster than localhost" [S15]; E2B provides "fast, secure, and scalable" execution [S17].

---

## Pattern 7: Context Engineering

### Problem
LLMs need rich context about the project, but context windows are limited and irrelevant context degrades quality.

### Solution
Strategically manage context through static files, dynamic retrieval, and compression.

### Static Context (CLAUDE.md Pattern)

```markdown
# CLAUDE.md

## Project Overview
This is a Next.js 14 e-commerce application using:
- shadcn/ui for components
- Tailwind CSS for styling
- Prisma + PostgreSQL for data
- Stripe for payments

## Code Conventions
- Use `const` arrow functions for components
- Props interfaces named `{Component}Props`
- Use server actions for mutations
- Client components only when necessary

## File Structure
- `app/` - Next.js app router pages
- `components/ui/` - shadcn components
- `components/` - custom components
- `lib/` - utilities and helpers

## Testing
- Vitest for unit tests
- Playwright for E2E
- Run: `npm test`

## Common Commands
- `npm run dev` - Start dev server
- `npm run build` - Production build
- `npm run lint` - Run ESLint
```

### Dynamic Context Retrieval

```typescript
class ContextManager {
  private vectorStore: VectorStore;

  async getRelevantContext(task: string, maxTokens: number): Promise<string> {
    // 1. Get task embedding
    const taskEmbedding = await embed(task);

    // 2. Find relevant code files
    const relevantFiles = await this.vectorStore.search(taskEmbedding, {
      limit: 10,
      minScore: 0.7
    });

    // 3. Prioritize by relevance and recency
    const sorted = relevantFiles.sort((a, b) => {
      return (b.score * 0.7 + b.recency * 0.3) - (a.score * 0.7 + a.recency * 0.3);
    });

    // 4. Truncate to token budget
    let context = '';
    let tokens = 0;
    for (const file of sorted) {
      const fileTokens = countTokens(file.content);
      if (tokens + fileTokens > maxTokens) break;
      context += `\n// ${file.path}\n${file.content}\n`;
      tokens += fileTokens;
    }

    return context;
  }
}
```

### Memory Compression (Replit Pattern)

```typescript
async function compressConversationMemory(
  history: Message[],
  maxTokens: number
): Promise<string> {
  // Use LLM to summarize long conversation history
  const summary = await llm.generate(`
    Summarize the key decisions and context from this conversation:
    ${history.map(m => `${m.role}: ${m.content}`).join('\n')}

    Focus on:
    - Architectural decisions made
    - Code patterns established
    - User preferences expressed
    - Errors encountered and fixed

    Keep the summary under ${maxTokens} tokens.
  `);

  return summary;
}
```

**Evidence**: Replit "uses LLMs themselves to compress memories, ensuring only the most relevant information is retained" [S4].
