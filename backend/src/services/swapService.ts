import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

// Token contracts on Lisk Sepolia (must match Flutter app)
const TOKEN_CONTRACTS: Record<string, string> = {
  LSK: process.env.MOCK_LSK_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e',
  ETH: process.env.MOCK_ETH_ADDRESS || '0x292D54495d4C9Af56D86fA6cAF25591037EF80b3',
  POL: process.env.MOCK_POL_ADDRESS || '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e',
};

// Token prices in USD (for exchange rate calculation)
const TOKEN_PRICES_USD: Record<string, number> = {
  LSK: 1.0,
  ETH: 3500.0,
  POL: 0.5,
};

// ERC20 ABI for transfer
const ERC20_ABI = [
  'function transfer(address to, uint256 amount) returns (bool)',
  'function balanceOf(address account) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function symbol() view returns (string)',
];

// Admin fee percentage (0.2%)
const ADMIN_FEE_PERCENT = 0.002;

export interface SwapRequest {
  userAddress: string;
  fromToken: string;
  toToken: string;
  fromAmount: string; // in token units (not wei)
  userTxHash: string; // tx hash of user sending tokens to hot wallet
}

export interface SwapResult {
  success: boolean;
  txHash?: string;
  fromToken?: string;
  toToken?: string;
  fromAmount?: string;
  toAmount?: string;
  adminFee?: string;
  error?: string;
}

export class SwapService {
  private provider: ethers.JsonRpcProvider;
  private hotWallet: ethers.Wallet;

  constructor() {
    const rpcUrl = process.env.LISK_SEPOLIA_RPC || 'https://rpc.sepolia-api.lisk.com';
    const privateKey = process.env.HOT_WALLET_PRIVATE_KEY;

    if (!privateKey) {
      throw new Error('HOT_WALLET_PRIVATE_KEY not configured');
    }

    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.hotWallet = new ethers.Wallet(privateKey, this.provider);

    console.log(`[SwapService] Initialized with hot wallet: ${this.hotWallet.address}`);
  }

  /**
   * Get hot wallet address
   */
  getHotWalletAddress(): string {
    return this.hotWallet.address;
  }

  /**
   * Get exchange rate between two tokens
   */
  getExchangeRate(fromToken: string, toToken: string): number {
    const fromPrice = TOKEN_PRICES_USD[fromToken.toUpperCase()] || 1;
    const toPrice = TOKEN_PRICES_USD[toToken.toUpperCase()] || 1;
    return fromPrice / toPrice;
  }

  /**
   * Calculate swap output amount after admin fee
   */
  calculateSwapOutput(fromAmount: number, fromToken: string, toToken: string): {
    toAmount: number;
    adminFee: number;
    exchangeRate: number;
  } {
    const adminFee = fromAmount * ADMIN_FEE_PERCENT;
    const amountAfterFee = fromAmount - adminFee;
    const exchangeRate = this.getExchangeRate(fromToken, toToken);
    const toAmount = amountAfterFee * exchangeRate;

    return {
      toAmount,
      adminFee,
      exchangeRate,
    };
  }

  /**
   * Get hot wallet token balance
   */
  async getTokenBalance(tokenSymbol: string): Promise<string> {
    const tokenAddress = TOKEN_CONTRACTS[tokenSymbol.toUpperCase()];
    if (!tokenAddress) {
      throw new Error(`Unknown token: ${tokenSymbol}`);
    }

    const contract = new ethers.Contract(tokenAddress, ERC20_ABI, this.provider);
    const balance = await contract.balanceOf(this.hotWallet.address);
    const decimals = await contract.decimals();
    
    return ethers.formatUnits(balance, decimals);
  }

  /**
   * Get all hot wallet balances
   */
  async getAllBalances(): Promise<Record<string, string>> {
    const balances: Record<string, string> = {};
    
    for (const symbol of Object.keys(TOKEN_CONTRACTS)) {
      try {
        balances[symbol] = await this.getTokenBalance(symbol);
      } catch (e) {
        balances[symbol] = '0';
      }
    }

    // Also get native ETH balance
    const ethBalance = await this.provider.getBalance(this.hotWallet.address);
    balances['NATIVE_ETH'] = ethers.formatEther(ethBalance);

    return balances;
  }

