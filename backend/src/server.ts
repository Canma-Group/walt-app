import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { ethers } from 'ethers';
import { db } from './db/database';
import { db as firestore } from './config/firebase';
import { QrisPaymentServiceDB } from './services/qrisPaymentServiceDB';
import { DepositVerifierDB } from './services/depositVerifierDB';
import { fetchPricesIDR, fetchPricesFromIndodax } from './services/priceService';
import { createPaymentOrchestrator, PaymentOrchestrator } from './services/paymentOrchestrator';
import { GasSponsorshipService } from './services/gasSponsorshipService';
import { QrisEscrowV2Service } from './services/qrisEscrowV2Service';
import { getNfcVoucherService, NFC_VAULT_ADDRESSES } from './services/nfcVoucherService';
import { initializeFaucetService, getFaucetService } from './services/faucetService';
import { initializeSwapService, getSwapService } from './services/swapService';
import * as admin from 'firebase-admin';

// Load environment variables
dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

// Middleware
app.use(cors());
app.use(express.json());

// Initialize QRIS Payment Service
const escrowMasterMnemonic = process.env.ESCROW_MASTER_MNEMONIC || '';
const hotWalletPrivateKey = process.env.HOT_WALLET_PRIVATE_KEY || '';
let qrisPaymentService: QrisPaymentServiceDB | null = null;
let qrisEscrowV2: QrisEscrowV2Service | null = null;
let depositVerifier: DepositVerifierDB | null = null;
let paymentOrchestrator: PaymentOrchestrator | null = null;
let gasSponsorshipService: GasSponsorshipService | null = null;

// Health check
app.get('/health', async (req, res) => {
  let hotWalletStatus = { address: '', balance: '0', sufficient: false };
  if (gasSponsorshipService) {
    const balance = await gasSponsorshipService.getHotWalletBalance();
    hotWalletStatus = {
      address: gasSponsorshipService.getHotWalletAddress(),
      balance: balance.eth,
      sufficient: balance.sufficient,
    };
  }
  
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    qrisServiceReady: qrisPaymentService !== null,
    qrisEscrowV2Ready: qrisEscrowV2 !== null,
    orchestratorReady: paymentOrchestrator !== null,
    gasSponsorshipReady: gasSponsorshipService !== null,
    hotWallet: hotWalletStatus,
    escrowV2: qrisEscrowV2 ? {
      address: qrisEscrowV2.getEscrowAddress(),
      operator: qrisEscrowV2.getOperatorAddress(),
    } : null,
    version: '2.2.0-escrow-v2',
    note: 'Crypto-to-Fiat Payment System with QrisEscrowV2',
  });
});

// ============ PRICE API (Proxy to Indodax) ============
// Phone fetches prices from backend since it can't reach Indodax directly

app.get('/prices', async (req, res) => {
  try {
    const pricesIDR = await fetchPricesFromIndodax();
    
    return res.status(200).json({
      success: true,
      timestamp: new Date().toISOString(),
      source: 'indodax',
      prices: pricesIDR,
    });
  } catch (error) {
    console.error('[Prices] Error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to fetch prices',
    });
  }
});

app.get('/prices/:symbol', async (req, res) => {
  try {
    const { symbol } = req.params;
    const pricesIDR = await fetchPricesFromIndodax();
    const price = pricesIDR[symbol.toUpperCase()];
    
    if (!price) {
      return res.status(404).json({
        success: false,
        error: `Price not found for ${symbol}`,
      });
    }
    
    return res.status(200).json({
      success: true,
      timestamp: new Date().toISOString(),
      symbol: symbol.toUpperCase(),
      priceIDR: price,
    });
  } catch (error) {
    console.error('[Prices] Error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to fetch price',
    });
  }
});

// ============ FAUCET API (Private Mock Token Minting) ============

// Mint mock tokens (LSK, ETH, POL) - unlimited for testing
app.post('/faucet/mint', async (req, res) => {
  try {
    const faucet = getFaucetService();
    if (!faucet) {
      return res.status(503).json({
        success: false,
        error: 'Faucet service not initialized. Check FAUCET_PRIVATE_KEY.',
      });
    }

    const { walletAddress, coin, amountIdr } = req.body;

    if (!walletAddress || !coin || !amountIdr) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress, coin, and amountIdr are required',
      });
    }

    if (!ethers.isAddress(walletAddress)) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress is not a valid Ethereum address',
      });
    }

    if (typeof amountIdr !== 'number' || !Number.isFinite(amountIdr) || amountIdr <= 0) {
      return res.status(400).json({
        success: false,
        error: 'amountIdr must be a positive number',
      });
    }

    // Validate coin
    const supportedCoins = faucet.getSupportedTokens();
    if (!supportedCoins.includes(coin.toUpperCase())) {
      return res.status(400).json({
        success: false,
        error: `Coin ${coin} not supported. Available: ${supportedCoins.join(', ')}`,
      });
    }

    const result = await faucet.mintTokens(walletAddress, coin, amountIdr);

    return res.status(200).json({
      success: true,
      data: result,
    });
  } catch (error) {
    console.error('[Faucet] Mint error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to mint tokens',
    });
  }
});

// Get faucet status
app.get('/faucet/status', async (req, res) => {
  try {
    const faucet = getFaucetService();
    if (!faucet) {
      return res.status(503).json({
        success: false,
        error: 'Faucet service not initialized',
      });
    }

    return res.status(200).json({
      success: true,
      data: {
        wallet: faucet.getWalletAddress(),
        supportedTokens: faucet.getSupportedTokens(),
        tokenAddresses: faucet.getTokenAddresses(),
      },
    });
  } catch (error) {
    console.error('[Faucet] Status error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get faucet status',
    });
  }
});

// Get token balances for an address
app.get('/faucet/balance/:walletAddress', async (req, res) => {
  try {
    const faucet = getFaucetService();
    if (!faucet) {
      return res.status(503).json({
        success: false,
        error: 'Faucet service not initialized',
      });
    }

    const { walletAddress } = req.params;
    const balances = await faucet.getAllBalances(walletAddress);

    return res.status(200).json({
      success: true,
      data: {
        address: walletAddress,
        balances,
      },
    });
  } catch (error) {
    console.error('[Faucet] Balance error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get balances',
    });
  }
});

// QRIS Payment Endpoints
app.post('/qris/payments', async (req, res) => {
  try {
    if (!qrisPaymentService) {
      return res.status(503).json({
        success: false,
        error: 'QRIS payment service not initialized. Check ESCROW_MASTER_MNEMONIC.',
      });
    }

    const { walletAddress, qrisPayload, amountIdr } = req.body;

    if (!walletAddress || !qrisPayload || !amountIdr) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress, qrisPayload, and amountIdr are required',
      });
    }

    if (!ethers.isAddress(walletAddress)) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress is not a valid Ethereum address',
      });
    }

    if (typeof amountIdr !== 'number' || !Number.isFinite(amountIdr) || amountIdr <= 0) {
      return res.status(400).json({
        success: false,
        error: 'amountIdr must be a positive number',
      });
    }

    // Get current LSK price in IDR
    const pricesIdr = await fetchPricesIDR(['LSK']);
    const lskPriceIdr = pricesIdr.LSK;

    if (!lskPriceIdr || lskPriceIdr <= 0) {
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch LSK price',
      });
    }

    const payment = await qrisPaymentService.createPayment(
      { walletAddress, qrisPayload, amountIdr },
      lskPriceIdr
    );

    return res.status(200).json({
      success: true,
      data: payment,
    });
  } catch (error) {
    console.error('[QRIS] Create payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to create payment',
    });
  }
});

app.get('/qris/payments/:paymentId', async (req, res) => {
  try {
    if (!qrisPaymentService) {
      return res.status(503).json({
        success: false,
        error: 'QRIS payment service not initialized',
      });
    }

    const { paymentId } = req.params;
    const payment = await qrisPaymentService.getPayment(paymentId);

    if (!payment) {
      return res.status(404).json({
        success: false,
        error: 'Payment not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: payment,
    });
  } catch (error) {
    console.error('[QRIS] Get payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get payment',
    });
  }
});

