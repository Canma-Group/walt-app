import { ethers } from 'ethers';
import crypto from 'crypto';
import { db, PaymentIntentRow } from '../db/database';

// QrisEscrowV2 ABI - only the functions we need
const ESCROW_V2_ABI = [
  'function pay(bytes32 orderId, string merchantId, uint256 totalAmount) external',
  'function payWithToken(bytes32 orderId, string merchantId, address token, uint256 totalAmount) external',
  'function release(bytes32 orderId) external',
  'function refund(bytes32 orderId, string reason) external',
  'function claimExpiredRefund(bytes32 orderId) external',
  'function dispute(bytes32 orderId, string reason) external',
  'function getPayment(bytes32 orderId) external view returns (tuple(bytes32 orderId, string merchantId, address buyer, address token, uint256 merchantAmount, uint256 platformFee, uint256 totalPaid, uint256 lockedAt, uint256 expiresAt, uint8 status))',
  'function getStatistics() external view returns (tuple(uint256 totalPayments, uint256 totalReleased, uint256 totalRefunded, uint256 totalDisputed, uint256 totalFeesCollected, uint256 totalVolume))',
  'function platformFeeBps() external view returns (uint256)',
  'function paymentTimeout() external view returns (uint256)',
  'function isTokenWhitelisted(address token) external view returns (bool)',
  'function getVersion() external pure returns (string)',
  'function paused() external view returns (bool)',
  'event PaymentCreated(bytes32 indexed orderId, string merchantId, address indexed buyer, address indexed token, uint256 merchantAmount, uint256 platformFee, uint256 totalPaid, uint256 expiresAt)',
  'event PaymentReleased(bytes32 indexed orderId, uint256 amount, address indexed recipient)',
  'event PaymentRefunded(bytes32 indexed orderId, uint256 amount, address indexed buyer, string reason)',
];


export interface CreatePaymentRequest {
  walletAddress: string;
  qrisPayload: string;
  amountIdr: number;
}

export interface CreatePaymentResponse {
  paymentId: string;
  orderId: string; // bytes32 for contract
  escrowAddress: string;
  amountIdr: number;
  lskAmountExpected: string;
  lskTokenAddress: string;
  chainId: number;
  expiresAt: Date;
  platformFeeBps: number;
}

export interface EscrowPaymentStatus {
  orderId: string;
  merchantId: string;
  buyer: string;
  token: string;
  merchantAmount: string;
  platformFee: string;
  totalPaid: string;
  lockedAt: number;
  expiresAt: number;
  status: 'NONE' | 'LOCKED' | 'RELEASED' | 'REFUNDED' | 'DISPUTED';
}

export interface EscrowStatistics {
  totalPayments: number;
  totalReleased: number;
  totalRefunded: number;
  totalDisputed: number;
  totalFeesCollected: string;
  totalVolume: string;
}

export class QrisEscrowV2Service {
  private provider: ethers.JsonRpcProvider;
  private operatorWallet: ethers.Wallet;
  private escrowContract: ethers.Contract;
  
  private escrowAddress: string;
  private lskTokenAddress: string;
  private chainId: number;

  constructor() {
    const rpcUrl = process.env.LISK_RPC_URL || 'https://rpc.sepolia-api.lisk.com';
    const escrowAddress = process.env.QRIS_ESCROW_V2_ADDRESS;
    const operatorKey = process.env.HOT_WALLET_PRIVATE_KEY;
    const lskTokenAddress = process.env.LSK_TOKEN_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';
    
    if (!escrowAddress) {
      throw new Error('QRIS_ESCROW_V2_ADDRESS not configured');
    }
    if (!operatorKey) {
      throw new Error('HOT_WALLET_PRIVATE_KEY not configured');
    }

    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.operatorWallet = new ethers.Wallet(operatorKey, this.provider);
    this.escrowContract = new ethers.Contract(escrowAddress, ESCROW_V2_ABI, this.operatorWallet);
    
    this.escrowAddress = escrowAddress;
    this.lskTokenAddress = lskTokenAddress.toLowerCase();
    this.chainId = parseInt(process.env.LISK_CHAIN_ID || '4202');
    
    console.log(`[QrisEscrowV2] Initialized`);
    console.log(`  Escrow: ${escrowAddress}`);
    console.log(`  LSK Token: ${lskTokenAddress}`);
    console.log(`  Operator: ${this.operatorWallet.address}`);
  }

