-- =====================================================================================
-- Step 5c: Customer analysis (written for PostgreSQL)
-- Base filter: line_type = 'sale' AND customer_id IS NOT NULL
-- This covers about 85% of revenue (rows without a CustomerID cannot be analysed per customer).
-- Techniques: CTEs, NTILE(), RANK(), MIN() per customer, conditional aggregation
-- =====================================================================================

-- Query 1: Customer KPIs --------------------------------------------------------------------
WITH customer_totals AS (
    SELECT
        customer_id,
        SUM(revenue)               AS revenue,
        COUNT(DISTINCT invoice_no) AS orders
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL
    GROUP BY customer_id
)
SELECT
    COUNT(*)                                                          AS customers,
    ROUND(SUM(revenue), 2)                                            AS customer_revenue,
    ROUND(AVG(revenue), 2)                                            AS avg_spend_per_customer,
    ROUND(1.0 * SUM(orders) / COUNT(*), 2)                            AS avg_orders_per_customer,
    SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END)                      AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_purchase_rate_pct
FROM customer_totals;


-- Query 2: Revenue concentration by customer decile (decile 1 = top 10% of customers) -------
WITH customer_totals AS (
    SELECT customer_id, SUM(revenue) AS revenue
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL
    GROUP BY customer_id
),
deciles AS (
    SELECT customer_id, revenue,
           NTILE(10) OVER (ORDER BY revenue DESC) AS decile
    FROM customer_totals
)
SELECT
    decile,
    COUNT(*)                                             AS customers,
    ROUND(SUM(revenue), 2)                               AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS revenue_share_pct,
    ROUND(100.0 * SUM(SUM(revenue)) OVER (ORDER BY decile)
          / SUM(SUM(revenue)) OVER (), 1)                AS cumulative_share_pct
FROM deciles
GROUP BY decile
ORDER BY decile;


-- Query 3: Top 10 customers ------------------------------------------------------------------
WITH customer_totals AS (
    SELECT
        customer_id,
        SUM(revenue)               AS revenue,
        COUNT(DISTINCT invoice_no) AS orders,
        MIN(invoice_date)          AS first_purchase,
        MAX(invoice_date)          AS last_purchase
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL
    GROUP BY customer_id
)
SELECT
    RANK() OVER (ORDER BY revenue DESC)                          AS revenue_rank,
    customer_id,
    ROUND(revenue, 2)                                            AS revenue,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)             AS share_of_customer_revenue_pct,
    orders,
    ROUND(revenue / orders, 2)                                   AS avg_order_value,
    first_purchase,
    last_purchase
FROM customer_totals
ORDER BY revenue_rank
LIMIT 10;


-- Query 4: Orders per customer (purchase frequency distribution) -----------------------------
WITH customer_orders AS (
    SELECT customer_id, COUNT(DISTINCT invoice_no) AS orders, SUM(revenue) AS revenue
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL
    GROUP BY customer_id
)
SELECT
    CASE WHEN orders = 1  THEN '1 order'
         WHEN orders <= 3 THEN '2-3 orders'
         WHEN orders <= 9 THEN '4-9 orders'
         ELSE '10+ orders' END                           AS frequency_band,
    COUNT(*)                                             AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)   AS pct_of_customers,
    ROUND(SUM(revenue), 2)                               AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_of_revenue
FROM customer_orders
GROUP BY CASE WHEN orders = 1  THEN '1 order'
              WHEN orders <= 3 THEN '2-3 orders'
              WHEN orders <= 9 THEN '4-9 orders'
              ELSE '10+ orders' END
ORDER BY MIN(orders);


-- Query 5: New vs returning customers by month ------------------------------------------------
-- New = the customer's first purchase month in the data. Dec 2010 is the first month of data,
-- so every customer there counts as "new" by construction. Dec 2011 is a partial month.
WITH customer_months AS (
    SELECT DISTINCT customer_id, invoice_month
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL
),
first_month AS (
    SELECT customer_id, MIN(invoice_month) AS first_month
    FROM customer_months
    GROUP BY customer_id
)
SELECT
    cm.invoice_month,
    COUNT(*)                                                         AS active_customers,
    SUM(CASE WHEN cm.invoice_month =  f.first_month THEN 1 ELSE 0 END) AS new_customers,
    SUM(CASE WHEN cm.invoice_month >  f.first_month THEN 1 ELSE 0 END) AS returning_customers,
    ROUND(100.0 * SUM(CASE WHEN cm.invoice_month > f.first_month THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                             AS returning_pct
FROM customer_months cm
JOIN first_month f ON f.customer_id = cm.customer_id
GROUP BY cm.invoice_month
ORDER BY cm.invoice_month;
