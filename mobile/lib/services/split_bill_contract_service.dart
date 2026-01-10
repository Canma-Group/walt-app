import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import '../config/env.dart';

/// Data models for smart contract
class ContractBill {
  final String billId;
  final String creator;
  final String description;
  final BigInt totalAmount;
  final BigInt collectedAmount;
  final DateTime createdAt;
  final DateTime deadline;
  final int status; // 0=Active, 1=Completed, 2=Cancelled
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
  bool get isActive => status == 0;
}

class ContractParticipant {
  final String wallet;
  final BigInt amountDue;
  final BigInt amountPaid;
  final int status; // 0=Pending, 1=Paid (contract), 3=Paid (Firestore)
  final DateTime? paidAt;
  final String requestedToken;

  ContractParticipant({
    required this.wallet,
    required this.amountDue,
    required this.amountPaid,
    required this.status,
    this.paidAt,
    this.requestedToken = 'LSK',
  });

  bool get hasPaid => status == 1 || status == 3;
}

/// Service for interacting with WaltSplitBillV3 smart contract
class SplitBillContractService {
  static const String _contractAddress = '0x49c19A8fD9f35f858DFfF6F2c0DE77a062d71B7c';
  
  Web3Client? _web3Client;
  http.Client? _httpClient;
  DeployedContract? _contract;
  
  // Contract ABI for WaltSplitBillV3
  static const String _abi = '''[
    {
      "inputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "name": "getBill",
      "outputs": [
        {"components": [
          {"internalType": "bytes32", "name": "billId", "type": "bytes32"},
          {"internalType": "address", "name": "creator", "type": "address"},
          {"internalType": "address", "name": "token", "type": "address"},
          {"internalType": "string", "name": "description", "type": "string"},
          {"internalType": "uint256", "name": "totalAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "collectedAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "createdAt", "type": "uint256"},
          {"internalType": "uint256", "name": "deadline", "type": "uint256"},
          {"internalType": "enum WaltSplitBillV3.BillStatus", "name": "status", "type": "uint8"},
          {"internalType": "uint8", "name": "participantCount", "type": "uint8"},
          {"internalType": "uint8", "name": "paidCount", "type": "uint8"}
        ], "internalType": "struct WaltSplitBillV3.Bill", "name": "", "type": "tuple"}
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "bytes32", "name": "billId", "type": "bytes32"}],
      "name": "getParticipants",
      "outputs": [
        {"components": [
          {"internalType": "address", "name": "wallet", "type": "address"},
          {"internalType": "uint256", "name": "amountDue", "type": "uint256"},
          {"internalType": "uint256", "name": "amountPaid", "type": "uint256"},
          {"internalType": "enum WaltSplitBillV3.PaymentStatus", "name": "status", "type": "uint8"},
          {"internalType": "uint256", "name": "paidAt", "type": "uint256"}
        ], "internalType": "struct WaltSplitBillV3.Participant[]", "name": "", "type": "tuple[]"}
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "address", "name": "user", "type": "address"}],
      "name": "getUserBills",
      "outputs": [{"internalType": "bytes32[]", "name": "", "type": "bytes32[]"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "address", "name": "user", "type": "address"}],
      "name": "getUserInvitations",
      "outputs": [{"internalType": "bytes32[]", "name": "", "type": "bytes32[]"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {"internalType": "string", "name": "description", "type": "string"},
        {"internalType": "address", "name": "token", "type": "address"},
        {"internalType": "address[]", "name": "participants", "type": "address[]"},
        {"internalType": "uint256[]", "name": "amounts", "type": "uint256[]"},
        {"internalType": "uint256", "name": "deadline", "type": "uint256"}
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
      "inputs": [{"internalType": "address", "name": "", "type": "address"}],
      "name": "supportedTokens",
      "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "owner",
      "outputs": [{"internalType": "address", "name": "", "type": "address"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "feeCollector",
      "outputs": [{"internalType": "address", "name": "", "type": "address"}],
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
    }
  ]''';

  Future<void> init() async {
    if (_web3Client != null) return;
    
    _httpClient = http.Client();
    _web3Client = Web3Client(Env.liskRpcUrl, _httpClient!);
    _contract = DeployedContract(
      ContractAbi.fromJson(_abi, 'WaltSplitBill'),
      EthereumAddress.fromHex(_contractAddress),
    );
    
    print('[SplitBillContract] Initialized at $_contractAddress');
    
    // Query contract state for debugging
    try {
      final ownerResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('owner'),
        params: [],
      );
      final ownerAddr = (ownerResult[0] as EthereumAddress).hex;
      print('[SplitBillContract] Contract owner: $ownerAddr');
      
      final feeResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('feeCollector'),
        params: [],
      );
      final feeCollector = (feeResult[0] as EthereumAddress).hex;
      print('[SplitBillContract] Fee collector: $feeCollector');
      
