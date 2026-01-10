import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../blocs/auth/auth_bloc.dart';
import 'transfer_details_page.dart';

class CryptoTransferPage extends StatefulWidget {
  const CryptoTransferPage({Key? key}) : super(key: key);

  @override
  State<CryptoTransferPage> createState() => _CryptoTransferPageState();
}

class _CryptoTransferPageState extends State<CryptoTransferPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _recentUsers = [];
  bool _isSearching = false;
  bool _isLoadingRecent = true;
  String? _currentUserId;

  // Color palette - Blue gradient theme
  static const Color primaryBlue = Color(0xFF1264EF);
  static const Color primaryBlueDark = Color(0xFF0A3989);
  static const Color primaryTeal = Color(0xFF08BFC1); // Keep for External Wallet only
  static const Color backgroundLight = Color(0xFFF8F8FA);
  static const Color cardWhite = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _loadRecentUsers();
    
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthSuccess) {
      _currentUserId = authState.user.id;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentUsers() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .limit(10)
          .get();
      
      final users = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        if (doc.id != _currentUserId) {
          users.add({'id': doc.id, ...doc.data()});
        }
      }
      
      setState(() {
        _recentUsers = users;
        _isLoadingRecent = false;
      });
    } catch (e) {
      setState(() => _isLoadingRecent = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final queryLower = query.toLowerCase();
      final nameResults = await _firestore.collection('users').get();
      
      final results = nameResults.docs
          .where((doc) {
            if (doc.id == _currentUserId) return false;
            final data = doc.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final wallet = (data['wallet_address'] ?? '').toString().toLowerCase();
            return name.contains(queryLower) || wallet.contains(queryLower);
          })
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _onUserSelected(Map<String, dynamic> user) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransferDetailsPage(
          recipientId: user['id'] ?? '',
          recipientName: user['name'] ?? 'Unknown',
          recipientWalletAddress: user['wallet_address'] ?? '',
          recipientProfilePhoto: user['profile_photo_url'],
          isInternalUser: true,
        ),
      ),
    );
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _onExternalWalletTap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TransferDetailsPage(
          recipientId: '',
          recipientName: 'External Wallet',
          recipientWalletAddress: '',
          isInternalUser: false,
        ),
      ),
    );
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = size.width / 375;

    return Scaffold(
      backgroundColor: backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(s),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.all(20 * s),
                children: [
                  // Search Bar
                  _buildSearchBar(s),
                  SizedBox(height: 20 * s),
                  
                  // External Wallet Card
                  _buildExternalWalletCard(s),
                  SizedBox(height: 24 * s),
                  
                  // Users Section
                  if (_searchController.text.isNotEmpty)
                    _buildSearchResults(s)
                  else
                    _buildRegisteredUsers(s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 16 * s),
      decoration: BoxDecoration(
        color: cardWhite,
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
                color: backgroundLight,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send Crypto',
                  style: GoogleFonts.poppins(
                    fontSize: 20 * s,
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Choose recipient',
                  style: GoogleFonts.poppins(
                    fontSize: 12 * s,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(double s) {
    return Container(
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(16 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _searchUsers,
        style: GoogleFonts.poppins(
          fontSize: 14 * s,
          color: textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search by name or wallet address',
          hintStyle: GoogleFonts.poppins(
            fontSize: 14 * s,
            color: textSecondary.withOpacity(0.6),
          ),
          prefixIcon: Container(
            padding: EdgeInsets.all(12 * s),
            child: Icon(
              Icons.search_rounded,
              color: primaryBlue,
              size: 24 * s,
            ),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 20 * s, color: textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    _searchUsers('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16 * s,
            vertical: 16 * s,
          ),
        ),
      ),
    );
  }

  Widget _buildExternalWalletCard(double s) {
    return GestureDetector(
      onTap: _onExternalWalletTap,
      child: Container(
        padding: EdgeInsets.all(20 * s),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryBlue, primaryTeal],
          ),
          borderRadius: BorderRadius.circular(20 * s),
          boxShadow: [
            BoxShadow(
              color: primaryTeal.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56 * s,
              height: 56 * s,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16 * s),
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.white,
                size: 28 * s,
              ),
            ),
            SizedBox(width: 16 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'External Wallet',
                    style: GoogleFonts.poppins(
                      fontSize: 18 * s,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    'Send to any blockchain address',
                    style: GoogleFonts.poppins(
                      fontSize: 13 * s,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 40 * s,
              height: 40 * s,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20 * s,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisteredUsers(double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4 * s,
              height: 24 * s,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [primaryBlueDark, primaryBlue],
                ),
                borderRadius: BorderRadius.circular(2 * s),
              ),
            ),
            SizedBox(width: 12 * s),
            Text(
              'Registered Users',
              style: GoogleFonts.poppins(
                fontSize: 17 * s,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const Spacer(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20 * s),
              ),
              child: Text(
                '${_recentUsers.length} users',
                style: GoogleFonts.poppins(
                  fontSize: 12 * s,
                  fontWeight: FontWeight.w600,
                  color: primaryBlue,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16 * s),
        
        if (_isLoadingRecent)
          _buildLoadingState(s)
        else if (_recentUsers.isEmpty)
          _buildEmptyState(s, 'No registered users found')
        else
          ..._recentUsers.map((user) => _buildUserCard(user, s)),
      ],
    );
  }

  Widget _buildSearchResults(double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4 * s,
              height: 24 * s,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [primaryBlueDark, primaryBlue],
                ),
                borderRadius: BorderRadius.circular(2 * s),
              ),
            ),
            SizedBox(width: 12 * s),
            Text(
              'Search Results',
              style: GoogleFonts.poppins(
                fontSize: 17 * s,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const Spacer(),
            if (!_isSearching && _searchResults.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20 * s),
                ),
                child: Text(
                  '${_searchResults.length} found',
                  style: GoogleFonts.poppins(
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w600,
                    color: primaryBlue,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 16 * s),
        
        if (_isSearching)
          _buildLoadingState(s)
        else if (_searchResults.isEmpty)
          _buildEmptyState(s, 'No users found')
        else
          ..._searchResults.map((user) => _buildUserCard(user, s)),
      ],
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, double s) {
    final name = user['name'] ?? 'Unknown';
    final wallet = user['wallet_address'] ?? '';
    final photo = user['profile_photo_url'];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    
    // Generate consistent color based on name
    final colors = [
      const Color(0xFF4B7BF5),
      const Color(0xFF08BFC1),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
    ];
    final colorIndex = name.hashCode.abs() % colors.length;
    final avatarColor = colors[colorIndex];

    return GestureDetector(
      onTap: () => _onUserSelected(user),
      child: Container(
        margin: EdgeInsets.only(bottom: 12 * s),
        padding: EdgeInsets.all(16 * s),
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(16 * s),
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52 * s,
              height: 52 * s,
              decoration: BoxDecoration(
                color: avatarColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: avatarColor.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: photo != null && photo.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        photo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            initial,
                            style: GoogleFonts.poppins(
                              fontSize: 20 * s,
                              fontWeight: FontWeight.w700,
                              color: avatarColor,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        initial,
                        style: GoogleFonts.poppins(
                          fontSize: 20 * s,
                          fontWeight: FontWeight.w700,
                          color: avatarColor,
                        ),
                      ),
                    ),
            ),
            SizedBox(width: 14 * s),
            
            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 15 * s,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  SizedBox(height: 4 * s),
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 14 * s,
                        color: textSecondary,
                      ),
                      SizedBox(width: 4 * s),
                      Expanded(
                        child: Text(
                          wallet.isNotEmpty
                              ? '${wallet.substring(0, 8)}...${wallet.substring(wallet.length - 6)}'
                              : 'No wallet',
                          style: GoogleFonts.poppins(
                            fontSize: 12 * s,
                            color: primaryBlue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Arrow
            Container(
              width: 36 * s,
              height: 36 * s,
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: primaryBlue,
                size: 22 * s,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(double s) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(40 * s),
        child: Column(
          children: [
            SizedBox(
              width: 40 * s,
              height: 40 * s,
              child: CircularProgressIndicator(
                color: primaryBlue,
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 16 * s),
            Text(
              'Loading...',
              style: GoogleFonts.poppins(
                fontSize: 14 * s,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(double s, String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(40 * s),
        child: Column(
          children: [
            Container(
              width: 64 * s,
              height: 64 * s,
              decoration: BoxDecoration(
                color: textSecondary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_search_outlined,
                color: textSecondary,
                size: 32 * s,
              ),
            ),
            SizedBox(height: 16 * s),
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 14 * s,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
