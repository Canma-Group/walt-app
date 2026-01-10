import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web3dart/web3dart.dart' as web3;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../services/waltswap_service.dart';
import '../../services/web3auth_service.dart';
import '../../services/multi_chain_service.dart';
import '../../services/auth_service.dart';
import '../../services/price_service.dart';

class SwapScreen extends StatefulWidget {
  const SwapScreen({Key? key}) : super(key: key);

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();
  
  // Services
  final WaltSwapService _waltSwapService = WaltSwapService();
  final Web3AuthService _web3AuthService = Web3AuthService();
  final MultiChainService _multiChainService = MultiChainService();
  
  // Swap status for waiting screen
  String _swapStatus = '';
  
  // Available tokens for swap
  String _fromToken = 'LSK';
  String _toToken = 'POL';
  
  // Swap state
  bool _isSwapping = false;
  bool _isLoadingQuote = false;
  bool _isCalculating = false;  // Loading state for price calculation
  SwapQuote? _currentQuote;
  String? _error;
  Map<String, double> _balances = {};
  
  // Token configurations (prices fetched from API)
  static const Map<String, Map<String, dynamic>> _tokenConfigs = {
    'LSK': {
      'name': 'Lisk',
      'color': Color(0xFF0D47A1),
      'icon': 'assets/icons/homepage/LISK.png',
    },
    'ETH': {
      'name': 'Ethereum',
      'color': Color(0xFF627EEA),
      'icon': 'assets/icons/homepage/Ethereum.png',
    },
    'POL': {
      'name': 'Polygon',
      'color': Color(0xFF8247E5),
      'icon': 'assets/icons/homepage/pol.png',
    },
  };
  
  // Real-time prices from API
  final PriceService _priceService = PriceService();
  Map<String, double> _realTimePrices = {};
  Timer? _priceTimer;
  bool _isLoadingPrices = true;
  
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  // App color palette (matching Figma design with gradients)
  static const Color primaryBlue = Color(0xFF1264EF);
  static const Color primaryBlueDark = Color(0xFF0A3989);
  static const Color backgroundColor = Color(0xFFF8F8FA);
  static const Color cardWhite = Colors.white;
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textGrey = Color(0xFFA3A3A3);
  
  final TextEditingController _pinController = TextEditingController();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _fromController.addListener(_onFromChanged);
    _toController.addListener(_onToChanged);
    
    // Load balances and prices on init
    _loadBalances();
    _loadRealTimePrices();
    
