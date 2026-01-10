import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart' as web3;

/// 1inch Swap Service
/// 
/// Integrates with 1inch Aggregation Protocol for token swaps
/// Admin takes 0.2% fee on each swap transaction
class OneInchSwapService {
  static final OneInchSwapService _instance = OneInchSwapService._internal();
  factory OneInchSwapService() => _instance;
  OneInchSwapService._internal();

  // 1inch API configuration
  static const String _apiKey = '618639c0-03c5-4f94-a23d-73a9aff59fd5';
  static const String _baseUrl = 'https://api.1inch.dev';
  
  // Admin fee percentage (0.2%)
  static const double adminFeePercent = 0.002;
  
  // Hot wallet address for receiving fees
  static const String feeReceiverAddress = '0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97';
  
  // Supported chains
  static const Map<String, int> supportedChains = {
    'ethereum': 1,
    'polygon': 137,
    'bsc': 56,
    'arbitrum': 42161,
    'optimism': 10,
    'avalanche': 43114,
    'base': 8453,
    'lisk-sepolia': 4202, // Testnet
  };

  /// Get swap quote from 1inch
  Future<SwapQuote> getSwapQuote({
    required int chainId,
    required String fromTokenAddress,
    required String toTokenAddress,
    required String amount, // in wei
    String? fromAddress,
  }) async {
    try {
      print('[1inch] Getting quote: $fromTokenAddress -> $toTokenAddress, amount: $amount');
      
      final url = Uri.parse('$_baseUrl/swap/v6.0/$chainId/quote');
      
      final response = await http.get(
        url.replace(queryParameters: {
          'src': fromTokenAddress,
          'dst': toTokenAddress,
          'amount': amount,
          if (fromAddress != null) 'from': fromAddress,
          'includeTokensInfo': 'true',
          'includeGas': 'true',
        }),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return SwapQuote.fromJson(data, chainId, adminFeePercent);
      } else {
        print('[1inch] Quote error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get quote: ${response.statusCode}');
      }
    } catch (e) {
      print('[1inch] Quote error: $e');
      rethrow;
    }
  }

  /// Get swap transaction data from 1inch
  Future<SwapTransaction> getSwapTransaction({
    required int chainId,
    required String fromTokenAddress,
    required String toTokenAddress,
    required String amount, // in wei
    required String fromAddress,
    required double slippage, // e.g., 1.0 for 1%
  }) async {
    try {
      print('[1inch] Getting swap tx: $fromTokenAddress -> $toTokenAddress');
      
      // Calculate amount after admin fee deduction
      final amountBigInt = BigInt.parse(amount);
      final adminFeeAmount = (amountBigInt.toDouble() * adminFeePercent).round();
      final amountAfterFee = amountBigInt - BigInt.from(adminFeeAmount);
      
      final url = Uri.parse('$_baseUrl/swap/v6.0/$chainId/swap');
      
      final response = await http.get(
        url.replace(queryParameters: {
          'src': fromTokenAddress,
          'dst': toTokenAddress,
          'amount': amountAfterFee.toString(),
          'from': fromAddress,
          'slippage': slippage.toString(),
          'includeTokensInfo': 'true',
          'includeGas': 'true',
          'receiver': fromAddress, // User receives swapped tokens
          'referrer': feeReceiverAddress, // Admin wallet for tracking
        }),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return SwapTransaction.fromJson(
          data, 
          chainId,
          adminFeeAmount: BigInt.from(adminFeeAmount),
          originalAmount: amountBigInt,
        );
      } else {
        print('[1inch] Swap error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get swap transaction: ${response.statusCode}');
      }
    } catch (e) {
      print('[1inch] Swap error: $e');
      rethrow;
    }
  }

