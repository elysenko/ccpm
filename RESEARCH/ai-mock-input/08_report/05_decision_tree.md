# Decision Tree: When to Auto-Decide vs Defer

## Master Decision Tree

```
                           ┌─────────────────┐
                           │  Prompt Received │
                           └────────┬────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │   Contains security keyword?   │
                    │ (password, key, token, secret) │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │ YES                           │ NO
                    ▼                               ▼
            ┌───────────────┐           ┌───────────────────────┐
            │    DEFER      │           │  Destructive action?  │
            │ Never proceed │           │ (rm, delete, drop)    │
            └───────────────┘           └───────────┬───────────┘
                                                    │
                                    ┌───────────────┴───────────┐
                                    │ YES                       │ NO
                                    ▼                           ▼
                        ┌───────────────────┐       ┌───────────────────────┐
                        │ Reversible?       │       │ Classify prompt type  │
                        │ (git-tracked, etc)│       └───────────┬───────────┘
                        └─────────┬─────────┘                   │
                                  │                             │
                    ┌─────────────┴─────────────┐   ┌──────────┴──────────┐
                    │ YES                       │NO │                      │
                    ▼                           ▼   │                      │
            ┌───────────────────┐   ┌───────────┐   │                      │
            │ AUTO-DECIDE       │   │   DEFER   │   │                      │
            │ default: NO       │   │           │   │                      │
            │ log for rollback  │   └───────────┘   │                      │
            └───────────────────┘                   │                      │
                                                    │                      │
                    ┌───────────────────────────────┘                      │
                    │                                                      │
    ┌───────────────┼───────────────┬───────────────┬──────────────┬──────┴──────┐
    │               │               │               │              │             │
    ▼               ▼               ▼               ▼              ▼             ▼
┌───────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐   ┌──────────┐   ┌─────────┐
│ Binary│     │  Path   │     │ Naming  │     │ Config  │   │ Selection│   │ Unknown │
└───┬───┘     └────┬────┘     └────┬────┘     └────┬────┘   └─────┬────┘   └────┬────┘
    │              │               │               │              │             │
    ▼              ▼               ▼               ▼              ▼             ▼
 See A          See B           See C           See D          See E         See F
```

## Branch A: Binary Decisions (Y/N)

```
                    ┌───────────────┐
                    │ Binary Prompt │
                    └───────┬───────┘
                            │
                            ▼
            ┌───────────────────────────┐
            │ Destructive indicator?    │
            │ (overwrite, delete, erase)│
            └───────────────┬───────────┘
                            │
            ┌───────────────┴───────────┐
            │ YES                       │ NO
            ▼                           ▼
    ┌───────────────────┐       ┌───────────────────┐
    │ File git-tracked? │       │ Non-destructive   │
    └─────────┬─────────┘       │ action detected?  │
              │                 └─────────┬─────────┘
    ┌─────────┴─────────┐                 │
    │ YES               │ NO              │
    ▼                   ▼         ┌───────┴───────┐
┌───────────┐   ┌───────────┐     │ YES           │ NO
│AUTO: YES  │   │AUTO: NO   │     ▼               ▼
│(reversible)│   │(conserve) │ ┌───────────┐ ┌───────────┐
└───────────┘   └───────────┘ │AUTO: YES  │ │AUTO: YES  │
                              │ (safe)    │ │ (default) │
                              └───────────┘ └───────────┘
```

**Rules:**
- "Continue?" → YES
- "Proceed?" → YES
- "Install?" → YES
- "Overwrite?" → NO (unless git-tracked)
- "Delete?" → NO
- "Replace?" → NO (unless git-tracked)

## Branch B: File Path Decisions

