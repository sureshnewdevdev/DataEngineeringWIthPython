-- =============================================================================
-- RETAIL DATA WAREHOUSE - SQL SERVER SCHEMA
-- Architecture : Medallion (Source → Staging → Dimension / Fact + Audit)
-- Author       : Generated from CSV profiling
-- Date         : 2026-06-16
-- Compatibility: SQL Server 2016+
-- =============================================================================

-- =============================================================================
-- 0. DATABASE & SCHEMA SETUP
-- =============================================================================

USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'RetailDW')
    CREATE DATABASE RetailDW;
GO

USE RetailDW;
GO

-- Layered schemas mirror the medallion architecture
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'src')  EXEC('CREATE SCHEMA src');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stg')  EXEC('CREATE SCHEMA stg');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dim')  EXEC('CREATE SCHEMA dim');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'fct')  EXEC('CREATE SCHEMA fct');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit') EXEC('CREATE SCHEMA audit');
GO


-- =============================================================================
-- 1. SOURCE LAYER  (schema: src)
--    Raw data as received from operational systems.
--    No FK enforcement here — source quality is unknown.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- src.customers
-- -----------------------------------------------------------------------------
IF OBJECT_ID('src.customers', 'U') IS NOT NULL DROP TABLE src.customers;
GO

CREATE TABLE src.customers (
    customer_id     INT             NOT NULL,
    customer_name   NVARCHAR(150)   NOT NULL,
    email           NVARCHAR(255)   NOT NULL,
    city            NVARCHAR(100)   NULL,
    country         NVARCHAR(100)   NULL,
    updated_at      DATETIME2(0)    NOT NULL,

    CONSTRAINT PK_src_customers PRIMARY KEY (customer_id)
);
GO

-- -----------------------------------------------------------------------------
-- src.products
-- -----------------------------------------------------------------------------
IF OBJECT_ID('src.products', 'U') IS NOT NULL DROP TABLE src.products;
GO

CREATE TABLE src.products (
    product_id      INT             NOT NULL,
    product_name    NVARCHAR(200)   NOT NULL,
    category        NVARCHAR(100)   NULL,
    price           DECIMAL(12, 2)  NOT NULL,
    updated_at      DATETIME2(0)    NOT NULL,

    CONSTRAINT PK_src_products PRIMARY KEY (product_id)
);
GO

-- -----------------------------------------------------------------------------
-- src.stores
-- -----------------------------------------------------------------------------
IF OBJECT_ID('src.stores', 'U') IS NOT NULL DROP TABLE src.stores;
GO

CREATE TABLE src.stores (
    store_id        INT             NOT NULL,
    store_name      NVARCHAR(150)   NOT NULL,
    region          NVARCHAR(100)   NULL,
    city            NVARCHAR(100)   NULL,
    updated_at      DATETIME2(0)    NOT NULL,

    CONSTRAINT PK_src_stores PRIMARY KEY (store_id)
);
GO

-- -----------------------------------------------------------------------------
-- src.orders
-- Soft FK references only (no FOREIGN KEY constraint — raw source data)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('src.orders', 'U') IS NOT NULL DROP TABLE src.orders;
GO

CREATE TABLE src.orders (
    order_id        INT             NOT NULL,
    customer_id     INT             NOT NULL,   -- soft ref → src.customers
    product_id      INT             NOT NULL,   -- soft ref → src.products
    store_id        INT             NOT NULL,   -- soft ref → src.stores
    order_date      DATE            NULL,
    quantity        INT             NOT NULL,
    amount          DECIMAL(14, 2)  NOT NULL,
    order_status    NVARCHAR(50)    NOT NULL,
    updated_at      DATETIME2(0)    NOT NULL,

    CONSTRAINT PK_src_orders PRIMARY KEY (order_id)
);
GO


-- =============================================================================
-- 2. STAGING LAYER  (schema: stg)
--    Cleaned & standardised copies of source tables.
--    Adds processed_at audit timestamp; enforces basic FK relationships.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- stg.customers
-- -----------------------------------------------------------------------------
IF OBJECT_ID('stg.customers', 'U') IS NOT NULL DROP TABLE stg.customers;
GO

