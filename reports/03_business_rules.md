# Step 3: Business Rules and Metric Definitions

**Depends on:** `02_data_audit.md`
**Principle:** no row is ever deleted from the raw data. Every row receives exactly one `line_type`, plus a few supporting flags. Each KPI is defined by which line types it includes. All figures below were tested against the raw file.

---

## 1. Line classification

Each row is assigned **one** `line_type`. Rules are applied in this priority order, and the first match wins.

| Priority | line_type | Rule | Rows | Net value (GBP) |
|---|---|---|---|---|
| 1 | `invalid_price` | UnitPrice < 0 (bad-debt adjustments, invoices A563186 and A563187) | 2 | -22,124.12 |
| 2 | `reversed_order` | Order fully reversed within minutes by a cancellation or manual entry: invoices 541431 / C541433, 581483 / C581484, 556444 / C556445 | 6 | 0.00 |
| 3 | `non_product` | Uppercased StockCode in: POST, DOT, C2, M, D, S, B, BANK CHARGES, AMAZONFEE, CRUK, PADS | 2,913 | 15,447.36 |
| 4 | `gift_voucher` | StockCode starts with GIFT_ | 34 | 685.81 |
| 5 | `cancellation` | InvoiceNo starts with "C" | 8,702 | -233,070.98 |
| 6 | `adjustment` | Negative quantity on a non-"C" invoice (all have price 0 and no customer) | 1,336 | 0.00 |
| 7 | `zero_price` | UnitPrice = 0 and quantity > 0 | 1,161 | 0.00 |
| 8 | `sale` | Everything else | 527,755 | 9,986,809.86 |
| | **Total** | | **541,909** | **9,747,747.93** |

The total equals the raw sum of Quantity x UnitPrice, so nothing is lost or double counted.

### Why this order

- **Fees and postage come before cancellation.** An Amazon fee booked on a "C" invoice is a cost line, not a returned product. Counting it as a cancellation would inflate cancellation value by hundreds of thousands of pounds.
- **Reversed orders come early** so that neither half of a same-day order-and-reversal appears in sales or in cancellations.
- **Zero-price rows with a customer:** the audit found 40. Seven are caught earlier by non-product or other rules, leaving 33 in `zero_price`. They contribute no revenue and are excluded from orders and units.

## 2. Decisions on the open items from Step 2

| Open item | Decision | Reason |
|---|---|---|
| Exact duplicates | **Keep, flag `is_duplicate`**. 5,221 duplicate rows are in `sale`, worth £24,213.74 (0.24% of sales). Report this as a sensitivity note. | A repeated line can be a legitimate second scan, and the impact is immaterial. |
| Extreme order-and-reversal pairs | **Classify as `reversed_order`**, excluded from both sales and cancellations. Together they are £284,623 of gross value (about 2.8% of sales) that never became real revenue. | Including them would inflate gross sales, cancellation value and average order value. |
| "Unspecified" and "European Community" | **Keep in totals**, label as `Unspecified / EC`, exclude from country rankings and maps. Value is £5,909 (0.06%). | They are not countries, but the sales are real. |
| StockCode case variants | **Uppercase and trim** StockCode into `stock_code_clean`. | Avoids counting `15056bl` and `15056BL` as different products. |
| Product description | `product_name` = the most frequent trimmed, uppercased description among `sale` rows for that cleaned code. | Gives one stable name per product. |
| Customers in two countries | Country is a **transaction attribute**. A customer's home country is the country on their most recent sale. | 8 customers are affected, so the rule is simple. |
| December 2011 | **Keep the data, flag `is_partial_month`**. It appears in charts but is marked and excluded from growth calculations. | Data ends 9 December. |

## 3. Which line types each KPI uses

| KPI group | Includes | Excludes |
|---|---|---|
| **Gross sales** (revenue, units, orders, AOV, products, countries) | `sale` | everything else |
| **Net revenue** | `sale` + `cancellation` | everything else |
| **Cancellation KPIs** | `cancellation` | everything else |
| **Customer KPIs and RFM** | `sale` rows with a CustomerID | rows without a CustomerID |
| **Data-quality page** | all line types, shown as a reconciliation | none |

## 4. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | Quantity x UnitPrice, summed over `sale` rows |
| Orders | Distinct InvoiceNo among `sale` rows |
| Units sold | Sum of Quantity over `sale` rows |
| Average order value | Revenue / Orders |
| Net revenue | Revenue minus the absolute value of cancellations |
| Cancellation value | Absolute sum of Quantity x UnitPrice over `cancellation` rows |
| Cancellation rate (value) | Cancellation value / Revenue |
| Cancellation rate (orders) | Distinct "C" invoices / (distinct sale invoices + distinct "C" invoices) |
| Customers | Distinct CustomerID among `sale` rows |
| New vs returning (per month) | New = customer's first-ever sale month; returning = any later month |
| Repeat purchase rate | Customers with 2 or more distinct sale invoices / all customers |
| Month-over-month growth | (Month revenue - previous month) / previous month, computed only for full months |
| Product contribution % | Product revenue / total revenue |

Year-over-year growth is **not** reported, because the data covers only about 12 months. Profit is **not** reported, because the dataset has no cost data.

## 5. Baseline results (for later validation)

These are the numbers every later step (SQL, JSON exports, dashboard) must reproduce.

| Metric | Value |
|---|---|
| Revenue (gross sales) | £9,986,809.86 |
| Cancellation value | £233,070.98 |
| Net revenue | £9,753,738.88 |
| Orders | 19,770 |
| Units sold | 5,421,830 |
| Average order value | £505.15 |
| Distinct products sold | 3,797 |
| Customers with sales | 4,333 |
| Cancellation rate (value) | 2.33% |
| Cancelled invoices | 3,420 |
| Sales rows with no CustomerID | 131,421 rows, £1,510,366.41 (15.12% of revenue) |
| Customer-level revenue (rows with CustomerID) | £8,476,443.45 across 18,399 orders |

**Reading the cancellation numbers:** only 2.33% of revenue is cancelled by value, but 3,420 cancelled invoices relative to about 19,770 sales orders means cancellations are frequent and small. The business question for Step 7 is where and why.

## 6. Known limitations to state in the final report

1. About 15% of revenue has no customer, so customer analysis covers 85% of sales.
2. Some cancellations in early December 2010 may refer to sales made before the data starts.
3. Only one year of data is available, so seasonality can't be separated from growth.
4. No cost data exists, so profitability cannot be assessed.
5. The three reversed orders were identified through audit review (large value, reversed within minutes). A rule-based test ("fully reversed within 24 hours and above £5,000") finds the same three.

## 7. Columns the cleaned dataset will contain (built in Step 4)

`invoice_no`, `stock_code`, `stock_code_clean`, `product_name`, `quantity`, `invoice_date`, `unit_price`, `customer_id`, `country`, `country_group`, `revenue`, `line_type`, `is_duplicate`, `has_customer`, `is_cancelled`, `is_partial_month`, `invoice_month`
