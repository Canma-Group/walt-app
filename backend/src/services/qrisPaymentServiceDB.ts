import { ethers } from 'ethers';
import crypto from 'crypto';
import { db, PaymentIntentRow } from '../db/database';

export interface CreatePaymentRequest {
  walletAddress: string;
  qrisPayload: string;
  amountIdr: number;
}

export interface CreatePaymentResponse {
  paymentId: string;
  orderId: string; // bytes32 for smart contract
  escrowAddress: string;
  amountIdr: number;
  lskAmountExpected: string;
  lskTokenAddress: string;
  chainId: number;
  expiresAt: Date;
}

export class QrisPaymentServiceDB {
  private escrowMasterMnemonic: string;
  // LISK SEPOLIA TESTNET - MockLSK token for hackathon demo
  private lskTokenAddress = (process.env.LSK_TOKEN_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e').toLowerCase();
  private chainId = parseInt(process.env.LISK_CHAIN_ID || '4202'); // Lisk Sepolia

  constructor(escrowMasterMnemonic: string) {
    if (!escrowMasterMnemonic || escrowMasterMnemonic === 'your-escrow-master-mnemonic-here') {
      throw new Error('ESCROW_MASTER_MNEMONIC not configured');
    }
    this.escrowMasterMnemonic = escrowMasterMnemonic;
  }

  private deriveEscrowWallet(index: number): ethers.HDNodeWallet {
    // Create fresh HD wallet from mnemonic and derive the path
    const masterNode = ethers.HDNodeWallet.fromPhrase(this.escrowMasterMnemonic);
    return masterNode.derivePath(`44'/60'/0'/0/${index}`);
  }

  async createPayment(req: CreatePaymentRequest, lskPriceIdr: number): Promise<CreatePaymentResponse> {
    const paymentId = crypto.randomUUID();
    const orderId = ethers.keccak256(ethers.toUtf8Bytes(paymentId)); // bytes32 for contract
    const qrisHash = crypto.createHash('sha256').update(req.qrisPayload).digest('hex');
    
    // Derive unique escrow address for this payment
    const escrowIndex = this.getEscrowIndexFromPaymentId(paymentId);
    const escrowWallet = this.deriveEscrowWallet(escrowIndex);
    const escrowAddress = escrowWallet.address;

    // Calculate LSK amount
    const lskAmountExpected = req.amountIdr / lskPriceIdr;
    const lskAmountExpectedWei = ethers.parseUnits(lskAmountExpected.toFixed(8), 18).toString();

    // Parse merchant name from QRIS (optional, basic parsing)
    const merchantName = this.parseMerchantName(req.qrisPayload);

    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

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
      escrow_address: escrowAddress,
      status: 'CREATED',
    });

    return {
      paymentId,
      orderId,
      escrowAddress,
      amountIdr: req.amountIdr,
      lskAmountExpected: lskAmountExpected.toFixed(8),
      lskTokenAddress: this.lskTokenAddress,
      chainId: this.chainId,
      expiresAt,
    };
  }

  async submitTxHash(paymentId: string, txHash: string): Promise<PaymentIntentRow> {
    const payment = await db.getPaymentIntent(paymentId);
    if (!payment) {
      throw new Error('Payment not found');
    }

    if (payment.status === 'PAID') {
      // Race condition: DepositVerifier already marked as PAID
      // Just return success instead of throwing error
      console.log(`[QRIS] Payment ${paymentId} already paid, returning success`);
      return payment;
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

  async getPayment(paymentId: string): Promise<PaymentIntentRow | null> {
    return await db.getPaymentIntent(paymentId);
  }

  async getAllPendingPayments(): Promise<PaymentIntentRow[]> {
    return await db.getPendingPayments();
  }

  async markAsPaid(paymentId: string, txHash: string): Promise<void> {
    await db.markAsPaid(paymentId, txHash);
  }

  private getEscrowIndexFromPaymentId(paymentId: string): number {
    const hash = crypto.createHash('sha256').update(paymentId).digest();
    return hash.readUInt32BE(0) % 1000000;
  }

  private parseMerchantName(qrisPayload: string): string | undefined {
    try {
      // Basic QRIS parsing - tag 59 is merchant name
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
}
