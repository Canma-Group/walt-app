import { ethers } from 'ethers';
import crypto from 'crypto';

// WaltQRPayV3 ABI
const WALTQRPAY_V3_ABI = [
  'function pay(bytes32 orderId, string merchantId, address token, uint256 totalAmount) external',
  'function release(bytes32 orderId) external',
  'function refund(bytes32 orderId, string reason) external',
  'function dispute(bytes32 orderId, string reason) external',
  'function claimExpiredRefund(bytes32 orderId) external',
  'function getPayment(bytes32 orderId) external view returns (tuple(bytes32 orderId, string merchantId, address buyer, address token, uint256 merchantAmount, uint256 platformFee, uint256 totalPaid, uint256 lockedAt, uint256 expiresAt, uint8 status))',
  'function getStatistics() external view returns (tuple(uint256 totalPayments, uint256 totalReleased, uint256 totalRefunded, uint256 totalDisputed, uint256 totalFeesCollected, uint256 totalVolume))',
  'function isTokenWhitelisted(address token) external view returns (bool)',
  'function platformFeeBps() external view returns (uint256)',
  'function paymentTimeout() external view returns (uint256)',
  'function getVersion() external pure returns (string)',
  'event PaymentCreated(bytes32 indexed orderId, string merchantId, address indexed buyer, address indexed token, uint256 merchantAmount, uint256 platformFee, uint256 totalPaid, uint256 expiresAt)',
  'event PaymentReleased(bytes32 indexed orderId, uint256 amount, address indexed recipient)',
];

// Supported tokens
export interface TokenInfo {
  address: string;
  symbol: string;
  decimals: number;
  priceIdr: number; // Fallback price
}

export const SUPPORTED_TOKENS: Record<string, TokenInfo> = {
  LSK: {
    address: process.env.MOCK_LSK_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e',
    symbol: 'LSK',
    decimals: 18,
    priceIdr: 3500, // ~$0.22 USD
  },
  ETH: {
    address: process.env.MOCK_ETH_ADDRESS || '0x292D54495d4C9Af56D86fA6cAF25591037EF80b3',
    symbol: 'ETH',
    decimals: 18,
    priceIdr: 55000000, // ~$3400 USD
  },
  POL: {
    address: process.env.MOCK_POL_ADDRESS || '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e',
    symbol: 'POL',
    decimals: 18,
    priceIdr: 2300, // ~$0.14 USD (ex-MATIC)
  },
};

export interface CreatePaymentRequest {
  walletAddress: string;
  qrisPayload: string;
  amountIdr: number;
  tokenSymbol: string; // LSK, ETH, or POL
}

export interface CreatePaymentResponse {
  paymentId: string;
  orderId: string;
  contractAddress: string;
  token: TokenInfo;
  amountIdr: number;
  tokenAmount: string;
  tokenAmountWei: string;
  chainId: number;
  expiresAt: Date;
  platformFeeBps: number;
  merchantId: string;
  merchantName: string;
}

export class WaltQRPayV3Service {
  private provider: ethers.JsonRpcProvider;
  private operatorWallet: ethers.Wallet;
  private contract: ethers.Contract;
  private contractAddress: string;
  private chainId: number;

  constructor() {
    const rpcUrl = process.env.LISK_RPC_URL || 'https://rpc.sepolia-api.lisk.com';
    const contractAddress = process.env.WALTQRPAY_V3_ADDRESS;
    const operatorKey = process.env.HOT_WALLET_PRIVATE_KEY;

    if (!contractAddress) {
      throw new Error('WALTQRPAY_V3_ADDRESS not configured');
    }
    if (!operatorKey) {
      throw new Error('HOT_WALLET_PRIVATE_KEY not configured');
    }

    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.operatorWallet = new ethers.Wallet(operatorKey, this.provider);
    this.contract = new ethers.Contract(contractAddress, WALTQRPAY_V3_ABI, this.operatorWallet);
    this.contractAddress = contractAddress;
    this.chainId = parseInt(process.env.LISK_CHAIN_ID || '4202');

    console.log(`[WaltQRPayV3] Initialized`);
    console.log(`  Contract: ${contractAddress}`);
    console.log(`  Operator: ${this.operatorWallet.address}`);
    console.log(`  Supported Tokens: LSK, ETH, POL`);
  }

