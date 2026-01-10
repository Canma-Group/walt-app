-- ============================================================
-- CRYPTO-TO-FIAT PAYMENT SYSTEM - Database Schema v2
-- Hackathon MVP - Lisk Mainnet
-- ============================================================

-- ============ ORDERS TABLE ============
-- Core order tracking from escrow lock to settlement
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    order_id VARCHAR(66) UNIQUE NOT NULL,  -- bytes32 from contract
    merchant_id VARCHAR(100) NOT NULL,
    buyer_address VARCHAR(42) NOT NULL,
    
    -- Amounts
    amount_lsk_wei VARCHAR(78) NOT NULL,
    amount_lsk DECIMAL(36, 18) NOT NULL,
    amount_idr DECIMAL(20, 2),  -- Filled after conversion
    
    -- Blockchain data
    escrow_tx_hash VARCHAR(66),
    block_number BIGINT,
    locked_at TIMESTAMP,
    expires_at TIMESTAMP,
    
    -- Status tracking
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    -- PENDING -> LOCKED -> PAID -> CONVERTING -> CONVERTED -> APPROVED -> SETTLING -> SETTLED
    -- Alternative paths: LOCKED -> REFUNDED, APPROVED -> ON_HOLD
    
    -- Timestamps
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Idempotency
    CONSTRAINT unique_order_tx UNIQUE (order_id, escrow_tx_hash)
);

CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_merchant ON orders(merchant_id);
CREATE INDEX IF NOT EXISTS idx_orders_buyer ON orders(buyer_address);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at DESC);

-- ============ TRADES TABLE ============
-- LSK -> IDR conversion tracking
CREATE TABLE IF NOT EXISTS trades (
    id SERIAL PRIMARY KEY,
    order_id VARCHAR(66) REFERENCES orders(order_id),
    trade_id VARCHAR(100) UNIQUE NOT NULL,  -- External trade ID
    
    -- Trade details
    exchange VARCHAR(50) NOT NULL DEFAULT 'INDODAX_MOCK',
    sell_amount_lsk DECIMAL(36, 18) NOT NULL,
    received_idr DECIMAL(20, 2) NOT NULL,
    exchange_rate DECIMAL(20, 8) NOT NULL,  -- IDR per LSK
    
    -- Fees
    exchange_fee_idr DECIMAL(20, 2) DEFAULT 0,
    
    -- Status
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    -- PENDING -> EXECUTED -> SETTLED
    
    executed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trades_order ON trades(order_id);
CREATE INDEX IF NOT EXISTS idx_trades_status ON trades(status);

-- ============ LEDGER TABLE ============
-- Merchant balance tracking
CREATE TABLE IF NOT EXISTS merchant_ledger (
    id SERIAL PRIMARY KEY,
    merchant_id VARCHAR(100) NOT NULL,
    order_id VARCHAR(66) REFERENCES orders(order_id),
    
    -- Amounts
    gross_idr DECIMAL(20, 2) NOT NULL,
    platform_fee_idr DECIMAL(20, 2) NOT NULL,
    net_idr DECIMAL(20, 2) NOT NULL,
    
    -- Fee config at time of transaction
    fee_rate_percent DECIMAL(5, 2) NOT NULL,  -- MDR rate applied
    
    -- Reference
    description TEXT,
    
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ledger_merchant ON merchant_ledger(merchant_id);
CREATE INDEX IF NOT EXISTS idx_ledger_order ON merchant_ledger(order_id);

-- ============ SETTLEMENTS TABLE ============
-- Fiat payout tracking (SIMULATED)
CREATE TABLE IF NOT EXISTS settlements (
    id SERIAL PRIMARY KEY,
    settlement_id VARCHAR(100) UNIQUE NOT NULL,
    merchant_id VARCHAR(100) NOT NULL,
    order_id VARCHAR(66) REFERENCES orders(order_id),
    
    -- Payout details
    payout_amount_idr DECIMAL(20, 2) NOT NULL,
    payout_reference VARCHAR(100),  -- Mock bank reference
    payout_method VARCHAR(50) DEFAULT 'BANK_TRANSFER_SIMULATED',
    
    -- Status
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    -- PENDING -> PROCESSING -> COMPLETED -> FAILED
    
    -- ⚠️ HACKATHON: Settlement is SIMULATED
    is_simulated BOOLEAN DEFAULT TRUE,
    simulation_note TEXT DEFAULT 'SIMULATED FOR HACKATHON - No real fiat transfer',
    
    processed_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_settlements_merchant ON settlements(merchant_id);
CREATE INDEX IF NOT EXISTS idx_settlements_status ON settlements(status);

-- ============ RULE ENGINE LOG ============
-- Audit trail for auto-approval decisions
CREATE TABLE IF NOT EXISTS rule_engine_log (
    id SERIAL PRIMARY KEY,
    order_id VARCHAR(66) REFERENCES orders(order_id),
    
    -- Rule evaluation
    rule_name VARCHAR(100) NOT NULL,
    rule_passed BOOLEAN NOT NULL,
    rule_details JSONB,
    
    -- Overall decision
    final_decision VARCHAR(20),  -- APPROVED, ON_HOLD, REJECTED
    
    evaluated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rule_log_order ON rule_engine_log(order_id);

-- ============ CONFIG TABLE ============
-- System configuration
CREATE TABLE IF NOT EXISTS system_config (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Insert default config
INSERT INTO system_config (key, value, description) VALUES
    ('auto_approve_threshold_idr', '10000000', 'Auto-approve orders below this IDR amount (10 juta)'),
    ('platform_fee_percent', '1.0', 'Platform fee percentage (MDR)'),
    ('escrow_contract_address', '', 'Deployed escrow contract address'),
    ('lsk_token_address', '0xac485391EB2d7D88253a7F1eF18C37f4571c1A24', 'LSK token on Lisk Mainnet'),
    ('exchange_wallet', '', 'CEX wallet for LSK conversion'),
    ('settlement_batch_size', '10', 'Max settlements per batch')
ON CONFLICT (key) DO NOTHING;

-- ============ WHITELISTED MERCHANTS ============
CREATE TABLE IF NOT EXISTS whitelisted_merchants (
    id SERIAL PRIMARY KEY,
    merchant_id VARCHAR(100) UNIQUE NOT NULL,
    merchant_name VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Insert demo merchants
INSERT INTO whitelisted_merchants (merchant_id, merchant_name) VALUES
    ('DEMO_MERCHANT_001', 'Toko Andika'),
    ('DEMO_MERCHANT_002', 'Warung Makan Bahagia'),
    ('DEMO_MERCHANT_003', 'Apotek Sehat'),
    ('MERCHANT_QRIS_DEMO', 'QRIS Demo Merchant')
ON CONFLICT (merchant_id) DO NOTHING;

-- ============ PROCESSED EVENTS ============
-- Idempotency tracking for blockchain events
CREATE TABLE IF NOT EXISTS processed_events (
    id SERIAL PRIMARY KEY,
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    order_id VARCHAR(66),
    processed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_processed_events_tx ON processed_events(tx_hash);

-- ============ TRIGGER FOR updated_at ============
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to orders table
DROP TRIGGER IF EXISTS update_orders_updated_at ON orders;
CREATE TRIGGER update_orders_updated_at 
    BEFORE UPDATE ON orders 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
