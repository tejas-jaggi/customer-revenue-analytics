-- =====================================================================
-- Validation: Dim_Product (Phase 3.6)
--
-- Slower, business-aware checks -- does the data satisfy the rules that
-- make it usable, not just "did the load mechanically work" (that's
-- sql/verification/smoke_test_dim_product.sql). This is the richest
-- dimension built so far (12 columns, 5 categories each with their own
-- valid subcategory/gender/price-range rules), so this suite is
-- deliberately the most thorough in Phase 3 to date, matching
-- generate_dim_product.py's validate_dataframe() check-for-check where
-- practical in SQL. Every check returns an empty result set (or an
-- explicit PASS) when clean.
-- =====================================================================

-- 1. category must only contain the 5 valid values
SELECT DISTINCT category AS invalid_category
FROM Dim_Product
WHERE category NOT IN ('Womenswear', 'Menswear', 'Outerwear', 'Footwear', 'Accessories');

-- 2. gender must only contain the 3 valid values
SELECT DISTINCT gender AS invalid_gender
FROM Dim_Product
WHERE gender NOT IN ('Women''s', 'Men''s', 'Unisex');

-- 3. collection_season must only contain the 6 valid values
SELECT DISTINCT collection_season AS invalid_collection_season
FROM Dim_Product
WHERE collection_season NOT IN (
    'Spring 2023', 'Spring 2024', 'Spring 2025',
    'Holiday 2023', 'Holiday 2024', 'Holiday 2025'
);

-- 4. product_id must match the PRD-#### pattern (4 digits) -- DuckDB
--    regexp_matches for pattern validation
SELECT product_id
FROM Dim_Product
WHERE NOT regexp_matches(product_id, '^PRD-\d{4}$');

-- 5. Category row counts must match the documented plan exactly
SELECT category, COUNT(*) AS actual_count,
       CASE
           WHEN category = 'Womenswear'  AND COUNT(*) = 45 THEN 'PASS'
           WHEN category = 'Menswear'    AND COUNT(*) = 35 THEN 'PASS'
           WHEN category = 'Outerwear'   AND COUNT(*) = 30 THEN 'PASS'
           WHEN category = 'Footwear'    AND COUNT(*) = 30 THEN 'PASS'
           WHEN category = 'Accessories' AND COUNT(*) = 40 THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM Dim_Product
GROUP BY category
ORDER BY category;

-- 6. subcategory must belong to its category's allowed list
SELECT product_id, category, subcategory
FROM Dim_Product
WHERE (category = 'Womenswear'  AND subcategory NOT IN ('Dresses', 'Tops', 'Bottoms', 'Denim', 'Knitwear'))
   OR (category = 'Menswear'    AND subcategory NOT IN ('Shirts', 'Bottoms', 'Denim', 'Knitwear', 'Activewear'))
   OR (category = 'Outerwear'   AND subcategory NOT IN ('Jackets', 'Coats', 'Vests'))
   OR (category = 'Footwear'    AND subcategory NOT IN ('Sneakers', 'Boots', 'Sandals'))
   OR (category = 'Accessories' AND subcategory NOT IN ('Bags', 'Jewelry', 'Belts', 'Hats', 'Scarves'));

-- 7. gender must belong to its category's allowed options (Womenswear is
--    always Women's, Menswear is always Men's -- neither ever mixes in
--    the other or Unisex)
SELECT product_id, category, gender
FROM Dim_Product
WHERE (category = 'Womenswear' AND gender != 'Women''s')
   OR (category = 'Menswear'   AND gender != 'Men''s');

-- 8. list_price must fall within the category's documented range
SELECT product_id, category, list_price
FROM Dim_Product
WHERE (category = 'Womenswear'  AND (list_price < 28  OR list_price > 120))
   OR (category = 'Menswear'    AND (list_price < 25  OR list_price > 110))
   OR (category = 'Outerwear'   AND (list_price < 90  OR list_price > 280))
   OR (category = 'Footwear'    AND (list_price < 60  OR list_price > 180))
   OR (category = 'Accessories' AND (list_price < 15  OR list_price > 65));

-- 9. unit_cost must match list_price x the category's documented cost
--    percentage, within 1 cent of rounding tolerance
SELECT product_id, category, list_price, unit_cost,
       ROUND(list_price * CASE category
           WHEN 'Womenswear'  THEN 0.40
           WHEN 'Menswear'    THEN 0.40
           WHEN 'Outerwear'   THEN 0.35
           WHEN 'Footwear'    THEN 0.45
           WHEN 'Accessories' THEN 0.30
       END, 2) AS expected_unit_cost
FROM Dim_Product
WHERE ABS(unit_cost - ROUND(list_price * CASE category
           WHEN 'Womenswear'  THEN 0.40
           WHEN 'Menswear'    THEN 0.40
           WHEN 'Outerwear'   THEN 0.35
           WHEN 'Footwear'    THEN 0.45
           WHEN 'Accessories' THEN 0.30
       END, 2)) > 0.01;

-- 10. unit_cost must never reach or exceed list_price (positive margin
--     on every SKU)
SELECT product_id, list_price, unit_cost
FROM Dim_Product
WHERE unit_cost >= list_price;

-- 11. collection_season must respect each category's documented lean
--     (Womenswear/Menswear -> Spring only; Outerwear/Accessories ->
--     Holiday only; Footwear -> either)
SELECT product_id, category, collection_season
FROM Dim_Product
WHERE (category IN ('Womenswear', 'Menswear') AND collection_season NOT LIKE 'Spring%')
   OR (category IN ('Outerwear', 'Accessories') AND collection_season NOT LIKE 'Holiday%');

-- 12. size business rule: NULL only for the five no-size accessory
--     subcategories; Footwear sizes only from the shoe-size vocabulary;
--     everything else only from the apparel-size vocabulary
SELECT product_id, category, subcategory, size
FROM Dim_Product
WHERE (subcategory IN ('Bags', 'Jewelry', 'Belts', 'Hats', 'Scarves') AND size IS NOT NULL)
   OR (subcategory NOT IN ('Bags', 'Jewelry', 'Belts', 'Hats', 'Scarves')
       AND category = 'Footwear' AND (size IS NULL OR size NOT IN ('6','7','8','9','10','11','12')))
   OR (subcategory NOT IN ('Bags', 'Jewelry', 'Belts', 'Hats', 'Scarves')
       AND category != 'Footwear' AND (size IS NULL OR size NOT IN ('XS','S','M','L','XL')));

-- 13. color must never be null (schema.sql permits it, but this
--     generator always assigns one -- a null here is a generation bug,
--     not an intentional gap)
SELECT COUNT(*) AS null_color_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Product
WHERE color IS NULL;

-- 14. Every row's is_active should be TRUE in this initial generation
SELECT COUNT(*) AS inactive_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Product
WHERE is_active != TRUE;

-- 15. FK-readiness: product_key must be dense, contiguous, and start at
--     1 -- this is what Fact_Order_Lines.product_key and
--     Fact_Returns.product_key will reference once those tables are built
SELECT MIN(product_key) AS min_key, MAX(product_key) AS max_key,
       COUNT(*) AS row_count,
       CASE WHEN MIN(product_key) = 1
             AND MAX(product_key) = COUNT(*)
             AND COUNT(DISTINCT product_key) = COUNT(*)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Product;
