-- =====================================================================================
-- Step 5d (part 1): Cancellation analysis (written for PostgreSQL)
-- Cancellations = line_type 'cancellation' (fees and the 3 reversed orders are excluded,
-- see 03_business_rules.md). Values are shown as positive amounts.
-- Techniques: CTEs, NTILE(), RANK(), conditional aggregation, joins to sales
-- =====================================================================================

-- Query 1: Cancellation KPIs ----------------------------------------------------------------
SELECT
    COUNT(DISTINCT invoice_no)                                  AS cancelled_invoices,
    COUNT(*)                                                    AS cancelled_lines,
    ROUND(-SUM(revenue), 2)                                     AS cancellation_value,
    ROUND(100.0 * -SUM(revenue)
          / (SELECT SUM(revenue) FROM sales_clean WHERE line_type = 'sale'), 2) AS rate_by_value_pct,
    ROUND(100.0 * COUNT(DISTINCT invoice_no)
          / (COUNT(DISTINCT invoice_no)
             + (SELECT COUNT(DISTINCT invoice_no) FROM sales_clean WHERE line_type = 'sale')), 2)
                                                                AS rate_by_orders_pct,
    ROUND(-SUM(CASE WHEN customer_id IS NULL THEN revenue ELSE 0 END), 2) AS value_without_customer
FROM sales_clean
WHERE line_type = 'cancellation';


-- Query 2: How concentrated are cancellations? (top 1% of cancelled invoices) ---------------
WITH cancel_invoices AS (
    SELECT invoice_no, -SUM(revenue) AS value
    FROM sales_clean
    WHERE line_type = 'cancellation'
    GROUP BY invoice_no
),
bucketed AS (
    SELECT value, NTILE(100) OVER (ORDER BY value DESC) AS percentile_bucket
    FROM cancel_invoices
)
SELECT
    COUNT(*)                                                    AS cancelled_invoices,
    ROUND(100.0 * SUM(CASE WHEN percentile_bucket = 1 THEN value ELSE 0 END)
          / SUM(value), 1)                                      AS top_1pct_share_of_value,
    ROUND(100.0 * SUM(CASE WHEN percentile_bucket <= 10 THEN value ELSE 0 END)
          / SUM(value), 1)                                      AS top_10pct_share_of_value,
    ROUND(AVG(value), 2)                                        AS avg_cancelled_invoice
FROM bucketed;


-- Query 3: The 10 largest cancelled invoices ---------------------------------------------------
SELECT
    RANK() OVER (ORDER BY -SUM(revenue) DESC)   AS value_rank,
    invoice_no,
    MAX(customer_id)                            AS customer_id,
    MIN(invoice_date)                           AS cancelled_at,
    COUNT(*)                                    AS lines,
    ROUND(-SUM(revenue), 2)                     AS value
FROM sales_clean
WHERE line_type = 'cancellation'
GROUP BY invoice_no
ORDER BY value_rank
LIMIT 10;


-- Query 4: Case study, the April 2011 spike -----------------------------------------------------
-- Invoice C550456 (customer 15749, 18 Apr 2011) is 69% of April's cancellations. The customer's
-- two January invoices total exactly the same value, and a new invoice was raised 12 minutes later.
-- That pattern looks like an order re-issued after an amendment, not lost demand.
SELECT
    invoice_no,
    MIN(invoice_date)               AS invoice_date,
    line_type,
    COUNT(*)                        AS lines,
    ROUND(SUM(revenue), 2)          AS value
FROM sales_clean
WHERE customer_id = 15749
  AND line_type IN ('sale', 'cancellation')
  AND invoice_no IN ('540815', '540818', 'C550456', '550461')
GROUP BY invoice_no, line_type
ORDER BY MIN(invoice_date);


