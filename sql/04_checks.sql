-- ============================================================
-- 04_checks.sql: reconcile the star schema with the source sheets
-- The extract dropped the sheets' TOTAL rows; those totals are the test.
-- Run after 03_star_schema.sql. Every check states its expected result.
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE wa_wh;
USE SCHEMA wa_resources.star;

-- check 0: row counts and keys
-- expected: dim_commodity_group 10 | dim_financial_year 42 | dim_commodity 46 |
--           fact_commodity_sales 1012 | fact_royalties 420 | fact_employment 216 |
--           commodities without a group 0
SELECT 'dim_commodity_group' AS tbl, COUNT(*) AS rows_ FROM dim_commodity_group
UNION ALL SELECT 'dim_financial_year',   COUNT(*) FROM dim_financial_year
UNION ALL SELECT 'dim_commodity',        COUNT(*) FROM dim_commodity
UNION ALL SELECT 'fact_commodity_sales', COUNT(*) FROM fact_commodity_sales
UNION ALL SELECT 'fact_royalties',       COUNT(*) FROM fact_royalties
UNION ALL SELECT 'fact_employment',      COUNT(*) FROM fact_employment
UNION ALL SELECT 'commodities without a group', COUNT(*) FROM dim_commodity WHERE commodity_group_key IS NULL;

------------------------------------------------------
-- check 1: sales value per year = sheet "TOTAL MINERALS AND PETROLEUM"
-- expected: 2003-04 = 26,487,353,901.12  (exact match)
--           2024-25 = 223,661,699,394.82 (sheet 223,711,479,151.82 minus 49,779,757)
-- The 2024-25 gap equals the sheet's "TOTAL TIN AND TANTALUM": Tin and Tantalum are
-- nfp (confidential) individually, so they are NULL here. The gap is fully explained.
SELECT
    y.financial_year,
    SUM(f.value_aud) AS total_value_aud
FROM fact_commodity_sales f
JOIN dim_financial_year y
    ON y.year_key = f.year_key
WHERE y.financial_year IN ('2003-04', '2024-25')
GROUP BY y.financial_year
ORDER BY y.financial_year;

------------------------------------------------------
-- check 2: royalties per year = sheet "Total Royalty Revenue"
-- (includes North West Shelf Grants; "Total Royalty Receipts" excludes them)
-- expected: 2003-04 = 1,033.58 | 2024-25 = 10,607.64
SELECT
    y.financial_year,
    SUM(r.royalty_aud_m) AS total_royalty_revenue
FROM fact_royalties r
JOIN dim_financial_year y
    ON y.year_key = r.year_key
WHERE y.financial_year IN ('2003-04', '2024-25')
GROUP BY y.financial_year
ORDER BY y.financial_year;

------------------------------------------------------
-- check 3: mining FTE per year = sheet "Total Mining"
-- (mineral exploration jobs are excluded by design)
-- expected: 2003-04 = 46,119 | 2024-25 = 134,590.03
SELECT
    y.financial_year,
    SUM(e.fte) AS total_mining
FROM fact_employment e
JOIN dim_financial_year y
    ON y.year_key = e.year_key
WHERE y.financial_year IN ('2003-04', '2024-25')
GROUP BY y.financial_year
ORDER BY y.financial_year;
