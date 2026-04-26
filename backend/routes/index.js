const express = require('express');
const router  = express.Router();
const auth    = require('../middleware/auth');

const authCtrl = require('../controllers/authController');
const subCtrl  = require('../controllers/subscriptionController');
const dataCtrl = require('../controllers/dataController');

// ── Auth ─────────────────────────────────────────────────────
router.post('/auth/register', authCtrl.register);
router.post('/auth/login',    authCtrl.login);
router.get ('/auth/me',  auth, authCtrl.me);

// ── Subscriptions ─────────────────────────────────────────────
router.get   ('/subscriptions/plans',               auth, subCtrl.getPlans);
router.get   ('/subscriptions',                     auth, subCtrl.getAll);
router.get   ('/subscriptions/:id',                 auth, subCtrl.getOne);
router.post  ('/subscriptions',                     auth, subCtrl.create);
router.patch ('/subscriptions/:id',                 auth, subCtrl.update);
router.delete('/subscriptions/:id',                 auth, subCtrl.cancel);
router.get   ('/subscriptions/:id/price-history',   auth, subCtrl.getPriceHistory);

// ── Transactions ──────────────────────────────────────────────
router.get ('/transactions',          auth, dataCtrl.getTransactions);
router.post('/transactions',          auth, dataCtrl.createTransaction);
router.post('/transactions/generate', auth, dataCtrl.generateTransaction);
router.get ('/transactions/report',   auth, dataCtrl.getMonthlyReport);
router.get ('/transactions/analytics',auth, dataCtrl.getAnalytics);

// ── Hidden Charges ────────────────────────────────────────────
router.get  ('/hidden-charges',            auth, dataCtrl.getHiddenCharges);
router.post ('/hidden-charges',            auth, dataCtrl.createHiddenCharge);
router.patch('/hidden-charges/:id/resolve',auth, dataCtrl.resolveHiddenCharge);

// ── Alerts ────────────────────────────────────────────────────
router.get  ('/alerts',                    auth, dataCtrl.getAlerts);
router.post ('/alerts',                    auth, dataCtrl.createAlert);
router.patch('/alerts/read-all',           auth, dataCtrl.markAllRead);
router.patch('/alerts/:id/read',           auth, dataCtrl.markRead);
router.post ('/alerts/generate-renewals',  auth, dataCtrl.generateRenewals);

module.exports = router;
