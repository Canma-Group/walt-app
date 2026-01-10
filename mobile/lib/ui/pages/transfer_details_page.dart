import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web3dart/web3dart.dart' as web3;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../services/multi_chain_service.dart';
import '../../services/web3auth_service.dart';
import '../../services/price_service.dart';
import '../../services/transaction_service.dart';
import '../../services/gas_sponsor_service.dart';
import '../../models/transaction_model.dart';
import '../../config/env.dart';

class TransferDetailsPage extends StatefulWidget {
  final String recipientId;
  final String recipientName;
  final String recipientWalletAddress;
  final String? recipientProfilePhoto;
  final bool isInternalUser;

  const TransferDetailsPage({
    Key? key,
    required this.recipientId,
    required this.recipientName,
    required this.recipientWalletAddress,
    this.recipientProfilePhoto,
    required this.isInternalUser,
  }) : super(key: key);

  @override
  State<TransferDetailsPage> createState() => _TransferDetailsPageState();
}

class _TransferDetailsPageState extends State<TransferDetailsPage> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _walletAddressController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  
  final MultiChainService _multiChainService = MultiChainService();
  final Web3AuthService _web3AuthService = Web3AuthService();
  final PriceService _priceService = PriceService();
  final TransactionService _transactionService = TransactionService();
  final GasSponsorService _gasSponsorService = GasSponsorService();
  
  String _selectedToken = 'POL';
  List<TokenBalance> _tokens = [];
  bool _isLoadingTokens = true;
  bool _isTransferring = false;
  String? _error;
  Map<String, double> _prices = {};
  
  // Gas Fee Sponsorship state
  GasFeeBreakdown? _feeBreakdown;
  bool _isCalculatingFees = false;
  
  // HACKATHON: Lisk Sepolia Testnet only
  static const Map<String, Map<String, dynamic>> _chainConfig = {
    'LSK': {
      'rpcUrl': 'https://rpc.sepolia-api.lisk.com',
      'chainId': 4202,
      'isNative': false,
      'tokenAddress': '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e', // MockLSK
      'chainName': 'Lisk Sepolia',
    },
    'ETH': {
      'rpcUrl': 'https://rpc.sepolia-api.lisk.com',
      'chainId': 4202,
      'isNative': true,
      'tokenAddress': '',
      'chainName': 'Lisk Sepolia',
    },
    'POL': {
      'rpcUrl': 'https://rpc.sepolia-api.lisk.com',
      'chainId': 4202,
      'isNative': false,
      'tokenAddress': '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e', // MockPOL
      'chainName': 'Lisk Sepolia',
    },
  };
  
  bool _isSponsoringGas = false;

  @override
  void initState() {
    super.initState();
    _loadTokens();
    _loadPrices();
    
    // Pre-fill wallet address if internal user
    if (widget.isInternalUser && widget.recipientWalletAddress.isNotEmpty) {
      _walletAddressController.text = widget.recipientWalletAddress;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _walletAddressController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadTokens() async {
    try {
      final authState = context.read<AuthBloc>().state;
      
      // Handle both AuthSuccess and AuthNeedsWalletVerification states
      String? walletAddress;
      String? token;
      if (authState is AuthSuccess) {
        walletAddress = authState.user.walletAddress;
        token = authState.user.token;
      } else if (authState is AuthNeedsWalletVerification) {
        walletAddress = authState.user.walletAddress;
        token = authState.user.token;
      }
      
      if (walletAddress == null || walletAddress.isEmpty) {
        setState(() {
          _error = 'User not authenticated';
          _isLoadingTokens = false;
        });
        return;
      }

      final tokens = await _multiChainService.getTokenBalances(
        walletAddress,
        token ?? '',
      );

      setState(() {
        _tokens = tokens;
        _isLoadingTokens = false;
        // Default to LSK if available
        if (tokens.any((t) => t.symbol == 'LSK')) {
          _selectedToken = 'LSK';
        } else if (tokens.isNotEmpty) {
          _selectedToken = tokens.first.symbol;
        }
      });
    } catch (e) {
      print('Error loading tokens: $e');
      setState(() {
        _error = 'Failed to load tokens';
        _isLoadingTokens = false;
      });
    }
  }

  Future<void> _loadPrices() async {
    try {
      final prices = await _priceService.fetchPricesIDR(['LSK', 'ETH', 'POL']);
      setState(() => _prices = prices);
    } catch (e) {
      print('Error loading prices: $e');
    }
  }

  /// Calculate gas fee breakdown when amount changes
  Future<void> _calculateGasFees() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      setState(() => _feeBreakdown = null);
      return;
    }
    
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() => _feeBreakdown = null);
      return;
    }
    
    setState(() => _isCalculatingFees = true);
    
    try {
      final config = _chainConfig[_selectedToken] ?? _chainConfig['LSK']!;
      final rpcUrl = config['rpcUrl'] as String;
      final isNative = config['isNative'] as bool;
      
      final breakdown = await _gasSponsorService.calculateGasFeeBreakdown(
        token: _selectedToken,
        transferAmount: amount,
        rpcUrl: rpcUrl,
        isNative: isNative,
      );
      
      if (mounted) {
        setState(() {
          _feeBreakdown = breakdown;
          _isCalculatingFees = false;
        });
      }
    } catch (e) {
      print('[Transfer] Error calculating fees: $e');
      if (mounted) {
        setState(() => _isCalculatingFees = false);
      }
    }
  }

  TokenBalance? get _selectedTokenBalance {
    try {
      return _tokens.firstWhere((t) => t.symbol == _selectedToken);
    } catch (e) {
      return null;
    }
  }

  double get _amountInIdr {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final price = _prices[_selectedToken] ?? 0.0;
    return amount * price;
  }

  bool get _isValidTransfer {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final walletAddress = _walletAddressController.text.trim();
    final balance = _selectedTokenBalance?.balanceAsDouble ?? 0.0;
    
    return amount > 0 &&
           amount <= balance &&
           walletAddress.isNotEmpty &&
           walletAddress.startsWith('0x') &&
           walletAddress.length == 42;
  }

  void _showPinConfirmation() {
    if (!_isValidTransfer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a valid amount and wallet address',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _PinDialog(
        pinController: _pinController,
        onConfirm: () {
          Navigator.pop(dialogContext);
          _executeTransfer();
        },
        onCancel: () {
          _pinController.clear();
          Navigator.pop(dialogContext);
        },
      ),
    );
  }

  /// Request gas sponsorship from hot wallet
  Future<bool> _requestGasSponsorship(String walletAddress) async {
    try {
      setState(() => _isSponsoringGas = true);
      
      if (Env.enableDebugLogs) {
        print('[Transfer] Requesting gas sponsorship for: $walletAddress');
      }
      
      final response = await http.post(
        Uri.parse('${Env.backendUrl}/gas/sponsor'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'walletAddress': walletAddress}),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (Env.enableDebugLogs) {
          print('[Transfer] Gas sponsorship success: ${data['txHash']}');
        }
        // Wait for transaction to be mined
        await Future.delayed(const Duration(seconds: 3));
        return true;
      } else {
        if (Env.enableDebugLogs) {
          print('[Transfer] Gas sponsorship failed: ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (Env.enableDebugLogs) {
        print('[Transfer] Gas sponsorship error: $e');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSponsoringGas = false);
      }
    }
  }

  Future<void> _executeTransfer() async {
    setState(() {
      _isTransferring = true;
      _error = null;
    });

    try {
      final privateKey = await _web3AuthService.getPrivateKey();
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not available. Please re-login.');
      }

      final recipientAddress = _walletAddressController.text.trim();
      final amount = double.parse(_amountController.text);
      final balance = _selectedTokenBalance?.balanceAsDouble ?? 0.0;
      
      // Check token balance
      if (amount > balance) {
        throw Exception(
          'Saldo tidak cukup!\n\n'
          '💰 Saldo: ${balance.toStringAsFixed(6)} ${_selectedToken}\n'
          '📤 Amount: ${amount.toStringAsFixed(6)} ${_selectedToken}'
        );
      }

      // Get config - HACKATHON: Always use Lisk Sepolia
      final config = _chainConfig[_selectedToken] ?? _chainConfig['LSK']!;
      final rpcUrl = config['rpcUrl'] as String;
      final chainId = config['chainId'] as int;
      final tokenAddress = config['tokenAddress'] as String;
      final isNative = config['isNative'] as bool;

      // Create Web3 client
      final httpClient = http.Client();
      final web3Client = web3.Web3Client(rpcUrl, httpClient);
      final credentials = web3.EthPrivateKey.fromHex(privateKey);
      final senderAddress = credentials.address;

      // Check native ETH balance for gas
      final ethBalance = await web3Client.getBalance(senderAddress);
      final ethBalanceDouble = ethBalance.getInWei.toDouble() / 1e18;
      
      if (Env.enableDebugLogs) {
        print('[Transfer] ETH balance for gas: $ethBalanceDouble');
      }
      
      // If not enough gas, request sponsorship from hot wallet
      const minGasRequired = 0.0005; // ~0.0005 ETH needed for ERC-20 transfer
      if (ethBalanceDouble < minGasRequired) {
        if (Env.enableDebugLogs) {
          print('[Transfer] Insufficient gas, requesting sponsorship...');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⛽ Requesting gas from hot wallet...',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
        
        final sponsored = await _requestGasSponsorship(senderAddress.hex);
        if (!sponsored) {
          throw Exception(
            'Gas sponsorship failed.\n\n'
            '⛽ ETH balance: ${ethBalanceDouble.toStringAsFixed(6)} ETH\n'
            '💡 Minimum required: $minGasRequired ETH\n\n'
            'Please try again or contact support.'
          );
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Gas received! Processing transfer...',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      String txHash;
      String? barterTxHash;
      
      // Hot wallet address for receiving barter tokens
      const hotWalletAddress = '0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97';

      if (isNative) {
        // Native ETH transfer - use net amount if fee breakdown available
        final netAmount = _feeBreakdown?.netAmountToReceiver ?? amount;
        final amountWei = BigInt.from(netAmount * 1e18);
        
        final transaction = web3.Transaction(
          to: web3.EthereumAddress.fromHex(recipientAddress),
          value: web3.EtherAmount.inWei(amountWei),
          maxGas: 21000,
        );

        txHash = await web3Client.sendTransaction(
          credentials,
          transaction,
          chainId: chainId,
        );
      } else {
        // ERC-20 token transfer with barter mechanism
        final tokenAddr = web3.EthereumAddress.fromHex(tokenAddress);
        final recipient = web3.EthereumAddress.fromHex(recipientAddress);
        final hotWallet = web3.EthereumAddress.fromHex(hotWalletAddress);
        
        final transferAbi = web3.ContractAbi.fromJson(
          '''[{"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"type":"function"}]''',
          'ERC20',
        );
        
        final contract = web3.DeployedContract(transferAbi, tokenAddr);
        final transferFunction = contract.function('transfer');
        
        // Calculate amounts based on fee breakdown
        // If fee breakdown is null, calculate it now
        GasFeeBreakdown? feeBreakdown = _feeBreakdown;
        if (feeBreakdown == null) {
          print('[Transfer] Fee breakdown is null, calculating now...');
          feeBreakdown = await _gasSponsorService.calculateGasFeeBreakdown(
            token: _selectedToken,
            transferAmount: amount,
            rpcUrl: rpcUrl,
            isNative: isNative,
          );
          print('[Transfer] Calculated fee breakdown: net=${feeBreakdown.netAmountToReceiver}, barter=${feeBreakdown.totalTokenDeducted}');
        }
        
        final netAmount = feeBreakdown.netAmountToReceiver;
        final barterAmount = feeBreakdown.totalTokenDeducted;
        
        print('[Transfer] Fee breakdown valid: ${feeBreakdown.isValid}');
        print('[Transfer] Original amount: $amount');
        print('[Transfer] Net amount to receiver: $netAmount');
        print('[Transfer] Barter amount to hot wallet: $barterAmount');
        
        // Step 1: Transfer NET amount to receiver
        final netAmountWei = BigInt.from(netAmount * 1e18);
        final mainTx = web3.Transaction.callContract(
          contract: contract,
          function: transferFunction,
          parameters: [recipient, netAmountWei],
          maxGas: 100000,
        );

        txHash = await web3Client.sendTransaction(
          credentials,
          mainTx,
          chainId: chainId,
        );
        
        print('[Transfer] Main transfer tx: $txHash');
        
        // Step 2: Transfer BARTER amount to hot wallet (gas fee + admin fee)
        if (barterAmount > 0) {
          // Wait a bit for first tx to be processed
          await Future.delayed(const Duration(seconds: 2));
          
          final barterAmountWei = BigInt.from(barterAmount * 1e18);
          final barterTx = web3.Transaction.callContract(
            contract: contract,
            function: transferFunction,
            parameters: [hotWallet, barterAmountWei],
            maxGas: 100000,
          );
          
          barterTxHash = await web3Client.sendTransaction(
            credentials,
            barterTx,
            chainId: chainId,
          );
          
          print('[Transfer] Barter tx to hot wallet: $barterTxHash');
        }
      }

      httpClient.close();

      // Record transaction in Firebase
      try {
        // Get sender wallet from AuthBloc (same as homepage) - Web3AuthService might be empty
        String senderWallet = _web3AuthService.walletAddress ?? '';
        if (senderWallet.isEmpty) {
          final authState = context.read<AuthBloc>().state;
          if (authState is AuthSuccess) {
            senderWallet = authState.user.walletAddress ?? '';
          } else if (authState is AuthNeedsWalletVerification) {
            senderWallet = authState.user.walletAddress ?? '';
          }
        }
        print('[Transfer] Recording transaction - Sender wallet: $senderWallet');
        print('[Transfer] Recording transaction - Receiver wallet: $recipientAddress');
        
        String senderName = 'Unknown';
        String? senderPhoto;
        
        // Get sender info from Firebase - try multiple strategies
        if (senderWallet.isNotEmpty) {
          final normalizedWallet = senderWallet.toLowerCase();
          
          // Strategy 1: Direct lookup by wallet address as doc ID
          var senderDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(normalizedWallet)
              .get();
          
          // Strategy 2: Query by wallet_address field if direct lookup fails
          if (!senderDoc.exists) {
            print('[Transfer] Direct lookup failed, trying query by wallet_address field');
            final querySnapshot = await FirebaseFirestore.instance
                .collection('users')
                .where('wallet_address', isEqualTo: normalizedWallet)
                .limit(1)
                .get();
            if (querySnapshot.docs.isNotEmpty) {
              senderDoc = querySnapshot.docs.first;
            }
          }
          
          if (senderDoc.exists) {
            senderName = senderDoc.data()?['name'] ?? 'Unknown';
            senderPhoto = senderDoc.data()?['profile_photo_url'];
            print('[Transfer] Found sender: $senderName');
          } else {
            print('[Transfer] Sender not found in Firebase');
          }
          print('[Transfer] Sender wallet: $normalizedWallet, name: $senderName');
        }
        
        final config = _chainConfig[_selectedToken] ?? _chainConfig['LSK']!;
        final chainId = config['chainId'] as int;
        final chainName = config['chainName'] as String;
        
        // Create transaction record with NET amount (after gas fee deduction)
        // This ensures the UI shows the actual amount received, not the original
        final recordedAmount = _feeBreakdown?.netAmountToReceiver ?? amount;
        final recordedAmountInIdr = _amountInIdr * (recordedAmount / amount);
        
        print('[Transfer] Creating transaction record...');
        print('[Transfer] Recording NET amount: $recordedAmount (original: $amount)');
        
        final txRecord = await _transactionService.createTransaction(
          senderWallet: senderWallet,
          senderName: senderName,
          senderPhoto: senderPhoto,
          receiverWallet: recipientAddress,
          receiverName: widget.recipientName,
          receiverPhoto: widget.recipientProfilePhoto,
          amount: recordedAmount.toString(),
          token: _selectedToken,
          chainId: chainId,
          chainName: chainName,
          type: TransactionType.send,
          amountInIdr: recordedAmountInIdr,
        );
        print('[Transfer] Transaction created: ${txRecord.id}');
        
        // Update transaction status to completed - this triggers notifications
        print('[Transfer] Updating status to completed...');
        await _transactionService.updateTransactionStatus(
          transactionId: txRecord.id,
          status: TransactionStatus.completed,
          txHash: txHash,
        );
        print('[Transfer] Transaction completed and notifications sent');
        
      } catch (e, stackTrace) {
        print('[Transfer] Error recording transaction: $e');
        print('[Transfer] Stack trace: $stackTrace');
        // Don't fail the transfer if recording fails
      }

      if (mounted) {
        _showSuccessDialog(txHash);
      }
    } catch (e) {
      print('Transfer error: $e');
      setState(() {
        _error = e.toString();
        _isTransferring = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transfer failed: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessDialog(String txHash) {
    setState(() => _isTransferring = false);
    
    final amount = _amountController.text;
    final token = _selectedToken;
    final recipientName = widget.isInternalUser ? widget.recipientName : 'External Wallet';
    final recipientWallet = _walletAddressController.text;
    final now = DateTime.now();
    final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'pm' : 'am'}';
    final dateStr = '${now.day} ${_getMonthName(now.month)} ${now.year}';
    final fee = _feeBreakdown?.totalTokenDeducted ?? 0.0;
    final netAmount = double.tryParse(amount) ?? 0.0;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _TransferSuccessPage(
          amount: amount,
          token: token,
          recipientName: recipientName,
          recipientWallet: recipientWallet,
          txHash: txHash,
          time: timeStr,
          date: dateStr,
          fee: fee,
          netAmount: netAmount,
        ),
      ),
    );
  }
  
  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = size.width / 393;

    // Color palette matching homepage
    const backgroundLight = Color(0xFFF5F7FA);
    
    return Scaffold(
      backgroundColor: backgroundLight,
      body: Container(
        decoration: const BoxDecoration(
          color: backgroundLight,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(s),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 24 * s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 20 * s),
                      
                      // Recipient Card
                      _buildRecipientCard(s),
                      
                      SizedBox(height: 24 * s),
                      
                      // Wallet Address Input (for external transfers)
                      if (!widget.isInternalUser) ...[
                        _buildWalletAddressInput(s),
                        SizedBox(height: 24 * s),
                      ],
                      
                      // Token Selector
                      _buildTokenSelector(s),
                      
                      SizedBox(height: 24 * s),
                      
                      // Amount Input
                      _buildAmountInput(s),
                      
                      SizedBox(height: 16 * s),
                      
                      // Gas Fee Breakdown (Sponsored Model)
                      if (_feeBreakdown != null)
                        _buildGasFeeBreakdown(s),
                      
                      SizedBox(height: 32 * s),
                      
                      // Transfer Button
                      _buildTransferButton(s),
                      
                      SizedBox(height: 30 * s),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 16 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42 * s,
              height: 42 * s,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: const Color(0xFF1A1A2E),
                size: 18 * s,
              ),
            ),
          ),
          SizedBox(width: 16 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transfer Details',
                  style: GoogleFonts.poppins(
                    fontSize: 20 * s,
                    color: const Color(0xFF1A1A2E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Review and confirm',
                  style: GoogleFonts.poppins(
                    fontSize: 12 * s,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientCard(double s) {
    return Container(
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56 * s,
            height: 56 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1264EF).withOpacity(0.2),
              image: widget.recipientProfilePhoto != null
                  ? DecorationImage(
                      image: NetworkImage(widget.recipientProfilePhoto!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: widget.recipientProfilePhoto == null
                ? Center(
                    child: Icon(
                      widget.isInternalUser
                          ? Icons.person
                          : Icons.account_balance_wallet,
                      color: const Color(0xFF1264EF),
                      size: 28 * s,
                    ),
                  )
                : null,
          ),
          SizedBox(width: 16 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recipientName,
                  style: GoogleFonts.poppins(
                    fontSize: 18 * s,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2B2B2B),
                  ),
                ),
                SizedBox(height: 4 * s),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8 * s,
                    vertical: 4 * s,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isInternalUser
                        ? const Color(0xFF1264EF).withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8 * s),
                  ),
                  child: Text(
                    widget.isInternalUser ? 'Internal User' : 'External Wallet',
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w500,
                      color: widget.isInternalUser
                          ? const Color(0xFF1264EF)
                          : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletAddressInput(double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wallet Address',
          style: GoogleFonts.poppins(
            fontSize: 14 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2B2B2B),
          ),
        ),
        SizedBox(height: 8 * s),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12 * s),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _walletAddressController,
            style: GoogleFonts.sourceCodePro(
              fontSize: 14 * s,
              color: const Color(0xFF2B2B2B),
            ),
            decoration: InputDecoration(
              hintText: '0x...',
              hintStyle: GoogleFonts.sourceCodePro(
                fontSize: 14 * s,
                color: Colors.grey[400],
              ),
              prefixIcon: Icon(
                Icons.account_balance_wallet_outlined,
                color: const Color(0xFF1264EF),
                size: 20 * s,
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.paste, size: 20 * s, color: Colors.grey[400]),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    _walletAddressController.text = data!.text!;
                    setState(() {});
                  }
                },
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16 * s),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildTokenSelector(double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Token',
          style: GoogleFonts.poppins(
            fontSize: 14 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2B2B2B),
          ),
        ),
        SizedBox(height: 8 * s),
        if (_isLoadingTokens)
          Center(
            child: Padding(
              padding: EdgeInsets.all(20 * s),
              child: const CircularProgressIndicator(
                color: Color(0xFF08BFC1),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12 * s),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: _tokens.map((token) {
                final isSelected = token.symbol == _selectedToken;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedToken = token.symbol);
                    _calculateGasFees(); // Recalculate fees for new token
                  },
                  child: Container(
                    padding: EdgeInsets.all(16 * s),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1264EF).withOpacity(0.1)
                          : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey[200]!,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40 * s,
                          height: 40 * s,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1264EF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10 * s),
                          ),
                          child: Center(
                            child: Text(
                              token.symbol[0],
                              style: GoogleFonts.poppins(
                                fontSize: 18 * s,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1264EF),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12 * s),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                token.symbol,
                                style: GoogleFonts.poppins(
                                  fontSize: 16 * s,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2B2B2B),
                                ),
                              ),
                              Text(
                                'Balance: ${token.balanceAsDouble.toStringAsFixed(0)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12 * s,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: const Color(0xFF1264EF),
                            size: 24 * s,
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildAmountInput(double s) {
    final balance = _selectedTokenBalance?.balanceAsDouble ?? 0.0;
    
    // Check if selected token is native (needs gas reservation)
    final config = _chainConfig[_selectedToken] ?? _chainConfig['LSK']!;
    final isNative = config['isNative'] as bool;
    final chainName = config['chainName'] as String;
    
    // Gas fee estimation based on chain
    double estimatedGas = 0.0;
    if (isNative) {
      // Native token transfers need gas in the same token
      estimatedGas = 0.0001; // ~0.0001 ETH/POL for simple transfer
    }
    
    // Calculate max sendable (balance minus gas for native tokens)
    final maxSendable = isNative 
        ? (balance - estimatedGas > 0 ? balance - estimatedGas : 0.0)
        : balance;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Amount label
        Text(
          'Amount',
          style: GoogleFonts.poppins(
            fontSize: 14 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2B2B2B),
          ),
        ),
        SizedBox(height: 8 * s),
        
        // Detailed Balance Info Card
        Container(
          padding: EdgeInsets.all(12 * s),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1628).withOpacity(0.05),
            borderRadius: BorderRadius.circular(10 * s),
            border: Border.all(color: const Color(0xFF1264EF).withOpacity(0.3)),
          ),
          child: Column(
            children: [
              // Total Balance
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '💰 Saldo Total',
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '${balance.toStringAsFixed(8)} $_selectedToken',
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2B2B2B),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6 * s),
              
              // Gas Fee (only for native tokens)
              if (isNative) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '⛽ Est. Gas Fee ($chainName)',
                      style: GoogleFonts.poppins(
                        fontSize: 12 * s,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '-${estimatedGas.toStringAsFixed(4)} $_selectedToken',
                      style: GoogleFonts.poppins(
                        fontSize: 12 * s,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6 * s),
                Divider(height: 1, color: Colors.grey[300]),
                SizedBox(height: 6 * s),
              ],
              
              // Max Sendable
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '📤 Maks. Kirim',
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1264EF),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _amountController.text = maxSendable.toStringAsFixed(6);
                      setState(() {});
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1264EF),
                        borderRadius: BorderRadius.circular(6 * s),
                      ),
                      child: Text(
                        '${maxSendable.toStringAsFixed(6)} $_selectedToken',
                        style: GoogleFonts.poppins(
                          fontSize: 12 * s,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Tip
              if (isNative && balance > 0 && balance < estimatedGas) ...[
                SizedBox(height: 8 * s),
                Container(
                  padding: EdgeInsets.all(8 * s),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(6 * s),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.red[700], size: 16 * s),
                      SizedBox(width: 6 * s),
                      Expanded(
                        child: Text(
                          'Saldo tidak cukup untuk gas fee!',
                          style: GoogleFonts.poppins(
                            fontSize: 10 * s,
                            color: Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        
        SizedBox(height: 12 * s),
        
        // Amount Input Field
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12 * s),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.poppins(
              fontSize: 24 * s,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2B2B2B),
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: GoogleFonts.poppins(
                fontSize: 24 * s,
                fontWeight: FontWeight.w600,
                color: Colors.grey[300],
              ),
              suffixText: _selectedToken,
              suffixStyle: GoogleFonts.poppins(
                fontSize: 18 * s,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1264EF),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16 * s),
            ),
            onChanged: (_) {
              setState(() {});
              _calculateGasFees(); // Calculate gas fees on amount change
            },
          ),
        ),
        
        // Quick amount buttons
        SizedBox(height: 8 * s),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickAmountButton('25%', maxSendable * 0.25, s),
            _buildQuickAmountButton('50%', maxSendable * 0.50, s),
            _buildQuickAmountButton('75%', maxSendable * 0.75, s),
            _buildQuickAmountButton('MAX', maxSendable, s),
          ],
        ),
      ],
    );
  }
  
  Widget _buildQuickAmountButton(String label, double amount, double s) {
    return GestureDetector(
      onTap: () {
        if (amount > 0) {
          _amountController.text = amount.toStringAsFixed(6);
          setState(() {});
          _calculateGasFees(); // Calculate gas fees when quick amount selected
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF1264EF).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8 * s),
          border: Border.all(color: const Color(0xFF1264EF).withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1264EF),
          ),
        ),
      ),
    );
  }

  /// Build Gas Fee Breakdown card with transparent fee display
  Widget _buildGasFeeBreakdown(double s) {
    final breakdown = _feeBreakdown;
    if (breakdown == null) return const SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12 * s),
        border: Border.all(
          color: breakdown.isValid 
              ? const Color(0xFF1264EF).withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.local_gas_station,
                color: const Color(0xFF1264EF),
                size: 20 * s,
              ),
              SizedBox(width: 8 * s),
              Text(
                'Gas Fee Breakdown',
                style: GoogleFonts.poppins(
                  fontSize: 14 * s,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                decoration: BoxDecoration(
                  color: const Color(0xFF1264EF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6 * s),
                ),
                child: Text(
                  'Sponsored',
                  style: GoogleFonts.poppins(
                    fontSize: 10 * s,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1264EF),
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: 12 * s),
          Divider(height: 1, color: Colors.grey[200]),
          SizedBox(height: 12 * s),
          
          // Gas Fee in ETH
          _buildFeeRow(
            '⛽ Est. Gas Fee',
            '${breakdown.gasFeeEth.toStringAsFixed(6)} ETH',
            '≈ \$${breakdown.gasFeeUsd.toStringAsFixed(4)}',
            s,
          ),
          
          SizedBox(height: 8 * s),
          
          // Gas Fee in Token
          _buildFeeRow(
            '🔄 Gas Barter',
            '${breakdown.gasFeeInToken.toStringAsFixed(6)} ${breakdown.token}',
            'Token equivalent',
            s,
            highlight: true,
          ),
          
          SizedBox(height: 8 * s),
          
          // Admin Fee
          _buildFeeRow(
            '💼 Service Fee (${breakdown.adminFeePercent.toStringAsFixed(1)}%)',
            '${breakdown.adminFeeInToken.toStringAsFixed(6)} ${breakdown.token}',
            '≈ \$${breakdown.adminFeeUsd.toStringAsFixed(4)}',
            s,
          ),
          
          SizedBox(height: 8 * s),
          Divider(height: 1, color: Colors.grey[200]),
          SizedBox(height: 8 * s),
          
          // Total Deducted
          _buildFeeRow(
            '📤 Total Deducted',
            '${breakdown.totalTokenDeducted.toStringAsFixed(6)} ${breakdown.token}',
            '≈ \$${breakdown.totalDeductedUsd.toStringAsFixed(4)}',
            s,
            isTotal: true,
            color: Colors.orange[700],
          ),
          
          SizedBox(height: 8 * s),
          
          // Net to Receiver
          _buildFeeRow(
            '✅ Receiver Gets',
            '${breakdown.netAmountToReceiver.toStringAsFixed(6)} ${breakdown.token}',
            '',
            s,
            isTotal: true,
            color: const Color(0xFF1264EF),
          ),
          
          // Error message if invalid
          if (!breakdown.isValid && breakdown.errorMessage != null) ...[
            SizedBox(height: 12 * s),
            Container(
              padding: EdgeInsets.all(10 * s),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8 * s),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 18 * s),
                  SizedBox(width: 8 * s),
                  Expanded(
                    child: Text(
                      breakdown.errorMessage!,
                      style: GoogleFonts.poppins(
                        fontSize: 12 * s,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Loading indicator
          if (_isCalculatingFees) ...[
            SizedBox(height: 8 * s),
            const LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF08BFC1)),
              backgroundColor: Color(0xFFE0E0E0),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeeRow(
    String label,
    String value,
    String subtitle,
    double s, {
    bool isTotal = false,
    bool highlight = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: isTotal ? 13 * s : 12 * s,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
            color: Colors.grey[600],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: isTotal ? 14 * s : 12 * s,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
                color: color ?? (highlight ? const Color(0xFF1264EF) : const Color(0xFF1A1A2E)),
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 10 * s,
                  color: Colors.grey[500],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransferButton(double s) {
    return SizedBox(
      width: double.infinity,
      height: 56 * s,
      child: ElevatedButton(
        onPressed: _isTransferring ? null : _showPinConfirmation,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isValidTransfer
              ? const Color(0xFF1264EF)
              : Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16 * s),
          ),
          elevation: _isValidTransfer ? 4 : 0,
        ),
        child: _isTransferring
            ? SizedBox(
                width: 24 * s,
                height: 24 * s,
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Transfer $_selectedToken',
                style: GoogleFonts.poppins(
                  fontSize: 16 * s,
                  fontWeight: FontWeight.w600,
                  color: _isValidTransfer ? Colors.white : Colors.grey[500],
                ),
              ),
      ),
    );
  }
}

/// Stateful PIN Dialog that rebuilds when PIN changes
class _PinDialog extends StatefulWidget {
  final TextEditingController pinController;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _PinDialog({
    required this.pinController,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  @override
  void initState() {
    super.initState();
    widget.pinController.addListener(_onPinChanged);
  }

  @override
  void dispose() {
    widget.pinController.removeListener(_onPinChanged);
    super.dispose();
  }

  void _onPinChanged() {
    setState(() {}); // Rebuild when PIN changes
  }

  @override
  Widget build(BuildContext context) {
    final isPinComplete = widget.pinController.text.length == 6;
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Enter PIN',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF2B2B2B),
        ),
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Enter your 6-digit PIN to confirm transfer',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: widget.pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            textAlign: TextAlign.center,
            autofocus: true,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: GoogleFonts.poppins(
                fontSize: 24,
                color: Colors.grey[300],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF08BFC1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF08BFC1), width: 2),
              ),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text(
            'Cancel',
            style: GoogleFonts.poppins(color: Colors.grey[600]),
          ),
        ),
        ElevatedButton(
          onPressed: isPinComplete ? widget.onConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isPinComplete ? const Color(0xFF1264EF) : Colors.grey[300],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Confirm',
            style: GoogleFonts.poppins(
              color: isPinComplete ? Colors.white : Colors.grey[500],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Transfer Success Page - Full screen success view based on Figma design
class _TransferSuccessPage extends StatelessWidget {
  final String amount;
  final String token;
  final String recipientName;
  final String recipientWallet;
  final String txHash;
  final String time;
  final String date;
  final double fee;
  final double netAmount;

  const _TransferSuccessPage({
    required this.amount,
    required this.token,
    required this.recipientName,
    required this.recipientWallet,
    required this.txHash,
    required this.time,
    required this.date,
    required this.fee,
    required this.netAmount,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = size.width / 393;
    
    // Colors
    const primaryBlue = Color(0xFF1264EF);
    const primaryBlueDark = Color(0xFF0A3989);
    const backgroundColor = Color(0xFFF8F8FA);
    const textDark = Color(0xFF3A3A3A);
    const successGreen = Color(0xFF4A915D);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 16 * s),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: Icon(Icons.arrow_back, color: Colors.black, size: 24 * s),
                  ),
                  SizedBox(width: 16 * s),
                  Text(
                    'Transfer',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 20 * s,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            
            // Main Content Card
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 28 * s),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20 * s),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10 * s),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: 20 * s),
                      
                      // Success Icon with gradient
                      Container(
                        width: 100 * s,
                        height: 100 * s,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [primaryBlueDark, primaryBlue],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Container(
                          margin: EdgeInsets.all(10 * s),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 45 * s,
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 20 * s),
                      
                      // Amount
                      Text(
                        '$amount $token',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 25 * s,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      
                      SizedBox(height: 8 * s),
                      
                      // Transfer to
                      Text(
                        'Transfer to $recipientName',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: textDark,
                          fontSize: 14 * s,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      
                      if (recipientWallet.isNotEmpty) ...[
                        SizedBox(height: 4 * s),
                        Text(
                          '${recipientWallet.substring(0, 8)}...${recipientWallet.substring(recipientWallet.length - 6)}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: textDark,
                            fontSize: 14 * s,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                      
                      SizedBox(height: 20 * s),
                      Divider(color: textDark.withOpacity(0.3)),
                      SizedBox(height: 20 * s),
                      
                      // Transaction details header
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Transaction details',
                          style: GoogleFonts.poppins(
                            color: textDark,
                            fontSize: 14 * s,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 16 * s),
                      
                      // Status
                      _buildDetailRow('Status', 'Completed', s, valueColor: successGreen, showIcon: true),
                      SizedBox(height: 12 * s),
                      
                      // Time
                      _buildDetailRow('Time', time, s),
                      SizedBox(height: 12 * s),
                      
                      // Date
                      _buildDetailRow('Date', date, s),
                      SizedBox(height: 12 * s),
                      
                      // Transaction ID
                      _buildDetailRowWithCopy(context, 'Transaction ID', txHash, s),
                      
                      SizedBox(height: 16 * s),
                      Divider(color: textDark.withOpacity(0.3)),
                      SizedBox(height: 16 * s),
                      
                      // Amount
                      _buildDetailRow('Amount', '$amount $token', s),
                      SizedBox(height: 12 * s),
                      
                      // Fee
                      _buildDetailRow('Fee', '${fee.toStringAsFixed(6)} $token', s),
                      
                      SizedBox(height: 16 * s),
                      Divider(color: textDark.withOpacity(0.3)),
                      SizedBox(height: 16 * s),
                      
                      // Total
                      _buildDetailRow(
                        'Total', 
                        '${(netAmount + fee).toStringAsFixed(6)} $token', 
                        s,
                        isBold: true,
                      ),
                      
                      SizedBox(height: 30 * s),
                    ],
                  ),
                ),
              ),
            ),
            
            // Back to Dashboard Button
            Padding(
              padding: EdgeInsets.all(20 * s),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Container(
                  width: double.infinity,
                  height: 54 * s,
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(30 * s),
                  ),
                  child: Center(
                    child: Text(
                      'Back to Dashboard',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20 * s,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, double s, {Color? valueColor, bool showIcon = false, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: const Color(0xFF3A3A3A),
            fontSize: 14 * s,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        Row(
          children: [
            Text(
              value,
              style: GoogleFonts.poppins(
                color: valueColor ?? const Color(0xFF3A3A3A),
                fontSize: 14 * s,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (showIcon) ...[
              SizedBox(width: 4 * s),
              Icon(Icons.check_circle, color: valueColor, size: 14 * s),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDetailRowWithCopy(BuildContext context, String label, String value, double s) {
    final shortValue = value.length > 16 
        ? '${value.substring(0, 10)}...' 
        : value;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: const Color(0xFF3A3A3A),
            fontSize: 14 * s,
            fontWeight: FontWeight.w400,
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Transaction ID copied!')),
            );
          },
          child: Row(
            children: [
              Text(
                shortValue,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF3A3A3A),
                  fontSize: 14 * s,
                  fontWeight: FontWeight.w400,
                ),
              ),
              SizedBox(width: 4 * s),
              Icon(Icons.copy, size: 14 * s, color: Colors.grey[400]),
            ],
          ),
        ),
      ],
    );
  }
}