  /// Execute swap with admin fee
  /// 
  /// Flow:
  /// 1. Transfer admin fee (0.2%) to hot wallet
  /// 2. Execute 1inch swap with remaining amount
  Future<SwapResult> executeSwap({
    required String privateKey,
    required int chainId,
    required String fromTokenAddress,
    required String toTokenAddress,
    required String amount,
    required String rpcUrl,
    required double slippage,
  }) async {
    try {
      final httpClient = http.Client();
      final web3Client = web3.Web3Client(rpcUrl, httpClient);
      final credentials = web3.EthPrivateKey.fromHex(privateKey);
      final fromAddress = credentials.address.hex;
      
      print('[1inch] Executing swap from: $fromAddress');
      
      // Step 1: Get swap transaction
      final swapTx = await getSwapTransaction(
        chainId: chainId,
        fromTokenAddress: fromTokenAddress,
        toTokenAddress: toTokenAddress,
        amount: amount,
        fromAddress: fromAddress,
        slippage: slippage,
      );
      
      // Step 2: Transfer admin fee to hot wallet (if ERC-20)
      String? feeTxHash;
      if (fromTokenAddress.toLowerCase() != '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee') {
        feeTxHash = await _transferAdminFee(
          web3Client: web3Client,
          credentials: credentials,
          tokenAddress: fromTokenAddress,
          feeAmount: swapTx.adminFeeAmount,
          chainId: chainId,
        );
        print('[1inch] Admin fee transferred: $feeTxHash');
      }
      
      // Step 3: Execute the swap
      final transaction = web3.Transaction(
        to: web3.EthereumAddress.fromHex(swapTx.toAddress),
        value: web3.EtherAmount.inWei(BigInt.parse(swapTx.value)),
        data: _hexToBytes(swapTx.data),
        maxGas: swapTx.gasLimit,
      );
      
      final swapTxHash = await web3Client.sendTransaction(
        credentials,
        transaction,
        chainId: chainId,
      );
      
      httpClient.close();
      
      print('[1inch] Swap executed: $swapTxHash');
      
      return SwapResult(
        success: true,
        swapTxHash: swapTxHash,
        feeTxHash: feeTxHash,
        fromToken: swapTx.fromToken,
        toToken: swapTx.toToken,
        fromAmount: swapTx.originalAmount.toString(),
        toAmount: swapTx.toAmount,
        adminFee: swapTx.adminFeeAmount.toString(),
        adminFeePercent: adminFeePercent * 100,
      );
    } catch (e) {
      print('[1inch] Swap execution error: $e');
      return SwapResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Transfer admin fee to hot wallet
  Future<String> _transferAdminFee({
    required web3.Web3Client web3Client,
    required web3.Credentials credentials,
    required String tokenAddress,
    required BigInt feeAmount,
    required int chainId,
  }) async {
    final tokenAddr = web3.EthereumAddress.fromHex(tokenAddress);
    final feeReceiver = web3.EthereumAddress.fromHex(feeReceiverAddress);
    
    final transferAbi = web3.ContractAbi.fromJson(
      '''[{"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"type":"function"}]''',
      'ERC20',
    );
    
    final contract = web3.DeployedContract(transferAbi, tokenAddr);
    final transferFunction = contract.function('transfer');
    
    final tx = web3.Transaction.callContract(
      contract: contract,
      function: transferFunction,
      parameters: [feeReceiver, feeAmount],
      maxGas: 100000,
    );
    
    return await web3Client.sendTransaction(
      credentials,
      tx,
      chainId: chainId,
    );
  }

  /// Get token list for a chain
  Future<List<TokenInfo>> getTokenList(int chainId) async {
    try {
      final url = Uri.parse('$_baseUrl/swap/v6.0/$chainId/tokens');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tokens = data['tokens'] as Map<String, dynamic>;
        
        return tokens.entries.map((e) {
          final tokenData = e.value as Map<String, dynamic>;
          return TokenInfo(
            address: e.key,
            symbol: tokenData['symbol'] ?? '',
            name: tokenData['name'] ?? '',
            decimals: tokenData['decimals'] ?? 18,
            logoUri: tokenData['logoURI'],
          );
        }).toList();
      } else {
        throw Exception('Failed to get token list: ${response.statusCode}');
      }
    } catch (e) {
      print('[1inch] Token list error: $e');
      return [];
    }
  }

  /// Check token allowance for 1inch router
  Future<BigInt> checkAllowance({
    required int chainId,
    required String tokenAddress,
    required String walletAddress,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/swap/v6.0/$chainId/approve/allowance');
      
      final response = await http.get(
        url.replace(queryParameters: {
          'tokenAddress': tokenAddress,
          'walletAddress': walletAddress,
        }),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BigInt.parse(data['allowance'] ?? '0');
      } else {
        return BigInt.zero;
      }
    } catch (e) {
      print('[1inch] Allowance check error: $e');
      return BigInt.zero;
    }
  }

  /// Get approve transaction for 1inch router
  Future<Map<String, dynamic>?> getApproveTransaction({
    required int chainId,
    required String tokenAddress,
    String? amount, // null for unlimited
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/swap/v6.0/$chainId/approve/transaction');
      
      final queryParams = {
        'tokenAddress': tokenAddress,
      };
      if (amount != null) {
        queryParams['amount'] = amount;
      }
      
      final response = await http.get(
        url.replace(queryParameters: queryParams),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return null;
      }
    } catch (e) {
      print('[1inch] Approve tx error: $e');
      return null;
    }
  }

  Uint8List _hexToBytes(String hex) {
    hex = hex.replaceFirst('0x', '');
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }
}

/// Swap Quote model
class SwapQuote {
  final String fromToken;
  final String toToken;
  final String fromTokenSymbol;
  final String toTokenSymbol;
  final String fromAmount;
  final String toAmount;
  final int chainId;
  final int estimatedGas;
  final double adminFeePercent;
  final String adminFeeAmount;
  final String amountAfterFee;
  final String toAmountAfterFee;

