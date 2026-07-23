# Phase 6 — Advanced Customer Analytics Report
## Customer Revenue Analytics — Solstice Apparel Co.

*Business-facing readout of the Phase 6 advanced customer analytics. Queries in `sql/analytics/08+`; warehouse v1.0.0 (frozen, certified); repository v1.1.0. Formalizes the customer-value picture Phase 5 previewed.*

---

## Executive Summary — Section 6.1 (RFM Segmentation)

- **Adaptive RFM was required, not optional.** A textbook RFM quintiles all three axes; the frequency distribution here makes that impossible — 63% of purchasers bought exactly once and the median frequency is 1 — so frequency uses behavior-defined bands while recency and monetary keep true empirical quintiles.
- **Value is concentrated in a named, addressable core.** Champions and Loyal together are 27.9% of purchasers but 76.2% of net revenue; Champions alone (15.3%) account for 56.1%.
- **The largest customer group is the smallest in value — for now.** The one-time majority (At Risk + Lost, ~40% of purchasers) contributes only 11% of revenue; its worth is as a conversion pipeline, not current revenue.
- **Major implication:** retention strategy can now target a specific roster (protect ~2,150 Champions/Loyal customers; convert ~3,070 one-timers) rather than an abstract "top decile."
- **Confidence is unusually high** because RFM — built from recency/frequency/monetary quintiles — independently reproduces the concentration Phase 5 found through order-frequency tiers. Two methods, one answer.
- **Validation: 4/4 pass**, reconciling to certified Net Revenue ($1,782,971.91) and the full 8,000-customer base; the whole analytics layer stands at 49/49.
- **Downstream:** the RFM segment labels become the slicing dimension for Cohort (6.2), CLV (6.3), Pareto (6.4), and Behavioral Analytics (6.5) — every later section reads these segments rather than re-deriving them.

---

## Section 6.1 — RFM Segmentation (Adaptive RFM)

**Status: ✅ approved for production. 4/4 validations pass; segment net revenue reconciles to the certified $1,782,971.91, base reconciles to 8,000.**

### Why Adaptive RFM is the analytically correct choice

Standard RFM assigns quintile scores (1–5) on all three axes. That works only when each axis has enough distinct, well-spread values for `NTILE(5)` to carve five roughly equal groups. Recency and Monetary satisfy that easily (1,079 and 6,246 distinct values). **Frequency does not, and this is not a minor wrinkle — it is a structural property of a one-purchase-heavy retail business.** With 63% of purchasers at frequency = 1 and a median of 1, forcing quintiles would assign the bottom three "scores" to customers who are *identical* on the metric, separated only by whatever arbitrary tie-break the sort imposes. Those scores would be noise wearing the costume of precision.

Adaptive RFM refuses that. It quintiles the two axes that support quintiling and applies **behavior-defined bands** to frequency, where the bands are anchored to the distribution's own shape rather than to a mechanical fifth-count:

| F-score | Frequency | Share | Percentile anchor |
|---|---|---|---|
| F1 | 1 order | 63.0% | the one-time floor (median = 1) |
| F2 | 2–3 | 8.9% | |
| F3 | 4–6 | 10.4% | upper edge ≈ P75 (4) |
| F4 | 7–11 | 10.8% | spans P90 (10) |
| F5 | 12+ | 6.9% | ≈ P95 (13) and above |

*(Frequency descriptive stats, purchasers: median 1 · P75 4 · P90 10 · P95 13 · max 32 · mean 3.41.)*

These are the Phase 5 behavioral tiers, re-verified against the percentiles and retained because each band is materially populated and its edges track the empirical quartiles. **The superiority is not stylistic — a forced-quintile frequency score would be actively misleading, ranking one-time buyers against each other as if the differences meant something. Adaptive RFM produces scores that mean what they claim to.** Scoring convention throughout: 5 = best (most recent, most frequent, highest value).

### Segments (business names + analytical codes)

