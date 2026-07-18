-- =====================================================================
-- Load: Fact_Order_Lines (Phase 3.10) -- standalone SQL-only load path.
-- Prerequisites: schema applied; all dimensions + Fact_Orders loaded;
-- data/generated/fact_order_lines.csv exists.
-- Run: duckdb data/database/solstice_apparel.duckdb < sql/generation/load_fact_order_lines.sql
-- =====================================================================
BEGIN TRANSACTION;
DELETE FROM Fact_Order_Lines;
COPY Fact_Order_Lines (
    order_line_key, order_key, customer_key, product_key, order_date_key,
    quantity, unit_price, gross_line_revenue, discount_amount,
    net_line_revenue, unit_cost
)
FROM 'data/generated/fact_order_lines.csv' (HEADER, DELIMITER ',');
COMMIT;
SELECT COUNT(*) AS rows_loaded FROM Fact_Order_Lines;
