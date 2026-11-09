-- ============================================================
-- 05_analysis.sql: answer the stakeholder question
-- "Which commodities drive WA's resource sales, royalties and jobs,
--  and how has that changed over 20 years?"
--
-- View:  star.v_group_year_summary
-- Grain: one commodity group x one financial year
--        10 groups x 22 years (2003-04 .. 2024-25) = 220 rows
--
-- Method: "drilling across". Each fact is first brought to the same grain
-- (group x year), then joined on the shared dimension keys.
-- Fact tables are never joined to each other at their own grain (fan-out).
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE wa_wh;
USE SCHEMA wa_resources.star;

CREATE OR REPLACE VIEW v_group_year_summary AS

WITH sales_by_group AS (
    -- Sales is at commodity level: sum it up to group level first
    SELECT
        c.commodity_group_key,
        f.year_key,
        SUM(f.value_aud) AS sales_aud
    FROM fact_commodity_sales f
    JOIN dim_commodity c ON c.commodity_key = f.commodity_key
    GROUP BY c.commodity_group_key, f.year_key
)

SELECT
    y.financial_year,
    g.commodity_group,
    s.sales_aud / 1e9                     AS sales_aud_bn,
    r.royalty_aud_m,
    e.fte,
    -- NULLIF: no division by zero; Petroleum has no FTE in the source -> NULL
    s.sales_aud / NULLIF(e.fte, 0) / 1e6  AS sales_per_fte_aud_m,

    -- Share of the same year's total (window function, rows are not merged)
    100 * s.sales_aud     / SUM(s.sales_aud)     OVER (PARTITION BY s.year_key) AS sales_share_pct,
    100 * e.fte           / SUM(e.fte)           OVER (PARTITION BY s.year_key) AS fte_share_pct,
    100 * r.royalty_aud_m / SUM(r.royalty_aud_m) OVER (PARTITION BY s.year_key) AS royalty_share_pct

-- Start from sales: it has all 10 groups and all 22 years.
-- LEFT JOINs keep Petroleum (no FTE) and years where a royalty is n/a.
FROM sales_by_group s
JOIN dim_commodity_group g ON g.commodity_group_key = s.commodity_group_key
JOIN dim_financial_year  y ON y.year_key            = s.year_key
LEFT JOIN fact_royalties  r
       ON r.commodity_group_key = s.commodity_group_key
      AND r.year_key            = s.year_key
LEFT JOIN fact_employment e
       ON e.commodity_group_key = s.commodity_group_key
      AND e.year_key            = s.year_key;


-- ============================================================
-- Checks and the comparison used in the findings memo
-- ============================================================

-- Expected: 220
SELECT COUNT(*) FROM v_group_year_summary;

-- First vs last year. Expected 2024-25 Iron Ore:
-- sales 125.81 bn | royalty 8,616.69 m | FTE 65,637 | 1.92 m per FTE | shares 56.25 / 48.77 / 81.23
SELECT *
FROM v_group_year_summary
WHERE financial_year IN ('2003-04', '2024-25')
ORDER BY financial_year DESC, sales_aud_bn DESC;
