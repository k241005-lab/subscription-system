-- ============================================================
--  STORED PROCEDURES — Subscription Management & Hidden Charges Tracker
-- ============================================================
USE subscription_tracker;

DELIMITER $$

-- ── SP 1 ──────────────────────────────────────────────────────
-- sp_monthly_expense_report
-- Returns: total spend, per-subscription breakdown for a given
--          user and month/year.
-- Usage: CALL sp_monthly_expense_report(1, 4, 2026);
-- ──────────────────────────────────────────────────────────────
CREATE PROCEDURE sp_monthly_expense_report(
    IN p_user_id  INT,
    IN p_month    INT,
    IN p_year     INT
)
BEGIN
    DECLARE v_total DECIMAL(10,2);

    -- Per-subscription detail
    SELECT
        s.subscription_id,
        COALESCE(s.custom_name, p.service_name)  AS service_name,
        p.plan_name,
        c.name                                    AS category,
        c.icon                                    AS category_icon,
        c.color_hex,
        SUM(t.amount)                             AS amount_paid,
        COUNT(t.transaction_id)                   AS tx_count,
        s.currency
    FROM Transactions  t
    JOIN Subscriptions s ON s.subscription_id = t.subscription_id
    JOIN Plans         p ON p.plan_id         = s.plan_id
    JOIN Categories    c ON c.category_id     = p.category_id
    WHERE t.user_id        = p_user_id
      AND MONTH(t.transaction_date) = p_month
      AND YEAR(t.transaction_date)  = p_year
      AND t.status IN ('completed')
    GROUP BY s.subscription_id, service_name, p.plan_name, c.name, c.icon, c.color_hex, s.currency
    ORDER BY amount_paid DESC;

    -- Grand total
    SELECT SUM(amount) AS total_spent
      FROM Transactions
     WHERE user_id = p_user_id
       AND MONTH(transaction_date) = p_month
       AND YEAR(transaction_date)  = p_year
       AND status = 'completed';
END$$


-- ── SP 2 ──────────────────────────────────────────────────────
-- sp_generate_renewal_alerts
-- Scans ALL active subscriptions due within `p_days_ahead` days
-- and inserts renewal alerts if not already generated today.
-- Run daily via cron / scheduled event.
-- Usage: CALL sp_generate_renewal_alerts(7);
-- ──────────────────────────────────────────────────────────────
CREATE PROCEDURE sp_generate_renewal_alerts(
    IN p_days_ahead INT
)
BEGIN
    DECLARE done       INT DEFAULT 0;
    DECLARE v_sub_id   INT;
    DECLARE v_user_id  INT;
    DECLARE v_name     VARCHAR(150);
    DECLARE v_amount   DECIMAL(10,2);
    DECLARE v_currency CHAR(3);
    DECLARE v_next_dt  DATE;
    DECLARE v_days_left INT;

    DECLARE cur CURSOR FOR
        SELECT
            s.subscription_id,
            s.user_id,
            COALESCE(s.custom_name, p.service_name),
            s.amount,
            s.currency,
            s.next_billing_date,
            DATEDIFF(s.next_billing_date, CURDATE()) AS days_left
        FROM Subscriptions s
        JOIN Plans p ON p.plan_id = s.plan_id
        WHERE s.status = 'active'
          AND s.auto_renew = 1
          AND s.next_billing_date BETWEEN CURDATE()
              AND DATE_ADD(CURDATE(), INTERVAL p_days_ahead DAY);

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO v_sub_id, v_user_id, v_name, v_amount, v_currency, v_next_dt, v_days_left;
        IF done THEN LEAVE read_loop; END IF;

        -- Only insert if no renewal alert created today for this subscription
        IF NOT EXISTS (
            SELECT 1 FROM Alerts
             WHERE subscription_id = v_sub_id
               AND alert_type      = 'renewal_reminder'
               AND DATE(created_at)= CURDATE()
        ) THEN
            INSERT INTO Alerts (user_id, subscription_id, alert_type, title, message, severity)
            VALUES (
                v_user_id,
                v_sub_id,
                'renewal_reminder',
                CONCAT(v_name, ' renews in ', v_days_left,
                       IF(v_days_left = 1, ' day', ' days')),
                CONCAT(v_name, ' will be charged ',
                       v_currency, ' ', v_amount, ' on ', v_next_dt, '.'),
                IF(v_days_left <= 1, 'warning', 'info')
            );
        END IF;
    END LOOP;

    CLOSE cur;
    SELECT ROW_COUNT() AS alerts_generated;
END$$


-- ── SP 3 ──────────────────────────────────────────────────────
-- sp_check_expired_subscriptions
-- Marks subscriptions as 'expired' if end_date has passed,
-- and generates an expiry alert.
-- Usage: CALL sp_check_expired_subscriptions();
-- ──────────────────────────────────────────────────────────────
CREATE PROCEDURE sp_check_expired_subscriptions()
BEGIN
    -- Collect expiring subs into temp table first
    CREATE TEMPORARY TABLE IF NOT EXISTS tmp_expired AS
        SELECT subscription_id, user_id,
               COALESCE(custom_name, (SELECT service_name FROM Plans WHERE plan_id = s.plan_id)) AS svc_name
          FROM Subscriptions s
         WHERE status   = 'active'
           AND end_date IS NOT NULL
           AND end_date < CURDATE();

    -- Update status
    UPDATE Subscriptions
       SET status     = 'expired',
           updated_at = CURRENT_TIMESTAMP
     WHERE subscription_id IN (SELECT subscription_id FROM tmp_expired);

    -- Insert expiry alerts
    INSERT INTO Alerts (user_id, subscription_id, alert_type, title, message, severity)
    SELECT user_id, subscription_id,
           'subscription_expired',
           CONCAT(svc_name, ' subscription expired'),
           CONCAT('Your ', svc_name, ' subscription has expired. Renew to continue service.'),
           'warning'
      FROM tmp_expired;

    DROP TEMPORARY TABLE IF EXISTS tmp_expired;
    SELECT ROW_COUNT() AS expired_count;