app.post('/qris/payments/:paymentId/tx', async (req, res) => {
  try {
    if (!qrisPaymentService) {
      return res.status(503).json({
        success: false,
        error: 'QRIS payment service not initialized',
      });
    }

    const { paymentId } = req.params;
    const { txHash } = req.body;

    if (!txHash) {
      return res.status(400).json({
        success: false,
        error: 'txHash is required',
      });
    }

    const payment = await qrisPaymentService.submitTxHash(paymentId, txHash);

    // Create transaction history record
    try {
      await db.createTransactionHistory({
        payment_id: paymentId,
        wallet_address: payment.payer_wallet_address,
        merchant_name: payment.merchant_name,
        amount_idr: payment.amount_idr,
        lsk_amount: payment.lsk_amount_expected,
        tx_hash: txHash,
        status: 'PENDING',
      });
    } catch (e) {
      console.error('[QRIS] Failed to create transaction history:', e);
    }

    return res.status(200).json({
      success: true,
      data: payment,
    });
  } catch (error) {
    console.error('[QRIS] Submit tx error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to submit transaction',
    });
  }
});

// Generate ABI-encoded calldata for pay() function
app.post('/qris/payments/:paymentId/calldata', async (req, res) => {
  try {
    const { paymentId } = req.params;
    const { merchantId } = req.body;
    
    const payment = await db.getPaymentIntent(paymentId);
    if (!payment) {
      return res.status(404).json({ success: false, error: 'Payment not found' });
    }
    
    // Generate orderId using keccak256 (same as contract expects)
    const orderId = ethers.keccak256(ethers.toUtf8Bytes(paymentId));
    
    // Parse amount to wei
    const amountWei = ethers.parseUnits(payment.lsk_amount_expected, 18);
    
    // ABI encode the pay() function call using ethers.js
    const iface = new ethers.Interface([
      'function pay(bytes32 orderId, string merchantId, uint256 totalAmount)'
    ]);
    
    const calldata = iface.encodeFunctionData('pay', [
      orderId,
      merchantId || payment.merchant_name || 'QRIS',
      amountWei
    ]);
    
    console.log(`[QRIS] Generated calldata for payment ${paymentId}`);
    console.log(`  OrderId: ${orderId}`);
    console.log(`  Amount: ${amountWei.toString()} wei`);
    
    return res.status(200).json({
      success: true,
      data: {
        calldata,
        orderId,
        amountWei: amountWei.toString(),
        escrowAddress: process.env.QRIS_ESCROW_V2_ADDRESS || '0xda7c9CF0988547d6F88899A3a822630bAD52060d',
        tokenAddress: process.env.LSK_TOKEN_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e',
      }
    });
  } catch (error) {
    console.error('[QRIS] Generate calldata error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to generate calldata',
    });
  }
});

// ============ GAS SPONSORSHIP ENDPOINTS ============

// Check if user needs gas sponsorship
app.get('/qris/gas-check/:walletAddress', async (req, res) => {
  try {
    if (!gasSponsorshipService) {
      return res.status(503).json({
        success: false,
        error: 'Gas sponsorship service not initialized. Check HOT_WALLET_PRIVATE_KEY.',
      });
    }

    const { walletAddress } = req.params;
    
    const needsGas = await gasSponsorshipService.needsGasSponsorship(walletAddress);
    const gasEstimate = await gasSponsorshipService.estimateGasCost();
    const gasCostIdr = await gasSponsorshipService.calculateGasCostIdr(gasEstimate.gasEth);
    
    return res.status(200).json({
      success: true,
      data: {
        walletAddress,
        needsGasSponsorship: needsGas,
        estimatedGasEth: gasEstimate.gasEth,
        estimatedGasCostIdr: gasCostIdr,
        gasPriceGwei: gasEstimate.gasPriceGwei,
      },
    });
  } catch (error) {
    console.error('[GasSponsorship] Check error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to check gas status',
    });
  }
});

// Request gas sponsorship for a payment
app.post('/qris/sponsor-gas', async (req, res) => {
  try {
    if (!gasSponsorshipService) {
      return res.status(503).json({
        success: false,
        error: 'Gas sponsorship service not initialized. Check HOT_WALLET_PRIVATE_KEY.',
      });
    }

    const { walletAddress, paymentId, escrowAddress, lskAmount } = req.body;

    if (!walletAddress || !paymentId || !escrowAddress || !lskAmount) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress, paymentId, escrowAddress, and lskAmount are required',
      });
    }

    // Verify payment exists and is pending
    if (qrisPaymentService) {
      const payment = await qrisPaymentService.getPayment(paymentId);
      if (!payment) {
        return res.status(404).json({
          success: false,
          error: 'Payment not found',
        });
      }
      if (payment.status !== 'CREATED') {
        return res.status(400).json({
          success: false,
          error: `Payment is not in CREATED state (status: ${payment.status})`,
        });
      }
    }

    console.log(`[GasSponsorship] Processing request for payment ${paymentId}`);

    const result = await gasSponsorshipService.sponsorGas({
      walletAddress,
      paymentId,
      escrowAddress,
      lskAmount,
    });

    if (!result.success) {
      return res.status(400).json({
        success: false,
        error: result.error,
      });
    }

    return res.status(200).json({
      success: true,
      data: {
        txHash: result.txHash,
        gasAmountEth: result.gasAmountEth,
        gasCostIdr: result.gasCostIdr,
        message: result.txHash === 'NOT_NEEDED' 
          ? 'User already has sufficient gas' 
          : 'Gas sponsored successfully',
      },
    });
  } catch (error) {
    console.error('[GasSponsorship] Sponsor error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to sponsor gas',
    });
  }
});

// ============ SIMPLE GAS SPONSORSHIP (for transfer page) ============
app.post('/gas/sponsor', async (req, res) => {
  try {
    if (!gasSponsorshipService) {
      return res.status(503).json({
        success: false,
        error: 'Gas sponsorship service not initialized',
      });
    }

    const { walletAddress } = req.body;

    if (!walletAddress) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress is required',
      });
    }

    console.log(`[GasSponsorship] Simple sponsor request for: ${walletAddress}`);

    // Use a simplified version - just send gas directly
    const result = await gasSponsorshipService.sponsorGas({
      walletAddress,
      paymentId: 'TRANSFER_' + Date.now(),
      escrowAddress: walletAddress, // Not used for simple transfer
      lskAmount: '0', // Not checking LSK for simple transfer
    });

    if (!result.success && result.error !== 'Insufficient LSK balance for payment') {
      return res.status(400).json({
        success: false,
        error: result.error,
      });
    }

    return res.status(200).json({
      success: true,
      txHash: result.txHash || 'SPONSORED',
      gasAmountEth: result.gasAmountEth || '0.0001',
    });
  } catch (error) {
    console.error('[GasSponsorship] Simple sponsor error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to sponsor gas',
    });
  }
});

// ============ TOP UP SIMULATION (for hackathon demo) ============
// Mints MockLSK tokens directly to user wallet using the mint() function
app.post('/topup/simulate', async (req, res) => {
  try {
    const { walletAddress, amountLsk, amountIdr } = req.body;

    if (!walletAddress || !amountLsk) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress and amountLsk are required',
      });
    }

    console.log(`[TopUp] Minting ${amountLsk} LSK to ${walletAddress}`);

    if (!hotWalletPrivateKey) {
      return res.status(503).json({
        success: false,
        error: 'Hot wallet not configured for top-up simulation',
      });
    }

    const { ethers } = await import('ethers');
    const provider = new ethers.JsonRpcProvider('https://rpc.sepolia-api.lisk.com');
    const hotWallet = new ethers.Wallet(hotWalletPrivateKey, provider);
    
    const mockLskAddress = process.env.LSK_TOKEN_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';
    
    // MockLSK contract has a public mint() function anyone can call
    const mockLskContract = new ethers.Contract(
      mockLskAddress,
      [
        'function mint(address to, uint256 amount) external',
        'function balanceOf(address) view returns (uint256)',
      ],
      hotWallet
    );

    // Convert amount to wei (18 decimals)
    const amountWei = ethers.parseEther(amountLsk.toString());
    
    // Check user's balance before
    const balanceBefore = await mockLskContract.balanceOf(walletAddress);
    console.log(`[TopUp] User balance before: ${ethers.formatEther(balanceBefore)} LSK`);

    // Mint MockLSK tokens directly to user wallet
    console.log(`[TopUp] Calling mint(${walletAddress}, ${amountWei})...`);
    const tx = await mockLskContract.mint(walletAddress, amountWei);
    console.log(`[TopUp] Transaction sent: ${tx.hash}`);
    
    const receipt = await tx.wait();
    
    if (!receipt || receipt.status !== 1) {
      return res.status(500).json({
        success: false,
        error: 'Mint transaction failed',
      });
    }

    // Check user's balance after
    const balanceAfter = await mockLskContract.balanceOf(walletAddress);
    console.log(`[TopUp] User balance after: ${ethers.formatEther(balanceAfter)} LSK`);
    console.log(`[TopUp] Success! Minted ${amountLsk} LSK to ${walletAddress}`);

    return res.status(200).json({
      success: true,
      txHash: tx.hash,
      amountLsk: amountLsk,
      amountIdr: amountIdr || 0,
      balanceBefore: ethers.formatEther(balanceBefore),
      balanceAfter: ethers.formatEther(balanceAfter),
      message: 'Top-up simulation successful - tokens minted to your wallet!',
    });
  } catch (error) {
    console.error('[TopUp] Simulation error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Top-up simulation failed',
    });
  }
});

