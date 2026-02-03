#!/bin/bash
# ar-context.sh - Context file management for /ar:implement
#
# This script provides functions to manage context files that preserve state
# between agent invocations during recursive decomposition.
#
# Context files location: .claude/ar/{session}/
#   - context.md    - Accumulated knowledge and research
#   - progress.md   - Current phase and completed nodes
#   - tree.md       - Human-readable decomposition tree
#
# Usage:
#   source .claude/scripts/ar-context.sh
#   ar_init_context_dir "inventory-sharing"
#   ar_write_context "$SESSION" "research" "Found 5 gaps..."
#   ar_read_context "$SESSION"

set -e

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CONTEXT_BASE="${PROJECT_ROOT}/.claude/ar"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =============================================================================
# Directory Management
# =============================================================================

# Initialize context directory for a session
ar_init_context_dir() {
    local session_name="$1"
    local original_request="${2:-}"
    local context_dir="${CONTEXT_BASE}/${session_name}"

    mkdir -p "$context_dir"

    # Initialize context.md if it doesn't exist
    if [ ! -f "${context_dir}/context.md" ]; then
        local created_at
        created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        cat > "${context_dir}/context.md" << EOF
# Session Context: ${session_name}

## Original Request
${original_request:-[Not specified]}

## Research Findings
_Pending research phase_

## Codebase Analysis
- Existing patterns: _To be analyzed_
- Related files: _To be analyzed_
- Tech stack: FastAPI, React, PostgreSQL (cattle-erp)

## Gap Summary
| Gap | Type | Status | Key Insight |
|-----|------|--------|-------------|
| _Pending_ | - | - | - |

## Decisions Made
_No decisions yet_

## Current Focus
Initializing session

---
Created: ${created_at}
Updated: ${created_at}
EOF
        echo -e "${GREEN}Created context.md${NC}" >&2
    fi

    # Initialize progress.md if it doesn't exist
    if [ ! -f "${context_dir}/progress.md" ]; then
        cat > "${context_dir}/progress.md" << EOF
# Decomposition Progress

## Status: initializing

## Phase: setup

## Current Node
- ID: none
- Name: none
- Layer: 0

## Completed Nodes
_None yet_

## Next Actions
1. Research feature requirements
2. Identify gaps
3. Begin decomposition
EOF
        echo -e "${GREEN}Created progress.md${NC}" >&2
    fi

    # Initialize tree.md if it doesn't exist
    if [ ! -f "${context_dir}/tree.md" ]; then
        cat > "${context_dir}/tree.md" << EOF
# Decomposition Tree

${session_name} (root)
└── [P] Pending decomposition

Legend: [A]=Atomic, [-]=Non-atomic/Decomposing, [P]=Pending
EOF
        echo -e "${GREEN}Created tree.md${NC}" >&2
    fi

    echo "$context_dir"
}

# Get context directory path
ar_get_context_dir() {
    local session_name="$1"
    echo "${CONTEXT_BASE}/${session_name}"
}

# Check if context exists
ar_context_exists() {
    local session_name="$1"
    local context_dir="${CONTEXT_BASE}/${session_name}"

    [ -d "$context_dir" ] && [ -f "${context_dir}/context.md" ]
}

# =============================================================================
# Context File Operations
# =============================================================================

# Update context.md with new section content
ar_write_context() {
    local session_name="$1"
    local section="$2"
    local content="$3"
    local context_file="${CONTEXT_BASE}/${session_name}/context.md"

    if [ ! -f "$context_file" ]; then
        echo -e "${YELLOW}Warning: Context file not found, initializing${NC}" >&2
        ar_init_context_dir "$session_name"
    fi

    local updated_at
    updated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update the Updated timestamp
    sed -i "s/^Updated: .*/Updated: ${updated_at}/" "$context_file"

    case "$section" in
        research)
            # Replace Research Findings section
            sed -i '/^## Research Findings$/,/^## /{/^## Research Findings$/!{/^## /!d}}' "$context_file"
            sed -i "s/^## Research Findings$/## Research Findings\n${content}/" "$context_file"
            ;;
        codebase)
            # Replace Codebase Analysis section
            sed -i '/^## Codebase Analysis$/,/^## /{/^## Codebase Analysis$/!{/^## /!d}}' "$context_file"
            sed -i "s/^## Codebase Analysis$/## Codebase Analysis\n${content}/" "$context_file"
            ;;
        gaps)
            # Replace Gap Summary section
            sed -i '/^## Gap Summary$/,/^## /{/^## Gap Summary$/!{/^## /!d}}' "$context_file"
            sed -i "s/^## Gap Summary$/## Gap Summary\n${content}/" "$context_file"
            ;;
        decisions)
            # Append to Decisions Made section
            sed -i "/^## Decisions Made$/a\\- ${content}" "$context_file"
            ;;
        focus)
            # Replace Current Focus section
            sed -i '/^## Current Focus$/,/^---/{/^## Current Focus$/!{/^---/!d}}' "$context_file"
            sed -i "s/^## Current Focus$/## Current Focus\n${content}/" "$context_file"
            ;;
        *)
            echo -e "${YELLOW}Unknown section: $section${NC}" >&2
            return 1
            ;;
    esac

    echo -e "${BLUE}Updated context: $section${NC}" >&2
}

