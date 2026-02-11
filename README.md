# DataCraft Warehouse (Data Warehouse Project)

This repository contains **source datasets (CSV)** and a **reference architecture diagram** for building a simple **Data Warehouse** using a **medallion approach (Bronze → Silver → Gold)**.

## What’s in this repo

```text
datasets/
  source_crm/
    cust_info.csv         # CRM customers (master data)
    prd_info.csv          # CRM products (master data + validity dates)
    sales_details.csv     # CRM sales order line facts
  source_erp/
    CUST_AZ12.csv         # ERP customer demographics (DOB, gender)
    LOC_A101.csv          # ERP customer geography (country)
    PX_CAT_G1V2.csv       # ERP product categories / subcategories
docs/
  Data-Architecture.drawio # Medallion DW architecture diagram
```

## Data sources

- **CRM (Customer & Sales)**: customers, products, sales order lines.
- **ERP (Enrichment / Reference)**: customer demographics, customer country, product category mapping.

## Dataset dictionary

### `datasets/source_crm/cust_info.csv` (customers)

- **Primary fields**
  - `cst_id`: numeric customer id (CRM internal)
  - `cst_key`: customer business key (example: `AW00011000`)
  - `cst_firstname`, `cst_lastname`
  - `cst_marital_status`
  - `cst_gndr`
  - `cst_create_date` (ISO date, e.g. `2025-10-06`)
- **Notes**
  - Names may contain extra whitespace; plan to trim in Silver.

### `datasets/source_crm/prd_info.csv` (products)

- **Primary fields**
  - `prd_id`: numeric product id (CRM internal)
  - `prd_key`: product business key / SKU-like code (example: `AC-HE-HL-U509-R`)
  - `prd_nm`: product name
  - `prd_cost`: product cost (nullable in data)
  - `prd_line`: product line indicator
  - `prd_start_dt`, `prd_end_dt`: validity window (ISO dates; end date nullable)

### `datasets/source_crm/sales_details.csv` (sales facts)

- **Primary fields**
  - `sls_ord_num`: sales order number (example: `SO43697`)
  - `sls_prd_key`: product key used on sales lines (example: `BK-R93R-62`)
  - `sls_cust_id`: customer id as stored on sales lines (numeric)
  - `sls_order_dt`, `sls_ship_dt`, `sls_due_dt`: dates encoded as `yyyymmdd` (example: `20101229`)
  - `sls_sales`: sales amount
  - `sls_quantity`: quantity
  - `sls_price`: unit price

### `datasets/source_erp/CUST_AZ12.csv` (customer demographics)

- **Primary fields**
  - `CID`: customer identifier (example: `NASAW00011000`)
  - `BDATE`: birth date (ISO date, e.g. `1971-10-06`)
  - `GEN`: gender (example: `Male`, `Female`)
- **Notes**
  - `CID` includes a `NASA` prefix relative to the CRM `cst_key` (see relationships below).

### `datasets/source_erp/LOC_A101.csv` (customer geography)

- **Primary fields**
  - `CID`: customer identifier (example: `AW-00011000`)
  - `CNTRY`: country (example: `Australia`, `US`, `Canada`)
- **Notes**
  - `CID` uses hyphens; CRM `cst_key` does not (see relationships below).

### `datasets/source_erp/PX_CAT_G1V2.csv` (product categories)

- **Primary fields**
  - `ID`: category id (example: `AC_HE`)
  - `CAT`: category (example: `Accessories`)
  - `SUBCAT`: subcategory (example: `Helmets`)
  - `MAINTENANCE`: flag (example: `Yes`/`No`)

## Business keys & recommended joins (Silver/Gold)

This data intentionally comes from **multiple source systems**, so some keys need **standardization** in the Silver layer before reliable joins.

### Customer keys (CRM ↔ ERP)

- **CRM customer business key**: `cust_info.cst_key` (e.g. `AW00011000`)
- **ERP demographics key**: `CUST_AZ12.CID` (e.g. `NASAW00011000`)
  - Recommended standardization: `erp_demo_customer_key = replace(CID, 'NASA', '')`
