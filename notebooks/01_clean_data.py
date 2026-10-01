"""
Step 4: Build the cleaned analytical dataset.

Applies the rules in reports/03_business_rules.md to the raw UCI Online Retail file.
No rows are deleted: every row receives one `line_type` plus supporting flags.

Run from the repository root:
    python notebooks/01_clean_data.py

Inputs : data/raw/Online_Retail.xlsx            (never modified)
Outputs: data/processed/online_retail_clean.csv
         reports/04_cleaning_log.md             (generated: transformations, reconciliation, validation)
"""
import hashlib
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
RAW = ROOT / "data" / "raw" / "Online_Retail.xlsx"
OUT_CSV = ROOT / "data" / "processed" / "online_retail_clean.csv"
OUT_LOG = ROOT / "reports" / "04_cleaning_log.md"

EXPECTED_SHA256 = "43465a06f2ccf7c8b5bd2892bc7defb52f97487934fe93b16ae4c3936424676d"

# ---- Business rule constants (see 03_business_rules.md) -------------------------------
NON_PRODUCT_CODES = {"POST", "DOT", "C2", "M", "D", "S", "B",
                     "BANK CHARGES", "AMAZONFEE", "CRUK", "PADS"}
REVERSED_ORDER_INVOICES = {"541431", "C541433", "581483", "C581484", "556444", "C556445"}
UNKNOWN_COUNTRIES = {"Unspecified", "European Community"}
PARTIAL_MONTH_START = pd.Timestamp("2011-12-01")

# ---- 1. Load raw ----------------------------------------------------------------------
sha = hashlib.sha256(RAW.read_bytes()).hexdigest()
if sha != EXPECTED_SHA256:
    raise SystemExit(f"Raw file checksum mismatch: {sha}")

raw = pd.read_excel(RAW, dtype={"InvoiceNo": str, "StockCode": str})
n_raw = len(raw)
raw_revenue = (raw["Quantity"] * raw["UnitPrice"]).sum()

df = pd.DataFrame({
    "row_id": np.arange(1, len(raw) + 1),          # position in the raw file (1-based)
    "invoice_no": raw["InvoiceNo"],
    "stock_code": raw["StockCode"],
    "quantity": raw["Quantity"],
    "invoice_date": raw["InvoiceDate"],
    "unit_price": raw["UnitPrice"],
    "customer_id": raw["CustomerID"],
    "country": raw["Country"],
})

# ---- 2. Standardise text fields -------------------------------------------------------
df["stock_code_clean"] = raw["StockCode"].str.strip().str.upper()
n_code_changed = int((df["stock_code_clean"] != raw["StockCode"]).sum())

desc_raw = raw["Description"]
desc_clean = (desc_raw.str.strip()
              .str.replace(r"\s+", " ", regex=True)
              .str.upper())
n_desc_changed = int((desc_clean.fillna("") != desc_raw.fillna("")).sum())

# ---- 3. Revenue -----------------------------------------------------------------------
df["revenue"] = (df["quantity"] * df["unit_price"]).round(4)

# ---- 4. line_type (first matching rule wins) ------------------------------------------
is_c = df["invoice_no"].str.startswith("C")
conditions = [
    df["unit_price"] < 0,
    df["invoice_no"].isin(REVERSED_ORDER_INVOICES),
    df["stock_code_clean"].isin(NON_PRODUCT_CODES),
    df["stock_code_clean"].str.startswith("GIFT_"),
    is_c,
    df["quantity"] < 0,
    df["unit_price"] == 0,
]
choices = ["invalid_price", "reversed_order", "non_product", "gift_voucher",
           "cancellation", "adjustment", "zero_price"]
df["line_type"] = np.select(conditions, choices, default="sale")

# ---- 5. product_name: most frequent cleaned description among sale rows ---------------
tmp = pd.DataFrame({"code": df["stock_code_clean"], "desc": desc_clean, "lt": df["line_type"]})