  // Generate bytes32 orderId from paymentId
  private generateOrderId(paymentId: string): string {
    return ethers.keccak256(ethers.toUtf8Bytes(paymentId));
  }

  // Parse merchant name from QRIS
  private parseMerchantName(qrisPayload: string): string {
    try {
      const tag59Match = qrisPayload.match(/59(\d{2})([^\d]{2,})/);
      if (tag59Match) {
        const length = parseInt(tag59Match[1]);
        return tag59Match[2].substring(0, length);
      }
    } catch (e) {
      console.error('Error parsing merchant name:', e);
    }
    return 'QRIS Merchant';
  }

  // Parse merchant ID from QRIS
  private parseMerchantId(qrisPayload: string): string {
    const qrisHash = crypto.createHash('sha256').update(qrisPayload).digest('hex');
    return qrisHash.substring(0, 16);
  }

  // Get token price in IDR using CoinGecko API (more accurate real-time prices)
  async getTokenPriceIdr(symbol: string): Promise<number> {
    const token = SUPPORTED_TOKENS[symbol.toUpperCase()];
    if (!token) return 3200;

    // CoinGecko ID mapping
    const coinGeckoIds: Record<string, string> = {
      'LSK': 'lisk',
      'ETH': 'ethereum',
      'POL': 'matic-network', // POL (ex-MATIC)
    };

    const coinId = coinGeckoIds[symbol.toUpperCase()];
    
    // Try CoinGecko API first (more accurate global prices)
    try {
      const response = await fetch(
        `https://api.coingecko.com/api/v3/simple/price?ids=${coinId}&vs_currencies=idr`,
        { headers: { 'Accept': 'application/json' } }
      );
      if (response.ok) {
        const data = await response.json();
        if (data[coinId]?.idr) {
          const price = Math.round(data[coinId].idr);
          console.log(`[WaltQRPayV3] CoinGecko ${symbol} price: Rp ${price}`);
          return price;
        }
      }
    } catch (e) {
      console.log(`[WaltQRPayV3] CoinGecko failed for ${symbol}, trying Indodax...`);
    }

    // Fallback to Indodax
    const indodaxPairs: Record<string, string> = {
      'LSK': 'lsk_idr',
      'ETH': 'eth_idr',
      'POL': 'matic_idr',
    };
    const pair = indodaxPairs[symbol.toUpperCase()];
    
    try {
      const response = await fetch(`https://indodax.com/api/ticker/${pair}`);
      if (response.ok) {
        const data = await response.json();
        if (data.ticker?.last) {
          const price = parseFloat(data.ticker.last);
          console.log(`[WaltQRPayV3] Indodax ${symbol} price: Rp ${price}`);
          return price;
        }
      }
    } catch (e) {
      console.log(`[WaltQRPayV3] Indodax also failed for ${symbol}, using fallback`);
    }
    
    // Fallback prices
    console.log(`[WaltQRPayV3] Using fallback price for ${symbol}: Rp ${token.priceIdr}`);
    return token.priceIdr;
  }

