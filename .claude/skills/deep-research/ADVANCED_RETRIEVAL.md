# Advanced Retrieval Enhancement for /dr

## Overview

This document describes the **Advanced Retrieval** enhancement using ColBERT (via RAGatouille) and HyDE (Hypothetical Document Embeddings). This addresses a key deficit: basic keyword search misses semantically relevant content.

## The Problem

Current /dr retrieval pipeline:
```
WebSearch (keywords) → URLs → WebFetch (full pages) → Extract claims
```

Issues:
1. **Keyword mismatch**: Relevant content uses different terminology than query
2. **Passage selection**: Full pages fetched but relevant passages not precisely identified
3. **Evidence matching**: When verifying claims, matching to source passages is imprecise
4. **No re-ranking**: Search results used in order returned, not by semantic relevance

## The Solution: Two-Layer Retrieval Enhancement

### Layer 1: HyDE for Query Expansion (Phase 3)

Before searching, generate a hypothetical answer and use it to expand queries.

### Layer 2: ColBERT for Evidence Indexing & Retrieval (Phases 3-6)

After fetching content, index it with ColBERT. Use late-interaction retrieval for:
- Passage extraction from fetched pages
- Claim-to-evidence matching
- Contradiction detection
- Synthesis support

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     ENHANCED RETRIEVAL PIPELINE                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PHASE 3: Querying                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │ Subquestion │───▶│    HyDE     │───▶│  Expanded   │         │
│  │             │    │  (Generate  │    │   Queries   │         │
│  │             │    │  hypothetical│    │             │         │
│  │             │    │   answer)   │    │             │         │
│  └─────────────┘    └─────────────┘    └──────┬──────┘         │
│                                               │                 │
│                                               ▼                 │
│                                        ┌─────────────┐         │
│                                        │  WebSearch  │         │
│                                        └──────┬──────┘         │
│                                               │                 │
│                                               ▼                 │
│                                        ┌─────────────┐         │
│                                        │  WebFetch   │         │
│                                        │  (get pages)│         │
│                                        └──────┬──────┘         │
│                                               │                 │
│                                               ▼                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 ColBERT INDEX                            │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
│  │  │ Page 1  │ │ Page 2  │ │ Page 3  │ │  ...    │       │   │
│  │  │passages │ │passages │ │passages │ │         │       │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  PHASES 4-6: Triangulation, Synthesis, QA                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│  │   Claim     │───▶│  ColBERT    │───▶│  Matched    │        │
│  │             │    │  Retrieval  │    │  Passages   │        │
│  └─────────────┘    └─────────────┘    └─────────────┘        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation

### Prerequisites

```bash
pip install ragatouille
```

RAGatouille handles ColBERT model loading, indexing, and retrieval with a simple API.

### Component 1: Evidence Index Manager

Create and manage a ColBERT index for each research project.

