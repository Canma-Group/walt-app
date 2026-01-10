import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Password Verification Service
/// Manages password verification state (in-memory flag, cleared on app close)
/// 
/// Security:
/// - Verification flag is stored in memory only (cleared on app close)
/// - Optional: Use FlutterSecureStorage for app restart detection
class PasswordVerificationService {
  static final PasswordVerificationService _instance = PasswordVerificationService._internal();
  factory PasswordVerificationService() => _instance;
  PasswordVerificationService._internal();

  final _storage = const FlutterSecureStorage();
  
  // In-memory flag (cleared on app close)
  bool _isPasswordVerified = false;
  
  // Storage key for session persistence (optional)
  static const String _sessionKey = 'password_verified_session';
  static const String _sessionTimestampKey = 'password_verified_timestamp';

  /// Check if password is already verified in this session
  bool isPasswordVerified() {
    return _isPasswordVerified;
  }

  /// Set password as verified (in-memory only)
  /// Optionally store session timestamp for app restart detection
  Future<void> setPasswordVerified({bool persistSession = false}) async {
    _isPasswordVerified = true;
    
    if (persistSession) {
      // Store session timestamp (for app restart detection)
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      await _storage.write(key: _sessionTimestampKey, value: timestamp);
      await _storage.write(key: _sessionKey, value: 'true');
    }
  }

  /// Clear password verification flag
  /// Called on logout or app close
  Future<void> clearPasswordVerification() async {
    _isPasswordVerified = false;
    
    // Clear stored session
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _sessionTimestampKey);
  }

  /// Check if there's a valid session from previous app run
  /// Returns true if session exists and is recent (within 5 minutes)
  /// This is optional - can be used for "remember me" functionality
  Future<bool> hasValidSession() async {
    try {
      final session = await _storage.read(key: _sessionKey);
      final timestampStr = await _storage.read(key: _sessionTimestampKey);
      
      if (session != 'true' || timestampStr == null) {
        return false;
      }
      
      final timestamp = int.tryParse(timestampStr);
      if (timestamp == null) {
        return false;
      }
      
      final sessionTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final difference = now.difference(sessionTime);
      
      // Session valid for 5 minutes only
      // After that, require password again
      if (difference.inMinutes > 5) {
        await clearPasswordVerification();
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Restore session from storage (if exists and valid)
  /// Called on app start
  Future<void> restoreSession() async {
    if (await hasValidSession()) {
      _isPasswordVerified = true;
    } else {
      _isPasswordVerified = false;
      await clearPasswordVerification();
    }
  }
}