| Segment | Customers | % | Net Revenue | Rev % | Avg CLV | Avg Orders | Avg Recency (days) |
|---|---|---|---|---|---|---|---|
| **Champions** | 1,178 | 15.3% | $1,000,140 | 56.1% | $849 | 11.8 | 40 |
| **Loyal** | 976 | 12.7% | $358,708 | 20.1% | $368 | 6.0 | 104 |
| Potential Loyalists | 531 | 6.9% | $85,762 | 4.8% | $162 | 2.5 | 56 |
| Promising | 1,249 | 16.2% | $92,432 | 5.2% | $74 | 1.1 | 283 |
| New / Recent | 693 | 9.0% | $45,057 | 2.5% | $65 | 1.0 | 81 |
| At Risk | 1,534 | 19.9% | $99,694 | 5.6% | $65 | 1.0 | 580 |
| Lost | 1,537 | 19.9% | $96,828 | 5.4% | $63 | 1.0 | 912 |
| Needs Attention | 8 | 0.1% | $3,078 | 0.2% | $385 | 5.4 | 502 |
| Hibernating | 5 | 0.1% | $1,275 | 0.1% | $255 | 3.2 | 776 |

Every customer also carries an analytical RFM code; the largest Champions cell is **R5F4M5** (352 customers, $213K). Both the names (for marketing activation) and the codes (for analytical joins) are published in `v_rfm_segments`.

### Why Champions dominate — the mechanism, not just the number

Champions are not dominant because they spend lavishly per order; their AOV is ordinary. They dominate because they **return again and again** — 11.8 orders each on average, at 40 days since last purchase. Their revenue share is the arithmetic product of ordinary baskets multiplied by extraordinary frequency and recency. This is the same mechanism Phase 5 isolated (value is frequency-driven, not basket-driven), now visible at the segment level: the RFM engine sorts customers primarily by *how often and how recently they buy*, and revenue concentration falls straight out of that sort. It follows that the lever on Champion revenue is **retention and reactivation cadence**, not upsell — a customer nudged from 11 orders to 13 is worth more than one nudged from a $84 to a $95 basket.

### Why one-time buyers are opportunity, not current value

The At Risk and Lost segments look alike on paper — both ~20% of purchasers, both ~$64 CLV, both averaging exactly one order — and both are, today, low-value. The distinction that matters is **recency**: At Risk customers last purchased ~580 days ago, Lost ~912. They are the same economic object viewed at different stages of decay: a customer who bought once and was never converted to a second purchase. Their low revenue is not a verdict on their potential; it is the signature of a *conversion that never happened*. This is precisely the second-purchase opportunity Phase 5 sized as the business's largest strategic prize, and RFM now quantifies its shape: ~3,070 customers sitting one successful re-engagement away from entering the Promising → Loyal → Champions pipeline. Treating them as "low value" and ignoring them would be reading the symptom as the diagnosis.

### Why independent convergence raises confidence

Phase 5 found concentration using **order-frequency tiers and a revenue decile curve**. Phase 6 finds the same concentration using **recency/frequency/monetary quintile scoring and a standard segment taxonomy**. These are genuinely different analytical constructions — different inputs, different grouping logic, different names — and they converge on the same core: a small, high-frequency minority carries the overwhelming majority of value. When two methods that could disagree instead agree, the finding is far more likely to be a property of the *business* than an artifact of a *method*. That is the epistemic value of building RFM after the Phase 5 decile work rather than instead of it — the redundancy is the point.

### Result Sanity Review
Segments partition all 7,711 purchasers with zero unclassified; net revenue reconciles to the cent to certified Net Revenue; Champions carry the highest CLV/frequency and lowest recency (as the taxonomy requires); the large low-value At Risk/Lost tail is the expected one-time majority. The tiny Needs Attention / Hibernating cells (13 customers total) are correctly-classified boundary combinations in the R×F grid — immaterial in size, flagged for transparency rather than over-interpreted.

### Phase Gate — Section 6.1
**APPROVED for production use.** 4/4 validations pass (Type A reconciliation to certified Net Revenue and the 8,000 base; Type B frequency-band coverage, score-range, and segment-partition checks). The adaptive methodology is documented and empirically justified — quintiles where the distribution supports them, behavior bands where it does not, with the degeneracy demonstrated rather than asserted. RFM segments now provide the customer labels that Cohort, CLV, Pareto, and the Portfolio Synthesis will slice by.

