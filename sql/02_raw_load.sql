-- ============================================================
-- 02_raw_load.sql: load the extracted CSVs into the RAW layer
-- Input:  01_Raw/*.csv (from scripts/extract.py)
--         03_Mapping/commodity_group_mapping.csv
-- Steps:  1. run this file down to the tables
--         2. upload the 4 CSVs to @raw_stage
--            (Snowsight: Ingestion -> Load data into a stage -> RAW_STAGE)
--         3. run the COPY INTO statements and the checks
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE wa_wh;
USE SCHEMA wa_resources.raw;

-- How to read the CSVs: comma-separated, 1 header row, quoted text allowed
-- (one commodity name contains commas: "Other (may include Garnet, ...)")
CREATE OR REPLACE FILE FORMAT csv_format
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE;          -- n/a and nfp were written as empty -> NULL, never 0

-- Landing area for the files
CREATE OR REPLACE STAGE raw_stage
  FILE_FORMAT = csv_format;

-- One RAW table per CSV: same columns, same order, no cleaning
CREATE OR REPLACE TABLE raw_sales (
    commodity       VARCHAR,
    unit            VARCHAR,
    financial_year  VARCHAR,
    quantity        NUMBER(38, 4),
    value_aud       NUMBER(38, 4)
);

CREATE OR REPLACE TABLE raw_royalties (
    source_name     VARCHAR,
    financial_year  VARCHAR,
    royalty_aud_m   NUMBER(38, 4)
);

CREATE OR REPLACE TABLE raw_employment (
    source_name     VARCHAR,
    financial_year  VARCHAR,
    fte             NUMBER(38, 4)
);

CREATE OR REPLACE TABLE raw_commodity_mapping (
    source_sheet     VARCHAR,
    source_name      VARCHAR,
    commodity_group  VARCHAR
);

-- ---------- after uploading the files to @raw_stage ----------

LIST @raw_stage;    -- expected: 4 files

COPY INTO raw_sales             FROM @raw_stage/raw_sales.csv;
COPY INTO raw_royalties         FROM @raw_stage/raw_royalties.csv;
COPY INTO raw_employment        FROM @raw_stage/raw_employment.csv;
COPY INTO raw_commodity_mapping FROM @raw_stage/commodity_group_mapping.csv;

-- ============================================================
-- Checks. COUNT(column) skips NULLs, so with_value = real values.
-- Expected:  sales 1012 | 925   (87 NULL: 68 nfp + 19 blank)
--            royalties 462 | 349 (113 n/a)
--            employment 288 | 288
--            mapping 69 | 69
-- ============================================================
SELECT 'sales' AS tbl, COUNT(*) AS rows_, COUNT(value_aud) AS with_value FROM raw_sales
UNION ALL SELECT 'royalties',  COUNT(*), COUNT(royalty_aud_m)   FROM raw_royalties
UNION ALL SELECT 'employment', COUNT(*), COUNT(fte)             FROM raw_employment
UNION ALL SELECT 'mapping',    COUNT(*), COUNT(commodity_group) FROM raw_commodity_mapping;
