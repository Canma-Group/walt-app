import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../services/qris_payment_service.dart';
import '../../services/web3auth_service.dart';
import '../../services/transaction_service.dart';
import '../../models/transaction_model.dart';
import '../../config/env.dart';

class QrisPaymentPage extends StatefulWidget {
  final String qrisPayload;
  final double amountIdr;
  final String? merchantName;

  const QrisPaymentPage({
    Key? key,
    required this.qrisPayload,
    required this.amountIdr,
    this.merchantName,
  }) : super(key: key);

  @override
  State<QrisPaymentPage> createState() => _QrisPaymentPageState();
}

class _QrisPaymentPageState extends State<QrisPaymentPage> {
  final QrisPaymentService _paymentService = QrisPaymentService();
  final Web3AuthService _web3AuthService = Web3AuthService();
  final TransactionService _transactionService = TransactionService();
  
  QrisPaymentIntent? _paymentIntent;
  QrisPaymentStatus? _paymentStatus;
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isSponsoringGas = false;
  String? _error;
  Timer? _statusPollTimer;
  
  // Gas sponsorship info
  double? _estimatedGasCostIdr;
  double? _adminFeeIdr;

  // Color scheme matching home page
  static const Color _primaryBlue = Color(0xFF1264EF);
  static const Color _lightBg = Color(0xFFE8EEF6); // Match home page background
  static const Color _textDark = Color(0xFF14193F);
  static const Color _textGrey = Color(0xFF3A3A3A);

  // Multi-token support (WaltQRPayV3)
  String _selectedToken = 'LSK';
  final Map<String, Map<String, dynamic>> _supportedTokens = {
    'LSK': {
      'address': '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e',
      'symbol': 'LSK',
      'name': 'Lisk',
      'color': Color(0xFF000000), // Match home page
    },
    'ETH': {
      'address': '0x292D54495d4C9Af56D86fA6cAF25591037EF80b3',
      'symbol': 'ETH',
      'name': 'Ethereum',
      'color': Color(0xFF627EEA), // Match home page
    },
    'POL': {
      'address': '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e',
      'symbol': 'POL',
      'name': 'Polygon',
      'color': Color(0xFF8247E5), // Match home page
    },
  };

  // HACKATHON: Use Lisk Sepolia Testnet
  String get _selectedTokenAddress => _supportedTokens[_selectedToken]!['address'] as String;
  static const String _waltQRPayV3Address = '0x4f11677bcF14FEEfD906Dd978a4E4Ad54b4Ce194'; // WaltQRPayV3
  static const String _liskRpcUrl = 'https://rpc.sepolia-api.lisk.com';
  static const int _chainId = 4202;

