import { Pool } from 'pg';

export interface PaymentIntentRow {
  payment_id: string;
  created_at: Date;
  expires_at: Date;
  payer_wallet_address: string;
  qris_payload: string;
  qris_hash: string;
  merchant_name?: string;
  amount_idr: number;
  lsk_amount_expected: string;
  lsk_amount_expected_wei: string;
  escrow_address: string;
  status: 'CREATED' | 'TX_SUBMITTED' | 'CONFIRMED' | 'PAID' | 'EXPIRED' | 'FAILED';
  tx_hash?: string;
  verified_at?: Date;
  receipt_id?: string;
  ledger_tx_hash?: string;
  updated_at: Date;
}

class Database {
  private pool: Pool;

  constructor() {
    this.pool = new Pool({
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      database: process.env.DB_NAME || 'qris_payments',
      user: process.env.DB_USER || 'qris_user',
      password: process.env.DB_PASSWORD || 'qris_password_dev',
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    });

    this.pool.on('error', (err: Error) => {
      console.error('[Database] Unexpected error on idle client', err);
    });
  }

  async connect(): Promise<void> {
    try {
      const client = await this.pool.connect();
      console.log('[Database] Connected to PostgreSQL');
      client.release();
    } catch (error) {
      console.error('[Database] Failed to connect:', error);
      throw error;
    }
  }

  async createPaymentIntent(data: Omit<PaymentIntentRow, 'created_at' | 'updated_at'>): Promise<PaymentIntentRow> {
    const query = `
      INSERT INTO payment_intents (
        payment_id, expires_at, payer_wallet_address, qris_payload, qris_hash,
        merchant_name, amount_idr, lsk_amount_expected, lsk_amount_expected_wei,
        escrow_address, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING *
    `;
    
    const values = [
      data.payment_id,
      data.expires_at,
      data.payer_wallet_address,
      data.qris_payload,
      data.qris_hash,
      data.merchant_name,
      data.amount_idr,
      data.lsk_amount_expected,
      data.lsk_amount_expected_wei,
      data.escrow_address,
      data.status,
    ];

    const result = await this.pool.query(query, values);
    return result.rows[0];
  }

  async getPaymentIntent(paymentId: string): Promise<PaymentIntentRow | null> {
    const query = 'SELECT * FROM payment_intents WHERE payment_id = $1';
    const result = await this.pool.query(query, [paymentId]);
    return result.rows[0] || null;
  }

  async updatePaymentStatus(
    paymentId: string,
    status: PaymentIntentRow['status'],
    txHash?: string
  ): Promise<PaymentIntentRow | null> {
    const query = `
      UPDATE payment_intents
      SET status = $1, tx_hash = COALESCE($2, tx_hash)
      WHERE payment_id = $3
      RETURNING *
    `;
    const result = await this.pool.query(query, [status, txHash, paymentId]);
    return result.rows[0] || null;
  }

  async markAsPaid(paymentId: string, txHash: string): Promise<PaymentIntentRow | null> {
    const receiptId = `RCP-${paymentId.substring(0, 8).toUpperCase()}`;
    const query = `
      UPDATE payment_intents
      SET status = 'PAID', tx_hash = $1, verified_at = NOW(), receipt_id = $2
      WHERE payment_id = $3
      RETURNING *
    `;
    const result = await this.pool.query(query, [txHash, receiptId, paymentId]);
    return result.rows[0] || null;
  }

  async getPendingPayments(): Promise<PaymentIntentRow[]> {
    const query = `
      SELECT * FROM payment_intents
      WHERE status IN ('CREATED', 'TX_SUBMITTED')
      AND expires_at > NOW()
      ORDER BY created_at ASC
    `;
    const result = await this.pool.query(query);
    return result.rows;
  }

  async close(): Promise<void> {
    await this.pool.end();
    console.log('[Database] Connection pool closed');
  }

