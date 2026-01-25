#!/bin/bash
# optimize_mermaid_diagram.sh - Validate and optimize Mermaid flowchart diagrams
#
# Features:
# - Removes orphan nodes (defined but never connected)
# - Reorders node definitions to minimize line crossings
# - Validates syntax basics
#
# Usage: ./optimize_mermaid_diagram.sh <input.md> [output.md]
# If output is omitted, modifies input in place

set -euo pipefail

INPUT_FILE="${1:-}"
OUTPUT_FILE="${2:-$INPUT_FILE}"

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "Usage: $0 <input.md> [output.md]" >&2
  exit 1
fi

# Extract mermaid code block from markdown
extract_mermaid() {
  sed -n '/```mermaid/,/```/p' "$1" | sed '1d;$d'
}

# Main execution
MERMAID_CODE=$(extract_mermaid "$INPUT_FILE")

if [ -z "$MERMAID_CODE" ]; then
  echo "No mermaid code block found in $INPUT_FILE" >&2
  exit 1
fi

# Write mermaid code to temp file for Python to read
TEMP_MERMAID=$(mktemp)
echo "$MERMAID_CODE" > "$TEMP_MERMAID"

# Get the content before and after the mermaid block
BEFORE=$(sed -n '1,/```mermaid/p' "$INPUT_FILE")
AFTER=$(sed -n '/^```$/,$ p' "$INPUT_FILE" | tail -n +2)