// Calculate admin fee for a payment
app.post('/qris/calculate-fee', async (req, res) => {
  try {
    if (!gasSponsorshipService) {
      return res.status(503).json({
        success: false,
        error: 'Gas sponsorship service not initialized',
      });
    }

    const { amountIdr, gasEth } = req.body;

    if (!amountIdr) {
      return res.status(400).json({
        success: false,
        error: 'amountIdr is required',
      });
    }

    const gasAmount = gasEth || '0';
    const feeResult = await gasSponsorshipService.calculateAdminFee(amountIdr, gasAmount);

    return res.status(200).json({
      success: true,
      data: {
        amountIdr,
        baseFeePercent: feeResult.baseFeePercent * 100, // Convert to percentage
        baseFeeIdr: feeResult.baseFeeIdr,
        gasCostIdr: feeResult.gasCostIdr,
        totalAdminFeeIdr: feeResult.totalAdminFeeIdr,
        totalWithFeeIdr: amountIdr + feeResult.totalAdminFeeIdr,
      },
    });
  } catch (error) {
    console.error('[Fee] Calculate error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to calculate fee',
    });
  }
});

// ============ QRIS Escrow V2 Endpoints ============

// Create payment with V2 escrow contract
app.post('/qris/v2/payments', async (req, res) => {
  try {
    if (!qrisEscrowV2) {
      return res.status(503).json({
        success: false,
        error: 'QrisEscrowV2 service not initialized',
      });
    }

    const { walletAddress, qrisPayload, amountIdr } = req.body;

    if (!walletAddress || !qrisPayload || !amountIdr) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress, qrisPayload, and amountIdr are required',
      });
    }

    // Get LSK price
    const prices = await fetchPricesFromIndodax();
    const lskPriceIdr = prices['lsk'] || 3200;

    const payment = await qrisEscrowV2.createPayment(
      { walletAddress, qrisPayload, amountIdr },
      lskPriceIdr
    );

    return res.status(201).json({
      success: true,
      data: {
        paymentId: payment.paymentId,
        orderId: payment.orderId,
        escrowAddress: payment.escrowAddress,
        amountIdr: payment.amountIdr,
        lskAmountExpected: payment.lskAmountExpected,
        lskTokenAddress: payment.lskTokenAddress,
        chainId: payment.chainId,
        expiresAt: payment.expiresAt.toISOString(),
        platformFeeBps: payment.platformFeeBps,
      },
    });
  } catch (error) {
    console.error('[QrisV2] Create payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to create payment',
    });
  }
});

// Get payment status from V2 contract
app.get('/qris/v2/payments/:paymentId', async (req, res) => {
  try {
    if (!qrisEscrowV2) {
      return res.status(503).json({
        success: false,
        error: 'QrisEscrowV2 service not initialized',
      });
    }

    const { paymentId } = req.params;

    // Get from database
    const dbPayment = await qrisEscrowV2.getPayment(paymentId);
    
    // Get from contract if exists
    const contractPayment = await qrisEscrowV2.getPaymentFromContract(paymentId);

    if (!dbPayment && !contractPayment) {
      return res.status(404).json({
        success: false,
        error: 'Payment not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: {
        database: dbPayment,
        contract: contractPayment,
      },
    });
  } catch (error) {
    console.error('[QrisV2] Get payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get payment',
    });
  }
});

// Submit transaction hash for V2 payment
app.post('/qris/v2/payments/:paymentId/tx', async (req, res) => {
  try {
    if (!qrisEscrowV2) {
      return res.status(503).json({
        success: false,
        error: 'QrisEscrowV2 service not initialized',
      });
    }

    const { paymentId } = req.params;
    const { txHash } = req.body;

    if (!txHash) {
      return res.status(400).json({
        success: false,
        error: 'txHash is required',
      });
    }

    const payment = await qrisEscrowV2.submitTxHash(paymentId, txHash);

    return res.status(200).json({
      success: true,
      data: {
        paymentId: payment.payment_id,
        status: payment.status,
        txHash: payment.tx_hash,
      },
    });
  } catch (error) {
    console.error('[QrisV2] Submit tx error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to submit transaction',
    });
  }
});

// Release payment (admin/operator only)
app.post('/qris/v2/payments/:paymentId/release', async (req, res) => {
  try {
    if (!qrisEscrowV2) {
      return res.status(503).json({
        success: false,
        error: 'QrisEscrowV2 service not initialized',
      });
    }

    const { paymentId } = req.params;
    const txHash = await qrisEscrowV2.releasePayment(paymentId);

    return res.status(200).json({
      success: true,
      data: {
        paymentId,
        status: 'RELEASED',
        txHash,
      },
    });
  } catch (error) {
    console.error('[QrisV2] Release error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to release payment',
    });
  }
});

// Refund payment (admin/operator only)
app.post('/qris/v2/payments/:paymentId/refund', async (req, res) => {
  try {
    if (!qrisEscrowV2) {
      return res.status(503).json({
        success: false,
        error: 'QrisEscrowV2 service not initialized',
      });
    }

    const { paymentId } = req.params;
    const { reason } = req.body;

    const txHash = await qrisEscrowV2.refundPayment(paymentId, reason || 'Admin refund');

    return res.status(200).json({
      success: true,
      data: {
        paymentId,
        status: 'REFUNDED',
        txHash,
      },
    });
  } catch (error) {
    console.error('[QrisV2] Refund error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to refund payment',
    });
  }
});

// Get escrow statistics
app.get('/qris/v2/stats', async (req, res) => {
  try {
    if (!qrisEscrowV2) {
      return res.status(503).json({
        success: false,
        error: 'QrisEscrowV2 service not initialized',
      });
    }

    const stats = await qrisEscrowV2.getStatistics();
    const version = await qrisEscrowV2.getVersion();
    const isPaused = await qrisEscrowV2.isPaused();
    const feeBps = await qrisEscrowV2.getPlatformFeeBps();

    return res.status(200).json({
      success: true,
      data: {
        version,
        isPaused,
        platformFeeBps: feeBps,
        platformFeePercent: feeBps / 100,
        escrowAddress: qrisEscrowV2.getEscrowAddress(),
        operatorAddress: qrisEscrowV2.getOperatorAddress(),
        statistics: stats,
      },
    });
  } catch (error) {
    console.error('[QrisV2] Stats error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get statistics',
    });
  }
});

// Transaction History Endpoints
app.get('/transactions/:walletAddress', async (req, res) => {
  try {
    const { walletAddress } = req.params;
    const limit = parseInt(req.query.limit as string) || 50;
    
    const transactions = await db.getTransactionHistory(walletAddress, limit);
    
    return res.status(200).json({
      success: true,
      data: transactions,
    });
  } catch (error) {
    console.error('[Transactions] Error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get transactions',
    });
  }
});

// Merchant Dashboard Endpoints
app.get('/merchant/notifications', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit as string) || 100;
    const notifications = await db.getMerchantNotifications(limit);
    
    return res.status(200).json({
      success: true,
      data: notifications,
    });
  } catch (error) {
    console.error('[Merchant] Error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get notifications',
    });
  }
});

// Serve merchant dashboard HTML
app.get('/merchant', (req, res) => {
  res.send(getMerchantDashboardHTML());
});

// ============ CRYPTO-TO-FIAT PAYMENT SYSTEM v2 ============

