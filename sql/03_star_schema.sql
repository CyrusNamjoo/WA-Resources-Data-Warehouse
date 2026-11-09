-- ============================================================
-- 03_star_schema.sql: build the star schema from the RAW layer (the "T" in ELT)
-- Model: galaxy schema, 3 facts sharing 2 dimensions (see docs/model_design.md)
--
--   dim_commodity_group  10 rows   (the conformed groups)
--   dim_financial_year   42 rows   (1983-84 .. 2024-25)
--   dim_commodity        46 rows   (sales commodities -> group)
--   fact_commodity_sales 1,012 rows (commodity x year)
--   fact_royalties       420 rows   (10 groups x 42 years)
--   fact_employment      216 rows   (9 groups x 24 years; no Petroleum in the source)
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE wa_wh;
USE SCHEMA wa_resources.star;

-- ---------------- Dimensions ----------------

-- 10 shared groups, with a surrogate key (1..10, alphabetical)
CREATE OR REPLACE TABLE dim_commodity_group AS
SELECT
    ROW_NUMBER() OVER (ORDER BY commodity_group) AS commodity_group_key,
    commodity_group
FROM (
    SELECT DISTINCT commodity_group
    FROM wa_resources.raw.raw_commodity_mapping
) g;

-- Every financial year in any source. Smart key = the year the FY ends in (2003-04 -> 2004).
-- Australian FY: 1 July to 30 June. UNION removes duplicate years.
CREATE OR REPLACE TABLE dim_financial_year AS
SELECT
    TO_NUMBER(LEFT(financial_year, 4)) + 1                         AS year_key,
    financial_year,
    DATE_FROM_PARTS(TO_NUMBER(LEFT(financial_year, 4)),     7,  1) AS fy_start_date,
    DATE_FROM_PARTS(TO_NUMBER(LEFT(financial_year, 4)) + 1, 6, 30) AS fy_end_date
FROM (
    SELECT financial_year FROM wa_resources.raw.raw_sales
    UNION
    SELECT financial_year FROM wa_resources.raw.raw_royalties
    UNION
    SELECT financial_year FROM wa_resources.raw.raw_employment
) y;

-- One row per sales commodity with its unit and group.
-- source_sheet filter: the same name (e.g. Gold) also appears in the royalties/employment mapping.
-- LEFT JOINs: an unmapped commodity shows up as a NULL key instead of disappearing.
CREATE OR REPLACE TABLE dim_commodity AS
SELECT
    ROW_NUMBER() OVER (ORDER BY s.commodity) AS commodity_key,
    s.commodity                              AS commodity_name,
    s.unit,
    g.commodity_group_key
FROM (
    SELECT DISTINCT commodity, unit
    FROM wa_resources.raw.raw_sales
) s
LEFT JOIN wa_resources.raw.raw_commodity_mapping m
       ON m.source_name  = s.commodity
      AND m.source_sheet = 'sales'
LEFT JOIN dim_commodity_group g
       ON g.commodity_group = m.commodity_group;

-- ---------------- Facts: keys + numbers only ----------------

-- Grain: one commodity x one financial year
CREATE OR REPLACE TABLE fact_commodity_sales AS
SELECT
    c.commodity_key,
    y.year_key,
    s.quantity,          -- in the commodity's unit (dim_commodity.unit): never sum across commodities
    s.value_aud          -- NULL where the source says nfp (confidential)
FROM wa_resources.raw.raw_sales s
JOIN dim_commodity c      ON c.commodity_name = s.commodity
JOIN dim_financial_year y ON y.financial_year = s.financial_year;

-- Grain: one commodity group x one financial year.
-- SUM + GROUP BY: two source rows (Petroleum, North West Shelf Grants) share one group.
-- SUM ignores NULLs; a group with only n/a stays NULL, never 0.
CREATE OR REPLACE TABLE fact_royalties AS
SELECT
    g.commodity_group_key,
    y.year_key,
    SUM(r.royalty_aud_m) AS royalty_aud_m
FROM wa_resources.raw.raw_royalties r
JOIN wa_resources.raw.raw_commodity_mapping m
  ON m.source_name  = r.source_name
 AND m.source_sheet = 'royalties'
JOIN dim_commodity_group g ON g.commodity_group = m.commodity_group
JOIN dim_financial_year y  ON y.financial_year  = r.financial_year
GROUP BY g.commodity_group_key, y.year_key;

-- Grain: one commodity group x one financial year.
-- Coal, Salt, Construction Materials and Other all sum into 'Other'.
CREATE OR REPLACE TABLE fact_employment AS
SELECT
    g.commodity_group_key,
    y.year_key,
    SUM(e.fte) AS fte
FROM wa_resources.raw.raw_employment e
JOIN wa_resources.raw.raw_commodity_mapping m
  ON m.source_name  = e.source_name
 AND m.source_sheet = 'employment'
JOIN dim_commodity_group g ON g.commodity_group = m.commodity_group
JOIN dim_financial_year y  ON y.financial_year  = e.financial_year
GROUP BY g.commodity_group_key, y.year_key;
