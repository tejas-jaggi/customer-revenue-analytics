# Phase 6 — Cross-Section Executive Insights (Running Tracker)

**Purpose.** The running insight record for Phase 6, maintained after every section so it evolves into the Phase 6 Executive Synthesis. Expanded schema (approved): Resolved / Open / Deferred Findings, plus Cross-Section Relationships, Contradictions, Executive Implications, and Future Modeling Opportunities. This is a tracker, not the synthesis — no cross-section narrative is drawn yet.

---

## Section insights

### Section 6.1 — RFM Segmentation (Adaptive RFM)
**Insight:** An Adaptive RFM framework (empirical quintiles for Recency & Monetary; behavior-defined bands for Frequency, because 63% of purchasers have frequency=1 and the median is 1) segments the 7,711 purchasers into a standard taxonomy. **Champions (15.3% of purchasers) drive 56.1% of net revenue at $849 CLV; Champions+Loyal (27.9%) drive 76.2%.** The At Risk+Lost tail (40% of purchasers) holds only 11% of revenue — the one-time majority, unconverted.

### Section 6.2 — Cohort Analytics
**Insight:** The platform's first longitudinal view. **Monthly purchase retention stabilizes at a durable ~13% floor from month 3** (after the one-time majority churns) — the cohort-level signature of the loyal core seen cross-sectionally in Phase 5/RFM. Two retention definitions were kept strictly separate: the primary monthly-purchase curve (~13% floor) and a secondary 90-day *engagement* measure (~27%, with a mechanical cliff at month 3 when the activity window lapses). Cumulative value ($273 Fully Mature → $43 Immature) and Champions-share gradients are **maturity/recency confounds, explicitly NOT vintage-quality trends** — the only valid cross-vintage comparison is retention at equal age.

### Section 6.3 — Historical Customer Lifetime Value
**Insight:** Historical CLV (observed, not predicted) splits the base into three economically distinct tiers: 289 non-purchasers, **677 zero-net buyers** (purchased then fully refunded — a non-obvious population), and 7,034 positive-CLV customers. Positive CLV is heavily right-skewed (median $102 vs mean $253); descriptive value classes show the **Elite class (7.6% of value-generating customers) holds 41.3% of retained value**. The CLV × RFM bridge puts dollars on scores: Champions average $849 (median $642), $1.0M total = 56.1% of portfolio value. Dual-source validated (snapshot = base-fact = certified $1,782,971.91).

### Section 6.4 — Pareto & Customer Concentration
**Insight:** Portfolio value is moderately-to-highly concentrated, measured three consistent ways. Complete portfolio (8,000): **top 1% = 11.8%, top 10% = 51.0%, top 20% = 70.3%, Gini = 0.6698**; purchaser base (7,711): Gini 0.6574. The **certified Phase 5 F.3 anchor reproduces exactly (top decile = 50.1%)**, proving the Phase 6 CLV vector and Phase 5 revenue measurement describe the same reality. The Lorenz curve is flat across the first decile — the 966 zero-value customers — and the bottom half of the portfolio holds just 7.5% of value. Concentration is framed as a trackable baseline, explicitly NOT as churn risk and with no universal benchmark asserted.

---

## ✅ Resolved Findings
| Finding | Section(s) | Outcome |
|---|---|---|
| Formal customer segmentation exists (was behavioral tiers only in Phase 5) | 6.1 | RFM taxonomy with published names + analytical codes; reconciles to certified Net Revenue |
| Cohort retention / revenue / AOV / value curves | 6.2 | Longitudinal view built; monthly retention stabilizes ~13% from month 3; all measures reconcile to certified anchors |
| Historical CLV distribution + CLV by segment | 6.3 | Three-tier distribution + descriptive value classes; CLV × RFM bridge (Champions $849 avg / 56.1% of portfolio); dual-source reconciled to certified Net Revenue |
| Formal concentration (top 1/5/10/20/50%, Lorenz, Gini) | 6.4 | Gini 0.6698 (complete portfolio) / 0.6574 (purchasers); top 20% = 70.3%; Phase 5 F.3 anchor reproduced exactly at 50.1% |

## ❓ Open Findings
| Finding | Raised | Resolves in | Status |
|---|---|---|---|
| Behavioral profile of RFM segments (cadence, returns, channel) | 6.1 | 6.5 | Open |