// Get order status (v2)
app.get('/v2/orders/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    const order = await db.getOrder(orderId);
    
    if (!order) {
      return res.status(404).json({ success: false, error: 'Order not found' });
    }
    
    // Get related trade info
    const trade = await db.getTradeByOrderId(orderId);
    
    return res.status(200).json({
      success: true,
      data: {
        ...order,
        trade: trade || null,
        isSimulated: true,
        simulationNote: 'HACKATHON MVP - Settlement is simulated',
      },
    });
  } catch (error) {
    console.error('[V2] Get order error:', error);
    return res.status(500).json({ success: false, error: 'Failed to get order' });
  }
});

// Merchant dashboard v2 (with ledger)
app.get('/v2/merchant/:merchantId/dashboard', async (req, res) => {
  try {
    const { merchantId } = req.params;
    
    const balance = await db.getMerchantBalance(merchantId);
    const transactions = await db.getMerchantLedgerHistory(merchantId, 20);
    const isWhitelisted = await db.isMerchantWhitelisted(merchantId);
    
    return res.status(200).json({
      success: true,
      data: {
        merchantId,
        isWhitelisted,
        balance: {
          grossIdr: parseFloat(balance.total_gross?.toString() || '0'),
          platformFeesIdr: parseFloat(balance.total_fees?.toString() || '0'),
          netIdr: parseFloat(balance.total_net?.toString() || '0'),
        },
        recentTransactions: transactions,
        isSimulated: true,
        simulationNote: 'HACKATHON MVP - All settlements are simulated',
      },
    });
  } catch (error) {
    console.error('[V2] Merchant dashboard error:', error);
    return res.status(500).json({ success: false, error: 'Failed to get merchant data' });
  }
});

// Demo endpoint: Process order through full flow
app.post('/v2/demo/process/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    
    if (!paymentOrchestrator) {
      return res.status(503).json({ success: false, error: 'Payment orchestrator not initialized' });
    }
    
    await paymentOrchestrator.demoProcessOrder(orderId);
    const order = await db.getOrder(orderId);
    
    return res.status(200).json({
      success: true,
      message: 'Order processed through demo flow',
      data: order,
    });
  } catch (error) {
    console.error('[V2] Demo process error:', error);
    return res.status(500).json({ 
      success: false, 
      error: error instanceof Error ? error.message : 'Failed to process order',
    });
  }
});

// ============ XENDIT PAYMENT SIMULATION (POC Demo) ============
import { XenditService } from './services/xenditService';
import { generateQrisPayload, generateSampleQrisCodes, parseQrisPayload } from './services/qrisDummyGenerator';

let xenditService: XenditService | null = null;

// Initialize Xendit if API key is present
if (process.env.XENDIT_API_KEY) {
  xenditService = new XenditService(process.env.XENDIT_API_KEY);
  console.log('[Server] Xendit service initialized');
}

// Create QRIS via Xendit (for receiving payment)
app.post('/xendit/qris/create', async (req, res) => {
  try {
    if (!xenditService) {
      return res.status(503).json({
        success: false,
        error: 'Xendit service not initialized. Set XENDIT_API_KEY.',
      });
    }

    const { externalId, amount, callbackUrl } = req.body;

    if (!externalId || !amount) {
      return res.status(400).json({
        success: false,
        error: 'externalId and amount are required',
      });
    }

    const result = await xenditService.createQrisPayment({
      externalId,
      amount: Math.round(amount),
      callbackUrl,
    });

    return res.status(201).json({
      success: true,
      data: result,
    });
  } catch (error) {
    console.error('[Xendit] Create QRIS error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to create QRIS',
    });
  }
});

// Simulate QRIS payment (sandbox only) - triggers Xendit logs
app.post('/xendit/qris/simulate', async (req, res) => {
  try {
    if (!xenditService) {
      return res.status(503).json({
        success: false,
        error: 'Xendit service not initialized',
      });
    }

    const { qrId, amount } = req.body;

    if (!qrId || !amount) {
      return res.status(400).json({
        success: false,
        error: 'qrId and amount are required',
      });
    }

    const result = await xenditService.simulateQrisPayment(qrId, Math.round(amount));

    return res.status(200).json({
      success: true,
      data: result,
    });
  } catch (error) {
    console.error('[Xendit] Simulate payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to simulate payment',
    });
  }
});

// Complete crypto-to-fiat flow: After user pays crypto, create disbursement in Xendit
app.post('/xendit/complete-payment', async (req, res) => {
  try {
    if (!xenditService) {
      return res.status(503).json({
        success: false,
        error: 'Xendit service not initialized',
      });
    }

    const { paymentId, amountIdr, merchantName, txHash } = req.body;

    if (!paymentId || !amountIdr) {
      return res.status(400).json({
        success: false,
        error: 'paymentId and amountIdr are required',
      });
    }

    console.log(`[Xendit] Completing crypto-to-fiat payment: ${paymentId}`);
    console.log(`  Amount: Rp ${amountIdr}`);
    console.log(`  Merchant: ${merchantName || 'Unknown'}`);
    console.log(`  Crypto TxHash: ${txHash || 'N/A'}`);

    // Create Disbursement (payout to merchant) - THIS SHOWS IN TRANSACTIONS
    const disbursementResult = await xenditService.createDisbursement({
      externalId: `CANMA-${paymentId}`,
      amount: Math.round(amountIdr),
      bankCode: 'BCA', // Simulated bank
      accountNumber: '1234567890', // Simulated account
      accountHolderName: merchantName || 'QRIS Merchant',
      description: `Crypto-to-Fiat Payout | TX: ${txHash?.substring(0, 10) || 'N/A'}`,
    });

    console.log(`[Xendit] ✅ Disbursement created successfully!`);
    console.log(`[Xendit] Disbursement ID: ${disbursementResult.id}`);
    console.log(`[Xendit] Status: ${disbursementResult.status}`);

    return res.status(200).json({
      success: true,
      data: {
        paymentId,
        xenditDisbursementId: disbursementResult.id,
        amountIdr: disbursementResult.amount,
        cryptoTxHash: txHash,
        xenditStatus: disbursementResult.status,
        message: 'Crypto-to-fiat payout created! Check Xendit dashboard → Transactions → Outgoing.',
        dashboardUrl: 'https://dashboard.xendit.co/transactions',
      },
    });
  } catch (error) {
    console.error('[Xendit] Complete payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to complete payment',
    });
  }
});

// Simulate invoice payment (for POC demo)
app.post('/xendit/invoice/:invoiceId/simulate', async (req, res) => {
  try {
    if (!xenditService) {
      return res.status(503).json({
        success: false,
        error: 'Xendit service not initialized',
      });
    }

    const { invoiceId } = req.params;
    const result = await xenditService.simulateInvoicePayment(invoiceId);

    return res.status(200).json({
      success: result.success,
      data: result,
    });
  } catch (error) {
    console.error('[Xendit] Simulate invoice error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to simulate payment',
    });
  }
});

// Get Xendit balance (for monitoring)
app.get('/xendit/balance', async (req, res) => {
  try {
    if (!xenditService) {
      return res.status(503).json({
        success: false,
        error: 'Xendit service not initialized',
      });
    }

    const balance = await xenditService.getBalance();

    return res.status(200).json({
      success: true,
      data: balance,
    });
  } catch (error) {
    console.error('[Xendit] Balance error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get balance',
    });
  }
});

// ============ QRIS DUMMY GENERATOR (for POC testing) ============

// Get sample QRIS codes for testing
app.get('/qris/dummy/samples', (req, res) => {
  try {
    const samples = generateSampleQrisCodes();
    
    return res.status(200).json({
      success: true,
      data: samples,
      note: 'Scan these QR codes with the app to test crypto-to-fiat payment flow',
    });
  } catch (error) {
    console.error('[QrisDummy] Error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to generate sample QRIS codes',
    });
  }
});

// Generate custom QRIS code
app.post('/qris/dummy/generate', (req, res) => {
  try {
    const { merchantName, merchantCity, amount, merchantId } = req.body;

    if (!merchantName || !merchantCity) {
      return res.status(400).json({
        success: false,
        error: 'merchantName and merchantCity are required',
      });
    }

    const payload = generateQrisPayload({
      merchantName,
      merchantCity,
      amount: amount ? Math.round(amount) : undefined,
      merchantId,
    });

    // Parse back to verify
    const parsed = parseQrisPayload(payload);

    return res.status(201).json({
      success: true,
      data: {
        payload,
        parsed,
        qrCodeUrl: `https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encodeURIComponent(payload)}`,
      },
    });
  } catch (error) {
    console.error('[QrisDummy] Generate error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to generate QRIS code',
    });
  }
});

