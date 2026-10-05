-- =====================================================================================
-- Step 5d (part 2): Cohort retention (written for PostgreSQL)
-- Cohort = month of a customer's first purchase. Retention = share of that cohort buying again
-- k months later. Customers without a CustomerID are excluded. December 2011 is left out entirely
-- (partial month). The December 2010 cohort contains every customer active in the first month of
-- data, including long-standing ones, so it is not a true "new customer" cohort.
-- Techniques: CTEs, DENSE_RANK() as a month index, cohort x month grid, LEFT JOIN
-- =====================================================================================

-- Query 1: Retention table in long format (one row per cohort and months since first purchase) ---
WITH customer_months AS (
    SELECT DISTINCT customer_id, invoice_month
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL AND NOT is_partial_month
),
month_index AS (
    SELECT invoice_month, DENSE_RANK() OVER (ORDER BY invoice_month) AS month_idx
    FROM (SELECT DISTINCT invoice_month FROM customer_months) m
),
cohorts AS (
    SELECT customer_id, MIN(invoice_month) AS cohort_month
    FROM customer_months
    GROUP BY customer_id
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM cohorts
    GROUP BY cohort_month
),
grid AS (
    SELECT cs.cohort_month, cs.cohort_size, mi.invoice_month,
           mi.month_idx - ci.month_idx AS months_since
    FROM cohort_sizes cs
    JOIN month_index ci ON ci.invoice_month = cs.cohort_month
    JOIN month_index mi ON mi.month_idx >= ci.month_idx
),
activity AS (
    SELECT co.cohort_month, cm.invoice_month, COUNT(*) AS active_customers
    FROM customer_months cm
    JOIN cohorts co ON co.customer_id = cm.customer_id
    GROUP BY co.cohort_month, cm.invoice_month
)
SELECT
    g.cohort_month,
    g.months_since,
    g.cohort_size,
    COALESCE(a.active_customers, 0)                                  AS active_customers,
    ROUND(100.0 * COALESCE(a.active_customers, 0) / g.cohort_size, 1) AS retention_pct
FROM grid g
LEFT JOIN activity a
       ON a.cohort_month = g.cohort_month AND a.invoice_month = g.invoice_month
ORDER BY g.cohort_month, g.months_since;


-- Query 2: Average retention curve across cohorts (December 2010 cohort excluded) ----------------
-- Weighted by cohort size. Only cohorts old enough to have reached month k are counted at month k.
WITH customer_months AS (
    SELECT DISTINCT customer_id, invoice_month
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL AND NOT is_partial_month
),
month_index AS (
    SELECT invoice_month, DENSE_RANK() OVER (ORDER BY invoice_month) AS month_idx
    FROM (SELECT DISTINCT invoice_month FROM customer_months) m
),
cohorts AS (
    SELECT customer_id, MIN(invoice_month) AS cohort_month
    FROM customer_months
    GROUP BY customer_id
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM cohorts
    GROUP BY cohort_month
),
grid AS (
    SELECT cs.cohort_month, cs.cohort_size, mi.invoice_month,
           mi.month_idx - ci.month_idx AS months_since
    FROM cohort_sizes cs
    JOIN month_index ci ON ci.invoice_month = cs.cohort_month
    JOIN month_index mi ON mi.month_idx >= ci.month_idx
),
activity AS (
    SELECT co.cohort_month, cm.invoice_month, COUNT(*) AS active_customers
    FROM customer_months cm
    JOIN cohorts co ON co.customer_id = cm.customer_id
    GROUP BY co.cohort_month, cm.invoice_month
),
retention AS (
    SELECT g.cohort_month, g.months_since, g.cohort_size,
           COALESCE(a.active_customers, 0) AS active_customers
    FROM grid g
    LEFT JOIN activity a
           ON a.cohort_month = g.cohort_month AND a.invoice_month = g.invoice_month
    WHERE g.cohort_month > DATE '2010-12-01'
)
SELECT
    months_since,
    COUNT(*)                                                    AS cohorts_included,
    SUM(cohort_size)                                            AS customers,
    SUM(active_customers)                                       AS active_customers,
    ROUND(100.0 * SUM(active_customers) / SUM(cohort_size), 1)  AS avg_retention_pct
FROM retention
GROUP BY months_since
ORDER BY months_since;