  // Transaction History methods
  async createTransactionHistory(data: {
    payment_id: string;
    wallet_address: string;
    merchant_name?: string;
    amount_idr: number;
    lsk_amount: string;
    tx_hash?: string;
    status: string;
  }): Promise<void> {
    const query = `
      INSERT INTO transaction_history 
      (payment_id, wallet_address, merchant_name, amount_idr, lsk_amount, tx_hash, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
    `;
    await this.pool.query(query, [
      data.payment_id,
      data.wallet_address,
      data.merchant_name,
      data.amount_idr,
      data.lsk_amount,
      data.tx_hash,
      data.status,
    ]);
  }

  async getTransactionHistory(walletAddress: string, limit: number = 50): Promise<any[]> {
    const query = `
      SELECT * FROM transaction_history 
      WHERE wallet_address = $1 
      ORDER BY created_at DESC 
      LIMIT $2
    `;
    const result = await this.pool.query(query, [walletAddress.toLowerCase(), limit]);
    return result.rows;
  }

  async updateTransactionStatus(paymentId: string, status: string, txHash?: string): Promise<void> {
    const query = `
      UPDATE transaction_history 
      SET status = $1, tx_hash = COALESCE($2, tx_hash)
      WHERE payment_id = $3
    `;
    await this.pool.query(query, [status, txHash, paymentId]);
  }

  // Merchant Notification methods
  async createMerchantNotification(data: {
    payment_id: string;
    merchant_name: string;
    merchant_city?: string;
    amount_idr: number;
    payer_wallet: string;
    tx_hash?: string;
  }): Promise<void> {
    const query = `
      INSERT INTO merchant_notifications 
      (payment_id, merchant_name, merchant_city, amount_idr, payer_wallet, tx_hash)
      VALUES ($1, $2, $3, $4, $5, $6)
    `;
    await this.pool.query(query, [
      data.payment_id,
      data.merchant_name,
      data.merchant_city,
      data.amount_idr,
      data.payer_wallet,
      data.tx_hash,
    ]);
  }

  async getMerchantNotifications(limit: number = 100): Promise<any[]> {
    const query = `
      SELECT * FROM merchant_notifications 
      ORDER BY notified_at DESC 
      LIMIT $1
    `;
    const result = await this.pool.query(query, [limit]);
    return result.rows;
  }

  async getMerchantNotificationsByName(merchantName: string, limit: number = 50): Promise<any[]> {
    const query = `
      SELECT * FROM merchant_notifications 
      WHERE merchant_name ILIKE $1
      ORDER BY notified_at DESC 
      LIMIT $2
    `;
    const result = await this.pool.query(query, [`%${merchantName}%`, limit]);
    return result.rows;
  }

  // ============ ORDERS (v2) ============

  async createOrder(data: {
    order_id: string;
    merchant_id: string;
    buyer_address: string;
    amount_lsk_wei: string;
    amount_lsk: number;
    escrow_tx_hash?: string;
    block_number?: number;
    locked_at?: Date;
    expires_at?: Date;
    status: string;
  }): Promise<any> {
    const query = `
      INSERT INTO orders (
        order_id, merchant_id, buyer_address, amount_lsk_wei, amount_lsk,
        escrow_tx_hash, block_number, locked_at, expires_at, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      ON CONFLICT (order_id) DO UPDATE SET
        status = $10,
        escrow_tx_hash = COALESCE($6, orders.escrow_tx_hash),
        block_number = COALESCE($7, orders.block_number),
        locked_at = COALESCE($8, orders.locked_at)
      RETURNING *
    `;
    const result = await this.pool.query(query, [
      data.order_id,
      data.merchant_id,
      data.buyer_address,
      data.amount_lsk_wei,
      data.amount_lsk,
      data.escrow_tx_hash,
      data.block_number,
      data.locked_at,
      data.expires_at,
      data.status,
    ]);
    return result.rows[0];
  }

  async getOrder(orderId: string): Promise<any | null> {
    const result = await this.pool.query(
      'SELECT * FROM orders WHERE order_id = $1',
      [orderId]
    );
    return result.rows[0] || null;
  }

