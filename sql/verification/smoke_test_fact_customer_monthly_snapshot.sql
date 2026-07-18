-- =====================================================================
-- Smoke Test: Fact_Customer_Monthly_Snapshot (Phase 3.12)
-- Fast, mechanical checks -- did the load succeed at all. The three
-- named invariants and every business rule live in
-- sql/validation/validate_fact_customer_monthly_snapshot.sql.
-- =====================================================================

-- 1. Row count is exactly 147,995 -- this table is fully derived, so the
--    count is exactly computable (sum over customers of the months from
--    their signup month through 2025-12), never a range
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 147995 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot;

-- 2. snapshot_key: no nulls, no duplicates
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT snapshot_key) AS distinct_keys,
       CASE WHEN COUNT(*) = COUNT(DISTINCT snapshot_key) AND COUNT(*) = COUNT(snapshot_key)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot;

-- 3. Grain: UNIQUE (customer_key, snapshot_month_date_key)
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT (customer_key, snapshot_month_date_key)) AS distinct_grain,
       CASE WHEN COUNT(*) = COUNT(DISTINCT (customer_key, snapshot_month_date_key))
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot;

-- 4. NOT NULL sweep. Only months_since_first_purchase and recency_days
--    are nullable, and only until the customer's first order -- both
--    directions are checked in the validation suite.
SELECT CASE WHEN SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN snapshot_month_date_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN customer_age_days IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN orders_last_30_days IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN orders_last_90_days IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN cumulative_orders_to_date IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN cumulative_net_revenue_to_date IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN rolling_12mo_net_revenue IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN is_active_flag IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN is_repeat_customer_flag IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN churn_risk_flag IS NULL THEN 1 ELSE 0 END) = 0
       THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot;

-- 5. schema.sql CHECK (customer_age_days >= 0) re-read
SELECT COUNT(*) AS negative_age_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot WHERE customer_age_days < 0;

-- 6. Every customer has a series, and no snapshot references a customer
--    that doesn't exist
SELECT (SELECT COUNT(DISTINCT customer_key) FROM Fact_Customer_Monthly_Snapshot) AS customers_in_snapshot,
       (SELECT COUNT(*) FROM Dim_Customer) AS customers_in_dim,
       CASE WHEN (SELECT COUNT(DISTINCT customer_key) FROM Fact_Customer_Monthly_Snapshot)
                 = (SELECT COUNT(*) FROM Dim_Customer)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- 7. Structural shape
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'Fact_Customer_Monthly_Snapshot' ORDER BY ordinal_position;
