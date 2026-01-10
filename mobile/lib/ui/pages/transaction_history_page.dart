import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/transaction_model.dart';
import '../../services/transaction_service.dart';
import '../../services/web3auth_service.dart';
import '../../blocs/auth/auth_bloc.dart';

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  final TransactionService _transactionService = TransactionService();
  final Web3AuthService _web3Auth = Web3AuthService();
  
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  String? _walletAddress;
  
  // Filters
  String _selectedFilter = 'all'; // all, sent, received, swap
  String _selectedToken = 'all';
  final List<String> _tokenOptions = ['all', 'LSK', 'ETH', 'POL'];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    
    try {
      // Try to get wallet address from AuthBloc first (same source as homepage)
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthSuccess) {
        _walletAddress = authState.user.walletAddress;
      } else if (authState is AuthNeedsWalletVerification) {
        _walletAddress = authState.user.walletAddress;
      } else {
        // Fallback to Web3Auth service
        _walletAddress = _web3Auth.walletAddress;
      }
      
      print('[TransactionHistory] Wallet address: $_walletAddress');
      
      if (_walletAddress == null || _walletAddress!.isEmpty) {
        print('[TransactionHistory] Wallet address is null or empty!');
        setState(() => _isLoading = false);
        return;
      }

      print('[TransactionHistory] Loading transactions for: $_walletAddress');
      final transactions = await _transactionService.getTransactions(
        walletAddress: _walletAddress!,
        limit: 100,
      );

      print('[TransactionHistory] Loaded ${transactions.length} transactions');
      
      setState(() {
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e, stack) {
      print('[TransactionHistory] Error loading: $e');
      print('[TransactionHistory] Stack: $stack');
      setState(() => _isLoading = false);
    }
  }

  List<TransactionModel> get _filteredTransactions {
    var filtered = _transactions;

    // Filter by type
    if (_selectedFilter == 'sent' && _walletAddress != null) {
      filtered = filtered.where((t) => t.isSender(_walletAddress!) && t.type != TransactionType.swap).toList();
    } else if (_selectedFilter == 'received' && _walletAddress != null) {
      filtered = filtered.where((t) => t.isReceiver(_walletAddress!) && t.type != TransactionType.swap).toList();
    } else if (_selectedFilter == 'swap') {
      filtered = filtered.where((t) => t.type == TransactionType.swap).toList();
    }

    // Filter by token
    if (_selectedToken != 'all') {
      filtered = filtered.where((t) => t.token == _selectedToken).toList();
    }

    return filtered;
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
          'Transaction History',
          style: GoogleFonts.poppins(
            fontSize: 18 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF08BFC1)),
            onPressed: _loadTransactions,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(s),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF08BFC1)),
                  )
                : _filteredTransactions.isEmpty
                    ? _buildEmptyState(s)
                    : _buildTransactionList(s),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(double s) {
    return Container(
      padding: EdgeInsets.all(16 * s),
      color: Colors.white,
      child: Column(
        children: [
          // Type filter - use SingleChildScrollView for horizontal scroll
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all', s),
                SizedBox(width: 8 * s),
                _buildFilterChip('Sent', 'sent', s),
                SizedBox(width: 8 * s),
                _buildFilterChip('Received', 'received', s),
                SizedBox(width: 8 * s),
                _buildFilterChip('Swap', 'swap', s),
                SizedBox(width: 12 * s),
                // Token dropdown
                Container(
                padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 4 * s),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8 * s),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedToken,
                    isDense: true,
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      color: const Color(0xFF1A1A2E),
                    ),
                    items: _tokenOptions.map((token) {
                      return DropdownMenuItem(
                        value: token,
                        child: Text(token == 'all' ? 'All Tokens' : token),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedToken = value ?? 'all');
                    },
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

  Widget _buildFilterChip(String label, String value, double s) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF08BFC1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(
            color: isSelected ? const Color(0xFF08BFC1) : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12 * s,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(double s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64 * s,
            color: Colors.grey[300],
          ),
          SizedBox(height: 16 * s),
          Text(
            'No transactions yet',
            style: GoogleFonts.poppins(
              fontSize: 16 * s,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: 8 * s),
          Text(
            'Your transaction history will appear here',
            style: GoogleFonts.poppins(
              fontSize: 13 * s,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(double s) {
    // Group transactions by date
    final Map<String, List<TransactionModel>> grouped = {};
    for (final tx in _filteredTransactions) {
      final dateKey = _formatDateKey(tx.createdAt);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(tx);
    }

    return RefreshIndicator(
      onRefresh: _loadTransactions,
      color: const Color(0xFF08BFC1),
      child: ListView.builder(
        padding: EdgeInsets.all(16 * s),
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final dateKey = grouped.keys.elementAt(index);
          final transactions = grouped[dateKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 12 * s, top: index > 0 ? 16 * s : 0),
                child: Text(
                  dateKey,
                  style: GoogleFonts.poppins(
                    fontSize: 13 * s,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              ...transactions.map((tx) => _buildTransactionCard(tx, s)),
            ],
          );
        },
      ),
    );
  }

  String _formatDateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final txDate = DateTime(date.year, date.month, date.day);

    if (txDate == today) {
      return 'Today';
    } else if (txDate == yesterday) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Widget _buildTransactionCard(TransactionModel tx, double s) {
    // Check if this is a swap transaction
    if (tx.type == TransactionType.swap) {
      return _buildSwapCard(tx, s);
    }
    
    final isSender = tx.isSender(_walletAddress ?? '');
    final isReceiver = tx.isReceiver(_walletAddress ?? '');
    
    // Determine display info based on transaction direction
    String displayName;
    String? displayPhoto;
    String displayWallet;
    
    if (isSender) {
      displayName = tx.receiverName;
      displayPhoto = tx.receiverPhoto;
      displayWallet = tx.truncatedReceiverWallet;
    } else {
      displayName = tx.senderName;
      displayPhoto = tx.senderPhoto;
      displayWallet = tx.truncatedSenderWallet;
    }

    return GestureDetector(
      onTap: () => _showTransactionDetail(tx),
      child: Container(
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
        child: Row(
          children: [
            // Icon
            Container(
              width: 48 * s,
              height: 48 * s,
              decoration: BoxDecoration(
                color: isSender
                    ? Colors.red.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSender ? Icons.arrow_upward : Icons.arrow_downward,
                color: isSender ? Colors.red[600] : Colors.green[600],
                size: 24 * s,
              ),
            ),
            SizedBox(width: 14 * s),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: GoogleFonts.poppins(
                            fontSize: 14 * s,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A2E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildStatusBadge(tx.status, s),
                    ],
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    displayWallet,
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 11 * s,
                      color: Colors.grey[500],
                    ),
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    _formatTime(tx.createdAt),
                    style: GoogleFonts.poppins(
                      fontSize: 11 * s,
                      color: Colors.grey[400],
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
                    fontSize: 15 * s,
                    fontWeight: FontWeight.w700,
                    color: isSender ? Colors.red[600] : Colors.green[600],
                  ),
                ),
                Text(
                  tx.token,
                  style: GoogleFonts.poppins(
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  /// Special card for swap transactions with detailed info
  Widget _buildSwapCard(TransactionModel tx, double s) {
    final fromAmount = tx.fromAmount ?? '0';
    final fromToken = tx.fromToken ?? 'LSK';
    final toAmount = tx.toAmount ?? tx.amount;
    final toToken = tx.toToken ?? tx.token;
    
    return GestureDetector(
      onTap: () => _showTransactionDetail(tx),
      child: Container(
        margin: EdgeInsets.only(bottom: 12 * s),
        padding: EdgeInsets.all(16 * s),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16 * s),
          border: Border.all(color: const Color(0xFF08BFC1).withOpacity(0.3)),
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
            // Header row
            Row(
              children: [
                // Swap icon
                Container(
                  width: 48 * s,
                  height: 48 * s,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF08BFC1),
                        const Color(0xFF08BFC1).withOpacity(0.7),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.swap_horiz,
                    color: Colors.white,
                    size: 26 * s,
                  ),
                ),
                SizedBox(width: 14 * s),
                
                // Swap label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Token Swap',
                            style: GoogleFonts.poppins(
                              fontSize: 14 * s,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          _buildStatusBadge(tx.status, s),
                        ],
                      ),
                      SizedBox(height: 4 * s),
                      Text(
                        'WaltSwap • ${_formatTime(tx.createdAt)}',
                        style: GoogleFonts.poppins(
                          fontSize: 11 * s,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 12 * s),
            
            // Swap details row
            Container(
              padding: EdgeInsets.all(12 * s),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Row(
                children: [
                  // From
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'From',
                          style: GoogleFonts.poppins(
                            fontSize: 10 * s,
                            color: Colors.grey[500],
                          ),
                        ),
                        SizedBox(height: 4 * s),
                        Text(
                          '-$fromAmount',
                          style: GoogleFonts.poppins(
                            fontSize: 14 * s,
                            fontWeight: FontWeight.w700,
                            color: Colors.red[600],
                          ),
                        ),
                        Text(
                          fromToken,
                          style: GoogleFonts.poppins(
                            fontSize: 12 * s,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Arrow
                  Container(
                    padding: EdgeInsets.all(8 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF08BFC1).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      color: const Color(0xFF08BFC1),
                      size: 18 * s,
                    ),
                  ),
                  
                  // To
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'To',
                          style: GoogleFonts.poppins(
                            fontSize: 10 * s,
                            color: Colors.grey[500],
                          ),
                        ),
                        SizedBox(height: 4 * s),
                        Text(
                          '+$toAmount',
                          style: GoogleFonts.poppins(
                            fontSize: 14 * s,
                            fontWeight: FontWeight.w700,
                            color: Colors.green[600],
                          ),
                        ),
                        Text(
                          toToken,
                          style: GoogleFonts.poppins(
                            fontSize: 12 * s,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
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
    );
  }

  Widget _buildStatusBadge(TransactionStatus status, double s) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case TransactionStatus.completed:
        bgColor = Colors.green.withOpacity(0.1);
        textColor = Colors.green[700]!;
        label = 'Completed';
        break;
      case TransactionStatus.pending:
        bgColor = Colors.orange.withOpacity(0.1);
        textColor = Colors.orange[700]!;
        label = 'Pending';
        break;
      case TransactionStatus.failed:
        bgColor = Colors.red.withOpacity(0.1);
        textColor = Colors.red[700]!;
        label = 'Failed';
        break;
      case TransactionStatus.cancelled:
        bgColor = Colors.grey.withOpacity(0.1);
        textColor = Colors.grey[700]!;
        label = 'Cancelled';
        break;
      case TransactionStatus.expired:
        bgColor = Colors.grey.withOpacity(0.1);
        textColor = Colors.grey[700]!;
        label = 'Expired';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6 * s),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10 * s,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showTransactionDetail(TransactionModel tx) {
    final s = MediaQuery.of(context).size.width / 375;
    final isSender = tx.isSender(_walletAddress ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24 * s)),
        ),
        padding: EdgeInsets.all(24 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40 * s,
              height: 4 * s,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2 * s),
              ),
            ),
            SizedBox(height: 24 * s),

            // Status icon
            Container(
              width: 64 * s,
              height: 64 * s,
              decoration: BoxDecoration(
                color: tx.status == TransactionStatus.completed
                    ? Colors.green.withOpacity(0.1)
                    : tx.status == TransactionStatus.failed
                        ? Colors.red.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                tx.status == TransactionStatus.completed
                    ? Icons.check_circle
                    : tx.status == TransactionStatus.failed
                        ? Icons.cancel
                        : Icons.access_time,
                color: tx.status == TransactionStatus.completed
                    ? Colors.green[600]
                    : tx.status == TransactionStatus.failed
                        ? Colors.red[600]
                        : Colors.orange[600],
                size: 36 * s,
              ),
            ),
            SizedBox(height: 16 * s),

            // Amount
            Text(
              '${isSender ? '-' : '+'}${tx.formattedAmount} ${tx.token}',
              style: GoogleFonts.poppins(
                fontSize: 28 * s,
                fontWeight: FontWeight.w700,
                color: isSender ? Colors.red[600] : Colors.green[600],
              ),
            ),
            SizedBox(height: 8 * s),

            // Type
            Text(
              isSender ? 'Sent to ${tx.receiverName}' : 'Received from ${tx.senderName}',
              style: GoogleFonts.poppins(
                fontSize: 14 * s,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 24 * s),

            // Details
            _buildDetailRow('Status', tx.status.name.toUpperCase(), s),
            _buildDetailRow('Date', '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year} ${_formatTime(tx.createdAt)}', s),
            _buildDetailRow('Network', tx.chainName, s),
            if (tx.memo != null && tx.memo!.isNotEmpty)
              _buildDetailRow('Memo', tx.memo!, s),
            if (tx.txHash != null) ...[
              SizedBox(height: 8 * s),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tx Hash',
                    style: GoogleFonts.poppins(
                      fontSize: 13 * s,
                      color: Colors.grey[500],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: tx.txHash!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tx hash copied')),
                      );
                    },
                    child: Row(
                      children: [
                        Text(
                          '${tx.txHash!.substring(0, 8)}...${tx.txHash!.substring(tx.txHash!.length - 6)}',
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 12 * s,
                            color: const Color(0xFF08BFC1),
                          ),
                        ),
                        SizedBox(width: 4 * s),
                        Icon(
                          Icons.copy,
                          size: 14 * s,
                          color: const Color(0xFF08BFC1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            SizedBox(height: 24 * s),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF08BFC1),
                  padding: EdgeInsets.symmetric(vertical: 16 * s),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12 * s),
                  ),
                ),
                child: Text(
                  'Close',
                  style: GoogleFonts.poppins(
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, double s) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * s),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13 * s,
              color: Colors.grey[500],
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13 * s,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}
