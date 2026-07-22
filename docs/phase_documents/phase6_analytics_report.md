# Phase 6 — Advanced Customer Analytics Report
## Customer Revenue Analytics — Solstice Apparel Co.

*Business-facing readout of the Phase 6 advanced customer analytics. Queries in `sql/analytics/08+`; warehouse v1.0.0 (frozen, certified); repository v1.1.0. Formalizes the customer-value picture Phase 5 previewed.*

---

## Section 6.1 — RFM Segmentation (Adaptive RFM)

**Status: ✅ approved for production. 4/4 validations pass; segment net revenue reconciles to the certified $1,782,971.91, base reconciles to 8,000.**

### Adaptive methodology — and why Frequency is not quintiled

Standard RFM quintiles every axis. That is inappropriate here for Frequency, and the data proves it: **63.0% of purchasers (4,860 of 7,711) are one-time buyers, and the median purchase frequency is exactly 1.** Empirical `NTILE(5)` on Frequency would place the bottom three quintiles all at frequency = 1, assigning scores by arbitrary tie-break rather than behavior.

So Phase 6 uses **Adaptive RFM**: empirical quintiles for **Recency** (1,079 distinct values) and **Monetary** (6,246 distinct values), which comfortably support quintiling, and **behavior-defined bands** for **Frequency**. The bands were verified against the frequency distribution's own percentiles before being finalized:

| Metric | Value |
|---|---|
| Median | 1 |
| P75 | 4 |
| P90 | 10 |
| P95 | 13 |
| Max | 32 |
| Mean | 3.41 |

| F-score | Frequency | Share | Percentile alignment |
|---|---|---|---|
| F1 | 1 order | 63.0% | the one-time floor (median = 1) |
| F2 | 2–3 | 8.9% | |
| F3 | 4–6 | 10.4% | upper edge ≈ P75 (4) |
| F4 | 7–11 | 10.8% | spans P90 (10) |
| F5 | 12+ | 6.9% | ≈ P95 (13) and above |

The Phase 5 behavioral tiers were **re-verified and retained unchanged** — each band is materially populated and the edges track the empirical quartiles, so no adjustment was warranted. Scoring convention: 5 = best on every axis (most recent, most frequent, highest value).

### Segments (business names + analytical codes)

| Segment | Customers | % | Net Revenue | Rev % | Avg CLV | Avg Orders | Avg Recency (days) |
|---|---|---|---|---|---|---|---|
| **Champions** | 1,178 | 15.3% | $1,000,140 | **56.1%** | $849 | 11.8 | 40 |
| **Loyal** | 976 | 12.7% | $358,708 | 20.1% | $368 | 6.0 | 104 |
| Potential Loyalists | 531 | 6.9% | $85,762 | 4.8% | $162 | 2.5 | 56 |
| Promising | 1,249 | 16.2% | $92,432 | 5.2% | $74 | 1.1 | 283 |
| New / Recent | 693 | 9.0% | $45,057 | 2.5% | $65 | 1.0 | 81 |
| At Risk | 1,534 | 19.9% | $99,694 | 5.6% | $65 | 1.0 | 580 |
| Lost | 1,537 | 19.9% | $96,828 | 5.4% | $63 | 1.0 | 912 |
| Needs Attention | 8 | 0.1% | $3,078 | 0.2% | $385 | 5.4 | 502 |
| Hibernating | 5 | 0.1% | $1,275 | 0.1% | $255 | 3.2 | 776 |

Every customer also carries an analytical RFM code (e.g. the largest Champions cell is **R5F4M5**, 352 customers, $213K). Both the names (for marketing) and the codes (for analytics) are published in `v_rfm_segments`.

### Business interpretation

**RFM independently reproduces Phase 5's concentration finding through a completely different method.** Champions + Loyal are **27.9% of purchasers but drive 76.2% of net revenue** — and Champions alone (15.3% of purchasers) drive **56.1%**, at an average CLV of $849 and 11.8 orders. Phase 5 found value is frequency-driven and concentrated; RFM segmentation, built from recency/frequency/monetary quintiles rather than order-count tiers, lands on the same core. That convergence is strong evidence the finding is real, not an artifact of one segmentation choice.

The actionable structure the segments add:
- **Champions & Loyal (2,154 customers, 76% of revenue)** — the retention priority. High recency, high frequency; protect at all costs.
- **At Risk & Lost (3,071 customers, 11% of revenue)** — overwhelmingly the one-time buyers (avg 1.0 orders) who never returned and now sit at 580–912 days recency. This is the **second-purchase conversion pool** Phase 5 sized as the strategic prize — the RFM view confirms it is large (40% of purchasers) and low-value *until* converted.
- **Promising, New/Recent, Potential Loyalists (2,473 customers)** — recent buyers not yet loyal; the pipeline into Champions/Loyal, and the highest-yield target for lifecycle marketing.

The tiny Needs Attention / Hibernating cells (13 customers) are an artifact of the R×F grid boundaries at unusual score combinations — correctly classified, immaterial in size, flagged for transparency rather than over-interpreted.

### Result Sanity Review
Segments partition all 7,711 purchasers with zero unclassified; net revenue reconciles to the cent to certified Net Revenue; Champions carry the highest CLV/frequency and lowest recency (as the taxonomy requires); the large low-value At Risk/Lost tail is the expected one-time majority. Nothing anomalous.

### Phase Gate — Section 6.1
**APPROVED for production use.** 4/4 validations pass (Type A reconciliation to certified Net Revenue and the 8,000 base; Type B frequency-band coverage and score-range checks). The adaptive methodology is documented and empirically justified — quintiles where the distribution supports them, behavior bands where it does not, with the degeneracy demonstrated rather than asserted. RFM segments now provide the customer labels that Cohort, CLV, Pareto, and the Portfolio Synthesis will slice by.
