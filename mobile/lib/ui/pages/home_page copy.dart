import 'dart:async';
import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/config/env.dart';
import 'package:banking_app/services/blockchain_service.dart';
import 'package:banking_app/services/multi_chain_service.dart';
import 'package:banking_app/services/price_service.dart';
import 'package:banking_app/screens/top_up_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:banking_app/models/user_model.dart';
import 'scan_qris_page.dart' show ScanQrisScreen;
import 'crypto_transfer_page.dart';
import 'transfer_details_page.dart';
import 'swap_page.dart';
import 'profile_page.dart';
import 'near_sync_page.dart';
import 'split_bill_page.dart';
import '../../screens/receive_screen.dart';
import '../widgets/add_quick_contact_sheet.dart';
import 'transaction_history_page.dart';
import 'notification_center_page.dart';
import 'qr_receive_page.dart';
import 'request_payment_page.dart';
import '../../models/transaction_model.dart';
import '../../services/transaction_service.dart';
import '../../services/notification_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isBalanceVisible = true;
  final BlockchainService _blockchainService = BlockchainService();
  final MultiChainService _multiChainService = MultiChainService();
  final PriceService _priceService = PriceService();
  String? _walletBalance; // Balance from Web3 (in LSK)
  bool _isLoadingBalance = false;
  
  // Multi-chain token balances
  List<TokenBalance> _tokens = [];
  bool _isLoadingTokens = false;
  
  // Total balance in IDR
  TotalBalanceResult? _totalBalance;
  bool _isLoadingPrices = false;
  
  // Price updates (realtime per 10s)
  Map<String, double> _pricesIdr = {};
  Timer? _priceUpdateTimer;
  
  // Firebase user data - fetched directly from Firestore
  String? _firebaseUserName;
  String? _firebaseProfilePhoto;
  String? _walletAddress;
  bool _isLoadingFirebaseUser = false;
  
  // Quick contacts for Quick Transaction (max 5)
  List<Map<String, dynamic>> _quickContacts = [];

  // Transaction and notification services
  final TransactionService _transactionService = TransactionService();
  final NotificationService _notificationService = NotificationService();
  List<TransactionModel> _recentTransactions = [];
  int _unreadNotificationCount = 0;
  bool _isLoadingTransactions = false;
  
  @override
  void initState() {
    super.initState();
    // Start realtime price updates
    _startPriceUpdates();
    // Load balance on init if user already logged in
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = context.read<AuthBloc>().state;
      print('[HomePage] initState - AuthState: ${authState.runtimeType}');
      
      // Handle both AuthSuccess and AuthNeedsWalletVerification states
      UserModel? user;
      if (authState is AuthSuccess) {
        user = authState.user;
      } else if (authState is AuthNeedsWalletVerification) {
        user = authState.user;
      }
      
      if (user != null) {
        final walletAddr = user.walletAddress;
        print('[HomePage] User wallet: $walletAddr');
        print('[HomePage] User name from AuthBloc: ${user.name}');
        print('[HomePage] User photo from AuthBloc: ${user.profilePicture}');
        
        // Set initial values from AuthBloc while Firebase loads
        if (mounted) {
          setState(() {
            _firebaseUserName = user!.name;
            _firebaseProfilePhoto = user.profilePicture;
          });
        }
        
        _loadBalanceForUser(walletAddr);
        _loadFirebaseUserData(walletAddr);
        _loadRecentTransactions(walletAddr);
        _loadUnreadNotificationCount(walletAddr);
      }
    });
  }
  
  /// Load recent transactions for this wallet
  Future<void> _loadRecentTransactions(String? walletAddress) async {
    if (walletAddress == null || walletAddress.isEmpty) return;
    
    setState(() => _isLoadingTransactions = true);
    
    try {
      final transactions = await _transactionService.getRecentTransactions(walletAddress);
      if (mounted) {
        setState(() {
          _recentTransactions = transactions;
          _isLoadingTransactions = false;
        });
      }
    } catch (e) {
      print('[HomePage] Error loading transactions: $e');
      if (mounted) setState(() => _isLoadingTransactions = false);
    }
  }
  
  /// Load unread notification count
  Future<void> _loadUnreadNotificationCount(String? walletAddress) async {
    if (walletAddress == null || walletAddress.isEmpty) return;
    
    try {
      final count = await _notificationService.getUnreadCount(walletAddress);
      if (mounted) {
        setState(() => _unreadNotificationCount = count);
      }
    } catch (e) {
      print('[HomePage] Error loading notification count: $e');
    }
  }
  
  /// Fetch user data directly from Firebase using wallet address as document ID
  Future<void> _loadFirebaseUserData(String? walletAddress) async {
    if (walletAddress == null || walletAddress.isEmpty) return;
    
    setState(() {
      _isLoadingFirebaseUser = true;
      _walletAddress = walletAddress;
    });
    
    try {
      final docId = walletAddress.toLowerCase();
      print('[HomePage] Loading Firebase user data for: $docId');
      
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .get();
      
      if (doc.exists && mounted) {
        final data = doc.data();
        print('[HomePage] Firebase user data: $data');
        
        setState(() {
          _firebaseUserName = data?['name'] as String?;
          _firebaseProfilePhoto = data?['profile_photo_url'] as String?;
          _isLoadingFirebaseUser = false;
        });
        
        print('[HomePage] Loaded - name: $_firebaseUserName, photo: $_firebaseProfilePhoto');
        
        // Load quick contacts for Quick Transaction
        _loadQuickContacts(docId);
      } else {
        print('[HomePage] Document not found for: $docId');
        setState(() => _isLoadingFirebaseUser = false);
      }
    } catch (e) {
      print('[HomePage] Error loading Firebase user data: $e');
      if (mounted) setState(() => _isLoadingFirebaseUser = false);
    }
  }
  
  Future<void> _loadQuickContacts(String walletAddress) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(walletAddress)
          .collection('quick_contacts')
          .limit(5)
          .get();
      
      if (mounted) {
        setState(() {
          _quickContacts = snapshot.docs.map((doc) => {
            'id': doc.id,
            ...doc.data(),
          }).toList();
        });
        print('[HomePage] Loaded ${_quickContacts.length} quick contacts');
      }
    } catch (e) {
      print('[HomePage] Error loading quick contacts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final s = screenWidth / 393.0;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        // Handle both AuthSuccess and AuthNeedsWalletVerification
        String? walletAddr;
        String? userName;
        String? userPhoto;
        
        if (state is AuthSuccess) {
          walletAddr = state.user.walletAddress;
          userName = state.user.name;
          userPhoto = state.user.profilePicture;
        } else if (state is AuthNeedsWalletVerification) {
          walletAddr = state.user.walletAddress;
          userName = state.user.name;
          userPhoto = state.user.profilePicture;
        }
        
        if (walletAddr != null) {
          // Update state with user data
          setState(() {
            _firebaseUserName = userName;
            _firebaseProfilePhoto = userPhoto;
          });
          _loadBalanceForUser(walletAddr);
          _loadFirebaseUserData(walletAddr);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
          // ====== BACKGROUND DENGAN GPLAY 1-4 PATTERN ======
          _buildBackgroundWithPattern(screenWidth, screenHeight),

          // ====== MAIN CONTENT ======
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                height: 996 * s,
                width: screenWidth,
                child: _buildDashboardHomeFigma(s),
              ),
            ),
          ),

          // Bottom navigation removed per user request
        ],
      ),
      ),
    );
  }

  void _startPriceUpdates() {
    // Update prices immediately
    _updatePrices();
    
    // Then update every 1 second (real-time Indodax prices)
    _priceUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updatePrices();
    });
  }
  
  Future<void> _updatePrices() async {
    try {
      // Get all unique symbols from tokens
      final symbols = _tokens.map((t) => t.symbol).toSet().toList();
      if (symbols.isEmpty) return;
      
      final prices = await _priceService.fetchPricesIDR(symbols);
      
      if (mounted) {
        setState(() {
          _pricesIdr = prices;
        });
      }
    } catch (e) {
      if (Env.enableDebugLogs) print('[HomePage] Error updating prices: $e');
    }
  }

  @override
  void dispose() {
    _priceUpdateTimer?.cancel();
    _blockchainService.dispose();
    _priceService.dispose();
    super.dispose();
  }

  Future<void> _loadBalanceForUser(String? walletAddress) async {
    if (walletAddress == null || walletAddress.isEmpty) {
      setState(() {
        _walletBalance = null;
      });
      return;
    }

    if (_isLoadingBalance) return;

    setState(() {
      _isLoadingBalance = true;
    });

    try {
      final balanceLSK = await _blockchainService.getBalanceInLSK(walletAddress);
      if (!mounted) return;
      setState(() {
        _walletBalance = balanceLSK;
      });
      
      // Also load multi-chain tokens
      _loadTokensForUser(walletAddress);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _walletBalance = null;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingBalance = false;
      });
    }
  }

  Future<void> _loadTokensForUser(String walletAddress) async {
    if (_isLoadingTokens) return;
    
    if (Env.enableDebugLogs) print('[HomePage] Loading tokens for: $walletAddress');

    setState(() {
      _isLoadingTokens = true;
      _isLoadingPrices = true;
    });

    try {
      // Get auth token for API calls
      final firebaseUser = FirebaseAuth.instance.currentUser;
      String? authToken;
      if (firebaseUser != null) {
        authToken = await firebaseUser.getIdToken();
      }

      // Fetch tokens (will use direct RPC if no auth token)
      final tokens = await _multiChainService.getTokenBalances(
        walletAddress,
        authToken ?? '',
      );
      
      if (Env.enableDebugLogs) print('[HomePage] Tokens loaded: ${tokens.length}');

      if (!mounted) return;
      setState(() {
        _tokens = tokens;
      });
      
      // Calculate total balance in IDR
      if (tokens.isNotEmpty) {
        final balanceInputs = tokens.map((t) => TokenBalanceInput(
          symbol: t.symbol,
          balance: double.tryParse(t.balance) ?? 0,
        )).toList();
        
        final totalResult = await _priceService.calculateTotalIDR(balanceInputs);
        
        if (Env.enableDebugLogs) {
          print('[HomePage] Total USD: \$${totalResult.totalUSD.toStringAsFixed(2)}');
          print('[HomePage] Total IDR: ${totalResult.totalIDRFullFormatted}');
        }
        
        if (!mounted) return;
        setState(() {
          _totalBalance = totalResult;
        });
      }
    } catch (e) {
      if (Env.enableDebugLogs) print('[HomePage] Error loading tokens: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingTokens = false;
        _isLoadingPrices = false;
      });
    }
  }

  /// Refresh balances, transactions, and notifications - called after transfers or when returning to home
  Future<void> _refreshBalances() async {
    final authState = context.read<AuthBloc>().state;
    String? walletAddress;
    
    if (authState is AuthSuccess) {
      walletAddress = authState.user.walletAddress;
    } else if (authState is AuthNeedsWalletVerification) {
      walletAddress = authState.user.walletAddress;
    }
    
    if (walletAddress != null && walletAddress.isNotEmpty) {
      // Refresh all data in parallel
      await Future.wait([
        _loadTokensForUser(walletAddress),
        _loadRecentTransactions(walletAddress),
        _loadUnreadNotificationCount(walletAddress),
      ]);
    }
  }

  // ==================== TOP UP METHOD SHEET ====================
  void _showTopUpMethodSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewPadding.bottom;
        return SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottomInset),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Pilih Metode Top Up',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF14193F),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pilih cara untuk menambah saldo wallet Anda',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),

                // Top Up Mockup Coin - Mint MockLSK, ETH, POL from faucet
                _buildTopUpOption(
                  icon: Icons.add_circle_outline,
                  title: 'Top Up Mockup Coin',
                  subtitle: 'Top up LSK, Ethereum, dan POL (Testnet)',
                  isComingSoon: false,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    
                    // Navigate to TopUpScreen
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TopUpScreen(),
                      ),
                    );
                    
                    // Refresh balances if top up was successful
                    if (result == true && mounted) {
                      await _refreshBalances();
                    }
                  },
                ),

                const SizedBox(height: 12),

                // Via Wallet Address Option
                _buildTopUpOption(
                  icon: Icons.qr_code,
                  title: 'Via Wallet Address',
                  subtitle: 'Terima crypto melalui wallet address Anda',
                  isComingSoon: false,
                  onTap: () {
                    final state = context.read<AuthBloc>().state;
                    String? walletAddress;
                    if (state is AuthSuccess) {
                      walletAddress = state.user.walletAddress;
                    } else if (state is AuthNeedsOnboarding) {
                      walletAddress = state.user.walletAddress;
                    } else if (state is AuthNeedsWalletVerification) {
                      walletAddress = state.user.walletAddress;
                    }

                    if (walletAddress == null || walletAddress.isEmpty) {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Wallet address belum tersedia', style: GoogleFonts.poppins()),
                          backgroundColor: const Color(0xFF08BFC1),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReceiveScreen(walletAddress: walletAddress!)),
                    );
                  },
                ),

                const SizedBox(height: 16),
              ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopUpOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isComingSoon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isComingSoon ? Colors.grey[100] : const Color(0xFFE8FAF6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isComingSoon ? Colors.grey[300]! : const Color(0xFF41F5D6),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isComingSoon ? Colors.grey[300] : const Color(0xFF41F5D6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isComingSoon ? Colors.grey[600] : const Color(0xFF14193F),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isComingSoon ? Colors.grey[600] : const Color(0xFF14193F),
                          ),
                        ),
                      ),
                      if (isComingSoon) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Soon',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[800],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isComingSoon ? Colors.grey[400] : const Color(0xFF2DCEC0),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BACKGROUND (Figma Design - Light Blue/Grey) ====================
  Widget _buildBackgroundWithPattern(double screenWidth, double screenHeight) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFE8EEF6), // Light blue-grey background from Figma
      ),
    );
  }

  // ==================== DASHBOARD HOME (Responsive Layout) ====================
  Widget _buildDashboardHomeFigma(double s) {
    return RefreshIndicator(
      onRefresh: () async {
        // Refresh all data
        final authState = context.read<AuthBloc>().state;
        UserModel? user;
        if (authState is AuthSuccess) {
          user = authState.user;
        } else if (authState is AuthNeedsWalletVerification) {
          user = authState.user;
        }
        if (user != null) {
          await Future.wait([
            _loadBalanceForUser(user.walletAddress),
            _loadRecentTransactions(user.walletAddress),
            _loadUnreadNotificationCount(user.walletAddress),
          ]);
        }
      },
      color: const Color(0xFF4B7BF5),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.symmetric(horizontal: 24 * s),
        children: [
          SizedBox(height: 20 * s),
          // Header row
          _buildHeaderRow(s),
          SizedBox(height: 20 * s),
          // Blue Balance Card
          _buildBlueBalanceCard(s),
          SizedBox(height: 24 * s),
          // Quick Actions
          _buildQuickActionsFigma(s),
          SizedBox(height: 24 * s),
          // Quick Transaction
          _buildQuickTransactionSection(s),
          SizedBox(height: 24 * s),
          // My Assets
          _buildMyAssetsSection(s),
          SizedBox(height: 24 * s),
          // Recent Transaction Section
          _buildRecentTransactionSection(s),
          SizedBox(height: 160 * s), // Bottom padding for scroll - increased for navbar
        ],
      ),
    );
  }

  // ==================== HEADER ROW ====================
  Widget _buildHeaderRow(double s) {
    return Row(
      children: [
        // Avatar
        GestureDetector(
          onTap: () {
            Navigator.push(context, _createSmoothPageRoute(const ProfileScreen()));
          },
          child: ClipOval(
            child: SizedBox(
              width: 44 * s,
              height: 44 * s,
              child: (_firebaseProfilePhoto != null && _firebaseProfilePhoto!.isNotEmpty)
                  ? Image.network(
                      _firebaseProfilePhoto!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildAvatarPlaceholder(s),
                    )
                  : _buildAvatarPlaceholder(s),
            ),
          ),
        ),
        SizedBox(width: 12 * s),
        // Center: Welcome text + username - centered and larger
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Welcome!',
                style: GoogleFonts.poppins(
                  color: Colors.black.withOpacity(0.7),
                  fontSize: 16 * s,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                (_firebaseUserName != null && _firebaseUserName!.isNotEmpty)
                    ? _firebaseUserName!
                    : 'User',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF1264EF),
                  fontSize: 20 * s,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        // Bell icon with badge
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationCenterPage()),
            ).then((_) => _loadUnreadNotificationCount(_walletAddress));
          },
          child: Stack(
            children: [
              Icon(
                Icons.notifications_outlined,
                size: 26 * s,
                color: const Color(0xFF3A3A3A),
              ),
              if (_unreadNotificationCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: EdgeInsets.all(4 * s),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: BoxConstraints(
                      minWidth: 16 * s,
                      minHeight: 16 * s,
                    ),
                    child: Text(
                      _unreadNotificationCount > 9 ? '9+' : '$_unreadNotificationCount',
                      style: GoogleFonts.poppins(
                        fontSize: 10 * s,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarPlaceholder(double s) {
    return Container(
      color: const Color(0xFFD9D9D9),
      alignment: Alignment.center,
      child: Text(
        (_firebaseUserName != null && _firebaseUserName!.trim().isNotEmpty)
            ? _firebaseUserName!.trim()[0].toUpperCase()
            : 'U',
        style: GoogleFonts.poppins(
          color: const Color(0xFF3A3A3A),
          fontSize: 16 * s,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ==================== BLUE BALANCE CARD (Glossy Design) ====================
  Widget _buildBlueBalanceCard(double s) {
    // Format balance display - show IDR with visibility toggle
    String balanceDisplay = 'Loading...';
    
    if (!_isBalanceVisible) {
      balanceDisplay = 'Rp ••••••';
    } else if (_totalBalance != null) {
      balanceDisplay = _totalBalance!.totalIDRFullFormatted;
    } else if (_isLoadingPrices) {
      balanceDisplay = 'Loading...';
    }

    final walletAddress = (_walletAddress != null && _walletAddress!.isNotEmpty)
        ? _walletAddress!
        : '';

    String walletAddressDisplay = walletAddress;
    if (walletAddressDisplay.length > 18) {
      walletAddressDisplay =
          '${walletAddressDisplay.substring(0, 8)}...${walletAddressDisplay.substring(walletAddressDisplay.length - 6)}';
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20 * s),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withOpacity(0.35),
            blurRadius: 25,
            offset: const Offset(0, 12),
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 * s),
        child: IntrinsicHeight(
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/icons/homepage/cardbalance.png',
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
              padding: EdgeInsets.all(20 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Balance',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: 8 * s),
                  Text(
                    balanceDisplay,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 28 * s,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (walletAddress.isNotEmpty) ...[
                    SizedBox(height: 8 * s),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: walletAddress));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Wallet address copied'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              walletAddressDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: 11 * s,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          Icon(
                            Icons.copy,
                            size: 14 * s,
                            color: Colors.white.withOpacity(0.78),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 4 * s),
                  // Estimasi dalam IDR and action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Estimasi dalam IDR',
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12 * s,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Row(
                        children: [
                          // Eye button
                          GestureDetector(
                            onTap: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
                            child: Container(
                              width: 36 * s,
                              height: 36 * s,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isBalanceVisible ? Icons.visibility : Icons.visibility_off,
                                size: 18 * s,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 10 * s),
                          // Plus button (Top Up)
                          GestureDetector(
                            onTap: () => _showTopUpMethodSheet(context),
                            child: Container(
                              width: 36 * s,
                              height: 36 * s,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.add,
                                size: 20 * s,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ==================== QUICK TRANSACTION SECTION ====================
  Widget _buildQuickTransactionSection(double s) {
    final defaultColors = <Color>[
      const Color(0xFF7B61FF),
      const Color(0xFF4CAF50),
      const Color(0xFFE0E0E0),
      const Color(0xFF212121),
      const Color(0xFF9C27B0),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B5FCF),
            Color(0xFF4B7BF5),
          ],
        ),
        borderRadius: BorderRadius.circular(16 * s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quick Transaction',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14 * s,
                  fontWeight: FontWeight.w500,
                ),
              ),
              GestureDetector(
                onTap: () => _showAddQuickContactSheet(),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(11 * s),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12 * s, color: Colors.white),
                      SizedBox(width: 4 * s),
                      Text(
                        'Add New',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10 * s,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * s),
          // Quick contacts row (max 5 from Firebase)
          SizedBox(
            height: 50 * s,
            child: _quickContacts.isEmpty
                ? Center(
                    child: Text(
                      'No quick contacts yet',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12 * s,
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickContacts.length > 5 ? 5 : _quickContacts.length,
                    itemBuilder: (context, index) {
                      final contact = _quickContacts[index];
                      final name = contact['name'] as String? ?? '';
                      final photoUrl = contact['photo_url'] as String?;
                      final walletAddr = contact['wallet_address'] as String? ?? '';
                      final avatarColor = defaultColors[index % defaultColors.length];
                      
                      return GestureDetector(
                        onTap: () {
                          // Navigate to transfer with pre-filled recipient
                          _navigateToTransferWithContact(walletAddr, name);
                        },
                        onLongPress: () {
                          // Show delete confirmation dialog
                          _showDeleteQuickContactDialog(contact, name);
                        },
                        child: Container(
                          margin: EdgeInsets.only(right: 12 * s),
                          width: 44 * s,
                          height: 44 * s,
                          decoration: BoxDecoration(
                            color: avatarColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                          ),
                          child: photoUrl != null && photoUrl.isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 16 * s,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 16 * s,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
          ),
          if (_quickContacts.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8 * s),
              child: Text(
                'Tekan lama untuk hapus',
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 9 * s,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  void _navigateToTransferWithContact(String walletAddress, String name) {
    Navigator.push(
      context,
      _createSmoothPageRoute(
        TransferDetailsPage(
          recipientId: walletAddress,
          recipientName: name,
          recipientWalletAddress: walletAddress,
          isInternalUser: true,
        ),
      ),
    );
  }
  
  void _showAddQuickContactSheet() {
    // Check if already at max 5 contacts
    if (_quickContacts.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maksimal 5 quick contact. Hapus salah satu untuk menambahkan yang baru.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddQuickContactSheet(
        onContactAdded: (contact) {
          _addQuickContact(contact);
        },
      ),
    );
  }
  
  void _showDeleteQuickContactDialog(Map<String, dynamic> contact, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Quick Contact'),
        content: Text('Apakah Anda yakin ingin menghapus "$name" dari Quick Transfer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteQuickContact(contact);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _deleteQuickContact(Map<String, dynamic> contact) async {
    if (_walletAddress == null) return;
    
    final contactId = contact['id'] as String?;
    if (contactId == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_walletAddress!.toLowerCase())
          .collection('quick_contacts')
          .doc(contactId)
          .delete();
      
      // Reload quick contacts
      await _loadQuickContacts(_walletAddress!.toLowerCase());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quick contact dihapus'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      print('[HomePage] Error deleting quick contact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error menghapus contact: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }
  
  Future<void> _addQuickContact(Map<String, dynamic> contact) async {
    if (_walletAddress == null) return;
    
    // Double-check limit
    if (_quickContacts.length >= 5) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maksimal 5 quick contact'), duration: Duration(seconds: 2)),
        );
      }
      return;
    }
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_walletAddress!.toLowerCase())
          .collection('quick_contacts')
          .add(contact);
      
      // Reload quick contacts and wait for it to complete
      await _loadQuickContacts(_walletAddress!.toLowerCase());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quick contact added!'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      print('[HomePage] Error adding quick contact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding contact: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }
  
  // Smooth page transition with physics animation
  Route _createSmoothPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Use spring physics for smooth animation
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.5, end: 1.0).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  // ==================== MY ASSETS SECTION ====================
  Widget _buildMyAssetsSection(double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Assets',
          style: GoogleFonts.poppins(
            color: const Color(0xFF3A3A3A),
            fontSize: 18 * s,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 12 * s),
        // Asset items - always show LSK, ETH, POL
        if (_isLoadingTokens)
          Container(
            height: 58 * s,
            decoration: BoxDecoration(
              color: const Color(0xFFD3D3D3).withOpacity(0.5),
              borderRadius: BorderRadius.circular(50 * s),
            ),
            child: Center(
              child: SizedBox(
                width: 24 * s,
                height: 24 * s,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4B7BF5),
                ),
              ),
            ),
          )
        else ...[
          // Lisk
          _buildAssetItemWithIDR(s, 'LSK', 'Lisk', _getTokenBalance('LSK'), const Color(0xFF000000)),
          SizedBox(height: 8 * s),
          // Polygon
          _buildAssetItemWithIDR(s, 'POL', 'Polygon', _getTokenBalance('POL'), const Color(0xFF8247E5)),
          SizedBox(height: 8 * s),
          // Ethereum
          _buildAssetItemWithIDR(s, 'ETH', 'Ethereum', _getTokenBalance('ETH'), const Color(0xFFF5F7FA)),
        ],
      ],
    );
  }
  
  String _getTokenBalance(String symbol) {
    for (final token in _tokens) {
      if (token.symbol.toUpperCase() == symbol.toUpperCase()) {
        return token.balance;
      }
    }
    return '0';
  }
  
  double _getTokenIDRValue(String symbol, String balance) {
    final balanceNum = double.tryParse(balance) ?? 0;
    final priceIdr = _pricesIdr[symbol.toUpperCase()] ?? 0;
    return balanceNum * priceIdr;
  }
  
  String _formatIDR(double value) {
    if (value == 0) return 'Rp 0';
    if (value < 1000) return 'Rp ${value.toStringAsFixed(0)}';
    if (value < 1000000) return 'Rp ${(value / 1000).toStringAsFixed(1)}K';
    if (value < 1000000000) return 'Rp ${(value / 1000000).toStringAsFixed(1)}M';
    return 'Rp ${(value / 1000000000).toStringAsFixed(2)}B';
  }

  // ==================== RECENT TRANSACTION SECTION ====================
  Widget _buildRecentTransactionSection(double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with "See All" button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Transaction',
              style: GoogleFonts.poppins(
                color: const Color(0xFF3A3A3A),
                fontSize: 18 * s,
                fontWeight: FontWeight.w600,
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransactionHistoryPage()),
                );
              },
              child: Text(
                'See All',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF08BFC1),
                  fontSize: 14 * s,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16 * s),
        
        // Transaction list
        if (_isLoadingTransactions)
          Center(
            child: Padding(
              padding: EdgeInsets.all(20 * s),
              child: const CircularProgressIndicator(
                color: Color(0xFF08BFC1),
                strokeWidth: 2,
              ),
            ),
          )
        else if (_recentTransactions.isEmpty)
          _buildEmptyTransactionState(s)
        else
          ..._recentTransactions.take(5).map((tx) => _buildRecentTxItem(tx, s)),
      ],
    );
  }

  Widget _buildEmptyTransactionState(double s) {
    return Container(
      padding: EdgeInsets.all(24 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48 * s,
            color: Colors.grey[300],
          ),
          SizedBox(height: 12 * s),
          Text(
            'No transactions yet',
            style: GoogleFonts.poppins(
              fontSize: 14 * s,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: 4 * s),
          Text(
            'Start by sending or receiving crypto',
            style: GoogleFonts.poppins(
              fontSize: 12 * s,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTxItem(TransactionModel tx, double s) {
    final isSender = tx.isSender(_walletAddress ?? '');
    
    // Determine display info based on transaction direction
    String displayName;
    if (isSender) {
      displayName = tx.receiverName;
    } else {
      displayName = tx.senderName;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12 * s),
      padding: EdgeInsets.all(14 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 42 * s,
            height: 42 * s,
            decoration: BoxDecoration(
              color: isSender
                  ? Colors.red.withOpacity(0.1)
                  : Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSender ? Icons.arrow_upward : Icons.arrow_downward,
              color: isSender ? Colors.red[600] : Colors.green[600],
              size: 20 * s,
            ),
          ),
          SizedBox(width: 12 * s),
          
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1A1A2E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2 * s),
                Text(
                  isSender ? 'Sent' : 'Received',
                  style: GoogleFonts.poppins(
                    fontSize: 11 * s,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isSender ? '-' : '+'}${tx.formattedAmount}',
                style: GoogleFonts.poppins(
                  fontSize: 14 * s,
                  fontWeight: FontWeight.w600,
                  color: isSender ? Colors.red[600] : Colors.green[600],
                ),
              ),
              Text(
                tx.token,
                style: GoogleFonts.poppins(
                  fontSize: 11 * s,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssetItemWithIDR(double s, String symbol, String name, String balance, Color color) {
    final balanceNum = double.tryParse(balance) ?? 0;
    final idrValue = _getTokenIDRValue(symbol, balance);

    String? pngAsset;
    switch (symbol.toUpperCase()) {
      case 'LSK':
        pngAsset = 'assets/icons/homepage/LISK.png';
        break;
      case 'POL':
      case 'MATIC':
        pngAsset = 'assets/icons/homepage/pol.png';
        break;
      case 'ETH':
        pngAsset = 'assets/icons/homepage/Ethereum.png';
        break;
    }

    final Widget cryptoIcon = (pngAsset != null)
        ? Image.asset(
            pngAsset,
            width: 30 * s,
            height: 30 * s,
            fit: BoxFit.contain,
          )
        : Icon(
            Icons.currency_bitcoin,
            size: 26 * s,
            color: Colors.white,
          );
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 8 * s),
      decoration: BoxDecoration(
        color: const Color(0xFFD3D3D3).withOpacity(0.5),
        borderRadius: BorderRadius.circular(50 * s),
      ),
      child: Row(
        children: [
          // Token icon with crypto_icons
          Container(
            width: 50 * s,
            height: 50 * s,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(child: cryptoIcon),
          ),
          SizedBox(width: 12 * s),
          // Name
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.poppins(
                color: const Color(0xFF3D3D3D),
                fontSize: 18 * s,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Balance and IDR value
          Padding(
            padding: EdgeInsets.only(right: 16 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_formatBalance(balance)} $symbol',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF3D3D3D),
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatIDR(idrValue),
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBalance(String balance) {
    final value = double.tryParse(balance) ?? 0;
    if (value == 0) return '0';
    if (value < 0.01) return '<0.01';
    if (value < 1) return value.toStringAsFixed(2);
    if (value < 100) return value.toStringAsFixed(2);
    return value.toStringAsFixed(0);
  }

  Widget _buildQuickActionsFigma(double s) {
    // Action item with icon
    Widget actionItem({
      required Widget icon,
      required String label,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56 * s,
                height: 56 * s,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF4B7BF5) : const Color(0xFFE8EEF6),
                  borderRadius: BorderRadius.circular(14 * s),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4B7BF5).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: SizedBox(
                    width: 32 * s,
                    height: 32 * s,
                    child: icon,
                  ),
                ),
              ),
              SizedBox(height: 6 * s),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF3A3A3A),
                  fontSize: 10 * s,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        actionItem(
          icon: Image.asset('assets/icons/homepage/QRScan.png', width: 28 * s, height: 28 * s),
          label: 'Instant\nScan',
          active: true,
          onTap: () => Navigator.push(context, _createSmoothPageRoute(const ScanQrisScreen())),
        ),
        actionItem(
          icon: Image.asset('assets/icons/homepage/Swap.png', width: 28 * s, height: 28 * s),
          label: 'Swap',
          active: false,
          onTap: () async {
            final result = await Navigator.push(context, _createSmoothPageRoute(const SwapScreen()));
            if (result == true && mounted) _refreshBalances();
          },
        ),
        actionItem(
          icon: Image.asset('assets/icons/homepage/P2P.png', width: 28 * s, height: 28 * s),
          label: 'P2P',
          active: false,
          onTap: () async {
            final result = await Navigator.push(context, _createSmoothPageRoute(const CryptoTransferPage()));
            if (result == true && mounted) _refreshBalances();
          },
        ),
        actionItem(
          icon: Image.asset('assets/icons/homepage/NearSync.png', width: 28 * s, height: 28 * s),
          label: 'NearSync',
          active: false,
          onTap: () => Navigator.push(context, _createSmoothPageRoute(const NearSyncPage())),
        ),
        actionItem(
          icon: Image.asset("assets/icons/homepage/SplitBill.png", width: 28 * s, height: 28 * s),
          label: 'Split\nBill',
          active: false,
          onTap: () => Navigator.push(context, _createSmoothPageRoute(const SplitBillPage())),
        ),
      ],
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader(double s) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24 * s),
      child: Row(
        children: [
          // Profile picture dengan border (gunakan foto dari akun Google)
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.all(2 * s),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
              ),
              child: ClipOval(
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    String? url;
                    if (state is AuthSuccess) {
                      url = state.user.profilePicture;
                    }
                    if (url != null && url.isNotEmpty) {
                      return Image.network(
                        url,
                        width: 48 * s,
                        height: 48 * s,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 48 * s,
                          height: 48 * s,
                          color: Colors.grey,
                          child: Icon(Icons.person, color: Colors.white, size: 28 * s),
                        ),
                      );
                    }
                    return Image.asset(
                      'assets/images/Homepage/240_F_699466075_DaPTBNlNQTOwwjkOiFEoOvzDV0ByXR9E 1.png',
                      width: 48 * s,
                      height: 48 * s,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48 * s,
                        height: 48 * s,
                        color: Colors.grey,
                        child: Icon(Icons.person, color: Colors.white, size: 28 * s),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const Spacer(),
          // Hanya tampilkan nama user (tanpa teks "Welcome")
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                (_firebaseUserName != null && _firebaseUserName!.isNotEmpty) 
                    ? _firebaseUserName! 
                    : 'User',
                style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.98),
                  fontSize: 18 * s,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.15),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          // Bell icon
          Container(
            padding: EdgeInsets.all(8 * s),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.1),
            ),
            child: Icon(
              Icons.notifications_outlined,
              color: Colors.white,
              size: 24 * s,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TOTAL BALANCE - MINIMALIS & JELAS ====================
  Widget _buildTotalBalance(double s) {
    // Format balance display
    String balanceDisplay;
    String subText = '';
    
    if (_isLoadingPrices || _totalBalance == null) {
      balanceDisplay = _isBalanceVisible ? 'Loading...' : '••••••';
    } else {
      balanceDisplay = _isBalanceVisible 
          ? _totalBalance!.totalIDRFullFormatted 
          : 'Rp ••••••';
      subText = _isBalanceVisible 
          ? '≈ \$${_totalBalance!.totalUSD.toStringAsFixed(2)} USD'
          : '';
    }
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Total Balance ',
              style: GoogleFonts.inter(
                color: Colors.white.withOpacity(0.92),
                fontSize: 15 * s,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.15,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
              child: Icon(
                _isBalanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: Colors.white.withOpacity(0.75),
                size: 18 * s,
              ),
            ),
          ],
        ),
        SizedBox(height: 4 * s),
        Text(
          balanceDisplay,
          style: GoogleFonts.inter(
            color: Colors.white.withOpacity(0.98),
            fontSize: 36 * s,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.2),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        if (subText.isNotEmpty) ...[
          SizedBox(height: 2 * s),
          Text(
            subText,
            style: GoogleFonts.inter(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14 * s,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }

  // ==================== WALLET CARD (CustomClipper Envelope Design) ====================
  Widget _buildWalletCard(double s, double screenWidth) {
    final cardWidth = 340 * s;
    final totalHeight = 210 * s;
    
    // Dimensi komponen - disesuaikan dengan Figma Frame 7
    final greyCardWidth = 290 * s;
    final greyCardHeight = 70 * s;
    final envelopeWidth = 310 * s;
    final envelopeHeight = 130 * s;
    final curveHeight = 22 * s; // Kedalaman lengkungan cekung di atas envelope

    return SizedBox(
      width: cardWidth,
      height: totalHeight,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          // ========== LAYER 1: GREEN CARD (Background, terlihat sedikit di belakang grey card) ==========
          Positioned(
            top: 5 * s,
            child: Container(
              width: greyCardWidth - 20 * s,
              height: greyCardHeight - 5 * s,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF5BB36A), Color(0xFF3A7A4A)],
                ),
                borderRadius: BorderRadius.circular(18 * s),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3A7A4A).withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),

          // ========== LAYER 2: GREY CARD (Kartu utama) ==========
          Positioned(
            top: 0,
            child: Container(
              width: greyCardWidth,
              height: greyCardHeight,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8A8A8A), Color(0xFF606060)],
                ),
                borderRadius: BorderRadius.circular(20 * s),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20 * s),
                child: Stack(
                  children: [
                    // Diagonal gradient overlay
                    Positioned(
                      right: -40 * s,
                      top: -20 * s,
                      child: Transform.rotate(
                        angle: -0.4,
                        child: Container(
                          width: 120 * s,
                          height: 150 * s,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFA0A0A0).withOpacity(0.6),
                                const Color(0xFF808080).withOpacity(0.3),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Card content
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 12 * s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (_firebaseUserName != null && _firebaseUserName!.isNotEmpty) 
                                ? _firebaseUserName! 
                                : 'User',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16 * s,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: 4 * s),
                          Row(
                            children: [
                              _buildCardDotsRow(s),
                              SizedBox(width: 8 * s),
                              Text(
                                '2600',
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 10 * s,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 1,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ========== LAYER 3: ENVELOPE (Amplop dengan lengkungan cekung di atas) ==========
          Positioned(
            top: greyCardHeight - curveHeight + 6 * s, // Posisi agar grey card terlihat "masuk" ke dalam lengkungan
            child: _buildEnvelopeShape(s, envelopeWidth, envelopeHeight, curveHeight),
          ),
        ],
      ),
    );
  }

  // ==================== ENVELOPE SHAPE (dengan CustomClipper) ====================
  Widget _buildEnvelopeShape(double s, double width, double height, double curveHeight) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // Shadow layer (manual shadow karena ClipPath memotong shadow)
          Positioned(
            top: 6,
            left: 4,
            right: 4,
            bottom: 0,
            child: ClipPath(
              clipper: EnvelopeClipper(curveHeight: curveHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16 * s),
                ),
              ),
            ),
          ),
          
          // Main envelope shape
          ClipPath(
            clipper: EnvelopeClipper(curveHeight: curveHeight),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.3, 1.0],
                  colors: [
                    Color(0xFF00A5A7), // Teal terang di atas
                    Color(0xFF008182), // Teal medium
                    Color(0xFF044445), // Teal gelap di bawah
                  ],
                ),
              ),
            ),
          ),

          // Dashed border overlay
          CustomPaint(
            size: Size(width, height),
            painter: EnvelopeDashedBorderPainter(
              curveHeight: curveHeight,
              color: Colors.white.withOpacity(0.85),
              strokeWidth: 2.0,
              dashWidth: 8,
              dashSpace: 5,
            ),
          ),

          // Content inside envelope - disesuaikan posisinya
          Positioned(
            left: 22 * s,
            right: 22 * s,
            top: curveHeight + 12 * s,
            bottom: 16 * s,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Balance info
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Total Balance',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13 * s,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 6 * s),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _isBalanceVisible ? '25,867.40' : '••••••',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 28 * s,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(width: 6 * s),
                        Text(
                          'USD',
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 15 * s,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Action buttons
                Row(
                  children: [
                    // Eye button
                    GestureDetector(
                      onTap: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
                      child: Container(
                        width: 36 * s,
                        height: 36 * s,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          _isBalanceVisible 
                              ? Icons.visibility_outlined 
                              : Icons.visibility_off_outlined,
                          color: Colors.white,
                          size: 18 * s,
                        ),
                      ),
                    ),
                    SizedBox(width: 10 * s),
                    // Plus button
                    Container(
                      width: 36 * s,
                      height: 36 * s,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 20 * s,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardDotsRow(double s) {
    return Row(
      children: List.generate(3, (index) => Container(
        margin: EdgeInsets.only(right: 8 * s),
        child: Row(
          children: List.generate(4, (_) => Container(
            width: 5 * s,
            height: 5 * s,
            margin: EdgeInsets.only(right: 2 * s),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          )),
        ),
      )),
    );
  }

  // ==================== QUICK ACTIONS - PERFECT ALIGNMENT ====================
  Widget _buildQuickActions(double s) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * s),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start, // Align all items from TOP
        children: [
          _buildActionButton(s, Icons.add, 'Top Up', true, null),
          _buildActionButton(s, Icons.sync_alt, 'Transfer', false, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CryptoTransferPage(),
              ),
            );
          }),
          _buildActionButton(s, Icons.swap_horiz, 'Swap', false, () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SwapScreen(),
              ),
            );
            if (result == true && mounted) _refreshBalances();
          }),
          _buildActionButton(s, Icons.storefront_outlined, 'Merchant', false, null),
          _buildActionButton(s, Icons.grid_view_rounded, 'More', false, null),
        ],
      ),
    );
  }

  Widget _buildActionButton(double s, IconData icon, String label, bool isActive, VoidCallback? onTap) {
    // STRICT FIXED sizes for PERFECT alignment
    final iconBoxSize = 62 * s;
    final labelHeight = 20 * s; // Fixed label height
    final spacing = 10 * s;
    final totalItemHeight = iconBoxSize + spacing + labelHeight;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: totalItemHeight, // FIXED TOTAL HEIGHT for all items
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ICON CONTAINER - Fixed 62x62
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF08BFC1) : const Color(0xFF2D2D2D).withOpacity(0.75),
                borderRadius: BorderRadius.circular(16 * s),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: const Color(0xFF08BFC1).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 26 * s, // Consistent icon size
                ),
              ),
            ),
            SizedBox(height: spacing),
            // LABEL - Fixed height container with adequate width
            SizedBox(
              height: labelHeight,
              width: 70 * s, // Wider to fit "Merchant" without wrapping
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TRANSACTION SECTION ====================
  Widget _buildTransactionSection(double s) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transaction',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF2A2A2A),
                  fontSize: 20 * s,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'View All >>',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF3A3A3A),
                  fontSize: 14 * s,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 14 * s),
          // Transaction items - EQUAL SPACING
          _buildTransactionItem(
            s: s,
            logo: 'N',
            logoColor: const Color(0xFFE50914),
            title: 'Netflix',
            subtitle: 'Entertainment',
            amount: '-\$ 6.99',
          ),
          SizedBox(height: 14 * s), // Same spacing
          _buildTransactionItem(
            s: s,
            logo: 'S',
            logoColor: const Color(0xFFEE4D2D),
            title: 'Shopee',
            subtitle: 'Market Place',
            amount: '-\$ 15.59',
          ),
          SizedBox(height: 14 * s), // Same spacing
          _buildTransactionItem(
            s: s,
            icon: Icons.restaurant,
            logoColor: const Color(0xFF555555),
            title: 'Warung Jogja',
            subtitle: 'Restaurant',
            amount: '-\$ 5.98',
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem({
    required double s,
    String? logo,
    IconData? icon,
    required Color logoColor,
    required String title,
    required String subtitle,
    required String amount,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF4A4A4A).withOpacity(0.65),
        borderRadius: BorderRadius.circular(40 * s),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 50 * s,
            height: 50 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: logoColor,
            ),
            child: Center(
              child: logo != null
                  ? Text(
                      logo,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 26 * s,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 26 * s),
            ),
          ),
          SizedBox(width: 14 * s),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17 * s,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13 * s,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          // Amount
          Text(
            amount,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16 * s,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 12 * s),
        ],
      ),
    );
  }
}

