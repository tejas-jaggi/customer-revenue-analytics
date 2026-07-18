-- =====================================================================
-- Load: Fact_Returns (Phase 3.11) -- standalone SQL-only load path.
-- Prerequisites: schema applied; all 8 dimensions + Fact_Orders +
-- Fact_Order_Lines loaded (FK constraints reject the load otherwise);
-- data/generated/fact_returns.csv exists.
-- Run: duckdb data/database/solstice_apparel.duckdb < sql/generation/load_fact_returns.sql
-- =====================================================================
BEGIN TRANSACTION;
DELETE FROM Fact_Returns;
COPY Fact_Returns (
    return_key, order_key, order_line_key, customer_key, product_key,
    return_date_key, return_reason_key, return_quantity, return_amount,
    restocking_fee, refund_completed_flag
)
FROM 'data/generated/fact_returns.csv' (HEADER, DELIMITER ',');
COMMIT;
SELECT COUNT(*) AS rows_loaded FROM Fact_Returns;