  async updateOrderStatus(orderId: string, status: string, extraData?: Record<string, any>): Promise<any | null> {
    let query = 'UPDATE orders SET status = $1';
    const values: any[] = [status];
    let paramIndex = 2;

    if (extraData) {
      for (const [key, value] of Object.entries(extraData)) {
        query += `, ${key} = $${paramIndex}`;
        values.push(value);
        paramIndex++;
      }
    }

    query += ` WHERE order_id = $${paramIndex} RETURNING *`;
    values.push(orderId);

    const result = await this.pool.query(query, values);
    return result.rows[0] || null;
  }

  async getOrdersByStatus(status: string | string[]): Promise<any[]> {
    const statuses = Array.isArray(status) ? status : [status];
    const placeholders = statuses.map((_, i) => `$${i + 1}`).join(', ');
    const query = `SELECT * FROM orders WHERE status IN (${placeholders}) ORDER BY created_at ASC`;
    const result = await this.pool.query(query, statuses);
    return result.rows;
  }

  // ============ TRADES ============

  async createTrade(data: {
    order_id: string;
    trade_id: string;
    exchange: string;
    sell_amount_lsk: number;
    received_idr: number;
    exchange_rate: number;
    exchange_fee_idr?: number;
    status: string;
  }): Promise<any> {
    const query = `
      INSERT INTO trades (
        order_id, trade_id, exchange, sell_amount_lsk, received_idr,
        exchange_rate, exchange_fee_idr, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING *
    `;
    const result = await this.pool.query(query, [
      data.order_id,
      data.trade_id,
      data.exchange,
      data.sell_amount_lsk,
      data.received_idr,
      data.exchange_rate,
      data.exchange_fee_idr || 0,
      data.status,
    ]);
    return result.rows[0];
  }

  async updateTradeStatus(tradeId: string, status: string): Promise<any | null> {
    const query = `
      UPDATE trades SET status = $1::character varying, executed_at = CASE WHEN $1::character varying = 'EXECUTED'::character varying THEN NOW() ELSE executed_at END
      WHERE trade_id = $2 RETURNING *
    `;
    const result = await this.pool.query(query, [status, tradeId]);
    return result.rows[0] || null;
  }

  async getTradeByOrderId(orderId: string): Promise<any | null> {
    const result = await this.pool.query(
      'SELECT * FROM trades WHERE order_id = $1',
      [orderId]
    );
    return result.rows[0] || null;
  }

  // ============ LEDGER ============

  async createLedgerEntry(data: {
    merchant_id: string;
    order_id: string;
    gross_idr: number;
    platform_fee_idr: number;
    net_idr: number;
    fee_rate_percent: number;
    description?: string;
  }): Promise<any> {
    const query = `
      INSERT INTO merchant_ledger (
        merchant_id, order_id, gross_idr, platform_fee_idr, net_idr,
        fee_rate_percent, description
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *
    `;
    const result = await this.pool.query(query, [
      data.merchant_id,
      data.order_id,
      data.gross_idr,
      data.platform_fee_idr,
      data.net_idr,
      data.fee_rate_percent,
      data.description,
    ]);
    return result.rows[0];
  }

  async getMerchantBalance(merchantId: string): Promise<{ total_gross: number; total_fees: number; total_net: number }> {
    const query = `
      SELECT 
        COALESCE(SUM(gross_idr), 0) as total_gross,
        COALESCE(SUM(platform_fee_idr), 0) as total_fees,
        COALESCE(SUM(net_idr), 0) as total_net
      FROM merchant_ledger WHERE merchant_id = $1
    `;
    const result = await this.pool.query(query, [merchantId]);
    return result.rows[0];
  }

  async getMerchantLedgerHistory(merchantId: string, limit: number = 50): Promise<any[]> {
    const query = `
      SELECT * FROM merchant_ledger 
      WHERE merchant_id = $1 
      ORDER BY created_at DESC 
      LIMIT $2
    `;
    const result = await this.pool.query(query, [merchantId, limit]);
    return result.rows;
  }

