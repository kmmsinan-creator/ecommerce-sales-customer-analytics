-- =====================================================================================
-- Step 5b: Product and country analysis (written for PostgreSQL)
-- Base filter: line_type = 'sale'   (see 03_business_rules.md)
-- Techniques: CTEs, RANK(), ROW_NUMBER(), running totals with window functions
-- =====================================================================================

-- Query 1: Top 10 products by revenue, with share and cumulative share -------------------
WITH product_totals AS (
    SELECT
        stock_code_clean,
        MAX(product_name)           AS product_name,
        SUM(revenue)                AS revenue,
        SUM(quantity)               AS units,
        COUNT(DISTINCT invoice_no)  AS orders
    FROM sales_clean
    WHERE line_type = 'sale'
    GROUP BY stock_code_clean
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY revenue DESC)  AS revenue_rank,
        100.0 * revenue / SUM(revenue) OVER () AS revenue_share_pct,
        100.0 * SUM(revenue) OVER (ORDER BY revenue DESC
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
              / SUM(revenue) OVER ()         AS cumulative_share_pct
    FROM product_totals
)
SELECT
    revenue_rank,
    stock_code_clean,
    product_name,
    ROUND(revenue, 2)                AS revenue,
    units,
    orders,
    ROUND(revenue / units, 2)        AS avg_selling_price,
    ROUND(revenue_share_pct, 2)      AS revenue_share_pct,
    ROUND(cumulative_share_pct, 2)   AS cumulative_share_pct
FROM ranked
WHERE revenue_rank <= 10
ORDER BY revenue_rank;


-- Query 2: Product concentration (Pareto): how many products make up 80% of revenue? -----
WITH product_totals AS (
    SELECT stock_code_clean, SUM(revenue) AS revenue
    FROM sales_clean
    WHERE line_type = 'sale'
    GROUP BY stock_code_clean
),
shares AS (
    SELECT
        revenue,
        100.0 * revenue / SUM(revenue) OVER () AS share_pct,
        100.0 * SUM(revenue) OVER (ORDER BY revenue DESC
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
              / SUM(revenue) OVER ()           AS cumulative_pct
    FROM product_totals
)
SELECT
    COUNT(*)                                              AS total_products,
    SUM(CASE WHEN cumulative_pct - share_pct < 80 THEN 1 ELSE 0 END) AS products_for_80pct_of_revenue,
    ROUND(100.0 * SUM(CASE WHEN cumulative_pct - share_pct < 80 THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                  AS pct_of_products
FROM shares;


-- Query 3: High volume, low value: top 50 by units sold, ranked by revenue too ----------
WITH product_totals AS (
    SELECT
        stock_code_clean,
        MAX(product_name) AS product_name,
        SUM(revenue)      AS revenue,
        SUM(quantity)     AS units
    FROM sales_clean
    WHERE line_type = 'sale'
    GROUP BY stock_code_clean
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY units DESC)   AS units_rank,
        RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
    FROM product_totals
)
SELECT
    units_rank,
    revenue_rank,
    revenue_rank - units_rank        AS rank_gap,
    product_name,
    units,
    ROUND(revenue, 2)                AS revenue,
    ROUND(revenue / units, 2)        AS avg_selling_price
FROM ranked
WHERE units_rank <= 50
ORDER BY rank_gap DESC
LIMIT 10;


-- Query 4: Country performance (Unspecified / EC kept out of the ranking) -----------------
WITH country_totals AS (
    SELECT
        country_group,
        SUM(revenue)                AS revenue,
        COUNT(DISTINCT invoice_no)  AS orders,
        COUNT(DISTINCT customer_id) AS customers
    FROM sales_clean
    WHERE line_type = 'sale'
      AND country_group <> 'Unspecified / EC'
    GROUP BY country_group
)
SELECT
    RANK() OVER (ORDER BY revenue DESC)                    AS revenue_rank,
    country_group,
    ROUND(revenue, 2)                                      AS revenue,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)       AS revenue_share_pct,
    orders,
    customers,
    ROUND(revenue / orders, 2)                             AS avg_order_value
FROM country_totals
ORDER BY revenue_rank
LIMIT 10;


-- Query 5: UK vs International ------------------------------------------------------------
SELECT
    market,
    ROUND(SUM(revenue), 2)                                         AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 2)     AS revenue_share_pct,
    COUNT(DISTINCT invoice_no)                                     AS orders,
    COUNT(DISTINCT customer_id)                                    AS customers,
    ROUND(SUM(revenue) / COUNT(DISTINCT invoice_no), 2)            AS avg_order_value,
    ROUND(SUM(revenue) / SUM(quantity), 2)                         AS avg_selling_price
FROM sales_clean
WHERE line_type = 'sale'
GROUP BY market
ORDER BY revenue DESC;


-- Query 6: Top 3 products in each of the 5 largest non-UK markets ------------------------
WITH country_rank AS (
    SELECT
        country_group,
        RANK() OVER (ORDER BY SUM(revenue) DESC) AS country_rank
    FROM sales_clean
    WHERE line_type = 'sale' AND market = 'International'
      AND country_group <> 'Unspecified / EC'
    GROUP BY country_group
),
product_by_country AS (
    SELECT
        s.country_group,
        s.stock_code_clean,
        MAX(s.product_name)  AS product_name,
        SUM(s.revenue)       AS revenue,
        ROW_NUMBER() OVER (PARTITION BY s.country_group ORDER BY SUM(s.revenue) DESC) AS product_rank
    FROM sales_clean s
    JOIN country_rank c ON c.country_group = s.country_group AND c.country_rank <= 5
    WHERE s.line_type = 'sale'
    GROUP BY s.country_group, s.stock_code_clean
)
SELECT country_group, product_rank, product_name, ROUND(revenue, 2) AS revenue
FROM product_by_country
WHERE product_rank <= 3
ORDER BY country_group, product_rank;