---

## Section 6.2 — Cohort Analytics

**Status: ✅ approved for production. 6/6 validations pass; cohort base reconciles to 8,000, revenue to $2,195,871.49, orders to 26,299, customer value to $1,782,971.91.**

Cohort Analytics is the platform's only **longitudinal** lens. Phase 5 and RFM answer *who is valuable now*; cohorts answer *is customer quality improving or decaying across signup vintages*. Per the approved design: **signup cohorts** (all 8,000 customers including the 289 non-purchasers, so age-0 measures activation, not just repeat purchase), and **two separate retention definitions that are never combined**.

### 6.2.1 — Cohort maturity classification

Comparing cohorts is only valid at a **common observable age** — a cohort that signed up in December 2025 has zero months to mature and would look falsely terrible against a 2023 cohort with 35. Every cohort is therefore classified by how much observation window it has to 2025-12:

| Maturity class | Observable months | Cohorts | Customers |
|---|---|---|---|
| Fully Mature | 12–35 | 24 | 5,500 |
| Established | 6–11 | 6 | 1,228 |
| Growing | 3–5 | 3 | 661 |
| Immature | 0–2 | 3 | 611 |

**All retention and value comparisons below are drawn from Fully Mature cohorts** unless stated; Immature/Growing cohorts are reported for completeness but explicitly excluded from cross-cohort quality judgments.

### 6.2.2 — Primary metric: monthly purchase retention

The share of a signup cohort placing an order in each month after signup (Fully Mature cohorts):

| Age (months) | 0 | 1 | 2 | 3 | 6 | 9 | 12 |
|---|---|---|---|---|---|---|---|
| Retention % | 67.3 | 29.8 | 20.7 | 12.6 | 13.4 | 13.3 | 12.6 |

**The curve tells the core lifecycle story.** Age-0 retention is **67.3%** — i.e. two-thirds of signups place an order in their signup month, and the remaining third either activate later or never (the 289 non-purchasers plus slow activators). Purchase activity then falls steeply through the first quarter and **stabilizes at a durable ~13% monthly repeat-purchase floor from month 3 onward.** That floor is the signature of the loyal core Phase 5 and RFM identified: after the one-time majority churns out, a stable ~13% of each cohort keeps buying month after month. The business is not slowly bleeding its cohorts to zero — it converts a steady minority into durable repeat buyers and holds them.

### 6.2.3 — Secondary metric: 90-day activity retention (engagement measure)

**This is an engagement measure, not purchase retention, and is reported separately by design.** It reads the snapshot's rolling-90-day active state at each age:

| Age (months) | 0 | 1 | 2 | 3 | 4 | 6 |
|---|---|---|---|---|---|---|
| Engagement % | 100.0 | 100.0 | 98.6 | 26.5 | 26.5 | 27.3 |

The **cliff at month 3** is the defining feature and precisely illustrates *why the two definitions must not be combined*: engagement sits near 100% for the first two months purely because the 90-day activity window has not yet lapsed since the first purchase — every buyer is mechanically "active." At month 3 the window clears the first order and engagement collapses to its true ~27% level. Read naively as "retention," this would wildly overstate early loyalty. Kept as a labeled *engagement* measure, it correctly says: about 27% of a cohort remains in a rolling-active state at maturity, a slightly broader measure than the ~13% who purchase in any single month (engagement counts a trailing 90-day window, monthly retention a single month).

### 6.2.4 — Cohort revenue, orders, AOV

Revenue and orders concentrate in the Fully Mature cohorts simply because they have had the most time to accumulate. **AOV is uniform across maturity classes (~$83–84)** — consistent with every prior section: order value is not where cohort differences live, frequency and retention are. Revenue and orders reconcile exactly to the certified $2,195,871.49 and 26,299.

### 6.2.5 — Cohort customer value (with the maturity caveat made explicit)

| Maturity class | Value per acquired customer |
|---|---|
| Fully Mature | $273.04 |
| Established | $160.81 |
| Growing | $87.03 |
| Immature | $42.96 |

