# WA Resources Data Warehouse (Snowflake)

A small data warehouse built in Snowflake from Western Australian Government resources data: sales, royalties and mining jobs by commodity, 1983-84 to 2024-25. ELT pipeline from printed-style Excel files to a reconciled star schema, plus an analysis view and findings memo.

**Built by:** Sirous Namjoo · Nov 2026 · personal practice project ([Job-Ad Practice Program](#why-this-project), Module 4: data modelling + cloud warehouse)

## The question

> *Which commodities drive WA's resource sales, royalties and jobs, and how has that changed over 20 years?*

**Answer in short** (full memo: [`docs/findings_memo.md`](docs/findings_memo.md)):
- Iron ore has replaced petroleum as the main source of value: **56% of sales** in 2024-25 (A$125.8bn), up from 20% in 2003-04.
- Iron ore brings in **81% of royalties**, so the State budget depends on it. Gold supports **27% of mining jobs** with only 13% of sales.
- Lithium grew from almost nothing to A$4.2bn; diamonds have almost disappeared.

## Pipeline

```
00_Original/*.xlsx  ──scripts/extract.py──▶  01_Raw/*.csv  ──COPY INTO──▶  RAW schema  ──SQL──▶  STAR schema  ──▶  v_group_year_summary
 (printed layout)      (unpivot, drop totals,     (long format)     (Snowflake)            (3 dims, 3 facts)      (analysis view)
                        n/a & nfp -> NULL)
                                              03_Mapping/commodity_group_mapping.csv ──▶ (conformed groups)
```

| Step | File | What it does |
|---|---|---|
| Extract | `scripts/extract.py` | Turns 3 Excel sheets into long CSVs: years from columns to rows, header/total rows dropped, `n/a` and `nfp` → NULL |
| Map | `03_Mapping/commodity_group_mapping.csv` | 69 source names (different spellings in each sheet) → 10 shared commodity groups |
| Setup | `sql/01_setup.sql` | Warehouse (X-Small, auto-suspend 60s), database, `raw` and `star` schemas |
| Load | `sql/02_raw_load.sql` | File format, stage, RAW tables, `COPY INTO`, row checks |
| Transform | `sql/03_star_schema.sql` | Dimensions and facts |
| Test | `sql/04_checks.sql` | Row counts, keys, and totals reconciled with the source sheets |
| Analyse | `sql/05_analysis.sql` | `v_group_year_summary`: the three facts side by side per group and year |

## The model (galaxy schema)

```
                    dim_financial_year (42)
                 ╱          │           ╲
fact_commodity_sales   fact_royalties   fact_employment
   (1,012 rows)          (420 rows)        (216 rows)
 commodity × year       group × year      group × year
         │                  │                 │
   dim_commodity (46) ─▶ dim_commodity_group (10) ◀┘
```

- **Conformed dimension:** each sheet spells commodities differently (`Diamond` / `Diamonds`, `Copper, Lead & Zinc` / `Copper-Lead-Zinc`). The mapping CSV turns them into 10 shared groups, so the three facts can be compared.
- **Drilling across:** facts are summed to the same grain (group × year) before being joined, so no rows are multiplied.
- Design decisions and cleaning rules: [`docs/model_design.md`](docs/model_design.md).

## Reconciliation

The extract drops the sheets' total rows; those totals are the test (`sql/04_checks.sql`).

| Check | Result |
|---|---|
| Sales 2003-04 vs *TOTAL MINERALS AND PETROLEUM* | Exact match: A$26,487,353,901.12 |
| Sales 2024-25 | A$49,779,757 lower, **exactly** the sheet's *TOTAL TIN AND TANTALUM* (both confidential individually) |
| Royalties vs *Total Royalty Revenue* | Exact match, both years |
| Mining FTE vs *Total Mining* | Exact match, both years |

## Limitations

1. **Confidential values (`nfp`):** 68 sales values across 7 small commodities are not published. They're NULL, not 0, so group totals for Tin & Tantalum, Mineral Sands and Other are lower bounds.
2. **Royalties = Total Royalty *Revenue***, which includes North West Shelf grants (Commonwealth payments for offshore petroleum). *Total Royalty Receipts* excludes them.
3. **No petroleum jobs:** the mining employment sheet doesn't cover petroleum, so its FTE is NULL. Mineral exploration jobs are also excluded.
4. **Nominal values:** not adjusted for inflation.
5. **Quantities use different units** (t, kg, ct, kl…): never sum `quantity` across commodities.
6. **"Other"** combines all small minerals (coal, salt, manganese, rare earths, …) so it means the same in all three facts.

## How to rebuild

1. `python scripts/extract.py` (needs `pandas`, `openpyxl`) → `01_Raw/*.csv`
2. In Snowflake, run `sql/01_setup.sql`, then `sql/02_raw_load.sql` down to the tables.
3. Upload the 3 raw CSVs and the mapping CSV to `@raw_stage` (Snowsight: Ingestion → Load data into a stage).
4. Run the rest of `02_raw_load.sql`, then `03`, `04` (all checks should match their expected values), and `05`.

## Data source

Western Australian Government, Department of Mines, Petroleum and Exploration: [Resources industry data](https://www.wa.gov.au/organisation/department-of-mines-petroleum-and-exploration/resources-industry-data), 2025 data files. Used here for practice and portfolio purposes.

## Why this project

Part of a self-directed program practising the work described in Perth data analyst job ads. Six of the sixteen ads asked for data modelling and a cloud warehouse (Snowflake or Fabric); this project is the practice for that skill.
