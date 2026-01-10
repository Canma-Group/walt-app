-- Database initialization script for QRIS Payment System

-- Create payment_intents table
CREATE TABLE IF NOT EXISTS payment_intents (
    payment_id UUID PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL,
    payer_wallet_address VARCHAR(42) NOT NULL,
    qris_payload TEXT NOT NULL,
    qris_hash VARCHAR(64) NOT NULL,
    merchant_name VARCHAR(255),
    amount_idr DECIMAL(20, 2) NOT NULL,
    lsk_amount_expected VARCHAR(50) NOT NULL,
    lsk_amount_expected_wei VARCHAR(78) NOT NULL,
    escrow_address VARCHAR(42) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'CREATED',
    tx_hash VARCHAR(66),
    verified_at TIMESTAMP,
    receipt_id VARCHAR(50),
    ledger_tx_hash VARCHAR(66),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_payment_status ON payment_intents(status);
CREATE INDEX IF NOT EXISTS idx_payment_escrow ON payment_intents(escrow_address);
CREATE INDEX IF NOT EXISTS idx_payment_payer ON payment_intents(payer_wallet_address);
CREATE INDEX IF NOT EXISTS idx_payment_created ON payment_intents(created_at);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to auto-update updated_at
CREATE TRIGGER update_payment_intents_updated_at BEFORE UPDATE
    ON payment_intents FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Transaction history table (for app display)
CREATE TABLE IF NOT EXISTS transaction_history (
    id SERIAL PRIMARY KEY,
    payment_id UUID REFERENCES payment_intents(payment_id),
    wallet_address VARCHAR(42) NOT NULL,
    tx_type VARCHAR(20) NOT NULL DEFAULT 'QRIS_PAYMENT',
    merchant_name VARCHAR(255),
    amount_idr DECIMAL(20, 2) NOT NULL,
    lsk_amount VARCHAR(50) NOT NULL,
    tx_hash VARCHAR(66),
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_txhistory_wallet ON transaction_history(wallet_address);
CREATE INDEX IF NOT EXISTS idx_txhistory_created ON transaction_history(created_at DESC);

-- Merchant notifications table (for mock merchant dashboard)
CREATE TABLE IF NOT EXISTS merchant_notifications (
    id SERIAL PRIMARY KEY,
    payment_id UUID REFERENCES payment_intents(payment_id),
    merchant_name VARCHAR(255) NOT NULL,
    merchant_city VARCHAR(100),
    amount_idr DECIMAL(20, 2) NOT NULL,
    payer_wallet VARCHAR(42) NOT NULL,
    tx_hash VARCHAR(66),
    status VARCHAR(20) NOT NULL DEFAULT 'RECEIVED',
    notified_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merchant_notif_name ON merchant_notifications(merchant_name);
CREATE INDEX IF NOT EXISTS idx_merchant_notif_created ON merchant_notifications(notified_at DESC);