- **ERP location key**: `LOC_A101.CID` (e.g. `AW-00011000`)
  - Recommended standardization: `erp_loc_customer_key = replace(CID, '-', '')`

After standardization, you can join:

- `cust_info.cst_key` ↔ `replace(CUST_AZ12.CID, 'NASA', '')`
- `cust_info.cst_key` ↔ `replace(LOC_A101.CID, '-', '')`

### Product keys (Sales ↔ Product ↔ Category)

- Sales lines reference `sales_details.sls_prd_key` (e.g. `BK-R93R-62`).
- Products use `prd_info.prd_key` (e.g. `AC-HE-HL-U509-R`).
- Categories use `PX_CAT_G1V2.ID` (e.g. `AC_HE`).

Recommended category mapping:

- `category_id = concat(split(prd_key, '-')[0], '_', split(prd_key, '-')[1])`
  - Example: `AC-HE-...` → `AC_HE` → join to `PX_CAT_G1V2.ID`

## Target warehouse model (Gold suggestion)

Typical star schema built from these sources:

- **Fact**
  - `fact_sales` (from `sales_details.csv`)
- **Dimensions**
  - `dim_customer` (CRM customer + ERP demographics + ERP country)
  - `dim_product` (CRM product + ERP category/subcategory)
  - `dim_date` (from order/ship/due dates)

## Architecture diagram

See `docs/Data-Architecture.drawio` for the reference flow:

- **Bronze**: raw CSVs as-is
- **Silver**: cleaned/standardized (trim strings, normalize keys, parse dates, type casting)
- **Gold**: curated marts (facts/dimensions for analytics)

## Notes & assumptions

- **Date formats differ** across sources:
  - CRM/ERP master data uses ISO dates (`YYYY-MM-DD`)
  - Sales uses numeric `yyyymmdd` values
- **Nulls exist** (e.g. `prd_cost` can be empty) and should be handled in Silver.

---

## Project Conclusion: Scripts Implementation Summary

This project implements a **medallion architecture data warehouse** (Bronze → Silver → Gold) using **SQL Server**, with comprehensive scripts for database setup, data ingestion, transformation, and analytics-ready presentation.

### **Overall Architecture**

The project follows a **three-layer medallion approach**:
- **Bronze**: Raw data ingestion from CSV sources
- **Silver**: Cleaned, standardized, and conformed data with business rules applied
- **Gold**: Analytics-ready star schema (dimensions + fact tables)

### **Scripts Overview**

#### **1. Initialization (`scripts/init_database.sql`)**
- Creates/drops the **DataWarehouse** database
- Establishes three schemas: `bronze`, `silver`, `gold`

#### **2. Bronze Layer (`scripts/bronze/`)**

**DDL (`ddl_bronze.sql`):**
- Creates 6 tables mirroring source structure:
  - **CRM**: `crm_cust_info`, `crm_prd_info`, `crm_sales_details`
  - **ERP**: `erp_cust_az12`, `erp_loc_a101`, `erp_px_cat_g1v2`

**Load Procedure (`proc_load_bronze.sql`):**
- Stored procedure `bronze.load_bronze` for automated data loading
- Uses **BULK INSERT** to load CSV files from CRM and ERP sources
- Implements **truncate-and-load** pattern for idempotent execution
- Includes comprehensive **logging** (per-table and batch-level timing)
- **Error handling** with TRY/CATCH blocks

**Key Features:**
- Raw data ingested as-is from source systems
- Repeatable, automated load process
- Performance tracking and error reporting

#### **3. Silver Layer (`scripts/silver/`)**

**DDL (`ddl_silver.sql`):**
- Creates 6 tables with enhanced structure:
  - Adds `dwh_create_date` timestamp to all tables
  - Proper data types (e.g., DATE for date fields)
  - Derived columns (e.g., `cat_id` extracted from `prd_key`)

**Load Procedure (`proc_load_silver.sql`):**
- Stored procedure `silver.load_silver` (can call `bronze.load_bronze` first)
- Implements comprehensive data quality transformations:

**CRM Data Transformations:**
- **Customers**: 
  - TRIM whitespace from names
  - Normalize marital status (S/M → Single/Married)
  - Normalize gender (F/M → Female/Male)
  - **Deduplication** by `cst_id` (keeps latest record by `cst_create_date`)
