---
name: perspectives
created: 2026-01-22T14:32:00Z
---

# Perspectives and Hypotheses

## Hypotheses

### H1: Docker CLI + containerd snapshotter mismatch (Prior: HIGH 70%)
The docker CLI when used without dockerd but with containerd as backend may trigger recursive snapshotter operations when the build context or layer handling doesn't match containerd's expected workflow.

### H2: Overlayfs/native snapshotter resource exhaustion (Prior: MEDIUM 50%)
Certain snapshotter configurations (overlayfs, native, stargz) may create excessive mount operations or temporary files during docker build, appearing as fork bomb behavior through process spawning.

### H3: BuildKit spawning behavior differences (Prior: MEDIUM 60%)
Docker's BuildKit integration may spawn processes differently than nerdctl's native BuildKit usage, causing runaway process creation in containerd-only environments.

### H4: Socket/API compatibility issue (Prior: LOW 30%)
Docker CLI attempting to communicate with containerd socket may cause retry loops or connection spawning that manifests as fork bomb.

## Perspectives

### 1. Container Runtime Engineer (containerd maintainer view)
- How does containerd handle build requests from different clients?
- What are known compatibility issues with docker CLI?
- What snapshotter behaviors could cause resource exhaustion?

### 2. Kubernetes Platform Operator (practical ops view)
- What's the simplest way to prevent docker CLI usage?
- How to configure nodes to only expose nerdctl?
- What monitoring detects this issue early?

### 3. Claude Code Power User (enforcement view)
- What hooks/rules exist to intercept commands?
- Can binary paths be overridden or aliased?
- How to make enforcement persistent across sessions?

### 4. Security/Reliability Engineer (adversarial view)
- What happens if enforcement is bypassed?
- Are there edge cases where docker CLI might still be invoked?
- What's the blast radius of the fork bomb?

### 5. nerdctl Developer (alternative tooling view)
- Why does nerdctl not have this problem?
- What architectural differences prevent the issue?
- Are there migration considerations?

## Key Questions by Perspective

### Container Runtime (H1, H2, H3)
1. What is the exact mechanism causing process multiplication?
2. Which snapshotter configurations are affected?
3. Is this a known issue with reported fixes?

### Platform Operator (practical)
1. Can docker binary be safely removed or disabled?
2. What's the minimal containerd configuration change?
3. How to detect and kill the runaway processes?

### Claude Code User (enforcement)
1. Does Claude Code support command hooks or pre-execution rules?
2. Can CLAUDE.md rules reliably block specific commands?
3. What's the precedence of different enforcement mechanisms?

### Security (adversarial)
1. Can Claude be tricked into using docker despite rules?
2. What if a script internally calls docker?
3. How to audit that enforcement is working?
