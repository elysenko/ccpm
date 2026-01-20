# Findings: Dependency Graph Algorithms

## SQ3: What algorithms work for dependency graph construction, cycle detection, topological sort?

### Overview

PRD dependencies form a directed graph where edges represent "must complete before" relationships. For valid decomposition, this graph must be a Directed Acyclic Graph (DAG)—cycles would indicate impossible orderings.

---

## Topological Sort

**Evidence Grade: A (Computer science fundamentals)**

### Definition
A topological sort produces a linear ordering of vertices such that for every directed edge (u, v), vertex u comes before v in the ordering. This is possible if and only if the graph is a DAG.

### Standard Algorithms

#### Kahn's Algorithm (BFS-based)
```python
def kahn_topological_sort(graph):
    """
    Time: O(V + E)
    Space: O(V)
    """
    in_degree = {v: 0 for v in graph.vertices}
    for u in graph.vertices:
        for v in graph.neighbors(u):
            in_degree[v] += 1

    # Start with vertices having no dependencies
    queue = [v for v in graph.vertices if in_degree[v] == 0]
    result = []

    while queue:
        u = queue.pop(0)
        result.append(u)
        for v in graph.neighbors(u):
            in_degree[v] -= 1
            if in_degree[v] == 0:
                queue.append(v)

    # If result doesn't include all vertices, cycle exists
    if len(result) != len(graph.vertices):
        raise CycleDetectedError("Graph contains cycle")

    return result
```

**Advantages:**
- Naturally detects cycles (incomplete result)
- Returns vertices in valid execution order
- Easy to understand and implement

#### DFS-based Approach
```python
def dfs_topological_sort(graph):
    """
    Time: O(V + E)
    Space: O(V)
    """
    visited = set()
    stack = []

    def dfs(v, temp_visited):
        if v in temp_visited:
            raise CycleDetectedError(f"Cycle detected at {v}")
        if v in visited:
            return

        temp_visited.add(v)
        for neighbor in graph.neighbors(v):
            dfs(neighbor, temp_visited)

        temp_visited.remove(v)
        visited.add(v)
        stack.append(v)

    for v in graph.vertices:
        if v not in visited:
            dfs(v, set())

    return stack[::-1]  # Reverse for correct order
```

**Advantages:**
- Single pass through graph
- Detects cycles during traversal
- Memory efficient with recursion

---

## Incremental Topological Ordering

**Evidence Grade: A (Academic research - Bender, Haeupler, et al.)**

For dynamic graphs where PRDs/dependencies are added incrementally:

### Problem Statement
Start with empty graph G = (V, ∅). Edges are added one at a time. Maintain valid topological ordering throughout.

### Algorithm Complexity Comparison

| Algorithm | Total Time for m insertions | Authors |
|-----------|---------------------------|---------|
| Naive (recompute) | O(n(m + n)) | - |
| Marchetti-Spaccamela | O(mn) | 1988 |
| **Haeupler et al.** | **O(m^(3/2))** | 2008 |
| Ajwani et al. | O(n^2.75) | Dense graphs |

### Recommended: Haeupler's Algorithm

For typical PRD counts (10-100), simpler algorithms suffice. For large-scale systems:

```python
def incremental_topological_update(graph, ordering, new_edge):
    """
    When adding edge (u, v):
    - If u already before v in ordering: no change needed
    - If v before u: need to reorder affected region
    - If creates cycle: reject edge

    Amortized: O(m^(3/2)) total for m insertions
    """
    u, v = new_edge

    u_pos = ordering.index(u)
    v_pos = ordering.index(v)

    if u_pos < v_pos:
        # Already valid
        graph.add_edge(u, v)
        return True

    # Check for cycle: v can reach u?
    if can_reach(graph, v, u):
        return False  # Would create cycle

    # Reorder: move affected vertices
    affected = get_affected_region(graph, ordering, u, v)
    reorder_region(ordering, affected)
    graph.add_edge(u, v)
    return True
```

---

## Cycle Detection