  @override
  void initState() {
    super.initState();
    _createPaymentIntent();
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _createPaymentIntent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authState = context.read<AuthBloc>().state;
      String? walletAddress;
      
      // Handle both AuthSuccess and AuthNeedsWalletVerification states
      if (authState is AuthSuccess) {
        walletAddress = authState.user.walletAddress;
      } else if (authState is AuthNeedsWalletVerification) {
        walletAddress = authState.user.walletAddress;
      }
      
      if (walletAddress == null || walletAddress.isEmpty) {
        throw Exception('User not authenticated or wallet not found');
      }
      
      // Use V3 API with multi-token support
      final intent = await _paymentService.createPaymentIntentV3(
        walletAddress: walletAddress,
        qrisPayload: widget.qrisPayload,
        amountIdr: widget.amountIdr,
        tokenSymbol: _selectedToken,
      );

      setState(() {
        _paymentIntent = intent;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _processPayment() async {
    if (_paymentIntent == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      // Get wallet address and private key from Web3Auth
      final privateKey = await _web3AuthService.getPrivateKey();
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not available. Please re-login.');
      }

      // Check LSK token balance (ERC-20) and native LSK for gas
      final credentials = EthPrivateKey.fromHex(privateKey);
      final senderAddress = credentials.address;
      final httpClient = http.Client();
      final web3Client = Web3Client(_liskRpcUrl, httpClient);
      
      try {
        // Check native ETH balance (for gas) - Lisk Sepolia uses ETH for gas
        final nativeBalance = await web3Client.getBalance(senderAddress);
        final nativeEth = nativeBalance.getInWei / BigInt.from(1e18);
        
        // Check ERC-20 token balance (selected token)
        final tokenBalance = await _getErc20Balance(
          web3Client, 
          _selectedTokenAddress, 
          senderAddress.hex,
        );
        final tokenAmount = tokenBalance / BigInt.from(1e18);
        
        final requiredLsk = double.tryParse(_paymentIntent!.lskAmountExpected) ?? 0;
        final gasEstimateEth = 0.0001; // ~0.0001 ETH untuk gas di Lisk
        
        if (Env.enableDebugLogs) {
          print('[QrisPayment] Wallet: ${senderAddress.hex}');
          print('[QrisPayment] Native ETH (gas): $nativeEth');
          print('[QrisPayment] $_selectedToken Token: $tokenAmount');
          print('[QrisPayment] Required: $requiredLsk $_selectedToken + $gasEstimateEth ETH gas');
        }
        
        // Check if enough native ETH for gas (Lisk Sepolia uses ETH for gas)
        if (nativeEth < gasEstimateEth) {
          if (Env.enableDebugLogs) {
            print('[QrisPayment] User needs gas sponsorship');
          }
          
          // Request gas sponsorship from backend
          setState(() => _isSponsoringGas = true);
          
          final sponsorResult = await _requestGasSponsorship(
            walletAddress: senderAddress.hex,
            paymentId: _paymentIntent!.paymentId,
            escrowAddress: _paymentIntent!.escrowAddress,
            lskAmount: _paymentIntent!.lskAmountExpected,
          );
          
          setState(() => _isSponsoringGas = false);
          
          if (!sponsorResult['success']) {
            throw Exception(
              'Gas sponsorship gagal: ${sponsorResult['error']}\n\n'
              'Wallet: ${senderAddress.hex.substring(0, 10)}...\n'
              'ETH (gas): ${nativeEth.toStringAsFixed(6)} ETH\n'
              'Dibutuhkan: ~$gasEstimateEth ETH untuk gas'
            );
          }
          
          // Store gas cost for admin fee calculation
          _estimatedGasCostIdr = (sponsorResult['gasCostIdr'] as num?)?.toDouble() ?? 5.0;
          
          if (Env.enableDebugLogs) {
            print('[QrisPayment] Gas sponsored! TxHash: ${sponsorResult['txHash']}');
            print('[QrisPayment] Gas cost: Rp $_estimatedGasCostIdr');
          }
          
          // Wait for gas to arrive (2 seconds should be enough on Lisk L2)
          await Future.delayed(const Duration(seconds: 2));
        }
        
        // Check if enough tokens for payment
        if (tokenAmount < requiredLsk) {
          throw Exception(
            'Saldo $_selectedToken Token tidak cukup!\n\n'
            'Wallet: ${senderAddress.hex.substring(0, 10)}...\n'
            'Network: Lisk Sepolia Testnet\n'
            '$_selectedToken Token: ${tokenAmount.toStringAsFixed(6)} $_selectedToken\n'
            'Dibutuhkan: ${requiredLsk.toStringAsFixed(4)} $_selectedToken\n\n'
            '⚠️ Token Anda mungkin ada di chain lain.\n'
            'Top up via menu Top Up Simulasi.'
          );
        }
      } finally {
        web3Client.dispose();
        httpClient.close();
      }

      // Step 1: Use calldata from V3 payment intent (already generated)
      final calldata = _paymentIntent!.calldata;
      final amountWei = _paymentIntent!.tokenAmountWei != null 
          ? BigInt.parse(_paymentIntent!.tokenAmountWei!) 
          : BigInt.from(double.parse(_paymentIntent!.lskAmountExpected) * 1e18);
      
      if (calldata == null || calldata.isEmpty) {
        throw Exception('Calldata not available. Please try again.');
      }
      
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Using V3 calldata: ${calldata.substring(0, 50)}...');
        print('[QrisPayment] Amount: $amountWei wei');
      }
      
      // Step 2: Approve escrow contract to spend tokens
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Approving escrow contract...');
      }
      final approveTxHash = await _approveEscrowContract(
        privateKey: privateKey,
        amount: _paymentIntent!.lskAmountExpected,
      );
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Approve txHash: $approveTxHash');
      }
      
      // Wait for approval to be mined
      await _waitForTransaction(approveTxHash);
      
      // Step 3: Call pay() on contract with backend-generated calldata
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Calling pay() on contract...');
      }
      final txHash = await _callContractWithCalldata(
        privateKey: privateKey,
        calldata: calldata,
      );

