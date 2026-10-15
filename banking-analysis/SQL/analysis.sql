-- Retail Banking Transaction Analysis
-- Main question:
-- How do customer and account characteristics influence banking transaction behaviour and value?

-- ============================================================
-- 1. Who are the most active customers?
-- ============================================================
-- Measures:
-- * transaction volume
-- * total transaction value
-- * average transaction value
-- * number of accounts

SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    COUNT(DISTINCT a.account_id) AS number_of_accounts,
    COUNT(t.transaction_id) AS total_transactions,
    SUM(t.amount) AS total_value,
    AVG(t.amount) AS average_value
FROM customers c
JOIN accounts a
    ON c.customer_id = a.customer_id
JOIN transactions t
    ON a.account_id = t.account_id
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name
ORDER BY
    total_transactions DESC,
    total_value DESC,
    average_value DESC
LIMIT 100;


-- ============================================================
-- 2. Does customer risk band relate to transaction behaviour?
-- ============================================================
-- Compares each risk band with the overall customer benchmark.
-- Activity index:
--   1.00 = same activity as the overall average
--   >1.00 = more active than average
--   <1.00 = less active than average

WITH risk_band_activity AS (
    SELECT
        c.risk_band,
        COUNT(DISTINCT c.customer_id) AS total_customers,
        COUNT(t.transaction_id) AS total_transactions,
        SUM(t.amount) AS total_transaction_value,
        AVG(t.amount) AS average_transaction_value,
        COUNT(t.transaction_id) * 1.0
            / COUNT(DISTINCT c.customer_id) AS transactions_per_customer
    FROM customers c
    LEFT JOIN accounts a
        ON c.customer_id = a.customer_id
    LEFT JOIN transactions t
        ON a.account_id = t.account_id
    GROUP BY c.risk_band
),

overall_average AS (
    SELECT
        COUNT(DISTINCT c.customer_id) AS total_customers,
        COUNT(t.transaction_id) AS total_transactions,
        COUNT(t.transaction_id) * 1.0
            / COUNT(DISTINCT c.customer_id) AS overall_transactions_per_customer
    FROM customers c
    LEFT JOIN accounts a
        ON c.customer_id = a.customer_id
    LEFT JOIN transactions t
        ON a.account_id = t.account_id
)

SELECT
    r.risk_band,
    r.total_customers,
    r.total_transactions,
    r.total_transaction_value,
    r.average_transaction_value,
    r.transactions_per_customer,
    o.overall_transactions_per_customer,
    r.transactions_per_customer
        / o.overall_transactions_per_customer AS activity_index,
    (
        r.transactions_per_customer
        / o.overall_transactions_per_customer - 1
    ) * 100 AS percentage_difference,
    CASE
        WHEN (
            r.transactions_per_customer
            / o.overall_transactions_per_customer - 1
        ) * 100 < -25
            THEN 'Significantly below average'
        WHEN (
            r.transactions_per_customer
            / o.overall_transactions_per_customer - 1
        ) * 100 < 0
            THEN 'Below average'
        WHEN (
            r.transactions_per_customer
            / o.overall_transactions_per_customer - 1
        ) * 100 < 25
            THEN 'Above average'
        ELSE 'Significantly above average'
    END AS activity_category
FROM risk_band_activity r
CROSS JOIN overall_average o
ORDER BY activity_index DESC;


-- ============================================================
-- 3. Which account types are most active?
-- ============================================================
-- Measures:
-- * number of accounts
-- * transaction volume
-- * total transaction value
-- * average transaction value

SELECT
    a.account_type,
    COUNT(a.account_id) AS total_accounts,
    COUNT(t.transaction_id) AS total_transactions,
    SUM(t.amount) AS total_transaction_value,
    AVG(t.amount) AS average_transaction_value
FROM accounts a
LEFT JOIN transactions t
    ON t.account_id = a.account_id
GROUP BY a.account_type
ORDER BY total_transactions DESC;


-- ============================================================
-- 4. How does transaction behaviour change over time?
-- ============================================================
-- Monthly transaction volume, value, and debit/credit activity.

