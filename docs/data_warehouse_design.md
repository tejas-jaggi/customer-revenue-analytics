# Data Warehouse Design — Customer Revenue Analytics
## Solstice Apparel

This document is the conceptual warehouse design. No schema.sql yet — the goal here is to get the architecture right so implementation is close to mechanical once we agree on it.

**Pattern:** Fact Constellation (multiple fact tables sharing conformed dimensions), not a single star. A single star schema can't cleanly support order-line-grain, return-grain, and time-series-grain analysis at once without either over-loading one fact table or losing analytical flexibility. A constellation is what an actual enterprise customer analytics warehouse looks like — this is also the concrete architectural difference from procurement's schema, not just a relabeling of tables.

---

## 1. Fact Tables

### Fact_Orders
**Purpose:** Order-level revenue and channel/campaign attribution. This is the fact that answers "how much did we sell, through which channel, tied to which campaign."

**Grain:** One row per order (order header).

**Measures:** gross_revenue, discount_amount, net_revenue, shipping_revenue, order_count (always 1, useful for additive counting), is_first_order (flag)

**Foreign Keys:** customer_key, order_date_key, sales_channel_key, geography_key (ship-to region), campaign_key (nullable — not every order is tied to a named campaign), acquisition_channel_key (denormalized from the customer's original acquisition channel, kept here too so channel-level revenue attribution doesn't require a join back through Dim_Customer every time)

**Degenerate dimension:** order_id (natural order number, kept directly in the fact — doesn't warrant its own dimension table since it has no descriptive attributes beyond what's already modeled)

---

### Fact_Order_Lines
**Purpose:** Product-level detail within each order. This is where product performance, category mix, and basket-level analysis live.

**Grain:** One row per product per order (order detail).

**Measures:** quantity, unit_price, gross_line_revenue, discount_amount, net_line_revenue, unit_cost (enables margin calculation later)

**Foreign Keys:** order_id (degenerate, ties back to Fact_Orders), customer_key, product_key, order_date_key

**Relationship to Fact_Orders:** Fact_Orders is the header; Fact_Order_Lines is the detail. Sum of net_line_revenue for a given order_id should reconcile to Fact_Orders.net_revenue — this reconciliation check becomes one of the Phase 4 data quality validations.

---

### Fact_Returns
**Purpose:** Return and reverse-logistics analysis — which products, categories, and customers drive returns, and what that costs in revenue.

**Grain:** One row per returned line item.

**Measures:** return_quantity, return_amount, restocking_fee (optional, can be 0)

**Foreign Keys:** order_id (degenerate, ties back to the original order), customer_key, product_key, return_date_key, return_reason_key

**Why separate from Fact_Order_Lines rather than an is_returned flag on the line:** returns happen on a different date than the purchase, sometimes only partially (2 of 3 units), and need their own reason coding. Bolting that onto the order line fact would force nulls and mixed grain into one table — a return-specific fact keeps both facts clean and additive.

---

### Fact_Customer_Monthly_Snapshot
**Purpose:** This is the table that makes Phase 6 (RFM, cohort retention, CLV) and Phase 10 (churn model) tractable without re-deriving customer state from raw transactions every single query. It's a periodic snapshot fact — one row per customer per calendar month, capturing that customer's state at that point in time.

**Grain:** One row per customer per month.

**Measures:** orders_this_month, net_revenue_this_month, cumulative_orders_to_date, cumulative_net_revenue_to_date, days_since_last_order (as of month end), months_since_acquisition (tenure), is_active_flag (purchased in trailing 90 days as of month end), returns_this_month, return_amount_this_month

**Foreign Keys:** customer_key, snapshot_month_date_key