**This gradient must not be read as declining acquisition quality — it is almost entirely a maturity artifact.** A Fully Mature cohort has had 12–35 months to accumulate value; an Immature cohort has had 0–2. The monotonic decline by maturity class is exactly what accumulation time alone would produce. The honest cross-vintage quality question ("are 2025 customers better than 2023 customers?") can only be answered at *equal age*, which the retention curve (6.2.2) addresses and this cumulative figure deliberately does not. Reported for completeness with the confound flagged, not interpreted as a trend.

### 6.2.6 — Cohort composition snapshot (RFM mix by maturity) — supporting

| Maturity class | Champions % | Lost % |
|---|---|---|
| Fully Mature | 20.5 | 27.9 |
| Established | 4.1 | 0.0 |
| Growing | 0.0 | 0.0 |
| Immature | 0.0 | 0.0 |

Champions concentrate entirely in Fully Mature cohorts, and this is **confounded by construction and must be read with care.** Two mechanical forces produce it, neither of which is pure acquisition quality: (1) reaching the Champions frequency band (7+ orders) *requires time* a young cohort hasn't had; (2) RFM recency is measured as of 2025-12-31, so newer cohorts skew to high-recency "New/Recent" segments and cannot yet appear as Champions or Lost. The composition is therefore descriptive of *lifecycle stage*, not a clean quality ranking of vintages. It is included as supporting integration with the RFM section, explicitly not as a primary finding.

### Result Sanity Review
All measures reconcile to certified anchors; the two retention curves are correctly distinct (primary settles ~13%, engagement drops at the 90-day boundary to ~27%); AOV uniform; the value and composition gradients behave exactly as maturity/recency confounds predict and are flagged as such rather than over-interpreted. Nothing anomalous.

### Phase Gate — Section 6.2
**APPROVED for production use.** 6/6 validations pass (Type A reconciliations to the certified base, revenue, orders, and Net Revenue; Type B retention-base and cohort-mapping recomputations). The section delivered the longitudinal view the platform lacked, kept the two retention definitions rigorously separate (the 90-day engagement cliff shows exactly why that mattered), and — most importantly for analytical integrity — refused to read the maturity-confounded value and composition gradients as quality trends, flagging them instead. Cohort labels and the maturity classification now feed the Portfolio Synthesis (6.6).

---

## Section 6.3 — Historical Customer Lifetime Value

**Status: ✅ approved for production. 5/5 validations pass, including a dual-source reconciliation; Historical CLV reconciles to the certified $1,782,971.91 across all 8,000 customers.**

**Terminology (used precisely throughout).** *Historical Customer Lifetime Value (Historical CLV)* is a **per-customer** quantity — the total observed Net Revenue one customer has generated over their lifetime to date. *Average Customer Value* is a **group aggregate** — the mean Historical CLV across a set of customers. They are different concepts and are not used interchangeably. And *historical* is literal: this section measures value that **has been** generated. It contains no prediction, no survival model, no projection — predictive CLV is deferred to the future predictive-modeling phase (Phase 9), where survival probability is actually modeled.

### 6.3.1 — Measurement and dual-source validation

Historical CLV(customer) = lifetime Order Net Revenue − lifetime returns, on the Net Revenue basis. The measure was computed two independent ways and both agree to the cent: the **base-fact computation** (orders − returns from `Fact_Orders`/`Fact_Returns`) and the **snapshot's cumulative net revenue** both total **$1,782,971.91**. Two independent derivations of the same quantity agreeing is stronger evidence than a single anchor match — the Type B dual-source check is the section's most rigorous validation. A useful structural property also holds: **no customer has negative Historical CLV** — returns never exceed purchases at the customer level.

### 6.3.2 — Three-tier distribution

The customer base does not split cleanly into "buyers and non-buyers." It has **three economically distinct populations**, and reporting them separately prevents the $0 mass from hiding inside an average:

