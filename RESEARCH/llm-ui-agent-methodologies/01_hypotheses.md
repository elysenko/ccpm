---
name: research-hypotheses
created: 2026-01-22T12:00:00Z
updated: 2026-01-22T14:00:00Z
---

# Research Hypotheses

## H1: Constrained Component Libraries Improve Generation Quality

**Prior Probability**: High (70-80%)
**Current Probability**: HIGH (85-90%) - CONFIRMED

**Statement**: UI generation agents that constrain output to a well-defined component library (e.g., shadcn/ui, Material UI) produce more reliable and maintainable code than those generating arbitrary CSS/HTML.

**Evidence Gathered**:
- v0 uses shadcn/ui + Tailwind + React as its core output stack [S2, S3]
- Claude Artifacts uses React + Tailwind + shadcn/ui + Recharts [S27]
- shadcn's AI-first design philosophy: "open code and consistent API allow AI models to read, understand, and generate new components" [S19]
- Custom instructions for LLMs emphasize "always use Shadcn and Tailwind" [S22]
- Component libraries reduce hallucination: "AI can identify the relevant Tailwind classes" vs arbitrary CSS [S19]

**Verdict**: CONFIRMED with high confidence. Multiple production tools and practitioner evidence support this.

---

## H2: Multi-Agent Architectures Outperform Single-Agent for Complex UIs

**Prior Probability**: Medium (50-60%)
**Current Probability**: NUANCED (65-75%) - CONDITIONALLY CONFIRMED

**Statement**: Breaking UI generation into specialized agents (planner, coder, verifier) produces better results than a single end-to-end agent for complex, multi-component interfaces.

**Evidence Gathered**:
- Replit uses multi-agent (manager/editor/verifier) architecture [S4]
- ScreenCoder (ICLR 2026): modular 3-agent system (grounding/planning/generation) achieves SOTA [S7]
- AI4UI: specialized agents for "design interpretation, planning, coding, review, testing" [S8]
- Anthropic multi-agent research: "90.2% improvement over single-agent" on research tasks [S13]
- PwC: "boosted code-generation accuracy from 10% to 70%" with CrewAI [S13]

**But also**:
- "Single-agent approaches suffice for approximately 80% of common use cases" [S14]
- Key distinction: "read vs write" - read tasks parallelize well, write tasks don't [S14]
- Multi-agent: "15x more tokens" than standard interactions [S13]

**Verdict**: CONDITIONALLY CONFIRMED. Multi-agent is superior for complex, parallelizable tasks (especially read-heavy like design analysis). Single-agent remains viable for simpler tasks and write-heavy operations.

---

## H3: Self-Debugging Loops are Essential for Production Quality

**Prior Probability**: High (75-85%)
**Current Probability**: HIGH (90-95%) - STRONGLY CONFIRMED

**Statement**: UI generation agents require iterative self-debugging cycles (generate → execute → observe errors → fix) to achieve production-quality output.

**Evidence Gathered**:
- v0 AutoFix: achieves "error-free generation rates well into the 90s" vs 62% baseline [S2, S3]
- Self-debugging research: "improves baseline accuracy by up to 12%" [S9]
- LEDEX framework: "15.92% higher pass@1" with self-debugging training [S10]
- Multi-agent + debugging: "achieves 92.07% accuracy on HumanEval" [S30]
- LLMs generate faulty code "approximately 10% of the time in isolation" [S3]

**Key Mechanism**: v0's streaming AutoFix "detects and fixes many of these errors in real time as the LLM streams the output" [S3]

**Verdict**: STRONGLY CONFIRMED. Self-debugging is not just beneficial but essential for production-quality output. Multiple academic papers and production systems confirm 10-15%+ improvements.

---

## H4: Visual Input (Screenshots/Designs) Improves Generation vs Text-Only

**Prior Probability**: Medium-High (60-70%)
**Current Probability**: HIGH (75-85%) - CONFIRMED WITH CAVEATS

**Statement**: Multimodal UI generation agents that accept visual input (screenshots, Figma designs) produce more accurate UI code than text-description-only agents.

**Evidence Gathered**:
- Design2Code benchmark: "GPT-4V generated webpages can replace original in 49% of cases" [S5]
- DCGen: 15% improvement in visual similarity with screenshot input [S6]
- Figma MCP: "structured JSON—not screenshots" provides "deterministic context for more accurate code generation" [S18]
- AI4UI: LLM-friendly Figma grammar for "autonomous agent interpretation" [S8]

**Caveats**:
- Raw screenshots have issues: "element omission, distortion, misarrangement" [S6]
- Structured design data (Figma JSON, MCP) outperforms raw screenshots
- Visual input requires preprocessing/segmentation for best results

**Verdict**: CONFIRMED WITH CAVEATS. Visual input improves accuracy, but structured design data (Figma MCP, JSON) outperforms raw screenshots. Preprocessing (segmentation, structured extraction) is key.

---

## H5: Hierarchical/Divide-and-Conquer Approaches Handle Complex UIs Better

**Prior Probability**: High (70-80%)
**Current Probability**: HIGH (85-90%) - CONFIRMED

**Statement**: Breaking complex UIs into hierarchical components (container → sections → individual components) and generating incrementally produces better results than whole-page generation.

**Evidence Gathered**:
- DCGen: "up to 15% improvement in visual similarity" with divide-and-conquer [S6]
- ScreenCoder: "grounding, planning, generation" three-stage modular approach [S7]
- DCGen motivation: "the smaller and more focused the image, the better the resulting code quality" [S6]
- Three failure modes of whole-page generation: element omission, distortion, misarrangement [S6]
- Anthropic best practice: "implement steps sequentially, testing each before moving to the next" [S11]

**Verdict**: CONFIRMED. Hierarchical generation is consistently superior for complex UIs. Multiple academic papers (DCGen, ScreenCoder, AI4UI) and practitioner evidence support this.

---

## Hypothesis Tracking Summary

| ID | Hypothesis | Prior | Current | Status |
|----|------------|-------|---------|--------|
| H1 | Constrained component libraries | 70-80% | 85-90% | CONFIRMED |
| H2 | Multi-agent > single-agent | 50-60% | 65-75% | CONDITIONAL |
| H3 | Self-debugging essential | 75-85% | 90-95% | STRONGLY CONFIRMED |
| H4 | Visual input improves accuracy | 60-70% | 75-85% | CONFIRMED (with caveats) |
| H5 | Hierarchical approaches better | 70-80% | 85-90% | CONFIRMED |
