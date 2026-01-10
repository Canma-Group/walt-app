/**
 * ESCROW EVENT LISTENER SERVICE
 * 
 * Listens to PaymentLocked events from the QrisEscrow smart contract on Lisk Mainnet.
 * Ensures idempotency via txHash + logIndex tracking.
 * Updates order status to LOCKED when payment is detected.
 * 
 * HACKATHON MVP - Lisk Mainnet
 */

import { ethers, Contract, EventLog } from 'ethers';
import { db } from '../db/database';

// ABI for QrisEscrowV2 contract events (Lisk Sepolia)
const ESCROW_ABI = [
  'event PaymentCreated(bytes32 indexed orderId, string merchantId, address indexed buyer, address indexed token, uint256 merchantAmount, uint256 platformFee, uint256 totalPaid, uint256 expiresAt)',
  'event PaymentReleased(bytes32 indexed orderId, string merchantId, address merchant, uint256 merchantAmount, uint256 platformFee)',
  'event PaymentRefunded(bytes32 indexed orderId, address buyer, uint256 amount, string reason)',
  'function getPayment(bytes32 orderId) view returns (bytes32 orderId, string merchantId, address buyer, address token, uint256 merchantAmount, uint256 platformFee, uint256 totalPaid, uint256 lockedAt, uint256 expiresAt, uint8 status)',
  'function pay(bytes32 orderId, string merchantId, uint256 totalAmount)',
];

export interface PaymentCreatedEvent {
  orderId: string;
  merchantId: string;
  buyerAddress: string;
  tokenAddress: string;
  merchantAmount: bigint;
  platformFee: bigint;
  totalPaid: bigint;
  expiresAt: bigint;
  txHash: string;
  blockNumber: number;
  logIndex: number;
}

export class EscrowEventListener {
  private provider: ethers.JsonRpcProvider;
  private contract: Contract;
  private isRunning = false;
  private pollInterval: NodeJS.Timeout | null = null;
  private lastProcessedBlock = 0;

  constructor(
    rpcUrl: string,
    private escrowAddress: string,
    private pollIntervalMs: number = 5000 // 5 seconds
  ) {
    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.contract = new ethers.Contract(escrowAddress, ESCROW_ABI, this.provider);
    
    console.log(`[EscrowListener] Initialized for contract: ${escrowAddress}`);
    console.log(`[EscrowListener] RPC: ${rpcUrl}`);
  }

  /**
   * Start listening for PaymentLocked events
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      console.log('[EscrowListener] Already running');
      return;
    }

    this.isRunning = true;
    console.log('[EscrowListener] Starting event listener...');

    // Get current block as starting point
    this.lastProcessedBlock = await this.provider.getBlockNumber() - 100; // Look back 100 blocks on start
    console.log(`[EscrowListener] Starting from block ${this.lastProcessedBlock}`);

    // Start polling
    this.poll();
    this.pollInterval = setInterval(() => this.poll(), this.pollIntervalMs);
  }

  /**
   * Stop listening
   */
  stop(): void {
    this.isRunning = false;
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
    console.log('[EscrowListener] Stopped');
  }

  /**
   * Poll for new events
   */
  private async poll(): Promise<void> {
    if (!this.isRunning) return;

    try {
      const currentBlock = await this.provider.getBlockNumber();
      
      if (currentBlock <= this.lastProcessedBlock) {
        return; // No new blocks
      }

      // Query PaymentCreated events
      const filter = this.contract.filters.PaymentCreated();
      const events = await this.contract.queryFilter(
        filter,
        this.lastProcessedBlock + 1,
        currentBlock
      );

      for (const event of events) {
        await this.processPaymentCreatedEvent(event as EventLog);
      }

      this.lastProcessedBlock = currentBlock;
    } catch (error) {
      console.error('[EscrowListener] Poll error:', error);
    }
  }