```
                    ┌───────────────┐
                    │  Path Prompt  │
                    └───────┬───────┘
                            │
                            ▼
            ┌───────────────────────────┐
            │ Path exists in codebase?  │
            └───────────────┬───────────┘
                            │
            ┌───────────────┴───────────┐
            │ YES                       │ NO
            ▼                           ▼
    ┌───────────────────┐       ┌───────────────────┐
    │ Outside workspace?│       │ Can infer from    │
    └─────────┬─────────┘       │ context/prompt?   │
              │                 └─────────┬─────────┘
    ┌─────────┴─────────┐                 │
    │ YES               │ NO              │
    ▼                   ▼         ┌───────┴───────┐
┌───────────┐   ┌───────────┐     │ YES           │ NO
│   DEFER   │   │ AUTO: Use │     ▼               ▼
│ (unsafe)  │   │ existing  │ ┌───────────┐ ┌───────────┐
└───────────┘   │ path      │ │AUTO: Infer│ │AUTO: Temp │
                └───────────┘ │ context   │ │ directory │
                              └───────────┘ └───────────┘
```

**Inference Rules:**
- "test" in prompt → `tests/` or `__tests__/` directory
- "config" in prompt → `config/` or project root
- "output" in prompt → `output/` or `dist/`
- Unknown → `./tmp/` or OS temp directory

## Branch C: Naming Decisions

```
                    ┌───────────────┐
                    │ Naming Prompt │
                    └───────┬───────┘
                            │
                            ▼
            ┌───────────────────────────┐
            │ Analyze codebase naming   │
            │ convention consensus      │
            └───────────────┬───────────┘
                            │
                            ▼
            ┌───────────────────────────┐
            │   Consensus > 80%?        │
            └───────────────┬───────────┘
                            │
            ┌───────────────┴───────────┐
            │ YES                       │ NO
            ▼                           ▼
    ┌───────────────────┐       ┌───────────────────┐
    │ AUTO: Generate    │       │ Use framework     │
    │ following pattern │       │ default if known? │
    └───────────────────┘       └─────────┬─────────┘
                                          │
                                ┌─────────┴─────────┐
                                │ YES               │ NO
                                ▼                   ▼
                        ┌───────────┐       ┌───────────┐
                        │ AUTO: Use │       │   DEFER   │
                        │ framework │       │ (no conf) │
                        │ default   │       └───────────┘
                        └───────────┘
```

**Convention Patterns:**
- `kebab-case`: React components, CSS classes
- `camelCase`: JavaScript variables, functions
- `PascalCase`: Classes, TypeScript types
- `snake_case`: Python, Ruby, database columns
- `SCREAMING_SNAKE`: Constants

## Branch D: Configuration Values

```
                    ┌───────────────┐
                    │ Config Prompt │
                    └───────┬───────┘
                            │
                            ▼
            ┌───────────────────────────┐
            │ Known config key?         │
            │ (port, timeout, etc)      │
            └───────────────┬───────────┘
                            │
            ┌───────────────┴───────────┐
            │ YES                       │ NO
            ▼                           ▼
    ┌───────────────────┐       ┌───────────────────┐
    │ Has framework     │       │ Has type hint?    │
    │ default?          │       │ (number, boolean) │
    └─────────┬─────────┘       └─────────┬─────────┘
              │                           │
    ┌─────────┴─────────┐       ┌─────────┴─────────┐
    │ YES               │ NO    │ YES               │ NO
    ▼                   ▼       ▼                   ▼
┌───────────┐   ┌───────────┐┌───────────┐  ┌───────────┐
│AUTO: Use  │   │AUTO: Use  ││AUTO: Use  │  │   DEFER   │
│ framework │   │ common    ││ type      │  │(arbitrary)│
│ default   │   │ default   ││ default   │  └───────────┘
└───────────┘   └───────────┘└───────────┘
```

**Common Defaults:**
| Config Key | Default Value |
|------------|---------------|
| port | 3000 |
| timeout | 30 (seconds) |
| retries | 3 |
| workers | CPU count |
| log_level | "info" |
| debug | false |

## Branch E: Selection Decisions