// ==================== DASHED BORDER PAINTER (Rectangle 79) ====================
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double borderRadius;

  DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(borderRadius),
      ));

    // Create dashed path
    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final length = draw ? dashWidth : dashSpace;
        if (draw) {
          dashPath.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== WALLET CARD (Premium 3D Pocket Stack with Animation) ====================
// Structure: Grey Card (BACK) + Green Pocket (FRONT) with lift animation & show/hide
class WalletCard extends StatefulWidget {
  final double scale;
  final String userName;
  final String cardNumber; // Truncated address e.g. "0x91A1…4AAC"
  final String fullWalletAddress; // Full address for copying
  final String cardLastDigits;
  final String balance;
  final String maskedBalance; // e.g. "••••••"
  final String currency;
  final String eyeIconAsset;
  final String eyeOffIconAsset; // Optional: closed eye icon
  final String plusIconAsset;
  final String textureAsset;

  const WalletCard({
    super.key,
    required this.scale,
    required this.userName,
    this.cardNumber = '0x91A1…4AAC',
    this.fullWalletAddress = '',
    required this.cardLastDigits,
    required this.balance,
    this.maskedBalance = '••••••',
    required this.currency,
    required this.eyeIconAsset,
    this.eyeOffIconAsset = '',
    required this.plusIconAsset,
    required this.textureAsset,
  });

  @override
  State<WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends State<WalletCard> {
  bool _isPressed = false;
  bool _isDetailsVisible = true; // Show/Hide balance & card number

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;

    // Total panel size
    final panelW = 326 * s;
    final panelH = 201 * s;

    // Consistent corner radius for premium look
    final cardRadius = 20 * s;

    // === LAYER 1 (BACK) - Grey/Metallic Card ===
    final greyCardW = 271 * s;
    final greyCardH = 120 * s;

    // === LAYER 2 (FRONT) - Green Pocket ===
    final pocketW = 319 * s;
    final pocketH = 140 * s;
    final curveDepth = 18 * s;

    // Display values based on visibility
    final displayCardNumber = _isDetailsVisible
        ? widget.cardNumber
        : '••••   ••••   ••••   ${widget.cardLastDigits}';
    final displayBalance = _isDetailsVisible ? widget.balance : widget.maskedBalance;

    // LIFT ANIMATION: Use AnimatedPadding for smooth lift effect
    final liftAmount = _isPressed ? 12 * s : 0.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: liftAmount), // Card rises up
        child: SizedBox(
          width: panelW,
          height: panelH,
          child: Stack(
            children: [
              // ============ LAYER 1 (BACK) - METALLIC GREY CARD ============
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: greyCardW,
                  height: greyCardH,
                  margin: EdgeInsets.only(top: 12 * s),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF8E8E8E),
                        const Color(0xFF6B6B6B),
                        const Color(0xFF585858),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(cardRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(_isPressed ? 0.25 : 0.15),
                        blurRadius: _isPressed ? 16 * s : 8 * s,
                        offset: Offset(0, _isPressed ? 6 * s : 2 * s),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Glare effect
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(cardRadius),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(0.18),
                                  Colors.white.withOpacity(0.0),
                                  Colors.white.withOpacity(0.0),
                                  Colors.white.withOpacity(0.08),
                                ],
                                stops: const [0.0, 0.3, 0.7, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Content
                      Padding(
                        padding: EdgeInsets.fromLTRB(20 * s, 16 * s, 20 * s, 40 * s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.userName,
                              style: GoogleFonts.poppins(
                                fontSize: 18 * s,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.3),
                                    offset: const Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 6 * s),
                            // Wallet address with identicon and copy button (Web3 UX)
                            GestureDetector(
                              onTap: () {
                                // Copy full address to clipboard
                                final addrToCopy = widget.fullWalletAddress.isNotEmpty 
                                    ? widget.fullWalletAddress 
                                    : widget.cardNumber;
                                Clipboard.setData(ClipboardData(text: addrToCopy));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Wallet address copied!'),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: const Color(0xFF065758),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Identicon (blockies) - deterministic colors based on address
                                  _buildIdenticon(widget.cardNumber, s),
                                  SizedBox(width: 8 * s),
                                  // Truncated address
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    child: Text(
                                      displayCardNumber,
                                      key: ValueKey<String>(displayCardNumber),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12 * s,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.white.withOpacity(0.80),
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6 * s),
                                  // Copy icon
                                  Icon(
                                    Icons.copy,
                                    size: 14 * s,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ============ LAYER 2 (FRONT) - PREMIUM GREEN POCKET ============
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: pocketW,
                  height: pocketH,
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(_isPressed ? 0.55 : 0.45),
                        blurRadius: _isPressed ? 14 * s : 10 * s,
                        offset: Offset(0, _isPressed ? -6 * s : -4 * s),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _PocketDashedBorderPainter(
                      curveDepth: curveDepth,
                      radius: cardRadius,
                      dashColor: Colors.white.withOpacity(0.50),
                      dashWidth: 5 * s,
                      dashGap: 4 * s,
                      strokeWidth: 1.5 * s,
                    ),
                    child: ClipPath(
                      clipper: _PocketClipper(
                        curveDepth: curveDepth,
                        radius: cardRadius,
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF0A9A9B),
                              Color(0xFF007677),
                              Color(0xFF045455),
                            ],
                            stops: [0.0, 0.4, 1.0],
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Texture overlay
                            Positioned.fill(
                              child: ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.12),
                                    Colors.white.withOpacity(0.08),
                                  ],
                                ).createShader(bounds),
                                blendMode: BlendMode.overlay,
                                child: Image.asset(widget.textureAsset, fit: BoxFit.cover),
                              ),
                            ),

                            // Diagonal glare
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: const Alignment(0.5, 1.0),
                                    colors: [
                                      Colors.white.withOpacity(0.15),
                                      Colors.white.withOpacity(0.0),
                                      Colors.white.withOpacity(0.0),
                                    ],
                                    stops: const [0.0, 0.4, 1.0],
                                  ),
                                ),
                              ),
                            ),

                            // Content
                            Positioned(
                              left: 20 * s,
                              right: 20 * s,
                              top: curveDepth + 8 * s,
                              bottom: 14 * s,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'Total Balance',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12 * s,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withOpacity(0.80),
                                    ),
                                  ),
                                  SizedBox(height: 2 * s),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // Balance + Currency (Animated)
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 250),
                                          child: Row(
                                            key: ValueKey<String>(displayBalance),
                                            crossAxisAlignment: CrossAxisAlignment.baseline,
                                            textBaseline: TextBaseline.alphabetic,
                                            children: [
                                              Text(
                                                displayBalance,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 26 * s,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                  height: 1.0,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.black.withOpacity(0.25),
                                                      offset: const Offset(0, 1),
                                                      blurRadius: 3,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(width: 6 * s),
                                              Text(
                                                widget.currency,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13 * s,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.white.withOpacity(0.75),
                                                  height: 1.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Buttons
                                      Row(
                                        children: [
                                          // EYE BUTTON - Toggle visibility
                                          _GlassToolButton(
                                            s: s,
                                            iconAsset: widget.eyeIconAsset,
                                            size: 36 * s,
                                            iconSize: Size(16 * s, 12 * s),
                                            isActive: _isDetailsVisible,
                                            onTap: () {
                                              setState(() {
                                                _isDetailsVisible = !_isDetailsVisible;
                                              });
                                            },
                                          ),
                                          SizedBox(width: 10 * s),
                                          _GlassToolButton(
                                            s: s,
                                            iconAsset: widget.plusIconAsset,
                                            size: 36 * s,
                                            iconSize: Size(14 * s, 14 * s),
                                            onTap: () {},
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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
  
  /// Build a simple identicon (blockies-style) based on wallet address
  /// Uses deterministic colors derived from the address hash
  Widget _buildIdenticon(String address, double s) {
    // Generate deterministic colors from address
    int hash = 0;
    for (int i = 0; i < address.length; i++) {
      hash = address.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    // Generate 4 colors for a 2x2 grid pattern
    List<Color> colors = [];
    for (int i = 0; i < 4; i++) {
      final colorHash = (hash + i * 1234567) & 0xFFFFFF;
      colors.add(Color(0xFF000000 | colorHash));
    }
    
    final size = 24 * s;
    final cellSize = size / 2;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4 * s),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3 * s),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: Container(color: colors[0])),
                  Expanded(child: Container(color: colors[1])),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: Container(color: colors[2])),
                  Expanded(child: Container(color: colors[3])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== GLASS TOOL BUTTON (Premium Look with Active State) ====================
class _GlassToolButton extends StatelessWidget {
  final double s;
  final String iconAsset;
  final double size;
  final Size iconSize;
  final VoidCallback onTap;
  final bool isActive; // For toggling visual state (e.g., eye open/closed)

  const _GlassToolButton({
    required this.s,
    required this.iconAsset,
    required this.size,
    required this.iconSize,
    required this.onTap,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isActive
                ? [
                    Colors.white.withOpacity(0.30),
                    Colors.white.withOpacity(0.15),
                  ]
                : [
                    Colors.white.withOpacity(0.15),
                    Colors.white.withOpacity(0.05),
                  ],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(isActive ? 0.30 : 0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4 * s,
              offset: Offset(0, 2 * s),
            ),
          ],
        ),
        child: Center(
          child: Image.asset(
            iconAsset,
            width: iconSize.width,
            height: iconSize.height,
            fit: BoxFit.contain,
            color: Colors.white.withOpacity(0.95),
          ),
        ),
      ),
    );
  }
}

// ==================== POCKET CLIPPER (Subtle Asymmetric Curve) ====================
class _PocketClipper extends CustomClipper<Path> {
  final double curveDepth;
  final double radius;

  _PocketClipper({required this.curveDepth, required this.radius});

  @override
  Path getClip(Size size) {
    final path = Path();
    
    // ========== MATHEMATICALLY SYMMETRICAL APPROACH ==========
    // Dimensi dasar
    final double w = size.width;
    final double h = size.height;
    final double centerPoint = w / 2; // Titik tengah X (KUNCI SIMETRIS)
    
    // Tuning parameters
    final double startY = curveDepth * 0.4; // Titik awal Y di kiri/kanan (sama)
    final double curveHeight = curveDepth; // Kedalaman lengkungan dari startY
    
    // Corner radius (clamped for safety)
    final double r = radius.clamp(0.0, size.shortestSide / 2);

    // ========== DRAW PATH ==========
    
    // 1. Mulai dari KIRI BAWAH (sebelum corner)
    path.moveTo(0, h - r);
    
    // 2. Bottom-left rounded corner
    path.quadraticBezierTo(0, h, r, h);
    
    // 3. Bottom edge (kiri ke kanan)
    path.lineTo(w - r, h);
    
    // 4. Bottom-right rounded corner
    path.quadraticBezierTo(w, h, w, h - r);
    
    // 5. Naik ke KANAN ATAS (titik awal kurva sisi kanan)
    path.lineTo(w, startY);
    
    // 6. THE SYMMETRICAL CURVE (dari KANAN ke KIRI)
    //    Control Point: X = centerPoint (TENGAH), Y = startY + curveHeight (bawah)
    //    End Point: X = 0 (kiri), Y = startY (sama dengan awal)
    path.quadraticBezierTo(
      centerPoint, startY + curveHeight, // Control point PASTI di tengah
      0, startY, // End point di kiri, Y sama dengan startY (SIMETRIS)
    );
    
    // 7. Tutup path (kembali ke titik awal di kiri bawah)
    path.close();
    
    return path;
  }

  @override
  bool shouldReclip(covariant _PocketClipper oldClipper) {
    return oldClipper.curveDepth != curveDepth || oldClipper.radius != radius;
  }
}

// ==================== POCKET DASHED BORDER PAINTER ====================
class _PocketDashedBorderPainter extends CustomPainter {
  final double curveDepth;
  final double radius;
  final Color dashColor;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;

  _PocketDashedBorderPainter({
    required this.curveDepth,
    required this.radius,
    required this.dashColor,
    required this.dashWidth,
    required this.dashGap,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dashColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // ========== MATHEMATICALLY SYMMETRICAL (SAME AS CLIPPER) ==========
    final double w = size.width;
    final double h = size.height;
    final double centerPoint = w / 2;
    final double startY = curveDepth * 0.4;
    final double curveHeight = curveDepth;
    final double r = radius.clamp(0.0, size.shortestSide / 2);

    final path = Path();
    
    // Same path as _PocketClipper for perfect match
    path.moveTo(0, h - r);
    path.quadraticBezierTo(0, h, r, h);
    path.lineTo(w - r, h);
    path.quadraticBezierTo(w, h, w, h - r);
    path.lineTo(w, startY);
    path.quadraticBezierTo(centerPoint, startY + curveHeight, 0, startY);
    path.close();

    // Draw dashed border
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final extractPath = metric.extractPath(
          distance,
          (distance + dashWidth).clamp(0, metric.length),
        );
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PocketDashedBorderPainter oldDelegate) {
    return oldDelegate.curveDepth != curveDepth ||
        oldDelegate.radius != radius ||
        oldDelegate.dashColor != dashColor;
  }
}

class _CircleToolButton extends StatelessWidget {
  final double s;
  final String iconAsset;
  final double size;
  final Size iconSize;
  final VoidCallback onTap;

  const _CircleToolButton({
    required this.s,
    required this.iconAsset,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Image.asset(
            iconAsset,
            width: iconSize.width,
            height: iconSize.height,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

// ==================== WALLET CURVE CLIPPER (Quadratic Bézier) ====================
class WalletCurveClipper extends CustomClipper<Path> {
  /// Width (0..1) of shoulder region on each side.
  final double shoulderWidthPct;

  /// Shoulder depth (0..1 of height) - small drop near shoulders.
  final double shoulderDepthPct;

  /// Center dip depth (0..1 of height) - bigger drop at center.
  final double dipDepthPct;

  /// Bottom radius as a fraction of height.
  final double bottomRadiusPct;

  const WalletCurveClipper({
    required this.shoulderWidthPct,
    required this.shoulderDepthPct,
    required this.dipDepthPct,
    required this.bottomRadiusPct,
  });

  @override
  Path getClip(Size size) {
    // Clamp params so shape doesn't go weird on extreme sizes
    final sw = shoulderWidthPct.clamp(0.16, 0.28);
    final sd = shoulderDepthPct.clamp(0.02, 0.10);
    final dd = dipDepthPct.clamp(0.10, 0.22);

    final shoulderX = size.width * sw;
    final shoulderY = size.height * sd;
    final dipY = size.height * dd;

    final r = (size.height * bottomRadiusPct).clamp(0.0, size.shortestSide / 2);

    final path = Path();

    // Top wave: 3 Quadratic Béziers (left shoulder -> dip -> right shoulder)
    // Start at top-left.
    path.moveTo(0, 0);

    // Segment 1: left edge to left shoulder point
    path.quadraticBezierTo(
      shoulderX * 0.45,
      0,
      shoulderX,
      shoulderY,
    );

    // Segment 2: left shoulder to right shoulder with deeper control in center (dip)
    path.quadraticBezierTo(
      size.width * 0.50,
      dipY,
      size.width - shoulderX,
      shoulderY,
    );

    // Segment 3: right shoulder to top-right
    path.quadraticBezierTo(
      size.width - (shoulderX * 0.45),
      0,
      size.width,
      0,
    );

    // Right edge down
    path.lineTo(size.width, size.height - r);
    // Bottom-right rounded corner
    path.quadraticBezierTo(size.width, size.height, size.width - r, size.height);

    // Bottom edge
    path.lineTo(r, size.height);
    // Bottom-left rounded corner
    path.quadraticBezierTo(0, size.height, 0, size.height - r);

    // Left edge up
    path.lineTo(0, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant WalletCurveClipper oldClipper) {
    return oldClipper.shoulderWidthPct != shoulderWidthPct ||
        oldClipper.shoulderDepthPct != shoulderDepthPct ||
        oldClipper.dipDepthPct != dipDepthPct ||
        oldClipper.bottomRadiusPct != bottomRadiusPct;
  }
}

// ==================== ENVELOPE CLIPPER (CustomClipper dengan Bezier Curve) ====================
class EnvelopeClipper extends CustomClipper<Path> {
  final double curveHeight;

  EnvelopeClipper({required this.curveHeight});

  @override
  Path getClip(Size size) {
    final path = Path();
    final borderRadius = 16.0;
    
    // Titik awal: pojok kiri atas
    path.moveTo(0, borderRadius);
    
    // Pojok kiri atas (rounded)
    path.quadraticBezierTo(0, 0, borderRadius, 0);
    
    // ========== LENGKUNGAN ATAS (Bezier Curve - cekung ke bawah seperti di Figma) ==========
    // Kurva dari kiri ke tengah (turun)
    path.quadraticBezierTo(
      size.width * 0.25, curveHeight * 0.8,  // Control point kiri
      size.width * 0.5, curveHeight,          // End point (titik terendah di tengah)
    );
    
    // Kurva dari tengah ke kanan (naik kembali)
    path.quadraticBezierTo(
      size.width * 0.75, curveHeight * 0.8,  // Control point kanan
      size.width - borderRadius, 0,           // End point
    );
    
    // Pojok kanan atas (rounded)
    path.quadraticBezierTo(size.width, 0, size.width, borderRadius);
    
    // Sisi kanan (garis lurus ke bawah)
    path.lineTo(size.width, size.height - borderRadius);
    
    // Pojok kanan bawah (rounded)
    path.quadraticBezierTo(size.width, size.height, size.width - borderRadius, size.height);
    
    // Sisi bawah (garis lurus ke kiri)
    path.lineTo(borderRadius, size.height);
    
    // Pojok kiri bawah (rounded)
    path.quadraticBezierTo(0, size.height, 0, size.height - borderRadius);
    
    // Sisi kiri (garis lurus ke atas)
    path.lineTo(0, borderRadius);
    
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ==================== ENVELOPE DASHED BORDER PAINTER ====================
class EnvelopeDashedBorderPainter extends CustomPainter {
  final double curveHeight;
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  EnvelopeDashedBorderPainter({
    required this.curveHeight,
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final borderRadius = 16.0;
    
    // Buat path yang sama dengan EnvelopeClipper
    final path = Path();
    
    // Titik awal: pojok kiri atas
    path.moveTo(0, borderRadius);
    
    // Pojok kiri atas (rounded)
    path.quadraticBezierTo(0, 0, borderRadius, 0);
    
    // Lengkungan atas (cekung ke bawah)
    path.quadraticBezierTo(
      size.width * 0.25, curveHeight * 0.8,
      size.width * 0.5, curveHeight,
    );
    
    path.quadraticBezierTo(
      size.width * 0.75, curveHeight * 0.8,
      size.width - borderRadius, 0,
    );
    
    // Pojok kanan atas (rounded)
    path.quadraticBezierTo(size.width, 0, size.width, borderRadius);
    
    // Sisi kanan (garis lurus ke bawah)
    path.lineTo(size.width, size.height - borderRadius);
    
    // Pojok kanan bawah (rounded)
    path.quadraticBezierTo(size.width, size.height, size.width - borderRadius, size.height);
    
    // Sisi bawah (garis lurus ke kiri)
    path.lineTo(borderRadius, size.height);
    
    // Pojok kiri bawah (rounded)
    path.quadraticBezierTo(0, size.height, 0, size.height - borderRadius);
    
    // Sisi kiri (garis lurus ke atas)
    path.lineTo(0, borderRadius);
    
    path.close();

    // Create dashed path
    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final length = draw ? dashWidth : dashSpace;
        if (draw) {
          dashPath.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
