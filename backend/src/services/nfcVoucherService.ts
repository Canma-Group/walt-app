import { ethers } from 'ethers';
import { getHotWallet } from '../config/lisk';

// NfcVoucherVault contract ABI (minimal for interactions)
const NFC_VAULT_ABI = [
  'function claim((address payer, address payee, address token, uint256 amount, uint256 nonce, uint256 deadline) voucher, bytes signature) external',
  'function deposit(address token, uint256 amount) external',
  'function withdraw(address token, uint256 amount) external',
  'function getBalance(address user, address token) external view returns (uint256)',
  'function isNonceUsed(address payer, uint256 nonce) external view returns (bool)',
  'function getNextNonce(address user) external view returns (uint256)',
  'event VoucherClaimed(address indexed payer, address indexed payee, address indexed token, uint256 amount, uint256 nonce, bytes32 voucherHash)',
  'event Deposited(address indexed user, address indexed token, uint256 amount, uint256 newBalance)',
];

// Contract addresses per chain (update after deployment)
export const NFC_VAULT_ADDRESSES: Record<string, string> = {
  'lisk-sepolia': '0xD86060d68400fFEDeD0062F63c57158d92a8243a',
  'sepolia': '',      // TODO: Deploy to Sepolia ETH
  'polygon-amoy': '', // TODO: Deploy to Polygon Amoy
};

export class NfcVoucherService {
  private hotWallet: ethers.Wallet;

  constructor() {
    this.hotWallet = getHotWallet();
  }

  /**
   * Initialize contract instance
   */
  private getContract(vaultAddress: string): ethers.Contract {
    return new ethers.Contract(vaultAddress, NFC_VAULT_ABI, this.hotWallet);
  }

  /**
   * Claim a voucher on behalf of user (relayer mode)
   * Backend pays gas, user receives tokens
   */
  async claimVoucherAsRelayer(
    vaultAddress: string,
    voucher: {
      payer: string;
      payee: string;
      token: string;
      amount: string;
      nonce: number;
      deadline: number;
    },
    signature: string
  ): Promise<{ success: boolean; txHash?: string; error?: string }> {
    try {
      const contract = this.getContract(vaultAddress);

      // Check if nonce already used
      const nonceUsed = await contract.isNonceUsed(voucher.payer, voucher.nonce);
      if (nonceUsed) {
        return { success: false, error: 'Voucher already claimed (nonce used)' };
      }

      // Check deadline
      const now = Math.floor(Date.now() / 1000);
      if (now > voucher.deadline) {
        return { success: false, error: 'Voucher expired' };
      }

      // Prepare voucher tuple
      const voucherTuple = [
        voucher.payer,
        voucher.payee,
        voucher.token,
        ethers.parseUnits(voucher.amount, 0), // Already in wei
        voucher.nonce,
        voucher.deadline,
      ];

      // Estimate gas
      const gasEstimate = await contract.claim.estimateGas(voucherTuple, signature);
      const gasLimit = (gasEstimate * BigInt(120)) / BigInt(100); // 20% buffer

      // Send transaction
      const tx = await contract.claim(voucherTuple, signature, {
        gasLimit,
      });

      console.log(`[NfcVoucher] Claim tx sent: ${tx.hash}`);

      // Wait for confirmation
      const receipt = await tx.wait();

      if (receipt.status === 1) {
        console.log(`[NfcVoucher] Claim confirmed: ${tx.hash}`);
        return { success: true, txHash: tx.hash };
      } else {
        return { success: false, error: 'Transaction failed on-chain' };
      }
    } catch (error: any) {
      console.error('[NfcVoucher] Claim error:', error);
      return { success: false, error: error.message || 'Unknown error' };
    }
  }

  /**
   * Get user's deposit balance in vault
   */
  async getDepositBalance(
    vaultAddress: string,
    userAddress: string,
    tokenAddress: string
  ): Promise<string> {
    try {
      const contract = this.getContract(vaultAddress);
      const balance = await contract.getBalance(userAddress, tokenAddress);
      return balance.toString();
    } catch (error) {
      console.error('[NfcVoucher] getBalance error:', error);
      return '0';
    }
  }

  /**
   * Get next available nonce for a user
   */
  async getNextNonce(vaultAddress: string, userAddress: string): Promise<number> {
    try {
      const contract = this.getContract(vaultAddress);
      const nonce = await contract.getNextNonce(userAddress);
      return Number(nonce);
    } catch (error) {
      console.error('[NfcVoucher] getNextNonce error:', error);
      return 0;
    }
  }

  /**
   * Check if a nonce has been used
   */
  async isNonceUsed(
    vaultAddress: string,
    payerAddress: string,
    nonce: number
  ): Promise<boolean> {
    try {
      const contract = this.getContract(vaultAddress);
      return await contract.isNonceUsed(payerAddress, nonce);
    } catch (error) {
      console.error('[NfcVoucher] isNonceUsed error:', error);
      return false;
    }
  }
}

// Singleton instance
let nfcVoucherServiceInstance: NfcVoucherService | null = null;

export const getNfcVoucherService = (): NfcVoucherService => {
  if (!nfcVoucherServiceInstance) {
    nfcVoucherServiceInstance = new NfcVoucherService();
  }
  return nfcVoucherServiceInstance;
};
