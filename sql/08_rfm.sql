-- =====================================================================================
-- Step 6: RFM customer segmentation (written for PostgreSQL)
-- Population: customers with at least one sale and a CustomerID (4,333 customers, GBP 8.48M).
-- Snapshot date: 2011-12-10, the day after the last transaction in the data.
--
-- Scores use fixed business cutoffs (not quintiles), because most customers share the same
-- order count and quintiles would split identical customers into different scores.
--   Recency (days since last purchase): <=30 = 5, <=90 = 4, <=180 = 3, <=270 = 2, else 1
--   Frequency (distinct orders):        1 = 1, 2 = 2, 3-4 = 3, 5-9 = 4, 10+ = 5
--   Monetary: quintiles of total spend (5 = highest). Reported, but segments are defined
--             by R and F so that spend can be compared across segments.
--
-- Segments (first matching row of this table applies):
--   Champions            R >= 4 and F >= 4
--   Loyal Customers      R >= 3 and F >= 3 (not Champions)
--   Potential Loyalists  R >= 4 and F = 2
--   Recent Customers     R >= 4 and F = 1
--   Needs Attention      R = 3 and F <= 2
--   At Risk              R <= 2 and F >= 3
--   Lost Customers       R <= 2 and F <= 2
-- Techniques: view, CTEs, CASE, NTILE(), window functions, date arithmetic
-- =====================================================================================

CREATE OR REPLACE VIEW rfm_customers AS
WITH params AS (
    SELECT DATE '2011-12-10' AS snapshot_date
),
customer_metrics AS (
    SELECT
        customer_id,
        MAX(invoice_date)          AS last_purchase,
        COUNT(DISTINCT invoice_no) AS frequency,
        SUM(revenue)               AS monetary
    FROM sales_clean
    WHERE line_type = 'sale' AND customer_id IS NOT NULL
    GROUP BY customer_id
),
rfm AS (
    SELECT
        m.*,
        p.snapshot_date - CAST(m.last_purchase AS DATE) AS recency_days
    FROM customer_metrics m
    CROSS JOIN params p
),
scored AS (
    SELECT
        *,
        CASE WHEN recency_days <= 30  THEN 5
             WHEN recency_days <= 90  THEN 4
             WHEN recency_days <= 180 THEN 3
             WHEN recency_days <= 270 THEN 2
             ELSE 1 END                          AS r_score,
        CASE WHEN frequency = 1  THEN 1
             WHEN frequency = 2  THEN 2
             WHEN frequency <= 4 THEN 3
             WHEN frequency <= 9 THEN 4
             ELSE 5 END                          AS f_score,
        NTILE(5) OVER (ORDER BY monetary)        AS m_score
    FROM rfm
)
SELECT
    customer_id,
    last_purchase,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r_score,
    f_score,
    m_score,
    CASE WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
         WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
         WHEN r_score >= 4 AND f_score = 2  THEN 'Potential Loyalists'
         WHEN r_score >= 4 AND f_score = 1  THEN 'Recent Customers'
         WHEN r_score = 3                   THEN 'Needs Attention'
         WHEN f_score >= 3                  THEN 'At Risk'
         ELSE 'Lost Customers'
    END AS segment
FROM scored;


-- Query 1: Segment summary --------------------------------------------------------------------
SELECT
    segment,
    COUNT(*)                                                     AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_of_customers,
    ROUND(SUM(monetary), 2)                                      AS revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue,
    ROUND(AVG(recency_days), 0)                                  AS avg_recency_days,
    ROUND(AVG(frequency), 1)                                     AS avg_orders,
    ROUND(AVG(monetary), 2)                                      AS avg_spend
FROM rfm_customers
GROUP BY segment
ORDER BY SUM(monetary) DESC;


-- Query 2: Recency x Frequency score grid (customer counts, for a heatmap) ------------------------
SELECT
    r_score,
    SUM(CASE WHEN f_score = 1 THEN 1 ELSE 0 END) AS f1,
    SUM(CASE WHEN f_score = 2 THEN 1 ELSE 0 END) AS f2,
    SUM(CASE WHEN f_score = 3 THEN 1 ELSE 0 END) AS f3,
    SUM(CASE WHEN f_score = 4 THEN 1 ELSE 0 END) AS f4,
    SUM(CASE WHEN f_score = 5 THEN 1 ELSE 0 END) AS f5
FROM rfm_customers
GROUP BY r_score
ORDER BY r_score DESC;


-- Query 3: Win-back list, the 10 highest-spending At Risk customers ---------------------------------
SELECT
    customer_id,
    CAST(last_purchase AS DATE) AS last_purchase,
    recency_days,
    frequency                   AS orders,
    monetary                    AS total_spend,
    ROUND(monetary / frequency, 2) AS avg_order_value
FROM rfm_customers
WHERE segment = 'At Risk'
ORDER BY monetary DESC
LIMIT 10;


-- Query 4: Reconciliation, must give 4,333 customers and 8,476,443.45 -------------------------------
SELECT COUNT(*) AS customers, ROUND(SUM(monetary), 2) AS revenue
FROM rfm_customers;
