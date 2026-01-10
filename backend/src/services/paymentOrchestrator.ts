/**
 * PAYMENT ORCHESTRATOR SERVICE
 * 
 * Central coordinator for the crypto-to-fiat payment flow.
 * Ties together all services and provides high-level API.
 * 
 * Flow:
 * 1. Create Payment Intent (for Flutter app)
 * 2. Listen for blockchain events (EscrowEventListener)
 * 3. Convert LSK to IDR (ConversionEngine)
 * 4. Apply rules and approve (RuleEngine)
 * 5. Settle to merchant (SettlementBot)
 * 
 * HACKATHON MVP - End-to-end payment processing
 */

import { ethers } from 'ethers';
import crypto from 'crypto';
import { db } from '../db/database';
import { EscrowEventListener, createEscrowListener } from './escrowEventListener';
import { ConversionEngine, createConversionEngine } from './conversionEngine';
import { RuleEngine, createRuleEngine } from './ruleEngine';
import { SettlementBot, createSettlementBot } from './settlementBot';

export interface CreatePaymentRequest {
  walletAddress: string;
  qrisPayload: string;
  amountIdr: number;
  merchantId?: string;
}

export interface PaymentIntentResponse {
  paymentId: string;
  orderId: string; // bytes32 for smart contract
  escrowAddress: string;
  amountIdr: number;
  lskAmountExpected: string;
  lskTokenAddress: string;
  chainId: number;
  expiresAt: Date;
  merchantName?: string;
}

