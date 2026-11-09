# Data dictionary: WA Resources Data Warehouse

Database `WA_RESOURCES` in Snowflake. Built by the scripts in `sql/` (run in order 01 → 05).
Design decisions: [`model_design.md`](model_design.md).

**How to read the NULL column:** NULL never means zero. It always means "no published number", and the reason is given. Where zero is a real value (nothing was produced), the source shows 0 and so does the warehouse.

## How to answer a question with this model

1. **Which number?** → the fact table (sales, royalties or jobs).
2. **Split by what?** → the dimension (commodity, group, year).
3. **Which grain?** → if you need more than one fact, sum each to commodity group × year first, then join on the keys. Or use `v_group_year_summary`, which already does this.

```
                    dim_financial_year
                 ╱          │           ╲
fact_commodity_sales   fact_royalties   fact_employment
         │                  │                 │
   dim_commodity ────▶ dim_commodity_group ◀──┘
```

---

## Schema STAR

### dim_commodity_group

**One row =** one shared commodity group · **Rows:** 10 · **Source:** distinct `commodity_group` in `raw.raw_commodity_mapping`

| Column | Type | Description | Example | NULL? |
|---|---|---|---|---|
| commodity_group_key | NUMBER | Surrogate key, 1–10 in alphabetical order of the name | 5 | Never |
| commodity_group | VARCHAR | Standard group name used by all three facts | Iron Ore | Never |

**Values:** Alumina & Bauxite · Copper-Lead-Zinc · Diamonds · Gold · Iron Ore · Lithium · Mineral Sands · Nickel · Other · Petroleum
**Used by:** `dim_commodity`, `fact_royalties`, `fact_employment`
**Note:** "Other" means the same in every fact: all small minerals (coal, salt, construction materials, manganese, rare earths, …). Petroleum is kept separate because it's too large to hide in Other.

### dim_financial_year

**One row =** one Australian financial year (1 July – 30 June) · **Rows:** 42 (1983-84 to 2024-25) · **Source:** every `financial_year` found in any RAW table (UNION)

| Column | Type | Description | Example | NULL? |
|---|---|---|---|---|
| year_key | NUMBER | The calendar year the FY **ends** in | 2025 | Never |
| financial_year | VARCHAR | Label as used in the source | 2024-25 | Never |
| fy_start_date | DATE | 1 July of the first year | 2024-07-01 | Never |
| fy_end_date | DATE | 30 June of the second year | 2025-06-30 | Never |

**Used by:** all three facts
**Note:** the facts cover different ranges: sales 2003-04 →, employment 2001-02 →, royalties 1983-84 →. Compare across facts only from **2003-04**.

### dim_commodity

**One row =** one commodity as listed in the sales sheet · **Rows:** 46 · **Source:** distinct `commodity`, `unit` in `raw.raw_sales`, mapped via `raw.raw_commodity_mapping` (sheet `sales`)

| Column | Type | Description | Example | NULL? |
|---|---|---|---|---|
| commodity_key | NUMBER | Surrogate key, alphabetical by name | 18 | Never |
| commodity_name | VARCHAR | Name exactly as in the source, trimmed. Capitals mark a standalone commodity (e.g. `GOLD`); mixed case marks one within a group (e.g. `Alumina`) | IRON ORE | Never |
| unit | VARCHAR | Unit of `quantity`: `t`, `kg`, `ct` (carats), `kl` (kilolitres), `'000m3` | t | Only for *Other Construcion Materials* (no unit in the source; spelling as in the source) |
| commodity_group_key | NUMBER | → `dim_commodity_group` | 5 | Never (tested in `04_checks.sql`) |

**Used by:** `fact_commodity_sales`

### fact_commodity_sales

**One row =** one commodity × one financial year · **Rows:** 1,012 (46 × 22, 2003-04 to 2024-25) · **Source:** `raw.raw_sales` ← sheet *Q&V FY 2003-04 to Now*, major commodities file

| Column | Type | Description | Example | NULL? |
|---|---|---|---|---|
| commodity_key | NUMBER | → `dim_commodity` | 18 | Never |
| year_key | NUMBER | → `dim_financial_year` | 2025 | Never |
| quantity | NUMBER(38,4) | Amount sold, **in the commodity's unit** (`dim_commodity.unit`) | 853,000,000 | 85 rows: not published in the source |
| value_aud | NUMBER(38,4) | Sales value, A$, nominal | 125,814,424,257 | 87 rows: 68 `nfp` (confidential) + 19 blank in the source |