  /**
   * Process a single PaymentCreated event
   */
  private async processPaymentCreatedEvent(event: EventLog): Promise<void> {
    const txHash = event.transactionHash;
    const logIndex = event.index;
    
    // Check idempotency - prevent double processing
    const isProcessed = await db.isEventProcessed(txHash, logIndex);
    if (isProcessed) {
      console.log(`[EscrowListener] Event already processed: ${txHash}:${logIndex}`);
      return;
    }

    try {
      // Decode event data for PaymentCreated(bytes32 orderId, string merchantId, address buyer, address token, uint256 merchantAmount, uint256 platformFee, uint256 totalPaid, uint256 expiresAt)
      const args = event.args as unknown as [string, string, string, string, bigint, bigint, bigint, bigint];
      const [orderId, merchantId, buyerAddress, tokenAddress, merchantAmount, platformFee, totalPaid, expiresAt] = args;

      const paymentEvent: PaymentCreatedEvent = {
        orderId,
        merchantId,
        buyerAddress,
        tokenAddress,
        merchantAmount,
        platformFee,
        totalPaid,
        expiresAt,
        txHash,
        blockNumber: event.blockNumber,
        logIndex,
      };

      console.log('[EscrowListener] PaymentCreated event detected:');
      console.log(`  - Order ID: ${orderId}`);
      console.log(`  - Merchant: ${merchantId}`);
      console.log(`  - Amount: ${ethers.formatUnits(totalPaid, 18)} LSK`);
      console.log(`  - Buyer: ${buyerAddress}`);
      console.log(`  - TX: ${txHash}`);

      // Create or update order in database
      await this.createOrderFromEvent(paymentEvent);

      // Mark event as processed (idempotency)
      await db.markEventProcessed(txHash, logIndex, 'PaymentCreated', orderId);

      console.log(`[EscrowListener] Order ${orderId} created/updated -> status: LOCKED`);
    } catch (error) {
      console.error(`[EscrowListener] Error processing event ${txHash}:${logIndex}:`, error);
    }
  }

  /**
   * Create order record from blockchain event
   */
  private async createOrderFromEvent(event: PaymentCreatedEvent): Promise<void> {
    const amountLsk = parseFloat(ethers.formatUnits(event.totalPaid, 18));
    const expiresAt = new Date(Number(event.expiresAt) * 1000);
    const block = await this.provider.getBlock(event.blockNumber);
    const lockedAt = block ? new Date(block.timestamp * 1000) : new Date();

    await db.createOrder({
      order_id: event.orderId,
      merchant_id: event.merchantId,
      buyer_address: event.buyerAddress.toLowerCase(),
      amount_lsk_wei: event.totalPaid.toString(),
      amount_lsk: amountLsk,
      escrow_tx_hash: event.txHash,
      block_number: event.blockNumber,
      locked_at: lockedAt,
      expires_at: expiresAt,
      status: 'LOCKED',
    });
  }

  /**
   * Manually process a specific transaction (for testing/recovery)
   */
  async processTransaction(txHash: string): Promise<void> {
    console.log(`[EscrowListener] Manually processing TX: ${txHash}`);
    
    const receipt = await this.provider.getTransactionReceipt(txHash);
    if (!receipt) {
      throw new Error('Transaction not found');
    }

    const logs = receipt.logs.filter(
      log => log.address.toLowerCase() === this.escrowAddress.toLowerCase()
    );

    for (const log of logs) {
      try {
        const parsed = this.contract.interface.parseLog({
          topics: log.topics as string[],
          data: log.data,
        });
        
        if (parsed && parsed.name === 'PaymentCreated') {
          await this.processPaymentCreatedEvent(log as unknown as EventLog);
        }
      } catch (e) {
        // Not a PaymentCreated event, skip
      }
    }
  }
}

// Export singleton factory
let listenerInstance: EscrowEventListener | null = null;

export function getEscrowListener(): EscrowEventListener | null {
  return listenerInstance;
}

export function createEscrowListener(
  rpcUrl: string,
  escrowAddress: string
): EscrowEventListener {
  if (listenerInstance) {
    listenerInstance.stop();
  }
  listenerInstance = new EscrowEventListener(rpcUrl, escrowAddress);
  return listenerInstance;
}