-- Query 5: April 2011 cancellation rate with and without that one invoice ----------------------
SELECT
    ROUND(100.0 * -SUM(CASE WHEN line_type = 'cancellation' THEN revenue ELSE 0 END)
          / SUM(CASE WHEN line_type = 'sale' THEN revenue ELSE 0 END), 2)     AS rate_all_pct,
    ROUND(100.0 * -SUM(CASE WHEN line_type = 'cancellation' AND invoice_no <> 'C550456'
                            THEN revenue ELSE 0 END)
          / SUM(CASE WHEN line_type = 'sale' THEN revenue ELSE 0 END), 2)     AS rate_excluding_c550456_pct
FROM sales_clean
WHERE invoice_month = DATE '2011-04-01'
  AND line_type IN ('sale', 'cancellation');


-- Query 6: Products with the most cancelled value -------------------------------------------------
-- Rate is measured by value. Unit-based rates mislead here: some cancellations refer to sales
-- made before the data starts or are booked at a different price.
WITH sales_by_product AS (
    SELECT stock_code_clean, MAX(product_name) AS product_name, SUM(revenue) AS sales_value
    FROM sales_clean
    WHERE line_type = 'sale'
    GROUP BY stock_code_clean
),
cancel_by_product AS (
    SELECT stock_code_clean, -SUM(revenue) AS cancel_value, COUNT(DISTINCT invoice_no) AS cancel_invoices
    FROM sales_clean
    WHERE line_type = 'cancellation'
    GROUP BY stock_code_clean
)
SELECT
    RANK() OVER (ORDER BY c.cancel_value DESC)   AS cancel_rank,
    s.product_name,
    ROUND(c.cancel_value, 2)                     AS cancel_value,
    c.cancel_invoices,
    ROUND(s.sales_value, 2)                      AS sales_value,
    ROUND(100.0 * c.cancel_value / s.sales_value, 1) AS cancel_rate_pct
FROM cancel_by_product c
JOIN sales_by_product s ON s.stock_code_clean = c.stock_code_clean
ORDER BY cancel_rank
LIMIT 10;


-- Query 7: Customers with unusually high cancellation activity ------------------------------------
-- Customers whose cancellations exceed 20% of their own sales and total more than GBP 2,000.
WITH sales_by_customer AS (
    SELECT customer_id, SUM(revenue) AS sales_value
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL
    GROUP BY customer_id
),
cancel_by_customer AS (
    SELECT customer_id, -SUM(revenue) AS cancel_value, COUNT(DISTINCT invoice_no) AS cancel_invoices
    FROM sales_clean
    WHERE line_type = 'cancellation' AND customer_id IS NOT NULL
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    ROUND(c.cancel_value, 2)                          AS cancel_value,
    c.cancel_invoices,
    ROUND(s.sales_value, 2)                           AS sales_value,
    ROUND(100.0 * c.cancel_value / s.sales_value, 1)  AS cancel_pct_of_own_sales
FROM cancel_by_customer c
JOIN sales_by_customer s ON s.customer_id = c.customer_id
WHERE c.cancel_value > 2000
  AND c.cancel_value > 0.2 * s.sales_value
ORDER BY c.cancel_value DESC;


-- Query 8: Cancellation rate by country (countries with sales above GBP 50,000) -------------------
WITH by_country AS (
    SELECT
        country_group,
        SUM(CASE WHEN line_type = 'sale'         THEN revenue ELSE 0 END) AS sales_value,
        -SUM(CASE WHEN line_type = 'cancellation' THEN revenue ELSE 0 END) AS cancel_value
    FROM sales_clean
    WHERE line_type IN ('sale', 'cancellation')
      AND country_group <> 'Unspecified / EC'
    GROUP BY country_group
)
SELECT
    country_group,
    ROUND(sales_value, 2)                         AS sales_value,
    ROUND(cancel_value, 2)                        AS cancel_value,
    ROUND(100.0 * cancel_value / sales_value, 2)  AS cancel_rate_pct
FROM by_country
WHERE sales_value > 50000
ORDER BY cancel_rate_pct DESC;