  // Create payment intent
  async createPayment(req: CreatePaymentRequest): Promise<CreatePaymentResponse> {
    const tokenKey = req.tokenSymbol.toUpperCase();
    const token = SUPPORTED_TOKENS[tokenKey];
    
    if (!token) {
      throw new Error(`Token ${req.tokenSymbol} not supported. Use LSK, ETH, or POL`);
    }

    // Verify token is whitelisted on contract
    const isWhitelisted = await this.contract.isTokenWhitelisted(token.address);
    if (!isWhitelisted) {
      throw new Error(`Token ${req.tokenSymbol} is not whitelisted on contract`);
    }

    const paymentId = crypto.randomUUID();
    const orderId = this.generateOrderId(paymentId);

    // Get token price from Indodax
    const tokenPriceIdr = await this.getTokenPriceIdr(tokenKey);
    
    // Calculate token amount with 1% platform fee included
    // Total = merchant amount + platform fee (1%)
    // So if merchant needs 2000 IDR, user pays 2000 / 0.99 = ~2020.20 IDR worth of tokens
    const platformFeePercent = 0.01; // 1%
    const totalAmountIdr = req.amountIdr / (1 - platformFeePercent);
    const tokenAmount = totalAmountIdr / tokenPriceIdr;
    const tokenAmountWei = ethers.parseUnits(tokenAmount.toFixed(8), token.decimals).toString();

    // Get contract config
    const platformFeeBps = await this.contract.platformFeeBps();
    const timeoutSeconds = await this.contract.paymentTimeout();
    const expiresAt = new Date(Date.now() + Number(timeoutSeconds) * 1000);

    // Parse merchant info
    const merchantName = this.parseMerchantName(req.qrisPayload);
    const merchantId = this.parseMerchantId(req.qrisPayload);

    console.log(`[WaltQRPayV3] Payment created: ${paymentId}`);
    console.log(`  Token: ${token.symbol} (${token.address})`);
    console.log(`  Price: Rp ${tokenPriceIdr} per ${token.symbol} (Indodax)`);
    console.log(`  Merchant Amount: Rp ${req.amountIdr}`);
    console.log(`  Total with Fee: Rp ${totalAmountIdr.toFixed(2)} (+1% platform fee)`);
    console.log(`  Token Amount: ${tokenAmount.toFixed(8)} ${token.symbol}`);
    console.log(`  Merchant: ${merchantName}`);

    return {
      paymentId,
      orderId,
      contractAddress: this.contractAddress,
      token,
      amountIdr: req.amountIdr,
      tokenAmount: tokenAmount.toFixed(8),
      tokenAmountWei,
      chainId: this.chainId,
      expiresAt,
      platformFeeBps: Number(platformFeeBps),
      merchantId,
      merchantName,
    };
  }

  // Generate calldata for pay function
  generatePayCalldata(orderId: string, merchantId: string, tokenAddress: string, amountWei: string): string {
    const iface = new ethers.Interface(WALTQRPAY_V3_ABI);
    return iface.encodeFunctionData('pay', [orderId, merchantId, tokenAddress, amountWei]);
  }

  // Check if token is whitelisted on contract
  async isTokenWhitelisted(tokenAddress: string): Promise<boolean> {
    try {
      const isWhitelisted = await this.contract.isTokenWhitelisted(tokenAddress);
      return isWhitelisted;
    } catch (e) {
      console.error(`[WaltQRPayV3] Error checking whitelist:`, e);
      return false;
    }
  }

  // Whitelist a token (admin only)
  async whitelistToken(tokenAddress: string, status: boolean): Promise<string> {
    try {
      console.log(`[WaltQRPayV3] Whitelisting token ${tokenAddress}: ${status}`);
      const tx = await this.contract.setTokenWhitelist(tokenAddress, status);
      const receipt = await tx.wait();
      console.log(`[WaltQRPayV3] Token whitelisted! TxHash: ${receipt.hash}`);
      return receipt.hash;
    } catch (e: any) {
      console.error(`[WaltQRPayV3] Error whitelisting token:`, e.message);
      throw e;
    }
  }

  // Whitelist all supported tokens
  async whitelistAllTokens(): Promise<Record<string, string>> {
    const results: Record<string, string> = {};
    for (const [symbol, token] of Object.entries(SUPPORTED_TOKENS)) {
      try {
        const isWhitelisted = await this.isTokenWhitelisted(token.address);
        if (!isWhitelisted) {
          const txHash = await this.whitelistToken(token.address, true);
          results[symbol] = txHash;
        } else {
          results[symbol] = 'already-whitelisted';
        }
      } catch (e: any) {
        results[symbol] = `error: ${e.message}`;
      }
    }
    return results;
  }

