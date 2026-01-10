import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import '../config/env.dart';

/// Data models for CanmaSplitBillV5 smart contract
class ContractBill {
  final String billId;
  final String creator;
  final String description;
  final BigInt totalAmount;
  final BigInt collectedAmount;
  final DateTime createdAt;
  final DateTime deadline;
  final int status; // 0=Active, 1=Completed, 2=Cancelled, 3=Expired
  final int participantCount;
  final int paidCount;
  final String requestedToken;
  final List<ContractParticipant> participants;

  ContractBill({
    required this.billId,
    required this.creator,
    required this.description,
    required this.totalAmount,
    required this.collectedAmount,
    required this.createdAt,
    required this.deadline,
    required this.status,
    required this.participantCount,
    required this.paidCount,
    required this.requestedToken,
    required this.participants,
  });

  bool get isComplete => status == 1;
  bool get isCancelled => status == 2;
  bool get isExpired => status == 3 || (status == 0 && DateTime.now().isAfter(deadline));
  bool get isActive => status == 0 && DateTime.now().isBefore(deadline);
}

class ContractParticipant {
  final String wallet;
  final BigInt amountDue;
  final BigInt amountPaid;
  final bool hasPaid;
  final bool hasClaimedRefund;
  final String requestedToken;

  ContractParticipant({
    required this.wallet,
    required this.amountDue,
    required this.amountPaid,
    required this.hasPaid,
    required this.hasClaimedRefund,
    this.requestedToken = 'LSK',
  });
}

/// Service for interacting with CanmaSplitBillV5 smart contract
class CanmaSplitBillV5Service {
  static const String _contractAddress = '0x998C402E2d5A55EC599C84B7B1C446732b29E5F3'; // Testing version with 1 min deadline
  
  Web3Client? _web3Client;
  http.Client? _httpClient;
  DeployedContract? _contract;
  
  // Contract ABI for CanmaSplitBillV5
  static const String _abi = '''[
    {
      "inputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "name": "getBill",
      "outputs": [
        {"components": [
          {"internalType": "bytes32", "name": "billId", "type": "bytes32"},
          {"internalType": "address", "name": "creator", "type": "address"},
          {"internalType": "address", "name": "paymentToken", "type": "address"},
          {"internalType": "uint256", "name": "totalAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "amountPerParticipant", "type": "uint256"},
          {"internalType": "uint256", "name": "deadline", "type": "uint256"},
          {"internalType": "uint256", "name": "createdAt", "type": "uint256"},
          {"internalType": "uint256", "name": "completedAt", "type": "uint256"},
          {"internalType": "uint256", "name": "participantCount", "type": "uint256"},
          {"internalType": "uint256", "name": "paidCount", "type": "uint256"},
          {"internalType": "uint256", "name": "totalCollected", "type": "uint256"},
          {"internalType": "uint8", "name": "status", "type": "uint8"},
          {"internalType": "string", "name": "description", "type": "string"}
        ], "internalType": "struct CanmaSplitBillV5.Bill", "name": "", "type": "tuple"}
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "name": "getBillParticipants",
      "outputs": [
        {"components": [
          {"internalType": "address", "name": "wallet", "type": "address"},
          {"internalType": "uint256", "name": "amountDue", "type": "uint256"},
          {"internalType": "uint256", "name": "amountPaid", "type": "uint256"},
          {"internalType": "bool", "name": "hasPaid", "type": "bool"},
          {"internalType": "bool", "name": "hasClaimedRefund", "type": "bool"}
        ], "internalType": "struct CanmaSplitBillV5.Participant[]", "name": "", "type": "tuple[]"}
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "address", "name": "user", "type": "address"}],
      "name": "getUserCreatedBills",
      "outputs": [{"internalType": "bytes32[]", "name": "", "type": "bytes32[]"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "address", "name": "user", "type": "address"}],
      "name": "getUserParticipatingBills",
      "outputs": [{"internalType": "bytes32[]", "name": "", "type": "bytes32[]"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "name": "getBillStatus",
      "outputs": [{"internalType": "enum CanmaSplitBillV5.BillStatus", "name": "", "type": "uint8"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {"internalType": "address", "name": "paymentToken", "type": "address"},
        {"internalType": "uint256", "name": "totalAmount", "type": "uint256"},
        {"internalType": "uint256", "name": "deadline", "type": "uint256"},
        {"internalType": "address[]", "name": "participants", "type": "address[]"},
        {"internalType": "string", "name": "description", "type": "string"}
      ],
      "name": "createBill",
      "outputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "name": "payShare",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "name": "cancelBill",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "name": "claimRefund",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "address", "name": "", "type": "address"}],
      "name": "supportedTokens",
      "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "VERSION",
      "outputs": [{"internalType": "string", "name": "", "type": "string"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "feeReceiver",
      "outputs": [{"internalType": "address", "name": "", "type": "address"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "adminFeeBps",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "view",
      "type": "function"
    }
  ]''';