# Read entire context file
ar_read_context() {
    local session_name="$1"
    local context_file="${CONTEXT_BASE}/${session_name}/context.md"

    if [ -f "$context_file" ]; then
        cat "$context_file"
    else
        echo ""
    fi
}

# Read specific section from context
ar_read_context_section() {
    local session_name="$1"
    local section="$2"
    local context_file="${CONTEXT_BASE}/${session_name}/context.md"

    if [ ! -f "$context_file" ]; then
        echo ""
        return
    fi

    case "$section" in
        research)
            sed -n '/^## Research Findings$/,/^## /{/^## Research Findings$/d;/^## /d;p}' "$context_file"
            ;;
        codebase)
            sed -n '/^## Codebase Analysis$/,/^## /{/^## Codebase Analysis$/d;/^## /d;p}' "$context_file"
            ;;
        gaps)
            sed -n '/^## Gap Summary$/,/^## /{/^## Gap Summary$/d;/^## /d;p}' "$context_file"
            ;;
        decisions)
            sed -n '/^## Decisions Made$/,/^## /{/^## Decisions Made$/d;/^## /d;p}' "$context_file"
            ;;
        focus)
            sed -n '/^## Current Focus$/,/^---/{/^## Current Focus$/d;/^---/d;p}' "$context_file"
            ;;
        *)
            echo ""
            ;;
    esac
}

# =============================================================================
# Progress File Operations
# =============================================================================

# Update progress.md
ar_write_progress() {
    local session_name="$1"
    local status="$2"
    local phase="$3"
    local current_node_id="${4:-none}"
    local current_node_name="${5:-none}"
    local current_layer="${6:-0}"
    local progress_file="${CONTEXT_BASE}/${session_name}/progress.md"

    if [ ! -f "$progress_file" ]; then
        ar_init_context_dir "$session_name"
    fi

    cat > "$progress_file" << EOF
# Decomposition Progress

## Status: ${status}

## Phase: ${phase}

## Current Node
- ID: ${current_node_id}
- Name: ${current_node_name}
- Layer: ${current_layer}

EOF

    echo -e "${BLUE}Updated progress: status=${status}, phase=${phase}${NC}" >&2
}

# Append completed node to progress
ar_add_completed_node() {
    local session_name="$1"
    local node_name="$2"
    local node_status="$3"
    local prd_name="${4:-}"
    local progress_file="${CONTEXT_BASE}/${session_name}/progress.md"

    local entry
    if [ -n "$prd_name" ]; then
        entry="- [x] ${node_name} (${node_status}, PRD: ${prd_name})"
    else
        entry="- [x] ${node_name} (${node_status})"
    fi

    # Add to Completed Nodes section
    if grep -q "^## Completed Nodes$" "$progress_file"; then
        sed -i "/^## Completed Nodes$/a\\${entry}" "$progress_file"
    else
        echo -e "\n## Completed Nodes\n${entry}" >> "$progress_file"
    fi
}

# Read progress status
ar_read_progress_status() {
    local session_name="$1"
    local progress_file="${CONTEXT_BASE}/${session_name}/progress.md"

    if [ -f "$progress_file" ]; then
        grep "^## Status:" "$progress_file" | cut -d: -f2 | tr -d ' '
    else
        echo "unknown"
    fi
}

# Read progress phase
ar_read_progress_phase() {
    local session_name="$1"
    local progress_file="${CONTEXT_BASE}/${session_name}/progress.md"

    if [ -f "$progress_file" ]; then
        grep "^## Phase:" "$progress_file" | cut -d: -f2 | tr -d ' '
    else
        echo "unknown"
    fi
}

# =============================================================================
# Tree File Operations
# =============================================================================

# Update tree.md with current decomposition structure
ar_write_tree() {
    local session_name="$1"
    local tree_content="$2"
    local tree_file="${CONTEXT_BASE}/${session_name}/tree.md"

    cat > "$tree_file" << EOF
# Decomposition Tree

${tree_content}

Legend: [A]=Atomic, [-]=Non-atomic/Decomposing, [P]=Pending
EOF

    echo -e "${BLUE}Updated tree.md${NC}" >&2
}

