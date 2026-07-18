-- =====================================================================
-- Smoke Test: Dim_Customer (Phase 3.8)
--
-- Fast, mechanical checks -- did the load succeed at all. Run
-- immediately after generate_dim_customer.py or load_dim_customer.sql.
-- Deeper business-rule and statistical checks live in
-- sql/validation/validate_dim_customer.sql, not here.
-- =====================================================================

-- 1. Row count must be exactly 8,000 (2,500 + 3,000 + 2,500 by year)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 8000 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Customer;

-- 2. customer_key: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_key) AS distinct_keys,
    COUNT(customer_key) AS non_null_keys,
    CASE WHEN COUNT(*) = COUNT(DISTINCT customer_key)
              AND COUNT(*) = COUNT(customer_key)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Customer;

-- 3. customer_id: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS distinct_ids,
    COUNT(customer_id) AS non_null_ids,
    CASE WHEN COUNT(*) = COUNT(DISTINCT customer_id)
              AND COUNT(*) = COUNT(customer_id)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Customer;

-- 4. email: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT email) AS distinct_emails,
    COUNT(email) AS non_null_emails,
    CASE WHEN COUNT(*) = COUNT(DISTINCT email)
              AND COUNT(*) = COUNT(email)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Customer;

-- 5. No nulls in the remaining NOT NULL columns (birth_year is nullable
--    in schema.sql, checked separately in validation since this
--    generator always populates it as its own expectation, not a
--    schema requirement)
SELECT
    SUM(CASE WHEN first_name IS NULL THEN 1 ELSE 0 END)             AS null_first_name,
    SUM(CASE WHEN last_name IS NULL THEN 1 ELSE 0 END)              AS null_last_name,
    SUM(CASE WHEN signup_date IS NULL THEN 1 ELSE 0 END)            AS null_signup_date,
    SUM(CASE WHEN acquisition_channel_key IS NULL THEN 1 ELSE 0 END) AS null_acquisition_channel_key,
    SUM(CASE WHEN home_geography_key IS NULL THEN 1 ELSE 0 END)      AS null_home_geography_key,
    CASE WHEN SUM(CASE WHEN first_name IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN last_name IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN signup_date IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN acquisition_channel_key IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN home_geography_key IS NULL THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Customer;

-- 6. FOREIGN KEY sanity read: every acquisition_channel_key and
--    home_geography_key must resolve to a real parent row. schema.sql's
--    REFERENCES constraints already enforce this at INSERT time -- this
--    is a readable, explicit re-confirmation, same philosophy as
--    Dim_Campaign's CHECK (end_date >= start_date) smoke-test re-read.
SELECT COUNT(*) AS orphaned_acquisition_channel_fk,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Customer c
LEFT JOIN Dim_Marketing_Channel m ON c.acquisition_channel_key = m.marketing_channel_key
WHERE m.marketing_channel_key IS NULL;

SELECT COUNT(*) AS orphaned_geography_fk,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Customer c
LEFT JOIN Dim_Geography g ON c.home_geography_key = g.geography_key
WHERE g.geography_key IS NULL;

-- 7. Structural shape check -- confirms the table has exactly the
--    columns schema.sql defines
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'Dim_Customer'
ORDER BY ordinal_position;
