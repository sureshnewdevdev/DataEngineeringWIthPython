# Data Warehouse Schema Documentation

## Overview

This dataset represents a **Retail Data Warehouse** with a classic medallion-style layered architecture:

| Layer | Tables | Purpose |
|---|---|---|
| **Source (src)** | src_customers, src_orders, src_products, src_stores | Raw ingested data |
| **Staging (stg)** | stg_customers, stg_orders, stg_products, stg_stores | Cleaned & standardized |
| **Dimension (dim)** | dim_customer, dim_date, dim_product, dim_store | Conformed dimensions |
| **Fact (fct)** | fct_sales | Core analytical fact table |
| **Audit/Quality** | pipeline_audit, rejected_orders | Data quality & observability |

---

## Source Layer

### `src_customers`
Raw customer data from the source system.

| Column | Type | Description |
|---|---|---|
| customer_id | INTEGER | Primary key |
| customer_name | VARCHAR | Full name |
| email | VARCHAR | Email address |
| city | VARCHAR | City of residence |
| country | VARCHAR | Country |
| updated_at | TIMESTAMP | Last updated in source |

**Row count:** ~5

---

### `src_orders`
Raw transactional order data from the source system.

| Column | Type | Description |
|---|---|---|
| order_id | INTEGER | Primary key |
| customer_id | INTEGER | FK → src_customers |
| product_id | INTEGER | FK → src_products |
| store_id | INTEGER | FK → src_stores |
| order_date | DATE/TIMESTAMP | Date of order |
| quantity | INTEGER | Units ordered |
| amount | DECIMAL | Order amount |
| order_status | VARCHAR | e.g. Completed, Cancelled, Pending |
| updated_at | TIMESTAMP | Last updated in source |

**Row count:** ~8

---

### `src_products`
Raw product catalog from the source system.

| Column | Type | Description |
|---|---|---|
| product_id | INTEGER | Primary key |
| product_name | VARCHAR | Product name |
| category | VARCHAR | Product category (e.g. Electronics) |
| price | DECIMAL | Unit price |
| updated_at | TIMESTAMP | Last updated in source |

**Row count:** ~4

---

### `src_stores`
Raw store master data from the source system.

| Column | Type | Description |
|---|---|---|
| store_id | INTEGER | Primary key |
| store_name | VARCHAR | Store name |
| region | VARCHAR | Geographic region |
| city | VARCHAR | City |
| updated_at | TIMESTAMP | Last updated in source |

**Row count:** ~3

---

## Staging Layer

### `stg_customers`
Cleaned and standardized customers. Adds `processed_at` audit column.

| Column | Type | Description |
|---|---|---|
| customer_id | INTEGER | Primary key |
| customer_name | VARCHAR | Full name |
| email | VARCHAR | Email address |
| city | VARCHAR | City |
| country | VARCHAR | Country |
| updated_at | TIMESTAMP | Last updated in source |
| processed_at | TIMESTAMP | When this record was staged |

---

### `stg_orders`
Cleaned and validated orders. Adds `processed_at` audit column.

| Column | Type | Description |
|---|---|---|
| order_id | INTEGER | Primary key |
| customer_id | INTEGER | FK → stg_customers |
| product_id | INTEGER | FK → stg_products |
| store_id | INTEGER | FK → stg_stores |
| order_date | DATE/TIMESTAMP | Date of order |
| quantity | INTEGER | Units ordered |
| amount | DECIMAL | Order amount |
| order_status | VARCHAR | Order status |
| updated_at | TIMESTAMP | Last updated in source |
| processed_at | TIMESTAMP | When this record was staged |

---

### `stg_products`
Cleaned product data. Adds `processed_at` audit column.

| Column | Type | Description |
|---|---|---|
| product_id | INTEGER | Primary key |
| product_name | VARCHAR | Product name |
| category | VARCHAR | Product category |
| price | DECIMAL | Unit price |
| updated_at | TIMESTAMP | Last updated in source |
| processed_at | TIMESTAMP | When this record was staged |

---

### `stg_stores`
Cleaned store data. Adds `processed_at` audit column.

| Column | Type | Description |
|---|---|---|
| store_id | INTEGER | Primary key |
| store_name | VARCHAR | Store name |
| region | VARCHAR | Geographic region |
| city | VARCHAR | City |
| updated_at | TIMESTAMP | Last updated in source |
| processed_at | TIMESTAMP | When this record was staged |

