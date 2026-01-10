import 'package:flutter/material.dart';
import 'package:banking_app/services/web3auth_service.dart';
import 'package:banking_app/services/cloud_functions_service.dart';
import 'package:banking_app/services/blockchain_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Test Page untuk verify Web3Auth + Firebase Integration
/// 
/// Usage: Add route '/test-wallet' di main.dart
class WalletTestPage extends StatefulWidget {
  const WalletTestPage({Key? key}) : super(key: key);

  @override
  State<WalletTestPage> createState() => _WalletTestPageState();
}

class _WalletTestPageState extends State<WalletTestPage> {
  final _web3AuthService = Web3AuthService();
  final _cloudFunctions = CloudFunctionsService();
  final _blockchainService = BlockchainService();
  final _firebaseAuth = FirebaseAuth.instance;

  String _status = 'Ready to test';
  String? _walletAddress;
  String? _firebaseUserId;
  String? _balance;
  bool _isLoading = false;
  List<String> _testResults = [];

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    setState(() {
      _status = 'Checking initial state...';
    });

    // Check Firebase Auth
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      _firebaseUserId = user.uid;
      _addResult('✅ Firebase Auth: User logged in (${user.email})');
    } else {
      _addResult('⚠️ Firebase Auth: No user logged in');
    }

    // Check Web3Auth wallet
    await _web3AuthService.initialize();
    final wallet = _web3AuthService.walletAddress;
    if (wallet != null) {
      _walletAddress = wallet;
      _addResult('✅ Web3Auth: Wallet exists ($wallet)');
    } else {
      _addResult('⚠️ Web3Auth: No wallet found');
    }

    setState(() {
      _status = 'Initial check complete';
    });
  }

  void _addResult(String result) {
    setState(() {
      _testResults.add('${DateTime.now().toString().substring(11, 19)}: $result');
    });
    print(result);
  }

  Future<void> _testLogin() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing login...';
      _testResults.clear();
    });

    try {
      // Step 1: Initialize Web3Auth
      _addResult('Step 1: Initializing Web3Auth...');
      await _web3AuthService.initialize();
      _addResult('✅ Web3Auth initialized');

      // Step 2: Login with Google
      _addResult('Step 2: Starting Google login...');
      final result = await _web3AuthService.loginWithGoogle();

      if (result['success'] == true) {
        _walletAddress = result['walletAddress'] as String?;
        _addResult('✅ Login successful!');
        _addResult('✅ Wallet Address: $_walletAddress');

        // Step 3: Check Firebase Auth
        final user = _firebaseAuth.currentUser;
        if (user != null) {
          _firebaseUserId = user.uid;
          _addResult('✅ Firebase User ID: $_firebaseUserId');
          _addResult('✅ Firebase Email: ${user.email}');
        } else {
          _addResult('❌ Firebase Auth: No user found');
        }

        // Step 4: Check balance
        if (_walletAddress != null) {
          _addResult('Step 4: Checking balance...');
          try {
            final balance = await _blockchainService.getBalanceInLSK(_walletAddress!);
            _balance = balance;
            _addResult('✅ Balance: $balance LSK');
          } catch (e) {
            _addResult('⚠️ Balance check failed: $e');
          }
        }

        setState(() {
          _status = '✅ Login test PASSED';
        });
      } else {
        _addResult('❌ Login failed: ${result['error']}');
        setState(() {
          _status = '❌ Login test FAILED';
        });
      }
    } catch (e) {
      _addResult('❌ Error: $e');
      setState(() {
        _status = '❌ Test FAILED: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testGetProfile() async {
    if (_firebaseUserId == null) {
      _addResult('❌ Must login first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Testing getProfile...';
    });

    try {
      final result = await _cloudFunctions.getUserProfile();
      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>?;
        _addResult('✅ Profile retrieved');
        _addResult('   Wallet: ${data?['walletAddress']}');
        _addResult('   Last Activity: ${data?['lastActivity']}');
        setState(() {
          _status = '✅ GetProfile test PASSED';
        });
      } else {
        _addResult('⚠️ Profile not found (normal if no top-up yet)');
        _addResult('   Message: ${result['message']}');
        setState(() {
          _status = '⚠️ Profile not found';
        });
      }
    } catch (e) {
      _addResult('❌ Error: $e');
      setState(() {
        _status = '❌ GetProfile test FAILED';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testCreateQRIS() async {
    if (_walletAddress == null) {
      _addResult('❌ Must login first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Testing createQRIS...';
    });

    try {
      final result = await _cloudFunctions.createQRIS(
        amountInIDR: 10000,
        userWalletAddress: _walletAddress!,
      );

      if (result['success'] == true) {
        _addResult('✅ QRIS created successfully');
        _addResult('   External ID: ${result['data']?['externalId']}');
        _addResult('   Amount: ${result['data']?['amount']} IDR');
        
        // This should trigger auto-save to Firestore
        _addResult('✅ Wallet should be saved to Firestore now');
        
        setState(() {
          _status = '✅ CreateQRIS test PASSED';
        });
      } else {
        _addResult('❌ QRIS creation failed: ${result['error']}');
        setState(() {
          _status = '❌ CreateQRIS test FAILED';
        });
      }
    } catch (e) {
      _addResult('❌ Error: $e');
      setState(() {
        _status = '❌ CreateQRIS test FAILED';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testLogout() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing logout...';
    });

    try {
      await _web3AuthService.logout();
      _addResult('✅ Logout successful');
      _addResult('✅ Wallet cleared from memory');
      
      setState(() {
        _walletAddress = null;
        _firebaseUserId = null;
        _balance = null;
        _status = '✅ Logout test PASSED';
      });
    } catch (e) {
      _addResult('❌ Logout failed: $e');
      setState(() {
        _status = '❌ Logout test FAILED';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Test Page'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              color: _status.contains('PASSED') 
                  ? Colors.green.shade50 
                  : _status.contains('FAILED')
                      ? Colors.red.shade50
                      : Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: $_status',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_firebaseUserId != null) ...[
                      const SizedBox(height: 8),
                      Text('Firebase UID: $_firebaseUserId'),
                    ],
                    if (_walletAddress != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Wallet: $_walletAddress',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ],
                    if (_balance != null) ...[
                      const SizedBox(height: 8),
                      Text('Balance: $_balance LSK'),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Test Buttons
            ElevatedButton(
              onPressed: _isLoading ? null : _testLogin,
              child: const Text('1. Test Login (Web3Auth + Firebase)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _testGetProfile,
              child: const Text('2. Test Get Profile (Firestore)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _testCreateQRIS,
              child: const Text('3. Test Create QRIS (Auto-save wallet)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _testLogout,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('4. Test Logout'),
            ),

            const SizedBox(height: 24),

            // Test Results
            const Text(
              'Test Results:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _testResults.length,
                itemBuilder: (context, index) {
                  final result = _testResults[index];
                  final isSuccess = result.contains('✅');
                  final isError = result.contains('❌');
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      result,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: isError
                            ? Colors.red
                            : isSuccess
                                ? Colors.green
                                : Colors.black87,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

