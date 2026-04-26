const db = require('../config/db');

class SubscriptionModel {
    static async getAllByUser(user_id) {
        const [rows] = await db.execute(`
            SELECT
                s.subscription_id,
                COALESCE(s.custom_name, p.service_name) AS service_name,
                p.service_name AS original_service,
                p.plan_name,
                p.billing_cycle,
                s.amount,
                s.currency,
                s.start_date,
                s.next_billing_date,
                s.end_date,
                s.status,
                s.auto_renew,
                s.notes,
                c.name       AS category,
                c.icon       AS category_icon,
                c.color_hex,
                DATEDIFF(s.next_billing_date, CURDATE()) AS days_until_renewal
            FROM Subscriptions s
            JOIN Plans      p ON p.plan_id     = s.plan_id
            JOIN Categories c ON c.category_id = p.category_id
            WHERE s.user_id = ?
            ORDER BY s.next_billing_date ASC
        `, [user_id]);
        return rows;
    }

    static async getById(subscription_id, user_id) {
        const [rows] = await db.execute(`
            SELECT
                s.*,
                COALESCE(s.custom_name, p.service_name) AS service_name,
                p.service_name AS original_service,
                p.plan_name,
                p.billing_cycle,
                c.name  AS category,
                c.icon  AS category_icon,
                c.color_hex
            FROM Subscriptions s
            JOIN Plans      p ON p.plan_id     = s.plan_id
            JOIN Categories c ON c.category_id = p.category_id
            WHERE s.subscription_id = ? AND s.user_id = ?
        `, [subscription_id, user_id]);
        return rows[0] || null;
    }

    static async create({ user_id, plan_id, custom_name, amount, currency, start_date, end_date, auto_renew, notes, billing_cycle }) {
        // Calculate next_billing_date from start_date based on billing_cycle
        const cycleMap = { daily: 1, weekly: 7, monthly: 30, yearly: 365 };
        const conn = await db.getConnection();
        const [result] = await conn.execute(`
            INSERT INTO Subscriptions
                (user_id, plan_id, custom_name, amount, currency, start_date, next_billing_date, end_date, auto_renew, notes)
            SELECT ?, ?, ?, ?, ?, ?,
                CASE billing_cycle
                    WHEN 'daily'   THEN DATE_ADD(?, INTERVAL 1 DAY)
                    WHEN 'weekly'  THEN DATE_ADD(?, INTERVAL 7 DAY)
                    WHEN 'monthly' THEN DATE_ADD(?, INTERVAL 1 MONTH)
                    WHEN 'yearly'  THEN DATE_ADD(?, INTERVAL 1 YEAR)
                END,
                ?, ?, ?
            FROM Plans WHERE plan_id = ?
        `, [user_id, plan_id, custom_name || null, amount, currency || 'USD',
            start_date, start_date, start_date, start_date, start_date,
            end_date || null, auto_renew ?? 1, notes || null, plan_id]);
        conn.release();
        return result.insertId;
    }

    static async update(subscription_id, user_id, fields) {
        const allowed = ['custom_name', 'amount', 'currency', 'end_date', 'status', 'auto_renew', 'notes'];
        const setClauses = [];
        const values = [];
        for (const key of allowed) {
            if (fields[key] !== undefined) {
                setClauses.push(`${key} = ?`);
                values.push(fields[key]);
            }
        }
        if (!setClauses.length) throw new Error('No valid fields to update');
        values.push(subscription_id, user_id);
        const [result] = await db.execute(
            `UPDATE Subscriptions SET ${setClauses.join(', ')} WHERE subscription_id = ? AND user_id = ?`,
            values
        );
        return result.affectedRows;
    }

    static async delete(subscription_id, user_id) {
        const [result] = await db.execute(
            `UPDATE Subscriptions SET status = 'cancelled', updated_at = NOW()
             WHERE subscription_id = ? AND user_id = ?`,
            [subscription_id, user_id]
        );
        return result.affectedRows;
    }

    static async getPlans() {
        const [rows] = await db.execute(`
            SELECT p.*, c.name AS category, c.icon, c.color_hex
              FROM Plans p
              JOIN Categories c ON c.category_id = p.category_id
             ORDER BY c.name, p.service_name, p.plan_name
        `);
        return rows;
    }

    static async getPriceHistory(subscription_id, user_id) {
        const [rows] = await db.execute(`
            SELECT ph.*
              FROM Price_History ph
              JOIN Subscriptions s ON s.subscription_id = ph.subscription_id
             WHERE ph.subscription_id = ? AND s.user_id = ?
             ORDER BY ph.changed_at DESC
        `, [subscription_id, user_id]);
        return rows;
    }
}

module.exports = SubscriptionModel;
