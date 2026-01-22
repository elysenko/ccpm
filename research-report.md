# Docker Build Fork Bomb Behavior with Containerd: Root Cause Analysis and Claude Code Enforcement

**Research Date:** 2026-01-22
**Classification:** Type C Analysis
**Confidence Level:** High (multiple independent sources confirm findings)

---

## Executive Summary

The "fork bomb" behavior observed when using `docker build` in a containerd-only Kubernetes environment is **not a true fork bomb** but rather a combination of two distinct failure modes:

1. **BuildKit Initialization Timeout Storm** - Docker daemon with containerd snapshotter enters a CPU-intensive loop during startup when many images/builds exist, causing 100% CPU utilization before timing out
2. **Containerd-Shim Process Leaks** - Under high pod churn or disk I/O, shim processes accumulate due to timeout mismatches between mount operations and gRPC clients

**Key Finding:** Using `nerdctl` instead of `docker` CLI avoids the daemon-related timeout issues because nerdctl interacts directly with containerd without requiring a centralized daemon architecture.

**Claude Code Enforcement:** Two reliable methods exist - PreToolUse hooks (guaranteed execution) and binary path aliasing (system-level). CLAUDE.md rules alone are insufficient as they can be deprioritized.

---

## Part 1: Root Cause Analysis

### The Problem is NOT a Fork Bomb

A true fork bomb recursively spawns processes until system resources are exhausted. What you're experiencing is more accurately described as:

1. **Resource exhaustion from initialization failures** - The docker daemon, when configured with containerd snapshotter, can enter a pathological state during startup
2. **Shim process accumulation** - containerd-shim-runc-v2 processes leak under specific conditions

### Root Cause #1: BuildKit Initialization Timeout (Docker 27.x)

**Affected Versions:** Docker 27.2.1, 27.3.1 (fixed in 27.4.0)

**Mechanism:** When Docker starts with the containerd snapshotter enabled and many images/builds exist (~40+), the BuildKit component performs consistency checks against containerd. This process:

1. Docker daemon starts and initializes BuildKit
2. BuildKit validates cache records against containerd's boltdb
3. gRPC communication between Docker and containerd becomes bottlenecked
4. Both processes consume 100% CPU for 1-2 minutes
5. Initialization exceeds the configured timeout
6. `dockerd` exits with "context deadline exceeded"
7. systemd restarts dockerd, repeating the cycle (observed 25+ restarts)

This creates the *appearance* of fork bomb behavior due to:
- Sustained 100% CPU
- Repeated process spawning (systemd restarts)
- System unresponsiveness

