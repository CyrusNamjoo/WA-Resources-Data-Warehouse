# Model design: WA Resources Data Warehouse

**Module 4 of the [[Job-Ad Practice Program]]** · Designed 5 Nov 2026 · Status: RAW layer loaded in Snowflake (9 Nov); star schema next
**Warehouse:** Snowflake (30-day trial, no credit card; start it only when the extract step is ready)

## Stakeholder question

> *Which commodities drive WA's resource sales, royalties and jobs, and how has that changed over 20 years?*
> e.g. sales value per mining job for iron ore vs gold.

Written as for an analyst at a WA government department or a mining company's strategy team.

## Sources

All from the WA Department of Mines (DMPE), [Resources industry data](https://www.wa.gov.au/organisation/department-of-mines-petroleum-and-exploration/resources-industry-data), 2025 files, in `00_Original/`.

| Fact | File | Sheet | Years in sheet |
|---|---|---|---|
| Sales | `2025-major-commodities-data-file.xlsx` | `Q&V FY 2003-04 to Now` | 2003-04 → 2024-25 |
| Royalties | `2025-economic-indicators-data-file.xlsx` | `Royalties Historic` | 1983-84 → 2024-25 |
| Employment | `2025-economic-indicators-data-file.xlsx` | `Mining Employment FY` | 2001-02 → 2024-25 |

**Common window for comparisons: 2003-04 → 2024-25 (22 financial years).** Each fact table loads its full history; the window applies when comparing across tables.

## The model (galaxy / fact constellation schema)

```
                    dim_financial_year
                 ╱          │           ╲
fact_commodity_sales   fact_royalties   fact_employment
 (commodity × year)    (group × year)    (group × year)
         │                  │                 │
   dim_commodity ───→ dim_commodity_group ←───┘
                            ↑
                            └── fact_royalties
```

### Fact tables

| Table | Grain (one row =) | Keys | Measures |
|---|---|---|---|
| `fact_commodity_sales` | one commodity × one financial year | `commodity_key`, `year_key` | `quantity` (in the commodity's unit), `value_aud` |
| `fact_royalties` | one commodity group × one financial year | `commodity_group_key`, `year_key` | `royalty_aud_m` (A$ million) |
| `fact_employment` | one commodity group × one financial year | `commodity_group_key`, `year_key` | `fte` (full-time equivalent mining jobs) |

### Dimensions

| Table | One row = | Columns |
|---|---|---|
| `dim_commodity` | one commodity as listed in the sales sheet (45 rows), e.g. Alumina, Bauxite, Gold | `commodity_key`, `commodity_name`, `unit`, `commodity_group_key` |
| `dim_commodity_group` | one shared group (10 rows) | `commodity_group_key`, `commodity_group` |
| `dim_financial_year` | one financial year | `year_key`, `financial_year` (e.g. `2003-04`), `fy_start_date`, `fy_end_date` |

**Unit lives in `dim_commodity`**, not in the fact table: it describes the commodity and never changes from year to year.

## Conformed dimension: the 10 commodity groups

Every fact table must use the same group list, so the three can be compared.

| Group | Sales sheet (header or standalone row) | Royalties sheet | Employment sheet |
|---|---|---|---|
| Alumina & Bauxite | ALUMINA AND BAUXITE (Alumina, Bauxite) | Alumina | Alumina and Bauxite |
| Copper-Lead-Zinc | COPPER-LEAD-ZINC (Copper, Lead, Zinc Metal) | Copper, Lead & Zinc | Copper-Lead-Zinc |
| Diamonds | DIAMONDS | Diamonds | Diamond |
| Gold | GOLD | Gold | Gold |
| Iron Ore | IRON ORE | Iron Ore | Iron Ore |
| Lithium | LITHIUM (Spodumene, Lithium Hydroxide) | Lithium | Lithium |
| Mineral Sands | MINERAL SANDS (Garnet, Ilmenite, …) | Mineral Sands | Mineral Sands |
| Nickel | NICKEL | Nickel | Nickel |
| Petroleum | PETROLEUM (Condensate, Crude Oil, LNG, LPG, Domestic Gas) | Petroleum, North West Shelf Grants | *not in this sheet → NULL* |
| Other | everything else (Coal, Salt, Clays, Cobalt, Construction Materials, Manganese, Tin and Tantalum, …) | Other Minerals | Coal, Salt, Construction Materials, Other |

**Decisions**
- **"Other" means the same thing in all three tables.** More detailed rows (e.g. Coal and Salt in employment) are grouped into Other so comparisons are like-for-like.
- **Petroleum is its own group**, not part of Other. It's far larger than all small minerals together (LNG sales alone are tens of billions), so putting it in Other would make Other's "value per job" meaningless.
- **Petroleum employment is NULL, not 0.** The sheet covers mining only. (Petroleum employment exists in a separate sheet and could be added later.)
- **North West Shelf Grants → Petroleum.** They're petroleum-related payments to the State.
- The mapping will be stored as a small CSV (`source_sheet`, `source_name`, `commodity_group`) so it's visible and editable, not hidden in code.

## Cleaning rules (extract and transform)

The sheets are laid out for printing, not analysis.

| Problem | Rule |
|---|---|
| Years run across as columns | Unpivot: years go down as rows |
| Group header rows (e.g. `ALUMINA AND BAUXITE`) | Not data. Use them to fill `commodity_group` for the rows beneath |
| Total rows (`TOTAL …`, `Total Royalty Receipts`, `Total Mining`, …) | Drop. Totals are calculated in the warehouse, otherwise sums double |
| `Cumulative Total` column (sales, royalties) | Drop, for the same reason |
| `n/a` | NULL, never 0. "No data" isn't "zero" |
| `nfp` ("not for publication": hidden to protect confidential company figures) | NULL, never 0. 68 sales values across 7 commodities (Tin, Tantalum, Manganese, Rare Earths, Garnet, Chromite, Potash). Found when Snowflake rejected the load on 9 Nov. Group totals that include these are lower bounds |
| Text notes inside the data (e.g. "(May include Manganese, …)") | Drop |
| Inconsistent names (`Diamond` / `Diamonds`, `Copper, Lead & Zinc` / `Copper-Lead-Zinc`, trailing spaces like `PETROLEUM `) | Map through the mapping CSV; trim spaces |
| Mineral exploration rows in the employment sheet | Drop (not mining production jobs) |

## Rules for using the data

- **Never sum `quantity` across commodities.** Units differ (t, kg, ct, kl, '000 m³). Sum `value_aud` instead.
- **Value is nominal** (not adjusted for inflation). Comparisons over 20 years should say so.
- **Royalties are not revenue.** They're payments to the State, a fraction of sales value.

## Reconciliation checks to build

- Sum of `value_aud` per group and year = the sheet's `TOTAL …` rows (the dropped totals become the test).
- Sum of royalties per year = `Total Royalty Receipts` in the sheet.
- Sum of FTE per year = `Total Mining` in the sheet.
- 10 groups in `dim_commodity_group`; every fact row has a group (no NULL keys).

## Next steps

1. **Mapping CSV:** every source name → one of the 10 groups (Sirous writes it).
2. **Extract:** script that turns the 3 sheets into long CSVs (`raw_sales.csv`, `raw_royalties.csv`, `raw_employment.csv`).
3. **Start the Snowflake trial**, load RAW tables, and build the star schema with SQL (the "T" in ELT).
4. Reconciliation checks, handover README, Git.