| Tier | Customers | % of base | Total Historical CLV | Business meaning |
|---|---|---|---|---|
| Non-purchaser | 289 | 3.6% | $0 | Acquired but never activated — no order ever placed |
| Zero-net buyer | 677 | 8.5% | $0 | Purchased, then **fully refunded** — real transactions, zero retained value |
| Positive Historical CLV | 7,034 | 87.9% | $1,782,971.91 | Retained economic value |

The **zero-net buyers are the non-obvious population**: 677 customers (8.5% of the base) *did* transact but returned everything, netting to exactly zero. They are invisible in a naive purchaser/non-purchaser split, yet they are operationally distinct from non-purchasers — they represent demand that converted to a sale and then reversed, a different problem (fit, satisfaction, returns) than a signup that never activated. Surfacing them is the honest version of the distribution.

### 6.3.3 — Value distribution and descriptive Historical Value Classes

Among the 7,034 positive-CLV customers, the distribution is **heavily right-skewed**, so the **median ($101.69) leads and the mean ($253.48) is context only** — with a P90 of $637 and a max of $3,949, the mean is pulled well above the typical customer and would mislead if used as "the average customer's value."

Four **descriptive** Historical Value Classes, empirically grounded on the distribution (breaks near P50/P75/~P92):

| Class | Customers | % of positive | Avg Historical CLV | Share of positive CLV |
|---|---|---|---|---|
| Low (<$100) | 3,475 | 49.4% | $49.97 | 9.7% |
| Moderate ($100–300) | 1,851 | 26.3% | $173.95 | 18.1% |
| High ($300–750) | 1,170 | 16.6% | $470.40 | 30.9% |
| Elite ($750+) | 538 | 7.6% | $1,369.84 | 41.3% |

The shape is the by-now-familiar concentration seen from a new angle: **the Elite class is 7.6% of value-generating customers but holds 41.3% of retained value**, while the Low class is nearly half of them but under 10%. *These classes are descriptive summaries of observed history only — they carry no predictive meaning and imply nothing about a customer's future value.* They exist to give later sections (Behavioral Analytics, Portfolio Synthesis) a compact value vocabulary; whether they earn their place there depends on whether value class explains behavioral differences, which 6.5 will test. **Concentration statistics — top-N%, Lorenz, Gini — are deliberately excluded here and reserved for Section 6.4.**

### 6.3.4 — Historical CLV × RFM segment (the principal bridge)

This is the view that translates RFM *scores* into *dollars* — the connective tissue between 6.1, 6.3, and the eventual 6.6 synthesis:

| RFM Segment | Customers | Avg Historical CLV | Median Historical CLV | Total Historical CLV | Portfolio CLV Share |
|---|---|---|---|---|---|
| Champions | 1,178 | $849.01 | $642.26 | $1,000,140 | 56.1% |
| Loyal | 976 | $367.53 | $309.34 | $358,708 | 20.1% |
| At Risk | 1,534 | $64.99 | $47.98 | $99,694 | 5.6% |
| Lost | 1,537 | $63.00 | $45.90 | $96,828 | 5.4% |
| Promising | 1,249 | $74.00 | $54.67 | $92,432 | 5.2% |
| Potential Loyalists | 531 | $161.51 | $138.41 | $85,762 | 4.8% |
| New / Recent | 693 | $65.02 | $48.66 | $45,057 | 2.5% |

Publishing **both average and median customer value per segment** matters because of the skew: within Champions the average ($849) sits well above the median ($642), confirming that even the top segment has a long right tail of exceptional customers pulling the group average up. Reading the *median* Champion ($642) as the typical Champion, and the *total* ($1.0M, 56.1% of the portfolio) as the segment's strategic weight, gives an executive two correctly-distinguished numbers rather than one ambiguous "value." At Risk and Lost — the one-time majority — sit near $64 average, $46 median: the second-purchase opportunity in dollars.

### Result Sanity Review
Both CLV sources reconcile to the certified total; the three tiers partition all 8,000; value classes cover all positive-CLV customers; every segment's median is below its mean (confirming right skew throughout); Champions carry the highest average, median, and total. Nothing anomalous.

