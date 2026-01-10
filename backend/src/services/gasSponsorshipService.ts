import { ethers } from 'ethers';
import { fetchPricesFromIndodax } from './priceService';

// Lisk Sepolia Testnet configuration (for hackathon demo)
const LISK_RPC_URL = process.env.LISK_RPC_URL || 'https://rpc.sepolia-api.lisk.com';
const LSK_TOKEN_ADDRESS = process.env.LSK_TOKEN_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';

// Gas configuration
const GAS_LIMIT_ERC20_TRANSFER = 100000; // Gas needed for ERC-20 transfer
const GAS_SAFETY_MARGIN = 1.5; // 50% safety margin
const MIN_GAS_BALANCE = 0.00005; // Minimum ETH balance to consider user has gas

interface GasSponsorshipRequest {
  walletAddress: string;
  paymentId: string;
  escrowAddress: string;
  lskAmount: string;
}

interface GasSponsorshipResult {
  success: boolean;
  txHash?: string;
  gasAmountWei?: string;
  gasAmountEth?: string;
  gasCostIdr?: number;
  error?: string;
}

interface AdminFeeResult {
  baseFeePercent: number;
  baseFeeIdr: number;
  gasCostIdr: number;
  totalAdminFeeIdr: number;
}

export class GasSponsorshipService {
  private provider: ethers.JsonRpcProvider;
  private hotWallet: ethers.Wallet;
  private hotWalletAddress: string;

  constructor(hotWalletPrivateKey: string) {
    this.provider = new ethers.JsonRpcProvider(LISK_RPC_URL);
    this.hotWallet = new ethers.Wallet(hotWalletPrivateKey, this.provider);
    this.hotWalletAddress = this.hotWallet.address;
    
    console.log(`[GasSponsorship] Hot wallet initialized: ${this.hotWalletAddress}`);
  }

  /**
   * Check if user needs gas sponsorship
   */
  async needsGasSponsorship(walletAddress: string): Promise<boolean> {
    try {
      const balance = await this.provider.getBalance(walletAddress);
      const balanceEth = parseFloat(ethers.formatEther(balance));
      
      console.log(`[GasSponsorship] User ${walletAddress} ETH balance: ${balanceEth}`);
      
      return balanceEth < MIN_GAS_BALANCE;
    } catch (error) {
      console.error('[GasSponsorship] Error checking balance:', error);
      return true; // Assume needs sponsorship on error
    }
  }

  /**
   * Check if user has enough LSK for the payment
   */
  async checkLskBalance(walletAddress: string, requiredAmount: string): Promise<boolean> {
    try {
      const lskContract = new ethers.Contract(
        LSK_TOKEN_ADDRESS,
        ['function balanceOf(address) view returns (uint256)'],
        this.provider
      );
      
      const balance = await lskContract.balanceOf(walletAddress);
      const requiredWei = ethers.parseEther(requiredAmount);
      
      console.log(`[GasSponsorship] User LSK balance: ${ethers.formatEther(balance)}, required: ${requiredAmount}`);
      
      return balance >= requiredWei;
    } catch (error) {
      console.error('[GasSponsorship] Error checking LSK balance:', error);
      return false;
    }
  }

  /**
   * Estimate gas cost for ERC-20 transfer
   */
  async estimateGasCost(): Promise<{ gasWei: bigint; gasEth: string; gasPriceGwei: string }> {
    try {
      const feeData = await this.provider.getFeeData();
      const gasPrice = feeData.gasPrice || ethers.parseUnits('0.001', 'gwei');
      
      // Calculate total gas cost with safety margin
      const gasNeeded = BigInt(Math.floor(GAS_LIMIT_ERC20_TRANSFER * GAS_SAFETY_MARGIN));
      const gasWei = gasNeeded * gasPrice;
      
      console.log(`[GasSponsorship] Gas estimate: ${gasNeeded} gas × ${ethers.formatUnits(gasPrice, 'gwei')} gwei = ${ethers.formatEther(gasWei)} ETH`);
      
      return {
        gasWei,
        gasEth: ethers.formatEther(gasWei),
        gasPriceGwei: ethers.formatUnits(gasPrice, 'gwei'),
      };
    } catch (error) {
      console.error('[GasSponsorship] Error estimating gas:', error);
      // Fallback: very small amount for Lisk L2
      const fallbackGas = ethers.parseEther('0.0001');
      return {
        gasWei: fallbackGas,
        gasEth: '0.0001',
        gasPriceGwei: '0.001',
      };
    }
  }

