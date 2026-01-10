import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart' as web3;
import '../config/env.dart';
import 'price_service.dart';

/// Gas Fee Sponsorship Service
/// 
/// Implements a barter mechanism where:
/// - Admin hot wallet pays for gas fees
/// - User's tokens are deducted as compensation
/// - Admin takes 0.5% margin on the barter
class GasSponsorService {
  static final GasSponsorService _instance = GasSponsorService._internal();
  factory GasSponsorService() => _instance;
  GasSponsorService._internal();

  final PriceService _priceService = PriceService();
  
  // Admin fee percentage (0.5%)
  static const double adminFeePercent = 0.005;
  
  // Hot wallet address for receiving barter tokens
  static const String hotWalletAddress = '0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97';
  
  // Minimum gas required for ERC-20 transfer (in ETH)
  static const double minGasRequired = 0.0005;
  
  // Gas limit for ERC-20 transfer
  static const int erc20GasLimit = 100000;
  
  // Gas limit for native transfer
  static const int nativeGasLimit = 21000;

  /// Calculate gas fee breakdown for a transfer
  /// Returns a GasFeeBreakdown with all fee details
  Future<GasFeeBreakdown> calculateGasFeeBreakdown({
    required String token,
    required double transferAmount,
    required String rpcUrl,
    bool isNative = false,
  }) async {
    try {
      print('[GasSponsorService] Calculating breakdown for $transferAmount $token');
      
      // 1. Get current gas price from chain
      final httpClient = http.Client();
      final web3Client = web3.Web3Client(rpcUrl, httpClient);
      
      final gasPrice = await web3Client.getGasPrice();
      final gasPriceGwei = gasPrice.getInWei.toDouble() / 1e9;
      
      httpClient.close();
      
      print('[GasSponsorService] Gas price: $gasPriceGwei gwei');
      
      // 2. Calculate gas fee in ETH
      final gasLimit = isNative ? nativeGasLimit : erc20GasLimit;
      final gasFeeWei = gasPrice.getInWei * BigInt.from(gasLimit);
      final gasFeeEth = gasFeeWei.toDouble() / 1e18;
      
      print('[GasSponsorService] Gas fee: $gasFeeEth ETH (limit: $gasLimit)');
      
      // 3. Get token price in USD
      final tokenPriceUsd = await _getTokenPriceUsd(token);
      final ethPriceUsd = await _getTokenPriceUsd('ETH');
      
      print('[GasSponsorService] Token price: \$$tokenPriceUsd, ETH price: \$$ethPriceUsd');
      
      // 4. Convert gas fee to token equivalent
      // Formula: gasFeeEth * ethPriceUsd / tokenPriceUsd
      double gasFeeInToken = 0;
      if (tokenPriceUsd > 0) {
        gasFeeInToken = (gasFeeEth * ethPriceUsd) / tokenPriceUsd;
      }
      
      print('[GasSponsorService] Gas fee in $token: $gasFeeInToken');
      
      // 5. Calculate admin fee (0.5% of TRANSFER AMOUNT, not gas fee)
      final adminFeeInToken = transferAmount * adminFeePercent;
      
      // 6. Total token deducted (gas fee + admin fee from transfer amount)
      final totalTokenDeducted = gasFeeInToken + adminFeeInToken;
      
      // 7. Net amount receiver gets
      final netAmountToReceiver = transferAmount - totalTokenDeducted;
      
      print('[GasSponsorService] Admin fee: $adminFeeInToken $token');
      print('[GasSponsorService] Total deducted: $totalTokenDeducted $token');
      print('[GasSponsorService] Net to receiver: $netAmountToReceiver $token');
      
      // 8. Calculate USD values
      final gasFeeUsd = gasFeeEth * ethPriceUsd;
      final adminFeeUsd = adminFeeInToken * tokenPriceUsd;
      final totalDeductedUsd = totalTokenDeducted * tokenPriceUsd;
      
      return GasFeeBreakdown(
        gasPriceGwei: gasPriceGwei,
        gasLimit: gasLimit,
        gasFeeEth: gasFeeEth,
        gasFeeUsd: gasFeeUsd,
        gasFeeInToken: gasFeeInToken,
        adminFeePercent: adminFeePercent * 100,
        adminFeeInToken: adminFeeInToken,
        adminFeeUsd: adminFeeUsd,
        totalTokenDeducted: totalTokenDeducted,
        totalDeductedUsd: totalDeductedUsd,
        transferAmount: transferAmount,
        netAmountToReceiver: netAmountToReceiver,
        token: token,
        tokenPriceUsd: tokenPriceUsd,
        ethPriceUsd: ethPriceUsd,
        isValid: netAmountToReceiver > 0,
        errorMessage: netAmountToReceiver <= 0 
            ? 'Transfer amount too small to cover gas fees' 
            : null,
      );
    } catch (e) {
      print('[GasSponsorService] Error calculating breakdown: $e');
      return GasFeeBreakdown.error('Failed to calculate gas fees: $e');
    }
  }

