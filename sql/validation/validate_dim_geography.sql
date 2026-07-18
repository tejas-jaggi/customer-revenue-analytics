-- =====================================================================
-- Validation: Dim_Geography (Phase 3.2)
--
-- Business-rule validation -- goes beyond the mechanical checks in
-- sql/verification/smoke_test_dim_geography.sql to confirm the data
-- actually reflects usable, internally-consistent US geography that
-- Dim_Customer and Fact_Orders can safely reference.
-- =====================================================================

-- 1. region must only contain the four valid values (empty result = PASS)
SELECT DISTINCT region AS invalid_region
FROM Dim_Geography
WHERE region NOT IN ('Northeast', 'Midwest', 'South', 'West');

-- 2. postal_code must be exactly 5 digits, US ZIP format (empty result = PASS)
SELECT geography_key, city, state, postal_code AS invalid_postal_code
FROM Dim_Geography
WHERE NOT (postal_code SIMILAR TO '[0-9]{5}');

-- 3. No duplicate (city, state) combinations (empty result = PASS)
SELECT city, state, COUNT(*) AS occurrences
FROM Dim_Geography
GROUP BY city, state
HAVING COUNT(*) > 1;

-- 4. Canonical state -> region mapping must hold for every row -- catches
--    a state accidentally tagged with the wrong region (empty result = PASS)
SELECT geography_key, city, state, region AS mismatched_region
FROM Dim_Geography
WHERE NOT (
    CASE region
        WHEN 'Northeast' THEN state IN ('NY','MA','PA','NJ','CT')
        WHEN 'Midwest'   THEN state IN ('IL','OH','MI','WI','MN','MO')
        WHEN 'South'     THEN state IN ('TX','FL','GA','NC','TN','VA')
        WHEN 'West'      THEN state IN ('CA','WA','OR','AZ','CO','NV')
        ELSE FALSE
    END
);

-- 5. Expected distribution: all 4 regions represented, each with at least
--    8 cities so downstream regional analysis in Phase 5/6 has enough
--    variety per region to be statistically meaningful
SELECT region, COUNT(*) AS city_count,
       CASE WHEN COUNT(*) >= 8 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Geography
GROUP BY region
ORDER BY region;

-- 5b. Confirm no region is missing entirely (a GROUP BY alone can't prove
--     a region has zero rows, since it simply wouldn't appear)
SELECT missing_region
FROM (VALUES ('Northeast'), ('Midwest'), ('South'), ('West')) AS all_regions(missing_region)
WHERE missing_region NOT IN (SELECT DISTINCT region FROM Dim_Geography);

-- 6. Foreign-key readiness: geography_key must be a dense, contiguous
--    integer sequence starting at 1 -- this is exactly what
--    Dim_Customer.home_geography_key and Fact_Orders.geography_key will
--    reference, so a gap or duplicate here would silently break
--    referential integrity for every downstream table
SELECT MIN(geography_key) AS min_key, MAX(geography_key) AS max_key, COUNT(*) AS row_count,
       CASE WHEN MIN(geography_key) = 1 AND MAX(geography_key) = COUNT(*)
                 AND COUNT(DISTINCT geography_key) = COUNT(*)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Geography;

-- 7. country must be the single consistent value expected for v1 scope
--    (US-only, per data_dictionary.md)
SELECT DISTINCT country AS unexpected_country
FROM Dim_Geography
WHERE country != 'United States';