# Generate tree from database
ar_generate_tree_from_db() {
    local session_name="$1"

    # Source ar-implement for DB access
    if [ -f "${PROJECT_ROOT}/.claude/scripts/ar-implement.sh" ]; then
        source "${PROJECT_ROOT}/.claude/scripts/ar-implement.sh"
    else
        echo "Error: ar-implement.sh not found"
        return 1
    fi

    # Query tree structure
    local tree_sql="
        WITH RECURSIVE tree AS (
            SELECT id, name, layer, is_atomic, status, prd_name, 0 AS indent
            FROM decomposition_nodes
            WHERE session_name = '$session_name' AND parent_id IS NULL
            UNION ALL
            SELECT n.id, n.name, n.layer, n.is_atomic, n.status, n.prd_name, t.indent + 1
            FROM decomposition_nodes n
            JOIN tree t ON n.parent_id = t.id
            WHERE n.session_name = '$session_name'
        )
        SELECT
            REPEAT('│   ', indent) ||
            CASE WHEN is_atomic THEN '[A] ' WHEN status = 'pending' THEN '[P] ' ELSE '[-] ' END ||
            name ||
            CASE WHEN prd_name IS NOT NULL THEN ' → ' || prd_name || '.md' ELSE '' END
        FROM tree
        ORDER BY indent, id
    "

    local tree_content
    tree_content=$(ar_query_rows "$tree_sql")

    if [ -n "$tree_content" ]; then
        ar_write_tree "$session_name" "${session_name} (root)
${tree_content}"
    fi
}

# =============================================================================
# Context Summary for Agent Prompts
# =============================================================================

# Generate concise context summary for agent handoff
ar_get_context_summary() {
    local session_name="$1"
    local max_lines="${2:-50}"

    local context_file="${CONTEXT_BASE}/${session_name}/context.md"

    if [ ! -f "$context_file" ]; then
        echo "No context available for session: $session_name"
        return
    fi

    # Extract key sections and compress
    local summary=""

    # Original request (first 3 lines)
    summary+="## Request\n"
    summary+=$(sed -n '/^## Original Request$/,/^## /{/^## Original Request$/d;/^## /d;p}' "$context_file" | head -3)
    summary+="\n\n"

    # Research (first 10 lines)
    local research
    research=$(sed -n '/^## Research Findings$/,/^## /{/^## Research Findings$/d;/^## /d;p}' "$context_file" | head -10)
    if [ -n "$research" ] && [ "$research" != "_Pending research phase_" ]; then
        summary+="## Research\n${research}\n\n"
    fi

    # Gap table (full)
    local gaps
    gaps=$(sed -n '/^## Gap Summary$/,/^## /{/^## Gap Summary$/d;/^## /d;p}' "$context_file")
    if [ -n "$gaps" ]; then
        summary+="## Gaps\n${gaps}\n\n"
    fi

    # Current focus
    local focus
    focus=$(sed -n '/^## Current Focus$/,/^---/{/^## Current Focus$/d;/^---/d;p}' "$context_file" | head -3)
    if [ -n "$focus" ]; then
        summary+="## Focus\n${focus}\n"
    fi

    echo -e "$summary" | head -"$max_lines"
}

# =============================================================================
# Cleanup
# =============================================================================

# Remove context directory for a session
ar_cleanup_context() {
    local session_name="$1"
    local context_dir="${CONTEXT_BASE}/${session_name}"

    if [ -d "$context_dir" ]; then
        rm -rf "$context_dir"
        echo -e "${GREEN}Cleaned up context for: $session_name${NC}" >&2
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "AR Context Management Script"
    echo ""
    echo "Usage: source .claude/scripts/ar-context.sh"
    echo ""
    echo "Functions available:"
    echo "  ar_init_context_dir <session> [request]  - Initialize context directory"
    echo "  ar_write_context <session> <section> <content>  - Update context section"
    echo "  ar_read_context <session>  - Read full context"
    echo "  ar_read_context_section <session> <section>  - Read specific section"
    echo "  ar_write_progress <session> <status> <phase> [node_id] [name] [layer]"
    echo "  ar_add_completed_node <session> <name> <status> [prd]  - Mark node complete"
    echo "  ar_write_tree <session> <content>  - Update tree visualization"
    echo "  ar_generate_tree_from_db <session>  - Generate tree from database"
    echo "  ar_get_context_summary <session> [max_lines]  - Get compressed summary"
    echo "  ar_cleanup_context <session>  - Remove context directory"
    echo ""
    echo "Sections: research, codebase, gaps, decisions, focus"
fi
