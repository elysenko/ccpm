# Research Contract: Bash Script Formatting Standards

## Core Question
What are the current best practices, style conventions, and tooling for formatting bash scripts to establish consistent code review standards?

## Decision/Use-Case
Establishing code review criteria for bash scripts - reviewers need clear, enforceable standards to evaluate script quality and consistency.

## Audience
Technical (developers and code reviewers)

## Scope
- **Geography**: Global (bash is universal)
- **Timeframe**: Current state (2024-2025 best practices)
- **Include**: Style guides (Google, community), formatters (shfmt), linters (shellcheck), indentation/naming conventions, error handling patterns, portability considerations
- **Exclude**: Zsh/fish-specific features, Windows batch scripting

## Constraints
- **Required sources**: Official tool documentation, major style guides (Google Shell Style Guide), community consensus (ShellCheck wiki, bash-hackers)
- **Avoid**: Outdated pre-2020 guides, opinion blogs without tooling backing

## Output Format
Actionable checklist with:
- Categorized formatting rules (indentation, naming, quoting, structure)
- Tool configurations (shfmt flags, shellcheck directives)
- Code review checklist items
- Anti-patterns to flag

## Definition of Done
- Covers all major formatting dimensions (whitespace, naming, quoting, structure, error handling)
- Includes tool-enforceable rules vs manual review items
- Provides specific shfmt/shellcheck configurations
- Actionable enough to use directly in code reviews

## Research Type
Type C: Analysis (Full 7-phase GoT)

## Intensity
Deep (5-8 agents, depth 4, stop score > 9)

---
Created: 2026-01-22
