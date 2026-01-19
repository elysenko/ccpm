# Market Research Domain Overlay

**Load this overlay when research involves market analysis, competitive intelligence, industry trends, consumer behavior, or market sizing.**

---

## Mandatory Citation Elements

For market research, every C1 claim must include:

| Element | Requirement |
|---------|-------------|
| **Report Publisher** | Name of research firm or organization |
| **Publication Date** | When the data was published |
| **Data Collection Period** | When the underlying data was gathered |
| **Sample Size/Methodology** | How data was collected (survey n=X, interviews, etc.) |
| **Geographic Scope** | Markets/regions covered |
| **Market Definition** | How the market segment is defined |

---

## Required Verification Checks

- [ ] Check if market sizing methodology is disclosed
- [ ] Verify sample sizes are adequate for claims made
- [ ] Note any sponsor bias (vendor-funded research)
- [ ] Check for conflicting estimates across sources
- [ ] Identify if projections are based on historical data or assumptions
- [ ] Verify currency and year for all financial figures
- [ ] Check if market definitions are consistent across sources

---

## Source Priority (Market Research)

| Priority | Source Type | Examples |
|----------|-------------|----------|
| **1** | Industry Associations | Trade associations with member data access |
| **2** | Government Statistics | Census Bureau, BLS, Eurostat, national statistics offices |
| **3** | Tier 1 Research Firms | Gartner, IDC, Forrester, McKinsey, BCG |
| **4** | Tier 2 Research Firms | MarketsandMarkets, Grand View, Allied Market Research |
| **5** | Company Filings | 10-K market discussions, investor presentations |
| **6** | Trade Publications | Industry-specific journals and news |
| **7** | News Sources | WSJ, FT, Bloomberg, Reuters |

---

## Quality Grade Modifiers (Market-Specific)

| Modifier | Effect |
|----------|--------|
| Primary research (surveys, interviews) disclosed | +1 grade |
| Large sample size (n > 1000) | +0.5 grade |
| Methodology not disclosed | -1 grade |
| Vendor-sponsored without disclosure | -1 grade |
| Projections beyond 3 years | -0.5 grade |
| Market definition unclear | -0.5 grade |
| Single-source estimate | -0.5 grade |

---

## Special Claim Categories

### Market Size Claims (C1-MARKET)
```
Required: Market definition, size (value/volume), currency, year,
geographic scope, methodology (top-down/bottom-up), source with page number
```

### Growth Rate Claims (C1-GROWTH)
```
Required: CAGR percentage, base year, forecast year,
underlying assumptions, source methodology, confidence interval if available
```

### Market Share Claims (C1-SHARE)
```
Required: Company/product, share percentage, market definition,
measurement basis (revenue/units), time period, source
```

### Competitive Intelligence Claims (C1-COMP)
```
Required: Competitor name, claim type (pricing/features/strategy),
source type (primary/secondary), verification status
```

---

## Market Sizing Standards

### Always Include:
- Base year actual vs. forecast year projected
- Currency (USD, EUR, etc.) with year (e.g., "USD 2024")
- Geographic scope clearly stated
- Market definition (what's included/excluded)
- Methodology (top-down from macro data vs. bottom-up from company data)

### Handle Conflicting Estimates:
1. Present range from multiple sources
2. Explain methodology differences
3. Weight by source quality
4. Note which estimate you use for analysis and why

**Example:**

> "The global AI in healthcare market was valued at $15.1B in 2023 (MarketsandMarkets) to $20.9B (Grand View Research). The variance stems from different market definitions: MarketsandMarkets excludes medical imaging AI while Grand View includes it."

---

## Projection Credibility Framework

| Timeframe | Credibility | Handling |
|-----------|-------------|----------|
| **1-2 years** | High | Can cite with standard confidence |
| **3-5 years** | Medium | Note assumptions, present range |
| **5-10 years** | Low | Present as scenario, not forecast |
| **10+ years** | Speculative | Use only for directional indication |

---

## Citation Format (Market Research)

```
"[Claim text]" [CONFIDENCE: High/Med/Low]
(Publisher, Report Title, Publication Date, p. XX)
Methodology: [Top-down/Bottom-up/Survey n=X]
Data period: [When data was collected]
```

---

## Common Pitfalls to Avoid

1. **TAM vs SAM vs SOM confusion**: Total Addressable ≠ Serviceable ≠ Obtainable
2. **Currency/year mismatch**: Always normalize to same currency-year
3. **Conflating revenue with market size**: Company revenue ≠ market they serve
4. **Ignoring methodology**: Top-down vs bottom-up can give very different numbers
5. **Projection optimism**: Research firms often overestimate growth rates
6. **Sponsor bias**: Vendor-funded research may overstate their market
7. **Definition drift**: Market definitions change between reports
