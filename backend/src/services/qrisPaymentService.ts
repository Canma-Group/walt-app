import { ethers } from 'ethers';
import crypto from 'crypto';

export interface PaymentIntent {
  paymentId: string;
  createdAt: Date;
  expiresAt: Date;
  payerWalletAddress: string;
  qrisPayload: string;
  qrisHash: string;
  merchantName?: string;
  amountIdr: number;
  lskAmountExpected: string;
  lskAmountExpectedWei: string;
  escrowAddress: string;
  status: 'CREATED' | 'TX_SUBMITTED' | 'CONFIRMED' | 'PAID' | 'EXPIRED' | 'FAILED';
  txHash?: string;
  verifiedAt?: Date;
  receiptId?: string;
  ledgerTxHash?: string;
}

export interface CreatePaymentRequest {
  walletAddress: string;
  qrisPayload: string;
  amountIdr: number;
}

export interface CreatePaymentResponse {
  paymentId: string;
  escrowAddress: string;
  amountIdr: number;
  lskAmountExpected: string;
  lskTokenAddress: string;
  chainId: number;
  expiresAt: Date;
}

export class QrisPaymentService {
  private payments: Map<string, PaymentIntent> = new Map();
  private escrowMasterWallet: ethers.HDNodeWallet;
  // LISK SEPOLIA TESTNET - MockLSK token for hackathon demo
  private lskTokenAddress = process.env.LSK_TOKEN_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';
  private chainId = parseInt(process.env.LISK_CHAIN_ID || '4202'); // Lisk Sepolia

  constructor(escrowMasterMnemonic: string) {
    if (!escrowMasterMnemonic || escrowMasterMnemonic === 'your-escrow-master-mnemonic-here') {
      throw new Error('ESCROW_MASTER_MNEMONIC not configured');
    }
    this.escrowMasterWallet = ethers.Wallet.fromPhrase(escrowMasterMnemonic);
  }

  async createPayment(req: CreatePaymentRequest, lskPriceIdr: number): Promise<CreatePaymentResponse> {
    const paymentId = crypto.randomUUID();
    const qrisHash = crypto.createHash('sha256').update(req.qrisPayload).digest('hex');
    
    // Derive unique escrow address for this payment
    const escrowIndex = this.getEscrowIndexFromPaymentId(paymentId);
    const escrowWallet = this.escrowMasterWallet.derivePath(`m/44'/60'/0'/0/${escrowIndex}`);
    const escrowAddress = escrowWallet.address;

    // Calculate LSK amount
    const lskAmountExpected = req.amountIdr / lskPriceIdr;
    const lskAmountExpectedWei = ethers.parseUnits(lskAmountExpected.toFixed(8), 18).toString();

    // Parse merchant name from QRIS (optional, basic parsing)
    const merchantName = this.parseMerchantName(req.qrisPayload);

    const payment: PaymentIntent = {
      paymentId,
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000), // 10 minutes
      payerWalletAddress: req.walletAddress.toLowerCase(),
      qrisPayload: req.qrisPayload,
      qrisHash,
      merchantName,
      amountIdr: req.amountIdr,
      lskAmountExpected: lskAmountExpected.toFixed(8),
      lskAmountExpectedWei,
      escrowAddress,
      status: 'CREATED',
    };

    this.payments.set(paymentId, payment);

    return {
      paymentId,
      escrowAddress,
      amountIdr: req.amountIdr,
      lskAmountExpected: lskAmountExpected.toFixed(8),
      lskTokenAddress: this.lskTokenAddress,
      chainId: this.chainId,
      expiresAt: payment.expiresAt,
    };
  }

  async submitTxHash(paymentId: string, txHash: string): Promise<PaymentIntent> {
    const payment = this.payments.get(paymentId);
    if (!payment) {
      throw new Error('Payment not found');
    }

    if (payment.status === 'PAID') {
      throw new Error('Payment already paid');
    }

    if (new Date() > payment.expiresAt) {
      payment.status = 'EXPIRED';
      throw new Error('Payment expired');
    }

    payment.txHash = txHash;
    payment.status = 'TX_SUBMITTED';
    this.payments.set(paymentId, payment);

    return payment;
  }

  getPayment(paymentId: string): PaymentIntent | undefined {
    return this.payments.get(paymentId);
  }

  getAllPendingPayments(): PaymentIntent[] {
    return Array.from(this.payments.values()).filter(
      p => p.status === 'TX_SUBMITTED' || p.status === 'CREATED'
    );
  }

  markAsPaid(paymentId: string, txHash: string): void {
    const payment = this.payments.get(paymentId);
    if (!payment) return;

    payment.status = 'PAID';
    payment.txHash = txHash;
    payment.verifiedAt = new Date();
    payment.receiptId = `RCP-${paymentId.substring(0, 8).toUpperCase()}`;
    this.payments.set(paymentId, payment);
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