---

## Dimension Layer

### `dim_customer`
SCD Type 2 customer dimension with history tracking.

| Column | Type | Description |
|---|---|---|
| customer_key | INTEGER | Surrogate primary key |
| customer_id | INTEGER | Natural/business key |
| customer_name | VARCHAR | Full name |
| email | VARCHAR | Email address |
| city | VARCHAR | City |
| country | VARCHAR | Country |
| effective_from | TIMESTAMP | When this version became active |
| effective_to | TIMESTAMP | When this version expired (NULL = current) |
| is_current | BOOLEAN (0/1) | 1 if this is the active record |

**Row count:** ~4 | **Pattern:** SCD Type 2

---

### `dim_date`
Date dimension for time-series analysis.

| Column | Type | Description |
|---|---|---|
| date_key | INTEGER | Surrogate key (YYYYMMDD format) |
| full_date | DATE | Full date value |
| year | INTEGER | Calendar year |
| month | INTEGER | Month number (1–12) |
| day | INTEGER | Day of month |
| month_name | VARCHAR | Month name (e.g. June) |

**Row count:** ~3

---

### `dim_product`
Product dimension.

| Column | Type | Description |
|---|---|---|
| product_key | INTEGER | Surrogate primary key |
| product_id | INTEGER | Natural/business key |
| product_name | VARCHAR | Product name |
| category | VARCHAR | Product category |
| price | DECIMAL | Unit price |

**Row count:** ~4

---

### `dim_store`
Store dimension.

| Column | Type | Description |
|---|---|---|
| store_key | INTEGER | Surrogate primary key |
| store_id | INTEGER | Natural/business key |
| store_name | VARCHAR | Store name |
| region | VARCHAR | Geographic region |
| city | VARCHAR | City |

**Row count:** ~3

---

## Fact Layer

### `fct_sales`
Central fact table for sales transactions. Joins to all four dimensions.

| Column | Type | Description |
|---|---|---|
| sales_key | INTEGER | Surrogate primary key |
| order_id | INTEGER | Source order identifier |
| customer_key | INTEGER | FK → dim_customer |
| product_key | INTEGER | FK → dim_product |
| store_key | INTEGER | FK → dim_store |
| date_key | INTEGER | FK → dim_date |
| quantity | INTEGER | Units sold |
| amount | DECIMAL | Revenue amount |
| order_status | VARCHAR | Order status |

**Row count:** ~5 | **Grain:** One row per order line

---

## Data Quality Layer

### `pipeline_audit`
Execution log for each pipeline run, tracking record counts and status.

| Column | Type | Description |
|---|---|---|
| audit_id | INTEGER | Primary key |
| pipeline_name | VARCHAR | Name of the pipeline |
| layer_name | VARCHAR | Layer being processed (e.g. Staging, Dimension) |
| input_count | INTEGER | Records entering the layer |
| output_count | INTEGER | Records successfully processed |
| rejected_count | INTEGER | Records that failed validation |
| status | VARCHAR | Run status (e.g. Success, Failed) |
| execution_time | TIMESTAMP | When the pipeline ran |
| comments | VARCHAR | Free-text notes |

**Row count:** ~4

---

### `rejected_orders`
Quarantine table for orders that failed validation rules.

| Column | Type | Description |
|---|---|---|
| order_id | INTEGER | Original order identifier |
| customer_id | INTEGER | Customer who placed the order |
| product_id | INTEGER | Product ordered |
| store_id | INTEGER | Store where order was placed |
| order_date | DATE/TIMESTAMP | Date of order |
| quantity | DECIMAL | Units ordered |
| amount | DECIMAL | Order amount |
| order_status | VARCHAR | Order status at rejection |
| rejection_reason | VARCHAR | Reason for rejection (e.g. "Invalid order date") |
| rejected_at | TIMESTAMP | When the record was rejected |

**Row count:** ~3

---

## Entity Relationship Summary

```
src_customers ──► stg_customers ──► dim_customer ──┐
src_orders    ──► stg_orders    ──────────────────► fct_sales
src_products  ──► stg_products  ──► dim_product  ──┤
src_stores    ──► stg_stores    ──► dim_store    ──┘
                                    dim_date     ──┘

stg_orders (rejected) ──► rejected_orders
pipeline runs         ──► pipeline_audit
```