```python
# /research_tools/evidence_index.py

from ragatouille import RAGPretrainedModel
from pathlib import Path
import json
import hashlib

class EvidenceIndex:
    """
    Manages a ColBERT index for research evidence.
    One index per research project.
    """

    def __init__(self, project_path: str, model_name: str = "colbert-ir/colbertv2.0"):
        self.project_path = Path(project_path)
        self.index_path = self.project_path / "10_graph" / "colbert_index"
        self.metadata_path = self.project_path / "10_graph" / "index_metadata.json"
        self.RAG = RAGPretrainedModel.from_pretrained(model_name)
        self.documents = []
        self.metadata = {}
        self._load_metadata()

    def _load_metadata(self):
        """Load existing index metadata if available."""
        if self.metadata_path.exists():
            with open(self.metadata_path) as f:
                self.metadata = json.load(f)

    def _save_metadata(self):
        """Save index metadata."""
        self.index_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.metadata_path, 'w') as f:
            json.dump(self.metadata, f, indent=2)

    def _content_hash(self, content: str) -> str:
        """Generate hash for deduplication."""
        return hashlib.md5(content.encode()).hexdigest()[:12]

    def add_document(self,
                     content: str,
                     url: str,
                     title: str = "",
                     source_quality: str = "C",
                     fetch_date: str = "") -> bool:
        """
        Add a fetched document to the index.

        Args:
            content: Full text content of the page
            url: Source URL
            title: Page title
            source_quality: A-E quality rating
            fetch_date: When content was fetched

        Returns:
            True if added, False if duplicate
        """
        content_hash = self._content_hash(content)

        # Skip duplicates
        if content_hash in self.metadata.get("indexed_hashes", []):
            return False

        # Chunk content into passages (simple approach: split by paragraphs, ~500 chars each)
        passages = self._chunk_content(content, url, title, source_quality)

        self.documents.extend(passages)

        # Track metadata
        if "indexed_hashes" not in self.metadata:
            self.metadata["indexed_hashes"] = []
        self.metadata["indexed_hashes"].append(content_hash)

        if "sources" not in self.metadata:
            self.metadata["sources"] = {}
        self.metadata["sources"][content_hash] = {
            "url": url,
            "title": title,
            "quality": source_quality,
            "fetch_date": fetch_date,
            "passage_count": len(passages)
        }

        return True

    def _chunk_content(self,
                       content: str,
                       url: str,
                       title: str,
                       quality: str,
                       chunk_size: int = 500,
                       overlap: int = 50) -> list:
        """
        Split content into overlapping passages for indexing.
        Each passage includes source metadata.
        """
        passages = []

        # Split into paragraphs first
        paragraphs = [p.strip() for p in content.split('\n\n') if p.strip()]

        current_chunk = ""
        for para in paragraphs:
            if len(current_chunk) + len(para) < chunk_size:
                current_chunk += para + "\n\n"
            else:
                if current_chunk:
                    passages.append({
                        "content": current_chunk.strip(),
                        "url": url,
                        "title": title,
                        "quality": quality
                    })
                current_chunk = para + "\n\n"

        # Don't forget the last chunk
        if current_chunk.strip():
            passages.append({
                "content": current_chunk.strip(),
                "url": url,
                "title": title,
                "quality": quality
            })

        return passages

    def build_index(self):
        """
        Build/rebuild the ColBERT index from all added documents.
        Call this after adding all documents for a phase.
        """
        if not self.documents:
            return

        # Extract just the content for indexing
        texts = [doc["content"] for doc in self.documents]
        doc_ids = [f"{doc['url']}::{i}" for i, doc in enumerate(self.documents)]

        # Build index
        self.RAG.index(
            collection=texts,
            document_ids=doc_ids,
            index_name="evidence",
            max_document_length=512,
            split_documents=False  # We already chunked
        )

        self.metadata["index_built"] = True
        self.metadata["document_count"] = len(self.documents)
        self._save_metadata()

    def search(self, query: str, k: int = 5) -> list:
        """
        Search the evidence index.

        Args:
            query: Search query (can be a claim, question, or keywords)
            k: Number of results to return

        Returns:
            List of dicts with content, url, title, quality, score
        """
        if not self.metadata.get("index_built"):
            return []

        results = self.RAG.search(query=query, k=k)

        # Enrich with metadata
        enriched = []
        for r in results:
            doc_id = r.get("document_id", "")
            # Find the matching document
            idx = int(doc_id.split("::")[-1]) if "::" in doc_id else 0
            if idx < len(self.documents):
                doc = self.documents[idx]
                enriched.append({
                    "content": r.get("content", doc["content"]),
                    "url": doc["url"],
                    "title": doc["title"],
                    "quality": doc["quality"],
                    "score": r.get("score", 0)
                })

        return enriched

    def search_for_claim(self, claim: str, min_quality: str = "D") -> list:
        """
        Find evidence passages that support or contradict a claim.
        Filters by minimum source quality.

        Args:
            claim: The claim to verify
            min_quality: Minimum source quality (A, B, C, D, E)

        Returns:
            Relevant passages with metadata
        """
        quality_order = {"A": 5, "B": 4, "C": 3, "D": 2, "E": 1}
        min_score = quality_order.get(min_quality, 1)

        results = self.search(claim, k=10)

        # Filter by quality
        filtered = [
            r for r in results
            if quality_order.get(r["quality"], 0) >= min_score
        ]

        return filtered[:5]  # Return top 5 after filtering
```

