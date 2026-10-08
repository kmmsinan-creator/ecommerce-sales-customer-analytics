"""
Step 7: Export pre-aggregated JSON for the web dashboard.

The dashboard runs in the browser and cannot read a database or a 77 MB CSV, so the heavy work is
done here and the page only loads small JSON files. Every figure mirrors a query in sql/03 to sql/08
and is checked against the locked baselines in reports/03_business_rules.md.

Run from the repository root (after notebooks/01_clean_data.py):
    python notebooks/02_export_dashboard_data.py

Input : data/processed/online_retail_clean.csv
Output: docs/data/*.json
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
CSV = ROOT / "data" / "processed" / "online_retail_clean.csv"
OUT = ROOT / "docs" / "data"
OUT.mkdir(parents=True, exist_ok=True)

SNAPSHOT = pd.Timestamp("2011-12-10")          # day after the last transaction

df = pd.read_csv(CSV, dtype={"invoice_no": str, "stock_code": str, "stock_code_clean": str},
                 parse_dates=["invoice_date"])
for col in ["is_duplicate", "has_customer", "is_cancelled", "is_partial_month"]:
    df[col] = df[col].astype(bool)
df["product_name"] = df["product_name"].fillna("")

sale = df[df.line_type == "sale"]
canc = df[df.line_type == "cancellation"]
cust_sale = sale[sale.has_customer]


def num(x, nd=2):
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return None
    return round(float(x), nd)


def write(name, obj):
    path = OUT / f"{name}.json"
    path.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return path


def rank_min(s, ascending=False):
    """SQL RANK(): ties share the lowest rank."""
    return s.rank(method="min", ascending=ascending).astype(int)


def ntile(n_rows, k):
    """Bucket number (1..k) for each 0-based sorted position, as SQL NTILE(k)."""
    base, extra = divmod(n_rows, k)
    cut = extra * (base + 1)
    pos = np.arange(n_rows)
    return np.where(pos < cut, pos // (base + 1) + 1, extra + (pos - cut) // base + 1)


# =============================================================================================
# kpis.json
# =============================================================================================
cust_tot = cust_sale.groupby("customer_id").agg(revenue=("revenue", "sum"),
                                                orders=("invoice_no", "nunique"))
revenue = sale.revenue.sum()
orders = sale.invoice_no.nunique()
canc_value = -canc.revenue.sum()
canc_inv = canc.invoice_no.nunique()
kpis = {
    "revenue": num(revenue), "orders": int(orders), "units": int(sale.quantity.sum()),
    "avg_order_value": num(revenue / orders), "products_sold": int(sale.stock_code_clean.nunique()),
    "customers": int(cust_sale.customer_id.nunique()),
    "revenue_per_customer": num(cust_sale.revenue.sum() / cust_sale.customer_id.nunique()),
    "cancellation_value": num(canc_value), "net_revenue": num(revenue - canc_value),
    "cancelled_invoices": int(canc_inv),
    "cancel_rate_value_pct": num(100 * canc_value / revenue),
    "cancel_rate_orders_pct": num(100 * canc_inv / (canc_inv + orders)),
    "avg_orders_per_customer": num(cust_tot.orders.sum() / len(cust_tot)),
    "repeat_customers": int((cust_tot.orders >= 2).sum()),
    "repeat_rate_pct": num(100 * (cust_tot.orders >= 2).mean(), 1),
    "customer_revenue": num(cust_sale.revenue.sum()),
    "revenue_without_customer": num(sale[~sale.has_customer].revenue.sum()),
    "revenue_without_customer_pct": num(100 * sale[~sale.has_customer].revenue.sum() / revenue, 1),
    "date_from": "2010-12-01", "date_to": "2011-12-09", "partial_month": "2011-12",
}
write("kpis", kpis)

# =============================================================================================
# monthly.json  (sales, cancellations, growth, new vs returning)
# =============================================================================================
m = sale.groupby("invoice_month").agg(revenue=("revenue", "sum"), orders=("invoice_no", "nunique"),
                                      units=("quantity", "sum"), customers=("customer_id", "nunique"),
                                      partial=("is_partial_month", "max"))
m["cancellations"] = -canc.groupby("invoice_month").revenue.sum()
m["cancellations"] = m["cancellations"].fillna(0)
m["prev"] = m.revenue.shift(1)
cm = cust_sale[["customer_id", "invoice_month"]].drop_duplicates()
first = cm.groupby("customer_id").invoice_month.min().rename("first_month")
cm = cm.join(first, on="customer_id")
nr = cm.assign(new=cm.invoice_month == cm.first_month).groupby("invoice_month").new.agg(["sum", "count"])
monthly = []
for month, r in m.iterrows():
    growth = None if (r.partial or pd.isna(r.prev)) else 100 * (r.revenue - r.prev) / r.prev
    new_c = int(nr.loc[month, "sum"])
    active = int(nr.loc[month, "count"])
    monthly.append({
        "month": month[:7], "revenue": num(r.revenue), "orders": int(r.orders), "units": int(r.units),
        "customers": int(r.customers), "avg_order_value": num(r.revenue / r.orders),
        "mom_growth_pct": num(growth, 1), "is_partial": bool(r.partial),
        "cancellations": num(r.cancellations), "net_revenue": num(r.revenue - r.cancellations),
        "cancel_rate_pct": num(100 * r.cancellations / r.revenue),
        "new_customers": new_c, "returning_customers": active - new_c,
        "returning_pct": num(100 * (active - new_c) / active, 1),
    })
write("monthly", monthly)

# =============================================================================================
# products.json
# =============================================================================================
p = sale.groupby("stock_code_clean").agg(name=("product_name", "max"), revenue=("revenue", "sum"),
                                          units=("quantity", "sum"), orders=("invoice_no", "nunique"))
p = p.sort_values("revenue", ascending=False)
p["revenue_rank"] = rank_min(p.revenue)
p["share"] = 100 * p.revenue / p.revenue.sum()
p["cum"] = p.share.cumsum()
p["units_rank"] = rank_min(p.units)
top = [{"rank": int(r.revenue_rank), "code": code, "name": r["name"], "revenue": num(r.revenue),
        "units": int(r.units), "orders": int(r.orders), "avg_price": num(r.revenue / r.units),
        "share_pct": num(r.share), "cumulative_pct": num(r.cum)}
       for code, r in p[p.revenue_rank <= 15].iterrows()]
n80 = int(((p.cum - p.share) < 80).sum())
vv = p[p.units_rank <= 50].assign(gap=lambda x: x.revenue_rank - x.units_rank) \
      .sort_values("gap", ascending=False).head(10)
volume_vs_value = [{"name": r["name"], "units_rank": int(r.units_rank), "revenue_rank": int(r.revenue_rank),
                    "units": int(r.units), "revenue": num(r.revenue), "avg_price": num(r.revenue / r.units)}
                   for _, r in vv.iterrows()]
top5_codes = list(p.head(5).index)
trend = sale[sale.stock_code_clean.isin(top5_codes)].groupby(["stock_code_clean", "invoice_month"]).revenue.sum()
months_all = [x["month"] for x in monthly]
top5_monthly = [{"code": c, "name": p.loc[c, "name"],
                 "revenue": [num(trend.get((c, mo + "-01"), 0.0)) for mo in months_all]} for c in top5_codes]
write("products", {"top": top, "pareto": {"total_products": int(len(p)), "products_for_80pct": n80,
                                          "pct_of_products": num(100 * n80 / len(p), 1)},
                   "volume_vs_value": volume_vs_value, "top5_monthly": top5_monthly, "months": months_all})

# =============================================================================================
# countries.json
# =============================================================================================
c = sale[sale.country_group != "Unspecified / EC"].groupby("country_group").agg(
    revenue=("revenue", "sum"), orders=("invoice_no", "nunique"), customers=("customer_id", "nunique"))
c = c.sort_values("revenue", ascending=False)
c["rank"] = rank_min(c.revenue)
c["share"] = 100 * c.revenue / c.revenue.sum()
countries = [{"rank": int(r["rank"]), "country": k, "revenue": num(r.revenue), "share_pct": num(r.share),
              "orders": int(r.orders), "customers": int(r.customers),
              "avg_order_value": num(r.revenue / r.orders)} for k, r in c.iterrows()]
mk = sale.groupby("market").agg(revenue=("revenue", "sum"), orders=("invoice_no", "nunique"),
                                customers=("customer_id", "nunique"), units=("quantity", "sum"))
markets = [{"market": k, "revenue": num(r.revenue), "share_pct": num(100 * r.revenue / mk.revenue.sum()),
            "orders": int(r.orders), "customers": int(r.customers),
            "avg_order_value": num(r.revenue / r.orders), "avg_price": num(r.revenue / r.units)}
           for k, r in mk.sort_values("revenue", ascending=False).iterrows()]
intl = sale[(sale.market == "International") & (sale.country_group != "Unspecified / EC")]
top5_intl = list(intl.groupby("country_group").revenue.sum().sort_values(ascending=False).head(5).index)
pc = intl[intl.country_group.isin(top5_intl)].groupby(["country_group", "stock_code_clean"]).agg(
    name=("product_name", "max"), revenue=("revenue", "sum")).reset_index()
pc = pc.sort_values(["country_group", "revenue"], ascending=[True, False])
top_products_by_country = [
    {"country": cg, "products": [{"name": r["name"], "revenue": num(r.revenue)} for _, r in g.head(3).iterrows()]}
    for cg, g in pc.groupby("country_group")]
write("countries", {"countries": countries, "markets": markets, "top_products_by_country": top_products_by_country})

# =============================================================================================
# customers.json
# =============================================================================================
ct = cust_sale.groupby("customer_id").agg(revenue=("revenue", "sum"), orders=("invoice_no", "nunique"),
                                          first=("invoice_date", "min"), last=("invoice_date", "max"))
srt = ct.sort_values("revenue", ascending=False).copy()
srt["decile"] = ntile(len(srt), 10)
dec = srt.groupby("decile").agg(customers=("revenue", "size"), revenue=("revenue", "sum"))
dec["share"] = 100 * dec.revenue / dec.revenue.sum()
dec["cum"] = dec.share.cumsum()
deciles = [{"decile": int(k), "customers": int(r.customers), "revenue": num(r.revenue),
            "share_pct": num(r.share, 1), "cumulative_pct": num(r.cum, 1)} for k, r in dec.iterrows()]
bands = pd.cut(ct.orders, [0, 1, 3, 9, 10**6], labels=["1 order", "2-3 orders", "4-9 orders", "10+ orders"])
fb = ct.groupby(bands, observed=True).agg(customers=("revenue", "size"), revenue=("revenue", "sum"))
freq_bands = [{"band": str(k), "customers": int(r.customers), "pct_of_customers": num(100 * r.customers / fb.customers.sum(), 1),
               "revenue": num(r.revenue), "pct_of_revenue": num(100 * r.revenue / fb.revenue.sum(), 1)}
              for k, r in fb.iterrows()]
top_customers = [{"rank": i + 1, "customer_id": int(k), "revenue": num(r.revenue),
                  "share_pct": num(100 * r.revenue / ct.revenue.sum()), "orders": int(r.orders),
                  "avg_order_value": num(r.revenue / r.orders),
                  "first_purchase": r["first"].strftime("%Y-%m-%d"), "last_purchase": r["last"].strftime("%Y-%m-%d")}
                 for i, (k, r) in enumerate(srt.head(10).iterrows())]
write("customers", {"deciles": deciles, "frequency_bands": freq_bands, "top_customers": top_customers})

# =============================================================================================
# rfm.json
# =============================================================================================
g = cust_sale.groupby("customer_id").agg(last=("invoice_date", "max"), frequency=("invoice_no", "nunique"),
                                         monetary=("revenue", "sum"))
g["recency"] = (SNAPSHOT - g["last"].dt.normalize()).dt.days
g["r"] = np.select([g.recency <= 30, g.recency <= 90, g.recency <= 180, g.recency <= 270], [5, 4, 3, 2], 1)
g["f"] = np.select([g.frequency == 1, g.frequency == 2, g.frequency <= 4, g.frequency <= 9], [1, 2, 3, 4], 5)
g["segment"] = np.select(
    [(g.r >= 4) & (g.f >= 4), (g.r >= 3) & (g.f >= 3), (g.r >= 4) & (g.f == 2), (g.r >= 4) & (g.f == 1),
     g.r == 3, g.f >= 3],
    ["Champions", "Loyal Customers", "Potential Loyalists", "Recent Customers", "Needs Attention", "At Risk"],
    "Lost Customers")
sg = g.groupby("segment").agg(customers=("monetary", "size"), revenue=("monetary", "sum"),
                              recency=("recency", "mean"), orders=("frequency", "mean"),
                              spend=("monetary", "mean")).sort_values("revenue", ascending=False)
segments = [{"segment": k, "customers": int(r.customers), "pct_of_customers": num(100 * r.customers / len(g), 1),
             "revenue": num(r.revenue), "pct_of_revenue": num(100 * r.revenue / g.monetary.sum(), 1),
             "avg_recency_days": int(round(r.recency)), "avg_orders": num(r.orders, 1), "avg_spend": num(r.spend)}
            for k, r in sg.iterrows()]
grid = g.groupby(["r", "f"]).size().unstack(fill_value=0).reindex(index=[5, 4, 3, 2, 1], columns=[1, 2, 3, 4, 5], fill_value=0)
at_risk = g[g.segment == "At Risk"].sort_values("monetary", ascending=False).head(10)
write("rfm", {"segments": segments,
              "grid": {"r_scores": [5, 4, 3, 2, 1], "f_scores": [1, 2, 3, 4, 5], "counts": grid.values.tolist()},
              "at_risk_top": [{"customer_id": int(k), "last_purchase": r["last"].strftime("%Y-%m-%d"),
                               "recency_days": int(r.recency), "orders": int(r.frequency),
                               "total_spend": num(r.monetary), "avg_order_value": num(r.monetary / r.frequency)}
                              for k, r in at_risk.iterrows()],
              "snapshot_date": SNAPSHOT.strftime("%Y-%m-%d")})

# =============================================================================================
# cancellations.json
# =============================================================================================
ci = canc.groupby("invoice_no").agg(value=("revenue", lambda s: -s.sum()), customer_id=("customer_id", "max"),
                                    ts=("invoice_date", "min"), lines=("revenue", "size")).sort_values("value", ascending=False)
ci["bucket"] = ntile(len(ci), 100)
conc = {"cancelled_invoices": int(len(ci)),
        "top_1pct_share": num(100 * ci[ci.bucket == 1].value.sum() / ci.value.sum(), 1),
        "top_10pct_share": num(100 * ci[ci.bucket <= 10].value.sum() / ci.value.sum(), 1),
        "avg_cancelled_invoice": num(ci.value.mean())}
top_inv = [{"rank": i + 1, "invoice_no": k, "customer_id": None if pd.isna(r.customer_id) else int(r.customer_id),
            "cancelled_at": r.ts.strftime("%Y-%m-%d %H:%M"), "lines": int(r.lines), "value": num(r.value)}
           for i, (k, r) in enumerate(ci.head(10).iterrows())]
case_inv = df[(df.customer_id == 15749) & df.invoice_no.isin(["540815", "540818", "C550456", "550461"])]
case = [{"invoice_no": k, "invoice_date": r.ts.strftime("%Y-%m-%d %H:%M"), "line_type": r.ltype, "lines": int(r.n),
         "value": num(r.v)}
        for k, r in case_inv.groupby("invoice_no").agg(ts=("invoice_date", "min"), ltype=("line_type", "first"),
                                                       n=("revenue", "size"), v=("revenue", "sum"))
        .sort_values("ts").iterrows()]
apr = df[(df.invoice_month == "2011-04-01") & df.line_type.isin(["sale", "cancellation"])]
apr_sales = apr[apr.line_type == "sale"].revenue.sum()
apr_c = apr[apr.line_type == "cancellation"]
april = {"rate_all_pct": num(100 * -apr_c.revenue.sum() / apr_sales),
         "rate_excluding_c550456_pct": num(100 * -apr_c[apr_c.invoice_no != "C550456"].revenue.sum() / apr_sales)}
ps = sale.groupby("stock_code_clean").agg(name=("product_name", "max"), sales=("revenue", "sum"))
pcn = canc.groupby("stock_code_clean").agg(cv=("revenue", lambda s: -s.sum()), inv=("invoice_no", "nunique"))
pj = pcn.join(ps, how="inner").sort_values("cv", ascending=False).head(10)
prod_c = [{"rank": i + 1, "name": r["name"], "cancel_value": num(r.cv), "cancel_invoices": int(r.inv),
           "sales_value": num(r.sales), "cancel_rate_pct": num(100 * r.cv / r.sales, 1)}
          for i, (k, r) in enumerate(pj.iterrows())]
cc = canc[canc.has_customer].groupby("customer_id").agg(cv=("revenue", lambda s: -s.sum()), inv=("invoice_no", "nunique"))
cj = cc.join(ct.revenue.rename("sales"), how="inner")
cj = cj[(cj.cv > 2000) & (cj.cv > 0.2 * cj.sales)].sort_values("cv", ascending=False)
cust_c = [{"customer_id": int(k), "cancel_value": num(r.cv), "cancel_invoices": int(r.inv),
           "sales_value": num(r.sales), "cancel_pct_of_own_sales": num(100 * r.cv / r.sales, 1)} for k, r in cj.iterrows()]
bc = df[df.line_type.isin(["sale", "cancellation"]) & (df.country_group != "Unspecified / EC")] \
    .groupby("country_group").apply(lambda x: pd.Series({"sales": x[x.line_type == "sale"].revenue.sum(),
                                                         "cancel": -x[x.line_type == "cancellation"].revenue.sum()}),
                                    include_groups=False)
bc = bc[bc.sales > 50000].assign(rate=lambda x: 100 * x.cancel / x.sales).sort_values("rate", ascending=False)
country_c = [{"country": k, "sales_value": num(r.sales), "cancel_value": num(r.cancel), "cancel_rate_pct": num(r.rate)}
             for k, r in bc.iterrows()]
write("cancellations", {"kpis": {"cancelled_invoices": kpis["cancelled_invoices"], "cancelled_lines": int(len(canc)),
                                 "cancellation_value": kpis["cancellation_value"],
                                 "rate_by_value_pct": kpis["cancel_rate_value_pct"],
                                 "rate_by_orders_pct": kpis["cancel_rate_orders_pct"],
                                 "value_without_customer": num(-canc[~canc.has_customer].revenue.sum())},
                        "concentration": conc, "top_invoices": top_inv, "april_case_study": case, "april": april,
                        "products": prod_c, "customers": cust_c, "countries": country_c})

# =============================================================================================
# cohorts.json
# =============================================================================================
cmo = sale[sale.has_customer & ~sale.is_partial_month][["customer_id", "invoice_month"]].drop_duplicates()
months = sorted(cmo.invoice_month.unique())
midx = {mo: i for i, mo in enumerate(months)}
coh = cmo.groupby("customer_id").invoice_month.min().rename("cohort")
cmo = cmo.join(coh, on="customer_id")
sizes = coh.value_counts().sort_index()
act = cmo.groupby(["cohort", "invoice_month"]).size()
rows = []
for cohort, size in sizes.items():
    for mo in months:
        if midx[mo] >= midx[cohort]:
            a = int(act.get((cohort, mo), 0))
            rows.append({"cohort": cohort[:7], "months_since": midx[mo] - midx[cohort], "cohort_size": int(size),
                         "active": a, "retention_pct": num(100 * a / size, 1)})
rdf = pd.DataFrame(rows)
avg = rdf[rdf.cohort > "2010-12"].groupby("months_since").agg(cohorts=("cohort", "size"), customers=("cohort_size", "sum"),
                                                              active=("active", "sum"))
avg_curve = [{"months_since": int(k), "cohorts_included": int(r.cohorts), "customers": int(r.customers),
              "active": int(r.active), "avg_retention_pct": num(100 * r.active / r.customers, 1)} for k, r in avg.iterrows()]
write("cohorts", {"retention": rows, "average_curve": avg_curve})

# =============================================================================================
# quality.json  (data-quality page)
# =============================================================================================
recon = df.groupby("line_type").agg(rows=("revenue", "size"), value=("revenue", "sum"))
order = ["sale", "cancellation", "non_product", "gift_voucher", "invalid_price", "reversed_order", "adjustment", "zero_price"]
meaning = {
    "sale": "Counted as sales (revenue, orders, units, products, countries)",
    "cancellation": "Returned or cancelled product lines (invoice starts with C)",
    "non_product": "Postage, fees, manual entries, discounts, samples, bank charges",
    "gift_voucher": "Gift vouchers, kept separate from product sales",
    "invalid_price": "Negative unit price (bad-debt adjustments)",
    "reversed_order": "Three large orders reversed within minutes, excluded from sales and cancellations",
    "adjustment": "Stock write-offs: negative quantity, price 0, no customer",
    "zero_price": "Free items, no revenue",
}
quality = {
    "raw": {"rows": int(len(df)), "columns": 8, "value": num(df.revenue.sum())},
    "reconciliation": [{"line_type": lt, "rows": int(recon.loc[lt, "rows"]), "value": num(recon.loc[lt, "value"]),
                        "meaning": meaning[lt]} for lt in order],
    "issues": [
        {"issue": "Missing CustomerID", "count": int(df.customer_id.isna().sum()),
         "treatment": "Kept for revenue, product and country analysis; excluded from customer analysis"},
        {"issue": "Missing Description", "count": 1454, "treatment": "All are zero-price adjustments; no revenue"},
        {"issue": "Exact duplicate rows", "count": int(df.is_duplicate.sum()),
         "treatment": "Kept and flagged; impact on sales 0.24%"},
        {"issue": "Cancelled invoices (rows)", "count": int(df.is_cancelled.sum()),
         "treatment": "Measured separately as cancellations"},
        {"issue": "Negative quantities", "count": int((df.quantity < 0).sum()),
         "treatment": "Cancellations or stock write-offs, never sales"},
        {"issue": "Zero unit price", "count": int((df.unit_price == 0).sum()), "treatment": "No revenue; excluded from sales"},
        {"issue": "Negative unit price", "count": int((df.unit_price < 0).sum()), "treatment": "Excluded everywhere"},
        {"issue": "Case-variant product codes", "count": 112, "treatment": "Codes trimmed and uppercased"},
        {"issue": "Descriptions with stray spaces", "count": 113453, "treatment": "Trimmed and standardised"},
        {"issue": "Partial final month", "count": int(df.is_partial_month.sum()),
         "treatment": "December 2011 flagged and excluded from growth and retention"},
    ],
    "limitations": [
        "About 15% of sales revenue has no CustomerID, so customer analysis covers about 85% of sales",
        "Only 12 months of data: seasonality cannot be separated from growth, and no year-over-year view exists",
        "No cost data: revenue is reported, profit is not",
        "Some early cancellations may relate to sales made before the data starts",
        "December 2010 cohort includes long-standing customers, not only new ones",
    ],
}
write("quality", quality)

write("meta", {"title": "E-Commerce Sales & Customer Intelligence Analytics",
               "source": "UCI Machine Learning Repository, Online Retail dataset (CC BY 4.0)",
               "rows": int(len(df)), "date_from": "2010-12-01", "date_to": "2011-12-09",
               "rfm_snapshot": SNAPSHOT.strftime("%Y-%m-%d")})

# =============================================================================================
# Validation against the locked baselines
# =============================================================================================
checks = [("revenue", kpis["revenue"], 9986809.86, 0.5), ("net_revenue", kpis["net_revenue"], 9753738.88, 0.5),
          ("cancellation_value", kpis["cancellation_value"], 233070.98, 0.5), ("orders", kpis["orders"], 19770, 0),
          ("units", kpis["units"], 5421830, 0), ("avg_order_value", kpis["avg_order_value"], 505.15, 0.01),
          ("products_sold", kpis["products_sold"], 3797, 0), ("customers", kpis["customers"], 4333, 0),
          ("cancelled_invoices", kpis["cancelled_invoices"], 3420, 0),
          ("customer_revenue", kpis["customer_revenue"], 8476443.45, 0.5),
          ("monthly revenue sums to total", sum(x["revenue"] for x in monthly), 9986809.86, 1.0),
          ("RFM customers", sum(s["customers"] for s in segments), 4333, 0),
          ("RFM revenue", sum(s["revenue"] for s in segments), 8476443.45, 1.0),
          ("country revenue + unspecified", sum(x["revenue"] for x in countries) + 5909.04, 9986809.86, 1.0),
          ("recon total", sum(x["value"] for x in quality["reconciliation"]), 9747747.93, 1.0)]
ok = True
print(f"{'check':36s}{'expected':>16s}{'actual':>16s}  result")
for name, got, exp, tol in checks:
    good = abs(got - exp) <= tol
    ok &= good
    print(f"{name:36s}{exp:>16,.2f}{got:>16,.2f}  {'PASS' if good else 'FAIL'}")
print()
for f in sorted(OUT.glob("*.json")):
    print(f"{f.name:20s}{f.stat().st_size / 1024:8.1f} KB")
print("\nALL CHECKS PASSED" if ok else "\nFAILURES PRESENT")
if not ok:
    raise SystemExit(1)
