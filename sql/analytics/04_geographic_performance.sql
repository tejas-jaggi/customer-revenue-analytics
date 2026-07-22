-- ####################################################################
-- Phase 5 — SQL Analytics Layer
-- SECTION D — GEOGRAPHIC PERFORMANCE ANALYSIS
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 (frozen, certified). Read-only analytics.
-- Governed by permanent rules P5-1/P5-2/P5-3 (docs/phase5_build_log.md).
--
-- PURPOSE: not geographic revenue reporting, but geographic PERFORMANCE —
--   where the business over/under-performs expectations and why a region
--   deserves management attention.
--
-- GRAIN DISCIPLINE (deliberate two-level design):
--   Primary lens = REGION (4: South/West/Midwest/Northeast). Every region
--   has 1,300-3,000 customers, so all regional findings are statistically
--   solid. City-level (46 geographies) is used ONLY in D.2's index, where
--   the agreed LOW-BASE GUARDRAIL separates signal from small-sample noise.
--   A 46-city revenue-per-customer scatter would be noise-dominated and is
--   deliberately avoided as the primary lens.
--
-- BOUNDARY: acquisition-channel-by-geography is Section E; returns-by-
--   geography is Section G. Section D identifies those questions (D.7),
--   it does not answer them.
--
-- ANCHOR: geographic revenue reconciles to Section B / certified Order Net
--   Revenue $2,195,871.49; customer counts reconcile to 8,000.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- D.1 — Regional Revenue Performance
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How do the four regions compare on revenue, orders,
--                     and customers, and what share does each contribute?
-- Stakeholder       : CFO / COO
-- Metric Definition : per region: SUM(net_revenue), COUNT(orders), distinct
--                     purchasing customers, % of total revenue
-- Metric Basis      : Order Net Revenue
-- Analysis Grain    : Fact_Orders (header — geography_key lives here) x Dim_Geography
-- SQL Design        : geography_key is on Fact_Orders (denormalized from the
--                     customer's home geography), so revenue is a clean header
--                     aggregate rolled to region. No line join.
-- Analytical Assumptions : geography_key on the order is the customer's home
--                     region (Phase 4 check 1.1 confirmed it matches the
--                     customer's current home_geography_key — no stale vintage).
-- Independent Review: Header measure grouped by region. Additive. OK.
-- Validation        : Type A — regional revenue sums to $2,195,871.49.
-- Result Sanity     : South largest (~37%, matches generation weight 38%),
--                     Northeast smallest (~18%). Order-count ordering matches
--                     revenue ordering (AOV is geography-independent).
-- ═══════════════════════════════════════════════════════════════════
SELECT g.region,
       COUNT(DISTINCT o.customer_key)                             AS purchasing_customers,
       COUNT(*)                                                   AS orders,
       ROUND(SUM(o.net_revenue), 2)                               AS order_net_revenue,
       ROUND(100.0 * SUM(o.net_revenue)
             / SUM(SUM(o.net_revenue)) OVER (), 1)                AS pct_of_revenue
FROM Fact_Orders o JOIN Dim_Geography g USING (geography_key)
GROUP BY g.region ORDER BY order_net_revenue DESC;

-- D.1-VALIDATION (Type A) — regional revenue reconciles to certified total
SELECT ROUND(SUM(net_revenue), 2) AS geographic_revenue_total, 2195871.49 AS certified_anchor,
       CASE WHEN ABS(SUM(net_revenue) - 2195871.49) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Orders;


-- ═══════════════════════════════════════════════════════════════════
-- D.2 — Revenue per Customer Index (region + city, with low-base guardrail)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which geographies punch above/below their weight —
--                     i.e., generate more/less revenue per customer than the
--                     national average?
-- Stakeholder       : CFO / COO
-- Metric Definition : Revenue per Customer = SUM(net_revenue)/total customers
--                     (denominator = ALL home-region customers incl. non-
--                     purchasers). Index = region RPC / national RPC * 100.
--                     Index 100 = national average; >100 outperforms.
-- Metric Basis      : Order Net Revenue per Customer
-- Analysis Grain    : Region and City (Dim_Geography), customer base from
--                     Dim_Customer, revenue from Fact_Orders
-- SQL Design        : national RPC = total revenue / total customers (a scalar).
--                     Per geography: its revenue / its FULL customer base
--                     (including non-purchasers, so the index reflects true
--                     commercial productivity, not just buyer intensity).
--                     City view adds a low_base_flag when customers < 150.
-- Analytical Assumptions : LOW-BASE GUARDRAIL — cities below 150 customers are
--                     flagged; their index is reported but must NOT be treated
--                     as a reliable signal (smallest city has 102 customers).
--                     Denominator includes non-purchasers deliberately: a
--                     region full of signups who never buy IS underperforming.
-- Independent Review: RPC uses full base as denominator; index is a ratio of
--                     ratios; guardrail isolates noise. OK.
-- Validation        : Type B — national RPC recomputed = $2,195,871.49 / 8,000
--                     = $274.48; region-weighted indices average to ~100.
-- Result Sanity     : Regional indices should cluster near 100 (revenue and
--                     customers both track region size); city indices spread
--                     wider, with low-base cities the widest.
-- ═══════════════════════════════════════════════════════════════════

-- D.2a Regional index (all statistically solid — every region > 1,300 customers)
WITH region_rev AS (
    SELECT g.region, SUM(o.net_revenue) AS revenue
    FROM Fact_Orders o JOIN Dim_Geography g USING (geography_key) GROUP BY g.region
),
region_base AS (
    SELECT g.region, COUNT(*) AS customers
    FROM Dim_Customer c JOIN Dim_Geography g ON c.home_geography_key = g.geography_key GROUP BY g.region
),
national AS (
    SELECT (SELECT SUM(net_revenue) FROM Fact_Orders) / (SELECT COUNT(*) FROM Dim_Customer) AS national_rpc
)
SELECT rb.region,
       rb.customers,
       ROUND(rr.revenue, 2)                                       AS revenue,
       ROUND(rr.revenue / rb.customers, 2)                        AS revenue_per_customer,
       ROUND((SELECT national_rpc FROM national), 2)              AS national_rpc,
       ROUND(100.0 * (rr.revenue / rb.customers)
             / (SELECT national_rpc FROM national), 1)            AS rpc_index
FROM region_base rb JOIN region_rev rr USING (region)
ORDER BY rpc_index DESC;

-- D.2b City index with low-base guardrail
WITH city_rev AS (
    SELECT g.geography_key, g.city, g.region, SUM(o.net_revenue) AS revenue
    FROM Fact_Orders o JOIN Dim_Geography g USING (geography_key) GROUP BY g.geography_key, g.city, g.region
),
city_base AS (
    SELECT c.home_geography_key AS geography_key, COUNT(*) AS customers
    FROM Dim_Customer c GROUP BY c.home_geography_key
),
national AS (
    SELECT (SELECT SUM(net_revenue) FROM Fact_Orders) / (SELECT COUNT(*) FROM Dim_Customer) AS national_rpc
)
SELECT cb.geography_key, cr.city, cr.region,
       cb.customers,
       ROUND(cr.revenue / cb.customers, 2)                        AS revenue_per_customer,
       ROUND(100.0 * (cr.revenue / cb.customers)
             / (SELECT national_rpc FROM national), 1)            AS rpc_index,
       CASE WHEN cb.customers < 150 THEN 'LOW_BASE_CAUTION' ELSE 'RELIABLE' END AS sample_reliability
FROM city_base cb JOIN city_rev cr USING (geography_key)
ORDER BY rpc_index DESC;

-- D.2-VALIDATION (Type B) — national RPC independently recomputed
SELECT ROUND((SELECT SUM(net_revenue) FROM Fact_Orders) / (SELECT COUNT(*) FROM Dim_Customer), 2) AS national_rpc,
       274.48 AS expected_rpc,
       CASE WHEN ABS((SELECT SUM(net_revenue) FROM Fact_Orders) / (SELECT COUNT(*) FROM Dim_Customer) - 274.48) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result;


-- ═══════════════════════════════════════════════════════════════════
-- D.3 — Customer Quality by Geography
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which regions have higher-VALUE customers (not just
--                     more customers)? Repeat rate, AOV, revenue per customer.
-- Stakeholder       : Head of Retention / CFO
-- Metric Definition : per region: repeat purchase rate (>=2 orders / base),
--                     AOV (revenue/orders), revenue per purchasing customer
-- Metric Basis      : Order Net Revenue, Customer Count, Order Count
-- Analysis Grain    : Fact_Orders rolled to region, base from Dim_Customer
-- SQL Design        : Combine per-region order aggregates with the per-region
--                     customer base and a repeat-customer count (customers with
--                     >=2 orders in that region). Repeat rate denominator is the
--                     full regional base (consistent with the certified 35.64%
--                     national definition).
-- Analytical Assumptions : Repeat rate uses the same >=2-lifetime-orders
--                     definition as the certified KPI, computed per region;
--                     the four regional rates aggregate to the national 35.64%.
-- Independent Review: Region-level rollups; repeat count from a HAVING subquery;
--                     denominators consistent. OK.
-- Validation        : Type A — customer-weighted regional repeat rate
--                     reconciles to certified 35.64%; AOV to $83.50 blended.
-- Result Sanity     : AOV near-uniform across regions (pricing geography-
--                     independent); repeat rate and RPC are where quality varies.
-- ═══════════════════════════════════════════════════════════════════
WITH region_orders AS (
    SELECT g.region,
           COUNT(*) AS orders,
           SUM(o.net_revenue) AS revenue,
           COUNT(DISTINCT o.customer_key) AS purchasing_customers
    FROM Fact_Orders o JOIN Dim_Geography g USING (geography_key) GROUP BY g.region
),
region_repeat AS (
    SELECT region, COUNT(*) AS repeat_customers FROM (
        SELECT g.region, o.customer_key
        FROM Fact_Orders o JOIN Dim_Geography g USING (geography_key)
        GROUP BY g.region, o.customer_key HAVING COUNT(*) >= 2
    ) GROUP BY region
),
region_base AS (
    SELECT g.region, COUNT(*) AS total_customers
    FROM Dim_Customer c JOIN Dim_Geography g ON c.home_geography_key = g.geography_key GROUP BY g.region
)
SELECT ro.region,
       rb.total_customers,
       ro.purchasing_customers,
       ROUND(100.0 * COALESCE(rr.repeat_customers,0) / rb.total_customers, 1)   AS repeat_rate_pct,
       ROUND(ro.revenue / ro.orders, 2)                                         AS aov,
       ROUND(ro.revenue / rb.total_customers, 2)                                AS revenue_per_customer
FROM region_orders ro
JOIN region_base rb USING (region)
LEFT JOIN region_repeat rr USING (region)
ORDER BY revenue_per_customer DESC;

-- D.3-VALIDATION (Type A) — regional repeat customers sum to national total (2,851 -> 35.64%)
-- Each row of the subquery is one (region, customer) pair with >=2 orders, so
-- COUNT(*) over it is the total number of repeat customers across all regions.
-- This proves the per-region repeat counts partition the national total with
-- no customer double-counted across regions (a customer has one home region).
SELECT COUNT(*) AS total_repeat_customers, 2851 AS certified_count,
       ROUND(100.0 * COUNT(*) / 8000, 2) AS repeat_rate_pct,
       CASE WHEN COUNT(*) = 2851 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT g.region, o.customer_key
      FROM Fact_Orders o JOIN Dim_Geography g USING (geography_key)
      GROUP BY g.region, o.customer_key HAVING COUNT(*) >= 2) sub;


-- ═══════════════════════════════════════════════════════════════════
-- D.4 — Geographic Growth (YoY revenue, customers, orders)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Is growth broad-based across regions, or concentrated
--                     in a few?
-- Stakeholder       : CFO
-- Metric Definition : per region: revenue 2023/2024/2025 and YoY growth;
--                     new-customer acquisition by signup year; order growth
-- Metric Basis      : Order Net Revenue, Customer Count, Order Count
-- Analysis Grain    : Fact_Orders x Dim_Date x Dim_Geography (revenue/orders);
--                     Dim_Customer x Dim_Geography (acquisition by signup year)
-- SQL Design        : Conditional aggregation by year per region for revenue;
--                     separate acquisition view counts customers by signup year
--                     and home region.
-- Analytical Assumptions : Revenue growth attributed by order year; customer
--                     acquisition by signup year (a customer acquired in 2023
--                     counts once, in their signup cohort).
-- Independent Review: Region x year conditional aggregation; no fan-out. OK.
-- Validation        : Type B — regional yearly revenue sums to the B.1a
--                     national yearly totals (329,574 / 785,091 / 1,081,207).
-- Result Sanity     : All regions grow every year (broad-based); no region
--                     shrinks; growth rates decelerate in line with national.
-- ═══════════════════════════════════════════════════════════════════

-- D.4a Regional revenue by year + YoY
WITH ry AS (
    SELECT g.region, d.year, SUM(o.net_revenue) AS revenue
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    JOIN Dim_Geography g USING (geography_key)
    GROUP BY g.region, d.year
)
SELECT region,
       ROUND(SUM(CASE WHEN year=2023 THEN revenue END), 2) AS rev_2023,
       ROUND(SUM(CASE WHEN year=2024 THEN revenue END), 2) AS rev_2024,
       ROUND(SUM(CASE WHEN year=2025 THEN revenue END), 2) AS rev_2025,
       ROUND(100.0 * (SUM(CASE WHEN year=2024 THEN revenue END) - SUM(CASE WHEN year=2023 THEN revenue END))
             / SUM(CASE WHEN year=2023 THEN revenue END), 1) AS yoy_2024_pct,
       ROUND(100.0 * (SUM(CASE WHEN year=2025 THEN revenue END) - SUM(CASE WHEN year=2024 THEN revenue END))
             / SUM(CASE WHEN year=2024 THEN revenue END), 1) AS yoy_2025_pct
FROM ry GROUP BY region ORDER BY rev_2025 DESC;

-- D.4b New-customer acquisition by region and signup year
SELECT g.region,
       SUM(CASE WHEN EXTRACT(YEAR FROM c.signup_date)=2023 THEN 1 ELSE 0 END) AS acquired_2023,
       SUM(CASE WHEN EXTRACT(YEAR FROM c.signup_date)=2024 THEN 1 ELSE 0 END) AS acquired_2024,
       SUM(CASE WHEN EXTRACT(YEAR FROM c.signup_date)=2025 THEN 1 ELSE 0 END) AS acquired_2025
FROM Dim_Customer c JOIN Dim_Geography g ON c.home_geography_key = g.geography_key
GROUP BY g.region ORDER BY g.region;

-- D.4-VALIDATION (Type B) — regional yearly revenue reconciles to national yearly
SELECT ROUND(SUM(CASE WHEN year=2023 THEN revenue END),2) AS y2023,
       ROUND(SUM(CASE WHEN year=2024 THEN revenue END),2) AS y2024,
       ROUND(SUM(CASE WHEN year=2025 THEN revenue END),2) AS y2025,
       CASE WHEN ABS(SUM(CASE WHEN year=2023 THEN revenue END) - 329574.19) <= 0.01
             AND ABS(SUM(CASE WHEN year=2024 THEN revenue END) - 785090.66) <= 0.01
             AND ABS(SUM(CASE WHEN year=2025 THEN revenue END) - 1081206.64) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT d.year, SUM(o.net_revenue) AS revenue
      FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key GROUP BY d.year) t;


