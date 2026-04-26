-- ============================================================
--  TRIGGERS — Subscription Management & Hidden Charges Tracker
-- ============================================================
USE subscription_tracker;

DELIMITER $$

-- ── TRIGGER 1 ─────────────────────────────────────────────────
-- After a new Transaction is inserted:
--   (a) Advance the subscription's next_billing_date
--   (b) Detect price changes vs previous transaction
--   (c) Detect duplicate charges (same sub, same period)
-- ──────────────────────────────────────────────────────────────
CREATE TRIGGER trg_after_transaction_insert
AFTER INSERT ON Transactions
FOR EACH ROW
BEGIN
    DECLARE v_prev_amount       DECIMAL(10,2);
    DECLARE v_billing_cycle     ENUM('daily','weekly','monthly','yearly');
    DECLARE v_dup_count         INT;
    DECLARE v_sub_amount        DECIMAL(10,2);
    DECLARE v_hc_id             INT;

    -- ── 1. Advance next_billing_date based on billing cycle ──
    SELECT p.billing_cycle
      INTO v_billing_cycle
      FROM Subscriptions s
      JOIN Plans p ON p.plan_id = s.plan_id
     WHERE s.subscription_id = NEW.subscription_id;

    UPDATE Subscriptions
       SET next_billing_date = CASE v_billing_cycle
               WHEN 'daily'   THEN DATE_ADD(NEW.billing_period_end, INTERVAL 1  DAY)
               WHEN 'weekly'  THEN DATE_ADD(NEW.billing_period_end, INTERVAL 7  DAY)
               WHEN 'monthly' THEN DATE_ADD(NEW.billing_period_end, INTERVAL 1  MONTH)
               WHEN 'yearly'  THEN DATE_ADD(NEW.billing_period_end, INTERVAL 1  YEAR)
               ELSE                DATE_ADD(NEW.billing_period_end, INTERVAL 1  MONTH)
           END,
           updated_at = CURRENT_TIMESTAMP
     WHERE subscription_id = NEW.subscription_id;

    -- ── 2. Detect price change vs previous transaction ────────
    SELECT amount
      INTO v_prev_amount
      FROM Transactions
     WHERE subscription_id = NEW.subscription_id
       AND transaction_id  <> NEW.transaction_id
       AND status          = 'completed'
     ORDER BY transaction_date DESC
     LIMIT 1;

    SELECT amount INTO v_sub_amount
      FROM Subscriptions WHERE subscription_id = NEW.subscription_id;

    IF v_prev_amount IS NOT NULL AND NEW.amount <> v_prev_amount THEN
        -- Log hidden charge
        INSERT INTO Hidden_Charges
            (transaction_id, subscription_id, user_id, charge_type,
             expected_amount, actual_amount, description)
        VALUES
            (NEW.transaction_id, NEW.subscription_id, NEW.user_id,
             IF(NEW.amount > v_prev_amount, 'price_increase', 'unexpected_fee'),
             v_prev_amount, NEW.amount,
             CONCAT('Amount changed from $', v_prev_amount,
                    ' to $', NEW.amount,
                    ' (', IF(NEW.amount > v_prev_amount, '+', ''),
                    ROUND(NEW.amount - v_prev_amount, 2), ')'));

        SET v_hc_id = LAST_INSERT_ID();

        -- Record in price history
        INSERT INTO Price_History (subscription_id, old_amount, new_amount, changed_by, reason)
        VALUES (NEW.subscription_id, v_prev_amount, NEW.amount, 'trigger',
                'Auto-detected via transaction comparison');

        -- Update subscription amount to reflect new price
        UPDATE Subscriptions
           SET amount = NEW.amount, updated_at = CURRENT_TIMESTAMP
         WHERE subscription_id = NEW.subscription_id;

        -- Generate alert
        INSERT INTO Alerts
            (user_id, subscription_id, hidden_charge_id, alert_type, title, message, severity)
        VALUES
            (NEW.user_id, NEW.subscription_id, v_hc_id,
             IF(NEW.amount > v_prev_amount, 'price_increased', 'overcharge_detected'),
             IF(NEW.amount > v_prev_amount,
                'Price Increase Detected',
                'Unexpected Charge Change Detected'),
             CONCAT('Your subscription charge changed from $', v_prev_amount,
                    ' to $', NEW.amount, ' on ', NEW.transaction_date, '.'),
             IF(NEW.amount > v_prev_amount, 'warning', 'critical'));
    END IF;

    -- ── 3. Detect duplicate charges ───────────────────────────
    SELECT COUNT(*) INTO v_dup_count
      FROM Transactions
     WHERE subscription_id       = NEW.subscription_id
       AND billing_period_start  = NEW.billing_period_start
       AND billing_period_end    = NEW.billing_period_end
       AND status                = 'completed'
       AND transaction_id       <> NEW.transaction_id;

    IF v_dup_count > 0 THEN
        INSERT INTO Hidden_Charges
            (transaction_id, subscription_id, user_id, charge_type,
             expected_amount, actual_amount, description)
        VALUES
            (NEW.transaction_id, NEW.subscription_id, NEW.user_id,
             'duplicate_charge', 0.00, NEW.amount,
             CONCAT('Duplicate charge detected for billing period ',
                    NEW.billing_period_start, ' to ', NEW.billing_period_end));

        SET v_hc_id = LAST_INSERT_ID();

        INSERT INTO Alerts
            (user_id, subscription_id, hidden_charge_id, alert_type, title, message, severity)
        VALUES
            (NEW.user_id, NEW.subscription_id, v_hc_id,
             'duplicate_detected',
             'Duplicate Charge Detected!',
             CONCAT('A duplicate charge of $', NEW.amount,
                    ' was detected. Check your billing statement.'),
             'critical');
    END IF;