  /// Get token price in USD
  Future<double> _getTokenPriceUsd(String token) async {
    // Fallback prices for hackathon demo - always use these as baseline
    final fallbackPrices = {
      'LSK': 1.0,
      'ETH': 3500.0,
      'POL': 0.5,
    };
    
    try {
      // Map token symbols to price service symbols
      final Map<String, String> tokenMap = {
        'LSK': 'LSK',
        'ETH': 'ETH',
        'POL': 'POL',
        'MATIC': 'POL',
      };
      
      final symbol = tokenMap[token.toUpperCase()] ?? token;
      final prices = await _priceService.fetchPricesUSD([symbol]);
      final price = prices[symbol] ?? 0.0;
      
      // If price is 0 or very small, use fallback
      if (price <= 0.0001) {
        print('[GasSponsorService] Price for $token is $price, using fallback');
        return fallbackPrices[token.toUpperCase()] ?? 1.0;
      }
      
      print('[GasSponsorService] Price for $token: \$$price');
      return price;
    } catch (e) {
      print('[GasSponsorService] Error getting price for $token: $e, using fallback');
      return fallbackPrices[token.toUpperCase()] ?? 1.0;
    }
  }

  /// Execute sponsored transfer with barter mechanism
  /// 
  /// Flow:
  /// 1. User sends (transferAmount - fees) to receiver
  /// 2. User sends (gasFee + adminFee) in tokens to hot wallet
  /// 3. Hot wallet sponsors the gas for both transactions
  Future<SponsoredTransferResult> executeSponsoredTransfer({
    required String senderPrivateKey,
    required String receiverAddress,
    required String tokenAddress,
    required double transferAmount,
    required GasFeeBreakdown feeBreakdown,
    required String rpcUrl,
    required int chainId,
    bool isNative = false,
  }) async {
    try {
      print('[GasSponsorService] Starting sponsored transfer...');
      print('[GasSponsorService] Transfer amount: ${feeBreakdown.transferAmount} ${feeBreakdown.token}');
      print('[GasSponsorService] Gas fee in token: ${feeBreakdown.gasFeeInToken}');
      print('[GasSponsorService] Admin fee: ${feeBreakdown.adminFeeInToken}');
      print('[GasSponsorService] Total deducted: ${feeBreakdown.totalTokenDeducted}');
      print('[GasSponsorService] Net to receiver: ${feeBreakdown.netAmountToReceiver}');
      
      // Step 1: Request gas sponsorship from backend
      final httpClient = http.Client();
      final web3Client = web3.Web3Client(rpcUrl, httpClient);
      final credentials = web3.EthPrivateKey.fromHex(senderPrivateKey);
      final senderAddress = credentials.address;
      
      // Request gas from hot wallet
      final gasSponsored = await _requestGasFromHotWallet(senderAddress.hex);
      if (!gasSponsored) {
        throw Exception('Failed to get gas sponsorship from hot wallet');
      }
      
      // Wait for gas to arrive
      await Future.delayed(const Duration(seconds: 3));
      
      String mainTxHash;
      String barterTxHash;
      
      if (isNative) {
        // For native transfers, we can't do barter easily
        // Just do a simple transfer
        final amountWei = BigInt.from(feeBreakdown.netAmountToReceiver * 1e18);
        
        final transaction = web3.Transaction(
          to: web3.EthereumAddress.fromHex(receiverAddress),
          value: web3.EtherAmount.inWei(amountWei),
          maxGas: nativeGasLimit,
        );
        
        mainTxHash = await web3Client.sendTransaction(
          credentials,
          transaction,
          chainId: chainId,
        );
        barterTxHash = ''; // No barter for native
      } else {
        // Step 2: Send tokens to receiver (net amount)
        final tokenAddr = web3.EthereumAddress.fromHex(tokenAddress);
        final recipient = web3.EthereumAddress.fromHex(receiverAddress);
        final hotWallet = web3.EthereumAddress.fromHex(hotWalletAddress);
        
        final transferAbi = web3.ContractAbi.fromJson(
          '''[{"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"type":"function"}]''',
          'ERC20',
        );
        
        final contract = web3.DeployedContract(transferAbi, tokenAddr);
        final transferFunction = contract.function('transfer');
        
        // Transfer to receiver
        final netAmountWei = BigInt.from(feeBreakdown.netAmountToReceiver * 1e18);
        final mainTx = web3.Transaction.callContract(
          contract: contract,
          function: transferFunction,
          parameters: [recipient, netAmountWei],
          maxGas: erc20GasLimit,
        );
        
        mainTxHash = await web3Client.sendTransaction(
          credentials,
          mainTx,
          chainId: chainId,
        );
        
        print('[GasSponsorService] Main transfer tx: $mainTxHash');
        
        // Step 3: Send barter tokens to hot wallet
        final barterAmountWei = BigInt.from(feeBreakdown.totalTokenDeducted * 1e18);
        final barterTx = web3.Transaction.callContract(
          contract: contract,
          function: transferFunction,
          parameters: [hotWallet, barterAmountWei],
          maxGas: erc20GasLimit,
        );
        
        barterTxHash = await web3Client.sendTransaction(
          credentials,
          barterTx,
          chainId: chainId,
        );
        
        print('[GasSponsorService] Barter tx to hot wallet: $barterTxHash');
      }
      
      httpClient.close();
      
      // Step 4: Record barter transaction to backend for verification
      await _recordBarterTransaction(
        senderAddress: senderAddress.hex,
        receiverAddress: receiverAddress,
        token: feeBreakdown.token,
        transferAmount: feeBreakdown.transferAmount,
        gasFeeInToken: feeBreakdown.gasFeeInToken,
        adminFeeInToken: feeBreakdown.adminFeeInToken,
        totalDeducted: feeBreakdown.totalTokenDeducted,
        netToReceiver: feeBreakdown.netAmountToReceiver,
        mainTxHash: mainTxHash,
        barterTxHash: barterTxHash,
      );
      
      return SponsoredTransferResult(
        success: true,
        mainTxHash: mainTxHash,
        barterTxHash: barterTxHash,
        feeBreakdown: feeBreakdown,
      );
    } catch (e) {
      print('[GasSponsorService] Sponsored transfer error: $e');
      return SponsoredTransferResult(
        success: false,
        error: e.toString(),
        feeBreakdown: feeBreakdown,
      );
    }
  }

