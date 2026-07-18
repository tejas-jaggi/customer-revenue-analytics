-- =====================================================================
-- Customer Revenue Analytics — Solstice Apparel
-- schema.sql
--
-- Fact Constellation: 8 dimensions, 4 fact tables (Orders, Order Lines,
-- Returns, Customer Monthly Snapshot). See docs/data_dictionary.md for
-- full column definitions and docs/design_decisions.md for rationale.
--
-- All surrogate keys are INTEGER, populated by the Phase 3 Python
-- generation scripts (not database identities) so the synthetic
-- dataset is fully reproducible across regenerations.
--
-- Schema Version: v1.1 — see docs/schema_changelog.md for revision history.
-- Architecture frozen as of v1.1: further changes require a genuine
-- design defect discovered during implementation, not a preference.
-- =====================================================================

-- Clean slate for repeatable builds during development
DROP TABLE IF EXISTS Fact_Customer_Monthly_Snapshot;
DROP TABLE IF EXISTS Fact_Returns;
DROP TABLE IF EXISTS Fact_Order_Lines;
DROP TABLE IF EXISTS Fact_Orders;
DROP TABLE IF EXISTS Dim_Customer;
DROP TABLE IF EXISTS Dim_Product;
DROP TABLE IF EXISTS Dim_Geography;
DROP TABLE IF EXISTS Dim_Sales_Channel;
DROP TABLE IF EXISTS Dim_Marketing_Channel;
DROP TABLE IF EXISTS Dim_Campaign;
DROP TABLE IF EXISTS Dim_Return_Reason;
DROP TABLE IF EXISTS Dim_Date;

-- =====================================================================
-- DIMENSION TABLES
-- =====================================================================

-- Conformed date dimension, referenced by every fact table's date roles
-- (order_date, return_date, snapshot_month).
CREATE TABLE Dim_Date (
    date_key                INTEGER PRIMARY KEY,       -- YYYYMMDD
    full_date               DATE NOT NULL,
    year                    INTEGER NOT NULL,
    quarter                 INTEGER NOT NULL,
    month                   INTEGER NOT NULL,
    month_name              VARCHAR NOT NULL,
    week_of_year            INTEGER NOT NULL,
    day_of_week             INTEGER NOT NULL,
    day_name                VARCHAR NOT NULL,
    is_weekend              BOOLEAN NOT NULL,
    holiday_flag            BOOLEAN NOT NULL DEFAULT FALSE,
    fiscal_quarter          INTEGER NOT NULL,          -- aligned to calendar quarter (documented assumption)
    fiscal_year             INTEGER NOT NULL,          -- aligned to calendar year (documented assumption)
    season                  VARCHAR NOT NULL,          -- Spring / Summer / Fall / Winter
    campaign_period_flag    BOOLEAN NOT NULL DEFAULT FALSE
);

-- No analytical/derived attributes here by design — loyalty and activity
-- status live on Fact_Customer_Monthly_Snapshot instead. Type 1 only.
CREATE TABLE Dim_Geography (
    geography_key           INTEGER PRIMARY KEY,
    city                    VARCHAR NOT NULL,
    state                   VARCHAR NOT NULL,
    region                  VARCHAR NOT NULL,          -- Northeast / Midwest / South / West
    country                 VARCHAR NOT NULL DEFAULT 'United States',
    postal_code             VARCHAR                    -- v1.1: descriptive granularity below city/state, see schema_changelog.md
);

CREATE TABLE Dim_Marketing_Channel (
    marketing_channel_key   INTEGER PRIMARY KEY,
    channel_name            VARCHAR NOT NULL,          -- Paid Social / Paid Search / Organic-SEO / Email-SMS / Affiliate-Referral / Direct
    channel_category        VARCHAR NOT NULL           -- Paid / Organic / Owned
);

CREATE TABLE Dim_Sales_Channel (
    sales_channel_key       INTEGER PRIMARY KEY,
    channel_name            VARCHAR NOT NULL,          -- Website / Mobile App / Marketplace
    channel_type            VARCHAR NOT NULL           -- Owned / Third-Party
);

CREATE TABLE Dim_Campaign (
    campaign_key            INTEGER PRIMARY KEY,
    campaign_name           VARCHAR NOT NULL,          -- e.g. "Black Friday 2024"
    campaign_type           VARCHAR NOT NULL,          -- Seasonal Launch / Promotional Sale / Clearance
    start_date              DATE NOT NULL,
    end_date                DATE NOT NULL,
    discount_depth          VARCHAR NOT NULL,          -- None / Light / Moderate / Deep / Deepest
    season                  VARCHAR NOT NULL,
    target_audience         VARCHAR NOT NULL,          -- All Customers / New Customers / Loyal-VIP / Lapsed-Winback
    is_active_flag          BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (end_date >= start_date)
);