  /**
   * Generate bytes32 orderId from paymentId
   */
  private paymentIdToOrderId(paymentId: string): string {
    return ethers.keccak256(ethers.toUtf8Bytes(paymentId));
  }

  /**
   * Create a payment intent (off-chain, stores in DB)
   * User will call the contract directly from Flutter app
   */
  async createPayment(req: CreatePaymentRequest, lskPriceIdr: number): Promise<CreatePaymentResponse> {
    const paymentId = crypto.randomUUID();
    const orderId = this.paymentIdToOrderId(paymentId);
    const qrisHash = crypto.createHash('sha256').update(req.qrisPayload).digest('hex');

    // Get contract config
    const platformFeeBps = await this.escrowContract.platformFeeBps();
    const timeoutSeconds = await this.escrowContract.paymentTimeout();

    // Calculate LSK amount (before fee)
    const lskAmountExpected = req.amountIdr / lskPriceIdr;
    const lskAmountExpectedWei = ethers.parseUnits(lskAmountExpected.toFixed(8), 18).toString();

    // Parse merchant info from QRIS
    const merchantName = this.parseMerchantName(req.qrisPayload);
    // Use merchantId for database reference
    const merchantId = this.parseMerchantId(req.qrisPayload) || qrisHash.substring(0, 16);
    console.log(`[QrisEscrowV2] Merchant ID: ${merchantId}`);

    const expiresAt = new Date(Date.now() + Number(timeoutSeconds) * 1000);

    // Save to database
    await db.createPaymentIntent({
      payment_id: paymentId,
      expires_at: expiresAt,
      payer_wallet_address: req.walletAddress.toLowerCase(),
      qris_payload: req.qrisPayload,
      qris_hash: qrisHash,
      merchant_name: merchantName,
      amount_idr: req.amountIdr,
      lsk_amount_expected: lskAmountExpected.toFixed(8),
      lsk_amount_expected_wei: lskAmountExpectedWei,
      escrow_address: this.escrowAddress, // Use contract address instead of derived wallet
      status: 'CREATED',
    });

    console.log(`[QrisEscrowV2] Payment created: ${paymentId}`);
    console.log(`  OrderId (bytes32): ${orderId}`);
    console.log(`  Amount: ${lskAmountExpected.toFixed(8)} LSK (${req.amountIdr} IDR)`);

    return {
      paymentId,
      orderId,
      escrowAddress: this.escrowAddress,
      amountIdr: req.amountIdr,
      lskAmountExpected: lskAmountExpected.toFixed(8),
      lskTokenAddress: this.lskTokenAddress,
      chainId: this.chainId,
      expiresAt,
      platformFeeBps: Number(platformFeeBps),
    };
  }

  /**
   * Get payment status from smart contract
   */
  async getPaymentFromContract(paymentId: string): Promise<EscrowPaymentStatus | null> {
    try {
      const orderId = this.paymentIdToOrderId(paymentId);
      const payment = await this.escrowContract.getPayment(orderId);
      
      const statusMap = ['NONE', 'LOCKED', 'RELEASED', 'REFUNDED', 'DISPUTED'] as const;
      
      return {
        orderId: payment.orderId,
        merchantId: payment.merchantId,
        buyer: payment.buyer,
        token: payment.token,
        merchantAmount: ethers.formatEther(payment.merchantAmount),
        platformFee: ethers.formatEther(payment.platformFee),
        totalPaid: ethers.formatEther(payment.totalPaid),
        lockedAt: Number(payment.lockedAt),
        expiresAt: Number(payment.expiresAt),
        status: statusMap[Number(payment.status)],
      };
    } catch (e) {
      console.error(`[QrisEscrowV2] Error getting payment from contract:`, e);
      return null;
    }
  }