  /// Request gas from hot wallet
  Future<bool> _requestGasFromHotWallet(String walletAddress) async {
    try {
      print('[GasSponsorService] Requesting gas for: $walletAddress');
      
      final response = await http.post(
        Uri.parse('${Env.backendUrl}/gas/sponsor'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'walletAddress': walletAddress}),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[GasSponsorService] Gas sponsored: ${data['txHash']}');
        return true;
      } else {
        print('[GasSponsorService] Gas sponsorship failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('[GasSponsorService] Gas sponsorship error: $e');
      return false;
    }
  }

  /// Record barter transaction for audit/verification
  Future<void> _recordBarterTransaction({
    required String senderAddress,
    required String receiverAddress,
    required String token,
    required double transferAmount,
    required double gasFeeInToken,
    required double adminFeeInToken,
    required double totalDeducted,
    required double netToReceiver,
    required String mainTxHash,
    required String barterTxHash,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Env.backendUrl}/gas/barter-record'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'senderAddress': senderAddress,
          'receiverAddress': receiverAddress,
          'hotWalletAddress': hotWalletAddress,
          'token': token,
          'transferAmount': transferAmount,
          'gasFeeInToken': gasFeeInToken,
          'adminFeeInToken': adminFeeInToken,
          'adminFeePercent': adminFeePercent * 100,
          'totalDeducted': totalDeducted,
          'netToReceiver': netToReceiver,
          'mainTxHash': mainTxHash,
          'barterTxHash': barterTxHash,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        print('[GasSponsorService] Barter record saved');
      } else {
        print('[GasSponsorService] Failed to record barter: ${response.body}');
      }
    } catch (e) {
      print('[GasSponsorService] Error recording barter: $e');
      // Don't throw - this is just for auditing
    }
  }

  /// Verify hot wallet received the barter tokens
  Future<BarterVerificationResult> verifyBarterReceived({
    required String barterTxHash,
    required String token,
    required double expectedAmount,
    required String rpcUrl,
  }) async {
    try {
      final httpClient = http.Client();
      final web3Client = web3.Web3Client(rpcUrl, httpClient);
      
      // Get transaction receipt
      final receipt = await web3Client.getTransactionReceipt(barterTxHash);
      
      httpClient.close();
      
      if (receipt == null) {
        return BarterVerificationResult(
          verified: false,
          message: 'Transaction not found or still pending',
        );
      }
      
      if (receipt.status == false) {
        return BarterVerificationResult(
          verified: false,
          message: 'Transaction failed on chain',
        );
      }
      
      // Calculate expected profit
      final gasFeeEquivalent = expectedAmount / (1 + adminFeePercent);
      final expectedProfit = expectedAmount - gasFeeEquivalent;
      final profitPercent = (expectedProfit / gasFeeEquivalent) * 100;
      
      return BarterVerificationResult(
        verified: true,
        message: 'Barter verified successfully',
        totalReceived: expectedAmount,
        gasFeeEquivalent: gasFeeEquivalent,
        adminProfit: expectedProfit,
        profitPercent: profitPercent,
        txHash: barterTxHash,
      );
    } catch (e) {
      return BarterVerificationResult(
        verified: false,
        message: 'Verification error: $e',
      );
    }
  }
}

