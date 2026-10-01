-- =====================================================================================
-- Step 4: Validate the loaded table against the locked baselines (03_business_rules.md)
-- Every row of the result must show PASS. If any shows FAIL, the load is wrong.
-- =====================================================================================

WITH sales AS (
    SELECT * FROM sales_clean WHERE line_type = 'sale'
),
cancels AS (
    SELECT * FROM sales_clean WHERE line_type = 'cancellation'
),
actuals AS (
    SELECT 'Rows loaded'                  AS check_name, 541909      AS expected, 0.0  AS tolerance,
           (SELECT COUNT(*) FROM sales_clean)                        AS actual
    UNION ALL SELECT 'Total revenue (all rows)',   9747747.93, 0.5,
           (SELECT SUM(revenue) FROM sales_clean)
    UNION ALL SELECT 'Revenue (gross sales)',      9986809.86, 0.5,
           (SELECT SUM(revenue) FROM sales)
    UNION ALL SELECT 'Cancellation value',          233070.98, 0.5,
           (SELECT -SUM(revenue) FROM cancels)
    UNION ALL SELECT 'Net revenue',                9753738.88, 0.5,
           (SELECT SUM(revenue) FROM sales) + (SELECT SUM(revenue) FROM cancels)
    UNION ALL SELECT 'Orders',                         19770, 0,
           (SELECT COUNT(DISTINCT invoice_no) FROM sales)
    UNION ALL SELECT 'Units sold',                   5421830, 0,
           (SELECT SUM(quantity) FROM sales)
    UNION ALL SELECT 'Average order value',           505.15, 0.01,
           (SELECT SUM(revenue) / COUNT(DISTINCT invoice_no) FROM sales)
    UNION ALL SELECT 'Distinct products sold',          3797, 0,
           (SELECT COUNT(DISTINCT stock_code_clean) FROM sales)
    UNION ALL SELECT 'Customers with sales',            4333, 0,
           (SELECT COUNT(DISTINCT customer_id) FROM sales)
    UNION ALL SELECT 'Cancelled invoices',              3420, 0,
           (SELECT COUNT(DISTINCT invoice_no) FROM cancels)
    UNION ALL SELECT 'Sales rows with no CustomerID', 131421, 0,
           (SELECT COUNT(*) FROM sales WHERE customer_id IS NULL)
    UNION ALL SELECT 'Customer-level revenue',     8476443.45, 0.5,
           (SELECT SUM(revenue) FROM sales WHERE customer_id IS NOT NULL)
    UNION ALL SELECT 'Customer-level orders',           18399, 0,
           (SELECT COUNT(DISTINCT invoice_no) FROM sales WHERE customer_id IS NOT NULL)
    UNION ALL SELECT 'Duplicate rows within sales',      5221, 0,
           (SELECT COUNT(*) FROM sales WHERE is_duplicate)
)
SELECT check_name,
       expected,
       ROUND(actual, 2) AS actual,
       CASE WHEN ABS(actual - expected) <= tolerance THEN 'PASS' ELSE 'FAIL' END AS result
FROM actuals;

-- Reconciliation by line type: the net_value column must total 9,747,747.93
SELECT line_type,
       COUNT(*)               AS row_count,
       ROUND(SUM(revenue), 2) AS net_value
FROM sales_clean
GROUP BY line_type
ORDER BY row_count DESC;
