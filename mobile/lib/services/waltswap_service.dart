import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart' as web3;
import 'package:cloud_firestore/cloud_firestore.dart';

/// WaltSwap Service - Interacts with WaltSwapV2 smart contract
/// Contract: 0x31169C501C316Fa6ec2e4E483ab32C09F8337149 on Lisk Sepolia
/// Verified: https://sepolia-blockscout.lisk.com/address/0x31169C501C316Fa6ec2e4E483ab32C09F8337149#code
class WaltSwapService {
  static const String contractAddress = '0x31169C501C316Fa6ec2e4E483ab32C09F8337149';
  static const String rpcUrl = 'https://rpc.sepolia-api.lisk.com';
  static const int chainId = 4202;
  
  // Token addresses
  static const Map<String, String> tokenContracts = {
    'LSK': '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e',
    'ETH': '0x292D54495d4C9Af56D86fA6cAF25591037EF80b3',
    'POL': '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e',
  };
  
  // Token prices in USD
  static const Map<String, double> tokenPrices = {
    'LSK': 1.0,
    'ETH': 3500.0,
    'POL': 0.5,
  };

  late web3.Web3Client _web3Client;
  late web3.DeployedContract _swapContract;
  
  // WaltSwapV2 ABI (using swap function with tuple parameter)
  static const String _swapAbi = '''[
    {"inputs":[{"components":[{"internalType":"address","name":"fromToken","type":"address"},{"internalType":"address","name":"toToken","type":"address"},{"internalType":"uint256","name":"fromAmount","type":"uint256"},{"internalType":"uint256","name":"minToAmount","type":"uint256"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"internalType":"struct WaltSwapV2.SwapParams","name":"params","type":"tuple"}],"name":"swap","outputs":[{"components":[{"internalType":"uint256","name":"toAmount","type":"uint256"},{"internalType":"uint256","name":"adminFee","type":"uint256"},{"internalType":"uint256","name":"swapId","type":"uint256"}],"internalType":"struct WaltSwapV2.SwapResult","name":"result","type":"tuple"}],"stateMutability":"nonpayable","type":"function"},
    {"inputs":[{"internalType":"address","name":"fromToken","type":"address"},{"internalType":"address","name":"toToken","type":"address"},{"internalType":"uint256","name":"fromAmount","type":"uint256"}],"name":"getSwapQuote","outputs":[{"internalType":"uint256","name":"toAmount","type":"uint256"},{"internalType":"uint256","name":"adminFee","type":"uint256"}],"stateMutability":"view","type":"function"},
    {"inputs":[{"internalType":"address","name":"token","type":"address"}],"name":"getPoolBalance","outputs":[{"internalType":"uint256","name":"balance","type":"uint256"}],"stateMutability":"view","type":"function"},
    {"inputs":[],"name":"feeReceiver","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
    {"inputs":[],"name":"adminFeeBps","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
    {"inputs":[],"name":"VERSION","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},
    {"inputs":[],"name":"NAME","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"}
  ]''';
  
  // ERC20 ABI for approve and allowance
  static const String _erc20Abi = '''[
    {"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
    {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
    {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
  ]''';

  WaltSwapService() {
    final httpClient = http.Client();
    _web3Client = web3.Web3Client(rpcUrl, httpClient);
    
    _swapContract = web3.DeployedContract(
      web3.ContractAbi.fromJson(_swapAbi, 'WaltSwapV2'),
      web3.EthereumAddress.fromHex(contractAddress),
    );
  }

