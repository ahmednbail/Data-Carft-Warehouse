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