# Perspectives for Bash Formatting Research

## P1: Tool Maintainer Perspective
**Focus**: What do shfmt and ShellCheck authors consider best practice?
**Questions**:
- What defaults did they choose and why?
- What options exist for customization?
- What anti-patterns does the tool explicitly flag?

## P2: Enterprise/Google Perspective
**Focus**: What works at scale with many contributors?
**Questions**:
- What rules reduce merge conflicts and improve readability?
- What conventions support automation and CI/CD?
- How do large codebases enforce consistency?

## P3: POSIX Purist Perspective (Adversarial)
**Focus**: Portability and standards compliance
**Questions**:
- Which bashisms should be avoided for portability?
- When is bash-specific syntax justified vs problematic?
- What breaks on different shells/platforms?

## P4: DevOps Practitioner Perspective (Practical)
**Focus**: Real-world scripts in CI/CD, automation, containers
**Questions**:
- What error handling patterns prevent production incidents?
- What makes scripts debuggable?
- What patterns work well in containerized environments?

## P5: Security Reviewer Perspective (Adversarial)
**Focus**: Secure coding patterns
**Questions**:
- What quoting/escaping mistakes lead to injection?
- What file handling patterns are dangerous?
- How should secrets/credentials be handled?

## P6: Code Reviewer Perspective (Practical)
**Focus**: What can be efficiently reviewed?
**Questions**:
- What should be automated vs manual review?
- What are common mistakes to catch?
- How to balance strictness with practicality?

---
Created: 2026-01-22
