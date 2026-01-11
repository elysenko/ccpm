# Roadmap Generate

Generate a consolidated roadmap from multiple sources for a scope.

## Usage
```
/pm:roadmap-generate <scope-name>
```

## Example
```
/pm:roadmap-generate gslr
```

This consolidates all roadmap sources and writes to `.claude/scopes/gslr-roadmap.json`.

## Instructions

You are a roadmap consolidator. Your job is to merge roadmap information from multiple sources into a single unified JSON file.

### Step 1: Load Existing PRDs

Read all PRD files from `.claude/prds/`:

```bash
ls .claude/prds/*.md
```

For each PRD file:
1. Parse YAML frontmatter
2. Extract: name, description, status, priority, effort, dependencies, type
3. Add to roadmap.prds array

```json
{
  "number": 42,
  "name": "scope-runner-system",
  "description": "Self-healing automation system...",
  "status": "in-progress",
  "priority": "P0-critical",
  "effort": "8 hours",
  "dependencies": [],
  "type": "feature",
  "source": "prd_file",
  "path": ".claude/prds/42-scope-runner-system.md"
}
```

### Step 2: Load roadmap.json (if exists)

Check if `roadmap.json` exists in the project root.

If it exists:
1. Parse the JSON file
2. Extract epics array
3. For each epic NOT already in roadmap.prds (by name matching):
   - Convert to PRD format
   - Add to roadmap.prds
4. Import dependencies array

```json
{
  "name": "graphql-api-layer",
  "description": "From roadmap.json epic",
  "status": "backlog",
  "priority": "must_have",
  "effort": "medium",
  "phase": 0,
  "source": "roadmap_json",
  "theme": "Technical Foundation"
}
```

### Step 3: Parse OrgMap_new.drawio (if exists)

Check if `OrgMap_new.drawio` exists in the project root.

If it exists, extract architectural information:

1. **Agent Nodes**: Find all `value="*Agent"` elements
   - CEO Agent (deprecated -> OrchestratorAgent)
   - Research Agent
   - QA Agent
   - Architect Agent
   - Marketing Agent

2. **Service Nodes**: Find key services
   - PostgreSQL database
   - MinIO storage
   - SQLite
   - Browser service

3. **Workflow Connections**: Extract the flow
   - User Input -> CEO Agent -> Research Agent -> etc.

4. **Data Flows**: What data goes where
   - Research results -> PostgreSQL
   - Files -> MinIO

Add to roadmap.architecture:

```json
{
  "agents": [
    {"name": "OrchestratorAgent", "replaces": "CEOAgent", "status": "active"},
    {"name": "ResearchAgent", "status": "active"},
    {"name": "QAAgent", "status": "active"},
    {"name": "ArchitectAgent", "status": "deprecated", "replacement": "MetaGPT ArchitectRole"}
  ],
  "services": [
    {"name": "PostgreSQL", "purpose": "Primary database"},
    {"name": "MinIO", "purpose": "Object storage"},
    {"name": "SQLite", "purpose": "Local task storage"}
  ],
  "workflow": [
    "UserInput",
    "EnvSetup",
    "OrchestratorAgent",
    "ResearchAgent",
    "QAAgent",
    "ArchitectAgent",
    "Implementation"
  ]
}
```

### Step 4: Build Dependency Graph

1. Collect all dependencies from PRDs
2. Create adjacency list representation
3. Identify blocking PRDs (those that block others)
4. Identify blocked PRDs (those waiting on others)

```json
{
  "dependencies": [
    {"from": "cli-command-system", "to": "orchestrator-agent", "type": "requires"},
    {"from": "metagpt-org-simulation", "to": "spec-document-system", "type": "requires"}
  ],
  "blocking": ["orchestrator-agent", "spec-document-system", "web-auth"],
  "blocked": ["cli-command-system", "iteration-feedback-loop"]
}
```

### Step 5: Topological Sort

Sort PRDs by dependencies:
1. PRDs with no dependencies first
2. Then PRDs whose dependencies are complete
3. Then remaining PRDs in priority order

### Step 6: Calculate Statistics

```json
{
  "statistics": {
    "total_prds": 42,
    "by_status": {
      "complete": 15,
      "in-progress": 3,
      "backlog": 24
    },
    "by_priority": {
      "P0-critical": 5,
      "P1-high": 12,
      "P2-normal": 20,
      "P3-low": 5
    },
    "completion_percentage": 35.7
  }
}
```

### Step 7: Write Unified Roadmap

Write to `.claude/scopes/{scope-name}-roadmap.json`:

```json
{
  "generated": "2026-01-09T06:45:00Z",
  "scope": "gslr",
  "sources": [
    {"type": "prd_files", "count": 42},
    {"type": "roadmap_json", "count": 11},
    {"type": "orgmap_drawio", "parsed": true}
  ],
  "prds": [
    // Sorted array of all PRDs
  ],
  "dependencies": [
    // All dependency relationships
  ],
  "architecture": {
    // From OrgMap_new.drawio
  },
  "statistics": {
    // Calculated stats
  },
  "execution_order": [
    // Topologically sorted list of PRD names to execute
  ]
}
```

## Output Format

```
/pm:roadmap-generate gslr

Loading PRDs from .claude/prds/...
  Found: 42 PRD files
  Complete: 15 | In Progress: 3 | Backlog: 24

Loading roadmap.json...
  Found: 11 epics, 33 dependencies
  New epics added: 0 (all already exist as PRDs)

Parsing OrgMap_new.drawio...
  Agents: 5 (1 deprecated)
  Services: 3
  Workflow steps: 7

Building dependency graph...
  Total dependencies: 33
  Blocking PRDs: 6
  Blocked PRDs: 18

Sorting by dependencies and priority...
  Execution order determined

Writing roadmap...
  Output: .claude/scopes/gslr-roadmap.json

Roadmap generated successfully.
  Total PRDs: 42
  Ready to execute: 12 (no unmet dependencies)
  Blocked: 18 (waiting on dependencies)
  In progress: 3
  Complete: 15
```

## Error Handling

- If `.claude/prds/` doesn't exist: Error, cannot generate roadmap
- If `roadmap.json` doesn't exist: Skip, continue with PRDs only
- If `OrgMap_new.drawio` doesn't exist: Skip, continue without architecture
- If PRD has invalid frontmatter: Warn and skip that PRD
- If circular dependency detected: Warn and include in output

## Important Notes

1. This command is typically called by `/pm:scope-run` before execution
2. The roadmap is regenerated each time (not incremental)
3. OrgMap_new.drawio parsing extracts high-level structure only (it's XML)
4. Dependencies are inferred from PRD content if not explicitly stated
5. The execution_order respects both dependencies and priority
