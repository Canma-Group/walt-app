import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import '../config/env.dart';
import 'lisk_ledger_service.dart';

/// Token model for multi-chain balances
class TokenBalance {
  final int chainId;
  final String chainName;
  final String symbol;
  final String name;
  final String balance;
  final String tokenAddress;
  final String type; // 'native', 'erc20', 'ledger'
  final String? icon;

  TokenBalance({
    required this.chainId,
    required this.chainName,
    required this.symbol,
    required this.name,
    required this.balance,
    required this.tokenAddress,
    this.type = 'native',
    this.icon,
  });

  factory TokenBalance.fromJson(Map<String, dynamic> json) {
    return TokenBalance(
      chainId: json['chainId'] ?? 0,
      chainName: json['chainName'] ?? '',
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      balance: json['balance']?.toString() ?? '0',
      tokenAddress: json['tokenAddress'] ?? '',
      type: json['type'] ?? 'native',
      icon: json['icon'],
    );
  }

  Map<String, dynamic> toJson() => {
    'chainId': chainId,
    'chainName': chainName,
    'symbol': symbol,
    'name': name,
    'balance': balance,
    'tokenAddress': tokenAddress,
    'type': type,
    'icon': icon,
  };

  double get balanceAsDouble => double.tryParse(balance) ?? 0.0;
}

/// Deposit record model
class DepositRecord {
  final String id;
  final String walletAddress;
  final int sourceChainId;
  final String tokenAddress;
  final String amount;
  final String sourceTxHash;
  final String? liskTxHash;
  final String recordedAt;
  final String status;

  DepositRecord({
    required this.id,
    required this.walletAddress,
    required this.sourceChainId,
    required this.tokenAddress,
    required this.amount,
    required this.sourceTxHash,
    this.liskTxHash,
    required this.recordedAt,
    required this.status,
  });

  factory DepositRecord.fromJson(Map<String, dynamic> json) {
    return DepositRecord(
      id: json['id'] ?? '',
      walletAddress: json['walletAddress'] ?? '',
      sourceChainId: json['sourceChainId'] ?? 0,
      tokenAddress: json['tokenAddress'] ?? '',
      amount: json['amount']?.toString() ?? '0',
      sourceTxHash: json['sourceTxHash'] ?? '',
      liskTxHash: json['liskTxHash'],
      recordedAt: json['recordedAt'] ?? '',
      status: json['status'] ?? '',
    );
  }
}

/// Multi-chain service for fetching token balances and managing deposits
class MultiChainService {
  final String _backendUrl;
  final http.Client _httpClient;
  
  // Chain configurations
  static const Map<int, ChainConfig> chains = {
    1135: ChainConfig(
      chainId: 1135,
      name: 'Lisk',
      rpcUrl: 'https://rpc.api.lisk.com',
      symbol: 'ETH',
      explorer: 'https://blockscout.lisk.com',
    ),
    4202: ChainConfig(
      chainId: 4202,
      name: 'Lisk Sepolia',
      rpcUrl: 'https://rpc.sepolia-api.lisk.com',
      symbol: 'ETH',
      explorer: 'https://sepolia-blockscout.lisk.com',
    ),
    137: ChainConfig(
      chainId: 137,
      name: 'Polygon',
      rpcUrl: 'https://polygon-rpc.com',
      symbol: 'POL',
      explorer: 'https://polygonscan.com',
    ),
    1: ChainConfig(
      chainId: 1,
      name: 'Ethereum',
      rpcUrl: 'https://eth.llamarpc.com',
      symbol: 'ETH',
      explorer: 'https://etherscan.io',
    ),
  };
  
  // LSK token contract on Lisk mainnet (lowercase to avoid EIP-55 issues)
  static const String lskTokenContract = '0xac485391eb2d7d88253a7f1ef18c37f4571c1a24';
  
  // MockLSK token contract on Lisk Sepolia testnet (for hackathon demo)
  // IMPORTANT: Must match env.dart and transfer_details_page.dart
  static const String mockLskTokenContract = '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';
  
  // MockETH token contract on Lisk Sepolia testnet
  static const String mockEthTokenContract = '0x292D54495d4C9Af56D86fA6cAF25591037EF80b3';
  
  // MockPOL token contract on Lisk Sepolia testnet  
  static const String mockPolTokenContract = '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e';

  MultiChainService({
    String? backendUrl,
    http.Client? httpClient,
  }) : _backendUrl = backendUrl ?? 'http://203.194.112.143:3000',
       _httpClient = httpClient ?? http.Client();