**Why this table earns its place:** without it, every cohort retention query and every RFM recalculation has to window-function its way through the entire order history, every time. With it, retention curves are a straightforward `GROUP BY acquisition_cohort, snapshot_month`, RFM recency/frequency/monetary are pre-computed fields, and — critically for Phase 10 — each row is already a labeled feature vector: `is_active_flag` two snapshots forward becomes the churn label. This is the single design decision that most separates a "tutorial" schema from a warehouse actually built for customer analytics.

---

## 2. Dimension Tables

### Dim_Customer
**Purpose:** Who the customer is and how they entered the business.

**Attributes:** customer_key (surrogate PK), customer_id (natural key), first_name, last_name, email, signup_date, acquisition_channel_key (FK to Dim_Marketing_Channel), home_geography_key (FK to Dim_Geography), loyalty_tier (SCD Type 2 — this changes over a customer's life as they move from New to Loyal to VIP, and preserving history lets us ask "what tier was this customer when they made this purchase," which a Type 1 overwrite would destroy), customer_status (active/churned, also SCD2)

**Business value:** every customer-level cut (segmentation, RFM, cohort, geography) starts here. The SCD2 tier history is what lets Phase 6 do a genuinely interesting analysis: did revenue increase *because* customers moved up a tier, or did the tier label just catch up to revenue that already happened.

**Note on personas:** persona (Loyal VIP, Fashion Enthusiast, Bargain Hunter, Seasonal Shopper, One-Time Buyer, High-Return Customer) is deliberately **not** a column here. Personas are the answer Phase 6 analysis should discover through RFM segmentation and behavioral clustering, not a label we hand the data ahead of time. Personas exist purely as generation logic in Phase 3 (they control the *probability distributions* — purchase frequency, AOV, category preference, return rate — used to generate realistic customers) and are documented in `docs/business_glossary.md`. If persona were a stored column, Phase 6 would just be "look up the column" instead of a real analytical exercise, which defeats the point of an RFM/segmentation project.

### Dim_Product
**Purpose:** What was sold.

**Attributes:** product_key (surrogate PK), product_id (natural key), product_name, category (Womenswear, Menswear, Outerwear, Footwear, Accessories), subcategory, size, color, collection_season (e.g., Spring 2024 — ties to the campaign calendar), list_price, unit_cost, is_active

**Business value:** category and product performance, discount impact by category, and the return-rate-by-category analysis (footwear running higher, per the business context) all key off this dimension.

### Dim_Date
**Purpose:** Standard conformed date dimension, used by every fact table (order date, return date, snapshot month) so time intelligence is consistent everywhere.

**Attributes:** date_key (PK, YYYYMMDD int), full_date, day_of_week, day_name, week_of_year, month, month_name, quarter, fiscal_year, is_weekend, is_holiday_season (Nov 1 – Dec 31 flag), season_label (Spring/Summer/Fall/Winter)

**Business value:** enables the seasonality analysis (holiday concentration, BFCM lift) directly through simple filters instead of date-math in every query.

### Dim_Geography
**Purpose:** Where the customer/order is located.

**Attributes:** geography_key (PK), city, state, region (e.g., Northeast, Midwest, South, West), country

**Business value:** regional performance and underperformance-relative-to-customer-base questions from Phase 1.

### Dim_Sales_Channel
**Purpose:** Where the transaction happened.

**Attributes:** sales_channel_key (PK), channel_name (Website, Mobile App, Marketplace), channel_type (Owned/Third-Party)

**Business value:** owned vs. marketplace revenue mix, a real tension for D2C brands (marketplace sales are easier to acquire but usually lower margin and give up the customer relationship).

### Dim_Marketing_Channel
**Purpose:** How the customer was acquired — this is the attribution dimension.

**Attributes:** marketing_channel_key (PK), channel_name (Paid Social, Paid Search, Organic/SEO, Email/SMS, Affiliate/Referral, Direct), channel_category (Paid/Organic/Owned)

**Business value:** directly answers "which channels bring in customers who stick around" by joining to Fact_Customer_Monthly_Snapshot retention data — cheap paid-social customers who churn fast vs. expensive-to-acquire-but-loyal email subscribers is exactly the kind of tension a VP Marketing needs surfaced.

### Dim_Campaign
**Purpose:** The named marketing campaign calendar, so orders and revenue can be attributed to specific pushes.

**Attributes:** campaign_key (PK), campaign_name, campaign_type (Seasonal Launch / Promotional Sale / Clearance), start_date, end_date, target_discount_pct

**Recommended calendar (2023–2025, repeating annually):**

| Campaign | Type | Approx. Window |
|---|---|---|
| Spring Collection Launch | Seasonal Launch | Late Feb – Mar |
| Summer Sale | Promotional Sale | Jul |
| Back-to-School | Promotional Sale | Aug |
| Black Friday | Promotional Sale | Late Nov |
| Cyber Monday | Promotional Sale | Late Nov |
| Holiday Collection | Seasonal Launch | Nov – Dec |
| January Clearance | Clearance | Jan |

**Business value:** campaign ROI and seasonal revenue concentration both depend on being able to say "this order happened *because of* Black Friday," not just "this order happened in November."

### Dim_Return_Reason
**Purpose:** Why something was returned.

**Attributes:** return_reason_key (PK), reason_code, reason_description (Wrong Size, Changed Mind, Defective/Quality Issue, Not as Described, Late Delivery, Other)

**Business value:** distinguishes controllable return drivers (sizing, quality) from uncontrollable ones (changed mind), which matters for the Phase 8 recommendation on which return problem is actually fixable.

---

## 3. Explicitly Excluded

**Dim_Sales_Rep:** the original template roadmap listed "Sales Representatives" as a possible dimension, but Solstice Apparel is a D2C e-commerce brand with no sales force — every transaction is self-service online. Including it would be padding the schema with a table that answers no real business question here, which cuts against the "design for business questions first" principle. (This is also part of what makes the schema feel different from procurement's supplier/rep-heavy model rather than a relabeled copy.)

**Dim_Promotion as separate from Dim_Campaign:** discount codes are folded into Fact_Orders/Fact_Order_Lines as measures (discount_amount) with Dim_Campaign providing the "why" when a discount is tied to a named push. A fully separate promotions dimension would be justified if Solstice ran many overlapping, non-seasonal promo codes — it doesn't, per the business context — so this stays a measure, not a dimension, to avoid over-normalizing.

---

## 4. Relationship Map

```
Dim_Customer ──< Fact_Orders >── Dim_Sales_Channel
     │                │  │
     │                │  └──< Dim_Campaign (nullable FK)
     │                │
     │                └──< Dim_Geography (ship-to)
     │
     ├──< Fact_Customer_Monthly_Snapshot >── Dim_Date (snapshot_month)
     │
     └──< Fact_Order_Lines >── Dim_Product
              │
              └── (order_id links back to Fact_Orders — degenerate dim)

Fact_Returns >── Dim_Product
     │      >── Dim_Customer
     │      >── Dim_Return_Reason
     └──     >── Dim_Date (return_date)
     (order_id links back to the originating order — degenerate dim)

Dim_Marketing_Channel ──< Dim_Customer (acquisition_channel_key)
Dim_Marketing_Channel ──< Fact_Orders (acquisition_channel_key, denormalized)
Dim_Date ──< every fact table (conformed across order_date, return_date, snapshot_month)
```

## 5. ER Diagram (text form)

```
┌─────────────────────┐
│    Dim_Customer      │
│  PK customer_key     │
│     customer_id      │
│     signup_date      │
│     acquisition_channel_key (FK)
│     home_geography_key (FK)
│     loyalty_tier  [SCD2]
│     customer_status [SCD2]
└──────────┬───────────┘
           │
           │ 1:M
           ▼
┌─────────────────────┐        ┌──────────────────────┐
│     Fact_Orders       │──M:1──▶│  Dim_Sales_Channel    │
│  PK order_key          │        └──────────────────────┘
│     order_id (degen)   │
│  FK customer_key       │        ┌──────────────────────┐
│  FK order_date_key     │──M:1──▶│      Dim_Campaign      │
│  FK sales_channel_key  │        └──────────────────────┘
│  FK campaign_key (null)│
│  FK geography_key      │        ┌──────────────────────┐
│  FK acquisition_channel│──M:1──▶│  Dim_Marketing_Channel │
│     gross/net_revenue  │        └──────────────────────┘
└──────────┬───────────┘
           │ 1:M (via order_id)
           ▼
┌─────────────────────┐        ┌──────────────────────┐
│   Fact_Order_Lines     │──M:1──▶│      Dim_Product       │
│  PK order_line_key     │        └──────────────────────┘
│     order_id (degen)   │
│  FK customer_key       │
│  FK product_key        │
│  FK order_date_key     │
│     quantity, revenue  │
└─────────────────────┘

┌─────────────────────┐        ┌──────────────────────┐
│     Fact_Returns       │──M:1──▶│   Dim_Return_Reason    │
│  PK return_key         │        └──────────────────────┘
│     order_id (degen)   │
│  FK customer_key       │
│  FK product_key        │
│  FK return_date_key    │
│     return_qty/amount  │
└─────────────────────┘

┌──────────────────────────────┐
│ Fact_Customer_Monthly_Snapshot │
│  PK snapshot_key               │
│  FK customer_key               │
│  FK snapshot_month_date_key    │
│     cumulative_revenue,        │
│     days_since_last_order,     │
│     is_active_flag, etc.       │
└──────────────────────────────┘

              ┌──────────────┐
   (shared)   │   Dim_Date    │  ← referenced by order_date_key,
              └──────────────┘    return_date_key, snapshot_month_date_key

              ┌──────────────┐
   (shared)   │ Dim_Geography │  ← referenced by Dim_Customer.home_geography_key
              └──────────────┘    and Fact_Orders.geography_key
```

*(I can regenerate this as a draw.io diagram, same as procurement-spend-intelligence, once the table list below is confirmed — just say the word.)*

---

## 6. Design Rationale — Table-to-Business-Question Mapping

| Business Question (Phase 1) | Tables That Answer It |
|---|---|
| Revenue trend by month/quarter/year | Fact_Orders + Dim_Date |
| Which channels/categories drive revenue | Fact_Orders + Dim_Sales_Channel; Fact_Order_Lines + Dim_Product |
| Highest-value customers (RFM/CLV) | Fact_Customer_Monthly_Snapshot + Dim_Customer |
| Revenue concentration (Pareto) | Fact_Customer_Monthly_Snapshot.cumulative_net_revenue_to_date |
| Repeat purchase rate, 90-day second purchase | Fact_Orders (order sequence per customer) + Fact_Customer_Monthly_Snapshot |
| Cohort retention by acquisition month/channel | Fact_Customer_Monthly_Snapshot + Dim_Customer.signup_date + Dim_Marketing_Channel |
| Early churn-risk signals | Fact_Customer_Monthly_Snapshot.days_since_last_order trend |
| RFM segment behavior differences | Fact_Customer_Monthly_Snapshot + Fact_Order_Lines (category mix by segment) |
| Underperforming regions | Fact_Orders + Dim_Geography, normalized by customer count in Dim_Customer |
| Return rate by category/size, revenue impact | Fact_Returns + Dim_Product + Dim_Return_Reason |
| Churn prediction (Phase 10) | Fact_Customer_Monthly_Snapshot as the feature/label table directly |
| Campaign performance | Fact_Orders + Dim_Campaign |

Every table on this design exists because it's load-bearing for at least one row above — nothing was added just to look sophisticated.

---

## 7. Extensibility

**Phase 5 (descriptive/diagnostic SQL):** all of it runs directly off Fact_Orders, Fact_Order_Lines, and their conformed dimensions — no schema changes needed.

**Phase 6 (RFM, CLV, cohort):** Fact_Customer_Monthly_Snapshot does the heavy lifting. RFM becomes a straightforward NTILE() over the snapshot's recency/frequency/monetary fields instead of a from-scratch derivation each time.

**Power BI:** the constellation maps cleanly onto a Power BI model — Dim_Date, Dim_Customer, Dim_Product, and Dim_Geography as conformed/shared dimensions across multiple fact tables is exactly the pattern Power BI's relationship view and time-intelligence DAX functions expect.

**Phase 10 (churn model):** Fact_Customer_Monthly_Snapshot rows are, with almost no transformation, a supervised learning table — features are the snapshot's own columns (recency, frequency, monetary-to-date, tenure, return behavior), and the label is derived by looking two snapshots ahead (`is_active_flag` at month+2 = 0 → churned). No separate feature engineering pipeline needs to be bolted on later because the warehouse was designed with this in mind from the start.

---

## Next Step

If this design holds up on review, next is confirming the full data dictionary (column-level types, keys, and constraints) and then `schema.sql`. I'd also recommend generating `docs/business_glossary.md` alongside this — KPI definitions, persona behavioral specs for Phase 3 data generation, and the campaign calendar all belong there so they're consistent across SQL comments, Python, and Power BI later. I went ahead and drafted that too — see the companion file.

---

## Addendum: Phase 2 Finalization Refinements

The design above is approved as the architecture (four-fact constellation, unchanged). The refinements below were applied before `schema.sql` — this section exists so this document and the final schema never drift apart. Full column-level detail lives in `docs/data_dictionary.md`; full reasoning lives in `docs/design_decisions.md`.

- **Dim_Customer slimmed:** `loyalty_tier` and `customer_status` removed from the dimension. Both were derived/analytical fields, and this project's own design principle says customer analytics belongs in fact tables, not dimensions. Activity and repeat-customer status now live as flags on Fact_Customer_Monthly_Snapshot instead.
- **SCD:** Type 1 only for the MVP. With the analytical attributes moved out of Dim_Customer, there's no longer a compelling reason to carry Type 2 history — every remaining Dim_Customer attribute (signup_date, acquisition channel, home geography) is effectively immutable in this business context.
- **Fact_Customer_Monthly_Snapshot redefined** as a true periodic snapshot with no duplicated transactional detail — derived customer-state measures only (recency, rolling activity windows, cumulative and rolling revenue, and three business-rule flags: active, repeat customer, churn risk). See `data_dictionary.md` for exact column list and `design_decisions.md` for the churn-risk business rule.
- **Fact_Order_Lines** now has its own surrogate key (`order_line_key`) so Fact_Returns can reference the exact line item returned, not just the order and product.
- **Fact_Returns** links to Order, Order Line, Customer, Product, Date, and Return Reason — six foreign keys total, confirmed against the original requirement.
- **Dim_Date** expanded with fiscal quarter/year, week number, weekend and holiday flags, season, and a campaign-period flag.
- **Dim_Campaign** enriched with discount depth, season, target audience, and an active flag.
- **All surrogate keys are integers**, assigned by the Phase 3 Python generation scripts rather than database-generated identities, so the synthetic dataset stays fully reproducible run to run.

**Schema v1.1 (Phase 2.5 patch):** four fields added after the Phase 2.5 data generation strategy review — `gender` on Dim_Product, `birth_year` on Dim_Customer, `postal_code` on Dim_Geography, and `refund_completed_flag` on Fact_Returns. Full rationale and version history live in `docs/schema_changelog.md`; column-level detail is in `docs/data_dictionary.md`. **The architecture is frozen as of v1.1** — further schema changes require a genuine design defect discovered during Phase 3+ implementation, not a preference.