```
                    ┌────────────────┐
                    │Selection Prompt│
                    └───────┬────────┘
                            │
                            ▼
            ┌───────────────────────────┐
            │ Option marked "default"   │
            │ or "recommended"?         │
            └───────────────┬───────────┘
                            │
            ┌───────────────┴───────────┐
            │ YES                       │ NO
            ▼                           ▼
    ┌───────────────────┐       ┌───────────────────┐
    │ AUTO: Select      │       │ Similar choice    │
    │ marked option     │       │ in codebase?      │
    └───────────────────┘       └─────────┬─────────┘
                                          │
                                ┌─────────┴─────────┐
                                │ YES               │ NO
                                ▼                   ▼
                        ┌───────────┐       ┌───────────┐
                        │AUTO: Match│       │ AUTO:     │
                        │ existing  │       │ First     │
                        │ choice    │       │ option    │
                        └───────────┘       └───────────┘
```

**Heuristics:**
- "(default)" label → select that option
- "(recommended)" label → select that option
- Previous similar choice in codebase → match it
- No signal → select first option (most common default)

## Branch F: Unknown/Unclassifiable

```
                    ┌───────────────┐
                    │Unknown Prompt │
                    └───────┬───────┘
                            │
                            ▼
            ┌───────────────────────────┐
            │ Can skip without breaking?│
            └───────────────┬───────────┘
                            │
            ┌───────────────┴───────────┐
            │ YES                       │ NO
            ▼                           ▼
    ┌───────────────────┐       ┌───────────────────┐
    │ AUTO: Skip        │       │ Can abort task?   │
    │ with warning      │       └─────────┬─────────┘
    └───────────────────┘                 │
                                ┌─────────┴─────────┐
                                │ YES               │ NO
                                ▼                   ▼
                        ┌───────────┐       ┌───────────┐
                        │   DEFER   │       │   FAIL    │
                        │ (abort)   │       │ (blocked) │
                        └───────────┘       └───────────┘
```

## Decision Matrix Summary

| Prompt Type | Confidence | Reversible | Auto-Decision | Default |
|-------------|------------|------------|---------------|---------|
| Binary - safe | High | N/A | YES | "y" |
| Binary - destructive | High | Yes | YES | "n" |
| Binary - destructive | High | No | NO | DEFER |
| Path - workspace | Medium | Yes | YES | Infer/temp |
| Path - outside | Low | N/A | NO | DEFER |
| Naming - consensus | High | Yes | YES | Follow pattern |
| Naming - no consensus | Low | N/A | NO | DEFER |
| Config - known | High | Yes | YES | Framework default |
| Config - unknown | Low | N/A | NO | DEFER |
| Selection - marked | High | Yes | YES | Marked option |
| Selection - unmarked | Medium | Yes | YES | First option |
| Free-form | Low | N/A | NO | DEFER |
| Unknown | N/A | N/A | NO | DEFER |

## Confidence Thresholds

| Threshold | Action |
|-----------|--------|
| > 0.9 | Auto-decide, minimal logging |
| 0.7 - 0.9 | Auto-decide, full logging |
| 0.5 - 0.7 | Auto-decide with warning flag |
| < 0.5 | Defer |

## Reversibility Check

```python
def is_reversible(action, context):
    """Check if an action can be undone."""

    # File operations
    if action.type == "file_write":
        return context.file_in_git or context.has_backup

    if action.type == "file_delete":
        return context.file_in_git or context.using_trash

    # Config changes
    if action.type == "config_change":
        return context.previous_value_stored

    # Git operations
    if action.type == "git_commit":
        return True  # Can revert

    if action.type == "git_push":
        return context.branch != "main"  # Harder to undo main

    # Package operations
    if action.type == "package_install":
        return context.lockfile_tracked

    # External operations
    if action.type == "api_call":
        return False  # Cannot undo

    return False  # Default conservative
```