    // Auto-refresh prices every 15 seconds
    _priceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadRealTimePrices();
    });
  }
  
  Future<void> _loadRealTimePrices() async {
    try {
      final prices = await _priceService.fetchPricesIDR(['LSK', 'ETH', 'POL']);
      if (mounted) {
        setState(() {
          _realTimePrices = prices;
          _isLoadingPrices = false;
        });
        print('[Swap] Real-time prices loaded: LSK=Rp${prices['LSK']}, ETH=Rp${prices['ETH']}, POL=Rp${prices['POL']}');
      }
    } catch (e) {
      print('[Swap] Error loading prices: $e');
      if (mounted) {
        setState(() => _isLoadingPrices = false);
      }
    }
  }
  
  Future<void> _loadBalances() async {
    print('[Swap] Loading token balances...');
    try {
      final authState = context.read<AuthBloc>().state;
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
        print('[Swap] No wallet address available');
        return;
      }
      
      print('[Swap] Loading balances for: $walletAddress');
      final tokens = await _multiChainService.getTokenBalances(walletAddress, token ?? '');
      
      final balances = <String, double>{};
      for (final t in tokens) {
        balances[t.symbol] = t.balanceAsDouble;
        print('[Swap] Balance ${t.symbol}: ${t.balanceAsDouble}');
      }
      
      if (mounted) {
        setState(() => _balances = balances);
      }
    } catch (e) {
      print('[Swap] Error loading balances: $e');
    }
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _debounceTimer?.cancel();
    _fromController.dispose();
    _toController.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Real-time prices from API (fallback to realistic market prices Jan 2026)
  static const Map<String, double> _fallbackPrices = {
    'LSK': 3510,      // Rp 3,510 per LSK
    'POL': 2250,      // Rp 2,250 per POL
    'ETH': 52400000,  // Rp 52,400,000 per ETH
  };
  
  double get _fromPrice => _realTimePrices[_fromToken] ?? _fallbackPrices[_fromToken] ?? 1;
  double get _toPrice => _realTimePrices[_toToken] ?? _fallbackPrices[_toToken] ?? 1;
  double get _exchangeRate => _toPrice > 0 ? _fromPrice / _toPrice : 1;

  Timer? _debounceTimer;
  
  void _onFromChanged() {
    if (_fromFocus.hasFocus) {
      final text = _fromController.text.replaceAll(',', '');
      if (text.isEmpty) {
        _toController.removeListener(_onToChanged);
        _toController.text = '';
        _toController.addListener(_onToChanged);
        setState(() => _isCalculating = false);
        return;
      }
      
      // Show loading indicator
      setState(() => _isCalculating = true);
      
      // Debounce calculation with delay
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 800), () {
        final value = double.tryParse(text) ?? 0;
        final converted = value * _exchangeRate;
        _toController.removeListener(_onToChanged);
        _toController.text = converted > 0 ? converted.toStringAsFixed(6) : '';
        _toController.addListener(_onToChanged);
        if (mounted) setState(() => _isCalculating = false);
      });
    }
  }

  void _onToChanged() {
    if (_toFocus.hasFocus) {
      final text = _toController.text.replaceAll(',', '');
      if (text.isEmpty) {
        _fromController.removeListener(_onFromChanged);
        _fromController.text = '';
        _fromController.addListener(_onFromChanged);
        setState(() => _isCalculating = false);
        return;
      }
      
      // Show loading indicator
      setState(() => _isCalculating = true);
      
      // Debounce calculation with delay
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 800), () {
        final value = double.tryParse(text) ?? 0;
        final converted = value / _exchangeRate;
        _fromController.removeListener(_onFromChanged);
        _fromController.text = converted > 0 ? converted.toStringAsFixed(6) : '';
        _fromController.addListener(_onFromChanged);
        if (mounted) setState(() => _isCalculating = false);
      });
    }
  }

  void _swapTokens() {
    _animationController.forward(from: 0);
    setState(() {
      final tempToken = _fromToken;
      _fromToken = _toToken;
      _toToken = tempToken;
      
      final tempValue = _fromController.text;
      _fromController.text = _toController.text;
      _toController.text = tempValue;
    });
  }

  void _clearAll() {
    setState(() {
      _fromController.text = '';
      _toController.text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = size.width / 393;
    
    final fromAmount = double.tryParse(_fromController.text.replaceAll(',', '')) ?? 0;
    final toAmount = double.tryParse(_toController.text.replaceAll(',', '')) ?? 0;
    final fromValueIdr = fromAmount * _fromPrice;
    final toValueIdr = toAmount * _toPrice;
    
    // Format IDR with proper thousand separators (Indonesian style: dots)
    String formatIdr(double value) {
      if (value == 0) return 'Rp 0';
      final rounded = value.round();
      // Manual formatting with dots as thousand separators
      final str = rounded.toString();
      final buffer = StringBuffer();
      int count = 0;
      for (int i = str.length - 1; i >= 0; i--) {
        if (count > 0 && count % 3 == 0) {
          buffer.write('.');
        }
        buffer.write(str[i]);
        count++;
      }
      return 'Rp ${buffer.toString().split('').reversed.join('')}';
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Gradient Background - Top portion
          Container(
            height: size.height * 0.35,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [primaryBlueDark, primaryBlue],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
          ),
          
          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 16 * s),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 44 * s,
                          height: 44 * s,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14 * s),
                          ),
                          child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20 * s),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Swap Token',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 20 * s,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: 44 * s), // Balance for back button
                    ],
                  ),
                ),
                
                // Balance Info
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20 * s),
                  child: Column(
                    children: [
                      Text(
                        'Available Balance',
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14 * s,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      SizedBox(height: 4 * s),
                      Text(
                        '${(_balances[_fromToken] ?? 0).toStringAsFixed(4)} $_fromToken',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 28 * s,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 24 * s),
                
                // Main Card
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 16 * s),
                      padding: EdgeInsets.all(20 * s),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28 * s),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                        // From Section
                        Container(
                          padding: EdgeInsets.all(16 * s),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(16 * s),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'From',
                                    style: GoogleFonts.poppins(
                                      color: textSecondary,
                                      fontSize: 13 * s,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      _fromController.text = (_balances[_fromToken] ?? 0).toString();
                                      _onFromChanged();
                                    },
                                    child: Text(
                                      'MAX',
                                      style: GoogleFonts.poppins(
                                        color: primaryBlue,
                                        fontSize: 12 * s,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8 * s),
                              Row(
                                children: [
                                  Expanded(
                                    child: _isCalculating && _toFocus.hasFocus
                                      ? Row(
                                          children: [
                                            SizedBox(
                                              width: 24 * s,
                                              height: 24 * s,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                                              ),
                                            ),
                                            SizedBox(width: 12 * s),
                                            Text(
                                              'Calculating...',
                                              style: GoogleFonts.poppins(
                                                color: textSecondary,
                                                fontSize: 16 * s,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        )
                                      : TextField(
                                          controller: _fromController,
                                          focusNode: _fromFocus,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                          style: GoogleFonts.poppins(
                                            color: textPrimary,
                                            fontSize: 28 * s,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            hintText: '0.00',
                                            hintStyle: GoogleFonts.poppins(
                                              color: Colors.grey[400],
                                              fontSize: 28 * s,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                  ),
                                  _buildTokenChip(_fromToken, true, s),
                                ],
                              ),
                              SizedBox(height: 4 * s),
                              Text(
                                '≈ ${formatIdr(fromValueIdr)}',
                                style: GoogleFonts.poppins(
                                  color: textSecondary,
                                  fontSize: 13 * s,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Swap Button
                        Transform.translate(
                          offset: Offset(0, 0),
                          child: GestureDetector(
                            onTap: _swapTokens,
                            child: Container(
                              width: 48 * s,
                              height: 48 * s,
                              margin: EdgeInsets.symmetric(vertical: 8 * s),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [primaryBlue, primaryBlueDark],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryBlue.withOpacity(0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.swap_vert_rounded,
                                color: Colors.white,
                                size: 24 * s,
                              ),
                            ),
                          ),
                        ),
                        
                        // To Section
                        Container(
                          padding: EdgeInsets.all(16 * s),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(16 * s),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'To',
                                style: GoogleFonts.poppins(
                                  color: textSecondary,
                                  fontSize: 13 * s,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8 * s),
                              Row(
                                children: [
                                  Expanded(
                                    child: _isCalculating && _fromFocus.hasFocus
                                      ? Row(
                                          children: [
                                            SizedBox(
                                              width: 24 * s,
                                              height: 24 * s,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                                              ),
                                            ),
                                            SizedBox(width: 12 * s),
                                            Text(
                                              'Calculating...',
                                              style: GoogleFonts.poppins(
                                                color: textSecondary,
                                                fontSize: 16 * s,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        )
                                      : TextField(
                                          controller: _toController,
                                          focusNode: _toFocus,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                          style: GoogleFonts.poppins(
                                            color: textPrimary,
                                            fontSize: 28 * s,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            hintText: '0.00',
                                            hintStyle: GoogleFonts.poppins(
                                              color: Colors.grey[400],
                                              fontSize: 28 * s,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                  ),
                                  _buildTokenChip(_toToken, false, s),
                                ],
                              ),
                              SizedBox(height: 4 * s),
                              Text(
                                '≈ ${formatIdr(toValueIdr)}',
                                style: GoogleFonts.poppins(
                                  color: textSecondary,
                                  fontSize: 13 * s,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        SizedBox(height: 16 * s),
                        
                        // Swap Details
                        Container(
                          padding: EdgeInsets.all(14 * s),
                          decoration: BoxDecoration(
                            color: primaryBlue.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12 * s),
                            border: Border.all(
                              color: primaryBlue.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildInfoRow('Rate', '1 $_fromToken = ${_exchangeRate.toStringAsFixed(6)} $_toToken', s),
                              Divider(height: 16 * s, color: primaryBlue.withOpacity(0.1)),
                              _buildInfoRow('Fee', '0.2%', s),
                              Divider(height: 16 * s, color: primaryBlue.withOpacity(0.1)),
                              _buildInfoRow('Network', 'Lisk Sepolia', s),
                            ],
                          ),
                        ),
                        
                        SizedBox(height: 20 * s),
                        
                        // Confirm Button
                        GestureDetector(
                          onTap: () => _showPinDialog(s),
                          child: Container(
                            width: double.infinity,
                            height: 56 * s,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [primaryBlueDark, primaryBlue],
                              ),
                              borderRadius: BorderRadius.circular(16 * s),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryBlue.withOpacity(0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 22 * s),
                                SizedBox(width: 10 * s),
                                Text(
                                  'Swap Now',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 17 * s,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        SizedBox(height: 16 * s),
                      ],
                    ),
                    ),
                  ),
                ),
                
                SizedBox(height: 16 * s),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTokenChip(String token, bool isFrom, double s) {
    return GestureDetector(
      onTap: () => _showTokenPicker(isFrom, s),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24 * s,
              height: 24 * s,
              decoration: BoxDecoration(
                color: (_tokenConfigs[token]!['color'] as Color).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  token[0],
                  style: GoogleFonts.poppins(
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w700,
                    color: _tokenConfigs[token]!['color'] as Color,
                  ),
                ),
              ),
            ),
            SizedBox(width: 6 * s),
            Text(
              token,
              style: GoogleFonts.poppins(
                color: textPrimary,
                fontSize: 14 * s,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4 * s),
            Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary, size: 18 * s),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value, double s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: textSecondary,
            fontSize: 13 * s,
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: textPrimary,
            fontSize: 13 * s,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTokenSelector(String token, bool isFrom, double s) {
    return GestureDetector(
      onTap: () => _showTokenPicker(isFrom, s),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primaryBlueDark.withOpacity(0.9),
              primaryBlue,
            ],
          ),
          borderRadius: BorderRadius.circular(25 * s),
          boxShadow: [
            BoxShadow(
              color: primaryBlue.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28 * s,
              height: 28 * s,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  token[0],
                  style: GoogleFonts.poppins(
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w700,
                    color: primaryBlueDark,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8 * s),
            Text(
              token,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14 * s,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4 * s),
            Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20 * s),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRowFigma(String label, String value, double s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontSize: 12 * s,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontSize: 12 * s,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  void _showPinDialog(double s) {
    final fromAmount = double.tryParse(_fromController.text.replaceAll(',', '')) ?? 0;
    
    if (fromAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid amount', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Check balance
    final balance = _balances[_fromToken] ?? 0;
    if (fromAmount > balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insufficient $_fromToken balance', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _pinController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SwapPinDialog(
        pinController: _pinController,
        onConfirm: () async {
          Navigator.pop(dialogContext);
          await _verifyPinAndSwap(s);
        },
        onCancel: () {
          Navigator.pop(dialogContext);
          _pinController.clear();
        },
      ),
    );
  }
  
  Future<void> _verifyPinAndSwap(double s) async {
    final pin = _pinController.text;
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN harus 6 digit'),
          backgroundColor: Colors.red,
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
          backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // PIN valid, proceed with swap
    await _executeSwap(s);
  }

  Widget _buildHeader(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 16 * s),
      decoration: BoxDecoration(
        color: cardWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40 * s,
              height: 40 * s,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: textPrimary,
                size: 18 * s,
              ),
            ),
          ),
          SizedBox(width: 16 * s),
          Text(
            'Swap Tokens',
            style: GoogleFonts.poppins(
              fontSize: 20 * s,
              color: textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _clearAll,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20 * s),
              ),
              child: Text(
                'Clear',
                style: GoogleFonts.poppins(
                  fontSize: 13 * s,
                  color: primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwapCard(double s) {
    return Container(
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(24 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // From Token
          _buildTokenInput(
            label: 'From',
            token: _fromToken,
            controller: _fromController,
            focusNode: _fromFocus,
            onTokenSelect: () => _showTokenPicker(true, s),
            s: s,
          ),
          
          // Swap Button
          Transform.translate(
            offset: Offset(0, -4 * s),
            child: GestureDetector(
              onTap: _swapTokens,
              child: AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationAnimation.value * 3.14159 * 2,
                    child: Container(
                      width: 48 * s,
                      height: 48 * s,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryBlue, primaryBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryBlue.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.swap_vert_rounded,
                        color: Colors.white,
                        size: 26 * s,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // To Token
          _buildTokenInput(
            label: 'To',
            token: _toToken,
            controller: _toController,
            focusNode: _toFocus,
            onTokenSelect: () => _showTokenPicker(false, s),
            s: s,
            isBottom: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTokenInput({
    required String label,
    required String token,
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onTokenSelect,
    required double s,
    bool isBottom = false,
  }) {
    final config = _tokenConfigs[token]!;
    final tokenColor = config['color'] as Color;
    
    return Container(
      padding: EdgeInsets.all(20 * s),
      decoration: BoxDecoration(
        color: isBottom ? backgroundColor.withOpacity(0.5) : cardWhite,
        borderRadius: BorderRadius.vertical(
          top: isBottom ? Radius.zero : Radius.circular(24 * s),
          bottom: isBottom ? Radius.circular(24 * s) : Radius.zero,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13 * s,
                  color: textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Balance: 0.00',
                style: GoogleFonts.poppins(
                  fontSize: 12 * s,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * s),
          Row(
            children: [
              // Token Selector
              GestureDetector(
                onTap: onTokenSelect,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
                  decoration: BoxDecoration(
                    color: tokenColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12 * s),
                    border: Border.all(color: tokenColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28 * s,
                        height: 28 * s,
                        decoration: BoxDecoration(
                          color: tokenColor.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            token[0],
                            style: GoogleFonts.poppins(
                              fontSize: 14 * s,
                              fontWeight: FontWeight.w700,
                              color: tokenColor,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8 * s),
                      Text(
                        token,
                        style: GoogleFonts.poppins(
                          fontSize: 15 * s,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      SizedBox(width: 4 * s),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: textSecondary,
                        size: 20 * s,
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(width: 16 * s),
              
              // Amount Input
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: GoogleFonts.poppins(
                    fontSize: 24 * s,
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 24 * s,
                      color: Colors.grey[300],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRateInfoCard(double s) {
    return Container(
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryBlue.withOpacity(0.1),
            primaryBlue.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16 * s),
        border: Border.all(color: primaryBlue.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10 * s),
            decoration: BoxDecoration(
              color: primaryBlue,
              borderRadius: BorderRadius.circular(10 * s),
            ),
            child: Icon(
              Icons.currency_exchange,
              color: Colors.white,
              size: 20 * s,
            ),
          ),
          SizedBox(width: 14 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exchange Rate',
                  style: GoogleFonts.poppins(
                    fontSize: 12 * s,
                    color: textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2 * s),
                Text(
                  '1 $_fromToken = ${_exchangeRate.toStringAsFixed(4)} $_toToken',
                  style: GoogleFonts.poppins(
                    fontSize: 15 * s,
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8 * s),
            ),
            child: Row(
              children: [
                Icon(Icons.trending_up, color: Colors.green, size: 16 * s),
                SizedBox(width: 4 * s),
                Text(
                  'Live',
                  style: GoogleFonts.poppins(
                    fontSize: 11 * s,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwapDetails(double s) {
    final fromAmount = double.tryParse(_fromController.text) ?? 0;
    final toAmount = double.tryParse(_toController.text) ?? 0;
    
    return Container(
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(16 * s),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          _buildDetailRow('You Pay', '$fromAmount $_fromToken', s),
          Divider(height: 24 * s, color: Colors.grey[200]),
          _buildDetailRow('You Receive', '$toAmount $_toToken', s),
          Divider(height: 24 * s, color: Colors.grey[200]),
          _buildDetailRow('Network Fee', '~0.001 ETH', s, isSmall: true),
          _buildDetailRow('Slippage', '0.5%', s, isSmall: true),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, double s, {bool isSmall = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isSmall ? 4 * s : 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: isSmall ? 12 * s : 14 * s,
              color: textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: isSmall ? 12 * s : 15 * s,
              fontWeight: isSmall ? FontWeight.w500 : FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwapButton(double s) {
    return GestureDetector(
      onTap: () => _executeSwap(s),
      child: Container(
        width: double.infinity,
        height: 56 * s,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryBlue, primaryBlue],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16 * s),
          boxShadow: [
            BoxShadow(
              color: primaryBlue.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.swap_horiz_rounded,
              color: Colors.white,
              size: 24 * s,
            ),
            SizedBox(width: 10 * s),
            Text(
              'Swap Now',
              style: GoogleFonts.poppins(
                fontSize: 16 * s,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTokenPicker(bool isFrom, double s) {
    final currentToken = isFrom ? _fromToken : _toToken;
    final otherToken = isFrom ? _toToken : _fromToken;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24 * s)),
        ),
        padding: EdgeInsets.all(20 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40 * s,
              height: 4 * s,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2 * s),
              ),
            ),
            SizedBox(height: 20 * s),
            Text(
              'Select Token',
              style: GoogleFonts.poppins(
                fontSize: 18 * s,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            SizedBox(height: 20 * s),
            ..._tokenConfigs.keys.where((t) => t != otherToken).map((token) {
              final config = _tokenConfigs[token]!;
              final isSelected = token == currentToken;
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isFrom) {
                      _fromToken = token;
                    } else {
                      _toToken = token;
                    }
                  });
                  _onFromChanged();
                  Navigator.pop(context);
                },
                child: Container(
                  margin: EdgeInsets.only(bottom: 12 * s),
                  padding: EdgeInsets.all(16 * s),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryBlue.withOpacity(0.1) : backgroundColor,
                    borderRadius: BorderRadius.circular(16 * s),
                    border: Border.all(
                      color: isSelected ? primaryBlue : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44 * s,
                        height: 44 * s,
                        decoration: BoxDecoration(
                          color: (config['color'] as Color).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            token[0],
                            style: GoogleFonts.poppins(
                              fontSize: 18 * s,
                              fontWeight: FontWeight.w700,
                              color: config['color'] as Color,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 14 * s),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            token,
                            style: GoogleFonts.poppins(
                              fontSize: 16 * s,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            config['name'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 12 * s,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: primaryBlue,
                          size: 24 * s,
                        ),
                    ],
                  ),
                ),
              );
            }),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSwap(double s) async {
    // Prevent double execution
    if (_isSwapping) {
      print('[Swap] Already swapping, ignoring duplicate call');
      return;
    }
    
    final fromAmount = double.tryParse(_fromController.text.replaceAll(',', '')) ?? 0;
    
    if (fromAmount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid amount', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Check balance
    final balance = _balances[_fromToken] ?? 0;
    if (fromAmount > balance) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insufficient $_fromToken balance', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (!mounted) return;
    setState(() {
      _isSwapping = true;
      _swapStatus = 'Preparing swap...';
      _error = null;
    });
    
    // Show waiting dialog
    _showSwapProgressDialog(s);
    
    print('[Swap] ========== SWAP EXECUTION START ==========');
    print('[Swap] From: $fromAmount $_fromToken');
    print('[Swap] To: $_toToken');
    print('[Swap] Using WaltSwap Contract: ${WaltSwapService.contractAddress}');
    
    try {
      // Get private key
      final privateKey = await _web3AuthService.getPrivateKey();
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not available. Please re-login.');
      }
      
      final credentials = web3.EthPrivateKey.fromHex(privateKey);
      final userAddress = credentials.address.hex;
      
      print('[Swap] User address: $userAddress');
      
      // Get quote first
      if (!mounted) return;
      setState(() => _swapStatus = 'Getting quote...');
      
      final quote = await _waltSwapService.getSwapQuote(
        fromToken: _fromToken,
        toToken: _toToken,
        fromAmount: fromAmount,
      );
      
      print('[Swap] Quote: ${quote.toAmount} $_toToken (fee: ${quote.adminFee} $_fromToken)');
      
      // Calculate minimum output with 1% slippage
      final minToAmount = quote.toAmount * 0.99;
      
      // Execute swap via WaltSwap contract
      final result = await _waltSwapService.executeSwap(
        fromToken: _fromToken,
        toToken: _toToken,
        fromAmount: fromAmount,
        minToAmount: minToAmount,
        credentials: credentials,
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() => _swapStatus = status);
          }
        },
      );
      
      if (result.success) {
        print('[Swap] Swap successful! TX: ${result.txHash}');
        print('[Swap] Output: ${result.toAmount} $_toToken');
        print('[Swap] Admin Fee: ${result.adminFee} $_fromToken');
        print('[Swap] ========== SWAP EXECUTION END ==========');
        
        // Update status in progress dialog
        if (mounted) {
          setState(() => _swapStatus = 'Saving transaction...');
        }
        
        // Record swap as transaction in Firestore for recent transactions
        await _recordSwapTransaction(
          userAddress: userAddress,
          fromToken: _fromToken,
          toToken: _toToken,
          fromAmount: fromAmount,
          toAmount: result.toAmount ?? quote.toAmount,
          txHash: result.txHash ?? '',
        );
        
        // Send notification to Firestore
        await _waltSwapService.sendSwapNotification(
          userAddress: userAddress,
          fromToken: _fromToken,
          toToken: _toToken,
          fromAmount: fromAmount,
          toAmount: result.toAmount ?? quote.toAmount,
          txHash: result.txHash ?? '',
        );
        
        if (mounted) {
          setState(() => _swapStatus = 'Confirming on blockchain...');
        }
        
        // Wait for transaction confirmation
        await Future.delayed(const Duration(seconds: 5));
        
        // Reload balances
        await _loadBalances();
        
        // Close progress dialog AFTER everything is done
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        
        if (!mounted) return;
        setState(() => _isSwapping = false);
        
        // Show success dialog
        if (mounted) {
          _showSwapSuccessDialog(
            s: s,
            fromAmount: fromAmount,
            toAmount: result.toAmount ?? quote.toAmount,
            adminFee: result.adminFee ?? quote.adminFee,
            txHash: result.txHash ?? '',
          );
        }
      } else {
        // Close progress dialog on failure
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        throw Exception(result.error ?? 'Swap failed');
      }
    } catch (e) {
      print('[Swap] Error: $e');
      
      // Close progress dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (!mounted) return;
      setState(() {
        _isSwapping = false;
        _swapStatus = '';
        _error = e.toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Swap failed: $e', style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSwapProgressDialog(double s) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24 * s),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 60 * s,
                  height: 60 * s,
                  child: CircularProgressIndicator(
                    strokeWidth: 4 * s,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                  ),
                ),
                SizedBox(height: 24 * s),
                Text(
                  'Processing Swap',
                  style: GoogleFonts.poppins(
                    fontSize: 18 * s,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                SizedBox(height: 12 * s),
                Text(
                  _swapStatus.isNotEmpty ? _swapStatus : 'Please wait...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14 * s,
                    color: textSecondary,
                  ),
                ),
                SizedBox(height: 16 * s),
                Container(
                  padding: EdgeInsets.all(12 * s),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12 * s),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz, color: Colors.blue, size: 20 * s),
                      SizedBox(width: 8 * s),
                      Text(
                        '$_fromToken → $_toToken',
                        style: GoogleFonts.poppins(
                          fontSize: 14 * s,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSwapSuccessDialog({
    required double s,
    required double fromAmount,
    required double toAmount,
    required double adminFee,
    required String txHash,
  }) {
    // Navigate to success page instead of showing dialog
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SwapSuccessPage(
          fromAmount: fromAmount,
          toAmount: toAmount,
          fromToken: _fromToken,
          toToken: _toToken,
          txHash: txHash,
          onBackToDashboard: () {
            Navigator.pop(context); // Pop success page
            Navigator.pop(context, true); // Pop swap screen with success
          },
        ),
      ),
    );
  }

  // Old dialog code - keeping for reference but not used
  void _showSwapSuccessDialogOld({
    required double s,
    required double fromAmount,
    required double toAmount,
    required double adminFee,
    required String txHash,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24 * s),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64 * s,
                height: 64 * s,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 48 * s,
              ),
            ),
            SizedBox(height: 20 * s),
            Text(
              'Swap Successful!',
              style: GoogleFonts.poppins(
                fontSize: 20 * s,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            SizedBox(height: 8 * s),
            Text(
              'Swapped $fromAmount $_fromToken\nfor ${toAmount.toStringAsFixed(6)} $_toToken',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14 * s,
                color: textSecondary,
              ),
            ),
            SizedBox(height: 12 * s),
            Container(
              padding: EdgeInsets.all(10 * s),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8 * s),
              ),
              child: Column(
                children: [
                  Text(
                    'Admin Fee: ${adminFee.toStringAsFixed(6)} $_fromToken (0.2%)',
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      color: primaryBlue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (txHash.isNotEmpty) ...[
                    SizedBox(height: 4 * s),
                    Text(
                      'TX: ${txHash.length > 18 ? '${txHash.substring(0, 10)}...${txHash.substring(txHash.length - 8)}' : txHash}',
                      style: GoogleFonts.poppins(
                        fontSize: 10 * s,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 12 * s),
            Container(
              padding: EdgeInsets.all(8 * s),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8 * s),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified, color: Colors.green, size: 16 * s),
                  SizedBox(width: 8 * s),
                  Expanded(
                    child: Text(
                      'Powered by WaltSwap Contract',
                      style: GoogleFonts.poppins(
                        fontSize: 11 * s,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24 * s),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  // Return true to indicate swap success - homepage should refresh
                  Navigator.pop(context, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  padding: EdgeInsets.symmetric(vertical: 14 * s),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12 * s),
                  ),
                ),
                child: Text(
                  'Done',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15 * s,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  /// Record swap transaction in Firestore for recent transactions
  Future<void> _recordSwapTransaction({
    required String userAddress,
    required String fromToken,
    required String toToken,
    required double fromAmount,
    required double toAmount,
    required String txHash,
  }) async {
    try {
      final normalizedWallet = userAddress.toLowerCase();
      
      // Record as "swap" type with full details
      await FirebaseFirestore.instance.collection('transactions').add({
        'type': 'swap',
        'sender_wallet': normalizedWallet,
        'sender_name': 'You',
        'receiver_wallet': normalizedWallet,
        'receiver_name': 'You',
        'amount': toAmount.toString(),
        'token': toToken,
        'from_amount': fromAmount.toString(),
        'from_token': fromToken,
        'to_amount': toAmount.toString(),
        'to_token': toToken,
        'chain_id': 4202,
        'chain_name': 'Lisk Sepolia',
        'tx_hash': txHash,
        'status': 'completed',
        'created_at': FieldValue.serverTimestamp(),
        'memo': 'Swapped $fromAmount $fromToken → ${toAmount.toStringAsFixed(4)} $toToken',
      });
      print('[Swap] Transaction recorded in Firestore');
    } catch (e) {
      print('[Swap] Failed to record transaction: $e');
    }
  }
}

/// PIN Dialog Widget for Swap
class _SwapPinDialog extends StatefulWidget {
  final TextEditingController pinController;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _SwapPinDialog({
    required this.pinController,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_SwapPinDialog> createState() => _SwapPinDialogState();
}

class _SwapPinDialogState extends State<_SwapPinDialog> {
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
            'Masukkan PIN 6 digit untuk konfirmasi swap',
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

/// Swap Success Page with Figma Design
class SwapSuccessPage extends StatelessWidget {
  final double fromAmount;
  final double toAmount;
  final String fromToken;
  final String toToken;
  final String txHash;
  final VoidCallback onBackToDashboard;

  const SwapSuccessPage({
    super.key,
    required this.fromAmount,
    required this.toAmount,
    required this.fromToken,
    required this.toToken,
    required this.txHash,
    required this.onBackToDashboard,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeFormat = DateFormat('h:mm a').format(now);
    final dateFormat = DateFormat('dd MMM yyyy').format(now);
    final txIdDisplay = txHash.isNotEmpty 
        ? '${txHash.substring(0, 10)}...' 
        : '-';
    
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
          'Swap',
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
                      '+${toAmount.toStringAsFixed(6)} $toToken',
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
                      'Swap $fromToken → $toToken',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF3A3A3A),
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    Text(
                      '-$fromAmount $fromToken',
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
                    _buildDetailRow('Time', timeFormat),
                    const SizedBox(height: 12),
                    // Date Row
                    _buildDetailRow('Date', dateFormat),
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
                    // From Amount Row
                    _buildDetailRow('From', '-$fromAmount $fromToken'),
                    const SizedBox(height: 12),
                    // To Amount Row
                    _buildDetailRow('To', '+${toAmount.toStringAsFixed(6)} $toToken'),
                    const SizedBox(height: 12),
                    // Admin Fee Row
                    _buildDetailRow('Admin fee', '0.2%'),
                    const SizedBox(height: 16),
                    // Divider
                    Container(
                      height: 1,
                      color: const Color(0xFF3A3A3A).withOpacity(0.2),
                    ),
                    const SizedBox(height: 16),
                    // Network Row
                    _buildDetailRow('Network', 'Lisk Sepolia', isBold: true),
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
