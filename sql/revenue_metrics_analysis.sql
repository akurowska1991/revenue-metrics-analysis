WITH base AS (
    SELECT 
        g.user_id,
        g.revenue_amount_usd,
        DATE_TRUNC('month', g.payment_date)::date AS payment_month
    FROM project.games_payments g
),

monthly_user_revenue AS (
    SELECT
        user_id,
        payment_month,
        SUM(revenue_amount_usd) AS revenue
    FROM base
    GROUP BY user_id, payment_month
),

first_payment AS (
    SELECT
        user_id,
        MIN(payment_month) AS first_payment_month
    FROM monthly_user_revenue
    GROUP BY user_id
),

user_metrics AS (
    SELECT
        m.user_id,
        m.payment_month,
        m.revenue,
        fp.first_payment_month,

        -- previous month in data
        LAG(m.payment_month) OVER (
            PARTITION BY m.user_id
            ORDER BY m.payment_month
        ) AS previous_paid_month,

        -- expected previous calendar month
        (m.payment_month - INTERVAL '1 month')::date AS previous_calendar_month,

        -- previous revenue
        LAG(m.revenue) OVER (
            PARTITION BY m.user_id
            ORDER BY m.payment_month
        ) AS previous_revenue,

        -- NEW USERS
        CASE 
            WHEN m.payment_month = fp.first_payment_month THEN 1
            ELSE 0
        END AS new_paid_user,

        CASE 
            WHEN m.payment_month = fp.first_payment_month THEN m.revenue
            ELSE 0
        END AS new_mrr,

        -- CHURN USERS
        CASE
            WHEN LEAD(m.payment_month) OVER (
                PARTITION BY m.user_id
                ORDER BY m.payment_month
            ) IS NULL
             OR LEAD(m.payment_month) OVER (
                PARTITION BY m.user_id
                ORDER BY m.payment_month
            ) != (m.payment_month + INTERVAL '1 month')::date
            THEN 1
            ELSE 0
        END AS churned_user,

        CASE
            WHEN LEAD(m.payment_month) OVER (
                PARTITION BY m.user_id
                ORDER BY m.payment_month
            ) IS NULL
             OR LEAD(m.payment_month) OVER (
                PARTITION BY m.user_id
                ORDER BY m.payment_month
            ) != (m.payment_month + INTERVAL '1 month')::date
            THEN m.revenue
            ELSE 0
        END AS churned_revenue,

        -- EXPANSION (only consecutive months)
        CASE 
            WHEN LAG(m.payment_month) OVER (
                    PARTITION BY m.user_id
                    ORDER BY m.payment_month
                 ) = (m.payment_month - INTERVAL '1 month')::date
             AND m.revenue > LAG(m.revenue) OVER (
                    PARTITION BY m.user_id
                    ORDER BY m.payment_month
                 )
            THEN m.revenue - LAG(m.revenue) OVER (
                    PARTITION BY m.user_id
                    ORDER BY m.payment_month
                 )
            ELSE 0
        END AS expansion_revenue,

        -- CONTRACTION (only consecutive months)
        CASE 
            WHEN LAG(m.payment_month) OVER (
                    PARTITION BY m.user_id
                    ORDER BY m.payment_month
                 ) = (m.payment_month - INTERVAL '1 month')::date
             AND m.revenue < LAG(m.revenue) OVER (
                    PARTITION BY m.user_id
                    ORDER BY m.payment_month
                 )
            THEN LAG(m.revenue) OVER (
                    PARTITION BY m.user_id
                    ORDER BY m.payment_month
                 ) - m.revenue
            ELSE 0
        END AS contraction_revenue

    FROM monthly_user_revenue m
    LEFT JOIN first_payment fp
        ON m.user_id = fp.user_id
)

SELECT
    payment_month,

    SUM(revenue) AS mrr,
    COUNT(DISTINCT user_id) AS paid_users,

    SUM(new_paid_user) AS new_paid_users,
    SUM(new_mrr) AS new_mrr,

    SUM(churned_user) AS churned_users,
    SUM(churned_revenue) AS churned_revenue,

    SUM(expansion_revenue) AS expansion_mrr,
    SUM(contraction_revenue) AS contraction_mrr

FROM user_metrics
GROUP BY payment_month
ORDER BY payment_month;