CREATE TABLE stg.customers (
    customer_id     INT             NOT NULL,
    customer_name   NVARCHAR(150)   NOT NULL,
    email           NVARCHAR(255)   NOT NULL,
    city            NVARCHAR(100)   NULL,
    country         NVARCHAR(100)   NULL,
    updated_at      DATETIME2(0)    NOT NULL,
    processed_at    DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME(),

    CONSTRAINT PK_stg_customers PRIMARY KEY (customer_id)
);
GO

-- -----------------------------------------------------------------------------
-- stg.products
-- -----------------------------------------------------------------------------
IF OBJECT_ID('stg.products', 'U') IS NOT NULL DROP TABLE stg.products;
GO

CREATE TABLE stg.products (
    product_id      INT             NOT NULL,
    product_name    NVARCHAR(200)   NOT NULL,
    category        NVARCHAR(100)   NULL,
    price           DECIMAL(12, 2)  NOT NULL,
    updated_at      DATETIME2(0)    NOT NULL,
    processed_at    DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME(),

    CONSTRAINT PK_stg_products PRIMARY KEY (product_id)
);
GO

-- -----------------------------------------------------------------------------
-- stg.stores
-- -----------------------------------------------------------------------------
IF OBJECT_ID('stg.stores', 'U') IS NOT NULL DROP TABLE stg.stores;
GO

CREATE TABLE stg.stores (
    store_id        INT             NOT NULL,
    store_name      NVARCHAR(150)   NOT NULL,
    region          NVARCHAR(100)   NULL,
    city            NVARCHAR(100)   NULL,
    updated_at      DATETIME2(0)    NOT NULL,
    processed_at    DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME(),

    CONSTRAINT PK_stg_stores PRIMARY KEY (store_id)
);
GO

-- -----------------------------------------------------------------------------
-- stg.orders
-- FK constraints enforced here — bad rows go to audit.rejected_orders instead
-- -----------------------------------------------------------------------------
IF OBJECT_ID('stg.orders', 'U') IS NOT NULL DROP TABLE stg.orders;
GO

CREATE TABLE stg.orders (
    order_id        INT             NOT NULL,
    customer_id     INT             NOT NULL,
    product_id      INT             NOT NULL,
    store_id        INT             NOT NULL,
    order_date      DATE            NOT NULL,
    quantity        INT             NOT NULL,
    amount          DECIMAL(14, 2)  NOT NULL,
    order_status    NVARCHAR(50)    NOT NULL,
    updated_at      DATETIME2(0)    NOT NULL,
    processed_at    DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME(),

    CONSTRAINT PK_stg_orders       PRIMARY KEY (order_id),
    CONSTRAINT FK_stg_orders_cust  FOREIGN KEY (customer_id) REFERENCES stg.customers (customer_id),
    CONSTRAINT FK_stg_orders_prod  FOREIGN KEY (product_id)  REFERENCES stg.products  (product_id),
    CONSTRAINT FK_stg_orders_store FOREIGN KEY (store_id)    REFERENCES stg.stores    (store_id),
    CONSTRAINT CHK_stg_orders_qty  CHECK (quantity > 0),
    CONSTRAINT CHK_stg_orders_amt  CHECK (amount   >= 0)
);
GO


-- =============================================================================
-- 3. DIMENSION LAYER  (schema: dim)
--    Conformed dimensions with surrogate keys.
--    dim.customer uses SCD Type 2 (history tracking).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- dim.date  — static calendar dimension, no FK dependencies
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dim.date', 'U') IS NOT NULL DROP TABLE dim.date;
GO

CREATE TABLE dim.date (
    date_key        INT             NOT NULL,   -- YYYYMMDD integer key
    full_date       DATE            NOT NULL,
    year            SMALLINT        NOT NULL,
    month           TINYINT         NOT NULL,
    day             TINYINT         NOT NULL,
    month_name      NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_dim_date          PRIMARY KEY (date_key),
    CONSTRAINT UQ_dim_date_full     UNIQUE      (full_date),
    CONSTRAINT CHK_dim_date_month   CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT CHK_dim_date_day     CHECK (day   BETWEEN 1 AND 31)
);
GO

-- -----------------------------------------------------------------------------
-- dim.customer  — SCD Type 2
--    effective_to NULL means the record is current (same as is_current = 1)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dim.customer', 'U') IS NOT NULL DROP TABLE dim.customer;
GO

