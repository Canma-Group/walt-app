/**
 * CONVERSION ENGINE SERVICE
 * 
 * Handles LSK -> IDR conversion after payment is confirmed.
 * For hackathon, this MOCKS the CEX API integration.
 * 
 * Flow:
 * 1. Detect orders with status LOCKED/PAID
 * 2. Fetch current LSK/IDR rate from Indodax
 * 3. Simulate market sell order
 * 4. Record trade and update order status to CONVERTED
 * 
 * HACKATHON MVP - Simulated CEX Integration
 */

import crypto from 'crypto';
import { db } from '../db/database';

export interface ConversionResult {
  tradeId: string;
  orderId: string;
  sellAmountLsk: number;
  receivedIdr: number;
  exchangeRate: number;
  exchangeFeeIdr: number;
  exchange: string;
}

export class ConversionEngine {
  private isRunning = false;
  private processInterval: NodeJS.Timeout | null = null;
  
  // Mock exchange configuration
  private readonly EXCHANGE_NAME = 'INDODAX_MOCK';
  private readonly EXCHANGE_FEE_PERCENT = 0.3; // 0.3% trading fee
  
  // Fallback LSK price if API fails
  private readonly FALLBACK_LSK_PRICE_IDR = 3400;

  constructor(
    private processIntervalMs: number = 10000 // 10 seconds
  ) {
    console.log('[ConversionEngine] Initialized');
  }

  /**
   * Start the conversion engine
   */
  start(): void {
    if (this.isRunning) {
      console.log('[ConversionEngine] Already running');
      return;
    }

    this.isRunning = true;
    console.log('[ConversionEngine] Starting...');

    // Process immediately, then on interval
    this.processConversions();
    this.processInterval = setInterval(
      () => this.processConversions(),
      this.processIntervalMs
    );
  }

  /**
   * Stop the conversion engine
   */
  stop(): void {
    this.isRunning = false;
    if (this.processInterval) {
      clearInterval(this.processInterval);
      this.processInterval = null;
    }
    console.log('[ConversionEngine] Stopped');
  }

  /**
   * Process pending conversions
   */
  private async processConversions(): Promise<void> {
    if (!this.isRunning) return;

    try {
      // Get orders ready for conversion
      // EscrowEventListener writes status = LOCKED when PaymentCreated is detected.
      // Conversion should therefore process both LOCKED and PAID.
      const orders = await db.getOrdersByStatus(['LOCKED', 'PAID']);
      
      if (orders.length === 0) {
        return;
      }

      console.log(`[ConversionEngine] Processing ${orders.length} orders for conversion`);

      for (const order of orders) {
        await this.convertOrder(order);
      }
    } catch (error) {
      console.error('[ConversionEngine] Process error:', error);
    }
  }

  /**
   * Convert a single order from LSK to IDR
   */
  private async convertOrder(order: any): Promise<ConversionResult | null> {
    const orderId = order.order_id;
    
    try {
      console.log(`[ConversionEngine] Converting order ${orderId}`);
      console.log(`  - LSK Amount: ${order.amount_lsk}`);

      // Update status to CONVERTING
      await db.updateOrderStatus(orderId, 'CONVERTING');

      // Get current LSK price
      const lskPriceIdr = await this.getLskPriceIdr();
      console.log(`  - LSK Price: Rp ${lskPriceIdr}`);

      // Calculate conversion
      const sellAmountLsk = parseFloat(order.amount_lsk);
      const grossIdr = sellAmountLsk * lskPriceIdr;
      const exchangeFeeIdr = grossIdr * (this.EXCHANGE_FEE_PERCENT / 100);
      const receivedIdr = grossIdr - exchangeFeeIdr;

      // Generate mock trade ID
      const tradeId = `TRADE-${crypto.randomUUID().substring(0, 8).toUpperCase()}`;

      // Record trade in database
      await db.createTrade({
        order_id: orderId,
        trade_id: tradeId,
        exchange: this.EXCHANGE_NAME,
        sell_amount_lsk: sellAmountLsk,
        received_idr: receivedIdr,
        exchange_rate: lskPriceIdr,
        exchange_fee_idr: exchangeFeeIdr,
        status: 'EXECUTED',
      });

      // Update order with IDR amount and status
      await db.updateOrderStatus(orderId, 'CONVERTED', {
        amount_idr: receivedIdr,
      });

      const result: ConversionResult = {
        tradeId,
        orderId,
        sellAmountLsk,
        receivedIdr,
        exchangeRate: lskPriceIdr,
        exchangeFeeIdr,
        exchange: this.EXCHANGE_NAME,
      };

      console.log(`[ConversionEngine] Order ${orderId} converted successfully`);
      console.log(`  - Trade ID: ${tradeId}`);
      console.log(`  - Received: Rp ${receivedIdr.toFixed(2)}`);
      console.log(`  - Exchange Fee: Rp ${exchangeFeeIdr.toFixed(2)}`);

      return result;
    } catch (error) {
      console.error(`[ConversionEngine] Error converting order ${orderId}:`, error);
      
      // Mark as failed
      await db.updateOrderStatus(orderId, 'CONVERSION_FAILED');
      return null;
    }
  }

  /**
   * Get current LSK price in IDR
   * Uses Indodax public API, falls back to cached/default price
   */
  private async getLskPriceIdr(): Promise<number> {
    try {
      const response = await fetch('https://indodax.com/api/ticker/lskidr');
      
      if (response.ok) {
        const data = await response.json();
        const price = parseFloat(data.ticker?.last || '0');
        
        if (price > 0) {
          return price;
        }
      }
    } catch (error) {
      console.warn('[ConversionEngine] Failed to fetch LSK price from Indodax:', error);
    }

    // Use fallback price
    console.log(`[ConversionEngine] Using fallback LSK price: Rp ${this.FALLBACK_LSK_PRICE_IDR}`);
    return this.FALLBACK_LSK_PRICE_IDR;
  }

  /**
   * Manually trigger conversion for a specific order (for testing)
   */
  async manualConvert(orderId: string): Promise<ConversionResult | null> {
    const order = await db.getOrder(orderId);
    
    if (!order) {
      throw new Error('Order not found');
    }

    if (order.status !== 'PAID' && order.status !== 'LOCKED') {
      throw new Error(`Order status must be PAID or LOCKED, got: ${order.status}`);
    }

    return this.convertOrder(order);
  }
}

// Export singleton
let engineInstance: ConversionEngine | null = null;

export function getConversionEngine(): ConversionEngine | null {
  return engineInstance;
}

export function createConversionEngine(): ConversionEngine {
  if (engineInstance) {
    engineInstance.stop();
  }
  engineInstance = new ConversionEngine();
  return engineInstance;
}
