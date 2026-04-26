require('dotenv').config();
const express = require('express');
const cors    = require('cors');
const cron    = require('node-cron');
const { AlertModel } = require('./models/Transaction');

const app = express();

// ── Middleware ────────────────────────────────────────────────
app.use(cors({
    origin: process.env.CLIENT_URL || '*',
    methods: ['GET','POST','PUT','PATCH','DELETE','OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ── Routes ────────────────────────────────────────────────────
app.use('/api', require('./routes/index'));
// ── Health Check ──────────────────────────────────────────────
app.get('/', (req, res) => {
    res.json({
        message: '🚀 Subscription Tracker API is running',
        version: '1.0.0',
        endpoints: '/api/auth | /api/subscriptions | /api/transactions | /api/hidden-charges | /api/alerts'
    });
});

// ── 404 handler ───────────────────────────────────────────────
app.use((req, res) => {
    res.status(404).json({ success: false, message: `Route ${req.originalUrl} not found` });
});

// ── Global error handler ──────────────────────────────────────
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
});

// ── Scheduled Jobs (node-cron) ────────────────────────────────
// Every day at 00:00 — generate renewal alerts for next 7 days
cron.schedule('0 0 * * *', async () => {
    console.log('🕐 Running daily renewal alert generation...');
    try {
        await AlertModel.generateRenewalAlerts(7);
        console.log('✅ Renewal alerts generated');
    } catch (err) {
        console.error('❌ Cron job failed:', err.message);
    }
});

// ── Start Server ──────────────────────────────────────────────
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
    console.log(`\n🚀 Server running on http://localhost:${PORT}`);
    console.log(`📡 API Base: http://localhost:${PORT}/api`);
    console.log(`🌐 Accepting requests from: ${process.env.CLIENT_URL || '*'}\n`);
});
