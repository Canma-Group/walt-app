import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart' as web3;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/user_model.dart';
import '../../models/notification_model.dart';
import '../../config/env.dart';
import '../../services/notification_service.dart';
import '../../services/canma_splitbill_v5_service.dart';

class SplitBillPage extends StatefulWidget {
  const SplitBillPage({Key? key}) : super(key: key);
  @override
  State<SplitBillPage> createState() => _SplitBillPageState();
}

class _SplitBillPageState extends State<SplitBillPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  static const Color primaryBlue = Color(0xFF1264EF);
  static const Color darkBlue = Color(0xFF0A3989);
  static const Color backgroundColor = Color(0xFFF8F8FA);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color successGreen = Color(0xFF22C55E);
  static const Color warningOrange = Color(0xFFF97316);
  static const Color errorRed = Color(0xFFEF4444);
  
  // Token addresses supported by WaltSplitBillV3 contract
  static const String lskTokenAddress = '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';
  static const String polTokenAddress = '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e';
  
  String? _walletAddress;
  String? _privateKey;
  Map<String, BigInt> _tokenBalances = {'LSK': BigInt.zero, 'POL': BigInt.zero, 'ETH': BigInt.zero};
  String _selectedToken = 'LSK';
  
  final _totalAmountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _participantController = TextEditingController();
  final _searchController = TextEditingController();
  
  List<SplitParticipant> _participants = [];
  bool _isCreating = false;
  List<ContractBill> _allBills = [];
  bool _isLoadingBills = false;
  String? _payingBillId;
  String? _claimingRefundBillId;
  List<RegisteredUser> _searchResults = [];
  List<RegisteredUser> _registeredUsers = [];
  bool _showUserPicker = false;

  final NotificationService _notificationService = NotificationService();
  final CanmaSplitBillV5Service _contractService = CanmaSplitBillV5Service();
  DateTime _selectedDeadline = DateTime.now().add(const Duration(hours: 24));
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadWalletInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _totalAmountController.dispose();
    _descriptionController.dispose();
    _participantController.dispose();
    _searchController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadWalletInfo() async {
    final authState = context.read<AuthBloc>().state;
    UserModel? user;
    if (authState is AuthSuccess) user = authState.user;
    else if (authState is AuthNeedsWalletVerification) user = authState.user;
    
    if (user != null) {
      setState(() => _walletAddress = user!.walletAddress);
      const storage = FlutterSecureStorage();
      _privateKey = await storage.read(key: 'web3auth_private_key');
      await Future.wait([_loadAllTokenBalances(), _loadAllBills(), _loadRegisteredUsers()]);
      _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
    }
  }

  Future<void> _loadAllTokenBalances() async {
    if (_walletAddress == null) return;
    try {
      final httpClient = http.Client();
      final web3Client = web3.Web3Client(Env.liskRpcUrl, httpClient);
      final walletAddr = web3.EthereumAddress.fromHex(_walletAddress!);
      
      try {
        final lskContract = web3.DeployedContract(web3.ContractAbi.fromJson(_erc20Abi, 'ERC20'), web3.EthereumAddress.fromHex(lskTokenAddress));
        final lskResult = await web3Client.call(contract: lskContract, function: lskContract.function('balanceOf'), params: [walletAddr]);
        _tokenBalances['LSK'] = lskResult[0] as BigInt;
      } catch (_) {}
      
      try {
        final polContract = web3.DeployedContract(web3.ContractAbi.fromJson(_erc20Abi, 'ERC20'), web3.EthereumAddress.fromHex(polTokenAddress));
        final polResult = await web3Client.call(contract: polContract, function: polContract.function('balanceOf'), params: [walletAddr]);
        _tokenBalances['POL'] = polResult[0] as BigInt;
      } catch (_) {}
      
      try {
        final ethBalance = await web3Client.getBalance(walletAddr);
        _tokenBalances['ETH'] = ethBalance.getInWei;
      } catch (_) {}
      
      setState(() {});
      web3Client.dispose();
      httpClient.close();
    } catch (e) { print('[SplitBill] Balance error: $e'); }
  }

  String _formatBalance(BigInt balance) => (balance / BigInt.from(1e18)).toStringAsFixed(2);

  Future<void> _loadAllBills() async {
    if (_walletAddress == null) return;
    setState(() => _isLoadingBills = true);
    try {
      // Load from smart contract only
      final bills = await _contractService.getAllBillsForUser(_walletAddress!);
      bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _allBills = bills);
      print('[SplitBill] Loaded ${bills.length} bills from smart contract');
    } catch (e) { 
      print('[SplitBill] Load bills error: $e'); 
    }
    finally { setState(() => _isLoadingBills = false); }
  }

  Future<void> _loadRegisteredUsers() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').limit(50).get();
      final users = <RegisteredUser>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final walletAddress = data['wallet_address'] ?? data['walletAddress'];
        if (walletAddress != null && walletAddress.toString().isNotEmpty && walletAddress.toString().toLowerCase() != (_walletAddress ?? '').toLowerCase()) {
          users.add(RegisteredUser(uid: doc.id, name: data['name'] ?? 'Unknown', email: data['email'] ?? '', walletAddress: walletAddress.toString(), photoURL: data['photoURL']));
        }
      }
      users.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _registeredUsers = users);
    } catch (_) {}
  }

  void _searchUsers(String query) {
    if (query.isEmpty) { setState(() => _searchResults = []); return; }
    final queryLower = query.toLowerCase();
    setState(() => _searchResults = _registeredUsers.where((u) => u.name.toLowerCase().contains(queryLower) || u.email.toLowerCase().contains(queryLower)).take(10).toList());
  }

  void _addParticipantFromUser(RegisteredUser user) {
    if (_participants.any((p) => p.address.toLowerCase() == user.walletAddress.toLowerCase())) { _showError('Already added'); return; }
    setState(() { _participants.add(SplitParticipant(address: user.walletAddress, name: user.name, amount: BigInt.zero, paid: false)); _showUserPicker = false; _searchController.clear(); _searchResults = []; _recalculateShares(); });
  }

  void _addParticipant() {
    final address = _participantController.text.trim();
    if (address.isEmpty || !address.startsWith('0x') || address.length != 42) { _showError('Invalid wallet address'); return; }
    if (_participants.any((p) => p.address.toLowerCase() == address.toLowerCase())) { _showError('Already added'); return; }
    setState(() { _participants.add(SplitParticipant(address: address, amount: BigInt.zero, paid: false)); _participantController.clear(); _recalculateShares(); });
  }

  void _removeParticipant(int index) { setState(() { _participants.removeAt(index); _recalculateShares(); }); }

  void _recalculateShares() {
    if (_participants.isEmpty) return;
    final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;
    if (totalAmount <= 0) return;
    final totalWei = BigInt.from(totalAmount * 1e18);
    final sharePerPerson = totalWei ~/ BigInt.from(_participants.length);
    for (var p in _participants) p.amount = sharePerPerson;
    setState(() {});
  }

  String _getTokenAddress(String token) {
    switch (token) { case 'LSK': return lskTokenAddress; case 'POL': return polTokenAddress; default: return lskTokenAddress; }
  }

  // Part 2 continues in next edit...
  
  static const String _erc20Abi = '''[{"inputs": [{"name": "account", "type": "address"}], "name": "balanceOf", "outputs": [{"name": "", "type": "uint256"}], "stateMutability": "view", "type": "function"},{"inputs": [{"name": "to", "type": "address"}, {"name": "amount", "type": "uint256"}], "name": "transfer", "outputs": [{"name": "", "type": "bool"}], "stateMutability": "nonpayable", "type": "function"}]''';
  String _shortenAddress(String address) => address.length <= 12 ? address : '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: errorRed, behavior: SnackBarBehavior.floating));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: successGreen, behavior: SnackBarBehavior.floating));
  String _formatDeadline(DateTime d) { final diff = d.difference(DateTime.now()); if (diff.isNegative) return 'Expired'; if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h left'; if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m left'; return '${diff.inMinutes}m left'; }
  Color _getDeadlineColor(DateTime d) { final diff = d.difference(DateTime.now()); if (diff.isNegative || diff.inHours < 2) return errorRed; if (diff.inHours < 12) return warningOrange; return successGreen; }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size.width / 375;
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor, elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: textPrimary), onPressed: () => Navigator.pop(context)),
        title: Text('Split Bill', style: GoogleFonts.poppins(color: textPrimary, fontSize: 18 * s, fontWeight: FontWeight.w600)),
        centerTitle: true,
        bottom: TabBar(controller: _tabController, labelColor: primaryBlue, unselectedLabelColor: textSecondary, indicatorColor: primaryBlue, indicatorWeight: 3, tabs: const [Tab(text: 'Create'), Tab(text: 'Activity')]),
      ),
      body: TabBarView(controller: _tabController, children: [_buildCreateTab(s), _buildActivityTab(s)]),
    );
  }

  Widget _buildCreateTab(double s) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16 * s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Request Payment In', style: GoogleFonts.poppins(color: textPrimary, fontSize: 14 * s, fontWeight: FontWeight.w600)),
        SizedBox(height: 12 * s),
        Row(children: ['LSK', 'POL', 'ETH'].map((t) => Expanded(child: Padding(padding: EdgeInsets.only(right: t != 'ETH' ? 12 * s : 0), child: _buildTokenOption(t, s)))).toList()),
        SizedBox(height: 24 * s),
        Text('Bill Name', style: GoogleFonts.poppins(color: textPrimary, fontSize: 14 * s, fontWeight: FontWeight.w600)),
        SizedBox(height: 8 * s),
        Container(decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12 * s), border: Border.all(color: Colors.grey.shade200)),
          child: TextField(controller: _descriptionController, style: GoogleFonts.poppins(color: textPrimary, fontSize: 16 * s),
            decoration: InputDecoration(hintText: 'e.g., Dinner at Restaurant', hintStyle: GoogleFonts.poppins(color: textSecondary.withOpacity(0.5)), border: InputBorder.none, contentPadding: EdgeInsets.all(16 * s)))),
        SizedBox(height: 20 * s),
        Text('Total Amount', style: GoogleFonts.poppins(color: textPrimary, fontSize: 14 * s, fontWeight: FontWeight.w600)),
        SizedBox(height: 8 * s),
        Container(decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12 * s), border: Border.all(color: Colors.grey.shade200)),
          child: TextField(controller: _totalAmountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => _recalculateShares(),
            style: GoogleFonts.poppins(color: textPrimary, fontSize: 16 * s),
            decoration: InputDecoration(hintText: '0.00', hintStyle: GoogleFonts.poppins(color: textSecondary.withOpacity(0.5)), border: InputBorder.none, contentPadding: EdgeInsets.all(16 * s)))),
        SizedBox(height: 20 * s),
        Text('Payment Deadline', style: GoogleFonts.poppins(color: textPrimary, fontSize: 14 * s, fontWeight: FontWeight.w600)),
        SizedBox(height: 8 * s),
        GestureDetector(onTap: _selectDeadline, child: Container(padding: EdgeInsets.all(16 * s), decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12 * s), border: Border.all(color: Colors.grey.shade200)),
          child: Row(children: [Icon(Icons.schedule, color: _getDeadlineColor(_selectedDeadline)), SizedBox(width: 12 * s), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${_selectedDeadline.day}/${_selectedDeadline.month}/${_selectedDeadline.year} ${_selectedDeadline.hour.toString().padLeft(2, '0')}:${_selectedDeadline.minute.toString().padLeft(2, '0')}', style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w500)), Text(_formatDeadline(_selectedDeadline), style: GoogleFonts.poppins(color: _getDeadlineColor(_selectedDeadline), fontSize: 12 * s))])), Icon(Icons.edit_calendar, color: textSecondary)]))),
        SizedBox(height: 24 * s),
        Text('Participants', style: GoogleFonts.poppins(color: textPrimary, fontSize: 14 * s, fontWeight: FontWeight.w600)),
        SizedBox(height: 12 * s),
        GestureDetector(onTap: () { _loadRegisteredUsers(); setState(() => _showUserPicker = true); },
          child: Container(padding: EdgeInsets.symmetric(vertical: 14 * s), decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12 * s), border: Border.all(color: primaryBlue)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.person_search, color: primaryBlue), SizedBox(width: 8 * s), Text('Search Registered Users', style: GoogleFonts.poppins(color: primaryBlue, fontWeight: FontWeight.w600))]))),
        SizedBox(height: 12 * s),
        Text('Or enter wallet address:', style: GoogleFonts.poppins(color: textSecondary, fontSize: 12 * s)),
        SizedBox(height: 8 * s),
        Row(children: [
          Expanded(child: Container(decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12 * s), border: Border.all(color: Colors.grey.shade200)),
            child: TextField(controller: _participantController, style: GoogleFonts.sourceCodePro(color: textPrimary, fontSize: 12 * s), decoration: InputDecoration(hintText: '0x...', border: InputBorder.none, contentPadding: EdgeInsets.all(14 * s))))),
          SizedBox(width: 8 * s),
          GestureDetector(onTap: _addParticipant, child: Container(padding: EdgeInsets.all(14 * s), decoration: BoxDecoration(color: primaryBlue, borderRadius: BorderRadius.circular(12 * s)), child: const Icon(Icons.add, color: Colors.white)))
        ]),
        if (_showUserPicker) ...[SizedBox(height: 12 * s), _buildUserPicker(s)],
        if (_participants.isNotEmpty) ...[SizedBox(height: 16 * s), Text('Added (${_participants.length})', style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w600)), SizedBox(height: 8 * s), ..._participants.asMap().entries.map((e) => _buildParticipantItem(e.value, e.key, s))],
        SizedBox(height: 24 * s),
        SizedBox(width: double.infinity, height: 52 * s, child: ElevatedButton(onPressed: _isCreating ? null : _createSplitBill, style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * s))),
          child: _isCreating ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text('Create Split Bill', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.w600)))),
        SizedBox(height: 100 * s),
      ]),
    );
  }

  Widget _buildTokenOption(String token, double s) {
    final isSelected = _selectedToken == token;
    final balance = _formatBalance(_tokenBalances[token] ?? BigInt.zero);
    return GestureDetector(onTap: () => setState(() => _selectedToken = token),
      child: Container(padding: EdgeInsets.symmetric(vertical: 16 * s), decoration: BoxDecoration(color: isSelected ? primaryBlue : cardColor, borderRadius: BorderRadius.circular(12 * s), border: Border.all(color: isSelected ? primaryBlue : Colors.grey.shade300, width: isSelected ? 2 : 1)),
        child: Column(children: [Text(token, style: GoogleFonts.poppins(color: isSelected ? Colors.white : textPrimary, fontSize: 16 * s, fontWeight: FontWeight.w600)), SizedBox(height: 4 * s), Text(balance, style: GoogleFonts.poppins(color: isSelected ? Colors.white70 : textSecondary, fontSize: 12 * s))])));
  }

  Widget _buildUserPicker(double s) {
    return Container(padding: EdgeInsets.all(16 * s), decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16 * s), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Select User', style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w600)), GestureDetector(onTap: () => setState(() => _showUserPicker = false), child: Icon(Icons.close, color: textSecondary))]),
        SizedBox(height: 12 * s),
        TextField(controller: _searchController, onChanged: _searchUsers, decoration: InputDecoration(hintText: 'Search by name...', prefixIcon: Icon(Icons.search, color: textSecondary), filled: true, fillColor: backgroundColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12 * s), borderSide: BorderSide.none))),
        SizedBox(height: 12 * s),
        ConstrainedBox(constraints: BoxConstraints(maxHeight: 200 * s), child: _searchResults.isEmpty 
          ? Center(child: Padding(padding: EdgeInsets.all(20 * s), child: Text('Type to search users...', style: GoogleFonts.poppins(color: textSecondary, fontSize: 13 * s))))
          : ListView(shrinkWrap: true, children: _searchResults.map((u) => _buildUserItem(u, s)).toList())),
      ]));
  }

  Widget _buildUserItem(RegisteredUser user, double s) {
    final isAdded = _participants.any((p) => p.address.toLowerCase() == user.walletAddress.toLowerCase());
    return GestureDetector(onTap: isAdded ? null : () => _addParticipantFromUser(user),
      child: Container(margin: EdgeInsets.only(bottom: 8 * s), padding: EdgeInsets.all(12 * s), decoration: BoxDecoration(color: isAdded ? primaryBlue.withOpacity(0.1) : backgroundColor, borderRadius: BorderRadius.circular(10 * s)),
        child: Row(children: [CircleAvatar(radius: 18 * s, backgroundColor: primaryBlue.withOpacity(0.2), child: Text(user.name[0].toUpperCase(), style: GoogleFonts.poppins(color: primaryBlue, fontWeight: FontWeight.w600))), SizedBox(width: 12 * s), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user.name, style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w500, fontSize: 13 * s)), Text(_shortenAddress(user.walletAddress), style: GoogleFonts.sourceCodePro(color: textSecondary, fontSize: 11 * s))])), Icon(isAdded ? Icons.check_circle : Icons.add_circle_outline, color: isAdded ? primaryBlue : textSecondary)])));
  }

  Widget _buildParticipantItem(SplitParticipant p, int index, double s) {
    return Container(margin: EdgeInsets.only(bottom: 8 * s), padding: EdgeInsets.all(12 * s), decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12 * s), border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [CircleAvatar(radius: 18 * s, backgroundColor: primaryBlue.withOpacity(0.15), child: Text((p.name ?? '?')[0].toUpperCase(), style: GoogleFonts.poppins(color: primaryBlue, fontWeight: FontWeight.w600))), SizedBox(width: 12 * s), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (p.name != null) Text(p.name!, style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w500, fontSize: 13 * s)), Text(_shortenAddress(p.address), style: GoogleFonts.sourceCodePro(color: textSecondary, fontSize: 11 * s))])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${_formatBalance(p.amount)} $_selectedToken', style: GoogleFonts.poppins(color: primaryBlue, fontWeight: FontWeight.w600, fontSize: 13 * s)), Text('Share', style: GoogleFonts.poppins(color: textSecondary, fontSize: 10 * s))]), SizedBox(width: 8 * s), GestureDetector(onTap: () => _removeParticipant(index), child: Icon(Icons.remove_circle, color: errorRed))]));
  }

  Future<void> _selectDeadline() async {
    // Minimum deadline - for testing set to 2 minutes, for production use 2 hours
    final minDate = DateTime.now().add(const Duration(minutes: 2)); // TESTING MODE
    final initialDate = _selectedDeadline.isBefore(minDate) ? minDate : _selectedDeadline;
    
    final date = await showDatePicker(context: context, initialDate: initialDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)), builder: (c, w) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: primaryBlue)), child: w!));
    if (date != null) {
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initialDate), builder: (c, w) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: primaryBlue)), child: w!));
      if (time != null) {
        var newDeadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        // Ensure deadline is at least 2 minutes from now (testing mode)
        if (newDeadline.isBefore(minDate)) {
          newDeadline = minDate;
          _showError('Deadline adjusted to minimum 2 minutes from now');
        }
        setState(() => _selectedDeadline = newDeadline);
      }
    }
  }

  Future<void> _createSplitBill() async {
    if (_walletAddress == null || _privateKey == null) { _showError('Wallet not connected'); return; }
    final description = _descriptionController.text.trim();
    if (description.isEmpty) { _showError('Enter bill name'); return; }
    final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;
    if (totalAmount <= 0) { _showError('Enter valid amount'); return; }
    if (_participants.isEmpty) { _showError('Add participants'); return; }
    
    // Validate deadline - TESTING MODE: 2 minutes minimum (production: 1 hour)
    final minDeadline = DateTime.now().add(const Duration(minutes: 2));
    if (_selectedDeadline.isBefore(minDeadline)) {
      _showError('Deadline must be at least 2 minutes from now');
      return;
    }
    
    setState(() => _isCreating = true);
    try {
      final totalWei = BigInt.from(totalAmount * 1e18);
      final sharePerPerson = totalWei ~/ BigInt.from(_participants.length);
      
      // Prepare participant data for smart contract (only invited participants, NOT creator)
      final participantAddresses = _participants.map((p) => p.address).toList();
      // Note: CanmaSplitBillV5 calculates share per participant automatically from totalAmount
      
      // Create credentials from private key
      final credentials = web3.EthPrivateKey.fromHex(_privateKey!);
      
      // Get token address for selected token
      final tokenAddress = _getTokenAddress(_selectedToken);
      
      // Write to smart contract
      print('[SplitBill] Creating bill on smart contract...');
      print('[SplitBill] Description: $description');
      print('[SplitBill] Token: $tokenAddress ($_selectedToken)');
      print('[SplitBill] Participants: ${participantAddresses.length}');
      print('[SplitBill] Share per person: ${_formatBalance(sharePerPerson)} $_selectedToken');
      
      final txHash = await _contractService.createBill(
        credentials: credentials,
        description: description,
        tokenAddress: tokenAddress,
        participantAddresses: participantAddresses,
        totalAmount: totalWei,
        deadline: _selectedDeadline,
      );
      
      print('[SplitBill] Bill created! TX: $txHash');
      
      // Send notification to all participants
      for (final participant in _participants) {
        try {
          await _notificationService.createNotification(
            userId: participant.address.toLowerCase(),
            type: NotificationType.splitBillInvite,
            title: 'Split Bill Invitation',
            body: 'You\'ve been invited to split "$description" - ${_formatBalance(sharePerPerson)} $_selectedToken',
            data: {'txHash': txHash, 'amount': sharePerPerson.toString(), 'token': _selectedToken},
          );
          print('[SplitBill] Notification sent to ${participant.address}');
        } catch (e) {
          print('[SplitBill] Failed to send notification to ${participant.address}: $e');
        }
      }
      
      _showSuccess('Split bill created on blockchain!');
      _descriptionController.clear(); _totalAmountController.clear();
      setState(() { _participants.clear(); _selectedDeadline = DateTime.now().add(const Duration(hours: 24)); });
      await _loadAllBills();
      _tabController.animateTo(1);
    } catch (e) { 
      print('[SplitBill] Create error: $e');
      _showError('Failed: $e'); 
    }
    finally { setState(() => _isCreating = false); }
  }

  Widget _buildActivityTab(double s) {
    return RefreshIndicator(onRefresh: _loadAllBills, color: primaryBlue,
      child: _isLoadingBills ? Center(child: CircularProgressIndicator(color: primaryBlue)) : _allBills.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: EdgeInsets.all(24 * s), decoration: BoxDecoration(color: primaryBlue.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.receipt_long, color: primaryBlue, size: 48 * s)), SizedBox(height: 16 * s), Text('No bills yet', style: GoogleFonts.poppins(color: textPrimary, fontSize: 16 * s, fontWeight: FontWeight.w600))]))
        : ListView.builder(padding: EdgeInsets.all(16 * s), itemCount: _allBills.length, itemBuilder: (c, i) => _buildBillCard(_allBills[i], s)));
  }

  Widget _buildBillCard(ContractBill bill, double s) {
    final isCreator = bill.creator.toLowerCase() == (_walletAddress ?? '').toLowerCase();
    final myParticipant = isCreator ? null : bill.participants.firstWhere((p) => p.wallet.toLowerCase() == (_walletAddress ?? '').toLowerCase(), orElse: () => ContractParticipant(wallet: '', amountDue: BigInt.zero, amountPaid: BigInt.zero, hasPaid: false, hasClaimedRefund: false, requestedToken: 'LSK'));
    final token = bill.requestedToken;
    final balance = _tokenBalances[token] ?? BigInt.zero;
    final hasInsufficientBalance = myParticipant != null && !myParticipant.hasPaid && balance < myParticipant.amountDue;
    
    return Container(margin: EdgeInsets.only(bottom: 16 * s), decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16 * s), border: bill.isComplete ? Border.all(color: successGreen.withOpacity(0.5), width: 2) : null, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(children: [
        if (!isCreator && myParticipant != null && myParticipant.wallet.isNotEmpty) Container(padding: EdgeInsets.all(16 * s), decoration: BoxDecoration(color: myParticipant.hasPaid ? successGreen.withOpacity(0.1) : backgroundColor, borderRadius: BorderRadius.vertical(top: Radius.circular(16 * s))),
          child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Your Share', style: GoogleFonts.poppins(color: textSecondary, fontSize: 12 * s)), Text('${_formatBalance(myParticipant.amountDue)} $token', style: GoogleFonts.poppins(color: textPrimary, fontSize: 20 * s, fontWeight: FontWeight.w700))])),
            // Show different buttons based on bill state
            if (bill.isExpired && myParticipant.hasPaid && !myParticipant.hasClaimedRefund)
              ElevatedButton(onPressed: _claimingRefundBillId != null ? null : () => _claimRefund(bill), style: ElevatedButton.styleFrom(backgroundColor: warningOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * s)), padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s)),
                child: _claimingRefundBillId == bill.billId ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text('Claim Refund', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)))
            else if (bill.isExpired && myParticipant.hasClaimedRefund)
              Container(padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s), decoration: BoxDecoration(color: textSecondary, borderRadius: BorderRadius.circular(8 * s)), child: Text('Refunded', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)))
            else if (myParticipant.hasPaid)
              Container(padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s), decoration: BoxDecoration(color: successGreen, borderRadius: BorderRadius.circular(8 * s)), child: Text('Paid', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)))
            else if (!bill.isExpired)
              ElevatedButton(onPressed: _payingBillId != null ? null : () => _payShare(bill), style: ElevatedButton.styleFrom(backgroundColor: successGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * s)), padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 12 * s)),
                child: _payingBillId == bill.billId ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text('Pay Now', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)))
            else
              Container(padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s), decoration: BoxDecoration(color: errorRed, borderRadius: BorderRadius.circular(8 * s)), child: Text('Expired', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)))])),
        Padding(padding: EdgeInsets.all(16 * s), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(padding: EdgeInsets.all(10 * s), decoration: BoxDecoration(color: (isCreator ? primaryBlue : warningOrange).withOpacity(0.1), borderRadius: BorderRadius.circular(10 * s)), child: Icon(isCreator ? Icons.receipt : Icons.mail, color: isCreator ? primaryBlue : warningOrange, size: 20 * s)), SizedBox(width: 12 * s), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(bill.description, style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14 * s)), Text(isCreator ? 'Created by you' : 'Invited', style: GoogleFonts.poppins(color: textSecondary, fontSize: 11 * s))])), Container(padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s), decoration: BoxDecoration(color: (bill.isComplete ? successGreen : warningOrange).withOpacity(0.1), borderRadius: BorderRadius.circular(20 * s)), child: Text(bill.isComplete ? 'Complete' : '${bill.paidCount}/${bill.participantCount}', style: GoogleFonts.poppins(color: bill.isComplete ? successGreen : warningOrange, fontSize: 11 * s, fontWeight: FontWeight.w600)))]),
          if (!bill.isComplete) ...[SizedBox(height: 12 * s), Container(padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s), decoration: BoxDecoration(color: _getDeadlineColor(bill.deadline).withOpacity(0.1), borderRadius: BorderRadius.circular(8 * s)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.timer, color: _getDeadlineColor(bill.deadline), size: 14 * s), SizedBox(width: 6 * s), Text(_formatDeadline(bill.deadline), style: GoogleFonts.poppins(color: _getDeadlineColor(bill.deadline), fontSize: 11 * s, fontWeight: FontWeight.w600))]))],
          SizedBox(height: 12 * s),
          Row(children: [
            Expanded(child: Container(padding: EdgeInsets.all(10 * s), decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(10 * s)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Total', style: GoogleFonts.poppins(color: textSecondary, fontSize: 11 * s)), Text('${_formatBalance(bill.totalAmount)} $token', style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 13 * s))]))),
            SizedBox(width: 12 * s),
            Expanded(child: Container(padding: EdgeInsets.all(10 * s), decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(10 * s)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Collected', style: GoogleFonts.poppins(color: textSecondary, fontSize: 11 * s)), Text('${_formatBalance(bill.collectedAmount)} $token', style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 13 * s))]))),
          ]),
          // Show participant list for creator
          if (isCreator && bill.participants.isNotEmpty) ...[
            SizedBox(height: 16 * s),
            Text('Participants', style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 13 * s)),
            SizedBox(height: 8 * s),
            ...bill.participants.map((p) => Container(
              margin: EdgeInsets.only(bottom: 8 * s),
              padding: EdgeInsets.all(10 * s),
              decoration: BoxDecoration(color: p.hasPaid ? successGreen.withOpacity(0.1) : backgroundColor, borderRadius: BorderRadius.circular(8 * s), border: Border.all(color: p.hasPaid ? successGreen.withOpacity(0.3) : Colors.transparent)),
              child: Row(children: [
                Container(padding: EdgeInsets.all(6 * s), decoration: BoxDecoration(color: (p.hasPaid ? successGreen : warningOrange).withOpacity(0.2), shape: BoxShape.circle), child: Icon(p.hasPaid ? Icons.check : Icons.hourglass_empty, color: p.hasPaid ? successGreen : warningOrange, size: 14 * s)),
                SizedBox(width: 10 * s),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_shortenAddress(p.wallet), style: GoogleFonts.poppins(color: textPrimary, fontSize: 12 * s, fontWeight: FontWeight.w500)),
                  Text('${_formatBalance(p.amountDue)} $token', style: GoogleFonts.poppins(color: textSecondary, fontSize: 11 * s)),
                ])),
                Container(padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s), decoration: BoxDecoration(color: p.hasPaid ? successGreen : warningOrange, borderRadius: BorderRadius.circular(12 * s)), child: Text(p.hasPaid ? 'Paid' : 'Pending', style: GoogleFonts.poppins(color: Colors.white, fontSize: 10 * s, fontWeight: FontWeight.w600))),
              ]),
            )).toList(),
          ],
        ])),
        if (hasInsufficientBalance) Container(width: double.infinity, margin: EdgeInsets.fromLTRB(16 * s, 0, 16 * s, 16 * s), padding: EdgeInsets.symmetric(vertical: 12 * s), decoration: BoxDecoration(color: errorRed, borderRadius: BorderRadius.circular(10 * s)), child: Text('Insufficient balance. Need ${_formatBalance(myParticipant!.amountDue)} $token', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13 * s, fontWeight: FontWeight.w500))),
      ]));
  }

  Future<void> _payShare(ContractBill bill) async {
    if (_walletAddress == null || _privateKey == null) { _showError('Wallet not connected'); return; }
    final myParticipant = bill.participants.firstWhere((p) => p.wallet.toLowerCase() == _walletAddress!.toLowerCase(), orElse: () => ContractParticipant(wallet: '', amountDue: BigInt.zero, amountPaid: BigInt.zero, hasPaid: false, hasClaimedRefund: false, requestedToken: 'LSK'));
    if (myParticipant.wallet.isEmpty || myParticipant.hasPaid) { _showError('Already paid'); return; }
    final token = bill.requestedToken;
    final balance = _tokenBalances[token] ?? BigInt.zero;
    if (balance < myParticipant.amountDue) { _showError('Insufficient balance'); return; }
    
    setState(() => _payingBillId = bill.billId);
    try {
      final credentials = web3.EthPrivateKey.fromHex(_privateKey!);
      
      // Use smart contract payShare function
      final txHash = await _contractService.payShare(
        credentials: credentials,
        billId: bill.billId,
        tokenAddress: _getTokenAddress(token),
        amount: myParticipant.amountDue,
      );
      
      print('[SplitBill] Payment TX: $txHash');
      
      // Send notification to creator
      try {
        await _notificationService.createNotification(
          userId: bill.creator.toLowerCase(),
          type: NotificationType.splitBillPayment,
          title: 'Payment Received',
          body: 'Payment for "${bill.description}" - ${_formatBalance(myParticipant.amountDue)} $token',
          data: {'billId': bill.billId, 'txHash': txHash},
        );
      } catch (e) {
        print('[SplitBill] Notification error (ignored): $e');
      }
      
      await Future.wait([_loadAllTokenBalances(), _loadAllBills()]);
      _showSuccess('Payment successful!');
    } catch (e) { 
      print('[SplitBill] Payment error: $e');
      _showError('Payment failed: $e'); 
    }
    finally { setState(() => _payingBillId = null); }
  }

  Future<void> _claimRefund(ContractBill bill) async {
    if (_walletAddress == null || _privateKey == null) { _showError('Wallet not connected'); return; }
    
    final myParticipant = bill.participants.firstWhere(
      (p) => p.wallet.toLowerCase() == _walletAddress!.toLowerCase(),
      orElse: () => ContractParticipant(wallet: '', amountDue: BigInt.zero, amountPaid: BigInt.zero, hasPaid: false, hasClaimedRefund: false, requestedToken: 'LSK'),
    );
    
    if (myParticipant.wallet.isEmpty) { _showError('You are not a participant'); return; }
    if (!myParticipant.hasPaid) { _showError('You have not paid yet'); return; }
    if (myParticipant.hasClaimedRefund) { _showError('Already claimed refund'); return; }
    
    setState(() => _claimingRefundBillId = bill.billId);
    try {
      final credentials = web3.EthPrivateKey.fromHex(_privateKey!);
      
      final txHash = await _contractService.claimRefund(
        credentials: credentials,
        billId: bill.billId,
      );
      
      print('[SplitBill] Refund claimed TX: $txHash');
      
      await Future.wait([_loadAllTokenBalances(), _loadAllBills()]);
      _showSuccess('Refund claimed successfully!');
    } catch (e) { 
      print('[SplitBill] Claim refund error: $e');
      _showError('Claim refund failed: $e'); 
    }
    finally { setState(() => _claimingRefundBillId = null); }
  }
}

class RegisteredUser { final String uid; final String name; final String email; final String walletAddress; final String? photoURL; RegisteredUser({required this.uid, required this.name, required this.email, required this.walletAddress, this.photoURL}); }
class SplitParticipant { final String address; final String? name; BigInt amount; bool paid; SplitParticipant({required this.address, this.name, required this.amount, required this.paid}); }
