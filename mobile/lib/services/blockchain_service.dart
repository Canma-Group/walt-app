import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import '../config/env.dart';

/// Blockchain Service - Manages Lisk blockchain interactions
class BlockchainService {
  late Web3Client _client;
  late String _rpcUrl;
  late http.Client _httpClient;
  
  BlockchainService({String? rpcUrl}) {
    _rpcUrl = rpcUrl ?? Env.liskRpcUrl;
    _httpClient = http.Client();
    _client = Web3Client(_rpcUrl, _httpClient);
  }

  String get rpcUrl => _rpcUrl;

  void setRpcUrl(String rpcUrl) {
    if (rpcUrl.isEmpty || _rpcUrl == rpcUrl) return;

    _rpcUrl = rpcUrl;
    _client.dispose();
    _httpClient.close();
    _httpClient = http.Client();
    _client = Web3Client(_rpcUrl, _httpClient);
  }

  Future<int> getChainId() async {
    try {
      final dynamic id = await _client.getChainId();
      final int chainId = id is BigInt ? id.toInt() : id as int;
      if (chainId <= 0) {
        throw Exception('Invalid chainId: $chainId');
      }
      return chainId;
    } catch (e) {
      throw Exception('Failed to get chainId: $e');
    }
  }
  
  /// Get LSK balance for an address
  Future<EtherAmount> getBalance(String address) async {
    try {
      final ethAddress = EthereumAddress.fromHex(address);
      return await _client.getBalance(ethAddress);
    } catch (e) {
      throw Exception('Failed to get balance: $e');
    }
  }
  
  /// Get balance in LSK (formatted)
  Future<String> getBalanceInLSK(String address) async {
    final balance = await getBalance(address);
    return balance.getValueInUnit(EtherUnit.ether).toStringAsFixed(6);
  }
  
  /// Send LSK to another address
  Future<String> sendTransaction({
    required Credentials credentials,
    required String toAddress,
    required BigInt amountInWei,
  }) async {
    try {
      final transaction = Transaction(
        to: EthereumAddress.fromHex(toAddress),
        value: EtherAmount.inWei(amountInWei),
      );

      final chainId = await getChainId();
      
      final txHash = await _client.sendTransaction(
        credentials,
        transaction,
        chainId: chainId,
      );
      
      return txHash;
    } catch (e) {
      throw Exception('Failed to send transaction: $e');
    }
  }
  
  /// Get transaction receipt
  Future<TransactionReceipt?> getTransactionReceipt(String txHash) async {
    try {
      return await _client.getTransactionReceipt(txHash);
    } catch (e) {
      if (Env.enableDebugLogs) print('Transaction not mined yet: $e');
      return null;
    }
  }
  
  /// Convert LSK to Wei (1 LSK = 10^18 Wei)
  BigInt lskToWei(double lsk) {
    return BigInt.from(lsk * 1e18);
  }
  
  /// Convert Wei to LSK
  double weiToLSK(BigInt wei) {
    return wei.toDouble() / 1e18;
  }
  
  /// Dispose client
  void dispose() {
    _client.dispose();
    _httpClient.close();
  }
}


