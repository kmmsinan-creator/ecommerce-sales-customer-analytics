# Data Dictionary: `sales_clean` / `online_retail_clean.csv`

One row per raw transaction line (541,909 rows). No raw rows are removed; use `line_type` to choose which rows a metric includes.

| Column | Type | Description |
|---|---|---|
| `row_id` | integer | Position of the row in the raw file (1-based). Primary key; lets any row be traced back to the source. |
| `invoice_no` | text | Order or cancellation document. Starts with "C" for cancellations, "A" for bad-debt adjustments. |
| `stock_code` | text | Product code exactly as in the raw file. |
| `stock_code_clean` | text | Trimmed and uppercased code. **Use this for all product analysis.** |
| `product_name` | text | Most frequent cleaned description for the code (sale rows take precedence). NULL for 110 non-sale rows with no description anywhere. |
| `quantity` | integer | Units on the line. Negative for cancellations and write-offs. |
| `invoice_date` | timestamp | Date and time of the transaction. |
| `unit_price` | decimal | Price per unit in GBP. |
| `customer_id` | integer | Customer. NULL for 135,080 rows (24.93%). |
| `country` | text | Country as in the raw file. A transaction attribute, not a fixed customer attribute. |
| `country_group` | text | Same as `country`, except "Unspecified" and "European Community" become "Unspecified / EC". |
| `market` | text | `UK`, `International`, or `Unknown`. Supports the UK vs international comparison. |
| `revenue` | decimal | `quantity * unit_price`, 4 decimals. |
| `line_type` | text | Exactly one of: `sale`, `cancellation`, `non_product`, `gift_voucher`, `invalid_price`, `reversed_order`, `adjustment`, `zero_price`. See `03_business_rules.md`. |
| `is_duplicate` | boolean | True for the 2nd and later copies of a row identical in all 8 raw fields. Flag only, not removed. |
| `has_customer` | boolean | True if `customer_id` is present. |
| `is_cancelled` | boolean | True if the raw InvoiceNo starts with "C". Note this is broader than `line_type = 'cancellation'`, which also excludes fees and reversed orders. **Use `line_type` for cancellation KPIs.** |
| `is_partial_month` | boolean | True for transactions on or after 2011-12-01 (data ends 9 December 2011). |
| `invoice_month` | date | First day of the invoice's month, for monthly grouping. |

## Which rows does a metric use?

| Metric group | Filter |
|---|---|
| Gross sales, orders, units, products, countries | `line_type = 'sale'` |
| Net revenue | `line_type IN ('sale', 'cancellation')` |
| Cancellation KPIs | `line_type = 'cancellation'` |
| Customer KPIs and RFM | `line_type = 'sale' AND has_customer` |
| Monthly growth | add `AND NOT is_partial_month` |