CREATE TABLE dim.customer (
    customer_key    INT             NOT NULL    IDENTITY(1, 1),
    customer_id     INT             NOT NULL,   -- natural / business key
    customer_name   NVARCHAR(150)   NOT NULL,
    email           NVARCHAR(255)   NOT NULL,
    city            NVARCHAR(100)   NULL,
    country         NVARCHAR(100)   NULL,
    effective_from  DATETIME2(0)    NOT NULL,
    effective_to    DATETIME2(0)    NULL,       -- NULL = current record
    is_current      BIT             NOT NULL    DEFAULT 1,

    CONSTRAINT PK_dim_customer      PRIMARY KEY (customer_key),
    CONSTRAINT CHK_dim_cust_dates   CHECK (effective_to IS NULL OR effective_to > effective_from)
);
GO

CREATE INDEX IX_dim_customer_bk ON dim.customer (customer_id, is_current);
GO

-- -----------------------------------------------------------------------------
-- dim.product
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dim.product', 'U') IS NOT NULL DROP TABLE dim.product;
GO

CREATE TABLE dim.product (
    product_key     INT             NOT NULL    IDENTITY(1, 1),
    product_id      INT             NOT NULL,   -- natural key
    product_name    NVARCHAR(200)   NOT NULL,
    category        NVARCHAR(100)   NULL,
    price           DECIMAL(12, 2)  NOT NULL,

    CONSTRAINT PK_dim_product       PRIMARY KEY (product_key),
    CONSTRAINT UQ_dim_product_id    UNIQUE      (product_id)
);
GO

-- -----------------------------------------------------------------------------
-- dim.store
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dim.store', 'U') IS NOT NULL DROP TABLE dim.store;
GO

CREATE TABLE dim.store (
    store_key       INT             NOT NULL    IDENTITY(1, 1),
    store_id        INT             NOT NULL,   -- natural key
    store_name      NVARCHAR(150)   NOT NULL,
    region          NVARCHAR(100)   NULL,
    city            NVARCHAR(100)   NULL,

    CONSTRAINT PK_dim_store         PRIMARY KEY (store_key),
    CONSTRAINT UQ_dim_store_id      UNIQUE      (store_id)
);
GO


-- =============================================================================
-- 4. FACT LAYER  (schema: fct)
--    Grain: one row per order line.
--    All four dimensions referenced via surrogate keys.
-- =============================================================================

IF OBJECT_ID('fct.sales', 'U') IS NOT NULL DROP TABLE fct.sales;
GO

CREATE TABLE fct.sales (
    sales_key       INT             NOT NULL    IDENTITY(1, 1),
    order_id        INT             NOT NULL,
    customer_key    INT             NOT NULL,
    product_key     INT             NOT NULL,
    store_key       INT             NOT NULL,
    date_key        INT             NOT NULL,
    quantity        INT             NOT NULL,
    amount          DECIMAL(14, 2)  NOT NULL,
    order_status    NVARCHAR(50)    NOT NULL,

    CONSTRAINT PK_fct_sales             PRIMARY KEY (sales_key),
    CONSTRAINT UQ_fct_sales_order       UNIQUE      (order_id),
    CONSTRAINT FK_fct_sales_customer    FOREIGN KEY (customer_key) REFERENCES dim.customer (customer_key),
    CONSTRAINT FK_fct_sales_product     FOREIGN KEY (product_key)  REFERENCES dim.product  (product_key),
    CONSTRAINT FK_fct_sales_store       FOREIGN KEY (store_key)    REFERENCES dim.store    (store_key),
    CONSTRAINT FK_fct_sales_date        FOREIGN KEY (date_key)     REFERENCES dim.date     (date_key),
    CONSTRAINT CHK_fct_sales_qty        CHECK (quantity > 0),
    CONSTRAINT CHK_fct_sales_amt        CHECK (amount   >= 0)
);
GO