  /// Get swap quote from contract
  Future<SwapQuote> getSwapQuote({
    required String fromToken,
    required String toToken,
    required double fromAmount,
  }) async {
    final fromTokenAddress = tokenContracts[fromToken.toUpperCase()];
    final toTokenAddress = tokenContracts[toToken.toUpperCase()];
    
    if (fromTokenAddress == null || toTokenAddress == null) {
      throw Exception('Unsupported token');
    }
    
    try {
      final result = await _web3Client.call(
        contract: _swapContract,
        function: _swapContract.function('getSwapQuote'),
        params: [
          web3.EthereumAddress.fromHex(fromTokenAddress),
          web3.EthereumAddress.fromHex(toTokenAddress),
          BigInt.from(fromAmount * 1e18),
        ],
      );
      
      final toAmount = (result[0] as BigInt).toDouble() / 1e18;
      final adminFee = (result[1] as BigInt).toDouble() / 1e18;
      
      return SwapQuote(
        fromToken: fromToken,
        toToken: toToken,
        fromAmount: fromAmount,
        toAmount: toAmount,
        adminFee: adminFee,
        exchangeRate: toAmount / (fromAmount - adminFee),
      );
    } catch (e) {
      print('[WaltSwap] getSwapQuote error: $e');
      // Fallback to local calculation
      final adminFee = fromAmount * 0.002;
      final amountAfterFee = fromAmount - adminFee;
      final fromPrice = tokenPrices[fromToken.toUpperCase()] ?? 1.0;
      final toPrice = tokenPrices[toToken.toUpperCase()] ?? 1.0;
      final toAmount = amountAfterFee * fromPrice / toPrice;
      
      return SwapQuote(
        fromToken: fromToken,
        toToken: toToken,
        fromAmount: fromAmount,
        toAmount: toAmount,
        adminFee: adminFee,
        exchangeRate: fromPrice / toPrice,
      );
    }
  }

  /// Check and approve token allowance
  Future<String?> approveToken({
    required String token,
    required double amount,
    required web3.Credentials credentials,
  }) async {
    final tokenAddress = tokenContracts[token.toUpperCase()];
    if (tokenAddress == null) {
      throw Exception('Unsupported token: $token');
    }
    
    final erc20Contract = web3.DeployedContract(
      web3.ContractAbi.fromJson(_erc20Abi, 'ERC20'),
      web3.EthereumAddress.fromHex(tokenAddress),
    );
    
    final userAddress = credentials.address;
    final spender = web3.EthereumAddress.fromHex(contractAddress);
    final amountWei = BigInt.from(amount * 1e18);
    
    // Check current allowance
    final allowanceResult = await _web3Client.call(
      contract: erc20Contract,
      function: erc20Contract.function('allowance'),
      params: [userAddress, spender],
    );
    
    final currentAllowance = allowanceResult[0] as BigInt;
    print('[WaltSwap] Current allowance: ${currentAllowance.toDouble() / 1e18} $token');
    
    if (currentAllowance >= amountWei) {
      print('[WaltSwap] Sufficient allowance, no approval needed');
      return null; // No approval needed
    }
    
    // Approve max amount
    print('[WaltSwap] Approving $token for WaltSwap...');
    final maxApproval = BigInt.parse('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', radix: 16);
    
    final approveTx = web3.Transaction.callContract(
      contract: erc20Contract,
      function: erc20Contract.function('approve'),
      parameters: [spender, maxApproval],
      maxGas: 100000,
    );
    
    final txHash = await _web3Client.sendTransaction(
      credentials,
      approveTx,
      chainId: chainId,
    );
    
    print('[WaltSwap] Approval TX: $txHash');
    
    // Wait for confirmation
    await Future.delayed(const Duration(seconds: 3));
    
    return txHash;
  }