      if (Env.enableDebugLogs) {
        print('[QrisPayment] Transfer txHash: $txHash');
      }

      // V3: Notify backend to trigger settlement bot (Xendit payout)
      await _paymentService.notifyV3PaymentCompleted(
        paymentId: _paymentIntent!.paymentId,
        txHash: txHash,
        amountIdr: widget.amountIdr,
        tokenSymbol: _selectedToken,
        merchantName: widget.merchantName,
      );

      // Save transaction to history
      await _saveTransactionToHistory(txHash);

      // Mark as paid
      if (Env.enableDebugLogs) {
        print('[QrisPayment] ✅ Payment completed! Setting status to PAID');
        print('[QrisPayment] TxHash: $txHash');
      }
      
      setState(() {
        _paymentStatus = QrisPaymentStatus(
          paymentId: _paymentIntent!.paymentId,
          status: 'PAID',
          amountIdr: widget.amountIdr,
          lskAmountExpected: _paymentIntent!.lskAmountExpected,
          escrowAddress: _paymentIntent!.escrowAddress,
          txHash: txHash,
          receiptId: 'V3-${DateTime.now().millisecondsSinceEpoch}',
        );
        _isProcessing = false;
      });
      
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Status after setState: ${_paymentStatus?.status}');
        print('[QrisPayment] isPaid: ${_paymentStatus?.isPaid}');
      }

    } catch (e) {
      String errorMsg = e.toString();
      
      // Parse RPC errors untuk pesan yang lebih jelas
      if (errorMsg.contains('insufficient funds')) {
        errorMsg = 'Saldo LSK tidak cukup untuk gas fee.\n'
            'Pastikan Anda memiliki native LSK di wallet untuk membayar biaya transaksi.';
      }
      
      setState(() {
        _error = errorMsg;
        _isProcessing = false;
      });
    }
  }

  /// Approve escrow contract to spend user's tokens
  Future<String> _approveEscrowContract({
    required String privateKey,
    required String amount,
  }) async {
    final httpClient = http.Client();
    final web3Client = Web3Client(_liskRpcUrl, httpClient);

    try {
      final credentials = EthPrivateKey.fromHex(privateKey);
      final senderAddress = credentials.address;

      // Parse amount to wei (18 decimals) - approve slightly more for safety
      final amountDouble = double.tryParse(amount) ?? 0;
      final amountWei = BigInt.from(amountDouble * 1.1 * 1e18); // 10% buffer

      // ERC-20 approve function signature: approve(address spender, uint256 amount)
      final approveFunctionSignature = '0x095ea7b3';
      final spenderPadded = _waltQRPayV3Address.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final amountPadded = amountWei.toRadixString(16).padLeft(64, '0');
      final data = '$approveFunctionSignature$spenderPadded$amountPadded';

      final gasPrice = await web3Client.getGasPrice();
      final nonce = await web3Client.getTransactionCount(senderAddress);

      final transaction = Transaction(
        to: EthereumAddress.fromHex(_selectedTokenAddress),
        gasPrice: gasPrice,
        maxGas: 60000,
        nonce: nonce.toInt(),
        data: hexToBytes(data),
      );

      final signedTx = await web3Client.signTransaction(
        credentials,
        transaction,
        chainId: _chainId,
      );

      final txHash = await web3Client.sendRawTransaction(signedTx);
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Approve txHash: $txHash');
      }
      return txHash;
    } finally {
      web3Client.dispose();
      httpClient.close();
    }
  }

  /// Wait for transaction to be mined
  Future<void> _waitForTransaction(String txHash) async {
    final httpClient = http.Client();
    final web3Client = Web3Client(_liskRpcUrl, httpClient);
    
    try {
      // Poll for transaction receipt (max 30 seconds)
      for (int i = 0; i < 15; i++) {
        try {
          final receipt = await web3Client.getTransactionReceipt(txHash);
          if (receipt != null) {
            if (Env.enableDebugLogs) {
              print('[QrisPayment] Transaction mined in block: ${receipt.blockNumber}');
            }
            return;
          }
        } catch (e) {
          // Receipt not available yet
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      // If we get here, transaction might still be pending but we'll proceed
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Transaction not yet mined, proceeding anyway...');
      }
    } finally {
      web3Client.dispose();
      httpClient.close();
    }
  }

  /// Call contract with pre-encoded calldata from backend
  Future<String> _callContractWithCalldata({
    required String privateKey,
    required String calldata,
  }) async {
    final httpClient = http.Client();
    final web3Client = Web3Client(_liskRpcUrl, httpClient);

    try {
      final credentials = EthPrivateKey.fromHex(privateKey);
      final senderAddress = credentials.address;

      int gasLimit;
      try {
        final estimatedGas = await web3Client.estimateGas(
          sender: senderAddress,
          to: EthereumAddress.fromHex(_waltQRPayV3Address),
          data: hexToBytes(calldata),
        );
        gasLimit = (estimatedGas.toInt() * 12 / 10).ceil();
        if (gasLimit < 500000) gasLimit = 500000;
      } catch (e) {
        gasLimit = 900000;
      }

      final gasPrice = await web3Client.getGasPrice();
      final nonce = await web3Client.getTransactionCount(senderAddress);

      final transaction = Transaction(
        to: EthereumAddress.fromHex(_waltQRPayV3Address),
        gasPrice: gasPrice,
        maxGas: gasLimit, // Higher gas for contract call
        nonce: nonce.toInt(),
        data: hexToBytes(calldata),
      );

      final signedTx = await web3Client.signTransaction(
        credentials,
        transaction,
        chainId: _chainId,
      );

      final txHash = await web3Client.sendRawTransaction(signedTx);
      return txHash;
    } finally {
      web3Client.dispose();
      httpClient.close();
    }
  }

  /// Call pay() on QrisEscrowV2 contract
  Future<String> _payViaEscrowContract({
    required String privateKey,
    required String orderId, // Already bytes32 from backend
    required String merchantId,
    required String amount,
  }) async {
    final httpClient = http.Client();
    final web3Client = Web3Client(_liskRpcUrl, httpClient);

    try {
      final credentials = EthPrivateKey.fromHex(privateKey);
      final senderAddress = credentials.address;

      // Parse amount to wei (18 decimals)
      final amountDouble = double.tryParse(amount) ?? 0;
      final amountWei = BigInt.from(amountDouble * 1e18);

      // pay(bytes32 orderId, string merchantId, uint256 totalAmount)
      // Function selector: keccak256("pay(bytes32,string,uint256)")[:4] = 0x8f1d6407
      const payFunctionSignature = '8f1d6407';
      
      // ABI Encoding for dynamic string:
      // [0-31]   orderId (bytes32)
      // [32-63]  offset to string data = 96 (0x60) - points to byte 96
      // [64-95]  totalAmount (uint256)
      // [96-127] string length
      // [128+]   string data (padded to 32 bytes)
      
      // 1. orderId (bytes32) - remove 0x and take 64 hex chars
      final orderIdHex = orderId.replaceFirst('0x', '').padLeft(64, '0').substring(0, 64);
      
      // 2. Offset to string = 96 (3 * 32 bytes for head params)
      final offsetHex = '0000000000000000000000000000000000000000000000000000000000000060';
      
      // 3. totalAmount (uint256)
      final amountHex = amountWei.toRadixString(16).padLeft(64, '0');
      
      // 4. String encoding: length + data
      final merchantBytes = utf8.encode(merchantId);
      final stringLengthHex = merchantBytes.length.toRadixString(16).padLeft(64, '0');
      
      // 5. String data padded to multiple of 32 bytes
      final stringDataHex = merchantBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final paddedStringData = stringDataHex.padRight(((merchantBytes.length + 31) ~/ 32) * 64, '0');
      
      final data = '0x$payFunctionSignature$orderIdHex$offsetHex$amountHex$stringLengthHex$paddedStringData';
      
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Contract call data: ${data.substring(0, 50)}...');
        print('[QrisPayment] OrderId: $orderId');
        print('[QrisPayment] MerchantId: $merchantId');
        print('[QrisPayment] Amount: $amountWei wei');
      }

      final gasPrice = await web3Client.getGasPrice();
      final nonce = await web3Client.getTransactionCount(senderAddress);

      final transaction = Transaction(
        to: EthereumAddress.fromHex(_waltQRPayV3Address),
        gasPrice: gasPrice,
        maxGas: 250000, // Higher gas for contract call
        nonce: nonce.toInt(),
        data: hexToBytes(data),
      );

      final signedTx = await web3Client.signTransaction(
        credentials,
        transaction,
        chainId: _chainId,
      );

      final txHash = await web3Client.sendRawTransaction(signedTx);
      return txHash;
    } finally {
      web3Client.dispose();
      httpClient.close();
    }
  }

  /// Generate bytes32 orderId from paymentId using keccak256
  String _generateOrderIdBytes32(String paymentId) {
    // Simple hash: convert paymentId to bytes and hash
    // This matches the backend's ethers.keccak256(ethers.toUtf8Bytes(paymentId))
    final bytes = paymentId.codeUnits;
    
    // For simplicity, we'll use a deterministic approach
    // In production, this should use proper keccak256
    // For now, pad the paymentId to 32 bytes
    final paddedHex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final result = paddedHex.padRight(64, '0');
    return '0x$result';
  }

  Uint8List hexToBytes(String hex) {
    hex = hex.replaceFirst('0x', '');
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Transfer LSK tokens to escrow address (simple ERC-20 transfer)
  Future<String> _transferLskToEscrow({
    required String privateKey,
    required String escrowAddress,
    required String amount,
  }) async {
    final httpClient = http.Client();
    final web3Client = Web3Client(_liskRpcUrl, httpClient);

    try {
      final credentials = EthPrivateKey.fromHex(privateKey);
      final senderAddress = credentials.address;

      // Parse amount to wei (18 decimals)
      final amountDouble = double.tryParse(amount) ?? 0;
      final amountWei = BigInt.from(amountDouble * 1e18);

      // ERC-20 transfer function signature
      final transferFunctionSignature = '0xa9059cbb';
      
      // Encode function data: transfer(address to, uint256 amount)
      final toAddressPadded = escrowAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final amountPadded = amountWei.toRadixString(16).padLeft(64, '0');
      final data = '$transferFunctionSignature$toAddressPadded$amountPadded';

      final gasPrice = await web3Client.getGasPrice();
      final nonce = await web3Client.getTransactionCount(senderAddress);

      final transaction = Transaction(
        to: EthereumAddress.fromHex(_selectedTokenAddress),
        gasPrice: gasPrice,
        maxGas: 100000,
        nonce: nonce.toInt(),
        data: hexToBytes(data),
      );

      final signedTx = await web3Client.signTransaction(
        credentials,
        transaction,
        chainId: _chainId,
      );

      final txHash = await web3Client.sendRawTransaction(signedTx);
      return txHash;
    } finally {
      web3Client.dispose();
      httpClient.close();
    }
  }

  /// Get ERC-20 token balance
  Future<BigInt> _getErc20Balance(
    Web3Client web3Client,
    String tokenAddress,
    String walletAddress,
  ) async {
    try {
      // balanceOf(address) function signature
      final balanceOfSignature = '0x70a08231';
      final addressPadded = walletAddress.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
      final data = '$balanceOfSignature$addressPadded';
      
      final result = await web3Client.callRaw(
        contract: EthereumAddress.fromHex(tokenAddress),
        data: hexToBytes(data),
      );
      
      if (result.isEmpty) return BigInt.zero;
      
      // Result is hex string, parse it
      String hexResult = result;
      if (hexResult.startsWith('0x')) {
        hexResult = hexResult.substring(2);
      }
      if (hexResult.isEmpty) return BigInt.zero;
      
      return BigInt.parse(hexResult, radix: 16);
    } catch (e) {
      if (Env.enableDebugLogs) print('[QrisPayment] Error getting ERC-20 balance: $e');
      return BigInt.zero;
    }
  }

  Future<Map<String, dynamic>> _requestGasSponsorship({
    required String walletAddress,
    required String paymentId,
    required String escrowAddress,
    required String lskAmount,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Env.backendUrl}/gas/sponsor'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'walletAddress': walletAddress,
          'paymentId': paymentId,
          'escrowAddress': escrowAddress,
          'lskAmount': lskAmount,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'txHash': data['data']?['txHash'],
          'gasAmountEth': data['data']?['gasAmountEth'],
          'gasCostIdr': data['data']?['gasCostIdr'],
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['error'] ?? 'Gas sponsorship failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Save QRIS payment transaction to history
  Future<void> _saveTransactionToHistory(String txHash) async {
    try {
      final authState = context.read<AuthBloc>().state;
      String? walletAddress;
      String? userName;
      
      if (authState is AuthSuccess) {
        walletAddress = authState.user.walletAddress;
        userName = authState.user.name;
      } else if (authState is AuthNeedsWalletVerification) {
        walletAddress = authState.user.walletAddress;
        userName = authState.user.name;
      }

      if (walletAddress == null) return;

      await _transactionService.createTransaction(
        senderWallet: walletAddress,
        senderName: userName ?? 'User',
        receiverWallet: _waltQRPayV3Address,
        receiverName: widget.merchantName ?? 'QRIS Merchant',
        amount: _paymentIntent?.lskAmountExpected ?? '0',
        token: _selectedToken,
        chainId: _chainId,
        chainName: 'Lisk Sepolia',
        type: TransactionType.qrisPayment,
        memo: 'QRIS Payment - ${widget.merchantName ?? 'Merchant'}',
        amountInIdr: widget.amountIdr,
      );

      // Update with txHash
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Transaction saved to history: $txHash');
      }
    } catch (e) {
      // Non-blocking - just log the error
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Failed to save transaction to history: $e');
      }
    }
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final status = await _paymentService.getPaymentStatus(_paymentIntent!.paymentId);
        
        setState(() {
          _paymentStatus = status;
        });

        if (status.isPaid) {
          _statusPollTimer?.cancel();
          setState(() {
            _isProcessing = false;
          });
        } else if (status.isExpired) {
          _statusPollTimer?.cancel();
          setState(() {
            _error = 'Payment expired';
            _isProcessing = false;
          });
        }
      } catch (e) {
        if (Env.enableDebugLogs) print('[QrisPayment] Poll error: $e');
      }
    });
  }

  String _formatCurrency(double value) {
    return value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  void _showWalletQRCode() {
    final authState = context.read<AuthBloc>().state;
    String? walletAddress;
    
    if (authState is AuthSuccess) {
      walletAddress = authState.user.walletAddress;
    } else if (authState is AuthNeedsWalletVerification) {
      walletAddress = authState.user.walletAddress;
    }
    
    if (walletAddress == null || walletAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wallet address not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final address = walletAddress; // Non-null local copy
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1628),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your Wallet Address',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: address,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      address,
                      style: GoogleFonts.robotoMono(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, color: _primaryBlue, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: address));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: const Text('Address copied!'),
                          backgroundColor: _primaryBlue,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Scan this QR to receive $_selectedToken',
              style: GoogleFonts.poppins(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'QRIS Payment',
          style: GoogleFonts.poppins(
            color: _textDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (Env.enableDebugLogs) {
      print('[QrisPayment] _buildBody called');
      print('[QrisPayment] _isLoading: $_isLoading');
      print('[QrisPayment] _error: $_error');
      print('[QrisPayment] _paymentStatus: ${_paymentStatus?.status}');
      print('[QrisPayment] isPaid: ${_paymentStatus?.isPaid}');
    }
    
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: _primaryBlue),
      );
    }

    if (_error != null && _paymentIntent == null) {
      return _buildErrorState();
    }

    if (_paymentStatus?.isPaid == true) {
      if (Env.enableDebugLogs) {
        print('[QrisPayment] Showing SUCCESS state!');
      }
      return _buildSuccessState();
    }

    return _buildPaymentConfirmation();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              'Error',
              style: GoogleFonts.poppins(
                color: _textDark,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: GoogleFonts.poppins(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _createPaymentIntent,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
              ),
              child: Text('Retry', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final timeStr = '$hour:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'pm' : 'am'}';
    final dateStr = '${now.day} ${_getMonthName(now.month)} ${now.year}';
    final txId = _paymentStatus?.txHash ?? _paymentStatus?.receiptId ?? '-';
    final shortTxId = txId.length > 14 ? '${txId.substring(0, 12)}...' : txId;
    
    // Calculate token amount from payment intent
    final tokenAmount = _paymentIntent?.lskAmountExpected ?? '0';
    final adminFee = (double.tryParse(tokenAmount) ?? 0) * 0.005; // 0.5% admin fee in token
    final totalTokenAmount = (double.tryParse(tokenAmount) ?? 0) + adminFee;
    
    return Container(
      color: const Color(0xFFE8EEF6),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Column(
          children: [
            // White card container
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  // Success icon - Figma gradient teal circle with inner border
                  Container(
                    width: 100,
                    height: 100,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment(0.37, 0.00),
                        end: Alignment(0.63, 1.00),
                        colors: [Color(0xFF045A5B), Color(0xFF08BFC1), Color(0xFF035A5B)],
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: const Center(
                          child: Icon(Icons.check, color: Colors.white, size: 45),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Amount in IDR
                  Text(
                    'Rp ${_formatCurrency(widget.amountIdr)}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Merchant info
                  Text(
                    'Transfer to ${widget.merchantName ?? 'Merchant'}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF3A3A3A),
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'QRIS Payment',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF3A3A3A),
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Divider
                  Container(
                    height: 1,
                    color: const Color(0xFF3A3A3A).withOpacity(0.3),
                  ),
                  const SizedBox(height: 20),
                  // Transaction details title
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Transaction details',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF3A3A3A),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Status row
                  _buildSuccessDetailRow('Status', 'Completed', isStatus: true),
                  const SizedBox(height: 12),
                  // Time row
                  _buildSuccessDetailRow('Time', timeStr),
                  const SizedBox(height: 12),
                  // Date row
                  _buildSuccessDetailRow('Date', dateStr),
                  const SizedBox(height: 12),
                  // Transaction ID row
                  _buildSuccessDetailRow('Trancaction ID', shortTxId, hasCopy: true, fullValue: txId),
                  const SizedBox(height: 16),
                  // Divider
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 20),
                    color: const Color(0xFF3A3A3A).withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  // Amount in token
                  _buildSuccessDetailRow('Amount', '$tokenAmount $_selectedToken'),
                  const SizedBox(height: 12),
                  // Admin fee (0.5%)
                  _buildSuccessDetailRow('Admin fee', '${adminFee.toStringAsFixed(6)} $_selectedToken'),
                  const SizedBox(height: 16),
                  // Divider
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 20),
                    color: const Color(0xFF3A3A3A).withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  // Total in token (bold) - right aligned
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${totalTokenAmount.toStringAsFixed(6)} $_selectedToken',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF3A3A3A),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            const SizedBox(height: 30),
            // Back to Dashboard button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1264EF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Back to Dashboard',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
  
  Widget _buildSuccessDetailRow(String label, String value, {bool isStatus = false, bool isBold = false, bool hasCopy = false, String? fullValue}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: const Color(0xFF3A3A3A),
            fontSize: 14,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        Row(
          children: [
            Text(
              value,
              style: GoogleFonts.poppins(
                color: isStatus ? const Color(0xFF4A915D) : const Color(0xFF3A3A3A),
                fontSize: 14,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (isStatus) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, color: Color(0xFF4A915D), size: 16),
            ],
            if (hasCopy && fullValue != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: fullValue));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Transaction ID copied!'),
                      backgroundColor: const Color(0xFF1264EF),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: const Icon(Icons.copy_outlined, color: Color(0xFF3A3A3A), size: 14),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(color: _textGrey, fontSize: 14),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTxHashRow(String txHash) {
    final blockscoutUrl = 'https://sepolia-blockscout.lisk.com/tx/$txHash';
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tx Hash',
                style: GoogleFonts.poppins(color: Colors.grey, fontSize: 14),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: txHash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Tx Hash copied!'),
                      backgroundColor: _primaryBlue,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Text(
                      '${txHash.substring(0, 10)}...${txHash.substring(txHash.length - 6)}',
                      style: GoogleFonts.poppins(
                        color: _primaryBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.copy, color: _primaryBlue, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(blockscoutUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(
              'View on Blockscout',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryBlue,
              side: BorderSide(color: _primaryBlue),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentConfirmation() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Merchant info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(Icons.store, color: _primaryBlue, size: 48),
                const SizedBox(height: 12),
                Text(
                  widget.merchantName ?? 'QRIS Merchant',
                  style: GoogleFonts.poppins(
                    color: _textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rp ${_formatCurrency(widget.amountIdr)}',
                  style: GoogleFonts.poppins(
                    color: _primaryBlue,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Token Selector (WaltQRPayV3 Multi-Token Support)
          Text(
            'Pay with',
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: _supportedTokens.entries.map((entry) {
                final isSelected = _selectedToken == entry.key;
                final tokenData = entry.value;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedToken = entry.key;
                      });
                      _createPaymentIntent();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? (tokenData['color'] as Color).withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected 
                            ? Border.all(color: tokenData['color'] as Color, width: 2)
                            : Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: Center(
                        child: Text(
                          tokenData['symbol'] as String,
                          style: GoogleFonts.poppins(
                            color: isSelected ? (tokenData['color'] as Color) : _textGrey,
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // Payment details
          Text(
            'Payment Details',
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildDetailRow('Amount (IDR)', 'Rp ${_formatCurrency(widget.amountIdr)}'),
                Divider(color: Colors.grey.withOpacity(0.2)),
                _buildDetailRow('$_selectedToken Amount', '${_paymentIntent?.lskAmountExpected ?? '0'} $_selectedToken'),
                Divider(color: Colors.grey.withOpacity(0.2)),
                _buildDetailRow('Network', 'Lisk Sepolia Testnet'),
                Divider(color: Colors.grey.withOpacity(0.2)),
                _buildDetailRow('Contract', _waltQRPayV3Address.substring(0, 10) + '...'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Error message
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.poppins(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // Processing state
          if (_isProcessing)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _paymentStatus?.status == 'TX_SUBMITTED'
                          ? 'Waiting for confirmation...'
                          : 'Processing payment...',
                      style: GoogleFonts.poppins(
                        color: _primaryBlue,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Pay button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _processPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                disabledBackgroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isProcessing ? 'Processing...' : 'Pay With My Assets',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(color: _textGrey, fontSize: 14),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeRow(String label, String value, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(color: _textDark, fontSize: 13),
                ),
                Text(
                  description,
                  style: GoogleFonts.poppins(color: _textGrey, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: _primaryBlue,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
