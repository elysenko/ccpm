# Research Contract: LLM Prompt Engineering Best Practices

## Core Research Question
What are the best practices and guiding principles for writing effective LLM prompts, especially for Claude models?

## Decision/Use-Case
Enable practitioners to write more effective prompts for Claude and other LLMs, with actionable guidelines and evidence-based recommendations.

## Audience
- **Primary**: Technical practitioners (developers, prompt engineers)
- **Secondary**: AI product managers, technical leads

## Scope

### Included
1. Prompt structure patterns (XML tags, markdown, section organization)
2. Chain-of-thought techniques (step-by-step reasoning, thinking tags)
3. System prompt design (persona, constraints, behavioral guidelines)
4. Few-shot vs zero-shot approaches (when each is appropriate)
5. Constitutional AI principles (harmlessness, helpfulness, honesty)
6. Prompt injection prevention (security patterns)
7. Meta-prompting strategies (prompts that generate prompts)
8. Claude-specific optimizations (extended thinking, model behaviors)

### Excluded
- Fine-tuning approaches (out of scope - prompt-only focus)
- Non-Claude models as primary focus (though comparisons welcome)
- Cost optimization (not primary concern)
- API implementation details (focus on prompt content)

### Geographic/Timeframe
- Global applicability
- Focus on current state (2024-2026)
- Historical context where relevant for evolution

## Constraints
- **Required sources**: Anthropic official documentation
- **Preferred sources**: Academic papers, reputable practitioner guides
- **Avoid**: Outdated pre-2023 guidance, unverified blog posts

## Output Format
Single comprehensive research report (`research-report.md`) containing:
1. Executive summary
2. Key findings for each topic
3. Hypothesis evaluation with updated confidence levels
4. Best practices checklist
5. Claude-specific recommendations
6. Sources cited

## Definition of Done
- [ ] All 8 topics covered with evidence
- [ ] All 5 hypotheses evaluated with updated confidence
- [ ] Minimum 10 high-quality sources cited
- [ ] Actionable best practices provided
- [ ] Claude-specific guidance included

## Research Intensity
- **Tier**: Standard
- **Agents**: 3-5
- **GoT Depth**: Max 3
- **Stop Score**: > 8

## Budget
- N_search = 30
- N_fetch = 30
- N_docs = 12
- N_iter = 6
