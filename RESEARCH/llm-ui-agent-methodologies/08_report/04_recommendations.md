# Recommendations: Building Your LLM UI Generation Agent

## Decision Framework

### Step 1: Assess Your Requirements

| Factor | Simple Agent | Composite Agent | Multi-Agent |
|--------|--------------|-----------------|-------------|
| UI Complexity | Components, forms | Pages, dashboards | Multi-page apps |
| Quality Needs | Prototype | Production-ready | Enterprise-grade |
| Token Budget | Low | Medium | High (15x) |
| Development Time | Days | Weeks | Months |
| Team Size | 1-2 | 3-5 | 5+ |

### Step 2: Choose Your Architecture

**Option A: Simple Agent (Start Here)**
- Single LLM with well-crafted system prompt
- Constrained output (shadcn + Tailwind)
- Basic error handling
- Best for: MVPs, component libraries, internal tools

**Option B: Composite Agent (v0 Model)**
- Base LLM + streaming AutoFix + post-processing
- RAG for documentation retrieval
- Deterministic fixers for common errors
- Best for: Production web apps, customer-facing UIs

**Option C: Multi-Agent (Replit/ScreenCoder Model)**
- Specialized agents for analysis, planning, coding, verification
- Orchestrator for coordination
- Human-in-the-loop checkpoints
- Best for: Complex applications, enterprise projects

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

**1.1 Define Output Stack**
```typescript
// Recommended stack
const OUTPUT_STACK = {
  framework: 'react',
  language: 'typescript',
  components: 'shadcn-ui',
  styling: 'tailwind-css',
  icons: 'lucide-react',
  charts: 'recharts'
};
```

**1.2 Create Base System Prompt**
```markdown
You are a UI code generation agent. You produce React components using:

## Stack
- React 18 with TypeScript (strict mode)
- shadcn/ui components (never invent components)
- Tailwind CSS (no custom CSS or inline styles)
- Lucide React for icons

## Rules
1. Always export a single default function component
2. Use TypeScript interfaces for all props
3. Never use `any` type
4. Prefer composition over complexity
5. Include accessibility attributes (aria-label, role, etc.)

## Component Pattern
```tsx
interface {Name}Props {
  // props here
}

export default function {Name}({ ...props }: {Name}Props) {
  return (
    // JSX here
  );
}
```
```

**1.3 Set Up Basic Validation**
```typescript
async function validateGeneratedCode(code: string): Promise<ValidationResult> {
  // 1. Parse code
  const ast = parse(code, { plugins: ['typescript', 'jsx'] });

  // 2. Check for forbidden patterns
  const issues: string[] = [];

  traverse(ast, {
    // No inline styles
    JSXAttribute(path) {
      if (path.node.name.name === 'style') {
        issues.push('Inline styles not allowed');
      }
    },
    // No any type
    TSAnyKeyword() {
      issues.push('Any type not allowed');
    }
  });

  // 3. TypeScript compilation
  const compileResult = await compile(code);
  if (!compileResult.success) {
    issues.push(...compileResult.errors);
  }

  return {
    valid: issues.length === 0,
    issues
  };
}
```

### Phase 2: Self-Correction (Week 3-4)

**2.1 Implement Streaming Fixes**
```typescript
class StreamingFixer {
  private buffer = '';
  private fixes: Fix[] = [
    new IconFix(),      // Replace invalid icons
    new ImportFix(),    // Fix import paths
    new ClassNameFix()  // Fix Tailwind classes
  ];

  async processChunk(chunk: string): Promise<string> {
    this.buffer += chunk;
    let result = chunk;

    for (const fix of this.fixes) {
      if (fix.matches(this.buffer)) {
        result = await fix.apply(result, this.buffer);
      }
    }

    return result;
  }
}
```

**2.2 Add Post-Generation Fixes**
```typescript
const POST_FIXES = [
  {
    name: 'missing-imports',
    detect: (code) => findUndefinedIdentifiers(code),
    fix: (code, missing) => addImports(code, missing)
  },
  {
    name: 'react-query-provider',
    detect: (code) => usesReactQuery(code) && !hasProvider(code),
    fix: (code) => wrapWithProvider(code, 'QueryClientProvider')
  },
  {
    name: 'typescript-errors',
    detect: async (code) => (await compile(code)).errors,
    fix: async (code, errors) => await llmFixErrors(code, errors)
  }
];
```

**2.3 Implement Error Feedback Loop**
```typescript
async function generateWithRetry(
  prompt: string,
  maxAttempts = 3
): Promise<string> {
  let code = '';
  let attempt = 0;

  while (attempt < maxAttempts) {
    attempt++;

    // Generate
    code = await llm.generate(
      attempt === 1 ? prompt : `${prompt}\n\nPrevious errors:\n${errors.join('\n')}\n\nFix these issues.`
    );

    // Apply streaming and post fixes
    code = await applyAllFixes(code);

    // Validate
    const result = await validateGeneratedCode(code);
    if (result.valid) {
      return code;
    }

    errors = result.issues;

    // Check for diminishing returns (debugging decay)
    if (attempt >= 2 && errors.length >= previousErrorCount) {
      console.log('Debugging decay detected, trying fresh approach');
      // Reset context and try different strategy
    }
  }

  return code; // Return best attempt
}
```

### Phase 3: Input Processing (Week 5-6)