def modal_name(frame):
    frame = frame.dropna(subset=["desc"])
    if frame.empty:
        return pd.Series(dtype="object")
    return frame.groupby("code")["desc"].agg(lambda s: s.value_counts().index[0])


name_sale = modal_name(tmp[tmp["lt"] == "sale"])
name_any = modal_name(tmp)
product_names = name_any.copy()
product_names.update(name_sale)               # sale-row names take precedence
df["product_name"] = df["stock_code_clean"].map(product_names)

# ---- 6. Flags and derived attributes --------------------------------------------------
dup_cols = ["InvoiceNo", "StockCode", "Description", "Quantity", "InvoiceDate",
            "UnitPrice", "CustomerID", "Country"]
df["is_duplicate"] = raw.duplicated(subset=dup_cols, keep="first")
df["has_customer"] = df["customer_id"].notna()
df["is_cancelled"] = is_c
df["is_partial_month"] = df["invoice_date"] >= PARTIAL_MONTH_START
df["invoice_month"] = df["invoice_date"].dt.to_period("M").dt.to_timestamp().dt.strftime("%Y-%m-%d")
df["country_group"] = np.where(df["country"].isin(UNKNOWN_COUNTRIES), "Unspecified / EC", df["country"])
df["market"] = np.select(
    [df["country"] == "United Kingdom", df["country"].isin(UNKNOWN_COUNTRIES)],
    ["UK", "Unknown"], default="International")
df["customer_id"] = df["customer_id"].astype("Int64")

cols = ["row_id", "invoice_no", "stock_code", "stock_code_clean", "product_name", "quantity",
        "invoice_date", "unit_price", "customer_id", "country", "country_group", "market",
        "revenue", "line_type", "is_duplicate", "has_customer", "is_cancelled",
        "is_partial_month", "invoice_month"]
df = df[cols]

# ---- 7. Integrity checks (fail loudly) ------------------------------------------------
assert len(df) == n_raw, "row count changed"
assert df["line_type"].notna().all()
assert abs(df["revenue"].sum() - raw_revenue) < 1.0, "revenue does not reconcile to raw"

# ---- 8. Write CSV ---------------------------------------------------------------------
OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
out = df.copy()
out["invoice_date"] = out["invoice_date"].dt.strftime("%Y-%m-%d %H:%M:%S")
for b in ["is_duplicate", "has_customer", "is_cancelled", "is_partial_month"]:
    out[b] = out[b].astype(int)
out.to_csv(OUT_CSV, index=False)

# ---- 9. Reconciliation and validation -------------------------------------------------
recon = (df.groupby("line_type")
         .agg(rows=("revenue", "size"), net_value=("revenue", "sum"))
         .reindex(["sale", "cancellation", "non_product", "gift_voucher", "invalid_price",
                   "reversed_order", "adjustment", "zero_price"]))

s = df[df["line_type"] == "sale"]
c = df[df["line_type"] == "cancellation"]
cust_sales = s[s["has_customer"]]

checks = [
    ("Rows in = rows out", n_raw, len(df), 0),
    ("Total revenue reconciles to raw", raw_revenue, df["revenue"].sum(), 0.5),
    ("Revenue (gross sales)", 9986809.86, s["revenue"].sum(), 0.5),
    ("Cancellation value", 233070.98, -c["revenue"].sum(), 0.5),
    ("Net revenue", 9753738.88, s["revenue"].sum() + c["revenue"].sum(), 0.5),
    ("Orders", 19770, s["invoice_no"].nunique(), 0),
    ("Units sold", 5421830, int(s["quantity"].sum()), 0),
    ("Average order value", 505.15, s["revenue"].sum() / s["invoice_no"].nunique(), 0.01),
    ("Distinct products sold", 3797, s["stock_code_clean"].nunique(), 0),
    ("Customers with sales", 4333, s["customer_id"].nunique(), 0),
    ("Cancelled invoices", 3420, c["invoice_no"].nunique(), 0),
    ("Sales rows with no CustomerID", 131421, int((~s["has_customer"]).sum()), 0),
    ("Customer-level revenue", 8476443.45, cust_sales["revenue"].sum(), 0.5),
    ("Customer-level orders", 18399, cust_sales["invoice_no"].nunique(), 0),
    ("Duplicate rows within sales", 5221, int(s["is_duplicate"].sum()), 0),
]
all_pass = all(abs(exp - got) <= tol for _, exp, got, tol in checks)