  // Verify transaction on-chain
  async verifyTransaction(txHash: string): Promise<any> {
    try {
      const receipt = await this.provider.getTransactionReceipt(txHash);
      const tx = await this.provider.getTransaction(txHash);
      
      if (!receipt || !tx) {
        return { exists: false, error: 'Transaction not found' };
      }

      // Check for PaymentCreated event in logs
      let hasPaymentCreatedEvent = false;
      let eventOrderId = '';
      
      if (receipt.logs && receipt.logs.length > 0) {
        // PaymentCreated event signature
        const paymentCreatedTopic = ethers.id('PaymentCreated(bytes32,string,address,address,uint256,uint256,uint256,uint256)');
        
        for (const log of receipt.logs) {
          if (log.topics[0] === paymentCreatedTopic) {
            hasPaymentCreatedEvent = true;
            eventOrderId = log.topics[1] || '';
            break;
          }
        }
      }

      return {
        exists: true,
        status: receipt.status === 1 ? 'SUCCESS' : 'FAILED',
        to: tx.to,
        from: tx.from,
        data: tx.data?.substring(0, 74) + '...', // First 74 chars (function selector + first param)
        contractAddress: this.contractAddress,
        isCorrectContract: tx.to?.toLowerCase() === this.contractAddress.toLowerCase(),
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        logsCount: receipt.logs?.length || 0,
        hasPaymentCreatedEvent,
        eventOrderId: eventOrderId.substring(0, 20) + '...',
      };
    } catch (e: any) {
      return { exists: false, error: e.message };
    }
  }

  // Get payment by orderId directly (for debugging)
  async getPaymentByOrderId(orderId: string): Promise<any> {
    try {
      console.log(`[WaltQRPayV3] Querying payment with orderId: ${orderId}`);
      const payment = await this.contract.getPayment(orderId);
      const statusMap = ['NONE', 'LOCKED', 'RELEASED', 'REFUNDED', 'DISPUTED', 'EXPIRED'];
      return {
        orderId: payment.orderId,
        status: statusMap[Number(payment.status)],
        statusNum: Number(payment.status),
      };
    } catch (e: any) {
      console.error(`[WaltQRPayV3] Error querying by orderId:`, e.message);
      return null;
    }
  }

  // Get payment status from contract
  async getPaymentFromContract(paymentId: string): Promise<any> {
    try {
      const orderId = this.generateOrderId(paymentId);
      console.log(`[WaltQRPayV3] Generated orderId for query: ${orderId}`);
      const payment = await this.contract.getPayment(orderId);

      const statusMap = ['NONE', 'LOCKED', 'RELEASED', 'REFUNDED', 'DISPUTED', 'EXPIRED'];

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
      console.error(`[WaltQRPayV3] Error getting payment:`, e);
      return null;
    }
  }

  // Release payment (operator) - checks status first to avoid errors
  async releasePayment(paymentId: string): Promise<string> {
    const orderId = this.generateOrderId(paymentId);
    console.log(`[WaltQRPayV3] Releasing payment: ${paymentId}`);

    // Check payment status first
    const payment = await this.getPaymentFromContract(paymentId);
    if (!payment) {
      throw new Error(`Payment ${paymentId} not found on contract`);
    }
    
    if (payment.status === 'RELEASED') {
      console.log(`[WaltQRPayV3] Payment already RELEASED, skipping`);
      return 'already-released';
    }
    
    if (payment.status !== 'LOCKED') {
      throw new Error(`Payment status is ${payment.status}, expected LOCKED`);
    }

    const tx = await this.contract.release(orderId);
    const receipt = await tx.wait();

    console.log(`[WaltQRPayV3] Payment released! TxHash: ${receipt.hash}`);
    return receipt.hash;
  }

  // Refund payment (operator)
  async refundPayment(paymentId: string, reason: string): Promise<string> {
    const orderId = this.generateOrderId(paymentId);
    console.log(`[WaltQRPayV3] Refunding payment: ${paymentId}`);

    const tx = await this.contract.refund(orderId, reason);
    const receipt = await tx.wait();

    console.log(`[WaltQRPayV3] Payment refunded! TxHash: ${receipt.hash}`);
    return receipt.hash;
  }

  // Get statistics
  async getStatistics(): Promise<any> {
    const stats = await this.contract.getStatistics();
    return {
      totalPayments: Number(stats.totalPayments),
      totalReleased: Number(stats.totalReleased),
      totalRefunded: Number(stats.totalRefunded),
      totalDisputed: Number(stats.totalDisputed),
      totalFeesCollected: ethers.formatEther(stats.totalFeesCollected),
      totalVolume: ethers.formatEther(stats.totalVolume),
    };
  }

  // Get version
  async getVersion(): Promise<string> {
    return await this.contract.getVersion();
  }

  // Get contract address
  getContractAddress(): string {
    return this.contractAddress;
  }

  // Get supported tokens
  getSupportedTokens(): Record<string, TokenInfo> {
    return SUPPORTED_TOKENS;
  }
}
