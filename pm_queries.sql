-- ============================================================
--   PM SESSION ASSIGNMENT — Advanced SQL
--   Topics: Subqueries, Window Functions, CTEs, EXPLAIN
-- ============================================================

-- ============================================================
-- SETUP: Extra Tables for PM Assignment
-- (departments & employees from AM session assumed to exist)
-- ============================================================

-- Orders table for revenue queries
CREATE TABLE orders (
    order_id    SERIAL PRIMARY KEY,
    customer_id INT,
    city        VARCHAR(50),
    category    VARCHAR(50),
    order_date  DATE,
    revenue     NUMERIC
);

-- Transactions table for Part C
CREATE TABLE transactions (
    user_id          INT,
    transaction_date DATE,
    amount           NUMERIC
);

-- Insert sample orders
INSERT INTO orders (customer_id, city, category, order_date, revenue) VALUES
(1,  'Mumbai',    'Electronics', '2024-01-05', 5000),
(2,  'Mumbai',    'Electronics', '2024-01-20', 8000),
(3,  'Delhi',     'Clothing',    '2024-01-10', 3000),
(4,  'Delhi',     'Electronics', '2024-02-14', 7000),
(5,  'Mumbai',    'Clothing',    '2024-02-18', 4000),
(6,  'Bangalore', 'Electronics', '2024-02-22', 9000),
(7,  'Mumbai',    'Electronics', '2024-03-01', 6000),
(8,  'Delhi',     'Clothing',    '2024-03-15', 2000),
(9,  'Bangalore', 'Electronics', '2024-03-20', 11000),
(10, 'Bangalore', 'Clothing',    '2024-03-25', 3500),
(1,  'Mumbai',    'Electronics', '2024-04-10', 7500),
(2,  'Mumbai',    'Clothing',    '2024-04-18', 2500),
(3,  'Delhi',     'Electronics', '2024-05-05', 8500),
(11, 'Mumbai',    'Electronics', '2024-01-12', 4500),
(12, 'Delhi',     'Clothing',    '2024-02-08', 3200),
(13, 'Bangalore', 'Electronics', '2024-03-30', 9500),
-- Intentionally skip some dates for Part B (sparse time series)
(14, 'Mumbai',    'Electronics', '2024-06-01', 6000),
(15, 'Delhi',     'Clothing',    '2024-06-15', 2800);

-- Insert sample transactions
INSERT INTO transactions (user_id, transaction_date, amount) VALUES
(1, '2024-01-15', 500),
(1, '2024-02-10', 300),
(1, '2024-03-20', 700),   -- user 1: 3 consecutive months ✓
(2, '2024-01-05', 200),
(2, '2024-03-22', 400),   -- user 2: gap in Feb, not consecutive
(3, '2024-02-14', 600),
(3, '2024-03-18', 450),
(3, '2024-04-25', 800),   -- user 3: 3 consecutive months ✓
(4, '2024-01-30', 150),
(4, '2024-02-28', 250);   -- user 4: only 2 months


-- ============================================================
-- PART A — Concept Application (40%)
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- A1: Running Total — Cumulative revenue per category by date
-- ─────────────────────────────────────────────────────────────
-- Simple idea: SUM() OVER (PARTITION BY category ORDER BY date)
-- This keeps adding up revenue for each category row by row.

SELECT
    category,
    order_date,
    revenue,
    SUM(revenue) OVER (
        PARTITION BY category      -- restart the total for each category
        ORDER BY order_date        -- add up in date order
    ) AS cumulative_revenue
FROM orders
ORDER BY category, order_date;


-- ─────────────────────────────────────────────────────────────
-- A2: Top-3 Customers by Revenue per City using ROW_NUMBER()
-- ─────────────────────────────────────────────────────────────
-- Step 1: Total revenue per customer per city
-- Step 2: Rank them within each city
-- Step 3: Keep only top 3

WITH customer_revenue AS (
    -- Step 1: Sum up each customer's total revenue per city
    SELECT
        city,
        customer_id,
        SUM(revenue) AS total_revenue
    FROM orders
    GROUP BY city, customer_id
),
ranked AS (
    -- Step 2: Rank customers within each city (highest revenue = rank 1)
    SELECT
        city,
        customer_id,
        total_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY city          -- rank within each city separately
            ORDER BY total_revenue DESC -- highest revenue gets rank 1
        ) AS rn
    FROM customer_revenue
)
-- Step 3: Keep only top 3
SELECT city, customer_id, total_revenue, rn
FROM ranked
WHERE rn <= 3
ORDER BY city, rn;


-- ─────────────────────────────────────────────────────────────
-- A3: Month-over-Month (MoM) Revenue Growth % using LAG
--     Flag months where growth < -5%
-- ─────────────────────────────────────────────────────────────
-- LAG() looks at the PREVIOUS row's value.
-- Growth % = (this_month - last_month) / last_month * 100