### Cohort × CLV — intentionally excluded
A Historical-CLV-by-cohort view is deliberately **not** produced here. Section 6.2 established that cumulative cohort measures rise monotonically with cohort age as a pure accumulation artifact (a 2023 cohort has had 35 months to accumulate value, a 2025 cohort barely any). Plotting Historical CLV by cohort would reproduce that maturity confound and invite it to be misread as a vintage-quality trend. The valid cross-vintage comparison is retention at equal age (6.2.2), not cumulative value — so this section holds to the portfolio and segment views, where the maturity confound does not apply.

### Phase Gate — Section 6.3
**APPROVED for production use.** 5/5 validations pass (Type A reconciliation to certified Net Revenue and the CLV×RFM total; Type B dual-source reconciliation, three-tier partition, and value-class coverage). The section measured historical value strictly as an outcome, kept *Historical CLV* and *Average Customer Value* rigorously distinct, surfaced the non-obvious zero-net-buyer population, and produced the CLV×RFM bridge that carries into the Portfolio Synthesis. The per-customer Historical CLV vector (`v_historical_clv`) is the direct input to Section 6.4's concentration analysis.

---

## Section 6.4 — Pareto & Customer Concentration

**Status: ✅ approved for production. 5/5 validations pass, including a cross-phase regression that reproduces the certified Phase 5 F.3 finding exactly (50.1%).**

### Executive Concentration Summary

- **Gini coefficient: 0.670** (complete portfolio, 8,000 customers) — a moderate-to-high degree of value concentration.
- **Top 20% of customers hold 70.3% of portfolio value**; the top 10% hold 51.0% and the top 1% hold 11.8%.
- **Overall interpretation:** value is meaningfully concentrated in a minority of customers, which is a *structural characteristic* of this portfolio rather than a defect. Moderate-to-high customer-value concentration is commonly observed across many customer portfolios, particularly in retail, where a small share of repeat buyers typically accounts for a disproportionate share of spend. A concentration figure of this magnitude is not, on its own, evidence of business distress, and it should not be read as one.
- **Concentration is not churn risk — the two are different things.** Concentration describes *how value is distributed today* across the customer base. Churn risk describes *the probability that customers stop buying*. A highly concentrated portfolio of deeply loyal, actively purchasing customers carries very different exposure from an equally concentrated portfolio whose top customers are lapsing. This section measures the former only; nothing here estimates any customer's likelihood of leaving, and no such inference should be drawn from these figures. (Section 6.2's retention evidence — a durable ~13% monthly repeat floor — and any future churn modeling are where that question belongs.)
- **Business implication:** the concentration confirms that the retention priorities already identified are aimed at the correct population. Because roughly 1,600 customers (the top 20%) account for about 70% of portfolio value, retention investment directed at that group protects the majority of the revenue base; conversely, dependence on that group should be *monitored* — the Gini is now a trackable KPI for exactly that purpose.

### What this section adds (and deliberately does not repeat)

Section 6.3 asked **"what is each customer worth?"** — a measurement question producing a per-customer value. Section 6.4 asks **"how concentrated is portfolio value?"** — a structural question about the portfolio as a system. The distinction is maintained throughout: 6.4 consumes 6.3's Historical CLV directly (`v_historical_clv`) and never recomputes customer value. The new capability introduced here is **inequality measurement** — the Lorenz curve and Gini coefficient — which has no per-customer analogue and which no prior section provides.

Deliberately excluded: HHI and CR4/CR8 (industrial-organization metrics built for markets with a handful of firms; at 8,000 customers they produce near-zero, uninterpretable values), the Palma ratio, and a standalone decile table (that would duplicate Phase 5 F.3 — decile points appear here only as Lorenz coordinates).

### Analytical basis — declared

Every figure states its population. **Primary base: the complete customer portfolio (8,000).** Concentration risk is a question about the whole portfolio, and customers who were acquired but generated no value are a real part of it; excluding them would flatter the numbers. **Reconciliation base: the certified Phase 5 purchaser population (7,711)**, published so earlier certified findings remain directly comparable.

### 6.4.2 — Top-N concentration ladder