- **Products**:
  - Extract `cat_id` from `prd_key` (derived column)
  - Handle NULL costs (default to 0)
  - Normalize product line codes (M/R/S/T → Mountain/Road/Other Sales/Touring)
  - Type casting and validity date logic
- **Sales**:
  - Convert `yyyymmdd` integer dates to DATE format
  - Handle invalid/zero dates gracefully
  - **Recalculate** `sls_sales` and `sls_price` when missing or inconsistent

**ERP Data Transformations:**
- **Demographics**:
  - Remove "NASA" prefix from customer IDs for key alignment
  - Clean gender values (trim, remove control characters)
  - Normalize to Female/Male/Unknown
  - Validate birth dates (reject future dates)
- **Location**:
  - Standardize customer IDs (remove hyphens)
  - **Country normalization** (DE→Germany, US/USA→United States, UK/GB→United Kingdom, etc.)
- **Product Categories**: Direct pass-through with audit timestamp

**Key Features:**
- Data cleaning and standardization
- Key alignment across CRM and ERP systems
- Business rule enforcement
- Comprehensive error handling and timing metrics

#### **4. Gold Layer (`scripts/gold/ddl_gold.sql`)**

Implements **star schema** using **views** (no base tables):

- **`gold.dim_customer`**:
  - Surrogate key (`customer_key`) for dimension table
  - Combines CRM customer data with ERP demographics and location
  - Joins on standardized keys: `cst_key` ↔ cleaned ERP `cid`
  - Intelligent gender resolution (prefer CRM, fallback to ERP)

- **`gold.dim_product`**:
  - Surrogate key (`product_key`) for dimension table
  - Enriches product data with category/subcategory from ERP
  - Joins on derived `cat_id` column
  - Filters to current products only (`prd_end_dt IS NULL`)

- **`gold.fact_sales`**:
  - Fact table with order-level granularity
  - Uses surrogate keys (`product_key`, `customer_key`) from dimensions
  - Includes order/ship/due dates, sales amount, quantity, and price
  - Ready for analytics and reporting

**Key Features:**
- Analytics-ready star schema
- Surrogate keys for optimal query performance
- Integrated data from multiple sources
- Current-state product filtering

#### **5. Testing & Quality Assurance (`test/quality_checks_silver.sql`)**

Comprehensive data quality checks on Silver layer:

- **Uniqueness & Null Checks**: Validates primary keys (no duplicates or nulls)
- **Data Formatting**: Checks for unwanted spaces in string fields
- **Standardization Validation**: Verifies normalized values (marital status, gender, product line, country)
- **Referential Integrity**: Validates date orders (start ≤ end, order ≤ ship ≤ due)
- **Business Rules**: Ensures sales = quantity × price consistency
- **Domain Validation**: Checks date ranges and non-negative values

**Key Features:**
- Automated quality validation
- Identifies data issues before Gold layer consumption
- Ensures data consistency and accuracy

### **Summary Table**

| Layer | Scripts | Key Accomplishments |
|-------|---------|-------------------|
| **Init** | `init_database.sql` | Database and schema setup |
| **Bronze** | `ddl_bronze.sql`, `proc_load_bronze.sql` | Raw data ingestion with logging and error handling |
| **Silver** | `ddl_silver.sql`, `proc_load_silver.sql` | Data cleaning, standardization, key alignment, business rules |
| **Gold** | `ddl_gold.sql` | Star schema implementation (dimensions + fact) |
| **Test** | `quality_checks_silver.sql` | Data quality validation and consistency checks |

### **Key Achievements**

✅ **Complete medallion architecture** implemented in SQL Server  
✅ **Automated ETL processes** with stored procedures  
✅ **Data quality transformations** (cleaning, standardization, deduplication)  
✅ **Cross-system key alignment** (CRM ↔ ERP integration)  
✅ **Analytics-ready star schema** with surrogate keys  
✅ **Comprehensive error handling** and performance logging  
✅ **Data quality validation** framework  

This implementation demonstrates a production-ready data warehouse solution following industry best practices for data integration, transformation, and presentation.