  // ERC20 ABI for approve
  static const String _erc20Abi = '''[
    {
      "inputs": [
        {"internalType": "address", "name": "spender", "type": "address"},
        {"internalType": "uint256", "name": "amount", "type": "uint256"}
      ],
      "name": "approve",
      "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {"internalType": "address", "name": "owner", "type": "address"},
        {"internalType": "address", "name": "spender", "type": "address"}
      ],
      "name": "allowance",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "view",
      "type": "function"
    }
  ]''';

  Future<void> init() async {
    if (_web3Client != null) return;
    
    _httpClient = http.Client();
    _web3Client = Web3Client(Env.liskRpcUrl, _httpClient!);
    _contract = DeployedContract(
      ContractAbi.fromJson(_abi, 'CanmaSplitBillV5'),
      EthereumAddress.fromHex(_contractAddress),
    );
    
    print('[CanmaSplitBillV5] Initialized at $_contractAddress');
    
    try {
      final versionResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('VERSION'),
        params: [],
      );
      print('[CanmaSplitBillV5] Version: ${versionResult[0]}');
      
      final feeResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('adminFeeBps'),
        params: [],
      );
      print('[CanmaSplitBillV5] Admin Fee: ${feeResult[0]} bps');
    } catch (e) {
      print('[CanmaSplitBillV5] Could not query contract state: $e');
    }
  }

  void dispose() {
    _web3Client?.dispose();
    _httpClient?.close();
  }

  /// Get all bills for a user (created + participating)
  Future<List<ContractBill>> getAllBillsForUser(String walletAddress) async {
    await init();
    
    final userAddress = EthereumAddress.fromHex(walletAddress);
    final bills = <ContractBill>[];
    final seenIds = <String>{};
    
    try {
      // Get bills created by user
      print('[CanmaSplitBillV5] Fetching created bills for: ${userAddress.hex}');
      final createdResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getUserCreatedBills'),
        params: [userAddress],
      );
      print('[CanmaSplitBillV5] Created result: $createdResult');
      final createdIds = (createdResult[0] as List).cast<dynamic>();
      print('[CanmaSplitBillV5] Found ${createdIds.length} created bills');
      
      for (final billIdBytes in createdIds) {
        final billId = _bytes32ToHex(billIdBytes);
        print('[CanmaSplitBillV5] Processing bill ID: $billId');
        if (!seenIds.contains(billId)) {
          seenIds.add(billId);
          final bill = await getBill(billId);
          print('[CanmaSplitBillV5] Bill fetched: ${bill != null}');
          if (bill != null) bills.add(bill);
        }
      }
      
      // Get bills user is participating in
      final participatingResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getUserParticipatingBills'),
        params: [userAddress],
      );
      final participatingIds = (participatingResult[0] as List).cast<dynamic>();
      print('[CanmaSplitBillV5] Found ${participatingIds.length} participating bills');
      
      for (final billIdBytes in participatingIds) {
        final billId = _bytes32ToHex(billIdBytes);
        if (!seenIds.contains(billId)) {
          seenIds.add(billId);
          final bill = await getBill(billId);
          if (bill != null) bills.add(bill);
        }
      }
      
      // Sort by created date descending
      bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      print('[CanmaSplitBillV5] Found ${bills.length} total bills for $walletAddress');
      return bills;
      
    } catch (e, stackTrace) {
      print('[CanmaSplitBillV5] Error getting bills: $e');
      print('[CanmaSplitBillV5] Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get a single bill by ID
  Future<ContractBill?> getBill(String billId) async {
    await init();
    
    try {
      final billIdBytes = _hexToBytes32(billId);
      print('[CanmaSplitBillV5] Getting bill: $billId');
      
      // Get bill data
      final billResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getBill'),
        params: [billIdBytes],
      );
      
      print('[CanmaSplitBillV5] Bill result length: ${billResult.length}');
      final billData = billResult[0] as List<dynamic>;
      print('[CanmaSplitBillV5] Bill data length: ${billData.length}');
      
      // CanmaSplitBillV5 Bill struct:
      // [0] billId, [1] creator, [2] paymentToken, [3] totalAmount,
      // [4] amountPerParticipant, [5] deadline, [6] createdAt, [7] completedAt,
      // [8] participantCount, [9] paidCount, [10] totalCollected, [11] status, [12] description
      
      // Check if bill exists (createdAt > 0)
      final createdAt = billData[6] as BigInt;
      print('[CanmaSplitBillV5] Bill createdAt: $createdAt');
      if (createdAt == BigInt.zero) {
        print('[CanmaSplitBillV5] Bill does not exist (createdAt = 0)');
        return null;
      }
      
      // Get token address and determine token name
      final tokenAddrRaw = (billData[2] as EthereumAddress).hex;
      final tokenAddr = tokenAddrRaw.toLowerCase();
      print('[CanmaSplitBillV5] Token address: $tokenAddr');
      
      String tokenName = 'UNKNOWN';
      // Token addresses on Lisk Sepolia
      if (tokenAddr == '0x4270a0c8676a10ab8cbe3e92bfd187d94c8f248e') {
        tokenName = 'LSK';
      } else if (tokenAddr == '0x292d54495d4c9af56d86fa6caf25591037ef80b3') {
        tokenName = 'ETH';
      } else if (tokenAddr == '0xee412e79eb7f565ec9e7c8a1b0a7ec27b63fbc5e') {
        tokenName = 'POL';
      }
      print('[CanmaSplitBillV5] Token name resolved: $tokenName');
      
      // Get participants
      final participantsResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getBillParticipants'),
        params: [billIdBytes],
      );
      
      final participantsData = participantsResult[0] as List<dynamic>;
      final participants = participantsData.map((p) {
        final pList = p as List<dynamic>;
        return ContractParticipant(
          wallet: (pList[0] as EthereumAddress).hex,
          amountDue: pList[1] as BigInt,
          amountPaid: pList[2] as BigInt,
          hasPaid: pList[3] as bool,
          hasClaimedRefund: pList[4] as bool,
          requestedToken: tokenName,
        );
      }).toList();
      
      // Get real-time status (handles auto-expire)
      final statusResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getBillStatus'),
        params: [billIdBytes],
      );
      final currentStatus = (statusResult[0] as BigInt).toInt();
      
      return ContractBill(
        billId: billId,
        creator: (billData[1] as EthereumAddress).hex,
        description: billData[12] as String,
        totalAmount: billData[3] as BigInt,
        collectedAmount: billData[10] as BigInt,
        createdAt: DateTime.fromMillisecondsSinceEpoch((billData[6] as BigInt).toInt() * 1000),
        deadline: DateTime.fromMillisecondsSinceEpoch((billData[5] as BigInt).toInt() * 1000),
        status: currentStatus,
        participantCount: (billData[8] as BigInt).toInt(),
        paidCount: (billData[9] as BigInt).toInt(),
        requestedToken: tokenName,
        participants: participants,
      );
      
    } catch (e, stackTrace) {
      print('[CanmaSplitBillV5] Error getting bill $billId: $e');
      print('[CanmaSplitBillV5] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Create a new bill
  /// Note: Creator does NOT pay - only participants pay
  Future<String> createBill({
    required Credentials credentials,
    required String description,
    required String tokenAddress,
    required List<String> participantAddresses,
    required BigInt totalAmount,
    required DateTime deadline,
  }) async {
    await init();
    
    print('[CanmaSplitBillV5] Creating bill...');
    print('[CanmaSplitBillV5]   Description: $description');
    print('[CanmaSplitBillV5]   Token: $tokenAddress');
    print('[CanmaSplitBillV5]   Total Amount: $totalAmount');
    print('[CanmaSplitBillV5]   Participants: ${participantAddresses.length}');
    print('[CanmaSplitBillV5]   Deadline: $deadline');
    
    final token = EthereumAddress.fromHex(tokenAddress.toLowerCase());
    final addresses = participantAddresses.map((a) => EthereumAddress.fromHex(a.toLowerCase())).toList();
    final deadlineTimestamp = BigInt.from(deadline.millisecondsSinceEpoch ~/ 1000);
    
    // Verify creator is not in participants list
    final creatorAddr = credentials.address.hex.toLowerCase();
    for (final addr in participantAddresses) {
      if (addr.toLowerCase() == creatorAddr) {
        throw Exception('Creator cannot be a participant');
      }
    }
    
    // Try to estimate gas first to catch errors
    try {
      final gasEstimate = await _web3Client!.estimateGas(
        sender: credentials.address,
        to: _contract!.address,
        data: _contract!.function('createBill').encodeCall([
          token,
          totalAmount,
          deadlineTimestamp,
          addresses,
          description,
        ]),
      );
      print('[CanmaSplitBillV5] Gas estimate: $gasEstimate');
    } catch (e) {
      print('[CanmaSplitBillV5] Gas estimate failed: $e');
      throw Exception('Contract call would fail: $e');
    }
    
    final tx = Transaction.callContract(
      contract: _contract!,
      function: _contract!.function('createBill'),
      parameters: [token, totalAmount, deadlineTimestamp, addresses, description],
      maxGas: 700000,
    );
    
    final txHash = await _web3Client!.sendTransaction(credentials, tx, chainId: 4202);
    print('[CanmaSplitBillV5] Create tx: $txHash');
    
    // Wait for confirmation and check status
    final receipt = await _waitForReceipt(txHash);
    if (receipt == null) {
      throw Exception('Transaction timeout - check explorer for status');
    }
    if (receipt.status == false) {
      throw Exception('Transaction reverted - bill creation failed. Check contract requirements.');
    }
    
    return txHash;
  }

  /// Pay share for a bill
  Future<String> payShare({
    required Credentials credentials,
    required String billId,
    required String tokenAddress,
    required BigInt amount,
  }) async {
    await init();
    
    print('[CanmaSplitBillV5] Paying share for bill: $billId');
    print('[CanmaSplitBillV5]   Token: $tokenAddress');
    print('[CanmaSplitBillV5]   Amount: $amount');
    
    // Step 1: Approve token spend
    await _approveToken(credentials, tokenAddress, amount * BigInt.from(2));
    
    // Wait for approval to be mined
    await Future.delayed(const Duration(seconds: 3));
    
    // Step 2: Pay share
    final billIdBytes = _hexToBytes32(billId);
    
    final tx = Transaction.callContract(
      contract: _contract!,
      function: _contract!.function('payShare'),
      parameters: [billIdBytes],
      maxGas: 300000,
    );
    
    final txHash = await _web3Client!.sendTransaction(credentials, tx, chainId: 4202);
    print('[CanmaSplitBillV5] Pay tx: $txHash');
    
    // Wait for confirmation
    final receipt = await _waitForReceipt(txHash);
    if (receipt?.status == false) {
      throw Exception('Payment transaction reverted');
    }
    
    return txHash;
  }

  /// Claim refund after deadline (pull-based)
  Future<String> claimRefund({
    required Credentials credentials,
    required String billId,
  }) async {
    await init();
    
    print('[CanmaSplitBillV5] Claiming refund for bill: $billId');
    
    final billIdBytes = _hexToBytes32(billId);
    
    final tx = Transaction.callContract(
      contract: _contract!,
      function: _contract!.function('claimRefund'),
      parameters: [billIdBytes],
      maxGas: 200000,
    );
    
    final txHash = await _web3Client!.sendTransaction(credentials, tx, chainId: 4202);
    print('[CanmaSplitBillV5] Refund tx: $txHash');
    
    final receipt = await _waitForReceipt(txHash);
    if (receipt?.status == false) {
      throw Exception('Refund transaction reverted');
    }
    
    return txHash;
  }

  /// Cancel a bill (creator only)
  Future<String> cancelBill({
    required Credentials credentials,
    required String billId,
  }) async {
    await init();
    
    print('[CanmaSplitBillV5] Cancelling bill: $billId');
    
    final billIdBytes = _hexToBytes32(billId);
    
    final tx = Transaction.callContract(
      contract: _contract!,
      function: _contract!.function('cancelBill'),
      parameters: [billIdBytes],
      maxGas: 300000,
    );
    
    final txHash = await _web3Client!.sendTransaction(credentials, tx, chainId: 4202);
    print('[CanmaSplitBillV5] Cancel tx: $txHash');
    
    final receipt = await _waitForReceipt(txHash);
    if (receipt?.status == false) {
      throw Exception('Cancel transaction reverted');
    }
    
    return txHash;
  }

  Future<void> _approveToken(Credentials credentials, String tokenAddress, BigInt amount) async {
    print('[CanmaSplitBillV5] Approving token: $tokenAddress');
    
    final tokenContract = DeployedContract(
      ContractAbi.fromJson(_erc20Abi, 'ERC20'),
      EthereumAddress.fromHex(tokenAddress),
    );
    
    final tx = Transaction.callContract(
      contract: tokenContract,
      function: tokenContract.function('approve'),
      parameters: [EthereumAddress.fromHex(_contractAddress), amount],
      maxGas: 100000,
    );
    
    final txHash = await _web3Client!.sendTransaction(credentials, tx, chainId: 4202);
    print('[CanmaSplitBillV5] Approve tx: $txHash');
    
    await _waitForReceipt(txHash);
  }

  Future<TransactionReceipt?> _waitForReceipt(String txHash) async {
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final receipt = await _web3Client!.getTransactionReceipt(txHash);
      if (receipt != null) {
        print('[CanmaSplitBillV5] Receipt received, status: ${receipt.status}');
        return receipt;
      }
    }
    print('[CanmaSplitBillV5] Timeout waiting for receipt');
    return null;
  }

  // Helper: Convert hex string to bytes32
  Uint8List _hexToBytes32(String hex) {
    final cleanHex = hex.startsWith('0x') ? hex.substring(2) : hex;
    final bytes = <int>[];
    for (int i = 0; i < cleanHex.length; i += 2) {
      bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }
    // Pad to 32 bytes
    while (bytes.length < 32) {
      bytes.insert(0, 0);
    }
    return Uint8List.fromList(bytes);
  }

  // Helper: Convert bytes32 to hex string
  String _bytes32ToHex(dynamic bytes) {
    print('[CanmaSplitBillV5] _bytes32ToHex input type: ${bytes.runtimeType}, value: $bytes');
    if (bytes is Uint8List) {
      return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    }
    if (bytes is List<int>) {
      return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    }
    if (bytes is List) {
      try {
        final intList = bytes.cast<int>();
        return '0x${intList.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      } catch (e) {
        print('[CanmaSplitBillV5] Failed to cast to int list: $e');
      }
    }
    // If it's already a hex string or BigInt
    final str = bytes.toString();
    if (str.startsWith('0x')) return str;
    return '0x$str';
  }
}
