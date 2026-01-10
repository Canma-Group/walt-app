import 'package:flutter/material.dart';
import '../services/web3auth_service.dart';
import '../config/env.dart';

/// Debug page untuk test Web3Auth secara isolated
class Web3AuthDebugPage extends StatefulWidget {
  const Web3AuthDebugPage({Key? key}) : super(key: key);

  @override
  State<Web3AuthDebugPage> createState() => _Web3AuthDebugPageState();
}

class _Web3AuthDebugPageState extends State<Web3AuthDebugPage> {
  String _status = 'Ready to test';
  String _logs = '';
  bool _isLoading = false;

  void _addLog(String message) {
    setState(() {
      final timestamp = DateTime.now().toString().substring(11, 19);
      _logs += '[$timestamp] $message\n';
    });
    print('[DEBUG] $message');
  }

  Future<void> _testWeb3AuthInit() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing Web3Auth initialization...';
      _logs = '';
    });

    try {
      _addLog('🔧 Starting Web3Auth initialization test');
      _addLog('Client ID: ${Env.web3AuthClientId}');
      _addLog('Network: ${Env.web3AuthNetwork}');
      
      final web3AuthService = Web3AuthService();
      
      _addLog('📡 Calling Web3AuthService.initialize()...');
      await web3AuthService.initialize();
      
      _addLog('✅ Web3Auth initialization SUCCESS');
      setState(() {
        _status = 'Initialization successful! Ready for login test.';
      });
      
    } catch (e) {
      _addLog('❌ Web3Auth initialization FAILED: $e');
      setState(() {
        _status = 'Initialization failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testWeb3AuthLogin() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing Web3Auth login...';
    });

    try {
      _addLog('🔐 Starting Web3Auth login test');
      
      final web3AuthService = Web3AuthService();
      
      _addLog('📱 Calling ensureUserWallet()...');
      final result = await web3AuthService.ensureUserWallet();
      
      _addLog('✅ Login SUCCESS!');
      _addLog('Method: ${result['method']}');
      _addLog('Wallet: ${result['walletAddress']}');
      _addLog('Success: ${result['success']}');
      
      setState(() {
        _status = 'Login successful! Wallet: ${result['walletAddress']}';
      });
      
    } catch (e) {
      _addLog('❌ Login FAILED: $e');
      setState(() {
        _status = 'Login failed: $e';
      });
      
      // Check for specific redirect error
      if (e.toString().toLowerCase().contains('redirect')) {
        _addLog('🚨 REDIRECT URL ERROR detected!');
        _addLog('Solution: Add canmawallet://auth to Web3Auth dashboard');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearLogs() {
    setState(() {
      _logs = '';
      _status = 'Logs cleared';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web3Auth Debug'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                'Status: $_status',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Test Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testWeb3AuthInit,
                    icon: _isLoading ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ) : const Icon(Icons.power_settings_new),
                    label: const Text('Test Init'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testWeb3AuthLogin,
                    icon: _isLoading ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ) : const Icon(Icons.login),
                    label: const Text('Test Login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              onPressed: _clearLogs,
              icon: const Icon(Icons.clear),
              label: const Text('Clear Logs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Configuration Info
            const Text(
              'Current Configuration:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Client ID: ${Env.web3AuthClientId.substring(0, 20)}...'),
                  Text('Network: ${Env.web3AuthNetwork}'),
                  const Text('Redirect: canmawallet://auth'),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Logs
            const Text(
              'Debug Logs:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _logs.isEmpty ? 'No logs yet. Click "Test Init" to start.' : _logs,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
