/**
 * RULE ENGINE SERVICE
 * 
 * Implements rule-based auto-approval for converted orders.
 * No human interaction required - fully automated.
 * 
 * Rules:
 * 1. Amount threshold - auto-approve if receivedIDR <= configurable threshold
 * 2. Merchant whitelist - auto-approve if merchantId is whitelisted
 * 3. Duplicate check - reject if orderId already processed
 * 
 * If all rules pass -> APPROVED (moves to settlement queue)
 * If any rule fails -> ON_HOLD (requires manual review)
 * 
 * HACKATHON MVP - Automated approval system
 */

import { db } from '../db/database';

export interface RuleEvaluationResult {
  orderId: string;
  decision: 'APPROVED' | 'ON_HOLD' | 'REJECTED';
  rules: {
    name: string;
    passed: boolean;
    details: Record<string, any>;
  }[];
  reason?: string;
}

export class RuleEngine {
  private isRunning = false;
  private processInterval: NodeJS.Timeout | null = null;

  // Default thresholds (can be overridden from config)
  private autoApproveThresholdIdr = 10000000; // 10 juta IDR
  private platformFeePercent = 1.0; // 1% MDR

  constructor(
    private processIntervalMs: number = 10000 // 10 seconds
  ) {
    console.log('[RuleEngine] Initialized');
  }

  /**
   * Start the rule engine
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      console.log('[RuleEngine] Already running');
      return;
    }

    // Load config from database
    await this.loadConfig();

    this.isRunning = true;
    console.log('[RuleEngine] Starting...');
    console.log(`  - Auto-approve threshold: Rp ${this.autoApproveThresholdIdr.toLocaleString()}`);
    console.log(`  - Platform fee: ${this.platformFeePercent}%`);

    // Process immediately, then on interval
    this.processOrders();
    this.processInterval = setInterval(
      () => this.processOrders(),
      this.processIntervalMs
    );
  }

  /**
   * Stop the rule engine
   */
  stop(): void {
    this.isRunning = false;
    if (this.processInterval) {
      clearInterval(this.processInterval);
      this.processInterval = null;
    }
    console.log('[RuleEngine] Stopped');
  }

  /**
   * Load configuration from database
   */
  private async loadConfig(): Promise<void> {
    try {
      const threshold = await db.getConfig('auto_approve_threshold_idr');
      if (threshold) {
        this.autoApproveThresholdIdr = parseFloat(threshold);
      }

      const feePercent = await db.getConfig('platform_fee_percent');
      if (feePercent) {
        this.platformFeePercent = parseFloat(feePercent);
      }
    } catch (error) {
      console.warn('[RuleEngine] Failed to load config, using defaults:', error);
    }
  }

  /**
   * Process converted orders through rules
   */
  private async processOrders(): Promise<void> {
    if (!this.isRunning) return;

    try {
      // Get orders ready for approval (status = CONVERTED)
      const orders = await db.getOrdersByStatus('CONVERTED');

      if (orders.length === 0) {
        return;
      }

      console.log(`[RuleEngine] Evaluating ${orders.length} orders`);

      for (const order of orders) {
        await this.evaluateOrder(order);
      }
    } catch (error) {
      console.error('[RuleEngine] Process error:', error);
    }
  }