### Component 2: HyDE Query Expander

Generate hypothetical answers to improve search queries.

```python
# /research_tools/hyde_expander.py

class HyDEExpander:
    """
    Hypothetical Document Embeddings for query expansion.
    Generates a hypothetical answer before searching.
    """

    HYDE_PROMPT = """You are a research assistant. Given a research question, write a SHORT hypothetical passage (2-3 sentences) that would answer this question if it existed in a high-quality source.

Do NOT search or use real information. Just write what an ideal answer MIGHT look like.

Question: {question}

Hypothetical answer passage:"""

    def __init__(self, llm_client):
        """
        Args:
            llm_client: LLM client with .complete() method
        """
        self.llm = llm_client

    def expand_query(self, question: str) -> dict:
        """
        Generate hypothetical answer and combine with original query.

        Args:
            question: Original research question

        Returns:
            dict with original, hypothetical, and combined queries
        """
        prompt = self.HYDE_PROMPT.format(question=question)
        hypothetical = self.llm.complete(prompt)

        return {
            "original": question,
            "hypothetical": hypothetical.strip(),
            "expanded": f"{question} {hypothetical.strip()}"
        }

    def expand_queries_batch(self, questions: list) -> list:
        """Expand multiple queries."""
        return [self.expand_query(q) for q in questions]
```

### Component 3: Integration Points

#### Phase 3: Enhanced Querying

```python
# Integration into Phase 3 querying workflow

def enhanced_query_workflow(subquestion: str, evidence_index: EvidenceIndex, hyde: HyDEExpander):
    """
    Enhanced querying with HyDE expansion and ColBERT indexing.
    """

    # Step 1: Expand query with HyDE
    expanded = hyde.expand_query(subquestion)

    # Step 2: Search web with both original and expanded queries
    original_results = web_search(expanded["original"])
    expanded_results = web_search(expanded["hypothetical"][:100])  # Use snippet

    # Step 3: Deduplicate and merge results
    all_urls = deduplicate_urls(original_results + expanded_results)

    # Step 4: Fetch content
    for url in all_urls[:10]:  # Limit to top 10
        content = web_fetch(url)
        if content:
            evidence_index.add_document(
                content=content["text"],
                url=url,
                title=content.get("title", ""),
                source_quality=assess_source_quality(url),
                fetch_date=datetime.now().isoformat()
            )

    # Step 5: Build/update index
    evidence_index.build_index()

    # Step 6: Use ColBERT to find best passages for this subquestion
    relevant_passages = evidence_index.search(subquestion, k=10)

    return relevant_passages
```

#### Phase 4: Enhanced Triangulation

```python
def verify_claim_with_colbert(claim: str, claim_type: str, evidence_index: EvidenceIndex):
    """
    Use ColBERT to find supporting/contradicting evidence for a claim.
    """

    # Set minimum quality based on claim type
    min_quality = "B" if claim_type == "C1" else "C"

    # Search for evidence
    evidence = evidence_index.search_for_claim(claim, min_quality=min_quality)

    # Analyze evidence
    supporting = []
    contradicting = []

    for e in evidence:
        # Use LLM to classify relationship
        relationship = classify_evidence_relationship(claim, e["content"])

        if relationship == "supports":
            supporting.append(e)
        elif relationship == "contradicts":
            contradicting.append(e)

    return {
        "claim": claim,
        "supporting_evidence": supporting,
        "contradicting_evidence": contradicting,
        "independence_count": count_independent_sources(supporting),
        "verification_status": determine_verification_status(supporting, contradicting)
    }
```