**Rules:**
- **Never sum `quantity` across commodities**: the units differ. Sum `value_aud` instead.
- **0 ≠ NULL:** 103 rows have `value_aud = 0` (nothing sold that year). NULL means the value exists but isn't published.
- Group totals that include `nfp` values are **lower bounds** (Tin & Tantalum, Mineral Sands, Other).

### fact_royalties

**One row =** one commodity group × one financial year · **Rows:** 420 (10 × 42, 1983-84 to 2024-25) · **Source:** `raw.raw_royalties` ← sheet *Royalties Historic*, economic indicators file

| Column | Type | Description | Example | NULL? |
|---|---|---|---|---|
| commodity_group_key | NUMBER | → `dim_commodity_group` | 5 | Never |
| year_key | NUMBER | → `dim_financial_year` | 2025 | Never |
| royalty_aud_m | NUMBER | Royalty revenue to the WA State, **A$ million**, nominal | 8,616.69 | 87 rows: `n/a` in the source (not reported separately): Copper-Lead-Zinc to 2012-13, Lithium to 2015-16, Mineral Sands to 2006-07 |

**Rules:**
- **Royalties are not company revenue.** They're payments to the State, a small share of sales value.
- **Petroleum = Petroleum royalties + North West Shelf grants** (Commonwealth payments for offshore petroleum), summed into one row. So yearly totals match the source's *Total Royalty Revenue*, not *Total Royalty Receipts*.
- In millions, while `fact_commodity_sales.value_aud` is in dollars. Convert before comparing.

### fact_employment

**One row =** one commodity group × one financial year · **Rows:** 216 (9 × 24, 2001-02 to 2024-25) · **Source:** `raw.raw_employment` ← sheet *Mining Employment FY*, economic indicators file

| Column | Type | Description | Example | NULL? |
|---|---|---|---|---|
| commodity_group_key | NUMBER | → `dim_commodity_group` | 5 | Never |
| year_key | NUMBER | → `dim_financial_year` | 2025 | Never |
| fte | NUMBER | Mining jobs, full-time equivalent | 65,637.13 | Never |

**Rules:**
- **Petroleum has no rows** (9 groups, not 10): the source covers mining only. In `v_group_year_summary` its `fte` therefore shows as NULL.
- **Mineral exploration jobs are excluded**, so yearly totals match the source's *Total Mining*.
- Coal, Salt, Construction Materials and Other are summed into **Other**.

### v_group_year_summary (view)

**One row =** one commodity group × one financial year · **Rows:** 220 (10 × 22, 2003-04 to 2024-25) · **Built by:** `sql/05_analysis.sql`. Each fact is summed to group × year, then joined ("drilling across").

| Column | Type | Description | NULL? |
|---|---|---|---|
| financial_year | VARCHAR | e.g. 2024-25 | Never |
| commodity_group | VARCHAR | Group name | Never |
| sales_aud_bn | NUMBER | Sales value, **A$ billion** | Never (nfp values count as missing, so this is a lower bound) |
| royalty_aud_m | NUMBER | Royalty revenue, **A$ million** | When royalties weren't reported separately (see `fact_royalties`) |
| fte | NUMBER | Mining jobs | Always for Petroleum |
| sales_per_fte_aud_m | NUMBER | Sales per job, **A$ million** | When `fte` is NULL |
| sales_share_pct | NUMBER | % of that year's total sales | Never |
| fte_share_pct | NUMBER | % of that year's mining jobs (Petroleum excluded) | When `fte` is NULL |
| royalty_share_pct | NUMBER | % of that year's royalty revenue | When `royalty_aud_m` is NULL |

---

## Schema RAW

Loaded unchanged from the CSVs by `sql/02_raw_load.sql`. Not for analysis: use STAR.

| Table | One row = | Rows | Columns | From |
|---|---|---|---|---|
| raw_sales | commodity × year | 1,012 | commodity, unit, financial_year, quantity, value_aud | `01_Raw/raw_sales.csv` |
| raw_royalties | source name × year | 462 | source_name, financial_year, royalty_aud_m | `01_Raw/raw_royalties.csv` |
| raw_employment | source name × year | 288 | source_name, financial_year, fte | `01_Raw/raw_employment.csv` |
| raw_commodity_mapping | source name × sheet | 69 | source_sheet (`sales` / `royalties` / `employment`), source_name, commodity_group | `03_Mapping/commodity_group_mapping.csv` |

**Mapping rule:** every `source_name` must match the source sheet **exactly**, and every `commodity_group` must be one of the 10 values above. A new name in next year's file will show up as a NULL `commodity_group_key` in `dim_commodity` (tested in `04_checks.sql`).