  /**
   * Calculate gas cost in IDR using Indodax prices
   */
  async calculateGasCostIdr(gasEth: string): Promise<number> {
    try {
      const prices = await fetchPricesFromIndodax();
      const ethPriceIdr = prices['ETH'] || 58500000; // Fallback price
      
      const gasCostIdr = parseFloat(gasEth) * ethPriceIdr;
      
      console.log(`[GasSponsorship] Gas cost: ${gasEth} ETH × Rp ${ethPriceIdr} = Rp ${gasCostIdr.toFixed(0)}`);
      
      return Math.ceil(gasCostIdr);
    } catch (error) {
      console.error('[GasSponsorship] Error calculating gas cost IDR:', error);
      // Fallback: assume ~Rp 5 for gas on Lisk L2
      return 5;
    }
  }

  /**
   * Calculate total admin fee (1% + gas cost)
   */
  async calculateAdminFee(amountIdr: number, gasEth: string): Promise<AdminFeeResult> {
    const baseFeePercent = 0.01; // 1%
    const baseFeeIdr = Math.ceil(amountIdr * baseFeePercent);
    const gasCostIdr = await this.calculateGasCostIdr(gasEth);
    
    return {
      baseFeePercent,
      baseFeeIdr,
      gasCostIdr,
      totalAdminFeeIdr: baseFeeIdr + gasCostIdr,
    };
  }

  /**
   * Sponsor gas for a user's transaction
   */
  async sponsorGas(request: GasSponsorshipRequest): Promise<GasSponsorshipResult> {
    const { walletAddress, paymentId, escrowAddress, lskAmount } = request;
    
    console.log(`[GasSponsorship] Processing request for payment ${paymentId}`);
    console.log(`[GasSponsorship] User: ${walletAddress}, Escrow: ${escrowAddress}, LSK: ${lskAmount}`);
    
    try {
      // 1. Verify user has enough LSK (skip if lskAmount is 0 - simple gas sponsorship)
      if (lskAmount && lskAmount !== '0' && parseFloat(lskAmount) > 0) {
        const hasLsk = await this.checkLskBalance(walletAddress, lskAmount);
        if (!hasLsk) {
          return {
            success: false,
            error: 'Insufficient LSK balance for payment',
          };
        }
      }
      
      // 2. Check if user actually needs gas
      const needsGas = await this.needsGasSponsorship(walletAddress);
      if (!needsGas) {
        console.log('[GasSponsorship] User already has sufficient gas');
        return {
          success: true,
          txHash: 'NOT_NEEDED',
          gasAmountWei: '0',
          gasAmountEth: '0',
          gasCostIdr: 0,
        };
      }
      
      // 3. Estimate gas cost
      const { gasWei, gasEth } = await this.estimateGasCost();
      
      // 4. Check hot wallet balance
      const hotWalletBalance = await this.provider.getBalance(this.hotWalletAddress);
      if (hotWalletBalance < gasWei) {
        console.error('[GasSponsorship] Hot wallet insufficient balance!');
        return {
          success: false,
          error: 'Hot wallet has insufficient ETH for gas sponsorship',
        };
      }
      
      // 5. Send gas to user
      console.log(`[GasSponsorship] Sending ${gasEth} ETH to ${walletAddress}`);
      
      const tx = await this.hotWallet.sendTransaction({
        to: walletAddress,
        value: gasWei,
      });
      
      console.log(`[GasSponsorship] Transaction sent: ${tx.hash}`);
      
      // Wait for confirmation
      const receipt = await tx.wait();
      
      if (!receipt || receipt.status !== 1) {
        return {
          success: false,
          error: 'Gas sponsorship transaction failed',
        };
      }
      
      // 6. Calculate gas cost in IDR
      const gasCostIdr = await this.calculateGasCostIdr(gasEth);
      
      console.log(`[GasSponsorship] Success! TxHash: ${tx.hash}, Gas cost: Rp ${gasCostIdr}`);
      
      return {
        success: true,
        txHash: tx.hash,
        gasAmountWei: gasWei.toString(),
        gasAmountEth: gasEth,
        gasCostIdr,
      };
    } catch (error) {
      console.error('[GasSponsorship] Error:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  /**
   * Get hot wallet balance
   */
  async getHotWalletBalance(): Promise<{ eth: string; sufficient: boolean }> {
    try {
      const balance = await this.provider.getBalance(this.hotWalletAddress);
      const ethBalance = ethers.formatEther(balance);
      
      // Consider sufficient if > 0.01 ETH
      const sufficient = parseFloat(ethBalance) > 0.01;
      
      return { eth: ethBalance, sufficient };
    } catch (error) {
      console.error('[GasSponsorship] Error getting hot wallet balance:', error);
      return { eth: '0', sufficient: false };
    }
  }

  /**
   * Get hot wallet address
   */
  getHotWalletAddress(): string {
    return this.hotWalletAddress;
  }
}