  /// Execute swap via WaltSwap contract
  Future<SwapResult> executeSwap({
    required String fromToken,
    required String toToken,
    required double fromAmount,
    required double minToAmount,
    required web3.Credentials credentials,
    Function(String)? onStatusUpdate,
  }) async {
    final fromTokenAddress = tokenContracts[fromToken.toUpperCase()];
    final toTokenAddress = tokenContracts[toToken.toUpperCase()];
    
    if (fromTokenAddress == null || toTokenAddress == null) {
      throw Exception('Unsupported token');
    }
    
    print('[WaltSwap] ========== SWAP EXECUTION START ==========');
    print('[WaltSwap] From: $fromAmount $fromToken');
    print('[WaltSwap] To: $toToken (min: $minToAmount)');
    print('[WaltSwap] Contract: $contractAddress');
    
    try {
      // Step 1: Approve token
      onStatusUpdate?.call('Approving $fromToken...');
      final approvalTx = await approveToken(
        token: fromToken,
        amount: fromAmount,
        credentials: credentials,
      );
      if (approvalTx != null) {
        print('[WaltSwap] Approval TX: $approvalTx');
        await Future.delayed(const Duration(seconds: 2));
      }
      
      // Step 2: Execute swap using swap() with tuple parameter
      onStatusUpdate?.call('Executing swap...');
      final fromAmountWei = BigInt.from(fromAmount * 1e18);
      final minToAmountWei = BigInt.from(minToAmount * 1e18);
      final deadline = BigInt.zero; // No deadline (0 means no deadline check)
      
      // Create SwapParams tuple: (fromToken, toToken, fromAmount, minToAmount, deadline)
      final swapParams = [
        web3.EthereumAddress.fromHex(fromTokenAddress),
        web3.EthereumAddress.fromHex(toTokenAddress),
        fromAmountWei,
        minToAmountWei,
        deadline,
      ];
      
      final swapTx = web3.Transaction.callContract(
        contract: _swapContract,
        function: _swapContract.function('swap'),
        parameters: [swapParams], // Pass as tuple
        maxGas: 350000,
      );
      
      final txHash = await _web3Client.sendTransaction(
        credentials,
        swapTx,
        chainId: chainId,
      );
      
      print('[WaltSwap] Swap TX: $txHash');
      
      // Wait for confirmation (increased to 8 seconds for block confirmation)
      onStatusUpdate?.call('Waiting for confirmation...');
      await Future.delayed(const Duration(seconds: 8));
      
      // Get actual output from quote
      final quote = await getSwapQuote(
        fromToken: fromToken,
        toToken: toToken,
        fromAmount: fromAmount,
      );
      
      print('[WaltSwap] Swap completed!');
      print('[WaltSwap] Output: ${quote.toAmount} $toToken');
      print('[WaltSwap] Admin Fee: ${quote.adminFee} $fromToken');
      print('[WaltSwap] ========== SWAP EXECUTION END ==========');
      
      return SwapResult(
        success: true,
        txHash: txHash,
        fromToken: fromToken,
        toToken: toToken,
        fromAmount: fromAmount,
        toAmount: quote.toAmount,
        adminFee: quote.adminFee,
      );
    } catch (e) {
      print('[WaltSwap] Swap error: $e');
      return SwapResult(
        success: false,
        error: e.toString(),
        fromToken: fromToken,
        toToken: toToken,
        fromAmount: fromAmount,
      );
    }
  }

  /// Get pool balance for a token
  Future<double> getPoolBalance(String token) async {
    final tokenAddress = tokenContracts[token.toUpperCase()];
    if (tokenAddress == null) return 0;
    
    try {
      final result = await _web3Client.call(
        contract: _swapContract,
        function: _swapContract.function('getPoolBalance'),
        params: [web3.EthereumAddress.fromHex(tokenAddress)],
      );
      
      return (result[0] as BigInt).toDouble() / 1e18;
    } catch (e) {
      print('[WaltSwap] getPoolBalance error: $e');
      return 0;
    }
  }

  /// Send swap notification to Firestore
  Future<void> sendSwapNotification({
    required String userAddress,
    required String fromToken,
    required String toToken,
    required double fromAmount,
    required double toAmount,
    required String txHash,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userAddress.toLowerCase())
          .collection('notifications')
          .add({
        'type': 'swap',
        'title': 'Swap Successful',
        'message': 'Swapped $fromAmount $fromToken for ${toAmount.toStringAsFixed(4)} $toToken',
        'fromToken': fromToken,
        'toToken': toToken,
        'fromAmount': fromAmount,
        'toAmount': toAmount,
        'txHash': txHash,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
      print('[WaltSwap] Notification sent to Firestore');
    } catch (e) {
      print('[WaltSwap] Failed to send notification: $e');
    }
  }

  /// Get exchange rate between two tokens
  double getExchangeRate(String fromToken, String toToken) {
    final fromPrice = tokenPrices[fromToken.toUpperCase()] ?? 1.0;
    final toPrice = tokenPrices[toToken.toUpperCase()] ?? 1.0;
    return fromPrice / toPrice;
  }

  void dispose() {
    _web3Client.dispose();
  }
}

/// Swap quote model
class SwapQuote {
  final String fromToken;
  final String toToken;
  final double fromAmount;
  final double toAmount;
  final double adminFee;
  final double exchangeRate;

  SwapQuote({
    required this.fromToken,
    required this.toToken,
    required this.fromAmount,
    required this.toAmount,
    required this.adminFee,
    required this.exchangeRate,
  });
}

/// Swap result model
class SwapResult {
  final bool success;
  final String? txHash;
  final String fromToken;
  final String toToken;
  final double fromAmount;
  final double? toAmount;
  final double? adminFee;
  final String? error;

  SwapResult({
    required this.success,
    this.txHash,
    required this.fromToken,
    required this.toToken,
    required this.fromAmount,
    this.toAmount,
    this.adminFee,
    this.error,
  });
}
