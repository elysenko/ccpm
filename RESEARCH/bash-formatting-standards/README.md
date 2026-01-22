# Bash Formatting Standards Research

Research conducted: 2026-01-22

## Overview

This research establishes comprehensive, enforceable standards for bash script formatting and code review, synthesizing guidance from:
- Google Shell Style Guide
- shfmt (official formatter)
- ShellCheck (official linter)
- Community best practices (Greg's Wiki, etc.)

## Key Deliverables

### Main Report
- **[08_report/bash-formatting-standards.md](./08_report/bash-formatting-standards.md)** - Complete code review guide

### Research Artifacts
- `00_research_contract.md` - Research scope and constraints
- `01_hypotheses.md` - Testable hypotheses and outcomes
- `01a_perspectives.md` - Stakeholder perspectives considered
- `03_source_catalog.csv` - Source quality ratings
- `04_evidence_ledger.csv` - Verified claims with evidence

## Quick Start

### Tool Configuration

**shfmt (Google style):**
```bash
shfmt -i 2 -ci -bn -sr
```

**ShellCheck (.shellcheckrc):**
```bash
shell=bash
external-sources=true
source-path=SCRIPTDIR
enable=quote-safe-variables
enable=require-variable-braces
```

### Key Standards Summary

| Category | Standard |
|----------|----------|
| Indentation | 2 spaces (never tabs) |
| Line length | 80 characters max |
| Variables | `lowercase_snake_case` |
| Constants | `UPPERCASE_SNAKE_CASE` |
| Functions | `name() {` syntax (no `function` keyword) |
| Tests | `[[ ]]` over `[ ]` |
| Command substitution | `$(cmd)` over backticks |
| Quoting | Always quote variables |
| Error handling | `set -euo pipefail` |

## Research Methodology

Type C: Analysis (Full 7-Phase GoT)
- 18 primary sources consulted
- 23 verified claims documented
- Hypothesis testing with 5 initial hypotheses

## Sources

See full source list in the [main report](./08_report/bash-formatting-standards.md#11-references).

Primary authoritative sources:
1. [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
2. [shfmt Documentation](https://github.com/mvdan/sh)
3. [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
4. [Greg's Wiki - BashPitfalls](http://mywiki.wooledge.org/BashPitfalls)