      // Check which tokens are supported
      final lskToken = EthereumAddress.fromHex('0xac485391eb2d7d88253a7f1ef18c37f4571c1571');
      final lskSupported = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('supportedTokens'),
        params: [lskToken],
      );
      print('[SplitBillContract] LSK (0xac48...) supported: ${lskSupported[0]}');
      
      // Check the other LSK token
      final lsk2Token = EthereumAddress.fromHex('0x4270a0c8676a10ab8cbe3e92bfd187d94c8f248e');
      final lsk2Supported = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('supportedTokens'),
        params: [lsk2Token],
      );
      print('[SplitBillContract] LSK (0x4270...) supported: ${lsk2Supported[0]}');
    } catch (e) {
      print('[SplitBillContract] Could not query contract state: $e');
    }
  }

  void dispose() {
    _web3Client?.dispose();
    _httpClient?.close();
  }

  /// Get all bills for a user (created + invitations)
  Future<List<ContractBill>> getAllBillsForUser(String walletAddress) async {
    await init();
    
    final userAddress = EthereumAddress.fromHex(walletAddress);
    final bills = <ContractBill>[];
    final seenIds = <String>{};
    
    try {
      // Get bills created by user - returns bytes32[] array
      final createdResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getUserBills'),
        params: [userAddress],
      );
      final createdIds = (createdResult[0] as List).cast<dynamic>();
      print('[SplitBillContract] Found ${createdIds.length} created bills');
      
      for (final billIdBytes in createdIds) {
        final billId = _bytes32ToHex(billIdBytes);
        if (!seenIds.contains(billId)) {
          seenIds.add(billId);
          final bill = await getBill(billId);
          if (bill != null) bills.add(bill);
        }
      }
      
      // Get bills user is invited to - returns bytes32[] array
      final inviteResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getUserInvitations'),
        params: [userAddress],
      );
      final inviteIds = (inviteResult[0] as List).cast<dynamic>();
      print('[SplitBillContract] Found ${inviteIds.length} invitations');
      
      for (final billIdBytes in inviteIds) {
        final billId = _bytes32ToHex(billIdBytes);
        if (!seenIds.contains(billId)) {
          seenIds.add(billId);
          final bill = await getBill(billId);
          if (bill != null) bills.add(bill);
        }
      }
      
      print('[SplitBillContract] Found ${bills.length} total bills for $walletAddress');
      return bills;
      
    } catch (e) {
      print('[SplitBillContract] Error getting bills: $e');
      return [];
    }
  }

  /// Get a single bill by ID
  Future<ContractBill?> getBill(String billId) async {
    await init();
    
    try {
      final billIdBytes = _hexToBytes32(billId);
      
      // Get bill data
      final billResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getBill'),
        params: [billIdBytes],
      );
      
      final billData = billResult[0] as List<dynamic>;
      
      // WaltSplitBillV3 Bill struct:
      // [0] billId, [1] creator, [2] token, [3] description, 
      // [4] totalAmount, [5] collectedAmount, [6] createdAt, [7] deadline,
      // [8] status, [9] participantCount, [10] paidCount
      
      // Check if bill exists (createdAt > 0)
      final createdAt = billData[6] as BigInt;
      if (createdAt == BigInt.zero) return null;
      
      // Get token address and determine token name
      final tokenAddr = (billData[2] as EthereumAddress).hex.toLowerCase();
      String tokenName = 'LSK';
      if (tokenAddr == '0x4270a0c8676a10ab8cbe3e92bfd187d94c8f248e') tokenName = 'LSK';
      else if (tokenAddr == '0xee412e79eb7f565ec9e7c8a1b0a7ec27b63fbc5e') tokenName = 'POL';
      else if (tokenAddr == '0x292d54495d4c9af56d86fa6caf25591037ef80b3') tokenName = 'ETH';
      
      // Get participants
      final participantsResult = await _web3Client!.call(
        contract: _contract!,
        function: _contract!.function('getParticipants'),
        params: [billIdBytes],
      );
      
      final participantsData = participantsResult[0] as List<dynamic>;
      final participants = participantsData.map((p) {
        final pList = p as List<dynamic>;
        return ContractParticipant(
          wallet: (pList[0] as EthereumAddress).hex,
          amountDue: pList[1] as BigInt,
          amountPaid: pList[2] as BigInt,
          status: (pList[3] as BigInt).toInt(),
          requestedToken: tokenName,
          paidAt: (pList[4] as BigInt) > BigInt.zero 
              ? DateTime.fromMillisecondsSinceEpoch((pList[4] as BigInt).toInt() * 1000)
              : null,
        );
      }).toList();
      
      return ContractBill(
        billId: billId,
        creator: (billData[1] as EthereumAddress).hex,
        description: billData[3] as String,
        totalAmount: billData[4] as BigInt,
        collectedAmount: billData[5] as BigInt,
        createdAt: DateTime.fromMillisecondsSinceEpoch((billData[6] as BigInt).toInt() * 1000),
        deadline: DateTime.fromMillisecondsSinceEpoch((billData[7] as BigInt).toInt() * 1000),
        status: (billData[8] as BigInt).toInt(),
        participantCount: (billData[9] as BigInt).toInt(),
        paidCount: (billData[10] as BigInt).toInt(),
        requestedToken: tokenName,
        participants: participants,
      );
      
    } catch (e) {
      print('[SplitBillContract] Error getting bill $billId: $e');
      return null;
    }
  }

  /// Create a new bill
  Future<String> createBill({
    required Credentials credentials,
    required String description,
    required String tokenAddress,
    required List<String> participantAddresses,
    required List<BigInt> participantAmounts,
    required DateTime deadline,
  }) async {
    await init();
    
    print('[SplitBillContract] Creating bill...');
    print('[SplitBillContract]   Description: $description');
    print('[SplitBillContract]   Token: $tokenAddress');
    print('[SplitBillContract]   Participants: ${participantAddresses.length}');
    print('[SplitBillContract]   Deadline: $deadline');
    
    final token = EthereumAddress.fromHex(tokenAddress.toLowerCase());
    final addresses = participantAddresses.map((a) => EthereumAddress.fromHex(a.toLowerCase())).toList();
    final deadlineTimestamp = BigInt.from(deadline.millisecondsSinceEpoch ~/ 1000);
    
    print('[SplitBillContract]   Amounts: $participantAmounts');
    print('[SplitBillContract]   DeadlineTs: $deadlineTimestamp');
    
    // Try to estimate gas first to catch errors
    try {
      final gasEstimate = await _web3Client!.estimateGas(
        sender: credentials.address,
        to: _contract!.address,
        data: _contract!.function('createBill').encodeCall([description, token, addresses, participantAmounts, deadlineTimestamp]),
      );
      print('[SplitBillContract] Gas estimate: $gasEstimate');
    } catch (e) {
      print('[SplitBillContract] Gas estimate failed: $e');
      throw Exception('Contract call would fail: $e');
    }
    
    final tx = Transaction.callContract(
      contract: _contract!,
      function: _contract!.function('createBill'),
      parameters: [description, token, addresses, participantAmounts, deadlineTimestamp],
      maxGas: 700000,
    );
    
    final txHash = await _web3Client!.sendTransaction(credentials, tx, chainId: 4202);
    print('[SplitBillContract] Create tx: $txHash');
    
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
    
    print('[SplitBillContract] Paying share for bill: $billId');
    print('[SplitBillContract]   Token: $tokenAddress');
    print('[SplitBillContract]   Amount: $amount');
    
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
    print('[SplitBillContract] Pay tx: $txHash');
    
    // Wait for confirmation
    final receipt = await _waitForReceipt(txHash);
    if (receipt?.status == false) {
      throw Exception('Payment transaction reverted');
    }
    
    return txHash;
  }

  Future<void> _approveToken(Credentials credentials, String tokenAddress, BigInt amount) async {
    print('[SplitBillContract] Approving token: $tokenAddress');
    
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
    print('[SplitBillContract] Approve tx: $txHash');
    
    await _waitForReceipt(txHash);
  }

  Future<TransactionReceipt?> _waitForReceipt(String txHash) async {
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final receipt = await _web3Client!.getTransactionReceipt(txHash);
      if (receipt != null) {
        print('[SplitBillContract] Receipt received, status: ${receipt.status}');
        return receipt;
      }
    }
    print('[SplitBillContract] Timeout waiting for receipt');
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
    if (bytes is List) {
      final intList = bytes.cast<int>();
      return '0x${intList.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    }
    return bytes.toString();
  }
}
