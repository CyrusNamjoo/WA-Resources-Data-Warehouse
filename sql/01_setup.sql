-- ============================================================
-- 01_setup.sql: WA Resources Data Warehouse (Snowflake)
-- Creates compute, database and schemas. Run once.
-- ============================================================

USE ROLE SYSADMIN;

-- Compute: smallest size, switches itself off after 60 seconds idle
-- (Snowflake charges for compute time, not for idle warehouses)
CREATE WAREHOUSE IF NOT EXISTS wa_wh
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

-- Storage
CREATE DATABASE IF NOT EXISTS wa_resources;
CREATE SCHEMA IF NOT EXISTS wa_resources.raw;    -- CSVs loaded as they are (the "L" in ELT)
CREATE SCHEMA IF NOT EXISTS wa_resources.star;   -- dimensions and facts (the "T" in ELT)

USE WAREHOUSE wa_wh;
USE SCHEMA wa_resources.raw;
