/*=============================================================================== 
 Advanced Sales Analysis Using Window Functions and Data Segmentation
===============================================================================
Purpose:
 --------
 This script performs several business analyses on the sales data stored in the
 data warehouse. The queries use window functions, aggregations, and data
 segmentation techniques to generate insights that can be used in dashboards,
 reports, and business decision-making.

 Analyses Included:
 ------------------

 1. Running Total Sales Analysis
    - Calculates monthly sales.
    - Computes cumulative (running) sales within each year.
    - Useful for identifying sales trends and growth over time.

 2. Year-over-Year (YoY) Product Analysis
    - Calculates yearly sales for each product.
    - Compares current sales with the product's average sales.
    - Compares current year sales with the previous year.
    - Classifies products as increasing, decreasing, or unchanged.

 3. Part-to-Whole Analysis
    - Calculates total sales for each product category.
    - Determines each category's contribution percentage to overall sales.

 4. Product Cost Segmentation
    - Groups products into cost ranges.
    - Shows the number of products within each cost segment.

 5. Customer Segmentation
    - Classifies customers based on:
        • Total spending
        • Customer lifespan
    - Segments customers into:
        • VIP
        • Regular
        • New

 Business Use Cases:
 -------------------
 - Sales trend reporting.
 - Product performance analysis.
 - Category contribution analysis.
 - Customer segmentation for marketing campaigns.
 - Building Power BI dashboards and executive reports.
===============================================================================
*/



/*============================================================================= 
 1. RUNNING TOTAL SALES ANALYSIS
=============================================================================*/
CREATE OR ALTER VIEW gold.running_total_sales AS
SELECT 
	order_month,
	total_sales,
	-- Calculate cumulative sales within each year
	SUM(total_sales) OVER(
		PARTITION BY YEAR(order_month)
		ORDER BY order_month
	) running_total_sales
FROM (
	SELECT 
		-- Group sales by month
		DATETRUNC(month, order_date) order_month,
		-- Total sales for each month
		SUM(sales) total_sales
	FROM gold.fast_sales
	-- Exclude records with missing order dates
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(month, order_date)
) t;
GO

/*============================================================================= 
 2. YEAR OVER YEAR PRODUCT SALES ANALYSIS
=============================================================================*/
CREATE OR ALTER VIEW gold.yoy_product_sales AS
WITH cte_1 AS (
	SELECT 
		-- Extract year from order date
		YEAR(f.order_date) order_year,
		p.product_name product_name,
		-- Total sales for each product and year
		SUM(f.sales) current_sales
	FROM gold.fast_sales f
	LEFT JOIN gold.dim_product p
		ON f.product_key = p.product_key
	WHERE YEAR(f.order_date) IS NOT NULL
	GROUP BY
		YEAR(f.order_date),
		p.product_name
)
SELECT *,
	-- Average yearly sales for the product
	AVG(current_sales) OVER(
		PARTITION BY product_name
	) sales_avg,

	-- Difference between current sales and average sales
	current_sales - AVG(current_sales) OVER(PARTITION BY product_name) diff_avg,

	-- Classify current sales relative to average (FIXED: Added column alias)
	CASE
		WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) > 0 THEN 'above avg'
		WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) < 0 THEN 'lower avg'
		ELSE 'avg'
	END AS sales_class,

	-- Retrieve previous year's sales
	LAG(current_sales) OVER(
		PARTITION BY product_name
		ORDER BY order_year
	) pre_sales,

	-- Calculate change from previous year
	current_sales - LAG(current_sales) OVER(
		PARTITION BY product_name
		ORDER BY order_year
	) ch_pre_sales,

	-- Classify year-over-year change (FIXED: Added column alias)
	CASE
		WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) > 0 THEN 'increase'
		WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) < 0 THEN 'decrease'
		ELSE 'no change'
	END AS change_class
FROM cte_1; -- FIXED: Removed invalid ORDER BY clause
GO

/*============================================================================= 
 3. PART-TO-WHOLE ANALYSIS
=============================================================================*/
CREATE OR ALTER VIEW gold.category_sales_percentage AS
WITH cte_2 AS (
	SELECT 
		p.category,
		-- Total sales for each category
		SUM(f.sales) tot_sales
	FROM gold.fast_sales f
	LEFT JOIN gold.dim_product p
		ON f.product_key = p.product_key
	GROUP BY p.category
)
SELECT *,
	-- Grand total sales across all categories
	SUM(tot_sales) OVER() total_sales,
	-- Percentage contribution of each category
	CONCAT(
		ROUND((CAST(tot_sales AS FLOAT) / SUM(tot_sales) OVER()) * 100, 2),
		'%'
	) per
FROM cte_2; -- FIXED: Removed invalid ORDER BY clause
GO

/*============================================================================= 
 4. PRODUCT COST SEGMENTATION
=============================================================================*/
CREATE OR ALTER VIEW gold.product_cost_segmentation AS
WITH product_segmentation AS (
	SELECT 
		product_key,
		product_name,
		cost,
		-- Group products into cost ranges
		CASE 
			WHEN cost < 100 THEN 'below 100'
			WHEN cost BETWEEN 100 AND 500 THEN '100_500'
			WHEN cost BETWEEN 500 AND 1000 THEN '500_1000'
			ELSE 'above 1000'
		END cost_range
	FROM gold.dim_product
)
SELECT 
	cost_range,
	-- Number of products in each segment
	COUNT(cost_range) total_number
FROM product_segmentation
GROUP BY cost_range; -- FIXED: Removed invalid ORDER BY clause
GO

/*============================================================================= 
 5. CUSTOMER SEGMENTATION
=============================================================================*/
CREATE OR ALTER VIEW gold.customer_segmentation AS
WITH order_info AS (
	SELECT 
		c.customer_key customer,
		-- Total amount spent by the customer
		SUM(f.sales) total_sales,
		-- Customer's first purchase date
		MIN(f.order_date) first_order,
		-- Customer's most recent purchase date
		MAX(f.order_date) last_order
	FROM gold.dim_customer c
	LEFT JOIN gold.fast_sales f
		ON c.customer_key = f.customer_key
	GROUP BY c.customer_key
)
SELECT 
	customer_segmentation, -- FIXED: Spelling
	-- Number of customers in each segment
	COUNT(customer) total_number
FROM (
	SELECT 
		*,
		-- Number of months between first and last purchase
		DATEDIFF(month, first_order, last_order) total_spending_time,
		-- Customer classification logic
		CASE 
			WHEN DATEDIFF(month, first_order, last_order) >= 12 AND total_sales > 5000 THEN 'VIP'
			WHEN DATEDIFF(month, first_order, last_order) >= 12 AND total_sales <= 5000 THEN 'regular' -- FIXED: Spelling
			ELSE 'new'
		END AS customer_segmentation -- FIXED: Spelling & ensured clear alias assignment
	FROM order_info
) t
GROUP BY customer_segmentation; -- FIXED: Removed invalid ORDER BY clause
GO
