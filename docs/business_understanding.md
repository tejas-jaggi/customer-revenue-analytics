# Business Understanding & Planning

## Company Profile

**Solstice Apparel Co.** is a direct-to-consumer apparel and lifestyle brand, launched in 2021 and now operating across three full fiscal years (2023–2025) of transaction history. The brand sells through its own website and mobile app, with a secondary presence on a third-party marketplace. Growth has been driven primarily by paid social and email/SMS lifecycle marketing, and the company is now under pressure to prove that its retention spend is paying off rather than continuing to lean on new customer acquisition.

**Product lines:** Womenswear, Menswear, Outerwear, Footwear, Accessories (5 categories, 100–300 SKUs across them)

**Sales channels:** Owned website (primary), mobile app, marketplace (Amazon)

**Marketing/acquisition channels:** Paid Social, Paid Search, Organic/SEO, Email/SMS, Affiliate/Referral, Direct

**Geography:** United States, sold across all regions, with meaningful concentration in a handful of states

**Known business dynamics to reflect in the synthetic data:**
- Seasonal demand spikes: spring/summer launch (Feb–Mar), summer sale (Jul), back-to-school (Aug), holiday peak (Nov–Dec, including a BFCM surge), January clearance
- Apparel-typical return behavior: return rates vary meaningfully by category, with footwear running highest due to sizing
- Revenue is heavily concentrated in repeat customers, and increasingly so — **corrected in Phase 4, see note below**

> **Narrative correction (Phase 4 warehouse validation, finding 5.5/5.6).** This document originally claimed *"a growing but still minority share of revenue from repeat customers."* Warehouse-wide validation disproved the "minority" half of that claim decisively: repeat customers (2+ orders) are **35.6% of the customer base but generate 82.4% of net revenue**, and the share has risen every year — **61.4% (2023) → 83.5% (2024) → 87.9% (2025)**. The "growing" half of the claim is confirmed; "still minority" was never true, not even in 2023.
>
> Per the Phase 4 ruling, generated data was **not** modified to satisfy the original narrative — the narrative is corrected to match the evidence. The business tension this project exists to surface is therefore *sharper*, not weaker, than first framed: Solstice is not a business that has yet to build a repeat base; it is a business **already dependent** on one, whose acquisition spend is feeding a comparatively small cohort that carries almost all the revenue. That reframes the CFO's question from "is retention spend paying off?" to "what is the concentration risk if this cohort lapses?" — which Phase 6's cohort and CLV work and Phase 8's recommendations should address directly.

## Why This Company, Why This Data Model

This project is the demand-side counterpart to procurement-spend-intelligence. That project answered "how well are we buying and managing suppliers." This one answers "how well are we keeping and growing customers." Same technical backbone (DuckDB, SQL, Python, Power BI), deliberately different business questions, deliberately different analytical toolkit (RFM, cohort retention, CLV, churn) so the two projects read as complementary rather than redundant on a resume.

## Stakeholders

| Stakeholder | Primary Concern | Key Questions They'd Ask |
|---|---|---|
| CFO / VP Finance | Revenue quality, margin, forecasting | Is revenue growth coming from new or repeat customers? What's our realistic CLV? |
| VP Marketing | Acquisition efficiency, channel ROI | Which channels bring in customers who actually stick around? |
| Head of Retention / Lifecycle Marketing | Repeat purchase, churn, loyalty | Who's at risk of churning? Which cohorts retain best? |
| VP Merchandising | Category and product performance | Which categories/products drive revenue vs. drive returns? |
| COO / Operations | Fulfillment, returns, regional performance | Where are we losing revenue to returns? Which regions underperform? |

## Core Business Questions

**Revenue**
- What is the revenue trend by month, quarter, and year, and how much is seasonal vs. underlying growth?
- Which channels and categories drive the largest share of revenue?

**Customer Value**
- Who are the highest-value customers by RFM and CLV?
- What share of revenue comes from the top 20% of customers (Pareto concentration)?

**Retention & Churn**
- What percentage of customers make a second purchase within 90 days of their first?
- How does retention differ across acquisition cohorts and acquisition channels?
- Which active customers show early churn-risk signals (declining recency/frequency)?

**Segmentation**
- How do RFM segments (Champions, Loyal, At Risk, Hibernating, New) differ in spend behavior and category preference?

**Geography & Product**
- Which regions are underperforming relative to their customer base size?
- Which categories/sizes drive disproportionate return volume, and what is the revenue impact?

**Prediction (Phase 10, stretch)**
- Can we flag active customers likely to churn in the next 90 days using a lightweight classification model, and how much lead time does that give the retention team?

## KPI Definitions

All formulas below are the ones the SQL and DAX layers will implement, defined up front so the numbers stay consistent across SQL, Python validation, and the Power BI dashboard.

| KPI | Formula |
|---|---|
| Order Net Revenue | SUM(order line revenue) − discounts. The value of an order **at transaction time**; returns are *not* deducted. This is the basis for AOV. |
| Net Revenue | Order Net Revenue − returns. The basis for revenue reporting, CLV, and Pareto concentration. |
| Average Order Value (AOV) | **Order Net Revenue ÷ Total Orders** — after discounts, **before** returns (the standard retail definition). Returns are reported separately via Return Rate rather than netted into AOV. *Resolved in Phase 4: the original wording ("Net Revenue ÷ Total Orders") was ambiguous and would have yielded $67.80 via one reading and $83.50 via another — **both inside Section 9's $65–85 validation band**, so the contradiction was invisible and would have surfaced later as SQL and Power BI publishing different "AOV" numbers. Validation check 3.2 now enforces a single value.* |
| Repeat Purchase Rate | Customers with ≥2 orders ÷ Total Customers |
| Cohort Retention Rate | Customers active in month N ÷ Customers in that acquisition cohort |
| Churn Rate | Customers with no purchase in trailing 90 days ÷ Active customer base |
| Customer Lifetime Value (historical) | Total net revenue per customer over their full history |
| CLV (projected, Phase 10) | AOV × Purchase Frequency × Avg Customer Lifespan × Gross Margin % |
| RFM Score | Recency, Frequency, Monetary each scored in quintiles (1–5), combined into a segment label |
| Return Rate | Units Returned ÷ Units Sold |
| Revenue Concentration (Pareto) | % of Net Revenue from top 20% of customers by lifetime spend |
| Discount Impact | Revenue lost to discounts ÷ Gross Revenue |

## Success Criteria

The project is done when:
1. The star/constellation schema loads 3 years of synthetic transactional data without integrity failures.
2. Every KPI above has a corresponding, tested SQL query in `sql/analytics.sql`.
3. The Power BI dashboard answers every business question above without requiring the viewer to open a query editor.
4. The README tells the Solstice Apparel Co. story end to end: business context → data model → key findings → recommendations.
5. (Stretch) The churn model produces a scored customer list with a documented precision/recall tradeoff, framed as a decision tool for the retention team, not just a model metric.