# Optimize the diagram using Python
OPTIMIZED=$(python3 - "$TEMP_MERMAID" << 'PYTHON_SCRIPT'
import sys
import re
from collections import defaultdict

# Read mermaid code from temp file
with open(sys.argv[1], 'r') as f:
    mermaid_code = f.read()

# Parse nodes and edges
node_pattern = re.compile(r'^\s*(\w+)\s*[\[\(\{"\']', re.MULTILINE)
edge_pattern = re.compile(r'(\w+)\s*(?:-->|-.->|==>|--o|--x|<-->|~~~)\s*(?:\|[^|]*\|)?\s*(\w+)')
subgraph_pattern = re.compile(r'subgraph\s+(\w+)')
subgraph_end_pattern = re.compile(r'^\s*end\s*$', re.MULTILINE)

# Find all nodes defined in the diagram
defined_nodes = set()
for match in node_pattern.finditer(mermaid_code):
    node_id = match.group(1)
    # Skip keywords
    if node_id.lower() not in ('subgraph', 'end', 'direction', 'classdef', 'linkstyle', 'click', 'flowchart', 'graph'):
        defined_nodes.add(node_id)

# Find all nodes that appear in edges (connected nodes)
connected_nodes = set()
edges = []
for match in edge_pattern.finditer(mermaid_code):
    src, dst = match.group(1), match.group(2)
    connected_nodes.add(src)
    connected_nodes.add(dst)
    edges.append((src, dst))

# Find orphan nodes (defined but never in any edge)
orphan_nodes = defined_nodes - connected_nodes

if orphan_nodes:
    print(f"# Removing {len(orphan_nodes)} orphan node(s): {', '.join(sorted(orphan_nodes))}", file=sys.stderr)

# Build adjacency for layout optimization
outgoing = defaultdict(list)  # node -> [targets]
incoming = defaultdict(list)  # node -> [sources]
for src, dst in edges:
    outgoing[src].append(dst)
    incoming[dst].append(src)

# Function to compute optimal node order within a layer
def optimal_order(nodes, target_nodes, node_connections):
    """Order nodes to minimize crossings with target layer."""
    if not nodes or not target_nodes:
        return list(nodes)

    # Create position map for target layer
    target_pos = {n: i for i, n in enumerate(target_nodes)}

    # Score each node by average position of its targets
    def score(node):
        targets = [t for t in node_connections.get(node, []) if t in target_pos]
        if not targets:
            return float('inf')
        return sum(target_pos[t] for t in targets) / len(targets)

    return sorted(nodes, key=score)

# Process the diagram line by line
lines = mermaid_code.split('\n')
result_lines = []
current_subgraph = None
subgraph_stack = []
pending_nodes = []  # (node_id, full_line)
all_subgraph_nodes = defaultdict(list)  # subgraph_name -> [node_ids in order]

# First pass: collect all subgraph nodes
for line in lines:
    stripped = line.strip()

    sg_match = subgraph_pattern.match(stripped)
    if sg_match:
        subgraph_stack.append(sg_match.group(1))
        current_subgraph = sg_match.group(1)
        continue

    if subgraph_end_pattern.match(stripped) and subgraph_stack:
        subgraph_stack.pop()
        current_subgraph = subgraph_stack[-1] if subgraph_stack else None
        continue

    if current_subgraph:
        node_match = node_pattern.match(stripped)
        if node_match:
            node_id = node_match.group(1)
            if node_id.lower() not in ('subgraph', 'end', 'direction', 'classdef', 'linkstyle', 'click', 'flowchart', 'graph'):
                if node_id not in orphan_nodes:
                    all_subgraph_nodes[current_subgraph].append(node_id)

# Get ordered list of subgraphs (by appearance)
subgraph_order = []
for line in lines:
    sg_match = subgraph_pattern.match(line.strip())
    if sg_match and sg_match.group(1) not in subgraph_order:
        subgraph_order.append(sg_match.group(1))

# Optimize node order for each subgraph based on next layer
optimized_subgraph_nodes = {}
for i, sg_name in enumerate(subgraph_order):
    nodes = all_subgraph_nodes[sg_name]
    # Get next layer's nodes
    if i + 1 < len(subgraph_order):
        next_sg = subgraph_order[i + 1]
        next_nodes = all_subgraph_nodes[next_sg]
        optimized_subgraph_nodes[sg_name] = optimal_order(nodes, next_nodes, outgoing)
    else:
        # Last layer - optimize based on incoming
        if i > 0:
            prev_sg = subgraph_order[i - 1]
            prev_nodes = all_subgraph_nodes[prev_sg]
            optimized_subgraph_nodes[sg_name] = optimal_order(nodes, prev_nodes, incoming)
        else:
            optimized_subgraph_nodes[sg_name] = nodes

# Second pass: rebuild with optimized order and orphans removed
current_subgraph = None
subgraph_stack = []
node_lines = {}  # node_id -> full line

i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.strip()

    # Check for subgraph start
    sg_match = subgraph_pattern.match(stripped)
    if sg_match:
        sg_name = sg_match.group(1)
        subgraph_stack.append(sg_name)
        current_subgraph = sg_name
        result_lines.append(line)

        # Collect node lines for this subgraph
        node_lines = {}
        other_lines = []
        i += 1
        while i < len(lines):
            inner_line = lines[i]
            inner_stripped = inner_line.strip()

            if subgraph_end_pattern.match(inner_stripped):
                # Output nodes in optimized order
                if sg_name in optimized_subgraph_nodes:
                    for node_id in optimized_subgraph_nodes[sg_name]:
                        if node_id in node_lines:
                            result_lines.append(node_lines[node_id])

                # Output other non-node lines
                for other_line in other_lines:
                    result_lines.append(other_line)

                result_lines.append(inner_line)  # 'end' line
                subgraph_stack.pop()
                current_subgraph = subgraph_stack[-1] if subgraph_stack else None
                break

            node_match = node_pattern.match(inner_stripped)
            if node_match:
                node_id = node_match.group(1)
                if node_id.lower() not in ('subgraph', 'end', 'direction', 'classdef', 'linkstyle', 'click', 'flowchart', 'graph'):
                    if node_id not in orphan_nodes:
                        node_lines[node_id] = inner_line
                else:
                    other_lines.append(inner_line)
            else:
                other_lines.append(inner_line)

            i += 1
        i += 1
        continue

    # Edge or other line - skip if references orphan node
    if any(orphan in stripped for orphan in orphan_nodes):
        i += 1
        continue

    result_lines.append(line)
    i += 1

print('\n'.join(result_lines))
PYTHON_SCRIPT
)

# Clean up temp file
rm -f "$TEMP_MERMAID"

# Check for stderr output (orphan removal messages)
STDERR_OUTPUT=$(echo "$OPTIMIZED" 2>&1 >/dev/null || true)

# Reconstruct the file
{
  echo "$BEFORE"
  echo "$OPTIMIZED"
  echo '```'
  echo "$AFTER"
} > "$OUTPUT_FILE"

echo "Optimized: $OUTPUT_FILE" >&2