**Source:** [moby/moby Issue #48569](https://github.com/moby/moby/issues/48569)

**Fix:** [PR #48953](https://github.com/moby/moby/pull/48953) removed the BuildKit init timeout entirely. Merged November 2024, released in Docker 27.4.0.

### Root Cause #2: Containerd-Shim Process Leaks

**Affected Versions:** containerd 2.0.6, 2.1.4 (NOT affecting 1.7.27)

**Mechanism:** Under high pod churn or high disk I/O:

1. Container deletion triggers `mount.UnmountAll` which can take 20-30 seconds
2. gRPC client timeout is 10 seconds
3. Client times out but server-side deletion continues
4. Container ID is removed from local records before shim cleanup completes
5. Orphaned shim processes remain with PPID=1

**Symptoms:**
- Hundreds of `containerd-shim-runc-v2` processes
- `ctr -n k8s.io c info` cannot find associated containers
- Gradual memory growth leading to OOM

**Source:** [containerd/containerd Issue #12344](https://github.com/containerd/containerd/issues/12344), [Issue #7496](https://github.com/containerd/containerd/issues/7496)

### Why nerdctl Avoids These Issues

| Aspect | Docker CLI | nerdctl |
|--------|-----------|---------|
| Architecture | Centralized daemon (dockerd) | Daemonless, direct containerd |
| BuildKit | Managed by dockerd with init timeout | Standalone buildkitd, no timeout coupling |
| Startup dependency | Requires full daemon initialization | Per-command execution |
| Failure isolation | Daemon failure affects all operations | Command failures are isolated |

Both use BuildKit for the actual build process, but nerdctl's direct interaction with containerd bypasses the problematic daemon initialization sequence.

**Source:** [nerdctl GitHub Repository](https://github.com/containerd/nerdctl)

---

## Part 2: Solutions Ranked by Effectiveness

### Solution 1: Claude Code PreToolUse Hook (RECOMMENDED)

**Reliability:** Guaranteed execution
**Complexity:** Low
**Persistence:** Survives context window limits

PreToolUse hooks execute before every tool call and cannot be overridden by conversation context or CLAUDE.md instructions.

#### Implementation

Create `~/.claude/settings.json` or `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"import json, sys; data=json.load(sys.stdin); cmd=data.get('tool_input',{}).get('command',''); blocked=['docker build','docker push','docker-compose build']; sys.exit(2) if any(b in cmd for b in blocked) else sys.exit(0)\" 2>&1 || echo 'Use nerdctl instead of docker. Run: nerdctl build' >&2"
          }
        ]
      }
    ]
  }
}
```

Or use a dedicated script for better maintainability:

**`.claude/hooks/block-docker.py`:**
```python
#!/usr/bin/env python3
import json
import sys

BLOCKED_PATTERNS = [
    'docker build',
    'docker push',
    'docker-compose build',
    'docker compose build',
]

ALLOWED_ALTERNATIVES = {
    'docker build': 'nerdctl build',
    'docker push': 'nerdctl push',
    'docker-compose': 'nerdctl compose',
}

try:
    data = json.load(sys.stdin)
    cmd = data.get('tool_input', {}).get('command', '')

    for pattern in BLOCKED_PATTERNS:
        if pattern in cmd:
            print(f"BLOCKED: '{pattern}' is not allowed in this environment.", file=sys.stderr)
            print(f"Use '{ALLOWED_ALTERNATIVES.get(pattern, 'nerdctl')}' instead.", file=sys.stderr)
            print("Reason: docker CLI causes resource exhaustion with containerd snapshotter.", file=sys.stderr)
            sys.exit(2)  # Exit code 2 = block the action

    sys.exit(0)  # Allow
except Exception as e:
    print(f"Hook error: {e}", file=sys.stderr)
    sys.exit(0)  # Fail open to avoid blocking legitimate commands
```

**`settings.json`:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 .claude/hooks/block-docker.py"
          }
        ]
      }
    ]
  }
}
```

**Why this works:** Exit code 2 is a hard block. The stderr message is shown to Claude, providing feedback on what to do instead. Unlike CLAUDE.md instructions, hooks execute deterministically every time.

**Source:** [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)

---

### Solution 2: System-Level Binary Aliasing

**Reliability:** High (bypasses Claude entirely)
**Complexity:** Medium
**Persistence:** Permanent until reversed

Replace or alias the `docker` binary at the system level so all invocations use nerdctl.

#### Option A: Shell Alias (User Level)

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Redirect docker to nerdctl
alias docker='nerdctl'
alias docker-compose='nerdctl compose'

# For Kubernetes namespace compatibility
alias docker='nerdctl -n k8s.io'
```

**Limitation:** Only works for interactive shells. Scripts using `#!/bin/bash` may bypass aliases.

#### Option B: Binary Wrapper (System Level)

```bash
# Backup original docker (if exists)
sudo mv /usr/bin/docker /usr/bin/docker.disabled 2>/dev/null || true

# Create wrapper script
sudo tee /usr/bin/docker << 'EOF'
#!/bin/bash
echo "WARNING: docker CLI is disabled. Using nerdctl instead." >&2
exec nerdctl "$@"
EOF

sudo chmod +x /usr/bin/docker
```

#### Option C: Remove Docker CLI Entirely

```bash
# Remove docker CLI package
sudo apt remove docker-ce-cli  # Debian/Ubuntu
# or
sudo yum remove docker-ce-cli  # RHEL/CentOS

# Ensure nerdctl is installed
# See: https://github.com/containerd/nerdctl/releases
```

