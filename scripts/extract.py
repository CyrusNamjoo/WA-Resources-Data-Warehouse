"""
Extract: WA Resources Data Warehouse

Turns three printed-style Excel sheets from the WA Department of Mines
into clean "long" CSVs (one row per name per financial year), ready to
load into the warehouse RAW layer.

    00_Original/*.xlsx  ->  01_Raw/raw_sales.csv
                            01_Raw/raw_royalties.csv
                            01_Raw/raw_employment.csv

Cleaning rules (see docs/model_design.md):
- years go from columns to rows (unpivot)
- group header rows, TOTAL rows, notes and "Cumulative Total" columns are dropped
- "n/a" becomes empty (NULL), never 0
- names are trimmed; mapping to commodity groups happens in the warehouse

Run from anywhere:  python scripts/extract.py
"""

from pathlib import Path

import pandas as pd

BASE = Path(__file__).resolve().parent.parent   # the project folder
SRC = BASE / "00_Original"
OUT = BASE / "01_Raw"

MAJOR_COMMODITIES = SRC / "2025-major-commodities-data-file.xlsx"
ECONOMIC_INDICATORS = SRC / "2025-economic-indicators-data-file.xlsx"


def extract_sales() -> pd.DataFrame:
    """Quantity and value per commodity per financial year (2003-04 onwards)."""
    df = pd.read_excel(MAJOR_COMMODITIES, sheet_name="Q&V FY 2003-04 to Now", header=None)

    # Column names are in Excel row 10 (index 9); data starts at Excel row 13 (index 12)
    data = df.iloc[12:].copy()
    data.columns = df.iloc[9].tolist()

    # Drop empty rows, TOTAL rows and the "(May include ...)" note
    data = data[data["COMMODITY"].notna()]
    name = data["COMMODITY"].astype(str)
    data = data[~name.str.startswith("TOTAL") & ~name.str.startswith("(May")]

    # Years from column names like "2003-04 Quantity"; skip "Cumulative Total"
    years = [c.replace(" Quantity", "") for c in data.columns
             if isinstance(c, str) and c.endswith(" Quantity") and not c.startswith("Cumulative")]

    # Drop group header rows: no unit AND no values
    # ("Other Construcion Materials" has no unit but does have values, so it stays)
    value_cols = [f"{y} Value $" for y in years]
    data = data[data["UNIT"].notna() | data[value_cols].notna().any(axis=1)]

    # Unpivot: one small table per year, stacked
    parts = [
        pd.DataFrame({
            "commodity": data["COMMODITY"].str.strip(),
            "unit": data["UNIT"],
            "financial_year": y,
            "quantity": data[f"{y} Quantity"],
            "value_aud": data[f"{y} Value $"],
        })
        for y in years
    ]
    sales = pd.concat(parts, ignore_index=True)

    # "nfp" (not for publication: hidden to protect confidential company figures)
    # and any other text -> empty (NULL), never 0. 68 values in the 2025 file.
    for col in ["quantity", "value_aud"]:
        sales[col] = pd.to_numeric(sales[col], errors="coerce")
    return sales



def extract_by_group(sheet: str, data_start: int, value_name: str) -> pd.DataFrame:
    """
    Generic extract for the economic-indicator sheets: one name column,
    financial years across. Used for royalties and employment.

    sheet       sheet name in the economic indicators file
    data_start  pandas index of the first data row (header is always index 7)
    value_name  name for the value column in the output
    """
    df = pd.read_excel(ECONOMIC_INDICATORS, sheet_name=sheet, header=None)

    data = df.iloc[data_start:].copy()
    data.columns = df.iloc[7].tolist()

    # Stop at the first "Total" row: below it are totals, mineral exploration
    # (employment) or a second calendar-year table (royalties)
    is_total = data["Commodity"].astype(str).str.startswith("Total")
    data = data.loc[: is_total.idxmax() - 1]
    data = data[data["Commodity"].notna()]

    # Year columns look like "1983-84"; this also skips "Cumulative Total"
    years = [c for c in data.columns
             if isinstance(c, str) and len(c) == 7 and c[4] == "-"]

    long = data.melt(id_vars=["Commodity"], value_vars=years,
                     var_name="financial_year", value_name=value_name)
    long = long.rename(columns={"Commodity": "source_name"})
    long["source_name"] = long["source_name"].str.strip()

    # "n/a" -> empty (NULL), never 0
    long[value_name] = pd.to_numeric(long[value_name], errors="coerce")
    return long


def main() -> None:
    OUT.mkdir(exist_ok=True)

    outputs = {
        "raw_sales.csv": extract_sales(),
        # Royalties: data starts one row lower, below the "($ Million)" label row
        "raw_royalties.csv": extract_by_group("Royalties Historic", 9, "royalty_aud_m"),
        "raw_employment.csv": extract_by_group("Mining Employment FY", 8, "fte"),
    }

    for filename, df in outputs.items():
        df.to_csv(OUT / filename, index=False)
        print(f"{filename:22} {df.shape[0]:>5} rows")

    # Expected: sales 1012 (46 x 22), royalties 462 (11 x 42), employment 288 (12 x 24)


if __name__ == "__main__":
    main()