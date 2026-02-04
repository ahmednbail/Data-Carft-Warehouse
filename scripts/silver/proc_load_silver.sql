-- Active: 1770210241881@@localhost@1433@DataWarehouse
EXEC bronze.load_bronze;
EXEC silver.load_silver;


--EXEC silver.load_silver;

CREATE OR ALTER PROCEDURE silver.load_silver  AS
  BEGIN
        DECLARE @start_time DATETIME, @end_time DATETIME ,@batch_start_time DATETIME , @batch_end_time DATETIME;
        BEGIN  TRY
            SET @batch_start_time= GETDATE();
            PRINT'================================================='
            PRINT'Loading silver layer';
            PRINT'================================================='

            PRINT'-------------------------------------------------'
            PRINT'Loading CRM Tables'
            PRINT'-------------------------------------------------'


            SET @start_time= GETDATE();
            PRINT 'Truncating Table: silver.crm_cust_info';
            TRUNCATE TABLE silver.crm_cust_info;
		    PRINT '>> Inserting Data Into: silver.crm_cust_info';
		    INSERT INTO silver.crm_cust_info (
			    cst_id, 
			    cst_key, 
			    cst_firstname, 
			    cst_lastname, 
			    cst_marital_status, 
			    cst_gndr,
			    cst_create_date
		    )
		    SELECT
			    cst_id,
			    cst_key,
			    TRIM(cst_firstname) AS cst_firstname,
			    TRIM(cst_lastname) AS cst_lastname,
			    CASE 
				    WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
				    WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
				    ELSE 'Unknown'
			    END AS cst_marital_status, -- Normalize marital status values to readable format
			    CASE 
				    WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
				    WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
				    ELSE 'Unknown'
			    END AS cst_gndr, -- Normalize gender values to readable format
			    cst_create_date
		    FROM (
			    SELECT
				    *,
				    ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
			    FROM bronze.crm_cust_info
			    WHERE cst_id IS NOT NULL
		    ) t
		    WHERE flag_last = 1;
            SET @end_time= GETDATE();
            PRINT 'Loading Duration' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) + ' seconds';
            PRINT'-------------------------------------------------'


            
            
            SET @start_time= GETDATE();
            PRINT 'Truncating Table:silver.crm_prd_info';
            TRUNCATE TABLE silver.crm_prd_info;
            PRINT '>> Inserting Data into:silver.crm_prd_info ';
            INSERT INTO silver.crm_prd_info (
                        prd_id,
                        cat_id,
                        prd_key,
                        prd_nm,
                        prd_cost,
                        prd_line,
                        prd_start_dt,
                        prd_end_dt
            )
            SELECT 
            prd_id,
            REPLACE(SUBSTRING(prd_key,1,5),'-','_') AS cat_id,  -- DERIVED COLUMN  --extract category id 
            SUBSTRING( prd_key, 7 , LEN(prd_key) ) AS prd_key, --extract product key
            prd_nm,
            ISNULL(prd_cost,0) AS prd_cost,  -- HANDLING NULL VALUES
            CASE UPPER(TRIM(prd_line))
                WHEN  'M' THEN 'Mountain'
                WHEN  'R' THEN 'Road'
                WHEN  'S' THEN 'Other Sales'
                WHEN  'T' THEN 'Touring'
                ELSE 'Unknown'  -- HANDLING INVALID VALUES
            END AS prd_line,
            CAST(prd_start_dt AS DATE) AS prd_start_dt,
            CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1 AS DATE) AS prd_end_dt 
            FROM bronze.crm_prd_info
            SET @end_time= GETDATE();
            PRINT 'Loading Duration' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) + ' seconds';
            PRINT'-------------------------------------------------'


            SET @start_time= GETDATE();
            PRINT 'Truncating Table: silver.crm_sales_details';
            TRUNCATE TABLE silver.crm_sales_details;
            PRINT '>> Inserting Data Into: silver.crm_sales_details';
			INSERT INTO silver.crm_sales_details (
				sls_ord_num,
				sls_prd_key,
				sls_cust_id,
				sls_order_dt,
				sls_ship_dt,
				sls_due_dt,
				sls_sales,
				sls_quantity,
				sls_price
			)
			SELECT 
				sls_ord_num,
				sls_prd_key,
				sls_cust_id,
				CASE 
					WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
					ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
				END AS sls_order_dt,
				CASE 
					WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
					ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
				END AS sls_ship_dt,
				CASE 
					WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
					ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
				END AS sls_due_dt,
				CASE 
					WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price) 
						THEN sls_quantity * ABS(sls_price)
					ELSE sls_sales
				END AS sls_sales, -- Recalculate sales if original value is missing or incorrect
				sls_quantity,
				CASE 
					WHEN sls_price IS NULL OR sls_price <= 0 
						THEN sls_sales / NULLIF(sls_quantity, 0)
					ELSE sls_price  -- Derive price if original value is invalid
				END AS sls_price
			FROM bronze.crm_sales_details;
            SET @end_time= GETDATE();
            PRINT 'Loading Duration' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) + ' seconds';
            PRINT'-------------------------------------------------'


            PRINT'-------------------------------------------------'
            PRINT'Loading ERP Tables'
            PRINT'-------------------------------------------------'


            SET @start_time= GETDATE();
            PRINT 'Truncating Table: silver.erp_cust_az12';
            TRUNCATE TABLE silver.erp_cust_az12;
            PRINT'Inserting Data into:silver.erp_cust_az12';
            WITH Cleaned_erp_cust_az12 AS (
                SELECT
                    CASE 
                        WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
                        ELSE cid 
                    END AS cid,
                    CASE 
                        WHEN bdate > GETDATE() THEN NULL
                        ELSE bdate
                    END AS bdate,
                    UPPER(
                        REPLACE(
                        REPLACE(
                        REPLACE(
                        REPLACE(TRIM(gen), CHAR(9),  ''),   -- tab
                                    CHAR(10), ''),   -- LF
                                    CHAR(13), ''),   -- CR
                                    CHAR(160), '')   -- non-breaking space
                    ) AS gen_clean
                FROM bronze.erp_cust_az12
            )
            INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
            SELECT
                cid,
                bdate,
                CASE
                    WHEN gen_clean IN ('F', 'FEMALE') THEN 'Female'
                    WHEN gen_clean IN ('M', 'MALE')   THEN 'Male'
                    ELSE 'Unknown'
                END AS gen
            FROM Cleaned_erp_cust_az12;
            SET @end_time= GETDATE();
            PRINT 'Loading Duration' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) + ' seconds';
            PRINT'-------------------------------------------------'    


            SET @start_time= GETDATE();
            PRINT 'Truncating Table: silver.erp_loc_a101';
            TRUNCATE TABLE silver.erp_loc_a101;
            PRINT '>> Inserting Data Into: silver.erp_loc_a101';
            WITH Cleaned_erp_loc_a101 AS (
                SELECT 
                    REPLACE (cid,'-','') AS cid, 
                    CNTRY AS old_cntry,
                    UPPER(
                        REPLACE(
                        REPLACE(
                        REPLACE(
                        REPLACE(TRIM(cntry), CHAR(9),  ''),   -- tab
                                    CHAR(10), ''),   -- LF
                                    CHAR(13), ''),   -- CR
                                    CHAR(160), '')   -- non-breaking space
                    ) AS cntry_clean
                FROM bronze.erp_loc_a101
            )
            INSERT INTO silver.erp_loc_a101 (cid, cntry)
            SELECT
                REPLACE (cid,'-','') AS cid, 
                CASE 
                    WHEN TRIM(cntry_clean) IN ('DE','Germany') THEN 'Germany'
                    WHEN TRIM(cntry_clean) IN ('US', 'USA','UNITED STATES') THEN 'United States'
                    WHEN TRIM(cntry_clean) IN ('UK', 'GB', 'UNITED KINGDOM') THEN 'United Kingdom'
                    WHEN TRIM(cntry_clean) IN ('FR', 'FRA', 'FRANCE') THEN 'France'
                    WHEN TRIM(cntry_clean) = 'Canada ' THEN 'Canada'
                    WHEN TRIM(cntry_clean) = 'Australia ' THEN 'Australia '
                    WHEN TRIM(cntry_clean) = '' OR old_cntry IS NULL THEN 'Unknown'
                    ELSE UPPER(TRIM(cntry_clean))
                END AS cntry
            FROM Cleaned_erp_loc_a101;
            SET @end_time =GETDATE();
            PRINT 'Loading Duration' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) + ' seconds';
            PRINT'-------------------------------------------------'

            SET @start_time= GETDATE();
            PRINT 'Truncating Table: silver.erp_px_cat_g1v2';
            TRUNCATE TABLE silver.erp_px_cat_g1v2;
            PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
            INSERT INTO silver.erp_px_cat_g1v2 ( id,
                cat,
                subcat,
                maintenance)
            SELECT 
                id,
                cat,
                subcat,
                maintenance
            FROM bronze.erp_px_cat_g1v2
            SET @end_time= GETDATE();
            PRINT 'Loading Duration' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) + ' seconds';
            PRINT'-------------------------------------------------'
            
            SET @batch_end_time = GETDATE();
		    PRINT '=========================================='
		    PRINT 'Loading Silver Layer is Completed';
            PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		    PRINT '=========================================='



      	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER'
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH


  END;



