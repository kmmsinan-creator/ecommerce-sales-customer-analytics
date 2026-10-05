-- =====================================================================================
-- Step 5a: Sales KPIs and monthly trend (written for PostgreSQL)
-- Base filter for every query here: line_type = 'sale'   (see 03_business_rules.md)
-- =====================================================================================

-- Query 1: Headline KPIs (one row) -------------------------------------------------------
SELECT
    ROUND(SUM(revenue), 2)                          AS revenue,
    COUNT(DISTINCT invoice_no)                      AS orders,
    SUM(quantity)                                   AS units_sold,
    ROUND(SUM(revenue) / COUNT(DISTINCT invoice_no), 2) AS avg_order_value,
    COUNT(DISTINCT stock_code_clean)                AS products_sold,
    COUNT(DISTINCT customer_id)                     AS customers,
    ROUND(SUM(CASE WHEN customer_id IS NOT NULL THEN revenue ELSE 0 END)
          / COUNT(DISTINCT customer_id), 2)         AS revenue_per_customer
FROM sales_clean
WHERE line_type = 'sale';


-- Query 2: Monthly revenue with month-over-month growth ----------------------------------
-- Growth is blank for the partial month (Dec 2011) and for the first month.
WITH monthly AS (
    SELECT
        invoice_month,
        SUM(revenue)                    AS revenue,
        COUNT(DISTINCT invoice_no)      AS orders,
        SUM(quantity)                   AS units,
        COUNT(DISTINCT customer_id)     AS customers,
        MAX(CASE WHEN is_partial_month THEN 1 ELSE 0 END) AS is_partial
    FROM sales_clean
    WHERE line_type = 'sale'
    GROUP BY invoice_month
)
SELECT
    invoice_month,
    ROUND(revenue, 2)                   AS revenue,
    orders,
    units,
    customers,
    ROUND(revenue / orders, 2)          AS avg_order_value,
    CASE WHEN is_partial = 1 THEN NULL
         ELSE ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY invoice_month))
                          / LAG(revenue) OVER (ORDER BY invoice_month), 1)
    END                                 AS mom_growth_pct,
    CASE WHEN is_partial = 1 THEN 'partial month (to 9 Dec)' ELSE '' END AS note
FROM monthly
ORDER BY invoice_month;


-- Query 3: Monthly gross sales vs cancellations vs net revenue ---------------------------
SELECT
    invoice_month,
    ROUND(SUM(CASE WHEN line_type = 'sale'         THEN revenue ELSE 0 END), 2) AS gross_sales,
    ROUND(-SUM(CASE WHEN line_type = 'cancellation' THEN revenue ELSE 0 END), 2) AS cancellations,
    ROUND(SUM(CASE WHEN line_type IN ('sale', 'cancellation') THEN revenue ELSE 0 END), 2) AS net_revenue,
    ROUND(100.0 * -SUM(CASE WHEN line_type = 'cancellation' THEN revenue ELSE 0 END)
          / SUM(CASE WHEN line_type = 'sale' THEN revenue ELSE 0 END), 2)       AS cancellation_rate_pct
FROM sales_clean
WHERE line_type IN ('sale', 'cancellation')
GROUP BY invoice_month
ORDER BY invoice_month;
