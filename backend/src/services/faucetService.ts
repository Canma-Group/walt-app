import { ethers } from 'ethers';
import { fetchPricesFromIndodax } from './priceService';

// Mock Token ABIs (simplified - just mint function)
const MOCK_TOKEN_ABI = [
  'function mint(address to, uint256 amount) external',
  'function balanceOf(address account) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function symbol() view returns (string)',
];

// Token addresses on Lisk Sepolia (will be set after deployment)
interface TokenAddresses {
  LSK: string;
  ETH: string;
  POL: string;
}

interface FaucetConfig {
  rpcUrl: string;
  privateKey: string;
  tokenAddresses: TokenAddresses;
}

interface MintResult {
  success: boolean;
  txHash: string;
  coin: string;
  amount: string;
  amountIdr: number;
  priceIdr: number;
  recipient: string;
  network: string;
}

export class FaucetService {
  private provider: ethers.JsonRpcProvider;
  private wallet: ethers.Wallet;
  private tokenContracts: Map<string, ethers.Contract>;
  private tokenAddresses: TokenAddresses;

  constructor(config: FaucetConfig) {
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
    this.wallet = new ethers.Wallet(config.privateKey, this.provider);
    this.tokenAddresses = config.tokenAddresses;
    this.tokenContracts = new Map();

    // Initialize token contracts
    for (const [symbol, address] of Object.entries(config.tokenAddresses)) {
      if (address && address !== '') {
        this.tokenContracts.set(
          symbol,
          new ethers.Contract(address, MOCK_TOKEN_ABI, this.wallet)
        );
        console.log(`[Faucet] Initialized ${symbol} contract at ${address}`);
      }
    }
  }

  /**
   * Mint tokens to a wallet address based on IDR amount
   * Uses real-time Indodax prices
   */
  async mintTokens(
    recipient: string,
    coin: string,
    amountIdr: number
  ): Promise<MintResult> {
    const upperCoin = coin.toUpperCase();
    
    // Validate coin
    if (!this.tokenContracts.has(upperCoin)) {
      throw new Error(`Token ${upperCoin} not supported. Available: ${Array.from(this.tokenContracts.keys()).join(', ')}`);
    }

    // Get real-time price from Indodax
    const prices = await fetchPricesFromIndodax();
    const priceIdr = prices[upperCoin];

    if (!priceIdr || priceIdr <= 0) {
      throw new Error(`Failed to get price for ${upperCoin}`);
    }

    // Calculate token amount from IDR
    const tokenAmount = amountIdr / priceIdr;
    const tokenAmountWei = ethers.parseEther(tokenAmount.toFixed(18));

    console.log(`[Faucet] Minting ${tokenAmount.toFixed(6)} ${upperCoin} (Rp ${amountIdr.toLocaleString()}) to ${recipient}`);
    console.log(`[Faucet] Price: Rp ${priceIdr.toLocaleString()} per ${upperCoin}`);

    // Mint tokens
    const contract = this.tokenContracts.get(upperCoin)!;
    const tx = await contract.mint(recipient, tokenAmountWei);
    const receipt = await tx.wait();

    console.log(`[Faucet] Minted! TxHash: ${receipt.hash}`);

    return {
      success: true,
      txHash: receipt.hash,
      coin: upperCoin,
      amount: tokenAmount.toFixed(6),
      amountIdr,
      priceIdr,
      recipient,
      network: 'Lisk Sepolia Testnet',
    };
  }

  /**
   * Get token balance for an address
   */
  async getBalance(address: string, coin: string): Promise<string> {
    const upperCoin = coin.toUpperCase();
    
    if (!this.tokenContracts.has(upperCoin)) {
      throw new Error(`Token ${upperCoin} not supported`);
    }

    const contract = this.tokenContracts.get(upperCoin)!;
    const balance = await contract.balanceOf(address);
    return ethers.formatEther(balance);
  }

  /**
   * Get all token balances for an address
   */
  async getAllBalances(address: string): Promise<Record<string, string>> {
    const balances: Record<string, string> = {};

    for (const [symbol, contract] of this.tokenContracts) {
      try {
        const balance = await contract.balanceOf(address);
        balances[symbol] = ethers.formatEther(balance);
      } catch (e) {
        console.error(`[Faucet] Failed to get ${symbol} balance:`, e);
        balances[symbol] = '0';
      }
    }

    return balances;
  }

  /**
   * Get faucet wallet address
   */
  getWalletAddress(): string {
    return this.wallet.address;
  }

  /**
   * Get supported tokens
   */
  getSupportedTokens(): string[] {
    return Array.from(this.tokenContracts.keys());
  }

  /**
   * Get token addresses
   */
  getTokenAddresses(): TokenAddresses {
    return this.tokenAddresses;
  }
}

// Singleton instance
let faucetService: FaucetService | null = null;

export function initializeFaucetService(): FaucetService | null {
  const rpcUrl = process.env.LISK_SEPOLIA_RPC || 'https://rpc.sepolia-api.lisk.com';
  const privateKey = process.env.FAUCET_PRIVATE_KEY || process.env.HOT_WALLET_PRIVATE_KEY || '';
  
  // Token addresses on Lisk Sepolia testnet
  const tokenAddresses: TokenAddresses = {
    LSK: process.env.MOCK_LSK_ADDRESS || '0xe8c03294be6180BeDFdbF569F14851B734fcf70B',
    ETH: process.env.MOCK_ETH_ADDRESS || '0x292D54495d4C9Af56D86fA6cAF25591037EF80b3',
    POL: process.env.MOCK_POL_ADDRESS || '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e',
  };

  if (!privateKey) {
    console.warn('[Faucet] No private key configured. Faucet service disabled.');
    return null;
  }

  try {
    faucetService = new FaucetService({
      rpcUrl,
      privateKey,
      tokenAddresses,
    });
    console.log('[Faucet] Service initialized successfully');
    console.log(`[Faucet] Wallet: ${faucetService.getWalletAddress()}`);
    console.log(`[Faucet] Supported tokens: ${faucetService.getSupportedTokens().join(', ')}`);
    return faucetService;
  } catch (e) {
    console.error('[Faucet] Failed to initialize:', e);
    return null;
  }
}

export function getFaucetService(): FaucetService | null {
  return faucetService;
}
