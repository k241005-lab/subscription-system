const db = require('../config/db');

// ── Transaction Model ─────────────────────────────────────────
class TransactionModel {
    static async getAllByUser(user_id, filters = {}) {
        let query = `
            SELECT
                t.*,
                COALESCE(s.custom_name, p.service_name) AS service_name,
                p.plan_name,
                c.name      AS category,
                c.color_hex
            FROM Transactions  t
            JOIN Subscriptions s ON s.subscription_id = t.subscription_id
            JOIN Plans         p ON p.plan_id         = s.plan_id
            JOIN Categories    c ON c.category_id     = p.category_id
            WHERE t.user_id = ?
        `;
        const params = [user_id];

        if (filters.month && filters.year) {
            query += ' AND MONTH(t.transaction_date) = ? AND YEAR(t.transaction_date) = ?';
            params.push(filters.month, filters.year);
        }
        if (filters.subscription_id) {
            query += ' AND t.subscription_id = ?';
            params.push(filters.subscription_id);
        }
        query += ' ORDER BY t.transaction_date DESC LIMIT 100';

        const [rows] = await db.execute(query, params);
        return rows;
    }

    static async getMonthlyReport(user_id, month, year) {
        const [rows] = await db.execute(
            'CALL sp_monthly_expense_report(?, ?, ?)', [user_id, month, year]
        );
        return { breakdown: rows[0], total: rows[1] };
    }

    static async generateTransaction(subscription_id, payment_method) {
        const [rows] = await db.execute(
            'CALL sp_generate_transaction(?, ?, @txn_id)', [subscription_id, payment_method]
        );
        const [[{ '@txn_id': txn_id }]] = await db.execute('SELECT @txn_id');
        return txn_id;
    }

    static async getSpendingByCategory(user_id, year) {
        const [rows] = await db.execute(
            'CALL sp_spending_by_category(?, ?)', [user_id, year]
        );
        return rows[0];
    }

    static async getMonthlyTrend(user_id) {
        const [rows] = await db.execute(`
            SELECT
                DATE_FORMAT(transaction_date, '%Y-%m') AS month,
                SUM(amount)  AS total,
                COUNT(*)     AS tx_count
            FROM Transactions
            WHERE user_id = ?
              AND status   = 'completed'
              AND transaction_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
            GROUP BY month
            ORDER BY month ASC
        `, [user_id]);
        return rows;
    }
}

// ── HiddenCharge Model ────────────────────────────────────────
class HiddenChargeModel {
    static async getAllByUser(user_id, onlyUnresolved = false) {
        let query = `
            SELECT
                hc.*,
                COALESCE(s.custom_name, p.service_name) AS service_name,
                p.plan_name,
                c.name      AS category,
                c.color_hex,
                t.transaction_date,
                t.reference_no
            FROM Hidden_Charges hc
            JOIN Subscriptions  s ON s.subscription_id = hc.subscription_id
            JOIN Plans          p ON p.plan_id         = s.plan_id
            JOIN Categories     c ON c.category_id     = p.category_id
            JOIN Transactions   t ON t.transaction_id  = hc.transaction_id
            WHERE hc.user_id = ?
        `;
        const params = [user_id];
        if (onlyUnresolved) { query += ' AND hc.is_resolved = 0'; }
        query += ' ORDER BY hc.detected_at DESC';
        const [rows] = await db.execute(query, params);
        return rows;
    }

    static async resolve(hidden_charge_id, user_id, reason) {
        const [rows] = await db.execute(
            'CALL sp_resolve_hidden_charge(?, ?)', [hidden_charge_id, reason]
        );
        return rows;
    }
}

// ── Alert Model ───────────────────────────────────────────────
class AlertModel {
    static async getAllByUser(user_id) {
        const [rows] = await db.execute(`
            SELECT
                a.*,
                COALESCE(s.custom_name, p.service_name) AS service_name,
                c.icon AS category_icon,
                c.color_hex
            FROM Alerts       a
            LEFT JOIN Subscriptions  s ON s.subscription_id = a.subscription_id
            LEFT JOIN Plans          p ON p.plan_id         = s.plan_id
            LEFT JOIN Categories     c ON c.category_id     = p.category_id
            WHERE a.user_id = ?
            ORDER BY a.created_at DESC
            LIMIT 50
        `, [user_id]);
        return rows;
    }

    static async markRead(alert_id, user_id) {
        const [result] = await db.execute(
            `UPDATE Alerts SET is_read = 1, read_at = NOW()
             WHERE alert_id = ? AND user_id = ?`,
            [alert_id, user_id]
        );
        return result.affectedRows;
    }

    static async markAllRead(user_id) {
        const [result] = await db.execute(
            `UPDATE Alerts SET is_read = 1, read_at = NOW()
             WHERE user_id = ? AND is_read = 0`,
            [user_id]
        );
        return result.affectedRows;
    }

    static async generateRenewalAlerts(daysAhead = 7) {
        const [rows] = await db.execute('CALL sp_generate_renewal_alerts(?)', [daysAhead]);
        return rows[0];
    }
}

module.exports = { TransactionModel, HiddenChargeModel, AlertModel };
