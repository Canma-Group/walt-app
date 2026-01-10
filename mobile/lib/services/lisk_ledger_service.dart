import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import '../config/env.dart';

/// Service untuk interact langsung dengan CrossChainLedger contract di Lisk Sepolia
/// Ini menghilangkan kebutuhan backend untuk recording deposits
class LiskLedgerService {
  static const String _liskRpcUrl = 'https://rpc.sepolia-api.lisk.com';
  static const int _liskChainId = 4202;
  
  late Web3Client _client;
  late http.Client _httpClient;
  
  // Contract address - set setelah deploy
  String? _contractAddress;
  
  // Contract ABI (minimal untuk read functions)
  static const String _contractAbi = '''
[
  {
    "inputs": [{"internalType": "address", "name": "user", "type": "address"}, {"internalType": "uint256", "name": "chainId", "type": "uint256"}, {"internalType": "address", "name": "token", "type": "address"}],
    "name": "getBalance",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "user", "type": "address"}, {"internalType": "uint256", "name": "sourceChainId", "type": "uint256"}, {"internalType": "address", "name": "token", "type": "address"}, {"internalType": "uint256", "name": "amount", "type": "uint256"}, {"internalType": "bytes32", "name": "sourceTxHash", "type": "bytes32"}],
    "name": "recordDeposit",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "chainId", "type": "uint256"}, {"internalType": "bytes32", "name": "txHash", "type": "bytes32"}],
    "name": "isTxProcessed",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
  }
]
''';

  DeployedContract? _contract;

  LiskLedgerService({String? contractAddress}) {
    _contractAddress = contractAddress;
    _httpClient = http.Client();
    _client = Web3Client(_liskRpcUrl, _httpClient);
  }

  /// Set contract address setelah deploy
  void setContractAddress(String address) {
    _contractAddress = address;
    _contract = null; // Reset contract instance
  }

  /// Get contract instance
  DeployedContract _getContract() {
    if (_contractAddress == null || _contractAddress!.isEmpty) {
      throw Exception('Contract address not set. Deploy contract first and call setContractAddress()');
    }
    
    _contract ??= DeployedContract(
      ContractAbi.fromJson(_contractAbi, 'CrossChainLedger'),
      EthereumAddress.fromHex(_contractAddress!),
    );
    
    return _contract!;
  }

  /// Get user's ledger balance for a specific chain and token
  Future<BigInt> getLedgerBalance({
    required String userAddress,
    required int chainId,
    String tokenAddress = '0x0000000000000000000000000000000000000000',
  }) async {
    try {
      final contract = _getContract();
      final function = contract.function('getBalance');
      
      final result = await _client.call(
        contract: contract,
        function: function,
        params: [
          EthereumAddress.fromHex(userAddress),
          BigInt.from(chainId),
          EthereumAddress.fromHex(tokenAddress),
        ],
      );
      
      return result.first as BigInt;
    } catch (e) {
      if (Env.enableDebugLogs) print('Error getting ledger balance: $e');
      return BigInt.zero;
    }
  }

  /// Check if a transaction has been processed
  Future<bool> isTxProcessed({
    required int chainId,
    required String txHash,
  }) async {
    try {
      final contract = _getContract();
      final function = contract.function('isTxProcessed');
      
      // Convert txHash to bytes32
      final txHashBytes = _hexToBytes32(txHash);
      
      final result = await _client.call(
        contract: contract,
        function: function,
        params: [
          BigInt.from(chainId),
          txHashBytes,
        ],
      );
      
      return result.first as bool;
    } catch (e) {
      if (Env.enableDebugLogs) print('Error checking tx processed: $e');
      return false;
    }
  }

  /// Record a deposit to the ledger (requires operator private key)
  /// This should only be called by the operator/owner
  Future<String?> recordDeposit({
    required String userAddress,
    required int sourceChainId,
    required String amount, // in wei
    required String sourceTxHash,
    required String operatorPrivateKey,
    String tokenAddress = '0x0000000000000000000000000000000000000000',
  }) async {
    try {
      final contract = _getContract();
      final function = contract.function('recordDeposit');
      
      // Create credentials from private key
      final credentials = EthPrivateKey.fromHex(operatorPrivateKey);
      
      // Convert txHash to bytes32
      final txHashBytes = _hexToBytes32(sourceTxHash);
      
      final txHash = await _client.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract,
          function: function,
          parameters: [
            EthereumAddress.fromHex(userAddress),
            BigInt.from(sourceChainId),
            EthereumAddress.fromHex(tokenAddress),
            BigInt.parse(amount),
            txHashBytes,
          ],
        ),
        chainId: _liskChainId,
      );
      
      if (Env.enableDebugLogs) print('Deposit recorded. Lisk TxHash: $txHash');
      return txHash;
    } catch (e) {
      if (Env.enableDebugLogs) print('Error recording deposit: $e');
      return null;
    }
  }

  /// Get all ledger balances for a user (Polygon, Ethereum, etc.)
  Future<List<LedgerBalance>> getAllLedgerBalances(String userAddress) async {
    final balances = <LedgerBalance>[];
    
    // Check Polygon balance
    try {
      final polBalance = await getLedgerBalance(
        userAddress: userAddress,
        chainId: 137,
      );
      if (polBalance > BigInt.zero) {
        balances.add(LedgerBalance(
          chainId: 137,
          chainName: 'Polygon (Ledger)',
          symbol: 'POL',
          balance: polBalance,
        ));
      }
    } catch (_) {}
    
    // Check Ethereum balance
    try {
      final ethBalance = await getLedgerBalance(
        userAddress: userAddress,
        chainId: 1,
      );
      if (ethBalance > BigInt.zero) {
        balances.add(LedgerBalance(
          chainId: 1,
          chainName: 'Ethereum (Ledger)',
          symbol: 'ETH',
          balance: ethBalance,
        ));
      }
    } catch (_) {}
    
    return balances;
  }

  /// Convert hex string to bytes32
  Uint8List _hexToBytes32(String hex) {
    String cleanHex = hex.startsWith('0x') ? hex.substring(2) : hex;
    // Pad to 64 characters (32 bytes)
    cleanHex = cleanHex.padLeft(64, '0');
    
    final bytes = <int>[];
    for (var i = 0; i < cleanHex.length; i += 2) {
      bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  void dispose() {
    _client.dispose();
    _httpClient.close();
  }
}

/// Model for ledger balance
class LedgerBalance {
  final int chainId;
  final String chainName;
  final String symbol;
  final BigInt balance;

  LedgerBalance({
    required this.chainId,
    required this.chainName,
    required this.symbol,
    required this.balance,
  });

  String get balanceFormatted {
    final value = balance.toDouble() / 1e18;
    if (value == 0) return '0';
    if (value < 0.0001) return '<0.0001';
    if (value < 1) return value.toStringAsFixed(4);
    return value.toStringAsFixed(2);
  }
}
