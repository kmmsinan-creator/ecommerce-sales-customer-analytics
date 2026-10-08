# E-Commerce Sales & Customer Intelligence Analytics

**Live dashboard:** https://kmmsinan-creator.github.io/ecommerce-sales-customer-analytics/

An end-to-end data analyst project on a real retail transaction dataset: raw-data audit, documented business rules, SQL analysis, customer segmentation (RFM), cohort retention, and an interactive web dashboard. Every number on the dashboard can be traced back to the raw file.

## The business problem

> Where is our revenue coming from, who are our best customers, are they coming back, and what is leaking away through cancellations?

I took the role of a data analyst at a UK-based online gift retailer. The dataset has 541,909 transaction lines covering 1 December 2010 to 9 December 2011.

## Headline results

| Metric | Value |
|---|---|
| Gross sales | £9,986,810 |
| Net revenue (after cancellations) | £9,753,739 |
| Orders | 19,770 |
| Customers with a purchase | 4,333 |
| Average order value | £505 |
| Cancellation rate | 2.33% of sales value (3,420 cancelled invoices) |
| Customers who ordered 2+ times | 65.3% |

## Key findings

1. **Revenue is seasonal.** Monthly revenue sits between £0.5M and £0.74M from January to August 2011, then climbs to £1.03M in September, £1.11M in October and £1.46M in November. With only 12 months of data, seasonality cannot be separated from real growth.
2. **A small group of customers drives revenue.** The top 10% of customers generate 60.2% of customer revenue. Customers with 10 or more orders are 8.9% of customers but 52.7% of revenue, while 34.7% bought only once and contribute 6.5%.
3. **RFM segmentation.** "Champions" are 23.8% of customers and 71.4% of revenue. An "At Risk" group of 82 customers averages £1,669 each and has not ordered for months, which makes it a ready win-back list.
4. **The UK dominates, and international revenue rests on a few accounts.** The UK is 84.7% of revenue. The Netherlands (£284k from 9 customers) and EIRE (£271k from 3 customers) depend on very few buyers, while Germany and France (94 and 87 customers) behave like the UK.
5. **Cancellations are frequent but small.** They are 2.33% of sales value but about 15% of invoices, and the top 1% of cancelled invoices hold 42.8% of the cancelled value. April 2011 looks like a 6.45% spike, but one invoice (C550456) is a cancel-and-reissue of an earlier order. Without it April is 2.00%.
6. **Product revenue is spread out.** The best product (Regency Cakestand 3 Tier) is only 1.75% of revenue, and 836 of 3,797 products (22%) make up 80% of revenue.
7. **Retention.** About 20% of new customers buy again the following month. Cohorts from September and October retain slightly better, but with one year of data that cannot be separated from the pre-Christmas season.

### Recommendations

- **Protect the Champions.** Retention work on roughly a quarter of customers protects about 70% of revenue.
- **Run a win-back campaign** on the At Risk list (the dashboard lists the top 10 by spend).
- **Investigate cancellation spikes before reacting.** Check whether a spike is real lost demand or an order amendment, as with April.
- **Reduce dependence on a few international accounts,** and treat the Netherlands and EIRE as account-managed markets.
- **Plan stock and staffing for the September to November ramp.**

## How the project works

```
Raw Excel (541,909 rows, never edited)
        |
   Data audit          -> reports/02_data_audit.md
        |
   Business rules      -> reports/03_business_rules.md
        |
   Python cleaning     -> notebooks/01_clean_data.py  -> online_retail_clean.csv
        |
   PostgreSQL          -> sql/01 to 08 (load, validate, KPIs, products, customers,
        |                 cancellations, cohorts, RFM)
   Python export       -> notebooks/02_export_dashboard_data.py -> docs/data/*.json
        |
   Web dashboard       -> docs/ (HTML, CSS, JavaScript, Chart.js), hosted on GitHub Pages
```

## Data cleaning approach

No row is ever deleted. Each of the 541,909 raw rows receives exactly one `line_type`, and every metric is defined by which line types it includes. The line types add up to the raw total of £9,747,747.93, so nothing is lost or double counted.