END$$


-- ── SP 4 ──────────────────────────────────────────────────────
-- sp_generate_transaction
-- Manually trigger a billing transaction for a subscription.
-- Used by cron/scheduler when billing date arrives.
-- Usage: CALL sp_generate_transaction(1, 'Visa *4242', @txn_id);
-- ──────────────────────────────────────────────────────────────
CREATE PROCEDURE sp_generate_transaction(
    IN  p_subscription_id INT,
    IN  p_payment_method  VARCHAR(80),
    OUT p_transaction_id  INT
)
BEGIN
    DECLARE v_user_id     INT;
    DECLARE v_amount      DECIMAL(10,2);
    DECLARE v_currency    CHAR(3);
    DECLARE v_cycle       ENUM('daily','weekly','monthly','yearly');
    DECLARE v_next_bill   DATE;
    DECLARE v_period_end  DATE;
    DECLARE v_ref_no      VARCHAR(100);

    SELECT s.user_id, s.amount, s.currency, p.billing_cycle, s.next_billing_date
      INTO v_user_id, v_amount, v_currency, v_cycle, v_next_bill
      FROM Subscriptions s
      JOIN Plans p ON p.plan_id = s.plan_id
     WHERE s.subscription_id = p_subscription_id
       AND s.status = 'active';

    IF v_user_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Subscription not found or not active';
    END IF;

    -- Calculate period end
    SET v_period_end = CASE v_cycle
        WHEN 'daily'   THEN DATE_ADD(v_next_bill, INTERVAL  1 DAY   ) - INTERVAL 1 DAY
        WHEN 'weekly'  THEN DATE_ADD(v_next_bill, INTERVAL  7 DAY   ) - INTERVAL 1 DAY
        WHEN 'monthly' THEN DATE_ADD(v_next_bill, INTERVAL  1 MONTH ) - INTERVAL 1 DAY
        WHEN 'yearly'  THEN DATE_ADD(v_next_bill, INTERVAL  1 YEAR  ) - INTERVAL 1 DAY
        ELSE                DATE_ADD(v_next_bill, INTERVAL  1 MONTH ) - INTERVAL 1 DAY
    END;

    -- Unique reference number
    SET v_ref_no = CONCAT('TXN-', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), '-', p_subscription_id);

    INSERT INTO Transactions
        (subscription_id, user_id, amount, currency,
         transaction_date, billing_period_start, billing_period_end,
         status, payment_method, reference_no)
    VALUES
        (p_subscription_id, v_user_id, v_amount, v_currency,
         CURDATE(), v_next_bill, v_period_end,
         'completed', p_payment_method, v_ref_no);

    SET p_transaction_id = LAST_INSERT_ID();
    -- NOTE: next_billing_date is advanced by trg_after_transaction_insert
END$$


-- ── SP 5 ──────────────────────────────────────────────────────
-- sp_spending_by_category
-- Returns spending totals grouped by category for a user.
-- Usage: CALL sp_spending_by_category(1, 2026);
-- ──────────────────────────────────────────────────────────────
CREATE PROCEDURE sp_spending_by_category(
    IN p_user_id INT,
    IN p_year    INT
)
BEGIN
    SELECT
        cat.name        AS category,
        cat.icon        AS icon,
        cat.color_hex   AS color,
        SUM(t.amount)   AS total_spent,
        COUNT(DISTINCT s.subscription_id) AS sub_count
    FROM Transactions  t
    JOIN Subscriptions s   ON s.subscription_id = t.subscription_id
    JOIN Plans         p   ON p.plan_id         = s.plan_id
    JOIN Categories    cat ON cat.category_id   = p.category_id
    WHERE t.user_id = p_user_id
      AND YEAR(t.transaction_date) = p_year
      AND t.status = 'completed'
    GROUP BY cat.category_id, cat.name, cat.icon, cat.color_hex
    ORDER BY total_spent DESC;
END$$


-- ── SP 6 ──────────────────────────────────────────────────────
-- sp_resolve_hidden_charge
-- Marks a hidden charge as resolved and optionally notes reason.
-- Usage: CALL sp_resolve_hidden_charge(2, 'Disputed and refunded');
-- ──────────────────────────────────────────────────────────────
CREATE PROCEDURE sp_resolve_hidden_charge(
    IN p_hidden_charge_id INT,
    IN p_reason           VARCHAR(255)
)
BEGIN
    UPDATE Hidden_Charges
       SET is_resolved = 1,
           resolved_at = CURRENT_TIMESTAMP,
           description = CONCAT(COALESCE(description, ''), ' | Resolved: ', p_reason)
     WHERE hidden_charge_id = p_hidden_charge_id;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Hidden charge not found';
    END IF;
    SELECT 'Resolved successfully' AS result;
END$$


DELIMITER ;

-- ── Scheduled MySQL Event (requires event_scheduler=ON) ──────
-- Automatically runs renewal check every day at midnight
SET GLOBAL event_scheduler = ON;

CREATE EVENT IF NOT EXISTS evt_daily_renewal_check
    ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '00:00:00')
    DO
        CALL sp_generate_renewal_alerts(7);

CREATE EVENT IF NOT EXISTS evt_daily_expiry_check
    ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '00:05:00')
    DO
        CALL sp_check_expired_subscriptions();
