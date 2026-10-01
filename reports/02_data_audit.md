# Step 2: Raw Data Audit

**Source:** UCI Machine Learning Repository, *Online Retail* (CC BY 4.0)
**File:** `data/raw/Online_Retail.xlsx` (SHA-256 `43465a06f2ccf7c8b5bd2892bc7defb52f97487934fe93b16ae4c3936424676d`)
**Scope of this document:** measure and describe data-quality issues. **No data was modified.** Cleaning decisions are made in Step 3.

---

## 1. Structure

| Property | Value |
|---|---|
| Rows | 541,909 |
| Columns | 8 |
| Date range | 2010-12-01 08:26 to 2011-12-09 12:50 |
| Trading days with records | 305 |
| Unique invoices | 25,900 |
| Unique StockCodes | 4,070 |
| Unique customers | 4,372 (IDs 12346 to 18287) |
| Countries | 38 |

| Column | Type | Business meaning |
|---|---|---|
| InvoiceNo | text | Order or cancellation document |
| StockCode | text | Product code |
| Description | text | Product name |
| Quantity | integer | Units on the line |
| InvoiceDate | datetime | Time of the transaction |
| UnitPrice | decimal | Price per unit (GBP) |
| CustomerID | decimal | Customer (stored as float because of blanks) |
| Country | text | Customer country |

## 2. Findings summary

| # | Dimension | Finding | Rows / items | Severity |
|---|---|---|---|---|
| 1 | Completeness | Missing CustomerID | 135,080 (24.93%) | High |
| 2 | Completeness | Missing Description | 1,454 | Low |
| 3 | Duplicates | Exact duplicate rows (all 8 fields) | 5,268 | Low (about 0.23% of gross sales) |
| 4 | Cancellations | InvoiceNo starts with "C" | 9,288 | High (business-relevant) |
| 5 | Quantity | Negative quantities | 10,624 | High |
| 6 | Price | UnitPrice = 0 | 2,515 | Medium |
| 7 | Price | UnitPrice < 0 | 2 | Medium |
| 8 | Invoice format | Non-standard prefix "A" | 3 rows | Low |
| 9 | Product codes | Non-product codes (POST, DOT, M, AMAZONFEE, etc.) | about 33 codes | High (distorts revenue) |
| 10 | Product codes | Case-variant duplicate codes (e.g. 15056bl vs 15056BL) | 112 pairs | Medium |
| 11 | Product text | Codes with more than one description | 650 (647 after trim and uppercase) | Medium |
| 12 | Product text | Descriptions with leading or trailing spaces | 113,453 | Low (easy fix) |
| 13 | Geography | Customers appearing under more than one country | 8 | Low |
| 14 | Geography | Non-country values: "Unspecified" (446 rows), "European Community" (61 rows) | 507 | Low |
| 15 | Outliers | Extreme quantities (e.g. 80,995 and 74,215, each cancelled minutes later) | 116 rows above 1,000 units | High |
| 16 | Outliers | Extreme prices (up to 38,970), mostly manual and fee codes | 1,036 rows above 100 | Medium |
| 17 | Dates | Partial final month (data ends 9 December 2011) | n/a | High (for trend analysis) |
| 18 | Dates | No transactions on Saturdays | n/a | Info |

## 3. Detailed findings

### 3.1 Completeness

- **CustomerID:** 135,080 rows (24.93%) have no customer. 98.9% of them are in the United Kingdom. These rows are valid sales for revenue, product and country analysis but **cannot** be used for any customer-level analysis (RFM, repeat rate, cohorts).
- **Description:** 1,454 rows have no description. All of them have UnitPrice = 0 and no CustomerID, so they are internal stock adjustments and carry no revenue.

### 3.2 Duplicates

- 5,268 rows repeat all eight fields of an earlier row.
- Their net value is about 0.23% of gross sales, which is small.
- A repeated line can be a genuine second scan of the same item, so duplicates cannot be proven to be errors. Decision deferred to Step 3.

### 3.3 Cancellations and negative quantities