**Source:** [Docker to nerdctl Migration Guide](https://medium.com/@pirocheto/installation-guide-for-migrating-from-docker-to-containerd-nerdctl-0847e30d608c)

---

### Solution 3: CLAUDE.md Rules (Supplementary Only)

**Reliability:** Low to Medium (can be deprioritized)
**Complexity:** Very Low
**Persistence:** Can be pushed out of context window

Your existing `docker-operations.md` rule is a good start but should be supplemented with hooks.

**Why CLAUDE.md is insufficient:**

> "An instruction in your CLAUDE.md file is a suggestion. The AI will probably follow it, but in a long conversation, it might get pushed out of the context window or just de-prioritized. A hook, on the other hand, is a hard-coded rule."

**Source:** [Claude Code Hooks: Guardrails That Actually Work](https://paddo.dev/blog/claude-code-hooks-guardrails/)

**Recommendation:** Keep your existing rule for documentation and guidance, but enforce with hooks.

---

### Solution 4: Upgrade Docker (If You Must Use Docker)

If you cannot migrate to nerdctl:

1. **Upgrade to Docker 27.4.0+** - Contains the BuildKit timeout fix
2. **Use containerd 1.7.x** - Avoids shim leak issues in 2.x
3. **Monitor shim processes:**
   ```bash
   watch 'ps aux | grep containerd-shim | wc -l'
   ```
4. **Set resource limits:**
   ```bash
   # In /etc/docker/daemon.json
   {
     "containerd-snapshotter": {
       "gc": true,
       "gc-config": {
         "schedule": "24h"
       }
     }
   }
   ```

---

## Part 3: Implementation Checklist

### Immediate Actions (Today)

- [ ] Create `.claude/hooks/block-docker.py` with the script above
- [ ] Add PreToolUse hook to `.claude/settings.json`
- [ ] Test by asking Claude to run `docker build` - should be blocked

### Short-Term Actions (This Week)

- [ ] Create system-level docker wrapper script
- [ ] Verify nerdctl is installed and functional: `nerdctl version`
- [ ] Update any existing scripts that call `docker` to use `nerdctl`
- [ ] Add monitoring for containerd-shim process count

### Validation

Test that enforcement works:

```
# In Claude Code session:
"Run docker build -t test ."

# Expected response:
"I cannot run docker build as it's blocked by a PreToolUse hook.
 Use nerdctl build instead: nerdctl build -t test ."
```

---

## Limitations and Open Questions

### Limitations

1. **Hook bypass via scripts** - If Claude writes and executes a shell script that contains `docker build`, the hook only sees the script execution, not the docker command within
2. **nerdctl feature gaps** - Some advanced Docker commands may not have nerdctl equivalents
3. **Namespace handling** - nerdctl uses containerd namespaces; images built without `-n k8s.io` won't be visible to Kubernetes

### What Would Change Our Conclusions

1. Evidence that nerdctl also triggers the BuildKit timeout issue
2. A Docker update that fundamentally changes the daemon architecture
3. Claude Code implementing command-level analysis for script contents

---

## Sources

### Primary Sources (Grade A)
- [moby/moby Issue #48569: dockerd fails with containerd snapshotter](https://github.com/moby/moby/issues/48569)
- [moby/moby PR #48953: Remove buildkit init timeout](https://github.com/moby/moby/pull/48953)
- [containerd/containerd Issue #12344: Shim process leaks](https://github.com/containerd/containerd/issues/12344)
- [containerd/nerdctl: Official Repository](https://github.com/containerd/nerdctl)
- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks-guide)

### Secondary Sources (Grade B)
- [containerd/containerd Issue #7496: Shim leaks under high disk I/O](https://github.com/containerd/containerd/issues/7496)
- [Claude Code Hooks: Guardrails That Actually Work](https://paddo.dev/blog/claude-code-hooks-guardrails/)
- [Docker vs Podman vs Containerd vs nerdctl Comparison](https://sanj.dev/post/docker-vs-podman-comparison)

### Supplementary Sources (Grade C)
- [Docker to nerdctl Migration Guide](https://medium.com/@pirocheto/installation-guide-for-migrating-from-docker-to-containerd-nerdctl-0847e30d608c)
- [Building Images with containerd](https://www.jimangel.io/posts/building-images-with-containerd/)
- [Embracing Nerdctl: Shift from DockerD to ContainerD](https://blogs.halodoc.io/docker-removal-nerdctl-adoption/)