#### Phase 6: Enhanced QA

```python
def citation_audit_with_colbert(report_claims: list, evidence_index: EvidenceIndex):
    """
    Audit that citations actually support their claims using ColBERT.
    """

    audit_results = []

    for claim in report_claims:
        # Find what the cited source actually says
        cited_evidence = evidence_index.search(
            query=claim["text"],
            k=3
        )

        # Check if citation supports claim
        for evidence in cited_evidence:
            if evidence["url"] == claim["cited_url"]:
                # Found the cited source - verify it supports the claim
                support_score = assess_citation_support(claim["text"], evidence["content"])

                audit_results.append({
                    "claim": claim["text"],
                    "cited_url": claim["cited_url"],
                    "actual_passage": evidence["content"],
                    "support_score": support_score,
                    "status": "PASS" if support_score > 0.7 else "REVIEW"
                })
                break
        else:
            # Cited source not found in index
            audit_results.append({
                "claim": claim["text"],
                "cited_url": claim["cited_url"],
                "status": "SOURCE_NOT_INDEXED"
            })

    return audit_results
```

---

## Modifications to deep-research.md

### Add to Tools Section (line 5)

```yaml
tools: WebSearch, WebFetch, Task, Read, Write, Glob, Grep, TodoWrite, EvidenceIndex
```

### Add New Section: Evidence Index Management

Insert after "Prompt Injection Firewall" in Phase 3:

```markdown
### Evidence Index (ColBERT)

All fetched content is indexed using ColBERT for late-interaction retrieval.

**Indexing Rules:**
1. Index content immediately after successful WebFetch
2. Chunk into ~500 character passages with overlap
3. Store source metadata (URL, title, quality grade, fetch date)
4. Rebuild index after each batch of fetches

**Retrieval Uses:**
- Phase 3: Find best passages from fetched content per subquestion
- Phase 4: Verify claims against indexed evidence
- Phase 5: Support synthesis with precise passage retrieval
- Phase 6: Audit citations against actual source content

**Index Location:** `./RESEARCH/[project_name]/10_graph/colbert_index/`
```

### Add HyDE to Phase 3

Insert after "Rules" in Phase 3:

```markdown
### Query Expansion (HyDE)

Before executing web searches, expand queries using Hypothetical Document Embeddings:

1. For each subquestion, generate a 2-3 sentence hypothetical answer
2. Use both original query AND hypothetical for search
3. Deduplicate results before fetching

**HyDE Prompt:**
```
Given this research question, write a SHORT hypothetical passage (2-3 sentences)
that would answer this question if it existed in a high-quality source.
Do NOT use real information. Just write what an ideal answer MIGHT look like.

Question: [SUBQUESTION]
```

**Why HyDE helps:** Bridges vocabulary gap between how users ask questions and how documents are written. A hypothetical answer uses document-like language.
```

### Add to Folder Structure

```markdown
  10_graph/
     graph_state.json
     graph_trace.md
     colbert_index/          # NEW: ColBERT evidence index
     index_metadata.json     # NEW: Index metadata and source tracking
```

### Update Phase 4 (Triangulation)

Add to the beginning of Phase 4:

```markdown
### Evidence Retrieval for Verification

For each C1 claim requiring verification:
1. Query the ColBERT index with the claim text
2. Filter results by minimum source quality (B+ for C1 claims)
3. Classify retrieved passages as supporting/contradicting/neutral
4. Apply independence rule to supporting evidence
```

### Update Phase 6 (QA)

Add to "Mandatory QA Checks":

```markdown
6. **ColBERT Citation Audit**: For each citation, retrieve the actual passage from the index and verify it supports the claim (not just that the URL was cited)
```