  /**
   * Evaluate a single order against all rules
   */
  async evaluateOrder(order: any): Promise<RuleEvaluationResult> {
    const orderId = order.order_id;
    const amountIdr = parseFloat(order.amount_idr || 0);
    const merchantId = order.merchant_id;

    console.log(`[RuleEngine] Evaluating order ${orderId}`);

    const rules: RuleEvaluationResult['rules'] = [];
    let allPassed = true;

    // Rule 1: Amount Threshold
    const thresholdPassed = amountIdr <= this.autoApproveThresholdIdr;
    rules.push({
      name: 'AMOUNT_THRESHOLD',
      passed: thresholdPassed,
      details: {
        amountIdr,
        threshold: this.autoApproveThresholdIdr,
        reason: thresholdPassed 
          ? 'Amount within auto-approve limit'
          : 'Amount exceeds auto-approve limit',
      },
    });
    if (!thresholdPassed) allPassed = false;

    // Log rule evaluation
    await db.logRuleEvaluation({
      order_id: orderId,
      rule_name: 'AMOUNT_THRESHOLD',
      rule_passed: thresholdPassed,
      rule_details: rules[rules.length - 1].details,
    });

    // Rule 2: Merchant Whitelist
    const isWhitelisted = await db.isMerchantWhitelisted(merchantId);
    // For hackathon, we auto-approve even non-whitelisted merchants if amount is small
    const whitelistPassed = isWhitelisted || amountIdr <= 1000000; // 1 juta
    rules.push({
      name: 'MERCHANT_WHITELIST',
      passed: whitelistPassed,
      details: {
        merchantId,
        isWhitelisted,
        reason: isWhitelisted 
          ? 'Merchant is whitelisted'
          : whitelistPassed 
            ? 'Small amount - auto-approved'
            : 'Merchant not whitelisted and large amount',
      },
    });
    if (!whitelistPassed) allPassed = false;

    // Log rule evaluation
    await db.logRuleEvaluation({
      order_id: orderId,
      rule_name: 'MERCHANT_WHITELIST',
      rule_passed: whitelistPassed,
      rule_details: rules[rules.length - 1].details,
    });

    // Rule 3: Duplicate Check (order not already settled)
    const existingSettlement = await this.checkDuplicateSettlement(orderId);
    const noDuplicate = !existingSettlement;
    rules.push({
      name: 'DUPLICATE_CHECK',
      passed: noDuplicate,
      details: {
        orderId,
        hasDuplicate: existingSettlement,
        reason: noDuplicate 
          ? 'No duplicate settlement found'
          : 'Order already has a settlement',
      },
    });
    if (!noDuplicate) allPassed = false;

    // Log rule evaluation
    await db.logRuleEvaluation({
      order_id: orderId,
      rule_name: 'DUPLICATE_CHECK',
      rule_passed: noDuplicate,
      rule_details: rules[rules.length - 1].details,
    });

    // Determine final decision
    const decision: RuleEvaluationResult['decision'] = allPassed ? 'APPROVED' : 'ON_HOLD';

    // Log final decision
    await db.logRuleEvaluation({
      order_id: orderId,
      rule_name: 'FINAL_DECISION',
      rule_passed: allPassed,
      rule_details: { rules: rules.map(r => ({ name: r.name, passed: r.passed })) },
      final_decision: decision,
    });

    // Update order status
    await db.updateOrderStatus(orderId, decision);

    // If approved, create ledger entry and queue for settlement
    if (decision === 'APPROVED') {
      await this.createLedgerEntry(order);
    }

    const result: RuleEvaluationResult = {
      orderId,
      decision,
      rules,
      reason: allPassed ? 'All rules passed' : 'One or more rules failed',
    };

    console.log(`[RuleEngine] Order ${orderId} -> ${decision}`);

    return result;
  }

  /**
   * Check if order already has a settlement
   */
  private async checkDuplicateSettlement(orderId: string): Promise<boolean> {
    try {
      const trade = await db.getTradeByOrderId(orderId);
      // If trade exists and is settled, it's a duplicate
      return trade?.status === 'SETTLED';
    } catch {
      return false;
    }
  }

  /**
   * Create ledger entry for approved order
   */
  private async createLedgerEntry(order: any): Promise<void> {
    const grossIdr = parseFloat(order.amount_idr || 0);
    const platformFeeIdr = grossIdr * (this.platformFeePercent / 100);
    const netIdr = grossIdr - platformFeeIdr;

    await db.createLedgerEntry({
      merchant_id: order.merchant_id,
      order_id: order.order_id,
      gross_idr: grossIdr,
      platform_fee_idr: platformFeeIdr,
      net_idr: netIdr,
      fee_rate_percent: this.platformFeePercent,
      description: `QRIS Payment - Order ${order.order_id.substring(0, 8)}`,
    });

    console.log(`[RuleEngine] Ledger entry created for ${order.order_id}`);
    console.log(`  - Gross: Rp ${grossIdr.toFixed(2)}`);
    console.log(`  - Fee (${this.platformFeePercent}%): Rp ${platformFeeIdr.toFixed(2)}`);
    console.log(`  - Net: Rp ${netIdr.toFixed(2)}`);
  }

  /**
   * Manually approve an order (bypass rules)
   */
  async manualApprove(orderId: string): Promise<void> {
    const order = await db.getOrder(orderId);
    if (!order) {
      throw new Error('Order not found');
    }

    await db.updateOrderStatus(orderId, 'APPROVED');
    await this.createLedgerEntry(order);
    
    console.log(`[RuleEngine] Order ${orderId} manually approved`);
  }
}

// Export singleton
let engineInstance: RuleEngine | null = null;

export function getRuleEngine(): RuleEngine | null {
  return engineInstance;
}

export function createRuleEngine(): RuleEngine {
  if (engineInstance) {
    engineInstance.stop();
  }
  engineInstance = new RuleEngine();
  return engineInstance;
}
