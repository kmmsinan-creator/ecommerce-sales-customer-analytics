-- =====================================================================================
-- Step 4: Create and load the cleaned analytical table  (PostgreSQL)
-- Source file : data/processed/online_retail_clean.csv  (built by notebooks/01_clean_data.py)
-- Rules       : reports/03_business_rules.md
-- Run from the repository root in psql, or use pgAdmin's Import/Export tool (see note).
-- =====================================================================================

DROP TABLE IF EXISTS sales_clean;

CREATE TABLE sales_clean (
    row_id            INTEGER        PRIMARY KEY,      -- position in the raw file (1-based)
    invoice_no        VARCHAR(10)    NOT NULL,
    stock_code        VARCHAR(20)    NOT NULL,         -- as in the raw file
    stock_code_clean  VARCHAR(20)    NOT NULL,         -- trimmed + uppercased
    product_name      VARCHAR(100),                    -- modal cleaned description (NULL if none exists)
    quantity          INTEGER        NOT NULL,
    invoice_date      TIMESTAMP      NOT NULL,
    unit_price        NUMERIC(12,4)  NOT NULL,
    customer_id       INTEGER,                         -- NULL for ~25% of rows
    country           VARCHAR(40)    NOT NULL,
    country_group     VARCHAR(40)    NOT NULL,         -- 'Unspecified / EC' for non-countries
    market            VARCHAR(15)    NOT NULL,         -- UK / International / Unknown
    revenue           NUMERIC(14,4)  NOT NULL,         -- quantity * unit_price
    line_type         VARCHAR(20)    NOT NULL,         -- see 03_business_rules.md section 1
    is_duplicate      BOOLEAN        NOT NULL,
    has_customer      BOOLEAN        NOT NULL,
    is_cancelled      BOOLEAN        NOT NULL,         -- raw InvoiceNo starts with 'C'
    is_partial_month  BOOLEAN        NOT NULL,         -- on/after 2011-12-01
    invoice_month     DATE           NOT NULL          -- first day of the invoice month
);

-- Load the CSV. Empty fields become NULL; 0/1 flags are accepted by BOOLEAN.
-- psql (run from the repository root):
\copy sales_clean FROM 'data/processed/online_retail_clean.csv' WITH (FORMAT csv, HEADER true)

-- pgAdmin alternative: right-click the table > Import/Export Data > Import,
-- Format = csv, Header = on, Delimiter = ','.

-- Indexes for the analysis queries in later steps (created after load for speed)
CREATE INDEX idx_sales_invoice_date  ON sales_clean (invoice_date);
CREATE INDEX idx_sales_customer      ON sales_clean (customer_id);
CREATE INDEX idx_sales_line_type     ON sales_clean (line_type);
CREATE INDEX idx_sales_stock_code    ON sales_clean (stock_code_clean);
CREATE INDEX idx_sales_country_group ON sales_clean (country_group);
CREATE INDEX idx_sales_invoice_no    ON sales_clean (invoice_no);

ANALYZE sales_clean;