CREATE TABLE Dim_Return_Reason (
    return_reason_key       INTEGER PRIMARY KEY,
    reason_code             VARCHAR NOT NULL,
    reason_description      VARCHAR NOT NULL,          -- Wrong Size / Defective-Quality / Not as Described / Changed Mind / Late Delivery / Other
    is_controllable         BOOLEAN NOT NULL
);

-- Type 1 (MVP). Deliberately excludes loyalty_tier / customer_status —
-- those are derived customer analytics and live on
-- Fact_Customer_Monthly_Snapshot instead. See design_decisions.md #5.
CREATE TABLE Dim_Customer (
    customer_key             INTEGER PRIMARY KEY,
    customer_id              VARCHAR NOT NULL UNIQUE,   -- natural key, e.g. CUST-000001
    first_name               VARCHAR NOT NULL,
    last_name                VARCHAR NOT NULL,
    email                    VARCHAR NOT NULL,
    signup_date               DATE NOT NULL,
    birth_year                INTEGER,                 -- v1.1: age is always derived from this at query time, never stored directly
    acquisition_channel_key   INTEGER NOT NULL REFERENCES Dim_Marketing_Channel(marketing_channel_key),
    home_geography_key        INTEGER NOT NULL REFERENCES Dim_Geography(geography_key)
);

CREATE TABLE Dim_Product (
    product_key              INTEGER PRIMARY KEY,
    product_id                VARCHAR NOT NULL UNIQUE,  -- natural key, e.g. PRD-0042
    product_name              VARCHAR NOT NULL,
    category                  VARCHAR NOT NULL,         -- Womenswear / Menswear / Outerwear / Footwear / Accessories
    subcategory                VARCHAR NOT NULL,
    gender                     VARCHAR NOT NULL,        -- v1.1: Women's / Men's / Unisex — cuts across category, not derivable from it
    size                       VARCHAR,
    color                      VARCHAR,
    collection_season          VARCHAR NOT NULL,        -- e.g. "Spring 2024"
    list_price                 DECIMAL(10,2) NOT NULL CHECK (list_price >= 0),
    unit_cost                  DECIMAL(10,2) NOT NULL CHECK (unit_cost >= 0),
    is_active                  BOOLEAN NOT NULL DEFAULT TRUE
);

-- =====================================================================
-- FACT TABLES
-- =====================================================================

-- Grain: one row per order (header level).
CREATE TABLE Fact_Orders (
    order_key                  INTEGER PRIMARY KEY,
    order_id                    VARCHAR NOT NULL UNIQUE,     -- degenerate dimension, e.g. ORD-000001
    customer_key                 INTEGER NOT NULL REFERENCES Dim_Customer(customer_key),
    order_date_key                INTEGER NOT NULL REFERENCES Dim_Date(date_key),
    sales_channel_key              INTEGER NOT NULL REFERENCES Dim_Sales_Channel(sales_channel_key),
    geography_key                   INTEGER NOT NULL REFERENCES Dim_Geography(geography_key),
    campaign_key                     INTEGER REFERENCES Dim_Campaign(campaign_key),  -- nullable: not every order ties to a named campaign
    acquisition_channel_key           INTEGER NOT NULL REFERENCES Dim_Marketing_Channel(marketing_channel_key), -- denormalized from customer at time of order
    gross_revenue                      DECIMAL(12,2) NOT NULL CHECK (gross_revenue >= 0),
    discount_amount                     DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    net_revenue                          DECIMAL(12,2) NOT NULL CHECK (net_revenue >= 0),
    shipping_revenue                      DECIMAL(10,2) NOT NULL DEFAULT 0,
    is_first_order                         BOOLEAN NOT NULL DEFAULT FALSE
);