// Serve HTML page with sample QR codes for easy testing
app.get('/qris/dummy', (req, res) => {
  const samples = generateSampleQrisCodes();
  
  const html = `
<!DOCTYPE html>
<html>
<head>
  <title>QRIS Dummy Generator - Canma Wallet POC</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; background: #0A1628; color: white; }
    h1 { color: #08BFC1; }
    .qr-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 20px; }
    .qr-card { background: #1a2744; border-radius: 12px; padding: 20px; text-align: center; }
    .qr-card img { background: white; padding: 10px; border-radius: 8px; }
    .qr-card h3 { color: #08BFC1; margin: 10px 0; }
    .qr-card p { color: #888; font-size: 12px; }
    .amount { color: #4CAF50; font-size: 18px; font-weight: bold; }
    .payload { background: #0d1829; padding: 10px; border-radius: 4px; font-size: 10px; word-break: break-all; margin-top: 10px; }
    .instructions { background: #1a2744; padding: 20px; border-radius: 12px; margin-bottom: 20px; }
    .instructions h2 { color: #08BFC1; }
    .instructions ol { color: #ccc; }
  </style>
</head>
<body>
  <h1>🔲 QRIS Dummy Generator</h1>
  <p>Canma Wallet - Crypto to Fiat POC Testing</p>
  
  <div class="instructions">
    <h2>📱 How to Test</h2>
    <ol>
      <li>Open Canma Wallet app on your phone</li>
      <li>Go to <strong>Scan QRIS</strong></li>
      <li>Scan one of the QR codes below</li>
      <li>Pay with LSK crypto</li>
      <li>Check <a href="https://dashboard.xendit.co/transactions" target="_blank" style="color: #08BFC1;">Xendit Dashboard</a> for payment logs</li>
    </ol>
  </div>
  
  <h2>📋 Sample QRIS Codes</h2>
  <div class="qr-grid">
    ${samples.map(s => `
      <div class="qr-card">
        <img src="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(s.payload)}" alt="${s.name}">
        <h3>${s.name}</h3>
        ${s.amount ? `<p class="amount">Rp ${s.amount.toLocaleString()}</p>` : '<p>Static QR (enter amount manually)</p>'}
        <div class="payload">${s.payload}</div>
      </div>
    `).join('')}
  </div>
  
  <h2 style="margin-top: 40px;">🔧 API Endpoints</h2>
  <ul>
    <li><code>GET /qris/dummy/samples</code> - Get all sample QRIS codes as JSON</li>
    <li><code>POST /qris/dummy/generate</code> - Generate custom QRIS code</li>
    <li><code>POST /xendit/complete-payment</code> - Complete crypto-to-fiat payment</li>
  </ul>
</body>
</html>
  `;
  
  res.setHeader('Content-Type', 'text/html');
  res.send(html);
});

// ============ NFC VOUCHER ENDPOINTS ============

// Claim voucher via relayer (backend pays gas)
app.post('/nfc/claim', async (req, res) => {
  try {
    const { chain, vaultAddress, voucher, signature } = req.body;
    
    if (!vaultAddress || !voucher || !signature) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: vaultAddress, voucher, signature',
      });
    }
    
    const nfcService = getNfcVoucherService();
    const result = await nfcService.claimVoucherAsRelayer(vaultAddress, voucher, signature);
    
    if (result.success) {
      return res.status(200).json({
        success: true,
        data: {
          txHash: result.txHash,
          chain,
          message: 'Voucher claimed successfully. Tokens transferred to payee.',
        },
      });
    } else {
      return res.status(400).json({
        success: false,
        error: result.error,
      });
    }
  } catch (error) {
    console.error('[NFC] Claim error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to claim voucher',
    });
  }
});

// Get deposit balance
app.get('/nfc/balance/:chain/:userAddress/:tokenAddress', async (req, res) => {
  try {
    const { chain, userAddress, tokenAddress } = req.params;
    const vaultAddress = NFC_VAULT_ADDRESSES[chain];
    
    if (!vaultAddress) {
      return res.status(400).json({
        success: false,
        error: `Vault not deployed on chain: ${chain}`,
      });
    }
    
    const nfcService = getNfcVoucherService();
    const balance = await nfcService.getDepositBalance(vaultAddress, userAddress, tokenAddress);
    
    return res.status(200).json({
      success: true,
      data: {
        chain,
        userAddress,
        tokenAddress,
        balance,
        balanceFormatted: (parseFloat(balance) / 1e18).toFixed(6),
      },
    });
  } catch (error) {
    console.error('[NFC] Balance error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get balance',
    });
  }
});

// Get next nonce for user
app.get('/nfc/nonce/:chain/:userAddress', async (req, res) => {
  try {
    const { chain, userAddress } = req.params;
    const vaultAddress = NFC_VAULT_ADDRESSES[chain];
    
    if (!vaultAddress) {
      return res.status(400).json({
        success: false,
        error: `Vault not deployed on chain: ${chain}`,
      });
    }
    
    const nfcService = getNfcVoucherService();
    const nonce = await nfcService.getNextNonce(vaultAddress, userAddress);
    
    return res.status(200).json({
      success: true,
      data: {
        chain,
        userAddress,
        nextNonce: nonce,
      },
    });
  } catch (error) {
    console.error('[NFC] Nonce error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get nonce',
    });
  }
});

// Get vault addresses config
app.get('/nfc/config', (req, res) => {
  return res.status(200).json({
    success: true,
    data: {
      vaultAddresses: NFC_VAULT_ADDRESSES,
      supportedChains: Object.keys(NFC_VAULT_ADDRESSES),
    },
  });
});

// ============ SWAP API ============

// Get swap quote
app.get('/swap/quote', async (req, res) => {
  try {
    const { fromToken, toToken, amount } = req.query;
    
    if (!fromToken || !toToken || !amount) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameters: fromToken, toToken, amount',
      });
    }
    
    const swapService = getSwapService();
    if (!swapService) {
      return res.status(503).json({
        success: false,
        error: 'Swap service not available',
      });
    }
    
    const quote = await swapService.getSwapQuote(
      fromToken as string,
      toToken as string,
      amount as string
    );
    
    return res.status(200).json({
      success: true,
      data: quote,
    });
  } catch (error) {
    console.error('[Swap] Quote error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get quote',
    });
  }
});

// Execute swap (send tokens from hot wallet to user)
app.post('/swap/execute', async (req, res) => {
  try {
    const { userAddress, fromToken, toToken, fromAmount, userTxHash } = req.body;
    
    if (!userAddress || !fromToken || !toToken || !fromAmount || !userTxHash) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameters: userAddress, fromToken, toToken, fromAmount, userTxHash',
      });
    }
    
    const swapService = getSwapService();
    if (!swapService) {
      return res.status(503).json({
        success: false,
        error: 'Swap service not available',
      });
    }
    
    console.log(`[Swap] Execute request from ${userAddress}: ${fromAmount} ${fromToken} -> ${toToken}`);
    
    const result = await swapService.executeSwap({
      userAddress,
      fromToken,
      toToken,
      fromAmount,
      userTxHash,
    });
    
    if (result.success) {
      return res.status(200).json({
        success: true,
        data: result,
      });
    } else {
      return res.status(400).json({
        success: false,
        error: result.error,
      });
    }
  } catch (error) {
    console.error('[Swap] Execute error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Swap execution failed',
    });
  }
});

// Get swap pool balances
app.get('/swap/pool', async (req, res) => {
  try {
    const swapService = getSwapService();
    if (!swapService) {
      return res.status(503).json({
        success: false,
        error: 'Swap service not available',
      });
    }
    
    const balances = await swapService.getAllBalances();
    
    return res.status(200).json({
      success: true,
      data: {
        hotWallet: swapService.getHotWalletAddress(),
        balances,
        adminFeePercent: 0.2,
      },
    });
  } catch (error) {
    console.error('[Swap] Pool error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get pool info',
    });
  }
});