**Evidence Grade: A (Tarjan's Algorithm)**

### Tarjan's Strongly Connected Components

Detects cycles by finding strongly connected components (SCCs). Any SCC with more than one vertex contains cycles.

```python
def tarjan_scc(graph):
    """
    Time: O(V + E)
    Space: O(V)

    Returns list of SCCs. Cycles exist if any SCC has size > 1.
    """
    index_counter = [0]
    stack = []
    lowlinks = {}
    index = {}
    on_stack = {}
    sccs = []

    def strongconnect(v):
        index[v] = index_counter[0]
        lowlinks[v] = index_counter[0]
        index_counter[0] += 1
        stack.append(v)
        on_stack[v] = True

        for w in graph.neighbors(v):
            if w not in index:
                strongconnect(w)
                lowlinks[v] = min(lowlinks[v], lowlinks[w])
            elif on_stack.get(w, False):
                lowlinks[v] = min(lowlinks[v], index[w])

        if lowlinks[v] == index[v]:
            scc = []
            while True:
                w = stack.pop()
                on_stack[w] = False
                scc.append(w)
                if w == v:
                    break
            sccs.append(scc)

    for v in graph.vertices:
        if v not in index:
            strongconnect(v)

    return sccs


def has_cycles(graph):
    """Returns True if graph contains any cycles."""
    sccs = tarjan_scc(graph)
    return any(len(scc) > 1 for scc in sccs)


def find_cycles(graph):
    """Returns list of cycles (SCCs with size > 1)."""
    sccs = tarjan_scc(graph)
    return [scc for scc in sccs if len(scc) > 1]
```

### Simpler Cycle Detection (for small graphs)

For typical PRD counts, simple DFS suffices:

```python
def simple_cycle_check(graph, new_edge):
    """
    Check if adding edge (u, v) would create cycle.
    True if v can already reach u.
    """
    u, v = new_edge
    visited = set()

    def can_reach(start, target):
        if start == target:
            return True
        if start in visited:
            return False
        visited.add(start)
        for neighbor in graph.neighbors(start):
            if can_reach(neighbor, target):
                return True
        return False

    return can_reach(v, u)
```

---

## Dependency Types in Requirements

**Evidence Grade: B (Springer academic journal)**

Research identifies four dependency types between features:

### 1. Refinement
One requirement elaborates another at a more detailed level.
- **Implication:** Child depends on parent for context
- **Graph:** Parent → Child edge

### 2. Constraint
One requirement restricts another's implementation options.
- **Implication:** Constrained requirement must consider constraint
- **Graph:** Constraint → Constrained edge

### 3. Influence
One requirement affects the priority or urgency of another.
- **Implication:** Soft dependency, not blocking
- **Graph:** May not need edge, just metadata

### 4. Interaction
Requirements share resources, data, or interfaces.
- **Implication:** Must be coordinated
- **Graph:** Bidirectional influence (potential cycle concern)

### Classification for Automation

| Type | Creates Edge? | Direction | Cycle Risk |
|------|--------------|-----------|-----------|
| Refinement | Yes | Parent → Child | Low |
| Constraint | Yes | Constraint → Target | Medium |
| Influence | Optional | Soft link | None |
| Interaction | Careful | May be bidirectional | High |

---

## DAG Validation Pipeline

```python
class DependencyDAG:
    def __init__(self):
        self.graph = {}  # adjacency list
        self.ordering = []  # current topological order

    def add_prd(self, prd_id):
        """Add new PRD node."""
        if prd_id not in self.graph:
            self.graph[prd_id] = []
            self.ordering.append(prd_id)

    def add_dependency(self, from_prd, to_prd):
        """
        Add dependency: from_prd must complete before to_prd.
        Returns (success, error_message).
        """
        # Ensure both exist
        self.add_prd(from_prd)
        self.add_prd(to_prd)

        # Check for cycle
        if self._would_create_cycle(from_prd, to_prd):
            cycle = self._find_cycle_path(from_prd, to_prd)
            return False, f"Cycle detected: {' -> '.join(cycle)}"

        # Add edge and update ordering
        self.graph[from_prd].append(to_prd)
        self._update_ordering(from_prd, to_prd)
        return True, None

    def get_execution_order(self):
        """Return PRDs in valid execution order."""
        return self.ordering.copy()

    def get_parallel_groups(self):
        """
        Return groups of PRDs that can execute in parallel.
        PRDs with same depth in DAG can run together.
        """
        depths = self._calculate_depths()
        groups = {}
        for prd, depth in depths.items():
            if depth not in groups:
                groups[depth] = []
            groups[depth].append(prd)
        return [groups[d] for d in sorted(groups.keys())]

    def validate(self):
        """
        Full validation returning list of issues.
        """
        issues = []

        # Check for cycles
        cycles = self._find_all_cycles()
        for cycle in cycles:
            issues.append({
                'type': 'CYCLE',
                'severity': 'ERROR',
                'prds': cycle,
                'message': f"Circular dependency: {' -> '.join(cycle)}"
            })

        # Check for orphans (no dependencies, not depended on)
        orphans = self._find_orphans()
        for orphan in orphans:
            issues.append({
                'type': 'ORPHAN',
                'severity': 'WARNING',
                'prds': [orphan],
                'message': f"PRD {orphan} has no dependencies"
            })

        # Check for deep chains (> 5 levels suggests poor decomposition)
        max_depth = self._calculate_max_depth()
        if max_depth > 5:
            issues.append({
                'type': 'DEEP_CHAIN',
                'severity': 'WARNING',
                'message': f"Dependency chain depth {max_depth} > 5"
            })

        return issues
```

---

## Performance Recommendations

| PRD Count | Algorithm | Expected Time |
|-----------|-----------|---------------|
| < 50 | Simple DFS | < 1ms |
| 50-500 | Kahn's | < 10ms |
| 500-5000 | Haeupler incremental | < 100ms |
| > 5000 | Consider partitioning | Varies |

For typical pm:decompose use cases (10-50 PRDs per roadmap), simple algorithms are sufficient. Optimize only if profiling shows bottleneck.