## ⏸️ Deferred Findings
| Finding | Deferred to | Reason |
|---|---|---|
| Predictive/projected CLV | Phase 9 (churn) | Requires explicit survival/churn modeling; no forward data — assumptions unsupported now |
| Holiday-plateau cause | Phase 7 | Needs promo/inventory data outside the warehouse |
| High-Return persona *identity* (named generation persona) | — (permanent) | ED-009: personas unstored; a discovered behavioral segment can be named, but never asserted to BE the generation persona |

## 🔗 Cross-Section Relationships
- **6.1 ↔ Phase 5 F:** RFM independently reproduces the Phase 5 concentration finding (17% → 63% became Champions 15.3% → 56.1%) via a different method — method convergence strengthens the core result.
- **6.1 → 6.2/6.3/6.4/6.5:** RFM segment labels (`v_rfm_segments`) are the slicing dimension for cohort value, CLV distribution, concentration-by-segment, and behavioral profiling downstream.
- **6.2 ↔ Phase 5 F / 6.1:** the cohort ~13% monthly-retention floor is the longitudinal manifestation of the same loyal core that Phase 5 (frequency-driven value) and 6.1 (Champions concentration) found cross-sectionally — three methods, one core.
- **6.2 → 6.6:** cohort maturity classification and the equal-age comparison discipline feed the Portfolio Synthesis and any future vintage-quality verdict.
- **6.3 → 6.4:** the per-customer Historical CLV vector (`v_historical_clv`) is the DIRECT input to Pareto/Lorenz/Gini — 6.4 consumes it rather than recomputing value.
- **6.3 ↔ 6.1:** CLV × RFM is the principal scores-to-dollars bridge; it and the maturity discipline from 6.2 are the two main threads feeding 6.6.
- **6.3 → 6.5:** descriptive Historical Value Classes give Behavioral Analytics a value axis — conditional on value class explaining behavioral differences.
- **6.4 ↔ Phase 5 F.3:** cross-phase regression — 6.4 reproduces the certified top-decile 50.1% exactly, demonstrating Phase 6 extends rather than supersedes certified Phase 5 work.
- **6.4 → 6.6:** Gini and the top-N ladder are headline Portfolio Synthesis inputs; concentration is the structural counterpart to 6.3's per-customer value.

## ⚠️ Contradictions
- None to date. (6.1 agrees with Phase 5 F; 6.2 agrees with both.)
- *Confound watch (not a contradiction):* 6.2's cumulative value/composition gradients could be MISREAD as "acquisition quality is declining." They are maturity/recency artifacts and are flagged as such — the retention curve at equal age is the only valid cross-vintage quality signal.

## 💡 Executive Implications
- The retention priority is now a *named, addressable list* (Champions + Loyal = 2,154 customers, 76% of revenue) rather than an abstract "top decile."
- The second-purchase conversion pool is now segment-identified (At Risk + Lost = 3,071 one-time customers) for targeted lifecycle campaigns.
- Retention is durable, not decaying: cohorts hold a stable ~13% monthly repeat-purchase floor after month 3, so the business converts and keeps a steady minority rather than bleeding cohorts to zero — retention investment protects an annuity, not a leaking bucket.
- 677 zero-net buyers (bought then fully refunded) are a distinct, addressable population — demand that converted and then reversed, a returns/satisfaction problem separate from the non-purchaser activation problem.
- Concentration confirms retention priorities target the right population: ~1,600 customers (top 20%) hold ~70% of portfolio value. The Gini is now a monitorable KPI for dependence, distinct from — and not a substitute for — churn risk measurement.

## 🔮 Future Modeling Opportunities
- Predictive CLV and churn probability per RFM segment (Phase 9) — the segments are natural model features/strata.
- RFM-segment migration over time (are Promising customers converting to Loyal?) — a cohort-style transition matrix, candidate for Phase 6.2 or a later extension.


---

## 📦 Repository Evolution
- **Sections completed:** Phase 5 A–G + Phase 6.1 RFM + 6.2 Cohort + 6.3 Historical CLV + 6.4 Pareto & Concentration = 11 analytics modules live.
- **Analytics layer status:** `sql/analytics/01`–`11` implemented; `12`–`13` planned (Behavioral Analytics, Portfolio Synthesis).
- **Repository note:** `09_cohort_analytics.sql` is the canonical cohort module (reconciled from the originally-planned `09_cohort_retention.sql`). `sql/analytics/README.md` index refreshed to current state in 6.4.
- **Validation status:** 65/65 passing across the whole analytics layer, re-runnable via `python/validation/run_analytics_validation.py`.
- **Next planned section:** 6.5 — Customer Behavioral Analytics (observed descriptive features only; must not recreate or infer generation personas per ED-009).
