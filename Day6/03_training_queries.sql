-- Training queries for sample retail data warehouse

-- View source data
SELECT * FROM src_orders;

-- View staging data
SELECT * FROM stg_orders;

-- View rejected records
SELECT * FROM rejected_orders;

-- View dimensions
SELECT * FROM dim_customer;
SELECT * FROM dim_product;
SELECT * FROM dim_store;
SELECT * FROM dim_date;

-- View fact table
SELECT * FROM fct_sales;

-- Sales by region and category
SELECT
    s.region,
    p.category,
    SUM(f.amount) AS total_sales,
    SUM(f.quantity) AS total_quantity
FROM fct_sales f
JOIN dim_store s ON f.store_key = s.store_key
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY s.region, p.category
ORDER BY total_sales DESC;

-- Customer sales
SELECT
    c.customer_name,
    c.city,
    SUM(f.amount) AS total_sales
FROM fct_sales f
JOIN dim_customer c ON f.customer_key = c.customer_key
GROUP BY c.customer_name, c.city
ORDER BY total_sales DESC;

-- Record count by layer
SELECT 'src_orders' AS table_name, COUNT(*) AS record_count FROM src_orders
UNION ALL
SELECT 'stg_orders', COUNT(*) FROM stg_orders
UNION ALL
SELECT 'rejected_orders', COUNT(*) FROM rejected_orders
UNION ALL
SELECT 'fct_sales', COUNT(*) FROM fct_sales;

-- Pipeline audit
SELECT * FROM pipeline_audit;