  /// Get all token balances from backend (includes on-chain + ledger)
  Future<List<TokenBalance>> getTokenBalances(
    String walletAddress,
    String authToken,
  ) async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$_backendUrl/tokens/$walletAddress'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final tokens = (data['data']['tokens'] as List)
              .map((t) => TokenBalance.fromJson(t))
              .toList();
          return tokens;
        }
      }
      
      // Fallback: fetch directly from chains
      return await _fetchDirectBalances(walletAddress);
    } catch (e) {
      if (Env.enableDebugLogs) print('Error fetching tokens from backend: $e');
      // Fallback to direct chain queries
      return await _fetchDirectBalances(walletAddress);
    }
  }

  /// Fetch balances directly from blockchain RPCs (fallback)
  /// HACKATHON MODE: Only fetches Lisk Sepolia testnet tokens
  Future<List<TokenBalance>> _fetchDirectBalances(String walletAddress) async {
    final List<TokenBalance> tokens = [];
    
    if (Env.enableDebugLogs) print('[MultiChainService] Fetching TESTNET balances for: $walletAddress');

    // HACKATHON: Skip mainnet tokens, only show testnet
    // Fetch MockLSK from Lisk Sepolia testnet
    if (Env.enableTestnet) {
      try {
        if (Env.enableDebugLogs) print('[MultiChainService] Fetching MockLSK from Lisk Sepolia...');
        
        final liskSepoliaClient = Web3Client(
          chains[4202]!.rpcUrl,
          _httpClient,
        );
        
        // Directly fetch MockLSK ERC-20 balance using contract call (more reliable than Blockscout)
        final mockLskBalance = await _getErc20BalanceRpc(
          liskSepoliaClient,
          mockLskTokenContract,
          walletAddress,
        );
        
        if (mockLskBalance > BigInt.zero) {
          final balanceDouble = mockLskBalance.toDouble() / BigInt.from(10).pow(18).toDouble();
          final balanceStr = balanceDouble.toStringAsFixed(4);
          
          if (Env.enableDebugLogs) print('[MultiChainService] Found MockLSK: $balanceStr');
          
          tokens.add(TokenBalance(
            chainId: 4202,
            chainName: 'Lisk Sepolia',
            symbol: 'LSK',
            name: 'MockLSK (Testnet)',
            balance: balanceStr,
            tokenAddress: mockLskTokenContract,
            type: 'erc20',
            icon: null,
          ));
        }
        
        // Also fetch native ETH on Lisk Sepolia
        final sepoliaEthBalance = await liskSepoliaClient.getBalance(
          EthereumAddress.fromHex(walletAddress),
        );
        final sepoliaEthStr = (sepoliaEthBalance.getInWei.toDouble() / 1e18).toStringAsFixed(6);
        
        if (Env.enableDebugLogs) print('[MultiChainService] Lisk Sepolia ETH: $sepoliaEthStr');
        
        if (double.parse(sepoliaEthStr) > 0) {
          tokens.add(TokenBalance(
            chainId: 4202,
            chainName: 'Lisk Sepolia',
            symbol: 'ETH',
            name: 'Sepolia ETH',
            balance: sepoliaEthStr,
            tokenAddress: '0x0000000000000000000000000000000000000000',
            type: 'native',
            icon: null,
          ));
        }
        
        // Fetch MockETH token if contract is set
        if (mockEthTokenContract.isNotEmpty) {
          print('[MultiChainService] Fetching MockETH from contract: $mockEthTokenContract');
          try {
            final mockEthBalance = await _getErc20BalanceRpc(
              liskSepoliaClient,
              mockEthTokenContract,
              walletAddress,
            );
            
            print('[MultiChainService] MockETH raw balance: $mockEthBalance');
            
            if (mockEthBalance > BigInt.zero) {
              final balanceDouble = mockEthBalance.toDouble() / BigInt.from(10).pow(18).toDouble();
              final balanceStr = balanceDouble.toStringAsFixed(6);
              
              print('[MultiChainService] Found MockETH: $balanceStr');
              
              tokens.add(TokenBalance(
                chainId: 4202,
                chainName: 'Lisk Sepolia',
                symbol: 'ETH',
                name: 'MockETH (Testnet)',
                balance: balanceStr,
                tokenAddress: mockEthTokenContract,
                type: 'erc20',
                icon: null,
              ));
            }
          } catch (e) {
            print('[MultiChainService] Error fetching MockETH: $e');
          }
        } else {
          print('[MultiChainService] MockETH contract is empty, skipping');
        }
        
        // Fetch MockPOL token if contract is set
        if (mockPolTokenContract.isNotEmpty) {
          print('[MultiChainService] Fetching MockPOL from contract: $mockPolTokenContract');
          try {
            final mockPolBalance = await _getErc20BalanceRpc(
              liskSepoliaClient,
              mockPolTokenContract,
              walletAddress,
            );
            
            print('[MultiChainService] MockPOL raw balance: $mockPolBalance');
            
            if (mockPolBalance > BigInt.zero) {
              final balanceDouble = mockPolBalance.toDouble() / BigInt.from(10).pow(18).toDouble();
              final balanceStr = balanceDouble.toStringAsFixed(4);
              
              print('[MultiChainService] Found MockPOL: $balanceStr');
              
              tokens.add(TokenBalance(
                chainId: 4202,
                chainName: 'Lisk Sepolia',
                symbol: 'POL',
                name: 'MockPOL (Testnet)',
                balance: balanceStr,
                tokenAddress: mockPolTokenContract,
                type: 'erc20',
                icon: null,
              ));
            }
          } catch (e) {
            print('[MultiChainService] Error fetching MockPOL: $e');
          }
        } else {
          print('[MultiChainService] MockPOL contract is empty, skipping');
        }
      } catch (e) {
        if (Env.enableDebugLogs) print('[MultiChainService] Error fetching Lisk Sepolia balance: $e');
      }
    }

    // HACKATHON: Skip Polygon and Ethereum mainnet - only testnet tokens
    // This keeps the demo focused on Lisk Sepolia testnet

    return tokens;
  }

  /// Record a deposit to the Lisk ledger
  Future<String?> recordDeposit({
    required String walletAddress,
    required int chainId,
    required String amount,
    required String txHash,
    required String authToken,
    String? tokenAddress,
  }) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$_backendUrl/record-deposit'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'walletAddress': walletAddress,
          'chainId': chainId,
          'tokenAddress': tokenAddress ?? '0x0000000000000000000000000000000000000000',
          'amount': amount,
          'txHash': txHash,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['data']['liskTxHash'];
        }
      }
      
      return null;
    } catch (e) {
      if (Env.enableDebugLogs) print('Error recording deposit: $e');
      return null;
    }
  }

  /// Get deposit history
  Future<List<DepositRecord>> getDepositHistory(
    String walletAddress,
    String authToken,
  ) async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$_backendUrl/deposits/$walletAddress'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return (data['data'] as List)
              .map((d) => DepositRecord.fromJson(d))
              .toList();
        }
      }
      
      return [];
    } catch (e) {
      if (Env.enableDebugLogs) print('Error fetching deposit history: $e');
      return [];
    }
  }

  /// Get chain config by ID
  static ChainConfig? getChainConfig(int chainId) {
    return chains[chainId];
  }

  /// Get explorer URL for a transaction
  static String getExplorerTxUrl(int chainId, String txHash) {
    final chain = chains[chainId];
    if (chain != null) {
      return '${chain.explorer}/tx/$txHash';
    }
    return '';
  }

  /// Get ERC-20 token balance using contract ABI
  Future<BigInt> _getErc20BalanceRpc(
    Web3Client client,
    String tokenAddress,
    String walletAddress,
  ) async {
    try {
      // Minimal ERC-20 ABI for balanceOf
      final erc20Abi = ContractAbi.fromJson(
        '[{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"}]',
        'ERC20',
      );
      
      final contract = DeployedContract(
        erc20Abi,
        EthereumAddress.fromHex(tokenAddress),
      );
      
      final balanceOf = contract.function('balanceOf');
      final result = await client.call(
        contract: contract,
        function: balanceOf,
        params: [EthereumAddress.fromHex(walletAddress)],
      );
      
      if (result.isNotEmpty && result[0] is BigInt) {
        return result[0] as BigInt;
      }
      return BigInt.zero;
    } catch (e) {
      if (Env.enableDebugLogs) print('[MultiChainService] Error getting ERC-20 balance: $e');
      return BigInt.zero;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Chain configuration
class ChainConfig {
  final int chainId;
  final String name;
  final String rpcUrl;
  final String symbol;
  final String explorer;

  const ChainConfig({
    required this.chainId,
    required this.name,
    required this.rpcUrl,
    required this.symbol,
    required this.explorer,
  });
}