SELECT
    DATE_TRUNC('month', posted_at) AS date_month,
    COUNT(t.transaction_id) AS number_of_transactions,
    SUM(t.amount) AS total_value,
    COUNT(
        CASE
            WHEN direction = 'debit' THEN transaction_id
        END
    ) AS debit_transactions,
    COUNT(
        CASE
            WHEN direction = 'credit' THEN transaction_id
        END
    ) AS credit_transactions
FROM transactions t
GROUP BY date_month
ORDER BY date_month;


-- ============================================================
-- 5. Which transaction channels and types drive activity?
-- ============================================================

-- 5.1 Channel-level behaviour
SELECT
    t.channel,
    COUNT(t.transaction_id) AS transactions_per_channel,
    SUM(t.amount) AS total_transaction_value,
    AVG(t.amount) AS average_transaction_value,
    COUNT(
        CASE
            WHEN direction = 'debit' THEN transaction_id
        END
    ) AS debit_transactions,
    COUNT(
        CASE
            WHEN direction = 'credit' THEN transaction_id
        END
    ) AS credit_transactions
FROM transactions t
GROUP BY t.channel
ORDER BY transactions_per_channel DESC;


-- 5.2 Transaction-type behaviour
SELECT
    transaction_type,
    COUNT(t.transaction_id) AS total_transactions,
    SUM(t.amount) AS total_transaction_value,
    AVG(t.amount) AS average_transaction_value
FROM transactions t
GROUP BY transaction_type
ORDER BY total_transaction_value DESC;


-- ============================================================
-- 6. Which customers/accounts are unusually active or inactive?
-- ============================================================

-- 6.1 Which customers make substantially more transactions
--     than the typical customer?
--
-- Definition:
-- More than 2 population standard deviations above the
-- average customer's transaction count.

WITH customer_transaction_activity AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        COUNT(t.transaction_id) AS total_transactions
    FROM customers c
    JOIN accounts a
        ON c.customer_id = a.customer_id
    JOIN transactions t
        ON a.account_id = t.account_id
    GROUP BY
        c.customer_id,
        c.first_name,
        c.last_name
),

activity_stats AS (
    SELECT
        AVG(total_transactions) AS mean_transactions,
        STDDEV_POP(total_transactions) AS std_transactions
    FROM customer_transaction_activity
)

SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.total_transactions,
    CASE
        WHEN c.total_transactions >
             s.mean_transactions + 2 * s.std_transactions
            THEN 'Unusually high'
        ELSE 'Normal'
    END AS activity_status
FROM customer_transaction_activity c
CROSS JOIN activity_stats s
ORDER BY c.total_transactions DESC;


-- 6.2 Which individual accounts have unusually large
--     transaction values?
--
-- Definition:
-- More than 2 population standard deviations above the
-- average account's total transaction value.

WITH account_activity AS (
    SELECT
        a.account_id,
        a.customer_id,
        COUNT(t.transaction_id) AS total_transactions,
        SUM(t.amount) AS total_value,
        AVG(t.amount) AS average_value
    FROM accounts a
    JOIN transactions t
        ON a.account_id = t.account_id
    GROUP BY
        a.account_id,
        a.customer_id
),

account_activity_stats AS (
    SELECT
        AVG(total_value) AS mean_value,
        STDDEV_POP(total_value) AS std_value
    FROM account_activity
)

SELECT
    a.account_id,
    a.customer_id,
    a.total_transactions,
    a.total_value,
    a.average_value,
    CASE
        WHEN a.total_value >
             s.mean_value + 2 * s.std_value
            THEN 'Unusually high'
        ELSE 'Normal'
    END AS account_activity_status
FROM account_activity a
CROSS JOIN account_activity_stats s
ORDER BY a.total_value DESC;


-- ============================================================
-- 7. Can we reconstruct account balances?
-- ============================================================
-- The dataset does not provide opening balances.
-- Therefore reconstructed balance assumes a starting balance of £0
-- and represents cumulative credits minus debits.
--
-- This is a reconstructed/net transaction balance, not an actual
-- bank statement balance.

-- 7.1 What is each account's running balance?