| Analytical basis | Top 1% | Top 5% | Top 10% | Top 20% | Top 50% |
|---|---|---|---|---|---|
| **Primary — complete portfolio (8,000)** | 11.8% | 35.0% | 51.0% | **70.3%** | 92.5% |
| Reconciliation — purchaser base (7,711) | 11.4% | 34.2% | 50.0% | 69.2% | 91.8% |

The two bases differ by roughly one percentage point at each rung — the gap is the effect of the 289 non-purchasers and 677 zero-net buyers, who add customers to the denominator without adding value. **Publishing both prevents an apparent contradiction:** the same "top decile" concept legitimately reads 51.0% on the complete portfolio and 50.0–50.1% on the purchaser base, and a single unlabeled figure would look like a discrepancy against Phase 5.

### 6.4.3 — Cross-phase reconciliation to Phase 5 F.3

Phase 5 F.3 certified that **the top decile of the 7,711 purchasers held 50.1% of net revenue.** Reproducing that exact construction on the Historical CLV vector returns **50.1%** — an exact match, validated as a Type A cross-phase regression. This is the section's most important integrity check: it proves the Phase 6 CLV vector and the Phase 5 revenue measurement describe the same underlying reality, and that 6.4 extends rather than supersedes certified work.

*(Methodological footnote: the ladder's "top 10%" on the purchaser base reads 50.0% while the decile construction reads 50.1%. The difference is boundary handling — a percentage threshold admits 771 customers where `NTILE(10)` assigns 772. Both are correct for their construction; the F.3 anchor is matched by reproducing F.3's construction.)*

### 6.4.4 — Lorenz curve

Cumulative share of portfolio value by cumulative share of customers (ascending by value):

| Customers (cumulative) | 10% | 20% | 30% | 40% | 50% | 60% | 70% | 80% | 90% | 100% |
|---|---|---|---|---|---|---|---|---|---|---|
| Value (cumulative) | 0.00% | 0.75% | 2.28% | 4.43% | 7.50% | 11.92% | 18.63% | 29.69% | 49.03% | 100% |

The curve is **flat across the first decile** — the bottom 10% of the portfolio holds exactly 0% of value, which is the 966 zero-value customers (289 never activated, 677 fully refunded) appearing as a genuine feature of the portfolio rather than a computational artifact. It then rises slowly and steepens sharply in the final deciles: **the bottom half of customers accounts for 7.5% of value, while the top decile alone accounts for the remaining 51%.**

### 6.4.5 — Gini coefficient

| Analytical basis | Gini |
|---|---|
| **Primary — complete portfolio (8,000)** | **0.6698** |
| Reconciliation — purchaser base (7,711) | 0.6574 |

The primary-base figure is higher precisely because it includes the zero-value customers, which legitimately increase measured inequality. **Interpreting the number responsibly:** the Gini is a *descriptive statistic about distribution shape*, not a performance score, a risk rating, or a distress signal. Moderate-to-high concentration of this kind is commonly observed in customer portfolios, and a figure near 0.67 is best used as a **baseline to track over time** — a rising Gini would indicate growing dependence on fewer customers, a falling one a broadening base. Its value to management is as a monitorable trend, not as a pass/fail threshold, and no universal benchmark is asserted here.

### Result Sanity Review
The ladder is monotonically non-decreasing and bounded; the Lorenz curve terminates at exactly 100%; both Gini figures fall inside [0,1] with the complete-portfolio value correctly exceeding the purchaser-base value; and the Phase 5 F.3 anchor reproduces exactly. The three metrics agree with one another — the ladder, curve, and coefficient describe the same distribution from three angles. Nothing anomalous.

### Phase Gate — Section 6.4
**APPROVED for production use.** 5/5 validations pass (Type A total-value and base reconciliation plus the Phase 5 F.3 cross-phase regression; Type B ladder monotonicity, Lorenz endpoint, and Gini bounds). The section introduced genuine new capability — portfolio-level inequality measurement — while consuming rather than recomputing Historical CLV, declared its analytical basis at every figure, preserved comparability with certified Phase 5 findings, and kept concentration rigorously distinct from churn risk. The Gini and top-N ladder are headline inputs to the Portfolio Synthesis (6.6).
