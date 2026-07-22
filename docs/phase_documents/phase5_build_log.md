# Phase 5 — Build Log
## Customer Revenue Analytics — Solstice Apparel Co.

Phase 5 builds the SQL analytics layer on the frozen, certified v1.0.0 warehouse. Where Phases 1–4 built and certified the warehouse, Phase 5 asks it business questions. This log records methodology and per-section build evidence; the business-facing answers live in `docs/phase5_analytics_report.md`.

---

## Finalized Phase 5 Methodology

Every analytical deliverable follows a fixed 13-step sequence: Business Question → Metric Definition → Metric Basis → Analysis Grain → SQL Design → Analytical Assumptions → Independent Review → SQL → Validation → Result Sanity Review → Business Interpretation → Documentation → Phase Gate.

### Permanent analytical rules

- **P5-1 — Certified KPI Regression Anchors.** The seven Phase 4 certified KPIs (Order Net Revenue $2,195,871.49; Net Revenue $1,782,971.91; Gross Margin 63.27%; AOV $83.50; Discount Impact 6.86%; Return Rate 16.64%; Repeat Purchase Rate 35.64%) are permanent regression anchors. Any query reproducing one must match it to the agreed precision (cent for money, 0.01pp for rates). A discrepancy is a defect in the analytical SQL until proven otherwise — the warehouse is frozen and correct.
- **P5-2 — One validation per query.** *Type A (Regression):* matches a certified anchor. *Type B (Independent Recomputation):* a different SQL path verifying a result that has no anchor. Every query carries exactly one.
- **P5-3 — Mandatory Basis + Grain declaration.** No query is reviewable without an explicit Metric Basis and Analysis Grain. This is the additivity firewall against the 1.291× Orders→Lines fan-out (Phase 4 check 6.8): header measures from Fact_Orders, product measures from Fact_Order_Lines, returns from Fact_Returns, customer-state from the snapshot — never summed across a grain-crossing join.

### Reviewed framework decisions (independently reviewed, not assumed)

