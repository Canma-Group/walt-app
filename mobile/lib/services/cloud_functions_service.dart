import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Cloud Functions Service - Calls backend Firebase Functions
class CloudFunctionsService {
  late FirebaseFunctions _functions;
  
  CloudFunctionsService() {
    _functions = FirebaseFunctions.instance;
    
    // Use emulator for local development
    // Uncomment this when testing locally:
    // _functions.useFunctionsEmulator('localhost', 5001);
  }
  
  /// Create QRIS payment for top-up
  Future<Map<String, dynamic>> createQRIS({
    required double amountInIDR,
    required String userWalletAddress,
  }) async {
    try {
      final callable = _functions.httpsCallable('createQRIS');
      final result = await callable.call(<String, dynamic>{
        'amountInIDR': amountInIDR.toInt(),
        'userWalletAddress': userWalletAddress,
      });
      
      return {
        'success': result.data['success'] ?? false,
        'data': result.data['data'],
        'error': result.data['error'],
      };
    } catch (e) {
      throw Exception('Failed to create QRIS: $e');
    }
  }
  
  /// Get user balance from blockchain
  Future<Map<String, dynamic>> getUserBalance({
    required String walletAddress,
  }) async {
    try {
      final callable = _functions.httpsCallable('getBalance');
      final result = await callable.call(<String, dynamic>{
        'walletAddress': walletAddress,
      });
      
      return {
        'success': result.data['success'] ?? false,
        'balance': result.data['data']?['balance'] ?? '0',
        'currency': result.data['data']?['currency'] ?? 'LSK',
        'error': result.data['error'],
      };
    } catch (e) {
      throw Exception('Failed to get balance: $e');
    }
  }
  
  /// Get user profile from Firestore (wallet address, activity)
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final callable = _functions.httpsCallable('getProfile');
      final result = await callable.call();
      
      return {
        'success': result.data['success'] ?? false,
        'data': result.data['data'],
        'error': result.data['error'],
        'message': result.data['message'],
      };
    } catch (e) {
      throw Exception('Failed to get profile: $e');
    }
  }
  
  /// Check if user exists by email and get their onboarding status
  /// This is called BEFORE authentication to determine the flow
  Future<Map<String, dynamic>> checkUserExists({
    required String email,
  }) async {
    try {
      final callable = _functions.httpsCallable('checkUser');
      final result = await callable.call(<String, dynamic>{
        'email': email,
      });
      
      final data = result.data;
      return {
        'success': data['success'] ?? false,
        'exists': data['data']?['exists'] ?? false,
        'needsOnboarding': data['data']?['needsOnboarding'] ?? true,
        'hasWalletPassword': data['data']?['hasWalletPassword'] ?? false,
        'hasPin': data['data']?['hasPin'] ?? false,
        'profileComplete': data['data']?['profileComplete'] ?? false,
        'userData': data['data']?['userData'],
        'error': data['error'],
      };
    } catch (e) {
      print('[CloudFunctions] checkUserExists error: $e');
      // Return default values on error - will proceed with normal flow
      return {
        'success': false,
        'exists': false,
        'needsOnboarding': true,
        'hasWalletPassword': false,
        'hasPin': false,
        'profileComplete': false,
        'error': e.toString(),
      };
    }
  }
}