**3.1 Add Text Prompt Enhancement**
```typescript
async function enhancePrompt(userPrompt: string): Promise<string> {
  // Detect intent and add relevant context
  const intent = await classifyIntent(userPrompt);

  let enhanced = userPrompt;

  if (intent.includes('form')) {
    enhanced += '\n\nUse react-hook-form for form state and zod for validation.';
  }

  if (intent.includes('data-table')) {
    enhanced += '\n\nUse @tanstack/react-table for table functionality.';
  }

  // Inject current documentation if needed
  const relevantDocs = await retrieveDocs(userPrompt);
  if (relevantDocs) {
    enhanced = `Reference:\n${relevantDocs}\n\n${enhanced}`;
  }

  return enhanced;
}
```

**3.2 Add Screenshot Processing (Optional)**
```typescript
async function processScreenshot(image: Buffer): Promise<DesignAnalysis> {
  // 1. Segment the image
  const segments = await segmentUI(image);

  // 2. Analyze each segment
  const analyses = await Promise.all(
    segments.map(async (segment) => ({
      ...segment,
      components: await analyzeSegment(segment.image)
    }))
  );

  // 3. Build component hierarchy
  return buildHierarchy(analyses);
}
```

**3.3 Integrate Figma MCP (Optional)**
```typescript
// See Pattern 5 in Implementation Patterns
```

### Phase 4: Execution & Verification (Week 7-8)

**4.1 Set Up Sandbox**
```typescript
// Choose based on requirements:

// Browser-based (lowest latency, no server cost)
import { WebContainer } from '@webcontainer/api';

// Cloud MicroVM (multi-language, strongest isolation)
import { Sandbox } from 'e2b';

// Self-hosted (full control, consistent performance)
import { DockerSandbox } from './sandbox';
```

**4.2 Implement Visual Verification**
```typescript
async function verifyVisually(
  code: string,
  expectedDesign?: Buffer
): Promise<VerificationResult> {
  // 1. Run code in sandbox
  const previewUrl = await runInSandbox(code);

  // 2. Screenshot the result
  const screenshot = await captureScreenshot(previewUrl);

  // 3. Compare if expected design provided
  if (expectedDesign) {
    const similarity = await computeVisualSimilarity(screenshot, expectedDesign);
    return {
      passed: similarity > 0.85,
      similarity,
      screenshot
    };
  }

  // 4. Basic render check
  return {
    passed: !isBlankOrError(screenshot),
    screenshot
  };
}
```

### Phase 5: Scale & Optimize (Week 9+)

**5.1 Multi-Agent (If Needed)**
```python
# See Pattern 4 in Implementation Patterns
```

**5.2 Fine-Tuning (If Needed)**
```python
# UICoder approach: generate synthetic data, filter with compiler + vision model
# Requires significant investment - only if base models insufficient
```

**5.3 Observability**
```typescript
// Track key metrics
const METRICS = {
  firstPassSuccessRate: 'Percentage of generations that compile on first attempt',
  autoFixRate: 'Percentage of errors caught by AutoFix',
  visualSimilarity: 'Average visual similarity to designs (if applicable)',
  tokensPerGeneration: 'Average tokens used per successful generation',
  latency: 'Time from prompt to rendered preview'
};
```

---

## Critical Decisions

### Model Selection

| Model | Strength | When to Use |
|-------|----------|-------------|
| Claude Sonnet 4.x | Long context, code quality | Default choice for UI generation |
| Claude Opus 4.x | Complex reasoning | Multi-agent orchestration |
| GPT-5.x | Broad capability | Alternative to Claude |
| Gemini 3 Pro | Frontend specialization | Experimental/comparison |
| Open Source (DeepSeek, Qwen) | Cost, privacy | Self-hosted, budget-constrained |

### Component Library

| Library | Pros | Cons | When to Use |
|---------|------|------|-------------|
| **shadcn/ui** | AI-optimized, fully customizable | React-only | Default choice |
| Material UI | Complete, well-documented | Opinionated, larger bundle | Enterprise, Google aesthetic |
| Ant Design | Enterprise features | Heavy, Chinese docs | Chinese market, enterprise |
| Custom | Full control | High maintenance | Unique design system |

### Execution Environment

| Environment | Latency | Isolation | Cost | When to Use |
|-------------|---------|-----------|------|-------------|
| WebContainer | <200ms | Browser sandbox | Free (client) | Browser-based tools |
| E2B | <200ms | MicroVM | $0.05/hr | Cloud-based, multi-language |
| Modal | ~1s cold | gVisor | Pay-per-second | Python ML workloads |
| Self-hosted | Varies | Full control | Infrastructure | Privacy, control needs |

---

## What Would Change Our Recommendations

1. **If models improve dramatically**: Simpler architectures may suffice; self-debugging may become less critical

2. **If component libraries add AI features**: May reduce need for constrained output validation

3. **If visual similarity benchmarks plateau**: May indicate fundamental limits of current approaches

4. **If MCP adoption accelerates**: Design-to-code pipelines may become the default entry point

5. **If token costs drop significantly**: Multi-agent architectures become more viable at scale

---

## Anti-Patterns to Avoid

1. **Over-engineering early**: Start simple, add complexity based on measured failures

2. **Ignoring validation**: Never ship generated code without compilation check

3. **Arbitrary CSS generation**: Always constrain to component library

4. **Whole-page generation for complex UIs**: Break into segments

5. **Infinite retry loops**: Implement debugging decay detection

6. **Ignoring accessibility**: Build WCAG checks into validation pipeline

7. **Blind model upgrades**: Test new models against regression suite before adopting
