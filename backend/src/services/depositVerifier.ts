import axios from 'axios';
import { QrisPaymentService } from './qrisPaymentService';

interface BlockscoutTokenTransfer {
  from: {
    hash: string;
  };
  to: {
    hash: string;
  };
  token: {
    address: string;
    symbol: string;
  };
  total: {
    value: string;
    decimals: string;
  };
  tx_hash: string;
  timestamp: string;
}

export class DepositVerifier {
  private blockscoutApiUrl = 'https://blockscout.lisk.com/api/v2';
  private lskTokenAddress = '0xac485391EB2d7D88253a7F1eF18C37f4571c1A24';
  private isRunning = false;
  private intervalId?: NodeJS.Timeout;

  constructor(private paymentService: QrisPaymentService) {}

  start(intervalSeconds: number = 10): void {
    if (this.isRunning) {
      console.log('[DepositVerifier] Already running');
      return;
    }

    this.isRunning = true;
    console.log(`[DepositVerifier] Starting with ${intervalSeconds}s interval`);

    this.intervalId = setInterval(() => {
      this.checkPendingPayments().catch(err => {
        console.error('[DepositVerifier] Error checking payments:', err);
      });
    }, intervalSeconds * 1000);

    // Run immediately
    this.checkPendingPayments().catch(err => {
      console.error('[DepositVerifier] Error checking payments:', err);
    });
  }

  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = undefined;
    }
    this.isRunning = false;
    console.log('[DepositVerifier] Stopped');
  }

  private async checkPendingPayments(): Promise<void> {
    const pendingPayments = this.paymentService.getAllPendingPayments();
    
    if (pendingPayments.length === 0) {
      return;
    }

    console.log(`[DepositVerifier] Checking ${pendingPayments.length} pending payments`);

    for (const payment of pendingPayments) {
      try {
        // Check if payment expired
        if (new Date() > payment.expiresAt) {
          console.log(`[DepositVerifier] Payment ${payment.paymentId} expired`);
          continue;
        }

        const verified = await this.verifyDeposit(payment);
        if (verified) {
          console.log(`[DepositVerifier] ✓ Payment ${payment.paymentId} verified and marked as PAID`);
        }
      } catch (error) {
        console.error(`[DepositVerifier] Error verifying payment ${payment.paymentId}:`, error);
      }
    }
  }

  private async verifyDeposit(payment: any): Promise<boolean> {
    try {
      // Query Blockscout for token transfers to escrow address
      const url = `${this.blockscoutApiUrl}/addresses/${payment.escrowAddress}/token-transfers`;
      const response = await axios.get(url, {
        params: {
          type: 'ERC-20',
        },
        timeout: 10000,
      });

      if (!response.data || !response.data.items) {
        return false;
      }

      const transfers: BlockscoutTokenTransfer[] = response.data.items;

      // Find matching transfer
      for (const transfer of transfers) {
        const fromAddress = transfer.from.hash.toLowerCase();
        const toAddress = transfer.to.hash.toLowerCase();
        const tokenAddress = transfer.token.address.toLowerCase();
        const txHash = transfer.tx_hash;

        // Check if this transfer matches our payment
        if (
          fromAddress === payment.payerWalletAddress.toLowerCase() &&
          toAddress === payment.escrowAddress.toLowerCase() &&
          tokenAddress === this.lskTokenAddress.toLowerCase()
        ) {
          // Check amount
          const transferredWei = BigInt(transfer.total.value);
          const expectedWei = BigInt(payment.lskAmountExpectedWei);

          // Allow 0.1% tolerance for rounding
          const minAcceptable = (expectedWei * BigInt(999)) / BigInt(1000);

          if (transferredWei >= minAcceptable) {
            // If payment has txHash, verify it matches
            if (payment.txHash && payment.txHash.toLowerCase() !== txHash.toLowerCase()) {
              console.log(`[DepositVerifier] TxHash mismatch for ${payment.paymentId}`);
              continue;
            }

            // Mark as paid
            this.paymentService.markAsPaid(payment.paymentId, txHash);
            return true;
          }
        }
      }

      return false;
    } catch (error) {
      console.error('[DepositVerifier] Error querying Blockscout:', error);
      return false;
    }
  }
}