export interface PaymentStatus {
  paymentId: string;
  orderId: string;
  status: string;
  amountIdr: number;
  amountLsk: string;
  merchantId: string;
  merchantName?: string;
  escrowTxHash?: string;
  tradeId?: string;
  settlementId?: string;
  payoutReference?: string;
  isSimulated: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export class PaymentOrchestrator {
  private escrowListener: EscrowEventListener | null = null;
  private conversionEngine: ConversionEngine | null = null;
  private ruleEngine: RuleEngine | null = null;
  private settlementBot: SettlementBot | null = null;

  // Configuration - Lisk Sepolia Testnet
  private readonly LSK_TOKEN_ADDRESS = process.env.LSK_TOKEN_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';
  private readonly CHAIN_ID = parseInt(process.env.CHAIN_ID || '4202'); // Lisk Sepolia
  private readonly LISK_RPC = process.env.LISK_RPC_URL || 'https://rpc.sepolia-api.lisk.com';
  private escrowContractAddress = process.env.QRIS_ESCROW_V2_ADDRESS || '';

  constructor() {
    console.log('[PaymentOrchestrator] Initialized');
  }

  /**
   * Initialize all services
   */
  async initialize(escrowAddress?: string): Promise<void> {
    console.log('[PaymentOrchestrator] Initializing services...');

    // Load escrow address from config or parameter
    if (escrowAddress) {
      this.escrowContractAddress = escrowAddress;
    } else {
      const configAddress = await db.getConfig('escrow_contract_address');
      if (configAddress) {
        this.escrowContractAddress = configAddress;
      }
    }

    // Initialize services
    if (this.escrowContractAddress) {
      this.escrowListener = createEscrowListener(this.LISK_RPC, this.escrowContractAddress);
      console.log(`[PaymentOrchestrator] Escrow listener ready for ${this.escrowContractAddress}`);
    } else {
      console.warn('[PaymentOrchestrator] No escrow contract address configured');
    }

    this.conversionEngine = createConversionEngine();
    this.ruleEngine = createRuleEngine();
    this.settlementBot = createSettlementBot();

    console.log('[PaymentOrchestrator] All services initialized');
  }

  /**
   * Start all automated services
   */
  async start(): Promise<void> {
    console.log('[PaymentOrchestrator] Starting all services...');

    if (this.escrowListener) {
      await this.escrowListener.start();
    }

    this.conversionEngine?.start();
    await this.ruleEngine?.start();
    await this.settlementBot?.start();

    console.log('[PaymentOrchestrator] All services running');
  }

  /**
   * Stop all services
   */
  stop(): void {
    console.log('[PaymentOrchestrator] Stopping all services...');

    this.escrowListener?.stop();
    this.conversionEngine?.stop();
    this.ruleEngine?.stop();
    this.settlementBot?.stop();

    console.log('[PaymentOrchestrator] All services stopped');
  }

  /**
   * Create a new payment intent
   * Called by Flutter app when user scans QRIS
   */
  async createPaymentIntent(req: CreatePaymentRequest, lskPriceIdr: number): Promise<PaymentIntentResponse> {
    // Generate unique payment ID
    const paymentId = crypto.randomUUID();
    
    // Convert to bytes32 for smart contract
    const orderId = ethers.keccak256(ethers.toUtf8Bytes(paymentId));

    // Parse merchant info from QRIS
    const merchantName = this.parseMerchantName(req.qrisPayload);
    const merchantId = req.merchantId || this.extractMerchantId(req.qrisPayload) || 'QRIS_MERCHANT';

    // Calculate LSK amount
    const lskAmountExpected = req.amountIdr / lskPriceIdr;
    const lskAmountWei = ethers.parseUnits(lskAmountExpected.toFixed(8), 18);

    // Expiration time (10 minutes)
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    // Create order in database
    await db.createOrder({
      order_id: orderId,
      merchant_id: merchantId,
      buyer_address: req.walletAddress.toLowerCase(),
      amount_lsk_wei: lskAmountWei.toString(),
      amount_lsk: lskAmountExpected,
      expires_at: expiresAt,
      status: 'PENDING',
    });

    console.log(`[PaymentOrchestrator] Payment intent created: ${paymentId}`);
    console.log(`  - Order ID: ${orderId.substring(0, 18)}...`);
    console.log(`  - Amount: Rp ${req.amountIdr} = ${lskAmountExpected.toFixed(4)} LSK`);
    console.log(`  - Merchant: ${merchantName || merchantId}`);

    return {
      paymentId,
      orderId,
      escrowAddress: this.escrowContractAddress,
      amountIdr: req.amountIdr,
      lskAmountExpected: lskAmountExpected.toFixed(8),
      lskTokenAddress: this.LSK_TOKEN_ADDRESS,
      chainId: this.CHAIN_ID,
      expiresAt,
      merchantName,
    };
  }

  /**
   * Submit transaction hash after user pays
   */
  async submitTransaction(orderId: string, txHash: string): Promise<PaymentStatus> {
    const order = await db.getOrder(orderId);
    if (!order) {
      throw new Error('Order not found');
    }

    // Update order with tx hash
    await db.updateOrderStatus(orderId, 'TX_SUBMITTED', {
      escrow_tx_hash: txHash,
    });

    // Simulate immediate status update to PAID for demo
    // In production, this would be verified by the event listener
    setTimeout(async () => {
      try {
        await db.updateOrderStatus(orderId, 'PAID');
        console.log(`[PaymentOrchestrator] Order ${orderId.substring(0, 18)}... marked as PAID`);
      } catch (e) {
        console.error('Error updating order to PAID:', e);
      }
    }, 3000); // 3 second delay to simulate blockchain confirmation

    return this.getPaymentStatus(orderId);
  }

  /**
   * Get payment status
   */
  async getPaymentStatus(orderId: string): Promise<PaymentStatus> {
    const order = await db.getOrder(orderId);
    if (!order) {
      throw new Error('Order not found');
    }

    // Get related trade and settlement
    const trade = await db.getTradeByOrderId(orderId);
    
    return {
      paymentId: orderId, // Using orderId as paymentId for simplicity
      orderId,
      status: order.status,
      amountIdr: parseFloat(order.amount_idr || 0),
      amountLsk: order.amount_lsk?.toString() || '0',
      merchantId: order.merchant_id,
      merchantName: order.merchant_name,
      escrowTxHash: order.escrow_tx_hash,
      tradeId: trade?.trade_id,
      settlementId: undefined, // Would fetch from settlements table
      payoutReference: undefined,
      isSimulated: true, // Always true for hackathon
      createdAt: order.created_at,
      updatedAt: order.updated_at,
    };
  }

  /**
   * Get all orders for a wallet
   */
  async getOrdersByWallet(walletAddress: string): Promise<any[]> {
    // Query orders from database by buyer address
    const orders = await db.getOrdersByStatus(['PENDING', 'LOCKED', 'PAID', 'CONVERTED', 'APPROVED', 'SETTLED']);
    return orders.filter(o => o.buyer_address === walletAddress.toLowerCase());
  }

  /**
   * Get merchant dashboard data
   */
  async getMerchantDashboard(merchantId: string): Promise<{
    balance: { gross: number; fees: number; net: number };
    recentTransactions: any[];
    pendingSettlements: number;
  }> {
    const balance = await db.getMerchantBalance(merchantId);
    const transactions = await db.getMerchantLedgerHistory(merchantId, 10);

    return {
      balance: {
        gross: parseFloat(balance.total_gross?.toString() || '0'),
        fees: parseFloat(balance.total_fees?.toString() || '0'),
        net: parseFloat(balance.total_net?.toString() || '0'),
      },
      recentTransactions: transactions,
      pendingSettlements: 0, // Would count from settlements table
    };
  }

  /**
   * Manual trigger for demo: process an order through the entire flow
   */
  async demoProcessOrder(orderId: string): Promise<void> {
    console.log(`[PaymentOrchestrator] Demo processing order ${orderId.substring(0, 18)}...`);

    // Simulate the entire flow
    const order = await db.getOrder(orderId);
    if (!order) {
      throw new Error('Order not found');
    }

    // Step 1: Mark as PAID (simulating blockchain confirmation)
    if (order.status === 'PENDING' || order.status === 'TX_SUBMITTED') {
      await db.updateOrderStatus(orderId, 'PAID');
      console.log('  -> PAID');
    }

    // Step 2: Convert (handled by ConversionEngine but we can trigger manually)
    if (this.conversionEngine) {
      await (this.conversionEngine as any).manualConvert?.(orderId);
      console.log('  -> CONVERTED');
    }

    // Step 3: Approve (handled by RuleEngine)
    const updatedOrder = await db.getOrder(orderId);
    if (updatedOrder && this.ruleEngine) {
      await this.ruleEngine.evaluateOrder(updatedOrder);
      console.log('  -> APPROVED');
    }

    // Step 4: Settle (handled by SettlementBot)
    if (this.settlementBot) {
      await (this.settlementBot as any).manualSettle?.(orderId);
      console.log('  -> SETTLED');
    }

    console.log(`[PaymentOrchestrator] Demo processing complete for ${orderId.substring(0, 18)}...`);
  }

  /**
   * Parse merchant name from QRIS payload
   */
  private parseMerchantName(qrisPayload: string): string | undefined {
    try {
      // Tag 59 is merchant name in QRIS
      const tag59Match = qrisPayload.match(/59(\d{2})([^\d]{2,})/);
      if (tag59Match) {
        const length = parseInt(tag59Match[1]);
        return tag59Match[2].substring(0, length);
      }
    } catch (e) {
      console.error('Error parsing merchant name:', e);
    }
    return undefined;
  }

  /**
   * Extract merchant ID from QRIS payload
   */
  private extractMerchantId(qrisPayload: string): string | undefined {
    try {
      // Tag 26-51 contain merchant account info
      const merchantMatch = qrisPayload.match(/26(\d{2})(.+?)(?=\d{2}[A-Z]|$)/);
      if (merchantMatch) {
        return `QRIS_${merchantMatch[2].substring(0, 10)}`;
      }
    } catch (e) {
      console.error('Error extracting merchant ID:', e);
    }
    return undefined;
  }
}

// Export singleton
let orchestratorInstance: PaymentOrchestrator | null = null;

export function getPaymentOrchestrator(): PaymentOrchestrator | null {
  return orchestratorInstance;
}

export function createPaymentOrchestrator(): PaymentOrchestrator {
  if (!orchestratorInstance) {
    orchestratorInstance = new PaymentOrchestrator();
  }
  return orchestratorInstance;
}