1. **Order Net Revenue** for revenue-trend/channel/category/campaign — endorsed (returns aren't attributable to campaign/channel in the schema; standard retail basis).
2. **Net Revenue** for CLV/Pareto/customer-value — endorsed (a customer's value must be net of returns, or High-Return Customers are overstated).
3. **Underperforming geography = Revenue per Customer indexed to national mean** — endorsed, with an added **low-base guardrail**: report customer count alongside and flag small-base regions rather than calling statistical noise "underperformance."
4. **90-Day Repeat Rate kept separate** from the certified lifetime Repeat Purchase Rate — endorsed strongly; conflating a 90-day-window metric with a lifetime ≥2-orders metric would be an analytical error. The 90-day metric lives in Section F and is Type B validated.

### Repository structure

Analytics SQL is split by section under `sql/analytics/` (e.g. `01_executive_kpi_summary.sql`), mirroring the established `sql/{generation,validation,verification}/` convention rather than a single monolithic `analytics.sql` — the same modularity discipline used everywhere else in the repo, chosen for navigability and reviewability of a multi-hundred-line analytics layer. `docs/phase5_analytics_report.md` holds business-facing answers; this file holds build evidence.

### Standard query documentation template

Each query is preceded by a header block: Business Question · Stakeholder · Metric Definition · Metric Basis · Analysis Grain · SQL Design · Analytical Assumptions · Independent Review · Validation · Result Sanity · Interpretation pointer.

---

## Section A — Executive KPI Summary

**Status: complete, executed, all regressions pass. Phase Gate: APPROVED (baseline established).**

### Deliverable
`sql/analytics/01_executive_kpi_summary.sql` — 8 queries: A.1–A.7 (one per certified KPI) plus A.8 (consolidated single-row executive panel).

### Execution result (against frozen v1.0.0 warehouse)

| Query | KPI | Value | Anchor | Result |
|---|---|---|---|---|
| A.1 | Order Net Revenue | $2,195,871.49 | $2,195,871.49 | ✅ PASS |
| A.2 | Net Revenue | $1,782,971.91 | $1,782,971.91 | ✅ PASS |
| A.3 | Gross Margin % | 63.27% | 63.27% | ✅ PASS |
| A.4 | AOV | $83.50 | $83.50 | ✅ PASS |
| A.5 | Discount Impact % | 6.86% | 6.86% | ✅ PASS |
| A.6 | Return Rate % | 16.64% | 16.64% | ✅ PASS |
| A.7 | Repeat Purchase Rate | 35.64% | 35.64% | ✅ PASS |
| A.8 | Consolidated panel | all of the above + 26,299 orders / 8,000 customers | — | ✅ (composed of anchored columns) |

**7/7 Type A regressions pass.** Section A is the certified analytical baseline for Phase 5.

### Notes
- **Two context KPIs added** (Total Orders, Total Customers) to A.8 only, as rate denominators; justified in the analytics report; Type B (exact counts), no anchor claimed.
- **Additivity discipline verified per query:** A.3 correctly computes margin on Fact_Order_Lines (the only grain carrying unit_cost); A.1/A.4/A.5 stay on the header; A.6 divides two independent unit scalars; none crosses the fan-out.
- **No new Engineering Decision.** Section A composes existing structure and introduces no reusable engineering pattern. Business-definition choices are documented here and in the analytics report, not the ED log — consistent with the Phase 3.7/3.11/3.12 boundary.

---

## Section B — Revenue Analysis

**Status: complete, executed, all validations pass. Phase Gate: APPROVED.**

### Deliverable
`sql/analytics/02_revenue_analysis.sql` — B.1 (trend: year/quarter/month), B.2 (seasonality-adjusted YoY: annual/quarter/month), B.3 (channel), B.4 (category + yearly trend), B.5 (category concentration), B.6 (YoY variance decomposition: channel + category), B.7 (four-path reconciliation capstone).

### Independent design review (before implementation)
Three adjustments to the proposed scope, each justified:
- **B.2 rebuilt around same-period-prior-year YoY** (Dec-vs-Dec) rather than sequential MoM, because the brief requires separating seasonality from growth and naive sequential growth conflates them. This is what let the section find that the growth deceleration is holiday-specific.
- **B.6 given a concrete method** — YoY contribution decomposition whose member deltas sum to the total change — rather than an impressionistic "which dimension looks up."
- **B.5 bounded to category-level concentration**, with customer Pareto explicitly deferred to Phase 6 (stated in the SQL) so it can't be mistaken for premature segmentation.
Considered and rejected: channel×category cross-revenue (Section C concern) and campaign revenue trend (Section E), as adding them would violate "no query merely because it's interesting."

### Execution result (8 validation queries, against frozen v1.0.0)

| Validation | Type | Result |
|---|---|---|
| B.1 yearly roll-up = $2,195,871.49 | A | ✅ PASS |
| B.3 channel roll-up = $2,195,871.49 | A | ✅ PASS |
| B.4 category roll-up (line grain) = $2,195,871.49 | A | ✅ PASS |
| B.6 channel decomposition = $296,115.98 delta | B | ✅ PASS |
| B.6 category decomposition = $296,115.98 delta | B | ✅ PASS |
| B.7 four independent paths all = $2,195,871.49 | A | ✅ PASS (4 paths) |

**8/8 pass.** Every revenue roll-up in the section reconciles to the certified Order Net Revenue, and both YoY decompositions reconcile to the identical total change.

### Additivity discipline (P5-3) verified per query
- Channel revenue (B.3) and channel decomposition (B.6a): **header grain** (Fact_Orders), `sales_channel_key` is a header FK.
- Category revenue (B.4) and category decomposition (B.6b): **line grain** (Fact_Order_Lines), `net_line_revenue` — the only correct category basis; reconciles to the header total (Phase 4 check 2.1), never a header-measure fan-out.
- B.7 capstone deliberately mixes grains across four paths to prove grain-independence — the strongest additivity proof available.

### Key analytical finding
Seasonality-adjusted growth reveals the ~138%→38% annual deceleration is **concentrated in the holiday peak** (December same-month YoY collapsed 129%→8.8%) while off-peak demand still grew ~33% (July). Underlying business healthy; holiday engine plateaued.

### No new Engineering Decision
Section B composes existing structure; business-definition choices documented here and in the analytics report, not the ED log.

---

## Section C — Product Performance Analysis

**Status: complete, executed, all validations pass. Phase Gate: APPROVED.**

### Deliverable
`sql/analytics/03_product_performance.sql` — C.1 (category profitability), C.2 (top/bottom products by profit), C.3 (return performance, product lens), C.4 (revenue vs margin vs returns + returns-adjusted profit), C.5 (premium/volume classification), C.6 (portfolio quadrants).

### Independent design review (before implementation)
- **Redesigned away from revenue reporting.** Section B already covered category revenue/growth/concentration; Section C is rebuilt around profitability, return exposure, and portfolio positioning. No revenue-trend duplication.
- **Added a returns-adjusted contribution view (C.4)** rather than reporting margin and returns side by side. A category's true economic value is margin net of return exposure; combining them is the analytically honest version of "which create value," and it is what re-ranks Footwear to last.
- **Held the Section G boundary** — returns evaluated only for product-profitability; reason codes, controllable split, restocking, and timing explicitly deferred (stated in SQL).

### Execution result (6 validation queries, against frozen v1.0.0)

| Validation | Type | Result |
|---|---|---|
| C.1 blended margin = 63.27% & gross profit = $1,389,245.69 | A | ✅ PASS |
| C.2 every product's profit sums to $1,389,245.69 | B | ✅ PASS |
| C.3 returned units = 6,088 & revenue returned = $412,899.58 | A | ✅ PASS |
| C.4 recomputed revenue = $2,195,871.49 & profit = $1,389,245.69 | B | ✅ PASS |
| C.5 units = 36,594 & revenue = $2,195,871.49 | B | ✅ PASS |
| C.6 revenue = $2,195,871.49 | B | ✅ PASS |

**6/6 pass.** Margin reconciles to Section A; revenue reconciles to Section B; returns reconcile to certified warehouse totals — exactly the cross-section reconciliation the brief required.

### Additivity discipline (P5-3)
All profitability computed at **line grain** (Fact_Order_Lines, where unit_cost lives); return exposure joined at **category level** from independent sold/returned aggregates, never a row-level orders↔returns fan-out.

### Key analytical finding
Revenue rank ≠ value rank. **Accessories** is #2 revenue but #1 profit / #1 returns-adjusted profit (70.5% margin, 8.6% returns, all top-5 profit SKUs) → investment candidate. **Footwear** is #3 revenue but last in returns-adjusted profit (54.2% margin + 27.8% returns compounding) → operational review. One flagged edge case: Menswear's PREMIUM classification is knife-edge ($60.45 vs $60.01 threshold), reported as a caveat not a clean signal.

### No new Engineering Decision
Composes existing structure; the returns-adjusted-profit approximation (only margin lost on restockable returns) is a documented analytical assumption, not an engineering pattern.

---

## Section D — Geographic Performance Analysis

**Status: complete, executed, all validations pass. Phase Gate: APPROVED.**

### Deliverable
`sql/analytics/04_geographic_performance.sql` — D.1 (regional revenue), D.2 (RPC index: region + city with low-base guardrail), D.3 (customer quality by region), D.4 (geographic growth + acquisition), D.5 (portfolio quadrants). D.6/D.7 are interpretation in the analytics report.

### Independent design review (before implementation)
- **Two-grain design.** Region (4) is the primary lens — statistically solid; city (46) only for the D.2 index under the low-base guardrail. A 46-city RPC scatter as the primary lens would be noise-dominated; deliberately avoided.
- **Held boundaries:** acquisition-channel-by-geography → Section E; returns-by-geography → Section G. Identified in D.7, not answered.

### Execution result (5 validation queries, against frozen v1.0.0)

| Validation | Type | Result |
|---|---|---|
| D.1 regional revenue = $2,195,871.49 | A | ✅ PASS |
| D.2 national RPC = $274.48 | B | ✅ PASS |
| D.3 regional repeat customers = 2,851 (35.64%) | A | ✅ PASS |
| D.4 regional yearly revenue = national yearly (329,574/785,091/1,081,207) | B | ✅ PASS |
| D.5 revenue = $2,195,871.49 | B | ✅ PASS |

**5/5 pass — after fixing one real bug.**

### Bug caught by validation (methodology working as designed)
The D.3 validation query initially referenced `SUM(repeat_customers)` against a subquery that aliased its columns as `(region, customer_key)` — it **executed-then-failed with a binder error**, not a silent wrong answer, but it is the clearest Section-D example of P5-2's purpose: the analytical D.3 query was correct, but its validation was malformed. Diagnosed (the subquery is one row per region-customer pair, so `COUNT(*)` is the repeat-customer total, not `SUM` of a non-existent column) and corrected. Re-ran: 5/5. Not worked around, not weakened.

### Additivity discipline (P5-3)
Revenue at **header grain** (Fact_Orders, geography_key is a header FK); customer base from **Dim_Customer** (home_geography_key, includes non-purchasers as the correct RPC denominator); repeat counts partition the national total with no cross-region double-counting (one home region per customer).

### Key analytical finding
Geography is a **weak** performance differentiator (regional RPC index spans only 94–106). South = volume (biggest revenue, avg value); West = best-balanced (high revenue + high value); Northeast = quality niche (smallest, highest value); Midwest = review candidate (trails both, modestly). The low-base guardrail materially changed the city ranking (reliable-city index range 73–128 vs 87–135 with noise). Redirects strategic attention to product/customer dimensions where spreads are wider.

### No new Engineering Decision
Composes existing structure; two-grain analysis and the low-base guardrail are analytical assumptions, documented here and in the report.

---

## Section E — Marketing Performance & Acquisition Quality

**Status: complete, executed, all validations pass. Phase Gate: APPROVED.**

### Deliverable
`sql/analytics/05_marketing_performance.sql` — E.1 (channel volume), E.2 (customer quality by channel), E.3 (campaign performance), E.4 (marketing efficiency: value-vs-volume gap), E.5 (inherited-question investigation: region mix, category affinity, holiday plateau), E.6 (portfolio quadrants). E.7 interpretation in report.

### Independent design review (before implementation)
- **Surfaced two attribution limitations up front:** L1 acquisition channel is a lifetime customer attribute (not touch-attribution) — a strength for the quality lens; L2 campaign attribution is thin and gross-only (returns carry no campaign_key). Also flagged **no spend data exists**, so ROI/CAC is uncomputable — efficiency means value density.
- **Redesigned E.5 to test-before-answering.** The holiday-plateau question was investigated and then **explicitly declined**: a lifetime attribute cannot explain a per-period timing phenomenon. Declining a forced conclusion is the correct analytical outcome.

### Execution result (6 validation queries, against frozen v1.0.0)

| Validation | Type | Result |
|---|---|---|
| E.1 channel revenue = $2,195,871.49 & customers = 8,000 | A | ✅ PASS |
| E.2 channel repeat customers = 2,851 | A | ✅ PASS |
| E.3 campaign-attributed revenue reconciles two ways | B | ✅ PASS |
| E.4 revenue & customer shares each sum to 100 | B | ✅ PASS |
| E.5 category-by-channel revenue = $2,195,871.49 | B | ✅ PASS |
| E.6 customers = 8,000 | B | ✅ PASS |

**6/6 pass.**

### Additivity discipline (P5-3)
Acquisition revenue at **header grain** (Fact_Orders, acquisition_channel_key denormalized, Phase 4 check 1.1 confirmed coherent). The single category-by-channel query (E.5b) correctly uses **line grain** (net_line_revenue via Fact_Order_Lines.customer_key → acquisition channel) and reconciles to the certified total.

### Key analytical findings
1. **Paid channels bring the highest-value customers** — the "paid = volume, owned = loyalty" assumption is *false* for Solstice. Paid Social leads on both volume (2,519) and value ($294/customer); Email/SMS and Organic/SEO are lowest-value.
2. **Channel does not explain the West's edge** — acquisition mix is near-uniform across regions (Paid Social 30–34% everywhere). Carries to Section F.
3. **Channel does not predict category affinity** — every channel sends ~30–32% to Accessories, ~13–15% to Footwear. Category preference lives at customer/persona level. Carries to Section F.
4. **Holiday-plateau question declined** — lifetime attribute cannot answer a timing question; not forced.
5. **Affiliate/Referral highest repeat rate (38.2%)** on a small base — a quality signal beneath the revenue ranking.

### Honesty notes
- Value-density is explicitly distinguished from cost-efficiency (no CAC data).
- Campaign figures are gross-of-returns (L2), stated wherever campaign revenue appears.

### No new Engineering Decision
Composes existing structure; attribution limitations are data-model facts documented here and in the report, not engineering decisions.

---

## Section F — Customer Value & Retention Analysis

**Status: complete, executed, all validations pass. Phase Gate: APPROVED.**

### Deliverable
`sql/analytics/06_customer_value_retention.sql` — F.1 (portfolio overview), F.2 (behavioral value segments), F.3 (decile concentration), F.4 (repeat vs new decomposition), F.5 (behavior + 90-Day Repeat Rate), F.6 (cross-section investigation). F.7 interpretation in report.

### Independent design review (before implementation) — a real methodological constraint
**Personas are not stored** (ED-009, design #5): computed at generation, never persisted, verified absent from every table. So F.2/F.3/F.6-as-written (GROUP BY persona) are **impossible** against the frozen warehouse. Three options weighed:
1. Re-derive personas in SQL — **rejected** (not reproducible in pure SQL; would defeat ED-009's purpose and make Phase 6 circular).
2. Skip persona analysis — **rejected** (the executive questions are answerable without it).
3. **Behavioral value segments from observed data — adopted.** Frequency × lifetime-value tiers answer "who creates value" using what customers did, and preview (not pre-empt) Phase 6 RFM.
Persona-dependent inherited questions (F.6d) are **explicitly declined**, not faked — same discipline as Section E's holiday-plateau decline.

### Execution result (6 validation queries, against frozen v1.0.0)

| Validation | Type | Result |
|---|---|---|
| F.1 base=8,000, revenue=$2,195,871.49, repeat=2,851 | A | ✅ PASS |
| F.2 tier net revenue=$1,782,971.91 & customers=8,000 | B | ✅ PASS |
| F.3 decile net revenue=$1,782,971.91 | B | ✅ PASS |
| F.4 repeat share=82.4% & count=2,851 | A | ✅ PASS |
| F.5 90-day rate bounded below lifetime buyer-repeat (37.0%) | B | ✅ PASS |
| F.6 top decile ~10% of 7,711 purchasers | B | ✅ PASS |

**6/6 pass.**

### Additivity discipline (P5-3)
Customer-grain throughout; CLV nets each customer's own returns as a scalar subquery (never row-multiplied); F.6c category mix correctly at line grain. Two bases used deliberately: Net Revenue for CLV/value, Order Net Revenue for the 82.4% reconciliation and AOV.

### Key analytical findings
1. **Value is a FREQUENCY phenomenon.** Repeat customers = 7.52 orders vs 1.0 (7.5×), AOV nearly identical ($84 vs $80). The 82.4% is driven by return visits, not bigger baskets → retention > upsell.
2. **17% of customers (Loyal 7+) drive 63% of net revenue**; **the top decile alone drives 50.1%.** The concentration is even sharper than the headline 82.4%.
3. **90-Day Repeat Rate = 24.3%** (new metric, distinct from and correctly below the certified 35.64% lifetime / 37.0% buyer-repeat).
4. **Composition does NOT explain the West** (high-value customers uniform across regions: 8.8–10.5%) — closes that thread negatively across D+E+F.
5. **High-value customers do NOT over-index on Accessories** (29.8% vs 31.6%) — value is not category-driven.
6. **Paid Social's edge IS partly composition** (11.4% high-value share vs Email/SMS 6.6%) — the one affirmative composition answer.
7. **Affiliate persona-driver DECLINED** — persona unstored.

### No new Engineering Decision
Composes existing structure. The behavioral-segment substitution for unstored personas is an analytical assumption (documented here and in the report), not an engineering pattern; it deliberately does not re-derive or persist personas.

---

## Section G — Returns & Value Leakage Analysis

**Status: complete, executed, all validations pass. Phase Gate: APPROVED. Final analytical section of Phase 5.**

### Deliverable
`sql/analytics/07_returns_value_leakage.sql` — G.1 (portfolio overview), G.2 (reason drivers + controllability), G.3 (product returns: rate vs dollar exposure vs Wrong Size mix), G.4 (customer return behavior: by tier, high-return cluster, top-decile survival), G.5 (geographic returns), G.6 (marketing returns), G.7 (value leakage ranking). G.7 interpretation in report.

### Independent design review (before implementation)
- **Reframed to "Returns & Value Leakage."** A pure returns report would duplicate Section C's category rates. The section earns its place via (1) reason/controllability decomposition and (2) the customer-level returns-adjusted value link to Section F, culminating in G.7 — a single ranked leakage table across returns, discounts, and unconverted customers.
- **Held the persona boundary** — the High-Return cluster is detected behaviorally (G.4b) but not labeled the unstored generation persona (ED-009).

### Execution result (7 validation queries, against frozen v1.0.0)

| Validation | Type | Result |
|---|---|---|
| G.1 returns=5,687, units=6,088, refunded=$412,899.58 | A | ✅ PASS |
| G.2 reason revenue = $412,899.58 | A | ✅ PASS |
| G.3 category returns = $412,899.58 (ties to Section C) | A | ✅ PASS |
| G.4 return-rate bands cover 7,711 purchasers | B | ✅ PASS |
| G.5 regional returned units = 6,088 | B | ✅ PASS |
| G.6 channel returned units = 6,088 | B | ✅ PASS |
| G.7 realized leaks = certified returns ($412,899.58) + discount ($161,827.55) | A | ✅ PASS |

**7/7 pass.**

### Additivity discipline (P5-3)
Return-grain aggregates (Fact_Returns) for reasons; category/region/channel returns via independent sold-vs-returned aggregates joined on the dimension attribute, never a row-level orders↔returns fan-out; customer-level returns netted as scalar subqueries.

### Key analytical findings
1. **74.5% of returned value ($307.7K) is controllable** — Wrong Size alone is 40.6% of the total leak. The biggest leak is the most fixable.
2. **G.3 dual answer:** Footwear's 27.8% rate is a *sizing* problem (54.8% Wrong Size); Womenswear is the larger *financial* risk ($171K exposure, 2× Footwear) despite a lower rate.
3. **Loyalty is not a return risk** — Loyal (7+) return at 17.1% = one-timers; top-decile customers lose only 15.0% of value to returns vs 22.3% for the rest, so high value survives returns intact (concentration is even sharper returns-adjusted).
4. **High-return behavioral cluster** — 785 customers (10.2%) return 60%+; consistent with the ~7% designed persona but reported as behavior (persona unstored).
5. **Returns don't disturb D or E** — regional (16.4–17.2%) and channel (15.6–17.4%) return rates flat; Paid Social's value edge survives returns intact.
6. **G.7 leakage ranking:** controllable returns $307.7K (53.5%) > discounts $161.8K (28.2%) > non-controllable returns $105.2K (18.3%); the modeled one-time retention opportunity (~$2.7M) dwarfs all realized leaks ~4×. Fix returns operationally; win retention strategically.

### No new Engineering Decision
Composes existing structure. The G.7 realized-vs-opportunity leakage framing is an analytical construction (documented, opportunity cost kept in a separate class to avoid double-counting), not an engineering pattern.

---

## Phase 5 Analytical Sections A–G — COMPLETE

All seven analytical sections are implemented, executed against the frozen v1.0.0 warehouse, validated, and gate-approved. Total Phase 5 validations across A–G: **A 7/7 · B 8/8 · C 6/6 · D 5/5 · E 6/6 · F 6/6 · G 7/7 = 45/45 pass.** One real bug was caught and fixed by validation (Section D.3). The Cross-Section Executive Insights tracker holds the full record (Resolved/Open/Deferred); the Phase 5 Executive Synthesis can be assembled from it on request.

## Phase 5 Finalization — Publication-Readiness Pass

**Status: complete. Clears the two structural gaps from the final architecture review; no analytical changes to Sections A–G.**

This pass added engineering/documentation to bring the repository to publication-ready state before the Executive Synthesis. Sections A–G were **not** modified — the architecture review certified them analytically clean (45/45), and this pass is reproducibility and navigation only.

### 1. Phase 5 validation runner
`python/validation/run_phase5_validation.py` — executes every validation query across the seven section files and prints a concise pass summary. Mirrors Phase 4's `run_warehouse_validation.py` philosophy: a re-runnable health check, not a one-off. Read-only; explicit exceptions (ED-003); a query that errors surfaces loudly rather than silently passing. Executed result:

```
45/45 validations passed
Phase 5 analytics layer reconciles to the certified warehouse. ✓
```

This closes the one near-mandatory gap from the review: the analytics layer's credibility rests on "every number reconciles," and there is now a one-command way to re-verify it rather than trusting the build log.

### 2. Roadmap corrected
`docs/project_roadmap.md` rewritten to reflect reality: Phase 5 marked complete (was "Next"); removed the stale `dashboard/` folder, monolithic `analytics.sql`, and "Power BI Dashboard (6–8 pages)" deliverable references (the Power-BI-removed note is retained as a deliberate scope decision); Phase 6 is now "Next"; the real `sql/analytics/` modular structure and per-section deliverables are listed. This was flagged in the Phase 4 audit and had persisted; now resolved.

### 3. Analytics navigation — chose `sql/analytics/README.md` over a thin `analytics.sql`
**Reasoning:** a concatenated `analytics.sql` index can only list file paths; a README maps each section file to the **business question** it answers and the **stakeholder** who asked it, so a reviewer navigates by intent. It also fits the repository's existing per-directory convention and doesn't introduce a monolithic file that would drift from the section files. The section files stay the single source of truth; the README only points into them.

### 4. Executive Findings Matrix
`docs/phase5_executive_findings_matrix.md` — 10 consolidated findings across A–G, each with supporting section(s), evidence strength (High/Medium/Low), business implication, and recommended executive action. This is the primary structured input to the Executive Synthesis. Evidence strength deliberately separates directly-measured findings (High) from the modeled $2.7M retention opportunity (Low) — the matrix carries the "modeled/directional" caveat forward so the synthesis cannot accidentally present a counterfactual as measured fact.

### No new Engineering Decision
The runner composes the established validation-runner pattern (ED-003 exceptions, read-only live DB); no reusable new pattern emerged.

### Phase 5 status after finalization
Sections A–G complete and validated (45/45, re-runnable). Roadmap, navigation, and findings matrix in place. **Ready for Executive Synthesis** — the one remaining Phase 5 deliverable, to be produced on request.