// System config endpoint
app.get('/v2/config', async (req, res) => {
  try {
    const threshold = await db.getConfig('auto_approve_threshold_idr');
    const feePercent = await db.getConfig('platform_fee_percent');
    const escrowAddress = await db.getConfig('escrow_contract_address');
    
    return res.status(200).json({
      success: true,
      data: {
        autoApproveThresholdIdr: parseFloat(threshold || '10000000'),
        platformFeePercent: parseFloat(feePercent || '1.0'),
        escrowContractAddress: escrowAddress || 'Not deployed',
        lskTokenAddress: '0xac485391EB2d7D88253a7F1eF18C37f4571c1A24',
        chainId: 1135,
        chainName: 'Lisk Mainnet',
      },
    });
  } catch (error) {
    console.error('[V2] Config error:', error);
    return res.status(500).json({ success: false, error: 'Failed to get config' });
  }
});

function getMerchantDashboardHTML(): string {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Merchant Dashboard - QRIS Payments</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #0a1628 0%, #1a2a4a 100%);
      min-height: 100vh;
      color: white;
    }
    .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 20px 0;
      border-bottom: 1px solid rgba(255,255,255,0.1);
      margin-bottom: 30px;
    }
    h1 { color: #08BFC1; font-size: 24px; }
    .status { display: flex; align-items: center; gap: 8px; }
    .status-dot { width: 10px; height: 10px; border-radius: 50%; background: #22c55e; animation: pulse 2s infinite; }
    @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }
    .stat-card {
      background: rgba(255,255,255,0.05);
      border-radius: 12px;
      padding: 20px;
      border: 1px solid rgba(255,255,255,0.1);
    }
    .stat-label { color: #888; font-size: 14px; margin-bottom: 8px; }
    .stat-value { font-size: 28px; font-weight: bold; color: #08BFC1; }
    .payments-list { background: rgba(255,255,255,0.05); border-radius: 12px; overflow: hidden; }
    .payments-header {
      padding: 15px 20px;
      background: rgba(8, 191, 193, 0.1);
      border-bottom: 1px solid rgba(255,255,255,0.1);
      font-weight: 600;
    }
    .payment-item {
      display: grid;
      grid-template-columns: 1fr 1fr 1fr 1fr;
      padding: 15px 20px;
      border-bottom: 1px solid rgba(255,255,255,0.05);
      animation: fadeIn 0.5s ease;
    }
    .payment-item:hover { background: rgba(255,255,255,0.02); }
    @keyframes fadeIn { from { opacity: 0; transform: translateY(-10px); } to { opacity: 1; transform: translateY(0); } }
    .payment-item.new { background: rgba(8, 191, 193, 0.1); }
    .amount { color: #22c55e; font-weight: bold; }
    .time { color: #888; font-size: 14px; }
    .tx-hash { font-family: monospace; font-size: 12px; color: #08BFC1; }
    .empty { padding: 40px; text-align: center; color: #666; }
    .refresh-btn {
      background: #08BFC1;
      color: white;
      border: none;
      padding: 8px 16px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 14px;
    }
    .refresh-btn:hover { background: #07a8aa; }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>🏪 Merchant Dashboard</h1>
      <div class="status">
        <div class="status-dot"></div>
        <span>Live - Auto-refresh every 5s</span>
        <button class="refresh-btn" onclick="loadPayments()">Refresh</button>
      </div>
    </header>
    
    <div class="stats">
      <div class="stat-card">
        <div class="stat-label">Total Payments</div>
        <div class="stat-value" id="totalPayments">0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Total Revenue (IDR)</div>
        <div class="stat-value" id="totalRevenue">Rp 0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Total LSK Received</div>
        <div class="stat-value" id="totalLsk">0 LSK</div>
      </div>
    </div>
    
    <div class="payments-list">
      <div class="payments-header">Recent Payments</div>
      <div id="paymentsList">
        <div class="empty">No payments yet. Waiting for customers...</div>
      </div>
    </div>
  </div>
  
  <script>
    let lastPaymentCount = 0;
    
    async function loadPayments() {
      try {
        const res = await fetch('/merchant/notifications');
        const data = await res.json();
        
        if (data.success && data.data) {
          renderPayments(data.data);
          updateStats(data.data);
        }
      } catch (e) {
        console.error('Failed to load payments:', e);
      }
    }
    
    function renderPayments(payments) {
      const list = document.getElementById('paymentsList');
      
      if (payments.length === 0) {
        list.innerHTML = '<div class="empty">No payments yet. Waiting for customers...</div>';
        return;
      }
      
      list.innerHTML = payments.map((p, i) => {
        const isNew = i < (payments.length - lastPaymentCount) && lastPaymentCount > 0;
        const time = new Date(p.notified_at).toLocaleString('id-ID');
        const txShort = p.tx_hash ? p.tx_hash.substring(0, 10) + '...' : '-';
        
        return \`
          <div class="payment-item \${isNew ? 'new' : ''}">
            <div>
              <div>\${p.merchant_name || 'Unknown Merchant'}</div>
              <div class="time">\${time}</div>
            </div>
            <div class="amount">Rp \${Number(p.amount_idr).toLocaleString('id-ID')}</div>
            <div>\${p.payer_wallet.substring(0, 8)}...</div>
            <div class="tx-hash">\${txShort}</div>
          </div>
        \`;
      }).join('');
      
      lastPaymentCount = payments.length;
    }
    
    function updateStats(payments) {
      const total = payments.length;
      const revenue = payments.reduce((sum, p) => sum + Number(p.amount_idr), 0);
      
      document.getElementById('totalPayments').textContent = total;
      document.getElementById('totalRevenue').textContent = 'Rp ' + revenue.toLocaleString('id-ID');
    }
    
    // Initial load
    loadPayments();
    
    // Auto-refresh every 5 seconds
    setInterval(loadPayments, 5000);
  </script>
</body>
</html>
  `;
}

// ==================== SPLIT BILL ENDPOINTS ====================

// Create a new split bill
app.post('/splitbill/create', async (req, res) => {
  try {
    const { 
      creator, 
      description, 
      totalAmount, 
      participants, 
      deadline,
      isIDRMode,
      originalIDRAmount,
      lskPriceAtCreation 
    } = req.body;

    console.log('[SplitBill] Creating new bill...');
    console.log('[SplitBill] Creator:', creator);
    console.log('[SplitBill] Description:', description);
    console.log('[SplitBill] Participants:', participants?.length);

    if (!creator || !description || !totalAmount || !participants || participants.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: creator, description, totalAmount, participants',
      });
    }

    // Generate unique bill ID
    const billId = `BILL_${Date.now()}_${creator.substring(2, 8)}`;
    console.log('[SplitBill] Generated bill ID:', billId);

    // Prepare bill data
    const billData = {
      billId,
      creator: creator.toLowerCase(),
      description,
      totalAmount: totalAmount.toString(),
      collectedAmount: '0',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      deadline: deadline ? admin.firestore.Timestamp.fromDate(new Date(deadline)) : admin.firestore.Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)),
      status: 0, // 0=Active
      participantCount: participants.length,
      paidCount: 0,
      participants: participants.map((p: any) => ({
        wallet: p.wallet?.toLowerCase() || p.address?.toLowerCase(),
        name: p.name || '',
        amountDue: p.amountDue?.toString() || p.amount?.toString() || '0',
        amountPaid: '0',
        status: 0, // 0=Invited
        paidAt: null,
      })),
      tokenAddress: process.env.LSK_TOKEN_ADDRESS || '0x8a21CF9Ba08Ae709D64Cb25AfAA951183EC9FF6D',
      chainId: 4202,
      isIDRMode: isIDRMode || false,
      originalIDRAmount: originalIDRAmount || null,
      lskPriceAtCreation: lskPriceAtCreation || null,
    };

    // Save to Firestore
    console.log('[SplitBill] Saving to Firestore...');
    await firestore.collection('split_bills').doc(billId).set(billData);
    console.log('[SplitBill] Bill saved successfully!');

    return res.status(200).json({
      success: true,
      billId,
      message: 'Split bill created successfully',
    });
  } catch (error) {
    console.error('[SplitBill] Create error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to create split bill',
    });
  }
});

// Get all bills for a wallet (as creator or participant)
app.get('/splitbill/all/:walletAddress', async (req, res) => {
  try {
    const { walletAddress } = req.params;
    const walletLower = walletAddress.toLowerCase();

    console.log('[SplitBill] Loading bills for:', walletLower);

    const bills: any[] = [];

    // Query bills where user is creator
    const creatorQuery = await firestore
      .collection('split_bills')
      .where('creator', '==', walletLower)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();

    console.log('[SplitBill] Found', creatorQuery.docs.length, 'bills as creator');

    for (const doc of creatorQuery.docs) {
      bills.push({ id: doc.id, ...doc.data() });
    }

    // Query all bills and filter for participant
    const allBillsQuery = await firestore
      .collection('split_bills')
      .orderBy('createdAt', 'desc')
      .limit(100)
      .get();

    for (const doc of allBillsQuery.docs) {
      const data = doc.data();
      const isParticipant = data.participants?.some(
        (p: any) => p.wallet?.toLowerCase() === walletLower
      );

      if (isParticipant && !bills.some(b => b.billId === data.billId)) {
        bills.push({ id: doc.id, ...data });
      }
    }

    console.log('[SplitBill] Total bills:', bills.length);

    return res.status(200).json({
      success: true,
      bills,
    });
  } catch (error) {
    console.error('[SplitBill] Load error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to load bills',
    });
  }
});

// Update bill after payment
app.post('/splitbill/pay', async (req, res) => {
  try {
    const { billId, payerWallet, amountPaid, txHash } = req.body;

    console.log('[SplitBill] Processing payment...');
    console.log('[SplitBill] Bill ID:', billId);
    console.log('[SplitBill] Payer:', payerWallet);
    console.log('[SplitBill] Amount:', amountPaid);
    console.log('[SplitBill] TxHash:', txHash);

    if (!billId || !payerWallet || !amountPaid) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: billId, payerWallet, amountPaid',
      });
    }

    const billRef = firestore.collection('split_bills').doc(billId);
    const billDoc = await billRef.get();

    if (!billDoc.exists) {
      return res.status(404).json({
        success: false,
        error: 'Bill not found',
      });
    }

    const data = billDoc.data()!;
    const participants = [...(data.participants || [])];
    const walletLower = payerWallet.toLowerCase();

    // Find and update participant
    let participantFound = false;
    for (let i = 0; i < participants.length; i++) {
      if (participants[i].wallet?.toLowerCase() === walletLower) {
        participants[i].status = 3; // Paid
        participants[i].amountPaid = amountPaid.toString();
        participants[i].paidAt = admin.firestore.Timestamp.now();
        participants[i].txHash = txHash;
        participantFound = true;
        console.log('[SplitBill] Updated participant', i, 'to Paid');
        break;
      }
    }

    if (!participantFound) {
      return res.status(400).json({
        success: false,
        error: 'Payer not found in participants',
      });
    }

    // Calculate new values
    const newPaidCount = participants.filter(p => p.status === 3).length;
    const currentCollected = BigInt(data.collectedAmount || '0');
    const newCollected = currentCollected + BigInt(amountPaid);

    await billRef.update({
      participants,
      paidCount: newPaidCount,
      collectedAmount: newCollected.toString(),
      status: newPaidCount >= participants.length ? 1 : 0, // 1=Completed
    });

    console.log('[SplitBill] Payment recorded: paidCount=', newPaidCount);

    return res.status(200).json({
      success: true,
      paidCount: newPaidCount,
      collectedAmount: newCollected.toString(),
      isComplete: newPaidCount >= participants.length,
    });
  } catch (error) {
    console.error('[SplitBill] Payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to record payment',
    });
  }
});