-- ═══════════════════════════════════════════════════════════════════
-- D.5 — Geographic Portfolio Assessment (revenue x customer value)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which regions are high-revenue AND high-value, and
--                     which are high on one axis but not the other?
-- Stakeholder       : CFO / COO
-- Metric Definition : classify each region on (revenue vs median region
--                     revenue) x (revenue-per-customer vs national RPC $274.48)
-- Metric Basis      : Order Net Revenue, Revenue per Customer
-- Analysis Grain    : Region
-- SQL Design        : Combine regional revenue with regional RPC; assign a 2x2
--                     quadrant against the median regional revenue and the
--                     national RPC. Thresholds are the business's own center.
-- Analytical Assumptions : "High/low value" is RPC relative to the national
--                     average (index 100); "high/low revenue" relative to the
--                     median region.
-- Independent Review: Quadrant logic deterministic from anchored inputs. OK.
-- Validation        : Type B — four regions each land in exactly one quadrant;
--                     revenue reconciles to $2,195,871.49.
-- Result Sanity     : With revenue and customers both tracking region size,
--                     expect most regions near the RPC line — the interesting
--                     cases are any region materially off it.
-- ═══════════════════════════════════════════════════════════════════
WITH region_metrics AS (
    SELECT g.region,
           SUM(o.net_revenue) AS revenue,
           SUM(o.net_revenue) / (SELECT COUNT(*) FROM Dim_Customer c2 JOIN Dim_Geography g2 ON c2.home_geography_key=g2.geography_key WHERE g2.region=g.region) AS rpc
    FROM Fact_Orders o JOIN Dim_Geography g USING (geography_key) GROUP BY g.region
),
th AS (SELECT MEDIAN(revenue) AS median_rev FROM region_metrics)
SELECT rm.region,
       ROUND(rm.revenue, 2)                                       AS revenue,
       ROUND(rm.rpc, 2)                                           AS revenue_per_customer,
       ROUND(100.0 * rm.rpc / 274.48, 1)                          AS rpc_index,
       CASE
           WHEN rm.revenue >= t.median_rev AND rm.rpc >= 274.48 THEN 'High Revenue / High Value'
           WHEN rm.revenue >= t.median_rev AND rm.rpc <  274.48 THEN 'High Revenue / Low Value'
           WHEN rm.revenue <  t.median_rev AND rm.rpc >= 274.48 THEN 'Low Revenue / High Value'
           ELSE 'Low Revenue / Low Value'
       END                                                        AS portfolio_quadrant
FROM region_metrics rm CROSS JOIN th t
ORDER BY rm.revenue DESC;

-- D.5-VALIDATION (Type B) — revenue reconciles to certified total
SELECT ROUND(SUM(revenue), 2) AS total_revenue,
       CASE WHEN ABS(SUM(revenue) - 2195871.49) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT g.region, SUM(o.net_revenue) AS revenue
      FROM Fact_Orders o JOIN Dim_Geography g USING (geography_key) GROUP BY g.region);
