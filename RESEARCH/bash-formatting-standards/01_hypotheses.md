# Research Hypotheses

## H1: Google Shell Style Guide Dominance
**Prior Probability**: High (75%)
**Final Probability**: 85%
**Verdict**: CONFIRMED
**Hypothesis**: The Google Shell Style Guide is the de facto standard that most other guides and tools align with.
**Evidence**:
- shfmt explicitly documents `-i 2 -ci` as producing Google-style formatting
- Multiple community guides reference Google as authoritative source
- Enterprise adoption widespread (Chromium, Google Cloud)
- Alternative guides (bahamas10) differ on minor points (tabs vs spaces) but agree on core principles

## H2: shfmt + ShellCheck Combination
**Prior Probability**: High (80%)
**Final Probability**: 95%
**Verdict**: STRONGLY CONFIRMED
**Hypothesis**: The combination of shfmt (formatting) and ShellCheck (linting) represents the current industry standard toolchain.
**Evidence**:
- GitHub Actions exist for both (shellcheck action, sh-checker combines both)
- Pre-commit hooks officially maintained for both
- All major guides recommend one or both tools
- No competing tools with comparable adoption found

## H3: 2-Space Indentation Consensus
**Prior Probability**: Medium (60%)
**Final Probability**: 70%
**Verdict**: PARTIALLY CONFIRMED
**Hypothesis**: 2-space indentation is the consensus standard (Google uses it, shfmt defaults may vary).
**Evidence**:
- Google explicitly requires 2 spaces
- shfmt defaults to tabs (0), but `-i 2` is commonly recommended
- bahamas10 guide prefers tabs
- Community split but Google influence tips consensus toward 2 spaces
- Note: shfmt EditorConfig integration allows project-level customization

## H4: Strict Quoting Rules
**Prior Probability**: High (85%)
**Final Probability**: 95%
**Verdict**: STRONGLY CONFIRMED
**Hypothesis**: Variable quoting (double quotes) is universally recommended, with specific exceptions.
**Evidence**:
- ShellCheck SC2086 is the most frequently triggered warning
- Greg's Wiki quotes rule: "When in doubt, double-quote every expansion"
- Google requires quoting for variables, command substitutions, spaces, metacharacters
- All sources agree on exceptions: integers, arithmetic, [[ ]] left side

## H5: Error Handling Patterns Standardized
**Prior Probability**: Medium (55%)
**Final Probability**: 75%
**Verdict**: CONFIRMED (with nuance)
**Hypothesis**: `set -euo pipefail` or similar strict mode is the recommended default for production scripts.
**Evidence**:
- "Unofficial bash strict mode" is widely cited
- Google recommends checking return values, error messages to stderr
- bahamas10 guide explicitly advises against `set -e` due to subtle issues
- Nuance: strict mode is recommended but with awareness of caveats (conditionals, pipefail with SIGPIPE)
- Error traps (`trap ... ERR`) provide better debugging info

---
Created: 2026-01-22
Updated: 2026-01-22 (outcomes added)
