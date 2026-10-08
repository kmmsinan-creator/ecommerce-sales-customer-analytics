# sql/

Written for PostgreSQL. Run the scripts in order from the repository root, because `01` uses a relative path for the CSV.

| Script | Purpose | Main techniques |
|---|---|---|
| `01_create_and_load.sql` | Create `sales_clean`, load the CSV, add indexes | DDL, `\copy` |
| `02_validate_baselines.sql` | Check the loaded data against locked KPIs. Every row must show PASS. | CTEs, `UNION ALL` |
| `03_sales_kpis.sql` | Headline KPIs, monthly revenue with growth, gross vs net revenue | `LAG`, conditional aggregation |
| `04_product_country.sql` | Product ranking, Pareto concentration, volume vs value, countries, UK vs international | `RANK`, `ROW_NUMBER`, running totals |
| `05_customers.sql` | Customer KPIs, revenue deciles, top customers, frequency bands, new vs returning | `NTILE`, `MIN` per customer |
| `06_cancellations.sql` | Cancellation KPIs, concentration, the April 2011 case study, products, customers, countries | `NTILE(100)`, joins |
| `07_cohorts.sql` | Cohort retention table and average retention curve | `DENSE_RANK` month index, cohort grid |
| `08_rfm.sql` | RFM view, segment summary, score grid, win-back list | views, `CASE`, date arithmetic |

## Rule for every analysis query

Metrics filter on `line_type`, never on raw columns. Sales use `line_type = 'sale'`, and customer analysis adds `customer_id IS NOT NULL`. See `reports/03_business_rules.md` for the full rules.

## Expected baselines

Revenue £9,986,809.86, orders 19,770, customers 4,333, cancellation value £233,070.98, net revenue £9,753,738.88.
