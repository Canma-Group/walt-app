import axios from 'axios';
import { ethers } from 'ethers';
import { QrisPaymentServiceDB } from './qrisPaymentServiceDB';
import { PaymentIntentRow, db } from '../db/database';

interface BlockscoutTokenTransfer {
  from: {
    hash: string;
  };
  to: {
    hash: string;
  };
  token: {
    address?: string;
    address_hash?: string;
    symbol: string;
  };
  total: {
    value: string;
    decimals: string;
  };
  tx_hash?: string;
  transaction_hash?: string;
  timestamp: string;
}

export class DepositVerifierDB {
  // Lisk Sepolia Testnet for hackathon demo
  private blockscoutApiUrl = process.env.BLOCKSCOUT_API_URL || 'https://sepolia-blockscout.lisk.com/api/v2';
  private lskTokenAddress = (process.env.LSK_TOKEN_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e').toLowerCase();
  private rpcUrl = process.env.LISK_RPC_URL || 'https://rpc.sepolia-api.lisk.com';
  private provider: ethers.JsonRpcProvider;
  private isRunning = false;
  private intervalId?: NodeJS.Timeout;

  constructor(private paymentService: QrisPaymentServiceDB) {
    this.provider = new ethers.JsonRpcProvider(this.rpcUrl);
  }

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
    const pendingPayments = await this.paymentService.getAllPendingPayments();
    
    if (pendingPayments.length === 0) {
      return;
    }

    console.log(`[DepositVerifier] Checking ${pendingPayments.length} pending payments`);

    for (const payment of pendingPayments) {
      try {
        // If payment has TX_SUBMITTED status with txHash, always try to verify
        // even if expired - the blockchain transaction might have succeeded
        const hasSubmittedTx = payment.status === 'TX_SUBMITTED' && payment.tx_hash;
        
        // Check if payment expired (but still verify if tx was submitted)
        if (new Date() > payment.expires_at && !hasSubmittedTx) {
          // Mark as EXPIRED so it doesn't keep showing up
          await db.updatePaymentStatus(payment.payment_id, 'EXPIRED');
          console.log(`[DepositVerifier] Payment ${payment.payment_id} expired -> marked EXPIRED`);
          continue;
        }

        const verified = await this.verifyDeposit(payment);
        if (verified) {
          console.log(`[DepositVerifier] ✓ Payment ${payment.payment_id} verified and marked as PAID`);
        } else if (hasSubmittedTx) {
          console.log(`[DepositVerifier] Payment ${payment.payment_id} has tx ${payment.tx_hash?.substring(0, 10)}... waiting for confirmation`);
        }
      } catch (error) {
        console.error(`[DepositVerifier] Error verifying payment ${payment.payment_id}:`, error);
      }
    }
  }

  private async verifyDeposit(payment: PaymentIntentRow): Promise<boolean> {
    // If we have a txHash, verify directly via RPC (FAST!)
    if (payment.tx_hash) {
      return await this.verifyViaRpc(payment);
    }
    
    // Fallback to Blockscout API for payments without txHash
    return await this.verifyViaBlockscout(payment);
  }

  // FAST: Verify transaction via RPC (no API timeout issues)
  private async verifyViaRpc(payment: PaymentIntentRow): Promise<boolean> {
    try {
      if (!payment.tx_hash) return false;

      const receipt = await this.provider.getTransactionReceipt(payment.tx_hash);
      
      if (!receipt) {
        // Transaction not yet mined
        return false;
      }

      // Check if transaction was successful
      if (receipt.status !== 1) {
        console.log(`[DepositVerifier] Transaction ${payment.tx_hash.substring(0, 10)}... failed on-chain - marking as FAILED`);
        // Mark as FAILED so we don't keep retrying
        await db.updatePaymentStatus(payment.payment_id, 'FAILED', payment.tx_hash);
        return true; // Return true to stop retrying
      }

      // Transaction confirmed! Mark as paid
      console.log(`[DepositVerifier] ✓ Transaction ${payment.tx_hash.substring(0, 10)}... confirmed in block ${receipt.blockNumber}`);
      
      await this.paymentService.markAsPaid(payment.payment_id, payment.tx_hash);

      // Create merchant notification
      try {
        await db.createMerchantNotification({
          payment_id: payment.payment_id,
          merchant_name: payment.merchant_name || 'QRIS Merchant',
          amount_idr: payment.amount_idr,
          payer_wallet: payment.payer_wallet_address,
          tx_hash: payment.tx_hash,
        });
        await db.updateTransactionStatus(payment.payment_id, 'PAID', payment.tx_hash);
      } catch (e) {
        console.error('[DepositVerifier] Failed to create notification:', e);
      }

      return true;
    } catch (error) {
      console.error(`[DepositVerifier] RPC error for ${payment.payment_id}:`, error);
      return false;
    }
  }

  // SLOW fallback: Verify via Blockscout API
  private async verifyViaBlockscout(payment: PaymentIntentRow): Promise<boolean> {
    try {
      const url = `${this.blockscoutApiUrl}/addresses/${payment.escrow_address}/token-transfers`;
      const response = await axios.get(url, {
        params: { type: 'ERC-20' },
        timeout: 10000,
      });

      if (!response.data || !response.data.items) {
        return false;
      }

      const transfers: BlockscoutTokenTransfer[] = response.data.items;

      for (const transfer of transfers) {
        const tokenAddr = transfer.token?.address_hash || transfer.token?.address;
        if (!transfer.from?.hash || !transfer.to?.hash || !tokenAddr) continue;
        
        const fromAddress = transfer.from.hash.toLowerCase();
        const toAddress = transfer.to.hash.toLowerCase();
        const tokenAddress = tokenAddr.toLowerCase();
        const txHash = transfer.tx_hash || transfer.transaction_hash;

        if (
          fromAddress === payment.payer_wallet_address.toLowerCase() &&
          toAddress === payment.escrow_address.toLowerCase() &&
          tokenAddress === this.lskTokenAddress.toLowerCase()
        ) {
          const transferredWei = BigInt(transfer.total.value);
          const expectedWei = BigInt(payment.lsk_amount_expected_wei);
          const minAcceptable = (expectedWei * BigInt(999)) / BigInt(1000);

          if (transferredWei >= minAcceptable && txHash) {
            await this.paymentService.markAsPaid(payment.payment_id, txHash);
            try {
              await db.createMerchantNotification({
                payment_id: payment.payment_id,
                merchant_name: payment.merchant_name || 'QRIS Merchant',
                amount_idr: payment.amount_idr,
                payer_wallet: payment.payer_wallet_address,
                tx_hash: txHash,
              });
              await db.updateTransactionStatus(payment.payment_id, 'PAID', txHash);
            } catch (e) {
              console.error('[DepositVerifier] Failed to create notification:', e);
            }
            return true;
          }
        }
      }
      return false;
    } catch (error) {
      console.error('[DepositVerifier] Blockscout error:', error);
      return false;
    }
  }
}