END$$


-- ── TRIGGER 2 ─────────────────────────────────────────────────
-- Before UPDATE on Subscriptions:
--   If the amount changes manually, record in Price_History
-- ──────────────────────────────────────────────────────────────
CREATE TRIGGER trg_before_subscription_update
BEFORE UPDATE ON Subscriptions
FOR EACH ROW
BEGIN
    IF OLD.amount <> NEW.amount THEN
        INSERT INTO Price_History (subscription_id, old_amount, new_amount, changed_by, reason)
        VALUES (OLD.subscription_id, OLD.amount, NEW.amount, 'user',
                'User manually updated subscription amount');
    END IF;
END$$


-- ── TRIGGER 3 ─────────────────────────────────────────────────
-- After a Subscription is cancelled or expired:
--   Clear pending alerts for that subscription
-- ──────────────────────────────────────────────────────────────
CREATE TRIGGER trg_after_subscription_status_change
AFTER UPDATE ON Subscriptions
FOR EACH ROW
BEGIN
    IF OLD.status = 'active' AND NEW.status IN ('cancelled', 'expired') THEN
        -- Mark renewal alerts as read (they're no longer relevant)
        UPDATE Alerts
           SET is_read = 1, read_at = CURRENT_TIMESTAMP
         WHERE subscription_id = NEW.subscription_id
           AND alert_type      = 'renewal_reminder'
           AND is_read         = 0;
    END IF;
END$$


-- ── TRIGGER 4 ─────────────────────────────────────────────────
-- After a Hidden_Charge is resolved:
--   Automatically mark linked alert as read
-- ──────────────────────────────────────────────────────────────
CREATE TRIGGER trg_after_hidden_charge_resolved
AFTER UPDATE ON Hidden_Charges
FOR EACH ROW
BEGIN
    IF OLD.is_resolved = 0 AND NEW.is_resolved = 1 THEN
        UPDATE Alerts
           SET is_read = 1, read_at = CURRENT_TIMESTAMP
         WHERE hidden_charge_id = NEW.hidden_charge_id
           AND is_read = 0;
    END IF;
END$$


DELIMITER ;
