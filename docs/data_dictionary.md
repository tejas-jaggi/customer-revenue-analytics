# Data Dictionary — Customer Revenue Analytics
## Solstice Apparel

Complete column-level reference for every table. This is the ground truth for `schema.sql` — if a column exists in the database, it's documented here, and vice versa.

Legend: **PK** = Primary Key, **FK** = Foreign Key, **NK** = Natural Key (business key, not the join key)

---

## Dimension Tables

### Dim_Date
**Grain:** One row per calendar date.

| Column | Type | Key | Description |
|---|---|---|---|
| date_key | INTEGER | PK | Surrogate key, format YYYYMMDD |
| full_date | DATE | | Calendar date |
| year | INTEGER | | Calendar year |
| quarter | INTEGER | | Calendar quarter (1–4) |
| month | INTEGER | | Month number (1–12) |
| month_name | VARCHAR | | Month name (January–December) |
| week_of_year | INTEGER | | ISO week number |
| day_of_week | INTEGER | | Day number (1=Monday–7=Sunday) |
| day_name | VARCHAR | | Day name (Monday–Sunday) |
| is_weekend | BOOLEAN | | True for Saturday/Sunday |
| holiday_flag | BOOLEAN | | True for recognized US retail holidays (New Year's Day, Memorial Day, July 4th, Labor Day, Thanksgiving, Black Friday, Christmas Day) |
| fiscal_quarter | INTEGER | | Fiscal quarter — aligned to calendar quarter for this project (documented assumption, see design_decisions.md) |
| fiscal_year | INTEGER | | Fiscal year — aligned to calendar year (same assumption) |
| season | VARCHAR | | Spring / Summer / Fall / Winter |
| campaign_period_flag | BOOLEAN | | True if this date falls within any Dim_Campaign start/end window |

### Dim_Customer
**Grain:** One row per customer.

| Column | Type | Key | Description |
|---|---|---|---|
| customer_key | INTEGER | PK | Surrogate key |
| customer_id | VARCHAR | NK | Business/natural customer identifier (e.g., CUST-000001) |
| first_name | VARCHAR | | Synthetic first name |
| last_name | VARCHAR | | Synthetic last name |
| email | VARCHAR | | Synthetic email address |
| signup_date | DATE | | Date the customer created an account (may precede first purchase) |
| birth_year | INTEGER | | *(v1.1)* Year of birth. Age is always derived at query time (current or snapshot date minus birth_year) — never stored, since a static age column would go stale |
| acquisition_channel_key | INTEGER | FK → Dim_Marketing_Channel | How the customer was acquired |
| home_geography_key | INTEGER | FK → Dim_Geography | Customer's primary shipping region |

Deliberately excludes: loyalty_tier, customer_status, persona — all analytical/derived and pushed to Fact_Customer_Monthly_Snapshot or generation-side documentation instead (see business_glossary.md and design_decisions.md).

### Dim_Product
**Grain:** One row per product/SKU.

| Column | Type | Key | Description |
|---|---|---|---|
| product_key | INTEGER | PK | Surrogate key |
| product_id | VARCHAR | NK | Business/natural product identifier (e.g., PRD-0042) |
| product_name | VARCHAR | | Product name |
| category | VARCHAR | | Womenswear / Menswear / Outerwear / Footwear / Accessories |
| subcategory | VARCHAR | | e.g., Dresses, Denim, Sneakers |
| gender | VARCHAR | | *(v1.1)* Women's / Men's / Unisex — cuts across category (e.g., unisex Accessories), not derivable from category alone |
| size | VARCHAR | | Size label (varies by category) |
| color | VARCHAR | | Color |
| collection_season | VARCHAR | | e.g., "Spring 2024" — ties product to the collection it launched with |
| list_price | DECIMAL(10,2) | | Standard selling price |
| unit_cost | DECIMAL(10,2) | | Cost of goods, enables margin calculation |
| is_active | BOOLEAN | | Whether the product is currently sellable |

### Dim_Geography
**Grain:** One row per city/state combination shipped to.

| Column | Type | Key | Description |
|---|---|---|---|
| geography_key | INTEGER | PK | Surrogate key |
| city | VARCHAR | | City |
| state | VARCHAR | | US state |
| region | VARCHAR | | Northeast / Midwest / South / West |
| country | VARCHAR | | Country (United States for all rows in v1) |
| postal_code | VARCHAR | | *(v1.1)* ZIP/postal code — descriptive granularity below city/state, kept flat; city/state/region remain the analytical rollup levels |

### Dim_Sales_Channel
**Grain:** One row per sales channel.

| Column | Type | Key | Description |
|---|---|---|---|
| sales_channel_key | INTEGER | PK | Surrogate key |
| channel_name | VARCHAR | | Website / Mobile App / Marketplace |
| channel_type | VARCHAR | | Owned / Third-Party |

### Dim_Marketing_Channel
**Grain:** One row per acquisition/marketing channel.

| Column | Type | Key | Description |
|---|---|---|---|
| marketing_channel_key | INTEGER | PK | Surrogate key |
| channel_name | VARCHAR | | Paid Social / Paid Search / Organic/SEO / Email/SMS / Affiliate/Referral / Direct |
| channel_category | VARCHAR | | Paid / Organic / Owned |

### Dim_Campaign
**Grain:** One row per named marketing campaign instance (each year's Black Friday is its own row).

| Column | Type | Key | Description |
|---|---|---|---|
| campaign_key | INTEGER | PK | Surrogate key |
| campaign_name | VARCHAR | | e.g., "Black Friday 2024" |
| campaign_type | VARCHAR | | Seasonal Launch / Promotional Sale / Clearance |
| start_date | DATE | | Campaign start |
| end_date | DATE | | Campaign end |
| discount_depth | VARCHAR | | None / Light / Moderate / Deep / Deepest |
| season | VARCHAR | | Spring / Summer / Fall / Winter |
| target_audience | VARCHAR | | All Customers / New Customers / Loyal-VIP / Lapsed-Winback |
| is_active_flag | BOOLEAN | | Whether this campaign record is currently in use (supports retiring old campaign definitions without deleting history) |

### Dim_Return_Reason
**Grain:** One row per return reason code.

| Column | Type | Key | Description |
|---|---|---|---|
| return_reason_key | INTEGER | PK | Surrogate key |
| reason_code | VARCHAR | | Short code |
| reason_description | VARCHAR | | Wrong Size / Defective-Quality Issue / Not as Described / Changed Mind / Late Delivery / Other |
| is_controllable | BOOLEAN | | Whether Solstice can realistically act on this reason (sizing, quality, logistics = controllable; changed mind = not) |

---

## Fact Tables

### Fact_Orders
**Grain:** One row per order (order header).

| Column | Type | Key | Description |
|---|---|---|---|
| order_key | INTEGER | PK | Surrogate key |
| order_id | VARCHAR | NK, UNIQUE | Business order number (degenerate dimension) |
| customer_key | INTEGER | FK → Dim_Customer | Who placed the order |
| order_date_key | INTEGER | FK → Dim_Date | When the order was placed |
| sales_channel_key | INTEGER | FK → Dim_Sales_Channel | Where the order was placed |
| geography_key | INTEGER | FK → Dim_Geography | Ship-to region |
| campaign_key | INTEGER | FK → Dim_Campaign, NULLABLE | Named campaign this order is attributed to, if any |
| acquisition_channel_key | INTEGER | FK → Dim_Marketing_Channel | Denormalized copy of the customer's acquisition channel, kept here so channel-level revenue rollups don't require a join through Dim_Customer |
| gross_revenue | DECIMAL(12,2) | | Revenue before discounts |
| discount_amount | DECIMAL(12,2) | | Total discount applied to the order |
| net_revenue | DECIMAL(12,2) | | gross_revenue − discount_amount |
| shipping_revenue | DECIMAL(10,2) | | Shipping charged, if any |
| is_first_order | BOOLEAN | | True if this is the customer's first order |

### Fact_Order_Lines
**Grain:** One row per product per order.

| Column | Type | Key | Description |
|---|---|---|---|
| order_line_key | INTEGER | PK | Surrogate key |
| order_key | INTEGER | FK → Fact_Orders | Parent order |
| customer_key | INTEGER | FK → Dim_Customer | Denormalized for direct product-customer analysis |
| product_key | INTEGER | FK → Dim_Product | Product sold |
| order_date_key | INTEGER | FK → Dim_Date | Denormalized order date |
| quantity | INTEGER | | Units sold on this line |
| unit_price | DECIMAL(10,2) | | Price at time of sale |
| gross_line_revenue | DECIMAL(12,2) | | quantity × unit_price |
| discount_amount | DECIMAL(10,2) | | Line-level discount |
| net_line_revenue | DECIMAL(12,2) | | gross_line_revenue − discount_amount |
| unit_cost | DECIMAL(10,2) | | Cost basis, enables margin |

**Reconciliation rule (Phase 4 validation):** SUM(net_line_revenue) per order_key should equal Fact_Orders.net_revenue for that order.

### Fact_Returns
**Grain:** One row per returned line item.

| Column | Type | Key | Description |
|---|---|---|---|
| return_key | INTEGER | PK | Surrogate key |
| order_key | INTEGER | FK → Fact_Orders | Originating order |
| order_line_key | INTEGER | FK → Fact_Order_Lines | Exact line item returned |
| customer_key | INTEGER | FK → Dim_Customer | Who returned it |
| product_key | INTEGER | FK → Dim_Product | What was returned |
| return_date_key | INTEGER | FK → Dim_Date | When the return was processed |
| return_reason_key | INTEGER | FK → Dim_Return_Reason | Why it was returned |
| return_quantity | INTEGER | | Units returned (≤ original line quantity) |
| return_amount | DECIMAL(12,2) | | Revenue reversed |
| restocking_fee | DECIMAL(10,2) | | Fee retained, if any (can be 0) |
| refund_completed_flag | BOOLEAN | | *(v1.1)* True once the refund has actually been issued, distinct from the return simply being requested/processed — not derivable from any other field, captures real operational lag |

### Fact_Customer_Monthly_Snapshot
**Grain:** One row per customer per calendar month. True periodic snapshot — no duplicated order/return-level detail, derived customer-state measures only.

| Column | Type | Key | Description |
|---|---|---|---|
| snapshot_key | INTEGER | PK | Surrogate key |
| customer_key | INTEGER | FK → Dim_Customer | Customer this snapshot describes |
| snapshot_month_date_key | INTEGER | FK → Dim_Date | Month-end date this snapshot represents |
| customer_age_days | INTEGER | | Days since signup_date as of snapshot month-end |
| months_since_first_purchase | INTEGER | | Months since the customer's first order (may differ from customer_age_days if signup preceded first purchase) |
| recency_days | INTEGER | | Days since the customer's most recent order as of snapshot month-end |
| orders_last_30_days | INTEGER | | Order count, trailing 30 days |
| orders_last_90_days | INTEGER | | Order count, trailing 90 days |
| cumulative_orders_to_date | INTEGER | | Total orders ever placed, through this snapshot month |
| cumulative_net_revenue_to_date | DECIMAL(14,2) | | Total net revenue ever generated, through this snapshot month |
| rolling_12mo_net_revenue | DECIMAL(14,2) | | Net revenue, trailing 12 months |
| is_active_flag | BOOLEAN | | Business rule: recency_days ≤ 90 |
| is_repeat_customer_flag | BOOLEAN | | Business rule: cumulative_orders_to_date ≥ 2 |
| churn_risk_flag | BOOLEAN | | Business rule: 60 < recency_days ≤ 90 (past a normal repurchase window but not yet counted inactive) — see design_decisions.md for the full rationale |

**Why this table has no orders_this_month/revenue_this_month columns:** those would duplicate what's directly derivable from Fact_Orders filtered to the snapshot month, and the instruction to avoid duplicating transactional data means the snapshot sticks to *state* (cumulative position, recency, rolling windows) rather than *activity* that's already recorded elsewhere at finer grain.
