/**
 * SETTLEMENT BOT SERVICE
 * 
 * ⚠️ SIMULATED FOR HACKATHON - No real fiat transfers
 * 
 * Automatically processes approved orders for fiat settlement.
 * In production, this would integrate with bank APIs, e-wallets, or PSPs.
 * 
 * Flow:
 * 1. Detect orders with status APPROVED
 * 2. Create settlement record
 * 3. Simulate bank transfer (generate mock reference)
 * 4. Mark settlement as COMPLETED
 * 5. Update order status to SETTLED
 * 
 * HACKATHON MVP - All settlements are simulated
 */

import crypto from 'crypto';
import { db } from '../db/database';

export interface SettlementResult {
  settlementId: string;
  orderId: string;
  merchantId: string;
  payoutAmountIdr: number;
  payoutReference: string;
  status: 'COMPLETED' | 'FAILED';
  isSimulated: boolean;
  simulationNote: string;
}

export class SettlementBot {
  private isRunning = false;
  private processInterval: NodeJS.Timeout | null = null;

  // Batch processing config
  private batchSize = 10;

  constructor(
    private processIntervalMs: number = 15000 // 15 seconds
  ) {
    console.log('[SettlementBot] Initialized');
    console.log('  ⚠️ HACKATHON MODE: All settlements are SIMULATED');
  }

  /**
   * Start the settlement bot
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      console.log('[SettlementBot] Already running');
      return;
    }

    // Load config
    await this.loadConfig();

    this.isRunning = true;
    console.log('[SettlementBot] Starting...');
    console.log(`  - Batch size: ${this.batchSize}`);

    // Process immediately, then on interval
    this.processSettlements();
    this.processInterval = setInterval(
      () => this.processSettlements(),
      this.processIntervalMs
    );
  }

  /**
   * Stop the settlement bot
   */
  stop(): void {
    this.isRunning = false;
    if (this.processInterval) {
      clearInterval(this.processInterval);
      this.processInterval = null;
    }
    console.log('[SettlementBot] Stopped');
  }

  /**
   * Load configuration from database
   */
  private async loadConfig(): Promise<void> {
    try {
      const batchSize = await db.getConfig('settlement_batch_size');
      if (batchSize) {
        this.batchSize = parseInt(batchSize);
      }
    } catch (error) {
      console.warn('[SettlementBot] Failed to load config, using defaults:', error);
    }
  }

  /**
   * Process approved orders for settlement
   */
  private async processSettlements(): Promise<void> {
    if (!this.isRunning) return;

    try {
      // Get approved orders ready for settlement
      const orders = await db.getOrdersByStatus(['APPROVED', 'SETTLEMENT_FAILED']);

      if (orders.length === 0) {
        return;
      }

      // Process in batches
      const batch = orders.slice(0, this.batchSize);
      console.log(`[SettlementBot] Processing ${batch.length} settlements`);

      for (const order of batch) {
        await this.settleOrder(order);
      }
    } catch (error) {
      console.error('[SettlementBot] Process error:', error);
    }
  }