  // ============ SETTLEMENTS ============

  async createSettlement(data: {
    settlement_id: string;
    merchant_id: string;
    order_id: string;
    payout_amount_idr: number;
    payout_reference?: string;
    status: string;
  }): Promise<any> {
    const query = `
      INSERT INTO settlements (
        settlement_id, merchant_id, order_id, payout_amount_idr,
        payout_reference, status, is_simulated, simulation_note
      ) VALUES ($1, $2, $3, $4, $5, $6, TRUE, 'SIMULATED FOR HACKATHON - No real fiat transfer')
      RETURNING *
    `;
    const result = await this.pool.query(query, [
      data.settlement_id,
      data.merchant_id,
      data.order_id,
      data.payout_amount_idr,
      data.payout_reference,
      data.status,
    ]);
    return result.rows[0];
  }

  async updateSettlementStatus(settlementId: string, status: string): Promise<any | null> {
    const query = `
      UPDATE settlements 
      SET status = $1::character varying, 
          processed_at = CASE WHEN $1::character varying = 'PROCESSING'::character varying THEN NOW() ELSE processed_at END,
          completed_at = CASE WHEN $1::character varying = 'COMPLETED'::character varying THEN NOW() ELSE completed_at END
      WHERE settlement_id = $2 
      RETURNING *
    `;
    const result = await this.pool.query(query, [status, settlementId]);
    return result.rows[0] || null;
  }

  async getPendingSettlements(limit: number = 10): Promise<any[]> {
    const query = `
      SELECT * FROM settlements 
      WHERE status = 'PENDING' 
      ORDER BY created_at ASC 
      LIMIT $1
    `;
    const result = await this.pool.query(query, [limit]);
    return result.rows;
  }

  // ============ RULE ENGINE LOG ============

  async logRuleEvaluation(data: {
    order_id: string;
    rule_name: string;
    rule_passed: boolean;
    rule_details?: Record<string, any>;
    final_decision?: string;
  }): Promise<void> {
    const query = `
      INSERT INTO rule_engine_log (order_id, rule_name, rule_passed, rule_details, final_decision)
      VALUES ($1, $2, $3, $4, $5)
    `;
    await this.pool.query(query, [
      data.order_id,
      data.rule_name,
      data.rule_passed,
      JSON.stringify(data.rule_details || {}),
      data.final_decision,
    ]);
  }

  // ============ CONFIG ============

  async getConfig(key: string): Promise<string | null> {
    const result = await this.pool.query(
      'SELECT value FROM system_config WHERE key = $1',
      [key]
    );
    return result.rows[0]?.value || null;
  }

  async setConfig(key: string, value: string): Promise<void> {
    await this.pool.query(
      `INSERT INTO system_config (key, value) VALUES ($1, $2)
       ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = NOW()`,
      [key, value]
    );
  }

  // ============ WHITELISTED MERCHANTS ============

  async isMerchantWhitelisted(merchantId: string): Promise<boolean> {
    const result = await this.pool.query(
      'SELECT 1 FROM whitelisted_merchants WHERE merchant_id = $1 AND is_active = TRUE',
      [merchantId]
    );
    return result.rows.length > 0;
  }

  // ============ PROCESSED EVENTS (Idempotency) ============

  async isEventProcessed(txHash: string, logIndex: number): Promise<boolean> {
    const result = await this.pool.query(
      'SELECT 1 FROM processed_events WHERE tx_hash = $1 AND log_index = $2',
      [txHash, logIndex]
    );
    return result.rows.length > 0;
  }

  async markEventProcessed(txHash: string, logIndex: number, eventName: string, orderId?: string): Promise<void> {
    await this.pool.query(
      `INSERT INTO processed_events (tx_hash, log_index, event_name, order_id)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (tx_hash, log_index) DO NOTHING`,
      [txHash, logIndex, eventName, orderId]
    );
  }
}

export const db = new Database();