WITH account_transactions AS (
    SELECT
        a.account_id,
        a.customer_id,
        t.transaction_id,
        t.posted_at,
        t.transaction_type,
        t.direction,
        t.amount,
        CASE
            WHEN t.direction = 'credit' THEN t.amount
            WHEN t.direction = 'debit' THEN -t.amount
        END AS signed_amount
    FROM accounts a
    JOIN transactions t
        ON a.account_id = t.account_id
)

SELECT
    account_id,
    customer_id,
    transaction_id,
    posted_at,
    transaction_type,
    direction,
    amount,
    signed_amount,
    SUM(signed_amount) OVER (
        PARTITION BY account_id
        ORDER BY posted_at, transaction_id
    ) AS running_balance
FROM account_transactions
ORDER BY account_id, posted_at, transaction_id;


-- 7.2 Which accounts have the highest/lowest reconstructed balances?

WITH account_transactions AS (
    SELECT
        a.account_id,
        a.customer_id,
        t.transaction_id,
        t.posted_at,
        t.transaction_type,
        t.direction,
        t.amount,
        CASE
            WHEN t.direction = 'credit' THEN t.amount
            WHEN t.direction = 'debit' THEN -t.amount
        END AS signed_amount
    FROM accounts a
    JOIN transactions t
        ON a.account_id = t.account_id
),

running_balance AS (
    SELECT
        account_id,
        customer_id,
        posted_at,
        transaction_id,
        SUM(signed_amount) OVER (
            PARTITION BY account_id
            ORDER BY posted_at, transaction_id
        ) AS reconstructed_balance,
        ROW_NUMBER() OVER (
            PARTITION BY account_id
            ORDER BY posted_at DESC, transaction_id DESC
        ) AS row_num
    FROM account_transactions
)

SELECT
    account_id,
    customer_id,
    reconstructed_balance
FROM running_balance
WHERE row_num = 1
ORDER BY reconstructed_balance DESC;


-- 7.3 Are accounts approaching or exceeding their overdraft limits?
--
-- Here, any negative reconstructed balance is treated as
-- approaching/using the overdraft facility.
-- An account below the negative overdraft limit is classified
-- as exceeding its limit.

WITH account_transactions AS (
    SELECT
        a.account_id,
        a.customer_id,
        t.transaction_id,
        t.posted_at,
        t.amount,
        t.direction,
        CASE
            WHEN t.direction = 'credit' THEN t.amount
            WHEN t.direction = 'debit' THEN -t.amount
        END AS signed_amount
    FROM accounts a
    JOIN transactions t
        ON a.account_id = t.account_id
),

running_balance AS (
    SELECT
        account_id,
        customer_id,
        posted_at,
        transaction_id,
        SUM(signed_amount) OVER (
            PARTITION BY account_id
            ORDER BY posted_at, transaction_id
        ) AS reconstructed_balance,
        ROW_NUMBER() OVER (
            PARTITION BY account_id
            ORDER BY posted_at DESC, transaction_id DESC
        ) AS row_num
    FROM account_transactions
),

account_balance AS (
    SELECT
        account_id,
        customer_id,
        reconstructed_balance
    FROM running_balance
    WHERE row_num = 1
)

SELECT
    a.account_id,
    a.customer_id,
    a.overdraft_limit,
    ab.reconstructed_balance,
    CASE
        WHEN ab.reconstructed_balance < a.overdraft_limit * -1
            THEN 'Exceeding overdraft limit'
        ELSE 'Approaching overdraft limit'
    END AS overdraft_status
FROM accounts a
JOIN account_balance ab
    ON a.account_id = ab.account_id
WHERE ab.reconstructed_balance < 0
ORDER BY ab.reconstructed_balance ASC;


-- ============================================================
-- Key analytical notes before visualisation
-- ============================================================
-- 1. Risk-band analysis compares transaction activity per customer
--    against the overall customer benchmark.
--
-- 2. Outlier analysis uses a 2-standard-deviation threshold.
--    These classifications describe unusual behaviour; they do
--    not imply causation.
--
-- 3. Reconstructed balances assume an opening balance of £0 because
--    no opening balance is provided in the dataset.
--
-- 4. The SQL analysis is intended to be paired with the Pandas
--    analysis and visualisations in the portfolio project.