- 9,288 rows are on invoices starting with "C". Every one of them has a negative quantity, and no "C" invoice has a positive quantity.
- 10,624 rows have a negative quantity in total. The other 1,336 negative rows are **not** on "C" invoices; all 1,336 have UnitPrice = 0 and no CustomerID. They look like stock write-offs (descriptions such as "damaged", "check", "thrown away") rather than customer behavior.
- Customer 12346 placed one order of 74,215 units at 10:01 on 18 January 2011 and cancelled it at 10:17 the same day. Customer 16446 has a similar 80,995-unit order and cancellation. These two pairs would badly distort gross sales, cancellation value and average order value if left unexamined.

### 3.4 Prices

- 2,515 rows have UnitPrice = 0. Of these, 2,475 have no CustomerID (adjustments) and 40 have a customer (possibly free items or promotions).
- 2 rows have a negative price. They are "Adjust bad debt" entries on invoices A563186 and A563187.

### 3.5 Invoice format

- 532,618 rows are plain 6-digit invoices, 9,288 are "C" + 6 digits, and 3 rows use an "A" prefix (A563185 to A563187). The "A" invoices are bad-debt adjustments.
- No invoice has more than one customer or more than one country. 43 invoices span two timestamps, never more than one minute apart (normal for an order saved across a minute boundary).

### 3.6 Product codes and descriptions

- 4,070 distinct StockCodes, but 112 are case variants of another code (for example `15056bl` and `15056BL`). After uppercasing, 3,958 remain.
- About 33 codes are not real products (postage, manual entries, fees, discounts, samples, charity, bank charges, gift vouchers). Several carry large values, for example AMAZONFEE at about -£222k and DOT at about +£206k.
- 650 StockCodes have more than one description. Many are genuine changes of wording, but some are stock-note text typed into the Description field (for example "wrongly marked", "found").
- 113,453 descriptions have leading or trailing spaces and 22,290 contain double spaces. This would break grouping by product name.
- 3,037 descriptions are not fully uppercase, mostly manual notes plus a handful of real products with mixed case.

### 3.7 Geography

- The United Kingdom accounts for the large majority of rows (495,478 of 541,909).
- "Unspecified" (446 rows, 4 customers) and "European Community" (61 rows, 1 customer) are not countries and need a documented treatment in market analysis.
- 8 customers appear under two countries each (for example 12370: Cyprus and Austria). Country should be treated as a transaction attribute, not a fixed customer attribute.

### 3.8 Outliers

- Median positive quantity is 3 units, the 95th percentile is 30, the 99th is 100 and the 99.9th is about 450.
- 116 rows exceed 1,000 units. The largest are the two order-and-cancel pairs in 3.3 plus a few wholesale-size orders.
- Median positive price is £2.08. The highest prices belong to manual entries (up to £38,970) and Amazon fees (up to £17,836), not products.

### 3.9 Dates

- The data ends on 9 December 2011 (1,632 rows on the last day), so **December 2011 is a partial month** and must be excluded or footnoted in any monthly trend or growth figure.
- There are no Saturday transactions. Sunday trading is present. Transaction hours run from 06:00 to 20:59.
- Row volume rises sharply from September to November 2011 (50k, 61k, 85k rows per month), consistent with seasonal pre-Christmas demand. Because only one year is covered, year-over-year growth is not possible.

## 4. What this audit means for the project

1. **Revenue cannot be computed as Quantity x UnitPrice over all rows.** Fees, postage, manual entries and adjustments would distort it.
2. **Customer analytics must exclude the 24.93% of rows with no CustomerID**, and the analysis must state this limitation.
3. **Cancellations are a real business topic** and should be measured separately from gross sales instead of being deleted.
4. **Two extreme order-and-cancel pairs** need an explicit treatment, because they can dominate several KPIs.
5. **December 2011 is incomplete**, so month-over-month growth must handle it.

## 5. Open decisions (resolved in Step 3)

- Treatment of exact duplicates
- Treatment of the two extreme order-and-cancel pairs
- How to label "Unspecified" and "European Community"
- Normalisation of StockCode case and Description whitespace
- Whether the 40 zero-price rows with a customer count as sales
- Final flag definitions and which flags each KPI uses
