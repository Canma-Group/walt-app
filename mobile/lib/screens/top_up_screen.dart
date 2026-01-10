import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme/app_colors.dart';
import '../blocs/auth/auth_bloc.dart';
import '../config/env.dart';
import '../services/transaction_service.dart';
import '../services/auth_service.dart';
import '../models/transaction_model.dart';

/// Top Up Screen - Mockup Coin Top Up for Hackathon Demo (LSK, ETH, POL)
class TopUpScreen extends StatefulWidget {
  const TopUpScreen({super.key});

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  final _amountController = TextEditingController();
  final _pinController = TextEditingController();
  final TransactionService _transactionService = TransactionService();
  final AuthService _authService = AuthService();
  bool _isProcessing = false;
  String _selectedCoin = 'LSK';
  Timer? _priceTimer;
  
  // Dynamic rates from API
  Map<String, double> _liveRates = {
    'LSK': 3385.0,
    'ETH': 54000000.0,
    'POL': 2150.0,
  };
  
  // Coin configurations
  static const Map<String, Map<String, dynamic>> _coinConfigs = {
    'LSK': {
      'name': 'Lisk',
      'color': Color(0xFF0D47A1),
      'network': 'Lisk Sepolia Testnet',
    },
    'ETH': {
      'name': 'Ethereum',
      'color': Color(0xFF627EEA),
      'network': 'Lisk Sepolia Testnet',
    },
    'POL': {
      'name': 'Polygon',
      'color': Color(0xFF8247E5),
      'network': 'Polygon Amoy Testnet',
    },
  };
  
  double get _currentRate => _liveRates[_selectedCoin] ?? 1.0;
  