  /**
   * Release payment (operator/admin only)
   */
  async releasePayment(paymentId: string): Promise<string> {
    const orderId = this.paymentIdToOrderId(paymentId);
    
    console.log(`[QrisEscrowV2] Releasing payment: ${paymentId}`);
    
    const tx = await this.escrowContract.release(orderId);
    const receipt = await tx.wait();
    
    console.log(`[QrisEscrowV2] Payment released! TxHash: ${receipt.hash}`);
    
    // Update DB
    await db.updatePaymentStatus(paymentId, 'PAID', receipt.hash);
    
    return receipt.hash;
  }

  /**
   * Refund payment (operator/admin only)
   */
  async refundPayment(paymentId: string, reason: string): Promise<string> {
    const orderId = this.paymentIdToOrderId(paymentId);
    
    console.log(`[QrisEscrowV2] Refunding payment: ${paymentId} - ${reason}`);
    
    const tx = await this.escrowContract.refund(orderId, reason);
    const receipt = await tx.wait();
    
    console.log(`[QrisEscrowV2] Payment refunded! TxHash: ${receipt.hash}`);
    
    // Update DB
    await db.updatePaymentStatus(paymentId, 'FAILED', receipt.hash);
    
    return receipt.hash;
  }

  /**
   * Get escrow statistics
   */
  async getStatistics(): Promise<EscrowStatistics> {
    const stats = await this.escrowContract.getStatistics();
    
    return {
      totalPayments: Number(stats.totalPayments),
      totalReleased: Number(stats.totalReleased),
      totalRefunded: Number(stats.totalRefunded),
      totalDisputed: Number(stats.totalDisputed),
      totalFeesCollected: ethers.formatEther(stats.totalFeesCollected),
      totalVolume: ethers.formatEther(stats.totalVolume),
    };
  }

  /**
   * Get contract version
   */
  async getVersion(): Promise<string> {
    return await this.escrowContract.getVersion();
  }

  /**
   * Check if contract is paused
   */
  async isPaused(): Promise<boolean> {
    return await this.escrowContract.paused();
  }

  /**
   * Get platform fee in basis points
   */
  async getPlatformFeeBps(): Promise<number> {
    const feeBps = await this.escrowContract.platformFeeBps();
    return Number(feeBps);
  }

  /**
   * Check if token is whitelisted
   */
  async isTokenWhitelisted(token: string): Promise<boolean> {
    return await this.escrowContract.isTokenWhitelisted(token);
  }

  /**
   * Get escrow contract address
   */
  getEscrowAddress(): string {
    return this.escrowAddress;
  }

  /**
   * Get operator wallet address
   */
  getOperatorAddress(): string {
    return this.operatorWallet.address;
  }

  // ============ DB Operations ============

  async getPayment(paymentId: string): Promise<PaymentIntentRow | null> {
    return await db.getPaymentIntent(paymentId);
  }

  async getAllPendingPayments(): Promise<PaymentIntentRow[]> {
    return await db.getPendingPayments();
  }

  async submitTxHash(paymentId: string, txHash: string): Promise<PaymentIntentRow> {
    const payment = await db.getPaymentIntent(paymentId);
    if (!payment) {
      throw new Error('Payment not found');
    }

    if (payment.status === 'PAID') {
      throw new Error('Payment already paid');
    }

    if (new Date() > payment.expires_at) {
      await db.updatePaymentStatus(paymentId, 'EXPIRED');
      throw new Error('Payment expired');
    }

    const updated = await db.updatePaymentStatus(paymentId, 'TX_SUBMITTED', txHash);
    if (!updated) {
      throw new Error('Failed to update payment');
    }

    return updated;
  }

  async markAsPaid(paymentId: string, txHash: string): Promise<void> {
    await db.markAsPaid(paymentId, txHash);
  }

  // ============ Helper Functions ============

  private parseMerchantName(qrisPayload: string): string | undefined {
    try {
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

  private parseMerchantId(qrisPayload: string): string | undefined {
    try {
      // Tag 26 contains merchant account info
      const tag26Match = qrisPayload.match(/26(\d{2})/);
      if (tag26Match) {
        return tag26Match[0];
      }
    } catch (e) {
      console.error('Error parsing merchant ID:', e);
    }
    return undefined;
  }
}
