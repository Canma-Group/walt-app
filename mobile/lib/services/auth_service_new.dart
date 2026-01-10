import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:banking_app/models/sign_in_form_model.dart';
import 'package:banking_app/models/sign_up_form_model.dart';
import 'package:banking_app/models/user_model.dart';
import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/services/web3auth_service.dart';
import 'package:banking_app/shared/shared_value.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

class GoogleLoginResult {
  final UserModel user;
  final bool needsOnboarding;
  const GoogleLoginResult({
    required this.user,
    required this.needsOnboarding,
  });
}

class AuthService {
  Future<bool> checkEmail(String email) async {
    try {
      final result = await firebase_auth.FirebaseAuth.instance
          .fetchSignInMethodsForEmail(email);

      if (result.isNotEmpty) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> checkEmailRegistered(String email) async {
    try {
      final result = await firebase_auth.FirebaseAuth.instance
          .fetchSignInMethodsForEmail(email);

      if (result.isNotEmpty) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<GoogleLoginResult> loginWithGoogle() async {
    try {
      // Get Firebase Auth instance
      final firebaseAuth = firebase_auth.FirebaseAuth.instance;
      
      // Get Web3Auth service
      final web3AuthService = Web3AuthService();
      
      // Login with Web3Auth (Google)
      final web3AuthResult = await web3AuthService.login();
      
      if (!web3AuthResult.success) {
        throw Exception('Web3Auth login failed');
      }
      
      // Get Firebase user
      final firebaseUser = firebaseAuth.currentUser;
      
      if (firebaseUser == null) {
        throw Exception('Firebase user not found after Web3Auth login');
      }
      
      // Get wallet address from Web3Auth
      final walletAddress = web3AuthResult.walletAddress;
      
      // Get user data from Firestore
      final db = FirebaseFirestore.instance;
      final userDoc = await db.collection('users').doc(firebaseUser.uid).get();
      
      // Default user name from Firebase Auth
      String userName = firebaseUser.displayName ?? 'User';
      String? phoneNumber;
      
      if (userDoc.exists) {
        final userData = userDoc.data();
        userName = userData?['name'] ?? userName;
        phoneNumber = userData?['phone_number'];
      }

      // Create UserModel
      final user = UserModel(
        id: firebaseUser.uid,
        name: userName,
        phoneNumber: phoneNumber,
        email: firebaseUser.email ?? '',
        username: firebaseUser.email?.split('@')[0] ?? '',
        verified: 1,
        profilePicture: firebaseUser.photoURL,
        balance: 0,
        walletAddress: walletAddress,
        token: await firebaseUser.getIdToken(),
      );
      
      // Check if user needs onboarding
      final needsOnboarding = await _checkNeedsOnboarding(firebaseUser.uid);
      
      return GoogleLoginResult(
        user: user,
        needsOnboarding: needsOnboarding,
      );
    } catch (e) {
      print('[AuthService] Google login error: $e');
      rethrow;
    }
  }

  Future<bool> _checkNeedsOnboarding(String uid) async {
    try {
      final db = FirebaseFirestore.instance;
      
      // Check user document
      final userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        return true;
      }
      
      final userData = userDoc.data() ?? <String, dynamic>{};
      
      // Check private document
      final privateDoc = await db.collection('user_private').doc(uid).get();
      final privateData = privateDoc.data() ?? <String, dynamic>{};
      
      // Check if required fields exist
      final name = userData['name'] as String?;
      final phoneNumber = userData['phone_number'] as String?;
      final profilePhotoUrl = userData['profile_photo_url'] as String?;
      final walletAddress = userData['wallet_address'] as String?;
      
      // Check if wallet password is set
      final hasWalletPassword = privateData['wallet_password_hash'] != null && 
                               privateData['wallet_password_salt'] != null;
      
      // Check if PIN is set
      final hasPin = privateData['pin_hash'] != null && 
                    privateData['pin_salt'] != null;
      
      // Check if profile is complete
      final profileComplete = userData['profile_completed'] == true;
      
      // User needs onboarding if any of these are missing
      return !profileComplete ||
          (phoneNumber == null || phoneNumber.isEmpty) ||
          name == null || name.isEmpty ||
          (profilePhotoUrl == null || profilePhotoUrl.isEmpty) ||
          (walletAddress == null || walletAddress.isEmpty) ||
          !hasWalletPassword ||
          !hasPin;
    } catch (e) {
      print('[AuthService] Error checking onboarding status: $e');
      return true; // Default to needing onboarding if there's an error
    }
  }

  Future<UserModel> register(SignUpFormModel data) async {
    try {
      // Create Firebase Auth user
      final credential =
          await firebase_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: data.email,
        password: data.password,
      );

      // Update display name
      await credential.user?.updateDisplayName(data.name);

      // Upload profile picture if provided
      String? profilePictureUrl;
      if (data.profilePicture != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('profile_pictures/${credential.user?.uid}.png');

        await ref.putFile(File(data.profilePicture!));
        profilePictureUrl = await ref.getDownloadURL();

        // Update profile photo URL
        await credential.user?.updatePhotoURL(profilePictureUrl);
      }

      // Create user in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user?.uid)
          .set({
        'name': data.name,
        'email': data.email,
        'phone_number': data.phoneNumber,
        'profile_photo_url': profilePictureUrl,
        'balance': 0,
        'verified': true,
        'profile_completed': true,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Create user model
      final user = UserModel(
        id: credential.user?.uid,
        name: data.name,
        phoneNumber: data.phoneNumber,
        email: data.email,
        username: data.email?.split('@')[0] ?? '',
        verified: 1,
        profilePicture: profilePictureUrl,
        balance: 0,
        token: await credential.user?.getIdToken(),
      );

      return user;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserModel> login(SignInFormModel data) async {
    try {
      final credential =
          await firebase_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: data.email,
        password: data.password,
      );

      final user = await getUserById(credential.user!.uid);
      return user;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await firebase_auth.FirebaseAuth.instance.signOut();
    } catch (e) {
      rethrow;
    }
  }

  Future<UserModel> getUserById(String id) async {
    try {
      final documentSnapshot =
          await FirebaseFirestore.instance.collection('users').doc(id).get();

      if (!documentSnapshot.exists) {
        throw Exception('User not found');
      }

      final data = documentSnapshot.data() as Map<String, dynamic>;

      return UserModel(
        id: id,
        name: data['name'],
        email: data['email'],
        phoneNumber: data['phone_number'],
        profilePicture: data['profile_photo_url'],
        verified: data['verified'] == true ? 1 : 0,
        balance: data['balance'] ?? 0,
        cardNumber: data['card_number'],
        pin: data['pin'],
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateUser(UserModel user) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'name': user.name,
        'email': user.email,
        'phone_number': user.phoneNumber,
        'username': user.username,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> storeWalletPassword(String uid, String walletPassword) async {
    final normalized = walletPassword.trim();
    if (normalized.length < 6) {
      throw Exception('Wallet password must be at least 6 characters');
    }
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (i) => random.nextInt(256));
    final salt = base64Encode(saltBytes);
    final combined = [...utf8.encode(normalized), ...base64Decode(salt)];
    final hash = sha256.convert(combined).toString();
    final db = FirebaseFirestore.instance;
    await db.collection('user_private').doc(uid).set({
      'wallet_password_hash': hash,
      'wallet_password_salt': salt,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> verifyWalletPassword(String walletPassword) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) throw Exception('User not found');
    final db = FirebaseFirestore.instance;
    final privDoc = await db.collection('user_private').doc(firebaseUser.uid).get();
    final data = privDoc.data() ?? <String, dynamic>{};
    final hash = data['wallet_password_hash'] as String?;
    final salt = data['wallet_password_salt'] as String?;
    if (hash == null || salt == null || hash.isEmpty || salt.isEmpty) {
      throw Exception('Wallet password is not set. Please complete onboarding.');
    }
    final trimmed = walletPassword.trim();
    final combinedTrimmed = [...utf8.encode(trimmed), ...base64Decode(salt)];
    final providedTrimmed = sha256.convert(combinedTrimmed).toString();
    if (providedTrimmed == hash) return true;
    final combinedRaw = [...utf8.encode(walletPassword), ...base64Decode(salt)];
    final providedRaw = sha256.convert(combinedRaw).toString();
    return providedRaw == hash;
  }

  Future<void> storePIN(String uid, String pin) async {
    try {
      // Validate PIN (6 digits)
      if (pin.length != 6 || !RegExp(r'^\d{6}$').hasMatch(pin)) {
        throw Exception('PIN must be 6 digits');
      }

      // Generate random salt
      final random = Random.secure();
      final saltBytes = List<int>.generate(16, (i) => random.nextInt(256));
      final salt = base64Encode(saltBytes);

      // Hash PIN with salt (SHA-256)
      final pinBytes = utf8.encode(pin);
      final saltBytesDecoded = base64Decode(salt);
      final combined = [...pinBytes, ...saltBytesDecoded];
      final hash = sha256.convert(combined);
      final pinHash = hash.toString();

      // Store in FlutterSecureStorage (local, encrypted)
      const storage = FlutterSecureStorage();
      await storage.write(key: 'user_pin', value: pin);

      // Store hash and salt in Firestore (backend) - private doc
      final db = FirebaseFirestore.instance;
      await db.collection('user_private').doc(uid).set({
        'pin_hash': pinHash,
        'pin_salt': salt,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }
}