  @override
  void initState() {
    super.initState();
    _fetchLivePrices();
    // Update prices every 2 seconds
    _priceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchLivePrices();
    });
  }
  
  Future<void> _fetchLivePrices() async {
    try {
      final response = await http.get(
        Uri.parse('${Env.backendUrl}/prices/idr'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final prices = data['data'] as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              if (prices['LSK'] != null) _liveRates['LSK'] = (prices['LSK'] as num).toDouble();
              if (prices['ETH'] != null) _liveRates['ETH'] = (prices['ETH'] as num).toDouble();
              if (prices['POL'] != null) _liveRates['POL'] = (prices['POL'] as num).toDouble();
            });
          }
        }
      }
    } catch (e) {
      print('[TopUp] Error fetching prices: $e');
    }
  }

  final _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  String get _estimatedAmount {
    final idrAmount = double.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    ) ?? 0;
    
    if (idrAmount == 0) return '0.00';
    
    final coinAmount = idrAmount / _currentRate;
    return coinAmount.toStringAsFixed(6);
  }

  /// Record top-up transaction and send notification
  Future<void> _recordTopUpTransaction({
    required String walletAddress,
    required double coinAmount,
    required double idrAmount,
    required String txHash,
  }) async {
    try {
      print('[TopUp] Recording transaction for wallet: $walletAddress');
      
      // Get user name from Firebase
      String userName = 'Unknown';
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(walletAddress.toLowerCase())
          .get();
      if (userDoc.exists) {
        userName = userDoc.data()?['name'] ?? 'Unknown';
      }
      
      // Create transaction record
      final txRecord = await _transactionService.createTransaction(
        senderWallet: 'faucet', // Top-up comes from faucet
        senderName: 'Canma Faucet',
        senderPhoto: null,
        receiverWallet: walletAddress,
        receiverName: userName,
        receiverPhoto: null,
        amount: coinAmount.toString(),
        token: _selectedCoin,
        chainId: _selectedCoin == 'POL' ? 80002 : 4202,
        chainName: _coinConfigs[_selectedCoin]!['network'] as String,
        type: TransactionType.topUp,
        amountInIdr: idrAmount,
      );
      
      // Update to completed status
      await _transactionService.updateTransactionStatus(
        transactionId: txRecord.id,
        status: TransactionStatus.completed,
        txHash: txHash,
      );
      
      print('[TopUp] Transaction recorded: ${txRecord.id}');
    } catch (e) {
      print('[TopUp] Error recording transaction: $e');
      // Don't fail the top-up if recording fails
    }
  }

  void _showPinDialog() {
    final amountStr = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final idrAmount = double.tryParse(amountStr) ?? 0;
    
    if (idrAmount < 10000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimum top up Rp 10.000'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    _pinController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _PinDialog(
        pinController: _pinController,
        onConfirm: () async {
          Navigator.pop(dialogContext);
          await _verifyPinAndProcess();
        },
        onCancel: () {
          Navigator.pop(dialogContext);
          _pinController.clear();
        },
      ),
    );
  }

  Future<void> _verifyPinAndProcess() async {
    final pin = _pinController.text;
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN harus 6 digit'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Get user wallet address
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
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Verify PIN
    final isPinValid = await _authService.verifyPin(walletAddress, pin);
    if (!isPinValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN salah'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // PIN valid, proceed with top up
    await _processTopUp(walletAddress);
  }

  Future<void> _processTopUp(String walletAddress) async {
    final amountStr = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final idrAmount = double.tryParse(amountStr) ?? 0;

    setState(() => _isProcessing = true);

    try {
      // Call backend faucet to mint mock tokens (real-time Indodax price)
      final response = await http.post(
        Uri.parse('${Env.backendUrl}/faucet/mint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'walletAddress': walletAddress,
          'coin': _selectedCoin,
          'amountIdr': idrAmount,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final result = data['data'];
          final coinAmount = double.tryParse(result['amount'].toString()) ?? 0;
          final txHash = result['txHash'] ?? '';
          
          // Record top-up transaction and notification
          await _recordTopUpTransaction(
            walletAddress: walletAddress,
            coinAmount: coinAmount,
            idrAmount: idrAmount,
            txHash: txHash,
          );
          
          if (mounted) {
            _showSuccessDialog(coinAmount, idrAmount, txHash);
          }
        } else {
          throw Exception(data['error'] ?? 'Unknown error');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Top up failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSuccessDialog(double coinAmount, double idrAmount, String txHash) {
    final now = DateTime.now();
    final timeFormat = DateFormat('h:mm a').format(now);
    final dateFormat = DateFormat('dd MMM yyyy').format(now);
    final txIdDisplay = txHash.isNotEmpty 
        ? '${txHash.substring(0, 10)}...' 
        : '-';
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TopUpSuccessPage(
          coinAmount: coinAmount,
          idrAmount: idrAmount,
          coinSymbol: _selectedCoin,
          txHash: txHash,
          txIdDisplay: txIdDisplay,
          time: timeFormat,
          date: dateFormat,
          onBackToDashboard: () {
            Navigator.pop(context); // Pop success page
            Navigator.pop(context, true); // Pop top up screen with success
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _amountController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Top Up Mockup Coin',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coin Selector
              Text(
                'Pilih Koin',
                style: GoogleFonts.poppins(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: _coinConfigs.keys.map((coin) {
                  final isSelected = _selectedCoin == coin;
                  final config = _coinConfigs[coin]!;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedCoin = coin),
                      child: Container(
                        margin: EdgeInsets.only(right: coin != 'POL' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? (config['color'] as Color).withOpacity(0.15) : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? config['color'] as Color : AppColors.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              coin,
                              style: GoogleFonts.poppins(
                                color: isSelected ? config['color'] as Color : AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              config['name'] as String,
                              style: GoogleFonts.poppins(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 20),
              
              // Info Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_coinConfigs[_selectedCoin]!['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (_coinConfigs[_selectedCoin]!['color'] as Color).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: _coinConfigs[_selectedCoin]!['color'] as Color, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Top up mockup $_selectedCoin untuk demo.\nKoin akan dikirim ke ${_coinConfigs[_selectedCoin]!['network']}.',
                        style: GoogleFonts.poppins(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Amount Input
              Text(
                'Jumlah (IDR)',
                style: GoogleFonts.poppins(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: GoogleFonts.poppins(
                    color: AppColors.textHint,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixText: 'Rp ',
                  prefixStyle: GoogleFonts.poppins(
                    color: AppColors.textSecondary,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1264EF), width: 2),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              
              const SizedBox(height: 16),
              
              // Quick Amount Buttons
              Row(
                children: [
                  _QuickAmountButton(
                    amount: '50.000',
                    onTap: () {
                      _amountController.text = '50000';
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 8),
                  _QuickAmountButton(
                    amount: '100.000',
                    onTap: () {
                      _amountController.text = '100000';
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 8),
                  _QuickAmountButton(
                    amount: '500.000',
                    onTap: () {
                      _amountController.text = '500000';
                      setState(() {});
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Estimation Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Anda akan menerima',
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _estimatedAmount,
                          style: GoogleFonts.poppins(
                            color: AppColors.textPrimary,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _selectedCoin,
                            style: GoogleFonts.poppins(
                              color: _coinConfigs[_selectedCoin]!['color'] as Color,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Rate: 1 $_selectedCoin = ${_currencyFormat.format(_currentRate)}',
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Network: ${_coinConfigs[_selectedCoin]!['network']}',
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _showPinDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1264EF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Top Up Sekarang',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAmountButton extends StatelessWidget {
  final String amount;
  final VoidCallback onTap;

  const _QuickAmountButton({
    required this.amount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1264EF).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1264EF).withOpacity(0.3)),
          ),
          child: Center(
            child: Text(
              'Rp $amount',
              style: GoogleFonts.poppins(
                color: const Color(0xFF0A3989),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PIN Dialog Widget
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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isPinComplete = widget.pinController.text.length == 6;
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Masukkan PIN',
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
            'Masukkan PIN 6 digit untuk konfirmasi top up',
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
                borderSide: const BorderSide(color: Color(0xFF1264EF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1264EF), width: 2),
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
            'Batal',
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
            'Konfirmasi',
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

/// Success Page with Figma Design
class _TopUpSuccessPage extends StatelessWidget {
  final double coinAmount;
  final double idrAmount;
  final String coinSymbol;
  final String txHash;
  final String txIdDisplay;
  final String time;
  final String date;
  final VoidCallback onBackToDashboard;

  const _TopUpSuccessPage({
    required this.coinAmount,
    required this.idrAmount,
    required this.coinSymbol,
    required this.txHash,
    required this.txIdDisplay,
    required this.time,
    required this.date,
    required this.onBackToDashboard,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: onBackToDashboard,
        ),
        title: Text(
          'Top Up',
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Main Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Success Icon Circle
                    Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(0.37, 0.00),
                          end: Alignment(0.63, 1.00),
                          colors: [Color(0xFF0A3989), Color(0xFF1264EF), Color(0xFF0A3989)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 45,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Amount
                    Text(
                      '+${coinAmount.toStringAsFixed(4)} $coinSymbol',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Description
                    Text(
                      'Top Up $coinSymbol',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF3A3A3A),
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    Text(
                      currencyFormat.format(idrAmount),
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
                      color: const Color(0xFF3A3A3A).withOpacity(0.2),
                    ),
                    const SizedBox(height: 20),
                    // Transaction Details Title
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
                    // Status Row
                    _buildDetailRow('Status', 'Completed', isStatus: true),
                    const SizedBox(height: 12),
                    // Time Row
                    _buildDetailRow('Time', time),
                    const SizedBox(height: 12),
                    // Date Row
                    _buildDetailRow('Date', date),
                    const SizedBox(height: 12),
                    // Transaction ID Row
                    _buildDetailRow('Transaction ID', txIdDisplay, hasCopy: true, fullValue: txHash),
                    const SizedBox(height: 16),
                    // Divider
                    Container(
                      height: 1,
                      color: const Color(0xFF3A3A3A).withOpacity(0.2),
                    ),
                    const SizedBox(height: 16),
                    // Amount Row
                    _buildDetailRow('Amount', '+${coinAmount.toStringAsFixed(4)} $coinSymbol'),
                    const SizedBox(height: 12),
                    // Admin Fee Row
                    _buildDetailRow('Admin fee', '\$ 0'),
                    const SizedBox(height: 16),
                    // Divider
                    Container(
                      height: 1,
                      color: const Color(0xFF3A3A3A).withOpacity(0.2),
                    ),
                    const SizedBox(height: 16),
                    // Total Row
                    _buildDetailRow('Total', currencyFormat.format(idrAmount), isBold: true),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              // Back to Dashboard Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: onBackToDashboard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1264EF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
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
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isStatus = false, bool hasCopy = false, String? fullValue, bool isBold = false}) {
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
          mainAxisSize: MainAxisSize.min,
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
            if (hasCopy && fullValue != null && fullValue.isNotEmpty) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: fullValue));
                },
                child: const Icon(Icons.copy, color: Color(0xFF3A3A3A), size: 14),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