-- Grain: one row per product per order (order detail).
-- Reconciliation rule (Phase 4): SUM(net_line_revenue) per order_key
-- should equal Fact_Orders.net_revenue for that order.
CREATE TABLE Fact_Order_Lines (
    order_line_key              INTEGER PRIMARY KEY,
    order_key                    INTEGER NOT NULL REFERENCES Fact_Orders(order_key),
    customer_key                  INTEGER NOT NULL REFERENCES Dim_Customer(customer_key),   -- denormalized, see design_decisions.md #8
    product_key                    INTEGER NOT NULL REFERENCES Dim_Product(product_key),
    order_date_key                   INTEGER NOT NULL REFERENCES Dim_Date(date_key),         -- denormalized order date
    quantity                          INTEGER NOT NULL CHECK (quantity > 0),
    unit_price                         DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    gross_line_revenue                  DECIMAL(12,2) NOT NULL CHECK (gross_line_revenue >= 0),
    discount_amount                      DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    net_line_revenue                      DECIMAL(12,2) NOT NULL CHECK (net_line_revenue >= 0),
    unit_cost                              DECIMAL(10,2) NOT NULL CHECK (unit_cost >= 0)
);

-- Grain: one row per returned line item.
CREATE TABLE Fact_Returns (
    return_key                   INTEGER PRIMARY KEY,
    order_key                     INTEGER NOT NULL REFERENCES Fact_Orders(order_key),
    order_line_key                  INTEGER NOT NULL REFERENCES Fact_Order_Lines(order_line_key),
    customer_key                     INTEGER NOT NULL REFERENCES Dim_Customer(customer_key),
    product_key                       INTEGER NOT NULL REFERENCES Dim_Product(product_key),
    return_date_key                    INTEGER NOT NULL REFERENCES Dim_Date(date_key),
    return_reason_key                    INTEGER NOT NULL REFERENCES Dim_Return_Reason(return_reason_key),
    return_quantity                       INTEGER NOT NULL CHECK (return_quantity > 0),
    return_amount                          DECIMAL(12,2) NOT NULL CHECK (return_amount >= 0),
    restocking_fee                          DECIMAL(10,2) NOT NULL DEFAULT 0,
    refund_completed_flag                   BOOLEAN NOT NULL DEFAULT FALSE  -- v1.1: return requested/processed vs. refund actually completed
);

-- Grain: one row per customer per calendar month. True periodic snapshot —
-- derived customer-state measures only, no duplicated transactional detail.
-- This table is the primary source for RFM, cohort analysis, CLV,
-- retention, and the Phase 10 ML feature/label table. See
-- design_decisions.md #2 and #7.
CREATE TABLE Fact_Customer_Monthly_Snapshot (
    snapshot_key                          INTEGER PRIMARY KEY,
    customer_key                           INTEGER NOT NULL REFERENCES Dim_Customer(customer_key),
    snapshot_month_date_key                  INTEGER NOT NULL REFERENCES Dim_Date(date_key),  -- month-end date
    customer_age_days                         INTEGER NOT NULL CHECK (customer_age_days >= 0),
    months_since_first_purchase                INTEGER,   -- nullable: null until the customer's first order
    recency_days                                INTEGER,  -- nullable: null until the customer's first order
    orders_last_30_days                          INTEGER NOT NULL DEFAULT 0,
    orders_last_90_days                           INTEGER NOT NULL DEFAULT 0,
    cumulative_orders_to_date                      INTEGER NOT NULL DEFAULT 0,
    cumulative_net_revenue_to_date                  DECIMAL(14,2) NOT NULL DEFAULT 0,
    rolling_12mo_net_revenue                         DECIMAL(14,2) NOT NULL DEFAULT 0,
    is_active_flag                                    BOOLEAN NOT NULL DEFAULT FALSE,   -- recency_days <= 90
    is_repeat_customer_flag                            BOOLEAN NOT NULL DEFAULT FALSE,  -- cumulative_orders_to_date >= 2
    churn_risk_flag                                     BOOLEAN NOT NULL DEFAULT FALSE, -- 60 < recency_days <= 90
    UNIQUE (customer_key, snapshot_month_date_key)
);

-- =====================================================================
-- INDEXES
-- Supplement the PK/FK constraints above with indexes on the columns
-- that will drive the heaviest filtering in Phase 5/6 analytics.
-- =====================================================================

CREATE INDEX idx_orders_customer ON Fact_Orders(customer_key);
CREATE INDEX idx_orders_date ON Fact_Orders(order_date_key);
CREATE INDEX idx_orderlines_order ON Fact_Order_Lines(order_key);
CREATE INDEX idx_orderlines_product ON Fact_Order_Lines(product_key);
CREATE INDEX idx_returns_order ON Fact_Returns(order_key);
CREATE INDEX idx_snapshot_customer_month ON Fact_Customer_Monthly_Snapshot(customer_key, snapshot_month_date_key);