WITH monthly_revenue AS (
    -- Step 1: Total revenue per month
    SELECT
        TO_CHAR(order_date, 'YYYY-MM') AS month,   -- format as "2024-01"
        SUM(revenue)                   AS total_rev
    FROM orders
    GROUP BY TO_CHAR(order_date, 'YYYY-MM')
),
with_growth AS (
    -- Step 2: Use LAG to get previous month's revenue
    SELECT
        month,
        total_rev,
        LAG(total_rev) OVER (ORDER BY month) AS prev_month_rev,
        ROUND(
            (total_rev - LAG(total_rev) OVER (ORDER BY month))
            / LAG(total_rev) OVER (ORDER BY month) * 100,
            2
        ) AS growth_pct
    FROM monthly_revenue
)
-- Step 3: Show results and flag bad months
SELECT
    month,
    total_rev,
    prev_month_rev,
    growth_pct,
    CASE
        WHEN growth_pct < -5 THEN 'FLAG: Drop > 5%'
        ELSE 'OK'
    END AS status
FROM with_growth
ORDER BY month;


-- ─────────────────────────────────────────────────────────────
-- A4: Multi-CTE — Departments where ALL employees earn
--     above the company average salary
-- ─────────────────────────────────────────────────────────────
-- Step 1: Find company-wide average salary (single number)
-- Step 2: Find departments that have ANY employee below that average
-- Step 3: Exclude those departments → remaining ones ALL earn above avg

WITH company_avg AS (
    -- Step 1: Company-wide average (just one number)
    SELECT AVG(salary) AS avg_sal
    FROM employees
),
below_avg_depts AS (
    -- Step 2: Departments that have at least ONE employee below average
    SELECT DISTINCT dept_id
    FROM employees, company_avg
    WHERE salary <= company_avg.avg_sal
)
-- Step 3: Departments NOT in the above list = all employees above average
SELECT d.dept_name, d.dept_id
FROM departments d
WHERE d.dept_id NOT IN (SELECT dept_id FROM below_avg_depts);


-- ─────────────────────────────────────────────────────────────
-- A5: 2nd Highest Salary per Department
--     WITHOUT window functions — using correlated subquery
-- ─────────────────────────────────────────────────────────────
-- Logic: For each employee, count how many people in their dept
--        earn MORE than them. If exactly 1 person earns more → rank 2.

SELECT name, dept_id, salary
FROM employees e1
WHERE (
    -- Count how many employees in same dept earn strictly more
    SELECT COUNT(DISTINCT salary)
    FROM employees e2
    WHERE e2.dept_id = e1.dept_id
      AND e2.salary > e1.salary
) = 1;   -- exactly 1 person earns more = you are 2nd highest


-- ============================================================
-- PART B — Stretch Problem (30%)
-- Recursive CTE: Generate 1 to 100, then fill missing dates
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- B1: Generate number series 1 to 100 using Recursive CTE
-- ─────────────────────────────────────────────────────────────
-- How Recursive CTE works:
--   1. Start with the "anchor" (base case) — just the number 1
--   2. The "recursive" part keeps adding 1 until we reach 100
--   3. UNION ALL combines all the rows together

WITH RECURSIVE numbers AS (
    -- Anchor: start at 1
    SELECT 1 AS n

    UNION ALL

    -- Recursive: keep adding 1, stop when n = 100
    SELECT n + 1
    FROM numbers
    WHERE n < 100
)
SELECT n FROM numbers;
-- Result: rows 1, 2, 3, ... 100


-- ─────────────────────────────────────────────────────────────
-- B2: Fill Missing Dates in Sparse Time Series
--     (dates with no orders appear with revenue = 0)
-- ─────────────────────────────────────────────────────────────
-- Step 1: Generate every date from min to max order_date
-- Step 2: LEFT JOIN with actual orders
-- Step 3: Where no order exists → revenue shows as 0

WITH RECURSIVE date_series AS (
    -- Anchor: start from the earliest order date
    SELECT MIN(order_date) AS dt
    FROM orders

    UNION ALL

    -- Recursive: add 1 day at a time
    SELECT dt + INTERVAL '1 day'
    FROM date_series
    WHERE dt < (SELECT MAX(order_date) FROM orders)
),
daily_revenue AS (
    -- Actual daily revenue (only dates that have orders)
    SELECT order_date, SUM(revenue) AS total_rev
    FROM orders
    GROUP BY order_date
)
-- LEFT JOIN: every date from series, 0 if no orders that day
SELECT
    ds.dt                              AS order_date,
    COALESCE(dr.total_rev, 0)          AS revenue   -- COALESCE replaces NULL with 0
FROM date_series ds
LEFT JOIN daily_revenue dr ON ds.dt = dr.order_date
ORDER BY ds.dt;


-- ============================================================
-- PART C — Interview Ready (20%)
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- C2 (Coding): Users who purchased in 3+ consecutive months
-- ─────────────────────────────────────────────────────────────
-- Strategy:
--   1. Get distinct (user, month) pairs — ignore multiple orders/month
--   2. Assign a ROW_NUMBER to each user's months in order
--   3. Subtract row number from month number → same value = consecutive
--   4. Group by user + that value, count → if count >= 3, flag them

