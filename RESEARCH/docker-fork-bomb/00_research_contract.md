---
name: docker-fork-bomb-containerd
created: 2026-01-22T14:30:00Z
updated: 2026-01-22T14:30:00Z
status: in-progress
type: C-ANALYSIS
---

# Research Contract: Docker Build Fork Bomb with Containerd Snapshotters

## Core Question
Why does `docker build` create fork bomb behavior with containerd snapshotters, and how can Claude Code be reliably forced to use nerdctl instead?

## Decision Context
DevOps troubleshooting for K8s+containerd environment where docker CLI triggers runaway processes. Need actionable fix plus Claude Code enforcement mechanism.

## Audience
Technical - DevOps engineers working with Kubernetes and containerd

## Scope
- **Geography**: N/A (technical)
- **Timeframe**: Current (2024-2025 containerd/nerdctl versions)
- **Include**: containerd snapshotter behavior, nerdctl vs docker CLI differences, Claude Code command enforcement methods (hooks, rules, binary interception)
- **Exclude**: Docker daemon issues (not using dockerd)

## Constraints
- **Required sources**: containerd/nerdctl GitHub issues, official docs, Claude Code documentation
- **Avoid**: Generic Docker tutorials
- **Depth**: Standard (practical solutions, not academic)

## Output Format
Diagnostic explanation + ranked solution options with implementation steps

## Definition of Done
1. Root cause of fork bomb identified with evidence
2. At least 2 working methods to enforce nerdctl usage in Claude Code
3. All claims supported by citations