// Start server
async function startServer() {
  try {
    // Connect to database
    await db.connect();
    console.log('[Server] Database connected');

    // Initialize QRIS service
    if (escrowMasterMnemonic && escrowMasterMnemonic !== 'your-escrow-master-mnemonic-here') {
      qrisPaymentService = new QrisPaymentServiceDB(escrowMasterMnemonic);
      depositVerifier = new DepositVerifierDB(qrisPaymentService);
      depositVerifier.start(10); // Check every 10 seconds
      console.log('[Server] QRIS payment service initialized');
    } else {
      console.warn('[Server] ESCROW_MASTER_MNEMONIC not configured - QRIS service disabled');
    }

    // Initialize Gas Sponsorship Service
    if (hotWalletPrivateKey && hotWalletPrivateKey.startsWith('0x')) {
      gasSponsorshipService = new GasSponsorshipService(hotWalletPrivateKey);
      console.log('[Server] Gas sponsorship service initialized');
    } else {
      console.warn('[Server] HOT_WALLET_PRIVATE_KEY not configured - Gas sponsorship disabled');
    }

    // Initialize QrisEscrowV2 Service
    if (process.env.QRIS_ESCROW_V2_ADDRESS) {
      try {
        qrisEscrowV2 = new QrisEscrowV2Service();
        const version = await qrisEscrowV2.getVersion();
        console.log(`[Server] QrisEscrowV2 service initialized (v${version})`);
        console.log(`  Escrow: ${qrisEscrowV2.getEscrowAddress()}`);
        console.log(`  Operator: ${qrisEscrowV2.getOperatorAddress()}`);
      } catch (e) {
        console.warn('[Server] QrisEscrowV2 initialization failed:', e);
      }
    } else {
      console.warn('[Server] QRIS_ESCROW_V2_ADDRESS not configured - V2 escrow disabled');
    }

    // Initialize Payment Orchestrator (v2 - Crypto-to-Fiat)
    try {
      paymentOrchestrator = createPaymentOrchestrator();
      await paymentOrchestrator.initialize();
      await paymentOrchestrator.start();
      console.log('[Server] Payment orchestrator started (Crypto-to-Fiat system)');
    } catch (e) {
      console.warn('[Server] Payment orchestrator initialization failed:', e);
      console.warn('[Server] V2 endpoints will have limited functionality');
    }

    // Initialize Faucet Service for mock tokens
    const faucet = initializeFaucetService();
    if (faucet) {
      console.log('[Server] Faucet service ready for LSK, ETH, POL mock tokens');
    }

    // Initialize Swap Service
    const swapService = initializeSwapService();
    if (swapService) {
      console.log('[Server] Swap service ready');
      console.log(`  Hot wallet: ${swapService.getHotWalletAddress()}`);
      const balances = await swapService.getAllBalances();
      console.log(`  Pool balances: LSK=${balances.LSK || '0'}, ETH=${balances.ETH || '0'}, POL=${balances.POL || '0'}`);
    } else {
      console.warn('[Server] Swap service not initialized - check HOT_WALLET_PRIVATE_KEY');
    }

    // Start Express server on all interfaces (0.0.0.0) for mobile device access
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`[Server] Running on http://0.0.0.0:${PORT}`);
      console.log(`[Server] Health check: http://192.168.1.26:${PORT}/health`);
    });
  } catch (error) {
    console.error('[Server] Failed to start:', error);
    process.exit(1);
  }
}

// ============ WALTQRPAY V3 (Multi-Token Support: LSK, ETH, POL) ============
import { WaltQRPayV3Service, SUPPORTED_TOKENS } from './services/waltQRPayV3Service';

let waltQRPayV3Service: WaltQRPayV3Service | null = null;

// Initialize WaltQRPayV3 if configured
if (process.env.WALTQRPAY_V3_ADDRESS) {
  try {
    waltQRPayV3Service = new WaltQRPayV3Service();
    console.log('[Server] WaltQRPayV3 service initialized (Multi-Token: LSK, ETH, POL)');
    
    // Auto-whitelist all supported tokens on startup
    (async () => {
      try {
        console.log('[Server] Checking token whitelist status...');
        const results = await waltQRPayV3Service!.whitelistAllTokens();
        for (const [symbol, result] of Object.entries(results)) {
          if (result === 'already-whitelisted') {
            console.log(`  ✅ ${symbol}: already whitelisted`);
          } else if (result.startsWith('error:')) {
            console.log(`  ❌ ${symbol}: ${result}`);
          } else {
            console.log(`  ✅ ${symbol}: whitelisted (tx: ${result.substring(0, 10)}...)`);
          }
        }
      } catch (e) {
        console.warn('[Server] Could not auto-whitelist tokens:', e);
      }
    })();
  } catch (e) {
    console.warn('[Server] WaltQRPayV3 not initialized:', e);
  }
}

// Get supported tokens
app.get('/v3/tokens', (req, res) => {
  return res.status(200).json({
    success: true,
    data: {
      tokens: SUPPORTED_TOKENS,
      contractAddress: process.env.WALTQRPAY_V3_ADDRESS,
    },
  });
});

