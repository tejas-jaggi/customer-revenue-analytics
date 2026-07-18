-- =====================================================================
-- Load: Fact_Orders (Phase 3.9)
-- Standalone SQL-only load path -- alternative to generate_fact_orders.py.
-- Prerequisites: schema applied; all 8 dimensions loaded (FK constraints
-- will reject the load otherwise); data/generated/fact_orders.csv exists.
-- Run: duckdb data/database/solstice_apparel.duckdb < sql/generation/load_fact_orders.sql
-- =====================================================================
BEGIN TRANSACTION;
DELETE FROM Fact_Orders;
COPY Fact_Orders (
    order_key, order_id, customer_key, order_date_key, sales_channel_key,
    geography_key, campaign_key, acquisition_channel_key,
    gross_revenue, discount_amount, net_revenue, shipping_revenue, is_first_order
)
FROM 'data/generated/fact_orders.csv' (HEADER, DELIMITER ',');
COMMIT;
SELECT COUNT(*) AS rows_loaded FROM Fact_Orders;
