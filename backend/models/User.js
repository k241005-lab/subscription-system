const db = require('../config/db');

class UserModel {
    static async findByEmail(email) {
        const [rows] = await db.execute(
            'SELECT * FROM Users WHERE email = ? AND is_active = 1', [email]
        );
        return rows[0] || null;
    }

    static async findById(user_id) {
        const [rows] = await db.execute(
            'SELECT user_id, full_name, email, phone, currency, created_at FROM Users WHERE user_id = ?',
            [user_id]
        );
        return rows[0] || null;
    }

    static async create({ full_name, email, password_hash, phone, currency }) {
        const [result] = await db.execute(
            `INSERT INTO Users (full_name, email, password_hash, phone, currency)
             VALUES (?, ?, ?, ?, ?)`,
            [full_name, email, password_hash, phone || null, currency || 'USD']
        );
        return result.insertId;
    }

    static async getDashboardStats(user_id) {
        const [rows] = await db.execute(`
            SELECT
                (SELECT COUNT(*) FROM Subscriptions WHERE user_id = ? AND status = 'active') AS active_subscriptions,
                (SELECT COALESCE(SUM(amount),0) FROM Transactions
                  WHERE user_id = ?
                    AND MONTH(transaction_date) = MONTH(CURDATE())
                    AND YEAR(transaction_date)  = YEAR(CURDATE())
                    AND status = 'completed')                                                   AS monthly_spend,
                (SELECT COUNT(*) FROM Hidden_Charges WHERE user_id = ? AND is_resolved = 0)    AS unresolved_hidden_charges,
                (SELECT COUNT(*) FROM Alerts WHERE user_id = ? AND is_read = 0)                AS unread_alerts
        `, [user_id, user_id, user_id, user_id]);
        return rows[0];
    }
}

module.exports = UserModel;