/// Gas Fee Breakdown model
class GasFeeBreakdown {
  final double gasPriceGwei;
  final int gasLimit;
  final double gasFeeEth;
  final double gasFeeUsd;
  final double gasFeeInToken;
  final double adminFeePercent;
  final double adminFeeInToken;
  final double adminFeeUsd;
  final double totalTokenDeducted;
  final double totalDeductedUsd;
  final double transferAmount;
  final double netAmountToReceiver;
  final String token;
  final double tokenPriceUsd;
  final double ethPriceUsd;
  final bool isValid;
  final String? errorMessage;

  GasFeeBreakdown({
    required this.gasPriceGwei,
    required this.gasLimit,
    required this.gasFeeEth,
    required this.gasFeeUsd,
    required this.gasFeeInToken,
    required this.adminFeePercent,
    required this.adminFeeInToken,
    required this.adminFeeUsd,
    required this.totalTokenDeducted,
    required this.totalDeductedUsd,
    required this.transferAmount,
    required this.netAmountToReceiver,
    required this.token,
    required this.tokenPriceUsd,
    required this.ethPriceUsd,
    required this.isValid,
    this.errorMessage,
  });

  factory GasFeeBreakdown.error(String message) {
    return GasFeeBreakdown(
      gasPriceGwei: 0,
      gasLimit: 0,
      gasFeeEth: 0,
      gasFeeUsd: 0,
      gasFeeInToken: 0,
      adminFeePercent: 0,
      adminFeeInToken: 0,
      adminFeeUsd: 0,
      totalTokenDeducted: 0,
      totalDeductedUsd: 0,
      transferAmount: 0,
      netAmountToReceiver: 0,
      token: '',
      tokenPriceUsd: 0,
      ethPriceUsd: 0,
      isValid: false,
      errorMessage: message,
    );
  }
}

/// Sponsored Transfer Result
class SponsoredTransferResult {
  final bool success;
  final String? mainTxHash;
  final String? barterTxHash;
  final String? error;
  final GasFeeBreakdown feeBreakdown;

  SponsoredTransferResult({
    required this.success,
    this.mainTxHash,
    this.barterTxHash,
    this.error,
    required this.feeBreakdown,
  });
}

/// Barter Verification Result
class BarterVerificationResult {
  final bool verified;
  final String message;
  final double? totalReceived;
  final double? gasFeeEquivalent;
  final double? adminProfit;
  final double? profitPercent;
  final String? txHash;

  BarterVerificationResult({
    required this.verified,
    required this.message,
    this.totalReceived,
    this.gasFeeEquivalent,
    this.adminProfit,
    this.profitPercent,
    this.txHash,
  });
}