  /**
   * Execute swap - send toToken to user
   * This should be called AFTER user has sent fromToken to hot wallet
   */
  async executeSwap(request: SwapRequest): Promise<SwapResult> {
    const { userAddress, fromToken, toToken, fromAmount, userTxHash } = request;

    console.log(`[SwapService] ========== SWAP EXECUTION ==========`);
    console.log(`[SwapService] User: ${userAddress}`);
    console.log(`[SwapService] From: ${fromAmount} ${fromToken}`);
    console.log(`[SwapService] To: ${toToken}`);
    console.log(`[SwapService] User TX: ${userTxHash}`);

    try {
      // 1. Verify user transaction (optional - for production)
      // const receipt = await this.provider.getTransactionReceipt(userTxHash);
      // if (!receipt || receipt.status !== 1) {
      //   throw new Error('User transaction not confirmed');
      // }

      // 2. Calculate output amount
      const fromAmountNum = parseFloat(fromAmount);
      const { toAmount, adminFee, exchangeRate } = this.calculateSwapOutput(
        fromAmountNum,
        fromToken,
        toToken
      );

      console.log(`[SwapService] Exchange rate: ${exchangeRate}`);
      console.log(`[SwapService] Admin fee (0.2%): ${adminFee} ${fromToken}`);
      console.log(`[SwapService] Output: ${toAmount} ${toToken}`);

      // 3. Check hot wallet has enough balance
      const hotWalletBalance = await this.getTokenBalance(toToken);
      if (parseFloat(hotWalletBalance) < toAmount) {
        throw new Error(`Insufficient ${toToken} liquidity in swap pool. Available: ${hotWalletBalance}`);
      }

      // 4. Send toToken to user
      const toTokenAddress = TOKEN_CONTRACTS[toToken.toUpperCase()];
      if (!toTokenAddress) {
        throw new Error(`Unknown token: ${toToken}`);
      }

      const contract = new ethers.Contract(toTokenAddress, ERC20_ABI, this.hotWallet);
      const decimals = await contract.decimals();
      const amountWei = ethers.parseUnits(toAmount.toFixed(6), decimals);

      console.log(`[SwapService] Sending ${toAmount} ${toToken} to ${userAddress}...`);

      const tx = await contract.transfer(userAddress, amountWei);
      console.log(`[SwapService] TX submitted: ${tx.hash}`);

      // Wait for confirmation
      const receipt = await tx.wait();
      console.log(`[SwapService] TX confirmed in block ${receipt?.blockNumber}`);
      console.log(`[SwapService] ========== SWAP COMPLETE ==========`);

      return {
        success: true,
        txHash: tx.hash,
        fromToken,
        toToken,
        fromAmount: fromAmountNum.toString(),
        toAmount: toAmount.toFixed(6),
        adminFee: adminFee.toFixed(6),
      };
    } catch (error: any) {
      console.error(`[SwapService] Swap failed:`, error);
      return {
        success: false,
        error: error.message || 'Swap execution failed',
      };
    }
  }

  /**
   * Get swap quote (preview without executing)
   */
  async getSwapQuote(fromToken: string, toToken: string, fromAmount: string): Promise<{
    fromToken: string;
    toToken: string;
    fromAmount: string;
    toAmount: string;
    adminFee: string;
    exchangeRate: number;
    poolBalance: string;
    sufficient: boolean;
  }> {
    const fromAmountNum = parseFloat(fromAmount);
    const { toAmount, adminFee, exchangeRate } = this.calculateSwapOutput(
      fromAmountNum,
      fromToken,
      toToken
    );

    const poolBalance = await this.getTokenBalance(toToken);
    const sufficient = parseFloat(poolBalance) >= toAmount;

    return {
      fromToken,
      toToken,
      fromAmount,
      toAmount: toAmount.toFixed(6),
      adminFee: adminFee.toFixed(6),
      exchangeRate,
      poolBalance,
      sufficient,
    };
  }
}

// Singleton instance
let swapServiceInstance: SwapService | null = null;

export function initializeSwapService(): SwapService | null {
  try {
    if (!swapServiceInstance) {
      swapServiceInstance = new SwapService();
    }
    return swapServiceInstance;
  } catch (e) {
    console.warn('[SwapService] Failed to initialize:', e);
    return null;
  }
}

export function getSwapService(): SwapService | null {
  return swapServiceInstance;
}