---

## Output Artifacts

### New File: `10_graph/index_metadata.json`

```json
{
  "index_built": true,
  "document_count": 47,
  "indexed_hashes": ["a1b2c3d4e5f6", "..."],
  "sources": {
    "a1b2c3d4e5f6": {
      "url": "https://example.com/article",
      "title": "Example Article",
      "quality": "B",
      "fetch_date": "2026-01-19T14:30:00Z",
      "passage_count": 12
    }
  },
  "retrieval_stats": {
    "total_queries": 156,
    "avg_results_per_query": 4.2,
    "cache_hit_rate": 0.34
  }
}
```

### New File: `09_qa/retrieval_audit.md`

```markdown
# Retrieval Quality Audit

## Index Statistics
- Documents indexed: 47
- Total passages: 382
- Unique sources: 23

## Query Performance
- Queries executed: 156
- Average relevance score: 7.4/10
- Zero-result queries: 3 (2%)

## Citation Verification via ColBERT
| Claim | Cited Source | Retrieved Passage | Support Score | Status |
|-------|--------------|-------------------|---------------|--------|
| [claim text] | [url] | [passage] | 0.85 | PASS |
| [claim text] | [url] | [passage] | 0.42 | REVIEW |

## Recommendations
- [Any sources that should be re-fetched]
- [Claims needing manual verification]
```

---

## Integration Without Python Runtime

If the /dr agent runs in an environment without persistent Python (e.g., pure LLM orchestration), the ColBERT integration can be approximated:

### Option A: External Service

Deploy RAGatouille as a microservice that the agent calls via HTTP:
- `POST /index` - Add document to index
- `POST /search` - Query the index
- `GET /stats` - Index statistics

### Option B: Prompt-Based Approximation

Without actual ColBERT, approximate the benefits through prompting:

1. **Passage Extraction**: After fetching, explicitly ask LLM to extract the 3-5 most relevant passages for each subquestion
2. **Evidence Matching**: When verifying claims, provide full source text and ask LLM to find the specific passage that supports/contradicts
3. **Citation Audit**: For each citation, retrieve source and ask LLM to quote the exact text that supports the claim

This loses the efficiency and precision of ColBERT but captures some benefit.

### Option C: Claude's Native Retrieval

If using Claude with built-in retrieval capabilities:
1. Attach fetched documents as context
2. Use Claude's native ability to search within provided context
3. Request specific passage citations in responses

---

## Cost-Benefit Analysis

### Costs
- **Compute**: ColBERT indexing and inference (moderate GPU/CPU)
- **Storage**: ~10-50MB per research project for index
- **Latency**: ~100-500ms per retrieval query
- **Complexity**: Additional infrastructure component

### Benefits
- **Retrieval Quality**: 20-50% improvement in finding relevant passages (documented in ColBERT papers)
- **Citation Accuracy**: Precise passage retrieval for verification
- **Reduced Hallucination**: Claims tied to specific retrieved text
- **Efficiency**: Don't need to re-read full documents; retrieve specific passages

### Break-Even

Worth implementing if:
- Research tasks regularly involve 10+ sources
- Citation accuracy is critical
- Factual verification is a priority
- Team has capacity to deploy/maintain retrieval service

Not worth implementing if:
- Research tasks are simple (Type A/B)
- Sources are few and short
- No infrastructure for running ColBERT

---

## Rollout Recommendation

### Phase 1: HyDE Only (Low Risk)
- Implement query expansion via prompting
- No infrastructure required
- ~10% improvement in search recall

### Phase 2: Passage Extraction (Medium Risk)
- After fetch, extract key passages via LLM
- Store passages with metadata
- Use for verification

### Phase 3: Full ColBERT (Higher Investment)
- Deploy RAGatouille service
- Full indexing and retrieval
- Citation audit automation

Start with Phase 1, measure improvement, then proceed.