named = df.loc[df["line_type"] == "sale", "product_name"].notna().mean()


def fmt(v):
    return f"{v:,.2f}" if isinstance(v, (float, np.floating)) else f"{int(v):,}"


lines = []
lines.append("# Step 4: Cleaning Log and Reconciliation\n")
lines.append("*Generated by `notebooks/01_clean_data.py`. Do not edit by hand.*\n")
lines.append(f"**Input:** `data/raw/Online_Retail.xlsx` (SHA-256 verified)  ")
lines.append(f"**Output:** `data/processed/online_retail_clean.csv` ({len(df):,} rows, {len(cols)} columns)\n")
lines.append("## 1. Transformations applied\n")
lines.append("| Transformation | Rows affected |")
lines.append("|---|---|")
lines.append(f"| Rows deleted | **0** |")
lines.append(f"| `stock_code_clean`: trimmed and uppercased | {n_code_changed:,} |")
lines.append(f"| `product_name`: trimmed, whitespace collapsed, uppercased (changed from raw Description) | {n_desc_changed:,} |")
lines.append(f"| `customer_id`: float converted to integer, blanks kept as empty | {int(df['has_customer'].sum()):,} populated, {int((~df['has_customer']).sum()):,} blank |")
lines.append(f"| `revenue` = quantity x unit_price (4 decimals) | {len(df):,} |")
lines.append(f"| `is_duplicate` flagged (2nd and later copies of identical rows) | {int(df['is_duplicate'].sum()):,} |")
lines.append(f"| `is_cancelled` (invoice starts with C) | {int(df['is_cancelled'].sum()):,} |")
lines.append(f"| `is_partial_month` (on or after 1 Dec 2011) | {int(df['is_partial_month'].sum()):,} |")
lines.append(f"| `country_group` = Unspecified / EC | {int((df['country_group'] == 'Unspecified / EC').sum()):,} |")
lines.append(f"| Sale rows with a `product_name` | {named:.2%} |\n")
lines.append("## 2. Line-type reconciliation\n")
lines.append("| line_type | Rows | Net value (GBP) |")
lines.append("|---|---|---|")
for lt, r in recon.iterrows():
    lines.append(f"| {lt} | {int(r['rows']):,} | {fmt(r['net_value'])} |")
lines.append(f"| **Total** | **{int(recon['rows'].sum()):,}** | **{fmt(recon['net_value'].sum())}** |")
lines.append(f"| Raw Quantity x UnitPrice (check) | {n_raw:,} | {fmt(raw_revenue)} |\n")
lines.append("## 3. Validation against locked baselines (Step 3)\n")
lines.append("| Check | Expected | Actual | Result |")
lines.append("|---|---|---|---|")
for name, exp, got, tol in checks:
    ok = abs(exp - got) <= tol
    lines.append(f"| {name} | {fmt(exp)} | {fmt(got)} | {'PASS' if ok else 'FAIL'} |")
lines.append(f"\n**Overall: {'ALL CHECKS PASSED' if all_pass else 'FAILURES PRESENT'}**\n")
OUT_LOG.parent.mkdir(parents=True, exist_ok=True)
OUT_LOG.write_text("\n".join(lines), encoding="utf-8")

print("\n".join(lines))
if not all_pass:
    raise SystemExit("Validation failed")