  /**
   * Settle a single order (SIMULATED)
   */
  private async settleOrder(order: any): Promise<SettlementResult | null> {
    const orderId = order.order_id;
    const merchantId = order.merchant_id;

    try {
      console.log(`[SettlementBot] Settling order ${orderId}`);

      // Update order status to SETTLING
      await db.updateOrderStatus(orderId, 'SETTLING');

      // Get ledger entry to determine payout amount
      const ledgerEntries = await db.getMerchantLedgerHistory(merchantId, 1);
      const latestEntry = ledgerEntries.find(e => e.order_id === orderId);
      const payoutAmountIdr = latestEntry?.net_idr || parseFloat(order.amount_idr || 0);

      // Generate settlement ID and mock bank reference
      const settlementId = `SETTLE-${crypto.randomUUID().substring(0, 8).toUpperCase()}`;
      const payoutReference = this.generateMockBankReference();

      // Create settlement record
      await db.createSettlement({
        settlement_id: settlementId,
        merchant_id: merchantId,
        order_id: orderId,
        payout_amount_idr: payoutAmountIdr,
        payout_reference: payoutReference,
        status: 'PENDING',
      });

      // Simulate processing delay (like real bank transfer)
      await this.simulateBankTransfer();

      // Update settlement status to COMPLETED
      await db.updateSettlementStatus(settlementId, 'COMPLETED');

      // Update order status to SETTLED
      await db.updateOrderStatus(orderId, 'SETTLED');

      // Update trade status to SETTLED
      const trade = await db.getTradeByOrderId(orderId);
      if (trade) {
        await db.updateTradeStatus(trade.trade_id, 'SETTLED');
      }

      // Create merchant notification for the legacy merchant dashboard
      try {
        // Generate a proper UUID for the notification since orderId is bytes32
        const notificationPaymentId = crypto.randomUUID();
        await db.createMerchantNotification({
          payment_id: notificationPaymentId,
          merchant_name: merchantId,
          amount_idr: payoutAmountIdr,
          payer_wallet: (order.buyer_address || '').toString(),
          tx_hash: (order.escrow_tx_hash || '').toString(),
        });
      } catch (e) {
        console.error('[SettlementBot] Failed to create merchant notification:', e);
      }

      const result: SettlementResult = {
        settlementId,
        orderId,
        merchantId,
        payoutAmountIdr,
        payoutReference,
        status: 'COMPLETED',
        isSimulated: true,
        simulationNote: 'SIMULATED FOR HACKATHON - No real fiat transfer occurred',
      };

      console.log(`[SettlementBot] ✅ Settlement ${settlementId} completed`);
      console.log(`  - Order: ${orderId}`);
      console.log(`  - Merchant: ${merchantId}`);
      console.log(`  - Payout: Rp ${payoutAmountIdr.toLocaleString()}`);
      console.log(`  - Bank Ref: ${payoutReference}`);
      console.log(`  ⚠️ SIMULATED - No real transfer`);

      return result;
    } catch (error) {
      console.error(`[SettlementBot] Error settling order ${orderId}:`, error);

      // Mark as failed
      await db.updateOrderStatus(orderId, 'SETTLEMENT_FAILED');
      return null;
    }
  }

  /**
   * Simulate bank transfer delay
   * In production, this would be actual API calls to bank/PSP
   */
  private async simulateBankTransfer(): Promise<void> {
    // Simulate 1-3 second processing time
    const delay = 1000 + Math.random() * 2000;
    await new Promise(resolve => setTimeout(resolve, delay));
  }

  /**
   * Generate mock bank reference number
   * Format: BANK-YYYYMMDD-XXXXXX
   */
  private generateMockBankReference(): string {
    const date = new Date();
    const dateStr = date.toISOString().slice(0, 10).replace(/-/g, '');
    const randomPart = Math.random().toString(36).substring(2, 8).toUpperCase();
    return `BANK-${dateStr}-${randomPart}`;
  }

  /**
   * Manually trigger settlement for a specific order
   */
  async manualSettle(orderId: string): Promise<SettlementResult | null> {
    const order = await db.getOrder(orderId);

    if (!order) {
      throw new Error('Order not found');
    }

    if (order.status !== 'APPROVED') {
      throw new Error(`Order must be APPROVED status, got: ${order.status}`);
    }

    return this.settleOrder(order);
  }

  /**
   * Get settlement statistics
   */
  async getStats(): Promise<{
    totalSettled: number;
    totalAmountIdr: number;
    pendingCount: number;
  }> {
    try {
      // This would be a proper SQL query in production
      const pendingSettlements = await db.getPendingSettlements(1000);
      
      return {
        totalSettled: 0, // Would query from settlements table
        totalAmountIdr: 0,
        pendingCount: pendingSettlements.length,
      };
    } catch {
      return {
        totalSettled: 0,
        totalAmountIdr: 0,
        pendingCount: 0,
      };
    }
  }
}

// Export singleton
let botInstance: SettlementBot | null = null;

export function getSettlementBot(): SettlementBot | null {
  return botInstance;
}

export function createSettlementBot(): SettlementBot {
  if (botInstance) {
    botInstance.stop();
  }
  botInstance = new SettlementBot();
  return botInstance;
}
