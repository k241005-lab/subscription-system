-- ============================================================
--  SUBSCRIPTION MANAGEMENT & HIDDEN CHARGES TRACKER SYSTEM
--  Database Schema | MySQL | Fully Normalized to 3NF
--  Authors: Ali Khurram, Mohsin Hassan, Abuzar Mehdi
-- ============================================================

CREATE DATABASE IF NOT EXISTS subscription_tracker;

USE subscription_tracker;

-- ============================================================
-- TABLE 1: Users
-- Stores registered user accounts
-- ============================================================
CREATE TABLE Users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    CONSTRAINT chk_currency CHECK (LENGTH(currency) = 3)
);

-- ============================================================
-- TABLE 2: Categories
-- Subscription categories (Streaming, SaaS, Fitness, etc.)
-- Separated from Subscriptions to satisfy 3NF
-- ============================================================
CREATE TABLE Categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE,
    icon VARCHAR(50) NOT NULL DEFAULT 'bi-tag',
    color_hex CHAR(7) NOT NULL DEFAULT '#6c757d'
);

-- ============================================================
-- TABLE 3: Plans
-- Master list of known service plans (Netflix Basic, etc.)
-- Decoupled from Subscriptions to avoid transitive dependency
-- ============================================================
CREATE TABLE Plans (
    plan_id INT AUTO_INCREMENT PRIMARY KEY,
    service_name VARCHAR(100) NOT NULL,
    plan_name VARCHAR(100) NOT NULL,
    category_id INT NOT NULL,
    billing_cycle ENUM(
        'daily',
        'weekly',
        'monthly',
        'yearly'
    ) NOT NULL DEFAULT 'monthly',
    base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    logo_url VARCHAR(255),
    website_url VARCHAR(255),
    CONSTRAINT fk_plans_category FOREIGN KEY (category_id) REFERENCES Categories (category_id),
    CONSTRAINT uq_plan UNIQUE (
        service_name,
        plan_name,
        billing_cycle
    )
);

-- ============================================================
-- TABLE 4: Subscriptions
-- User's actual active subscriptions
-- ============================================================
CREATE TABLE Subscriptions (
    subscription_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    plan_id INT NOT NULL,
    custom_name VARCHAR(150), -- override display name
    amount DECIMAL(10, 2) NOT NULL CHECK (amount >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    start_date DATE NOT NULL,
    next_billing_date DATE NOT NULL,
    end_date DATE, -- NULL = ongoing
    status ENUM(
        'active',
        'paused',
        'cancelled',
        'expired'
    ) NOT NULL DEFAULT 'active',
    auto_renew TINYINT(1) NOT NULL DEFAULT 1,
    notes TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_sub_user FOREIGN KEY (user_id) REFERENCES Users (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_sub_plan FOREIGN KEY (plan_id) REFERENCES Plans (plan_id)
);

-- Index for fast billing-date lookups (used by daily scheduler)
CREATE INDEX idx_sub_next_billing ON Subscriptions (next_billing_date, status);

CREATE INDEX idx_sub_user ON Subscriptions (user_id);

-- ============================================================
-- TABLE 5: Transactions
-- Every billing event (auto-generated or manual)
-- ============================================================
CREATE TABLE Transactions (
    transaction_id INT AUTO_INCREMENT PRIMARY KEY,
    subscription_id INT NOT NULL,
    user_id INT NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    transaction_date DATE NOT NULL,
    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,
    status ENUM(
        'pending',
        'completed',
        'failed',
        'refunded'
    ) NOT NULL DEFAULT 'completed',
    payment_method VARCHAR(80),
    reference_no VARCHAR(100) UNIQUE,
    notes TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_txn_sub FOREIGN KEY (subscription_id) REFERENCES Subscriptions (subscription_id) ON DELETE CASCADE,
    CONSTRAINT fk_txn_user FOREIGN KEY (user_id) REFERENCES Users (user_id) ON DELETE CASCADE
);

CREATE INDEX idx_txn_user_date ON Transactions (user_id, transaction_date);

CREATE INDEX idx_txn_sub ON Transactions (subscription_id);

-- ============================================================
-- TABLE 6: Hidden_Charges
-- Detected anomalies: price spikes, duplicates, unexpected fees
-- ============================================================
CREATE TABLE Hidden_Charges (
    hidden_charge_id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id INT NOT NULL,
    subscription_id INT NOT NULL,
    user_id INT NOT NULL,
    charge_type ENUM(
        'price_increase',
        'duplicate_charge',
        'unexpected_fee',
        'early_renewal',
        'currency_change'
    ) NOT NULL,
    expected_amount DECIMAL(10, 2) NOT NULL,
    actual_amount DECIMAL(10, 2) NOT NULL,
    difference DECIMAL(10, 2) GENERATED ALWAYS AS (
        actual_amount - expected_amount
    ) STORED,
    description TEXT,
    detected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_resolved TINYINT(1) NOT NULL DEFAULT 0,
    resolved_at DATETIME,
    CONSTRAINT fk_hc_txn FOREIGN KEY (transaction_id) REFERENCES Transactions (transaction_id) ON DELETE CASCADE,
    CONSTRAINT fk_hc_sub FOREIGN KEY (subscription_id) REFERENCES Subscriptions (subscription_id) ON DELETE CASCADE,
    CONSTRAINT fk_hc_user FOREIGN KEY (user_id) REFERENCES Users (user_id) ON DELETE CASCADE
);

CREATE INDEX idx_hc_user ON Hidden_Charges (user_id, is_resolved);

CREATE INDEX idx_hc_sub ON Hidden_Charges (subscription_id);

-- ============================================================
-- TABLE 7: Alerts
-- Renewal reminders, overcharge warnings, etc.
-- ============================================================
CREATE TABLE Alerts (
    alert_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    subscription_id INT, -- NULL = account-level alert
    hidden_charge_id INT, -- linked anomaly if applicable
    alert_type ENUM(
        'renewal_reminder',
        'overcharge_detected',
        'duplicate_detected',
        'subscription_expired',
        'payment_failed',
        'price_increased'
    ) NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    severity ENUM('info', 'warning', 'critical') NOT NULL DEFAULT 'info',
    is_read TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    read_at DATETIME,
    CONSTRAINT fk_alert_user FOREIGN KEY (user_id) REFERENCES Users (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_alert_sub FOREIGN KEY (subscription_id) REFERENCES Subscriptions (subscription_id) ON DELETE SET NULL,
    CONSTRAINT fk_alert_hc FOREIGN KEY (hidden_charge_id) REFERENCES Hidden_Charges (hidden_charge_id) ON DELETE SET NULL
);

CREATE INDEX idx_alert_user_read ON Alerts (user_id, is_read);

-- ============================================================
-- TABLE 8: Price_History
-- Audit trail of plan price changes over time (3NF compliance)
-- ============================================================
CREATE TABLE Price_History (
    history_id INT AUTO_INCREMENT PRIMARY KEY,
    subscription_id INT NOT NULL,
    old_amount DECIMAL(10, 2) NOT NULL,
    new_amount DECIMAL(10, 2) NOT NULL,
    changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by ENUM('user', 'system', 'trigger') NOT NULL DEFAULT 'system',
    reason VARCHAR(255),
    CONSTRAINT fk_ph_sub FOREIGN KEY (subscription_id) REFERENCES Subscriptions (subscription_id) ON DELETE CASCADE
);