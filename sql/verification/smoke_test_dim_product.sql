-- =====================================================================
-- Smoke Test: Dim_Product (Phase 3.6)
--
-- Fast, mechanical checks -- did the load succeed at all. Run
-- immediately after generate_dim_product.py or load_dim_product.sql.
-- Deeper business-rule checks live in
-- sql/validation/validate_dim_product.sql, not here.
-- =====================================================================

-- 1. Row count must be exactly 180 (45+35+30+30+40 per the category plan)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 180 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Product;

-- 2. product_key: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_key) AS distinct_keys,
    COUNT(product_key) AS non_null_keys,
    CASE WHEN COUNT(*) = COUNT(DISTINCT product_key)
              AND COUNT(*) = COUNT(product_key)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Product;

-- 3. product_id: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_id) AS distinct_ids,
    COUNT(product_id) AS non_null_ids,
    CASE WHEN COUNT(*) = COUNT(DISTINCT product_id)
              AND COUNT(*) = COUNT(product_id)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Product;

-- 4. No nulls in the columns schema.sql marks NOT NULL (size and color
--    are nullable in schema.sql and checked separately in validation)
SELECT
    SUM(CASE WHEN product_name IS NULL THEN 1 ELSE 0 END)       AS null_product_name,
    SUM(CASE WHEN category IS NULL THEN 1 ELSE 0 END)           AS null_category,
    SUM(CASE WHEN subcategory IS NULL THEN 1 ELSE 0 END)        AS null_subcategory,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END)             AS null_gender,
    SUM(CASE WHEN collection_season IS NULL THEN 1 ELSE 0 END)  AS null_collection_season,
    SUM(CASE WHEN list_price IS NULL THEN 1 ELSE 0 END)         AS null_list_price,
    SUM(CASE WHEN unit_cost IS NULL THEN 1 ELSE 0 END)          AS null_unit_cost,
    SUM(CASE WHEN is_active IS NULL THEN 1 ELSE 0 END)          AS null_is_active,
    CASE WHEN SUM(CASE WHEN product_name IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN category IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN subcategory IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN collection_season IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN list_price IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN unit_cost IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN is_active IS NULL THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Product;

-- 5. schema.sql's CHECK (list_price >= 0) / CHECK (unit_cost >= 0)
--    sanity read against the actual loaded table
SELECT COUNT(*) AS rows_with_bad_prices,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Product
WHERE list_price < 0 OR unit_cost < 0;

-- 6. Structural shape check -- confirms the table has exactly the
--    columns schema.sql defines
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'Dim_Product'
ORDER BY ordinal_position;
