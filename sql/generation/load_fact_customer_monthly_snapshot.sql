-- =====================================================================
-- Load: Fact_Customer_Monthly_Snapshot (Phase 3.12) -- standalone
-- SQL-only load path, an alternative to running the generator directly.
-- Both produce identical results: the generator has no randomness at all,
-- so data/generated/fact_customer_monthly_snapshot.csv is a pure
-- function of the persisted facts.
--
-- Prerequisites: schema applied; all 8 dimensions + Fact_Orders +
-- Fact_Order_Lines + Fact_Returns loaded (FK constraints reject the load
-- otherwise); the CSV exists.
--
-- Run: duckdb data/database/solstice_apparel.duckdb < sql/generation/load_fact_customer_monthly_snapshot.sql
-- =====================================================================
BEGIN TRANSACTION;
DELETE FROM Fact_Customer_Monthly_Snapshot;
COPY Fact_Customer_Monthly_Snapshot (
    snapshot_key, customer_key, snapshot_month_date_key, customer_age_days,
    months_since_first_purchase, recency_days, orders_last_30_days,
    orders_last_90_days, cumulative_orders_to_date, cumulative_net_revenue_to_date,
    rolling_12mo_net_revenue, is_active_flag, is_repeat_customer_flag, churn_risk_flag
)
FROM 'data/generated/fact_customer_monthly_snapshot.csv' (HEADER, DELIMITER ',');
COMMIT;
SELECT COUNT(*) AS rows_loaded FROM Fact_Customer_Monthly_Snapshot;
