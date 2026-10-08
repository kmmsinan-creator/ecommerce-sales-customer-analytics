# notebooks/

Two Python scripts that run from the repository root. Requirements: Python 3.10+, `pandas>=2.2`, `numpy`, `openpyxl`.

| Script | Input | Output |
|---|---|---|
| `01_clean_data.py` | `data/raw/Online_Retail.xlsx` | `data/processed/online_retail_clean.csv` and `reports/04_cleaning_log.md` |
| `02_export_dashboard_data.py` | `data/processed/online_retail_clean.csv` | Ten JSON files in `docs/data/` |

## Checks built into the scripts

- `01_clean_data.py` verifies the raw file's checksum, confirms that no rows are lost, confirms that revenue reconciles to the raw total, and compares 15 KPIs with the locked baselines.
- `02_export_dashboard_data.py` compares the exported figures with the same baselines and stops with an error if any differ.

Both finish with "ALL CHECKS PASSED" when everything matches.
