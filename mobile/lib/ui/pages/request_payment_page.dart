import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/payment_request_model.dart';
import '../../services/payment_request_service.dart';
import '../../services/web3auth_service.dart';

class RequestPaymentPage extends StatefulWidget {
  const RequestPaymentPage({super.key});

  @override
  State<RequestPaymentPage> createState() => _RequestPaymentPageState();
}

class _RequestPaymentPageState extends State<RequestPaymentPage> with SingleTickerProviderStateMixin {
  final PaymentRequestService _requestService = PaymentRequestService();
  final Web3AuthService _web3Auth = Web3AuthService();
  
  late TabController _tabController;
  
  // Create request form
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  
  String _selectedToken = 'LSK';
  final List<String> _tokens = ['LSK', 'ETH', 'POL'];
  
  Map<String, dynamic>? _selectedUser;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _recentUsers = [];
  bool _isSearching = false;
  bool _isCreating = false;
  
  // Request lists
  List<PaymentRequestModel> _sentRequests = [];
  List<PaymentRequestModel> _receivedRequests = [];
  bool _isLoadingRequests = true;
  
  String? _walletAddress;
  String? _userName;
  String? _userPhoto;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
    _loadRecentUsers();
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    _walletAddress = _web3Auth.walletAddress;
    if (_walletAddress != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_walletAddress!.toLowerCase())
            .get();
        if (doc.exists) {
          setState(() {
            _userName = doc.data()?['name'] ?? 'Unknown';
            _userPhoto = doc.data()?['profile_photo_url'];
          });
        }
      } catch (e) {
        print('[RequestPayment] Error loading user: $e');
      }
    }
  }

  Future<void> _loadRecentUsers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('wallet_address', isNotEqualTo: _walletAddress?.toLowerCase())
          .limit(10)
          .get();

      setState(() {
        _recentUsers = snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList();
      });
    } catch (e) {
      print('[RequestPayment] Error loading recent users: $e');
    }
  }

  Future<void> _loadRequests() async {
    if (_walletAddress == null) return;
    
    setState(() => _isLoadingRequests = true);
    
    try {
      final sent = await _requestService.getPaymentRequests(
        walletAddress: _walletAddress!,
        asRequester: true,
        asPayer: false,
      );
      
      final received = await _requestService.getPaymentRequests(
        walletAddress: _walletAddress!,
        asRequester: false,
        asPayer: true,
      );
      
      setState(() {
        _sentRequests = sent;
        _receivedRequests = received;
        _isLoadingRequests = false;
      });
    } catch (e) {
      print('[RequestPayment] Error loading requests: $e');
      setState(() => _isLoadingRequests = false);
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
      
      // Search by name or wallet address
      final nameSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10)
          .get();

      final results = nameSnapshot.docs
          .where((doc) => doc.id.toLowerCase() != _walletAddress?.toLowerCase())
          .map((doc) => {
            'id': doc.id,
            ...doc.data(),
          })
          .toList();

      // Also check if query is a wallet address
      if (query.startsWith('0x') && query.length >= 10) {
        final walletDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(queryLower)
            .get();
        
        if (walletDoc.exists && walletDoc.id.toLowerCase() != _walletAddress?.toLowerCase()) {
          final existing = results.any((r) => r['id'] == walletDoc.id);
          if (!existing) {
            results.insert(0, {
              'id': walletDoc.id,
              ...walletDoc.data()!,
            });
          }
        }
      }

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      print('[RequestPayment] Error searching: $e');
      setState(() => _isSearching = false);
    }
  }

  Future<void> _createRequest() async {
    if (_selectedUser == null || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a user and enter amount')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      await _requestService.createPaymentRequest(
        requesterWallet: _walletAddress!,
        requesterName: _userName ?? 'Unknown',
        requesterPhoto: _userPhoto,
        payerWallet: _selectedUser!['wallet_address'] ?? _selectedUser!['id'],
        payerName: _selectedUser!['name'] ?? 'Unknown',
        payerPhoto: _selectedUser!['profile_photo_url'],
        amount: _amountController.text,
        token: _selectedToken,
        memo: _memoController.text.isEmpty ? null : _memoController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment request sent!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Reset form
        setState(() {
          _selectedUser = null;
          _amountController.clear();
          _memoController.clear();
          _searchController.clear();
          _searchResults = [];
        });
        
        // Reload requests
        _loadRequests();
        
        // Switch to sent tab
        _tabController.animateTo(1);
      }
    } catch (e) {
      print('[RequestPayment] Error creating request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final s = screenWidth / 375;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Request Payment',
          style: GoogleFonts.poppins(
            fontSize: 18 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF08BFC1),
          unselectedLabelColor: Colors.grey[500],
          indicatorColor: const Color(0xFF08BFC1),
          labelStyle: GoogleFonts.poppins(
            fontSize: 13 * s,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'New Request'),
            Tab(text: 'Sent'),
            Tab(text: 'Received'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreateRequestTab(s),
          _buildSentRequestsTab(s),
          _buildReceivedRequestsTab(s),
        ],
      ),
    );
  }

  Widget _buildCreateRequestTab(double s) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected User Card
          if (_selectedUser != null) _buildSelectedUserCard(s),
          
          // Search Field
          if (_selectedUser == null) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12 * s),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _searchUsers,
                style: GoogleFonts.poppins(fontSize: 14 * s),
                decoration: InputDecoration(
                  hintText: 'Search by name or wallet address',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 14 * s,
                    color: Colors.grey[400],
                  ),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16 * s),
                ),
              ),
            ),
            SizedBox(height: 16 * s),

            // Search Results or Recent Users
            if (_searchController.text.isNotEmpty)
              _buildSearchResults(s)
            else
              _buildRecentUsers(s),
          ],

          // Amount & Token Selection (show after user selected)
          if (_selectedUser != null) ...[
            SizedBox(height: 20 * s),
            _buildAmountSection(s),
            SizedBox(height: 16 * s),
            _buildMemoSection(s),
            SizedBox(height: 24 * s),
            _buildCreateButton(s),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedUserCard(double s) {
    final name = _selectedUser!['name'] ?? 'Unknown';
    final wallet = _selectedUser!['wallet_address'] ?? _selectedUser!['id'] ?? '';
    final photo = _selectedUser!['profile_photo_url'];
    
    String truncatedWallet = wallet;
    if (wallet.length > 16) {
      truncatedWallet = '${wallet.substring(0, 8)}...${wallet.substring(wallet.length - 6)}';
    }

    return Container(
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF08BFC1).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16 * s),
        border: Border.all(color: const Color(0xFF08BFC1)),
      ),
      child: Row(
        children: [
          Container(
            width: 48 * s,
            height: 48 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF08BFC1).withOpacity(0.2),
              image: photo != null
                  ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover)
                  : null,
            ),
            child: photo == null
                ? Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: GoogleFonts.poppins(
                        fontSize: 18 * s,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF08BFC1),
                      ),
                    ),
                  )
                : null,
          ),
          SizedBox(width: 14 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Request from',
                  style: GoogleFonts.poppins(
                    fontSize: 11 * s,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 15 * s,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  truncatedWallet,
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 11 * s,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _selectedUser = null),
            icon: Icon(Icons.close, color: Colors.grey[600], size: 20 * s),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(double s) {
    if (_isSearching) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20 * s),
          child: const CircularProgressIndicator(color: Color(0xFF08BFC1)),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20 * s),
          child: Text(
            'No users found',
            style: GoogleFonts.poppins(fontSize: 14 * s, color: Colors.grey[500]),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search Results',
          style: GoogleFonts.poppins(
            fontSize: 14 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        SizedBox(height: 12 * s),
        ..._searchResults.map((user) => _buildUserItem(user, s)),
      ],
    );
  }

  Widget _buildRecentUsers(double s) {
    if (_recentUsers.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Users',
          style: GoogleFonts.poppins(
            fontSize: 14 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        SizedBox(height: 12 * s),
        ..._recentUsers.map((user) => _buildUserItem(user, s)),
      ],
    );
  }

  Widget _buildUserItem(Map<String, dynamic> user, double s) {
    final name = user['name'] ?? 'Unknown';
    final wallet = user['wallet_address'] ?? user['id'] ?? '';
    final photo = user['profile_photo_url'];
    
    String truncatedWallet = wallet;
    if (wallet.length > 16) {
      truncatedWallet = '${wallet.substring(0, 8)}...${wallet.substring(wallet.length - 6)}';
    }

    return GestureDetector(
      onTap: () => setState(() {
        _selectedUser = user;
        _searchController.clear();
        _searchResults = [];
      }),
      child: Container(
        margin: EdgeInsets.only(bottom: 10 * s),
        padding: EdgeInsets.all(14 * s),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12 * s),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40 * s,
              height: 40 * s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF08BFC1).withOpacity(0.1),
                image: photo != null
                    ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover)
                    : null,
              ),
              child: photo == null
                  ? Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: GoogleFonts.poppins(
                          fontSize: 16 * s,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF08BFC1),
                        ),
                      ),
                    )
                  : null,
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    truncatedWallet,
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 11 * s,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20 * s),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountSection(double s) {
    return Container(
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16 * s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount',
            style: GoogleFonts.poppins(
              fontSize: 14 * s,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          SizedBox(height: 12 * s),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.poppins(
              fontSize: 24 * s,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: GoogleFonts.poppins(
                fontSize: 24 * s,
                color: Colors.grey[300],
              ),
              border: InputBorder.none,
            ),
          ),
          SizedBox(height: 12 * s),
          Row(
            children: _tokens.map((token) {
              final isSelected = _selectedToken == token;
              return GestureDetector(
                onTap: () => setState(() => _selectedToken = token),
                child: Container(
                  margin: EdgeInsets.only(right: 8 * s),
                  padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF08BFC1) : const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(20 * s),
                  ),
                  child: Text(
                    token,
                    style: GoogleFonts.poppins(
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey[600],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoSection(double s) {
    return Container(
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16 * s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Note (Optional)',
            style: GoogleFonts.poppins(
              fontSize: 14 * s,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          SizedBox(height: 12 * s),
          TextField(
            controller: _memoController,
            maxLines: 2,
            style: GoogleFonts.poppins(fontSize: 14 * s),
            decoration: InputDecoration(
              hintText: 'What is this payment for?',
              hintStyle: GoogleFonts.poppins(
                fontSize: 14 * s,
                color: Colors.grey[400],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12 * s),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12 * s),
                borderSide: const BorderSide(color: Color(0xFF08BFC1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateButton(double s) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isCreating ? null : _createRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF08BFC1),
          padding: EdgeInsets.symmetric(vertical: 16 * s),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12 * s),
          ),
        ),
        child: _isCreating
            ? SizedBox(
                width: 24 * s,
                height: 24 * s,
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Send Request',
                style: GoogleFonts.poppins(
                  fontSize: 15 * s,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildSentRequestsTab(double s) {
    if (_isLoadingRequests) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF08BFC1)),
      );
    }

    if (_sentRequests.isEmpty) {
      return _buildEmptyState(s, 'No sent requests', 'Your payment requests will appear here');
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: EdgeInsets.all(16 * s),
        itemCount: _sentRequests.length,
        itemBuilder: (context, index) {
          return _buildRequestCard(_sentRequests[index], true, s);
        },
      ),
    );
  }

  Widget _buildReceivedRequestsTab(double s) {
    if (_isLoadingRequests) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF08BFC1)),
      );
    }

    if (_receivedRequests.isEmpty) {
      return _buildEmptyState(s, 'No received requests', 'Payment requests from others will appear here');
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: EdgeInsets.all(16 * s),
        itemCount: _receivedRequests.length,
        itemBuilder: (context, index) {
          return _buildRequestCard(_receivedRequests[index], false, s);
        },
      ),
    );
  }

  Widget _buildEmptyState(double s, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64 * s, color: Colors.grey[300]),
          SizedBox(height: 16 * s),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16 * s,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: 8 * s),
          Text(
            subtitle,
            style: GoogleFonts.poppins(fontSize: 13 * s, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(PaymentRequestModel request, bool isSent, double s) {
    final otherName = isSent ? request.payerName : request.requesterName;
    final otherPhoto = isSent ? request.payerPhoto : request.requesterPhoto;

    Color statusColor;
    String statusText;
    
    switch (request.status) {
      case PaymentRequestStatus.pending:
        statusColor = Colors.orange;
        statusText = request.isExpired ? 'Expired' : 'Pending';
        break;
      case PaymentRequestStatus.paid:
        statusColor = Colors.green;
        statusText = 'Paid';
        break;
      case PaymentRequestStatus.cancelled:
        statusColor = Colors.grey;
        statusText = 'Cancelled';
        break;
      case PaymentRequestStatus.expired:
        statusColor = Colors.grey;
        statusText = 'Expired';
        break;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12 * s),
      padding: EdgeInsets.all(16 * s),
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
          Row(
            children: [
              Container(
                width: 44 * s,
                height: 44 * s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF08BFC1).withOpacity(0.1),
                  image: otherPhoto != null
                      ? DecorationImage(image: NetworkImage(otherPhoto), fit: BoxFit.cover)
                      : null,
                ),
                child: otherPhoto == null
                    ? Center(
                        child: Text(
                          otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                          style: GoogleFonts.poppins(
                            fontSize: 16 * s,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF08BFC1),
                          ),
                        ),
                      )
                    : null,
              ),
              SizedBox(width: 12 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSent ? 'To: $otherName' : 'From: $otherName',
                      style: GoogleFonts.poppins(
                        fontSize: 14 * s,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    if (request.memo != null && request.memo!.isNotEmpty)
                      Text(
                        request.memo!,
                        style: GoogleFonts.poppins(
                          fontSize: 12 * s,
                          color: Colors.grey[500],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${request.formattedAmount} ${request.token}',
                    style: GoogleFonts.poppins(
                      fontSize: 15 * s,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6 * s),
                    ),
                    child: Text(
                      statusText,
                      style: GoogleFonts.poppins(
                        fontSize: 10 * s,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          // Action buttons for pending requests
          if (request.status == PaymentRequestStatus.pending && !request.isExpired) ...[
            SizedBox(height: 12 * s),
            Divider(color: Colors.grey[200]),
            SizedBox(height: 8 * s),
            Row(
              children: [
                if (!isSent) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _declineRequest(request),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8 * s),
                        ),
                      ),
                      child: Text('Decline', style: GoogleFonts.poppins(fontSize: 12 * s)),
                    ),
                  ),
                  SizedBox(width: 8 * s),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _payRequest(request),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF08BFC1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8 * s),
                        ),
                      ),
                      child: Text(
                        'Pay',
                        style: GoogleFonts.poppins(fontSize: 12 * s, color: Colors.white),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _cancelRequest(request),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[600],
                        side: BorderSide(color: Colors.red[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8 * s),
                        ),
                      ),
                      child: Text('Cancel Request', style: GoogleFonts.poppins(fontSize: 12 * s)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _payRequest(PaymentRequestModel request) {
    // TODO: Navigate to transfer page with pre-filled data
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pay ${request.formattedAmount} ${request.token} to ${request.requesterName}')),
    );
  }

  void _declineRequest(PaymentRequestModel request) {
    // For now, just show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Request declined')),
    );
  }

  Future<void> _cancelRequest(PaymentRequestModel request) async {
    try {
      await _requestService.cancelRequest(request.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request cancelled')),
      );
      _loadRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