  SwapQuote({
    required this.fromToken,
    required this.toToken,
    required this.fromTokenSymbol,
    required this.toTokenSymbol,
    required this.fromAmount,
    required this.toAmount,
    required this.chainId,
    required this.estimatedGas,
    required this.adminFeePercent,
    required this.adminFeeAmount,
    required this.amountAfterFee,
    required this.toAmountAfterFee,
  });

  factory SwapQuote.fromJson(Map<String, dynamic> json, int chainId, double feePercent) {
    final fromAmount = json['fromAmount'] ?? '0';
    final toAmount = json['toAmount'] ?? '0';
    
    final fromAmountBigInt = BigInt.parse(fromAmount);
    final adminFee = (fromAmountBigInt.toDouble() * feePercent).round();
    final amountAfterFee = fromAmountBigInt - BigInt.from(adminFee);
    
    // Estimate output after fee (proportional reduction)
    final toAmountBigInt = BigInt.parse(toAmount);
    final toAmountAfterFee = (toAmountBigInt.toDouble() * (1 - feePercent)).round();
    
    return SwapQuote(
      fromToken: json['srcToken']?['address'] ?? '',
      toToken: json['dstToken']?['address'] ?? '',
      fromTokenSymbol: json['srcToken']?['symbol'] ?? '',
      toTokenSymbol: json['dstToken']?['symbol'] ?? '',
      fromAmount: fromAmount,
      toAmount: toAmount,
      chainId: chainId,
      estimatedGas: json['gas'] ?? 200000,
      adminFeePercent: feePercent * 100,
      adminFeeAmount: adminFee.toString(),
      amountAfterFee: amountAfterFee.toString(),
      toAmountAfterFee: toAmountAfterFee.toString(),
    );
  }
}

/// Swap Transaction model
class SwapTransaction {
  final String toAddress;
  final String data;
  final String value;
  final int gasLimit;
  final String fromToken;
  final String toToken;
  final String toAmount;
  final BigInt originalAmount;
  final BigInt adminFeeAmount;

  SwapTransaction({
    required this.toAddress,
    required this.data,
    required this.value,
    required this.gasLimit,
    required this.fromToken,
    required this.toToken,
    required this.toAmount,
    required this.originalAmount,
    required this.adminFeeAmount,
  });

  factory SwapTransaction.fromJson(
    Map<String, dynamic> json,
    int chainId, {
    required BigInt adminFeeAmount,
    required BigInt originalAmount,
  }) {
    final tx = json['tx'] as Map<String, dynamic>;
    return SwapTransaction(
      toAddress: tx['to'] ?? '',
      data: tx['data'] ?? '',
      value: tx['value'] ?? '0',
      gasLimit: tx['gas'] ?? 500000,
      fromToken: json['srcToken']?['symbol'] ?? '',
      toToken: json['dstToken']?['symbol'] ?? '',
      toAmount: json['toAmount'] ?? '0',
      originalAmount: originalAmount,
      adminFeeAmount: adminFeeAmount,
    );
  }
}

/// Swap Result model
class SwapResult {
  final bool success;
  final String? swapTxHash;
  final String? feeTxHash;
  final String? fromToken;
  final String? toToken;
  final String? fromAmount;
  final String? toAmount;
  final String? adminFee;
  final double? adminFeePercent;
  final String? error;

  SwapResult({
    required this.success,
    this.swapTxHash,
    this.feeTxHash,
    this.fromToken,
    this.toToken,
    this.fromAmount,
    this.toAmount,
    this.adminFee,
    this.adminFeePercent,
    this.error,
  });
}

/// Token Info model
class TokenInfo {
  final String address;
  final String symbol;
  final String name;
  final int decimals;
  final String? logoUri;

  TokenInfo({
    required this.address,
    required this.symbol,
    required this.name,
    required this.decimals,
    this.logoUri,
  });
}
