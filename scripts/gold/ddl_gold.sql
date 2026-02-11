-- Active: 1770210241881@@localhost@1433@DataWarehouse

---dim cutomer 

CREATE VIEW gold.dim_customer AS
SELECT  
      ROW_NUMBER() OVER(ORDER BY cm.cst_id) AS customer_key,
      cm.cst_id AS customer_id,
      cm.cst_key AS customer_number,
      cm.cst_firstname AS first_name,
      cm.cst_lastname AS last_name,
      el.cntry AS country,
      cm.cst_marital_status AS marital_status,
      CASE WHEN cm.cst_gndr != 'Unknown' THEN  cm.cst_gndr 
           ELSE COALESCE(ec.gen, 'Unknown') 
      END AS gender ,
      ec.bdate AS birthdate,
      cm.cst_create_date AS create_date
 FROM silver.crm_cust_info cm 
 LEFT JOIN silver.erp_cust_az12 ec  
      ON cm.cst_key = ec.cid
 LEFT JOIN silver.erp_loc_a101 el 
      ON cm.cst_key = el.cid;




---dim product 
CREATE VIEW gold.dim_product AS 
SELECT 
      ROW_NUMBER() OVER(ORDER BY cp.prd_start_dt,cp.prd_id) AS product_key,
      cp.prd_id AS product_id,
      cp.prd_key AS product_number,
      cp.prd_nm AS product_name,
      cp.cat_id AS category_id,
      ep.cat AS category,
      ep.subcat AS subcategory,
      ep.maintenance,
      cp.prd_cost AS product_cost,
      cp.prd_line AS product_line,
      cp.prd_start_dt AS start_date
 FROM silver.crm_prd_info  cp 
 LEFT JOIN silver.erp_px_cat_g1v2 ep 
    ON cp.cat_id = ep.id
 WHERE cp.prd_end_dt IS NUll;




-- Fact_sales 
CREATE VIEW gold.fact_sales AS
SELECT 
       sd.sls_ord_num AS order_number,
       dp.product_key,
       dc.customer_key,
       sd.sls_order_dt AS order_date,
       sd.sls_ship_dt AS ship_date,
       sd.sls_due_dt AS due_date,
       sd.sls_sales AS sales_amount,
       sd.sls_quantity AS quantity,
       sd.sls_price AS price
 FROM silver.crm_sales_details AS sd
 LEFT JOIN gold.dim_customer dc 
 ON sd.sls_cust_id = dc.customer_id 
 LEFT JOIN gold.dim_product dp
 ON sd.sls_prd_key = dp.product_number;







SELECT * FROM gold.dim_product



SELECT * FROM gold.dim_customer





SELECT * FROM gold.fact_sales