// Create payment intent with token selection
app.post('/v3/qris/create-payment', async (req, res) => {
  try {
    if (!waltQRPayV3Service) {
      return res.status(503).json({
        success: false,
        error: 'WaltQRPayV3 service not initialized',
      });
    }

    const { walletAddress, qrisPayload, amountIdr, tokenSymbol } = req.body;

    if (!walletAddress || !qrisPayload || !amountIdr || !tokenSymbol) {
      return res.status(400).json({
        success: false,
        error: 'walletAddress, qrisPayload, amountIdr, and tokenSymbol are required',
      });
    }

    const payment = await waltQRPayV3Service.createPayment({
      walletAddress,
      qrisPayload,
      amountIdr,
      tokenSymbol,
    });

    // Check if token is whitelisted on contract
    const isWhitelisted = await waltQRPayV3Service.isTokenWhitelisted(payment.token.address);
    console.log(`[V3] Token ${payment.token.symbol} (${payment.token.address}) whitelisted: ${isWhitelisted}`);
    
    if (!isWhitelisted) {
      console.warn(`[V3] ⚠️ WARNING: Token ${payment.token.symbol} is NOT whitelisted! Payment will fail.`);
    }

    // Generate calldata for contract call
    const calldata = waltQRPayV3Service.generatePayCalldata(
      payment.orderId,
      payment.merchantId,
      payment.token.address,
      payment.tokenAmountWei
    );

    // Debug logging
    console.log(`[V3] Generated calldata for payment ${payment.paymentId}`);
    console.log(`  OrderId: ${payment.orderId}`);
    console.log(`  Token: ${payment.token.address}`);
    console.log(`  Calldata: ${calldata.substring(0, 66)}...`);

    return res.status(201).json({
      success: true,
      data: {
        ...payment,
        calldata,
      },
    });
  } catch (error) {
    console.error('[V3] Create payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to create payment',
    });
  }
});

// Get payment status
app.get('/v3/qris/payment/:paymentId', async (req, res) => {
  try {
    if (!waltQRPayV3Service) {
      return res.status(503).json({
        success: false,
        error: 'WaltQRPayV3 service not initialized',
      });
    }

    const { paymentId } = req.params;
    const payment = await waltQRPayV3Service.getPaymentFromContract(paymentId);

    if (!payment) {
      return res.status(404).json({
        success: false,
        error: 'Payment not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: payment,
    });
  } catch (error) {
    console.error('[V3] Get payment error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get payment',
    });
  }
});

// V3: Notify payment completed - triggers settlement bot
app.post('/v3/qris/payment-completed', async (req, res) => {
  try {
    const { paymentId, txHash, amountIdr, tokenSymbol, merchantName } = req.body;

    if (!txHash || !amountIdr) {
      return res.status(400).json({
        success: false,
        error: 'txHash and amountIdr are required',
      });
    }

    console.log(`[V3] Payment completed notification:`);
    console.log(`  Payment ID: ${paymentId}`);
    console.log(`  Tx Hash: ${txHash}`);
    console.log(`  Amount: Rp ${amountIdr}`);
    console.log(`  Token: ${tokenSymbol}`);

    // Trigger Xendit fiat payout via payment orchestrator
    if (paymentOrchestrator) {
      // Queue for settlement (Xendit payout simulation)
      console.log(`[V3] Queuing payment for Xendit settlement: Rp ${amountIdr}`);
      
      // Directly trigger Xendit payout
      if (xenditService) {
        const payout = await xenditService.createDisbursement({
          externalId: `CAMMA-${txHash.substring(0, 20)}`,
          amount: amountIdr,
          bankCode: 'BCA',
          accountNumber: '1234567890',
          accountHolderName: merchantName || 'QRIS Merchant',
          description: `Crypto-to-Fiat Payout | TX: ${txHash.substring(0, 10)}`,
        });
        
        console.log(`[V3] Xendit payout created: ${payout?.id || 'simulated'}`);
        
        // Wait for transaction to be confirmed before releasing (3 seconds)
        console.log(`[V3] Waiting 3s for tx confirmation: ${txHash}`);
        await new Promise(resolve => setTimeout(resolve, 3000));
        
        // Verify the transaction on-chain
        if (waltQRPayV3Service) {
          const txVerification = await waltQRPayV3Service.verifyTransaction(txHash);
          console.log(`[V3] Transaction verification:`);
          console.log(`  Status: ${txVerification.status || 'UNKNOWN'}`);
          console.log(`  To: ${txVerification.to}`);
          console.log(`  Expected: ${txVerification.contractAddress}`);
          console.log(`  Correct contract: ${txVerification.isCorrectContract}`);
          console.log(`  Logs count: ${txVerification.logsCount}`);
          console.log(`  PaymentCreated event: ${txVerification.hasPaymentCreatedEvent}`);
          console.log(`  Data: ${txVerification.data}`);
          
          // If no PaymentCreated event, the pay() function likely reverted internally
          if (!txVerification.hasPaymentCreatedEvent && txVerification.isCorrectContract) {
            console.log(`[V3] ⚠️ No PaymentCreated event - pay() may have reverted (insufficient approval/balance?)`);
          }
          
          // Extract orderId from transaction data and query directly
          if (txVerification.data && txVerification.data.length >= 74) {
            const orderIdFromTx = '0x' + txVerification.data.substring(10, 74);
            console.log(`[V3] OrderId from tx data: ${orderIdFromTx}`);
            
            // Query contract with this orderId directly
            const directQuery = await waltQRPayV3Service.getPaymentByOrderId(orderIdFromTx);
            console.log(`[V3] Direct query result: status=${directQuery?.status}, orderId=${directQuery?.orderId}`);
          }
        }
        
        // Release payment on smart contract after Xendit settlement (mark as RELEASED)
        let releaseTxHash: string | null = null;
        if (waltQRPayV3Service && paymentId) {
          try {
            // First check payment status on contract
            const paymentStatus = await waltQRPayV3Service.getPaymentFromContract(paymentId);
            console.log(`[V3] Payment status on contract: ${paymentStatus?.status || 'NOT FOUND'}`);
            console.log(`[V3] Payment orderId: ${paymentStatus?.orderId || 'N/A'}`);
            
            if (paymentStatus?.status === 'LOCKED') {
              console.log(`[V3] Releasing payment on smart contract: ${paymentId}`);
              releaseTxHash = await waltQRPayV3Service.releasePayment(paymentId);
              console.log(`[V3] ✅ Smart contract payment RELEASED! TxHash: ${releaseTxHash}`);
              
              // Note: Xendit sandbox doesn't support status simulation for disbursements
              // In production, status will auto-update via webhook after bank transfer completes
              console.log(`[V3] Xendit disbursement ${payout?.id} created - status will update via webhook in production`);
            } else if (paymentStatus?.status === 'NONE') {
              console.log(`[V3] ⚠️ Payment not found on contract - tx may have failed or used different orderId`);
            } else {
              console.log(`[V3] Payment already ${paymentStatus?.status}, skipping release`);
            }
          } catch (releaseError: any) {
            // Don't fail the request - Xendit payout already created
            console.error(`[V3] Failed to release on contract: ${releaseError.message}`);
          }
        }
        
        return res.status(200).json({
          success: true,
          data: {
            message: 'Payment processed and settled',
            payoutId: payout?.id,
            txHash,
            releaseTxHash,
          },
        });
      }
    }

    return res.status(200).json({
      success: true,
      data: {
        message: 'Payment notification received',
        txHash,
      },
    });
  } catch (error) {
    console.error('[V3] Payment completed error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to process payment',
    });
  }
});

// Get V3 statistics
app.get('/v3/stats', async (req, res) => {
  try {
    if (!waltQRPayV3Service) {
      return res.status(503).json({
        success: false,
        error: 'WaltQRPayV3 service not initialized',
      });
    }

    const stats = await waltQRPayV3Service.getStatistics();
    const version = await waltQRPayV3Service.getVersion();

    return res.status(200).json({
      success: true,
      data: {
        ...stats,
        version,
        contractAddress: waltQRPayV3Service.getContractAddress(),
      },
    });
  } catch (error) {
    console.error('[V3] Stats error:', error);
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : 'Failed to get stats',
    });
  }
});

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n[Server] Shutting down gracefully...');
  if (depositVerifier) {
    depositVerifier.stop();
  }
  if (paymentOrchestrator) {
    paymentOrchestrator.stop();
  }
  await db.close();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log('\n[Server] Shutting down gracefully...');
  if (depositVerifier) {
    depositVerifier.stop();
  }
  if (paymentOrchestrator) {
    paymentOrchestrator.stop();
  }
  await db.close();
  process.exit(0);
});

startServer();