| line_type | What it is | Rows |
|---|---|---|
| `sale` | Counted as sales | 527,755 |
| `cancellation` | Returned or cancelled product lines | 8,702 |
| `non_product` | Postage, fees, manual entries, discounts, samples | 2,913 |
| `zero_price` | Free items, no revenue | 1,161 |
| `adjustment` | Stock write-offs (negative quantity, price 0, no customer) | 1,336 |
| `gift_voucher` | Gift vouchers, kept separate | 34 |
| `reversed_order` | Three large orders reversed within minutes | 6 |
| `invalid_price` | Negative-price bad-debt entries | 2 |

Judgment calls, each documented in `reports/03_business_rules.md`:

- **Amazon fees on cancellation invoices are not product cancellations.** Counting them would have inflated cancellation value.
- **Three huge order-and-reversal pairs** (about £285k combined) are excluded from both sales and cancellations, because they never became real revenue.
- **Exact duplicate rows are kept and flagged.** They are 0.24% of sales, and a repeated line can be a legitimate second scan.
- **December 2011 is a partial month** (data ends on the 9th), so it is flagged and left out of growth and retention figures.
- **No year-over-year growth and no profit.** The data covers about 12 months and has no cost information.

## The dashboard

Five tabs: **Overview** (KPIs, monthly revenue, top products and countries), **Customers** (RFM segments, revenue concentration, purchase frequency, new vs returning, cohort retention, win-back list), **Products** (top 15, volume vs value, monthly trends), **Markets** (UK vs international, countries, average order value), and **Cancellations & data quality** (cancellation analysis, the April case study, row-level reconciliation, issues found, limitations).

The dashboard reads small pre-aggregated JSON files, not the raw data. The export script checks them against the locked baseline KPIs before writing.

## SQL techniques used

Written for PostgreSQL: CTEs, window functions (`LAG`, `RANK`, `ROW_NUMBER`, `NTILE`, `DENSE_RANK`, running totals with `SUM() OVER`), conditional aggregation with `CASE`, date arithmetic, views, cohort analysis with a month index, and RFM scoring.

## Repository structure

```
ecommerce-sales-customer-analytics/
├── data/
│   ├── raw/Online_Retail.xlsx        original file, never edited
│   └── processed/                    cleaned CSV (rebuilt by the script, not committed)
├── notebooks/
│   ├── 01_clean_data.py              raw Excel -> cleaned CSV, with reconciliation checks
│   └── 02_export_dashboard_data.py   cleaned CSV -> JSON for the dashboard
├── sql/                              eight scripts, see sql/README.md
├── reports/                          audit, business rules, cleaning log, data dictionary
└── docs/                             the website (served by GitHub Pages)
    ├── index.html
    ├── css/style.css
    ├── js/app.js
    └── data/*.json
```

## How to reproduce

Requirements: Python 3.10+ with `pandas>=2.2`, `numpy`, `openpyxl`, and PostgreSQL.

```bash
# 1. Build the cleaned dataset (verifies the raw file checksum first)
python notebooks/01_clean_data.py

# 2. Load it into PostgreSQL (run from the repository root)
createdb ecommerce
psql -d ecommerce -f sql/01_create_and_load.sql
psql -d ecommerce -f sql/02_validate_baselines.sql    # every row must show PASS
psql -d ecommerce -f sql/03_sales_kpis.sql            # then 04 to 08

# 3. Rebuild the dashboard data and preview the site locally
python notebooks/02_export_dashboard_data.py
python -m http.server --directory docs 8000           # open http://localhost:8000
```

## Limitations

- About 15% of sales revenue has no CustomerID, so customer analysis covers about 85% of sales.
- Only 12 months of data, so seasonality cannot be separated from growth.
- No cost data, so revenue is reported and profit is not.
- Some early cancellations may relate to sales made before the data starts.
- The December 2010 cohort includes long-standing customers, not only new ones.

## Tech stack

Python (pandas, NumPy), SQL (PostgreSQL), HTML, CSS, JavaScript, Chart.js 4, GitHub Pages.

## Data source

Chen, D. *Online Retail* dataset, UCI Machine Learning Repository (https://archive.ics.uci.edu/dataset/352/online+retail), licensed CC BY 4.0.

## Author

Mohammad Sinan Koyam Moopa.
