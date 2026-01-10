import 'package:flutter/material.dart';
import '../services/web3auth_service.dart';

/// Simple test untuk Web3Auth - focused test
class SimpleWeb3AuthTest extends StatefulWidget {
  const SimpleWeb3AuthTest({Key? key}) : super(key: key);

  @override
  State<SimpleWeb3AuthTest> createState() => _SimpleWeb3AuthTestState();
}

class _SimpleWeb3AuthTestState extends State<SimpleWeb3AuthTest> {
  String _result = 'Tap button to test Web3Auth';
  bool _isLoading = false;

  Future<void> _testWeb3Auth() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing Web3Auth...';
    });

    try {
      print('=== SIMPLE WEB3AUTH TEST START ===');
      
      final service = Web3AuthService();
      final result = await service.ensureUserWallet();
      
      setState(() {
        _result = 'SUCCESS!\nMethod: ${result['method']}\nWallet: ${result['walletAddress']}';
      });
      
      print('=== TEST SUCCESS ===');
      
    } catch (e) {
      setState(() {
        _result = 'ERROR: $e';
      });
      
      print('=== TEST FAILED: $e ===');
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
        title: const Text('Web3Auth Test'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _result,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 32),
            
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _testWeb3Auth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('TEST WEB3AUTH', style: TextStyle(fontSize: 18)),
              ),
            ),
            
            const SizedBox(height: 16),
            
            const Text(
              'Check console logs for detailed debug info',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
