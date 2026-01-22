# Bash Script Formatting Standards: Code Review Guide

## Executive Summary

This report establishes comprehensive, enforceable standards for bash script formatting and code review. The standards synthesize guidance from the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html), official tool documentation ([shfmt](https://github.com/mvdan/sh), [ShellCheck](https://github.com/koalaman/shellcheck)), and community best practices ([Greg's Wiki](https://mywiki.wooledge.org/)).

**Key Finding**: The combination of **shfmt** (formatting) and **ShellCheck** (linting) represents the current industry-standard toolchain. Using `shfmt -i 2 -ci` produces Google-style formatting, while ShellCheck provides 500+ automated checks for common errors and anti-patterns.

---

## Table of Contents

1. [Tool Configuration](#1-tool-configuration)
2. [Formatting Rules](#2-formatting-rules)
3. [Naming Conventions](#3-naming-conventions)
4. [Quoting Rules](#4-quoting-rules)
5. [Control Structures](#5-control-structures)
6. [Error Handling](#6-error-handling)
7. [Function Standards](#7-function-standards)
8. [Anti-Patterns to Flag](#8-anti-patterns-to-flag)
9. [Code Review Checklist](#9-code-review-checklist)
10. [CI/CD Integration](#10-cicd-integration)
11. [References](#11-references)

---

## 1. Tool Configuration

### 1.1 shfmt Configuration

**Command-line flags for Google-style formatting:**

```bash
shfmt -i 2 -ci -bn -sr
```

| Flag | Description |
|------|-------------|
| `-i 2` | 2-space indentation |
| `-ci` | Indent switch cases |
| `-bn` | Binary operators may start a line |
| `-sr` | Redirect operators followed by space |

**EditorConfig (`.editorconfig`):**

```ini
[*.sh]
indent_style = space
indent_size = 2
shell_variant = bash
binary_next_line = true
switch_case_indent = true
space_redirects = true

[*.bash]
indent_style = space
indent_size = 2
shell_variant = bash
switch_case_indent = true
```

**CI Usage:**
```bash
# Check formatting (returns non-zero on diff)
shfmt -d .

# List files needing formatting
shfmt -l .

# Format in place
shfmt -l -w .
```

### 1.2 ShellCheck Configuration

**Recommended `.shellcheckrc`:**

```bash
# Use bash dialect
shell=bash

# Enable external source analysis
external-sources=true

# Search path for sourced files
source-path=SCRIPTDIR

# Optional stricter checks (enable as appropriate)
enable=quote-safe-variables
enable=require-variable-braces
enable=check-unassigned-uppercase

# Disable specific rules if justified (document why)
# disable=SC2059  # Example: intentional printf format
```

**Command-line usage:**
```bash
# Standard check
shellcheck script.sh

# POSIX compliance check
shellcheck --shell=sh script.sh

# Output format for CI
shellcheck -f gcc script.sh

# Check multiple scripts
shellcheck scripts/*.sh
```

**Critical ShellCheck Codes to Never Ignore:**

| Code | Description | Severity |
|------|-------------|----------|
| SC2086 | Unquoted variable expansion | High |
| SC2046 | Unquoted command substitution | High |
| SC2006 | Backticks instead of $() | Medium |
| SC2164 | cd without || exit | High |
| SC2155 | Declare and assign separately | Medium |
| SC2034 | Unused variable | Low |
| SC1090 | Cannot follow sourced file | Info |

---

## 2. Formatting Rules

### 2.1 Indentation

| Rule | Standard | Tool-Enforced |
|------|----------|---------------|
| Indent size | **2 spaces** | shfmt `-i 2` |
| Tab characters | **Never** (except heredocs with `<<-`) | shfmt |
| Continuation lines | 2-space indent | shfmt |

**Correct:**
```bash
if [[ -n "$var" ]]; then
  echo "value: $var"
fi
```

**Wrong:**
```bash
if [[ -n "$var" ]]; then
    echo "value: $var"  # 4 spaces - wrong
fi
```

### 2.2 Line Length

| Rule | Standard | Tool-Enforced |
|------|----------|---------------|
| Maximum | **80 characters** | Manual review |
| Long strings | Use heredocs or embedded newlines | Manual review |
| URLs/paths | May exceed if necessary | Manual review |

**Breaking long lines:**
```bash
# Long commands: use backslash continuation
curl --silent \
  --header "Content-Type: application/json" \
  --data "$payload" \
  "$api_url"

# Long strings: use heredocs
cat <<EOF
This is a very long message that would exceed
80 characters if written on a single line.
EOF
```

### 2.3 Blank Lines

| Rule | Standard |
|------|----------|
| Between functions | One blank line |
| Between sections | One blank line |
| Consecutive blank lines | Never more than one |
| End of file | Single newline |

### 2.4 Pipelines

**Short pipelines (fits on one line):**
```bash
command1 | command2 | command3
```

**Long pipelines (split at pipe):**
```bash
command1 \
  | command2 \
  | command3 \
  | command4
```

---

## 3. Naming Conventions

### 3.1 Variables

| Type | Convention | Example |
|------|------------|---------|
| Local/script variables | `lowercase_snake_case` | `file_path`, `line_count` |
| Constants | `UPPERCASE_SNAKE_CASE` | `SCRIPT_DIR`, `MAX_RETRIES` |
| Environment variables | `UPPERCASE_SNAKE_CASE` | `PATH`, `HOME`, `EDITOR` |
| Loop variables | Match what they iterate | `for file in "${files[@]}"` |

**Correct:**
```bash
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MAX_RETRIES=3

local file_path="$1"
local line_count=0

for user in "${users[@]}"; do
  echo "$user"
done
```

### 3.2 Functions

| Rule | Convention |
|------|------------|
| Naming style | `lowercase_snake_case` |
| Package prefix | Optional `package::function` |
| Declaration | `function_name() {` (no `function` keyword) |

**Correct:**
```bash
process_file() {
  local -r file="$1"
  # implementation
}

mylib::init() {
  # library initialization
}
```

**Wrong:**
```bash
function processFile {  # function keyword + camelCase
  # implementation
}
```

### 3.3 Files

| Rule | Convention |
|------|------------|
| Naming style | `lowercase_with_underscores` or `lowercase-with-hyphens` |
| Extension | `.sh` for source files; no extension for PATH executables |
| Consistency | Match project convention |

---

## 4. Quoting Rules

### 4.1 General Principle

> "When in doubt, double-quote every expansion."
> -- [Greg's Wiki](https://mywiki.wooledge.org/Quotes)

### 4.2 When to Quote

| Context | Quote? | Example |
|---------|--------|---------|
| Variable expansion | **Yes** | `"$var"`, `"${var}"` |
| Command substitution | **Yes** | `"$(command)"` |
| Strings with spaces | **Yes** | `"hello world"` |
| Literal strings | Single quotes | `'no $expansion'` |
| Arithmetic expressions | No | `$((a + b))` |
| `[[ ]]` pattern matching | Depends | Quote for literal, unquote for pattern |
| Assignment RHS | Optional | `var=$other` works, but `var="$other"` preferred |

### 4.3 Variable Expansion Style

**Preferred:** `"${var}"` with braces
**Acceptable:** `"$var"` when unambiguous

```bash
# Preferred
echo "Processing ${filename} in ${directory}/"

# Acceptable
echo "Value: $var"

# Required (disambiguation)
echo "${var}_suffix"  # Not $var_suffix
```

### 4.4 Array Expansion

**Always use `"${array[@]}"`:**

```bash
# Correct - preserves elements with spaces
for item in "${my_array[@]}"; do
  echo "$item"
done

# Wrong - word splitting breaks elements
for item in ${my_array[@]}; do
  echo "$item"
done

# Correct - passing array to command
my_command "${args[@]}"

# Use "$@" for positional parameters
process_args() {
  for arg in "$@"; do
    echo "$arg"
  done
}
```

### 4.5 Quoting Exceptions

No quotes needed for:
- Literal integers: `count=0`
- Arithmetic contexts: `((i++))`
- `[[ ]]` left side: `[[ $var == pattern ]]`
- Special variables that never contain spaces: `$$`, `$?`, `$#`

---

## 5. Control Structures

### 5.1 Conditionals

**Syntax: `then`/`do` on same line:**

```bash
# Correct
if [[ -f "$file" ]]; then
  process_file "$file"
elif [[ -d "$file" ]]; then
  process_directory "$file"
else
  echo "Unknown type" >&2
fi

# Wrong
if [[ -f "$file" ]]
then  # then on separate line
  process_file "$file"
fi
```

### 5.2 Use `[[ ]]` Over `[ ]`

| Feature | `[[ ]]` | `[ ]` |
|---------|---------|-------|
| Word splitting prevention | Yes | No |
| Glob expansion prevention | Yes | No |
| Pattern matching | `==`/`!=` | No |
| Regex matching | `=~` | No |
| Logical operators | `&&`, `||` | `-a`, `-o` |
| Portability | Bash/Ksh/Zsh | POSIX |

**Correct:**
```bash
if [[ -n "$var" && "$var" != "skip" ]]; then
  echo "Processing"
fi
```

**Avoid (unless POSIX required):**
```bash
if [ -n "$var" ] && [ "$var" != "skip" ]; then
  echo "Processing"
fi
```

### 5.3 Case Statements

```bash
case "${option}" in
  -h|--help)
    show_help
    ;;
  -v|--verbose)
    verbose=true
    ;;
  -*)
    echo "Unknown option: ${option}" >&2
    exit 1
    ;;
  *)
    process_arg "${option}"
    ;;
esac
```

### 5.4 Loops

**For loops:**
```bash
# Iterate over array
for file in "${files[@]}"; do
  process "$file"
done

# C-style (when index needed)
for ((i = 0; i < count; i++)); do
  echo "Item $i: ${items[i]}"
done

# Brace expansion (bash-specific)
for i in {1..10}; do
  echo "$i"
done
```

**While loops:**
```bash
# Reading lines from file
while IFS= read -r line; do
  process_line "$line"
done < "$input_file"

# Reading from command (process substitution)
while IFS= read -r line; do
  process_line "$line"
done < <(some_command)
```

### 5.5 Arithmetic

**Use `(( ))` for arithmetic:**

```bash
# Correct
if ((count > 0)); then
  ((count--))
fi

total=$((a + b))

# Wrong
if [ $count -gt 0 ]; then  # Avoid -gt/-lt
  count=$((count - 1))
fi

# Never use
let count=count+1  # Deprecated
expr $a + $b       # Deprecated
```

---

## 6. Error Handling

### 6.1 Strict Mode

**Recommended script header:**

```bash
#!/bin/bash
set -euo pipefail
```

| Flag | Effect | Caveat |
|------|--------|--------|
| `-e` | Exit on error | Disabled in conditionals |
| `-u` | Error on undefined variable | May need `${var:-}` for optional vars |
| `-o pipefail` | Pipeline fails if any command fails | SIGPIPE handling |

**Alternative with error trap (more debugging info):**

```bash
#!/bin/bash
set -uo pipefail
trap 's=$?; echo "Error on line $LINENO: $BASH_COMMAND"; exit $s' ERR
```

### 6.2 Check Command Success

**Always check critical commands:**

```bash
# Correct
cd "$directory" || exit 1

# Correct (with message)
cd "$directory" || {
  echo "Failed to cd to $directory" >&2
  exit 1
}

# Correct (alternative)
if ! cd "$directory"; then
  echo "Failed to cd to $directory" >&2
  exit 1
fi

# Wrong
cd "$directory"  # May silently fail
rm -rf *          # Dangerous if cd failed!
```

### 6.3 Error Messages to STDERR

```bash
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

# Usage
err "Failed to process file: $file"
```

### 6.4 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Misuse of command |
| 126 | Command not executable |
| 127 | Command not found |
| 128+n | Killed by signal n |

---

## 7. Function Standards

### 7.1 Structure

```bash
# Brief description of what the function does.
# Globals:
#   GLOBAL_VAR - description
# Arguments:
#   $1 - description
#   $2 - description (optional)
# Outputs:
#   Writes to stdout
# Returns:
#   0 on success, non-zero on error
function_name() {
  local -r arg1="$1"
  local arg2="${2:-default}"
  local result

  # Implementation

  echo "$result"
}
```

### 7.2 Local Variables

**Always declare function variables as local:**

```bash
process_data() {
  local -r input="$1"      # Readonly local
  local count=0            # Mutable local
  local line               # Declare before loop

  while IFS= read -r line; do
    ((count++))
  done < "$input"

  echo "$count"
}
```

**Separate declare and assign for command substitution:**

```bash
# Correct - captures exit code
local output
output=$(some_command)
local -r status=$?

# Wrong - exit code is masked
local output=$(some_command)  # SC2155
```

### 7.3 Main Function Pattern

**Scripts with multiple functions should use a main():**

```bash
#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <file>

Options:
  -h, --help    Show this help
  -v, --verbose Enable verbose output
EOF
}

process_file() {
  local -r file="$1"
  # implementation
}

main() {
  local verbose=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -v|--verbose)
        verbose=true
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 1
  fi

  process_file "$1"
}

main "$@"
```

---

## 8. Anti-Patterns to Flag

### 8.1 Critical Anti-Patterns (Always Reject)

| Anti-Pattern | Problem | Correct Alternative |
|--------------|---------|---------------------|
| `for f in $(ls)` | Word splitting, glob expansion | `for f in ./*` |
| `cat file \| grep` | Useless use of cat | `grep pattern file` |
| `cd dir` without `\|\| exit` | Silent failure | `cd dir \|\| exit 1` |
| Unquoted `$var` | Word splitting | `"$var"` |
| Backticks `` `cmd` `` | Hard to nest, read | `$(cmd)` |
| `[ $var = val ]` | Word splitting, empty var | `[[ "$var" = "val" ]]` |
| `eval "$user_input"` | Code injection | Avoid eval entirely |
| `echo "$var"` with user data | Format string injection | `printf '%s\n' "$var"` |

### 8.2 Style Anti-Patterns (Flag for Review)

| Anti-Pattern | Problem | Better Alternative |
|--------------|---------|---------------------|
| `function foo {` | Mixes syntaxes | `foo() {` |
| `$var` without braces | Inconsistent | `${var}` |
| `[ -a ]` / `[ -o ]` | Deprecated | `[[ ]] && [[ ]]` |
| `let` / `expr` | Deprecated | `(( ))` / `$(( ))` |
| `echo -e` / `echo -n` | Non-portable | `printf` |
| `$*` instead of `$@` | Loses argument boundaries | `"$@"` |
| Global variables in functions | Side effects | `local` variables |

### 8.3 Security Anti-Patterns (Always Reject)

| Anti-Pattern | Risk | Mitigation |
|--------------|------|------------|
| Unquoted variables in commands | Command injection | Always quote |
| `eval` with external input | Arbitrary code execution | Avoid eval |
| Parsing `ls` output | Filename injection | Use globs/find -print0 |
| Temporary files in /tmp | Race conditions | Use `mktemp` |
| Storing secrets in variables | Process inspection | Use files with 600 perms |
| SUID/SGID scripts | Privilege escalation | Use sudo |

---

## 9. Code Review Checklist

### 9.1 Automated Checks (Must Pass)

- [ ] **shfmt** reports no formatting differences (`shfmt -d .`)
- [ ] **ShellCheck** reports no errors (`shellcheck -S error *.sh`)
- [ ] **ShellCheck** warnings reviewed and addressed or documented

### 9.2 Manual Review - Structure

- [ ] Script has appropriate shebang (`#!/bin/bash` or `#!/usr/bin/env bash`)
- [ ] Script has file header comment explaining purpose
- [ ] `set -euo pipefail` or equivalent error handling present
- [ ] Functions have documentation comments (for non-trivial functions)
- [ ] Main function pattern used for scripts > 50 lines
- [ ] Functions placed near top of file, after constants

### 9.3 Manual Review - Variables & Quoting

- [ ] All variables double-quoted in command arguments
- [ ] Constants declared with `readonly` at file scope
- [ ] Function variables declared with `local`
- [ ] Variable names follow naming conventions
- [ ] No unquoted `$@` or array expansions

### 9.4 Manual Review - Commands & Control Flow

- [ ] `[[ ]]` used instead of `[ ]` for tests
- [ ] `$(...)` used instead of backticks
- [ ] `(( ))` used for arithmetic
- [ ] Critical commands checked for success (`|| exit`, `|| return`)
- [ ] Error messages written to stderr

### 9.5 Manual Review - Security

- [ ] No `eval` with untrusted input
- [ ] No parsing of `ls` output
- [ ] Temporary files created with `mktemp`
- [ ] No secrets in script variables
- [ ] User input properly validated/sanitized

### 9.6 Manual Review - Portability (if required)

- [ ] Bashisms documented/justified if portability needed
- [ ] GNU-specific options avoided (or documented)
- [ ] Script tested with target shell

---

## 10. CI/CD Integration

### 10.1 GitHub Actions

**`.github/workflows/shell-lint.yml`:**

```yaml
name: Shell Lint

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: './scripts'
        env:
          SHELLCHECK_OPTS: -e SC1091  # Ignore source not found

  shfmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install shfmt
        run: |
          curl -sS https://webinstall.dev/shfmt | bash
          echo "$HOME/.local/bin" >> $GITHUB_PATH

      - name: Check formatting
        run: shfmt -d -i 2 -ci scripts/
```

**Combined action using sh-checker:**

```yaml
name: Shell Check

on: [push, pull_request]

jobs:
  sh-checker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run sh-checker
        uses: luizm/action-sh-checker@master
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SHFMT_OPTS: -i 2 -ci
        with:
          sh_checker_comment: true
```

### 10.2 Pre-commit Hooks

**`.pre-commit-config.yaml`:**

```yaml
repos:
  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.10.0
    hooks:
      - id: shellcheck
        args: ["--severity=warning"]

  - repo: https://github.com/scop/pre-commit-shfmt
    rev: v3.8.0-1
    hooks:
      - id: shfmt
        args: ["-i", "2", "-ci", "-w"]
```

**Install:**
```bash
pip install pre-commit
pre-commit install
```

### 10.3 Local Development

**Makefile target:**

```makefile
.PHONY: lint lint-fix

SHELL_SCRIPTS := $(shell find . -name '*.sh' -type f)

lint:
	shellcheck $(SHELL_SCRIPTS)
	shfmt -d -i 2 -ci $(SHELL_SCRIPTS)

lint-fix:
	shfmt -w -i 2 -ci $(SHELL_SCRIPTS)
```

---

## 11. References

### Primary Sources

1. **Google Shell Style Guide**
   https://google.github.io/styleguide/shellguide.html
   *Authoritative enterprise style guide*

2. **shfmt Documentation**
   https://github.com/mvdan/sh
   https://manpages.debian.org/testing/shfmt/shfmt.1.en.html
   *Official formatter documentation*

3. **ShellCheck Wiki**
   https://github.com/koalaman/shellcheck/wiki
   https://www.shellcheck.net/wiki/
   *Comprehensive linter documentation with 500+ rules*

### Community References

4. **Greg's Wiki - BashPitfalls**
   http://mywiki.wooledge.org/BashPitfalls
   *Definitive list of common bash mistakes*

5. **Greg's Wiki - Quotes**
   https://mywiki.wooledge.org/Quotes
   *Authoritative quoting reference*

6. **Greg's Wiki - BashGuide**
   https://mywiki.wooledge.org/BashGuide
   *Comprehensive bash programming guide*

7. **Unofficial Bash Strict Mode**
   http://redsymbol.net/articles/unofficial-bash-strict-mode/
   *Error handling best practices*

8. **bahamas10/bash-style-guide**
   https://github.com/bahamas10/bash-style-guide
   *Alternative community style guide*

### CI/CD Resources

9. **ShellCheck GitHub Action**
   https://github.com/marketplace/actions/shellcheck

10. **sh-checker Action**
    https://github.com/marketplace/actions/sh-checker

11. **shellcheck-precommit**
    https://github.com/koalaman/shellcheck-precommit

### Official Documentation

12. **GNU Bash Manual**
    https://www.gnu.org/software/bash/manual/

13. **POSIX Shell Specification**
    https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html

---

## Appendix A: Quick Reference Card

### shfmt Google Style
```bash
shfmt -i 2 -ci -bn -sr
```

### ShellCheck Recommended Config
```bash
# .shellcheckrc
shell=bash
external-sources=true
source-path=SCRIPTDIR
enable=quote-safe-variables
enable=require-variable-braces
```

### Script Template
```bash
#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
  local -r arg="${1:?Usage: $0 <argument>}"

  echo "Processing: ${arg}"
}

main "$@"
```

### Common ShellCheck Suppressions (use sparingly)
```bash
# shellcheck disable=SC2059  # Intentional printf format
# shellcheck disable=SC1091  # Source file not found (external)
# shellcheck disable=SC2034  # Variable used in sourced file
```

---

*Report generated: 2026-01-22*
*Research methodology: Deep Research with Graph of Thoughts v3.1*
