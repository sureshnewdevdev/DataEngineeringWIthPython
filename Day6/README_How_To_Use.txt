Sample Retail Data Warehouse Training Database
==============================================

Use this database to explain data warehouse operations in classroom training.

Main file:
- retail_datawarehouse_training.db

Recommended tool:
- DB Browser for SQLite
- VS Code SQLite extension
- Python sqlite3

Tables included:
1. Source layer:
   - src_customers
   - src_products
   - src_stores
   - src_orders

2. Staging layer:
   - stg_customers
   - stg_products
   - stg_stores
   - stg_orders

3. Rejection layer:
   - rejected_orders

4. Dimension layer:
   - dim_customer
   - dim_product
   - dim_store
   - dim_date

5. Fact layer:
   - fct_sales

6. Audit layer:
   - pipeline_audit

Training flow:
1. Show source tables.
2. Explain staging cleanup: trim names, lowercase emails, standardize values.
3. Show rejected_orders: invalid date, invalid quantity, customer not found.
4. Explain dimension tables and surrogate keys.
5. Explain fact table and joins with dimensions.
6. Run reporting queries from 03_training_queries.sql.