WITH user_months AS (
    -- Step 1: One row per user per month (remove duplicates)
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', transaction_date) AS txn_month
    FROM transactions
),
numbered AS (
    -- Step 2: Number each user's months in order
    SELECT
        user_id,
        txn_month,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY txn_month
        ) AS rn
    FROM user_months
),
grouped AS (
    -- Step 3: Subtract row number from month → consecutive months get same value
    -- Example: Jan=1, Feb=2, Mar=3 with rn=1,2,3 → (1-1)=(2-2)=(3-3)=0 (same group)
    SELECT
        user_id,
        txn_month,
        (txn_month - (rn || ' months')::INTERVAL) AS grp
    FROM numbered
)
-- Step 4: Count per group — if 3 or more, they had 3 consecutive months
SELECT DISTINCT user_id
FROM grouped
GROUP BY user_id, grp
HAVING COUNT(*) >= 3;


-- ─────────────────────────────────────────────────────────────
-- C3 (Optimise): Rewrite correlated subquery as window function
-- ─────────────────────────────────────────────────────────────

-- ORIGINAL (slow — correlated subquery, runs once per row = O(n²)):
-- SELECT name, salary FROM employees e1
-- WHERE salary > (SELECT AVG(salary) FROM employees e2
--                 WHERE e2.department = e1.department);

-- REWRITTEN using window function (fast — one pass over data):
SELECT name, salary
FROM (
    SELECT
        name,
        salary,
        AVG(salary) OVER (PARTITION BY dept_id) AS dept_avg
    FROM employees
) subq
WHERE salary > dept_avg;

-- WHY IS THIS FASTER?
-- Correlated subquery: runs the AVG subquery for EVERY single row → O(n²)
-- Window function:     PostgreSQL calculates all dept averages in ONE pass → O(n)
-- On a table with 1 million rows, the window version can be 100x+ faster.


-- ============================================================
-- PART D — AI-Augmented Task (10%)
-- ============================================================
-- AI Prompt Used:
-- "Give me 3 SQL interview questions at senior data engineer level
--  involving window functions or CTEs. Include the expected answer
--  and a common mistake candidates make."
-- ─────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────
-- D1: Find the first purchase date for each user,
--     and the revenue difference from their average order.
-- ─────────────────────────────────────────────────────────────

-- Expected Answer:
SELECT
    user_id,
    transaction_date,
    amount,
    MIN(transaction_date) OVER (PARTITION BY user_id) AS first_purchase,
    ROUND(amount - AVG(amount) OVER (PARTITION BY user_id), 2) AS diff_from_avg
FROM transactions
ORDER BY user_id, transaction_date;

-- Common Mistake: Using GROUP BY instead of window functions,
-- which collapses rows and loses individual transaction details.
-- GROUP BY cannot show both per-row AND per-user aggregated values
-- at the same time — window functions solve exactly this.


-- ─────────────────────────────────────────────────────────────
-- D2: Using a CTE, find customers whose total spending
--     is above the average total spending across all customers.
-- ─────────────────────────────────────────────────────────────

-- Expected Answer:
WITH customer_totals AS (
    SELECT user_id, SUM(amount) AS total_spent
    FROM transactions
    GROUP BY user_id
),
avg_spending AS (
    SELECT AVG(total_spent) AS avg_total
    FROM customer_totals
)
SELECT ct.user_id, ct.total_spent, at.avg_total
FROM customer_totals ct, avg_spending at
WHERE ct.total_spent > at.avg_total;

-- Common Mistake: Writing a nested subquery for the average inside
-- the WHERE clause, which is harder to read and harder to debug.
-- CTEs make each step clear and testable independently.


-- ─────────────────────────────────────────────────────────────
-- D3: Detect "gaps" — users who skipped a month between purchases.
-- ─────────────────────────────────────────────────────────────

-- Expected Answer:
WITH user_months AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', transaction_date) AS txn_month
    FROM transactions
),
with_next AS (
    SELECT
        user_id,
        txn_month,
        LEAD(txn_month) OVER (
            PARTITION BY user_id ORDER BY txn_month
        ) AS next_month
    FROM user_months
)
SELECT user_id, txn_month AS gap_start, next_month AS gap_end
FROM with_next
WHERE next_month IS NOT NULL
  -- If difference between consecutive months > 1 month, there's a gap
  AND next_month > txn_month + INTERVAL '1 month';

-- Common Mistake: Candidates try to do this with a self-join
-- (comparing every row to every other row for the same user).
-- This is O(n²) and very slow. LEAD() does this in a single O(n) pass.


-- ============================================================
-- EXPLAIN BASICS (Referenced in Rubric)
-- ============================================================

-- Check how PostgreSQL executes the window function query:
EXPLAIN ANALYZE
SELECT name, salary
FROM (
    SELECT name, salary,
           AVG(salary) OVER (PARTITION BY dept_id) AS dept_avg
    FROM employees
) subq
WHERE salary > dept_avg;

-- Key things to look for in EXPLAIN output:
-- "WindowAgg"      → PostgreSQL is using a window function (good!)
-- "Seq Scan"       → Reading whole table (ok for small tables)
-- "Index Scan"     → Using an index (faster for large tables)
-- "Hash Join"      → Joining tables via hashing (efficient)
-- "cost=X..Y"      → Estimated cost; lower is better