-- Covering indexes for common analytical query patterns
CREATE INDEX IX_fct_sales_customer ON fct.sales (customer_key) INCLUDE (amount, quantity);
CREATE INDEX IX_fct_sales_product  ON fct.sales (product_key)  INCLUDE (amount, quantity);
CREATE INDEX IX_fct_sales_store    ON fct.sales (store_key)    INCLUDE (amount, quantity);
CREATE INDEX IX_fct_sales_date     ON fct.sales (date_key)     INCLUDE (amount, quantity);
GO


-- =============================================================================
-- 5. AUDIT LAYER  (schema: audit)
--    Pipeline execution log + rejected-record quarantine.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- audit.pipeline_audit
-- -----------------------------------------------------------------------------
IF OBJECT_ID('audit.pipeline_audit', 'U') IS NOT NULL DROP TABLE audit.pipeline_audit;
GO

CREATE TABLE audit.pipeline_audit (
    audit_id        INT             NOT NULL    IDENTITY(1, 1),
    pipeline_name   NVARCHAR(200)   NOT NULL,
    layer_name      NVARCHAR(100)   NOT NULL,
    input_count     INT             NOT NULL    DEFAULT 0,
    output_count    INT             NOT NULL    DEFAULT 0,
    rejected_count  INT             NOT NULL    DEFAULT 0,
    status          NVARCHAR(50)    NOT NULL,   -- SUCCESS | FAILED | PARTIAL
    execution_time  DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME(),
    comments        NVARCHAR(1000)  NULL,

    CONSTRAINT PK_audit_pipeline    PRIMARY KEY (audit_id),
    CONSTRAINT CHK_audit_counts     CHECK (
        input_count    >= 0 AND
        output_count   >= 0 AND
        rejected_count >= 0 AND
        output_count + rejected_count <= input_count
    ),
    CONSTRAINT CHK_audit_status     CHECK (status IN ('SUCCESS', 'FAILED', 'PARTIAL'))
);
GO

-- -----------------------------------------------------------------------------
-- audit.rejected_orders
--    Quarantine table — accepts dirty data so order_date is NVARCHAR(50)
--    and FK constraints are intentionally absent.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('audit.rejected_orders', 'U') IS NOT NULL DROP TABLE audit.rejected_orders;
GO

CREATE TABLE audit.rejected_orders (
    rejection_id        INT             NOT NULL    IDENTITY(1, 1),
    order_id            INT             NULL,
    customer_id         INT             NULL,
    product_id          INT             NULL,
    store_id            INT             NULL,
    order_date          NVARCHAR(50)    NULL,       -- kept as VARCHAR — may be malformed
    quantity            DECIMAL(14, 2)  NULL,
    amount              DECIMAL(14, 2)  NULL,
    order_status        NVARCHAR(50)    NULL,
    rejection_reason    NVARCHAR(500)   NOT NULL,
    rejected_at         DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME(),

    CONSTRAINT PK_rejected_orders   PRIMARY KEY (rejection_id)
);
GO

CREATE INDEX IX_rejected_orders_order_id ON audit.rejected_orders (order_id);
GO


-- =============================================================================
-- 6. HELPER VIEW — full sales detail (star join)
-- =============================================================================

IF OBJECT_ID('dbo.vw_sales_detail', 'V') IS NOT NULL DROP VIEW dbo.vw_sales_detail;
GO

CREATE VIEW dbo.vw_sales_detail AS
SELECT
    fs.sales_key,
    fs.order_id,
    fs.order_status,

    -- Date
    dd.full_date        AS order_date,
    dd.year,
    dd.month_name,

    -- Customer
    dc.customer_id,
    dc.customer_name,
    dc.email,
    dc.city             AS customer_city,
    dc.country,

    -- Product
    dp.product_id,
    dp.product_name,
    dp.category,
    dp.price            AS unit_price,

    -- Store
    ds.store_id,
    ds.store_name,
    ds.region,
    ds.city             AS store_city,

    -- Measures
    fs.quantity,
    fs.amount
FROM       fct.sales       fs
JOIN       dim.customer    dc ON fs.customer_key = dc.customer_key
JOIN       dim.product     dp ON fs.product_key  = dp.product_key
JOIN       dim.store       ds ON fs.store_key    = ds.store_key
JOIN       dim.date        dd ON fs.date_key     = dd.date_key
WHERE      dc.is_current = 1;   -- only current customer version
GO


-- =============================================================================
-- END OF SCRIPT
-- =============================================================================
