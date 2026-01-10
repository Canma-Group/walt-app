import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:banking_app/models/sign_in_form_model.dart';
import 'package:banking_app/models/sign_up_form_model.dart';
import 'package:banking_app/models/user_model.dart';
import 'package:banking_app/services/connection_service.dart';
import 'package:banking_app/services/price_service.dart';
import 'package:banking_app/services/web3auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FieldPath;
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GoogleLoginResult {
  final UserModel user;
  final bool needsOnboarding;
  final bool hasWalletPassword;
  final bool hasPin;
  final bool isReturningUser; // User sudah pernah login sebelumnya
  
  const GoogleLoginResult({
    required this.user,
    required this.needsOnboarding,
    this.hasWalletPassword = false,
    this.hasPin = false,
    this.isReturningUser = false,
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

  /// Helper: Retry Firestore operations with exponential backoff
  Future<T> _retryFirestore<T>(Future<T> Function() operation, {int maxRetries = 3}) async {
    int attempt = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries || !e.toString().contains('unavailable')) {
          rethrow;
        }
        print('[AuthService] Firestore unavailable, retrying in ${attempt * 2}s (attempt $attempt/$maxRetries)');
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  Future<GoogleLoginResult> loginWithGoogle({BuildContext? context}) async {
    try {
      print('[AuthService] Starting Google login flow (Web3Auth first)');
      
      // Check internet connection first
      final connectionService = ConnectionService();
      final hasInternet = await connectionService.hasInternetConnection();
      
      if (!hasInternet && context != null) {
        print('[AuthService] No internet connection detected');
        connectionService.showConnectionErrorDialog(
          context,
          message: 'Internet connection is required to login with Google and generate your wallet.',
        );
        throw Exception('No internet connection. Google login requires internet access.');
      }
      
      // ============================================================
      // STEP 1: Web3Auth Google Login FIRST (user picks account ONCE)
      // ============================================================
      final web3AuthService = Web3AuthService();
      String walletAddress = '';
      String? userEmail;
      String? userName;
      String? userPhoto;

      print('[AuthService] Step 1: Web3Auth Google login (single account picker)');

      try {
        final web3AuthResult = await web3AuthService.loginWithGoogle();

        final success = web3AuthResult['success'] as bool? ?? false;
        walletAddress = web3AuthResult['walletAddress'] as String? ?? '';
        
        // Get user info from Web3Auth
        final userInfo = web3AuthResult['userInfo'] as Map<String, dynamic>?;
        userEmail = userInfo?['email'] as String?;
        userName = userInfo?['name'] as String?;
        userPhoto = userInfo?['profileImage'] as String?;

        if (!success || walletAddress.isEmpty) {
          print('[AuthService] Web3Auth login failed: $web3AuthResult');
          if (context != null) {
            connectionService.showWeb3AuthErrorDialog(
              context,
              'Failed to generate wallet with Web3Auth',
            );
          }
          throw Exception('Web3Auth login failed');
        }

        print('[AuthService] Web3Auth login successful');
        print('[AuthService] - Wallet: $walletAddress');
        print('[AuthService] - Email: $userEmail');
        print('[AuthService] - Name: $userName');
        
        // CRITICAL FIX: Check if this email already exists in Firestore BEFORE Firebase Auth
        // This allows us to completely bypass onboarding for existing users
        Map<String, dynamic>? existingUserData;
        String? existingUserId;
        
        if (userEmail != null && userEmail.isNotEmpty) {
          print('[AuthService] Checking if email $userEmail already exists in Firestore');
          
          try {
            // Check directly in Firestore first
            final db = FirebaseFirestore.instance;
            final querySnapshot = await _retryFirestore(() =>
              db.collection('users').where('email', isEqualTo: userEmail).limit(1).get()
            );
            
            if (querySnapshot.docs.isNotEmpty) {
              existingUserId = querySnapshot.docs.first.id;
              existingUserData = querySnapshot.docs.first.data();
              print('[AuthService] Found existing user with email $userEmail: $existingUserId');
              print('[AuthService] Existing user data: $existingUserData');
            } else {
              print('[AuthService] No existing user found with email $userEmail');
            }
          } catch (e) {
            print('[AuthService] Error checking email in Firestore: $e');
          }
          
          // Also check with Firebase Auth as a backup
          final emailExists = await checkEmailRegistered(userEmail);
          print('[AuthService] Firebase Auth email check: exists=$emailExists');
        }
        
        // If we found existing user data, extract profile information
        if (existingUserData != null) {
          userName = existingUserData['name'] as String? ?? userName;
          userPhoto = existingUserData['profile_photo_url'] as String? ?? userPhoto;
          print('[AuthService] Using existing user data: name=$userName');
        }
      } catch (e) {
        print('[AuthService] Error during Web3Auth login: $e');
        if (context != null) {
          connectionService.showWeb3AuthErrorDialog(context, e.toString());
        }
        rethrow;
      }

      // ============================================================
      // STEP 2: Firebase Auth - Anonymous auth (instant, no picker)
      // ============================================================
      print('[AuthService] Step 2: Firebase Anonymous Auth');
      
      final firebaseAuth = firebase_auth.FirebaseAuth.instance;
      firebase_auth.User? firebaseUser = firebaseAuth.currentUser;
      
      if (firebaseUser == null) {
        // Use Anonymous Auth (no picker, instant)
        print('[AuthService] Creating anonymous Firebase session');
        try {
          final credential = await firebaseAuth.signInAnonymously();
          firebaseUser = credential.user;
          print('[AuthService] Anonymous Firebase auth successful: ${firebaseUser?.uid}');
        } catch (e) {
          print('[AuthService] Anonymous auth failed: $e');
          throw Exception('Firebase authentication failed: $e');
        }
      }

      if (firebaseUser == null) {
        throw Exception('Unable to authenticate with Firebase');
      }

      print('[AuthService] Firebase user authenticated: ${firebaseUser.uid}');
      
      final db = FirebaseFirestore.instance;
      final firebaseUid = firebaseUser.uid;
      final firebaseEmail = firebaseUser.email;
      final userDisplayName = firebaseUser.displayName ?? userName;
      final userPhotoURL = firebaseUser.photoURL ?? userPhoto;
      
      // CRITICAL FIX: Make sure we have a valid wallet address before using as document ID
      if (walletAddress.isEmpty || !walletAddress.startsWith('0x')) {
        // If wallet address is invalid/empty, use Firebase UID as fallback
        print('[AuthService] WARNING: Invalid wallet address - Using Firebase UID instead');
        
        // Safety check before throwing an exception
        throw Exception('Invalid wallet address: $walletAddress. Expected format: 0x...');
      }
      
      // Always normalize wallet address to lowercase for consistency
      final String normalizedWallet = walletAddress.toLowerCase();
      // Use 0x prefix + 40 characters only
      final String docId = normalizedWallet.length >= 42 
          ? normalizedWallet.substring(0, 42) 
          : normalizedWallet;
      
      print('[AuthService] Using wallet-based document ID: $docId');
      
      // Check if document exists for this wallet
      final userDoc = await _retryFirestore(() => db.collection('users').doc(docId).get());
      final bool isReturningUserWithWallet = userDoc.exists;
      
      // First get ALL documents that aren't this one
      final allDocs = await _retryFirestore(() => db.collection('users').get());
      
      // Find ONLY documents with SAME wallet address but different ID (duplicates for THIS user only)
      final duplicateDocs = allDocs.docs.where((doc) {
        if (doc.id == docId) return false; // Skip the current document
        
        final docData = doc.data();
        
        // Get wallet address from document (case insensitive)
        final docWallet = (docData['wallet_address'] as String?)?.toLowerCase() ?? '';
        
        // ONLY delete if document has SAME wallet address (duplicate of current user)
        if (docWallet == normalizedWallet) {
          print('[AuthService] Found duplicate document for same wallet: ${doc.id}');
          return true;
        }
        
        return false;
      }).toList();
      
      if (duplicateDocs.isNotEmpty) {
        print('[AuthService] Found ${duplicateDocs.length} duplicate documents to delete');
        
        for (final doc in duplicateDocs) {
          try {
            print('[AuthService] Deleting duplicate document: ${doc.id}');
            await _retryFirestore(() => db.collection('users').doc(doc.id).delete());
          } catch (e) {
            print('[AuthService] Error deleting duplicate document: $e');
          }
        }
      }
      
      if (isReturningUserWithWallet) {
        // RETURNING USER - Update Firebase UID and fill missing profile data
        print('[AuthService] RETURNING USER - Updating Firebase UID in existing document');
        
        // Get existing data to check what needs to be updated
        final existingData = userDoc.data() ?? {};
        final existingName = existingData['name'] as String?;
        final existingPhoto = existingData['profile_photo_url'] as String?;
        
        // Build update data - always update Firebase UID, conditionally update name/photo if empty
        final updateData = <String, dynamic>{
          'current_firebase_uid': firebaseUid,
          'updated_at': FieldValue.serverTimestamp(),
        };
        
        // Update name if empty in database but available from Google
        if ((existingName == null || existingName.isEmpty) && userDisplayName != null && userDisplayName.isNotEmpty) {
          updateData['name'] = userDisplayName;
          print('[AuthService] Updating empty name to: $userDisplayName');
        }
        
        // Update profile photo if empty in database but available from Google
        if ((existingPhoto == null || existingPhoto.isEmpty) && userPhotoURL != null && userPhotoURL.isNotEmpty) {
          updateData['profile_photo_url'] = userPhotoURL;
          print('[AuthService] Updating empty profile photo');
        }
        
        await _retryFirestore(() => db.collection('users').doc(docId).update(updateData));
        print('[AuthService] Updated existing document with new Firebase UID');
        
        // Also check if private data needs migration to wallet-based ID
        final privateDoc = await _retryFirestore(() => db.collection('user_private').doc(docId).get());
        if (!privateDoc.exists) {
          print('[AuthService] Migrating private data to wallet-based ID');
          
          try {
            // Try to find private data under Firebase UID
            final legacyPrivateDoc = await _retryFirestore(() => db.collection('user_private').doc(firebaseUid).get());
            if (legacyPrivateDoc.exists && legacyPrivateDoc.data() != null) {
              // Copy legacy private data to wallet-based document
              await _retryFirestore(() => db.collection('user_private').doc(docId).set(
                legacyPrivateDoc.data()!,
                SetOptions(merge: true),
              ));
              
              // Delete the old document
              await _retryFirestore(() => db.collection('user_private').doc(firebaseUid).delete());
              print('[AuthService] Migrated private data to wallet-based ID');
            }
          } catch (e) {
            print('[AuthService] Error migrating private data: $e');
          }
        }
      } else {
        // NEW USER - Create document with wallet address as ID
        print('[AuthService] NEW USER - Creating document with wallet address as ID');
        
        // Double-check document doesn't exist before creating (prevent race condition)
        final checkDoc = await _retryFirestore(() => db.collection('users').doc(docId).get());
        if (checkDoc.exists) {
          print('[AuthService] Document already exists (race condition prevented), skipping creation');
        } else {
          // Ensure we have a valid name - fallback chain: displayName -> email prefix -> 'User'
          final String safeName = (userDisplayName != null && userDisplayName.isNotEmpty) 
              ? userDisplayName 
              : (firebaseEmail?.split('@')[0] ?? 'User');
          
          // Use set WITHOUT merge to ensure we create exactly one document
          await _retryFirestore(() => db.collection('users').doc(docId).set({
            'email': firebaseEmail ?? userEmail,
            'name': safeName,
            'profile_photo_url': userPhotoURL,
            'wallet_address': normalizedWallet,  // Always store normalized wallet address
            'current_firebase_uid': firebaseUid,
            'created_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          }));
          print('[AuthService] Created new document: $docId with name: $safeName');
        }
      }
      
      // Use docId (wallet address) as the userId for all operations
      final String userId = docId;
      
      try {
        final userDoc = await _retryFirestore(() => db.collection('users').doc(userId).get());
        final userData = userDoc.data();
        
        print('[AuthService] Fetched user data for $userId: $userData');
        print('[AuthService] Document exists: ${userDoc.exists}');
        
        // Use existing data if available, fallback to Firebase Auth data
        // Handle empty string as null
        final rawName = userData?['name'];
        String userName = (rawName != null && rawName.toString().isNotEmpty) 
            ? rawName.toString() 
            : (firebaseUser.displayName ?? 'User');
        
        String? phoneNumber = userData?['phone_number'];
        
        final rawPhoto = userData?['profile_photo_url'];
        String? profilePhoto = (rawPhoto != null && rawPhoto.toString().isNotEmpty) 
            ? rawPhoto.toString() 
            : firebaseUser.photoURL;
        
        print('[AuthService] Final values - name: $userName, photo: $profilePhoto');

        print('[AuthService] Creating UserModel: name=$userName, email=${firebaseUser.email}, wallet=$walletAddress');

        // Create UserModel - use userId (which may be the existing user's ID)
        final user = UserModel(
          id: userId,
          name: userName,
          phoneNumber: phoneNumber,
          email: firebaseUser.email ?? '',
          username: firebaseUser.email?.split('@')[0] ?? '',
          verified: 1,
          balance: 0,
          profilePicture: profilePhoto,
          walletAddress: walletAddress,  // Add wallet address to UserModel
        );
        
        // For returning users, bypass onboarding completely
        // Check detailed onboarding status - use wallet address as userId
        final onboardingStatus = await _checkOnboardingStatus(
          userId, 
          hasDuplicateWallet: isReturningUserWithWallet, 
          hasDuplicateEmail: false
        );
        
        final needsOnboarding = onboardingStatus['needsOnboarding'] as bool;
        final hasWalletPassword = onboardingStatus['hasWalletPassword'] as bool;
        final hasPin = onboardingStatus['hasPin'] as bool;
        final isReturningUser = onboardingStatus['isReturningUser'] as bool || isReturningUserWithWallet;
        
        print('[AuthService] Login result: '
            'isReturningUser=$isReturningUser, '
            'needsOnboarding=$needsOnboarding, '
            'hasWalletPassword=$hasWalletPassword, '
            'hasPin=$hasPin, '
            'isReturningUserWithWallet=$isReturningUserWithWallet');
        
        // If returning user with same wallet, bypass onboarding completely
        return GoogleLoginResult(
          user: user,
          // If returning user, bypass onboarding
          needsOnboarding: isReturningUserWithWallet ? false : needsOnboarding,
          hasWalletPassword: hasWalletPassword,
          hasPin: hasPin,
          isReturningUser: isReturningUser,
        );
      } catch (e) {
        print('[AuthService] Error accessing Firestore: $e');
        if (context != null) {
          connectionService.showFirebaseErrorDialog(context, 'Error accessing Firestore: $e');
        }
        throw Exception('Error accessing Firestore: $e');
      }
    } catch (e) {
      print('[AuthService] Google login error: $e');
      rethrow;
    }
  }

  /// Returns detailed onboarding status for the user
  Future<Map<String, dynamic>> _checkOnboardingStatus(
    String uid, {
    bool hasDuplicateWallet = false,
    bool hasDuplicateEmail = false,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      String? userEmail;
      bool isEmailInAnotherAccount = false;
      
      // Check user document
      final userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        return {
          'needsOnboarding': true,
          'hasWalletPassword': false,
          'hasPin': false,
          'isReturningUser': false,
        };
      }
      
      final userData = userDoc.data() ?? <String, dynamic>{};
      userEmail = userData['email'] as String?;
      
      // CRITICAL FIX: First check by wallet address, then by email
      // First priority: Wallet address check
      bool isWalletInAnotherAccount = false;
      final userWalletAddress = userData['wallet_address'] as String?;
      
      if (userWalletAddress != null && userWalletAddress.isNotEmpty) {
        try {
          print('[AuthService] In _checkOnboardingStatus: Checking for wallet $userWalletAddress in other accounts');
          // Find accounts with same wallet address
          final usersWithWallet = await db.collection('users')
              .where('wallet_address', isEqualTo: userWalletAddress)
              .where('profile_completed', isEqualTo: true)
              .limit(1)
              .get();
          
          if (usersWithWallet.docs.isNotEmpty && usersWithWallet.docs.first.id != uid) {
            isWalletInAnotherAccount = true;
            print('[AuthService] Found wallet $userWalletAddress in account: ${usersWithWallet.docs.first.id}');
            print('[AuthService] Will bypass onboarding for this wallet');
          }
        } catch (e) {
          print('[AuthService] Error checking wallet in other accounts: $e');
        }
      }
      
      // Second priority: Email check
      if (!isWalletInAnotherAccount && userEmail != null && userEmail.isNotEmpty) {
        try {
          print('[AuthService] In _checkOnboardingStatus: Checking for email $userEmail in other accounts');
          // Find accounts with same email that have completed onboarding
          final usersWithEmail = await db.collection('users')
              .where('email', isEqualTo: userEmail)
              .where('profile_completed', isEqualTo: true)
              .limit(1)
              .get();
          
          if (usersWithEmail.docs.isNotEmpty && usersWithEmail.docs.first.id != uid) {
            isEmailInAnotherAccount = true;
            print('[AuthService] Found email $userEmail in another account: ${usersWithEmail.docs.first.id}');
            print('[AuthService] Will bypass onboarding for this user');
          }
        } catch (e) {
          print('[AuthService] Error checking email in other accounts: $e');
        }
      }
      
      // Check private document - try wallet address first, then uid
      String privateDocId = uid;
      
      // If uid is a wallet address (starts with 0x), use it directly
      // Otherwise, try to get wallet address from user document
      if (!uid.startsWith('0x') && userWalletAddress != null && userWalletAddress.isNotEmpty) {
        privateDocId = userWalletAddress.toLowerCase();
      }
      
      print('[AuthService] Checking user_private with docId: $privateDocId');
      var privateDoc = await db.collection('user_private').doc(privateDocId).get();
      
      // If not found with wallet address, try with uid as fallback
      if (!privateDoc.exists && privateDocId != uid) {
        print('[AuthService] user_private not found with wallet, trying uid: $uid');
        privateDoc = await db.collection('user_private').doc(uid).get();
      }
      
      final privateData = privateDoc.data() ?? <String, dynamic>{};
      
      // Check if required fields exist
      final name = userData['name'] as String?;
      final phoneNumber = userData['phone_number'] as String?;
      final walletAddress = userData['wallet_address'] as String?;
      
      // Check if wallet password is set
      final hasWalletPassword = privateData['wallet_password_hash'] != null && 
                               privateData['wallet_password_salt'] != null;
      
      // Check if PIN is set
      final hasPin = privateData['pin_hash'] != null && 
                    privateData['pin_salt'] != null;
      
      // Check if profile is complete
      final profileComplete = userData['profile_completed'] == true;
      
      // User is returning if they have wallet password and PIN set
      // OR if this wallet/email exists in another account with completed profile
      final isReturningUser = (hasWalletPassword && hasPin) || isEmailInAnotherAccount || isWalletInAnotherAccount;
      
      // CRITICAL FIX: Bypass onboarding completely if wallet or email exists in another account
      // Now also consider the duplicate flags passed in as parameters
      final needsOnboarding = (isEmailInAnotherAccount || isWalletInAnotherAccount || hasDuplicateWallet || hasDuplicateEmail) ? false : (
        !profileComplete ||
        (phoneNumber == null || phoneNumber.isEmpty) ||
        name == null || name.isEmpty ||
        (userWalletAddress == null || userWalletAddress.isEmpty) ||
        !hasWalletPassword ||
        !hasPin
      );
      
      print('[AuthService] Onboarding status: needsOnboarding=$needsOnboarding, '
          'hasWalletPassword=$hasWalletPassword, hasPin=$hasPin, isReturningUser=$isReturningUser, '
          'isEmailInAnotherAccount=$isEmailInAnotherAccount');
      
      return {
        'needsOnboarding': needsOnboarding,
        'hasWalletPassword': hasWalletPassword,
        'hasPin': hasPin,
        'isReturningUser': isReturningUser,
        'isEmailInAnotherAccount': isEmailInAnotherAccount,
      };
    } catch (e) {
      print('[AuthService] Error checking onboarding status: $e');
      return {
        'needsOnboarding': true,
        'hasWalletPassword': false,
        'hasPin': false,
        'isReturningUser': false,
      };
    }
  }
  
  /// Legacy method for backward compatibility
  Future<bool> _checkNeedsOnboarding(String uid) async {
    final status = await _checkOnboardingStatus(uid);
    return status['needsOnboarding'] as bool;
  }

  /// Alias for register() - for backward compatibility
  Future<UserModel> registerWithPassword(SignUpFormModel data) async {
    return register(data);
  }
  
  Future<UserModel> register(SignUpFormModel data) async {
    try {
      // Create Firebase Auth user
      final credential =
          await firebase_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: data.email ?? '',
        password: data.password ?? '',
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
        id: credential.user?.uid ?? '',
        name: data.name ?? '',
        phoneNumber: data.phoneNumber,
        email: data.email,
        username: data.email?.split('@')[0] ?? '',
        verified: 1,
        profilePicture: profilePictureUrl,
        balance: 0,
        token: await credential.user?.getIdToken() ?? '',
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
        email: data.email ?? '',
        password: data.password ?? '',
      );

      final user = await getUserById(credential.user?.uid ?? '');
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
  
  /// Logout with Google (alias for logout)
  Future<void> logoutWithGoogle() async {
    try {
      // Clear all cached data first
      PriceService.clearCache();
      
      // Clear Firestore cache to prevent stale data issues
      try {
        await FirebaseFirestore.instance.terminate();
        await FirebaseFirestore.instance.clearPersistence();
      } catch (e) {
        print('[AuthService] Could not clear Firestore: $e');
        // Continue even if this fails
      }
      
      await logout();
      
      // Also logout from Web3Auth if needed
      final web3AuthService = Web3AuthService();
      await web3AuthService.logout();
      
      // Small delay to allow connections to close properly
      await Future.delayed(const Duration(milliseconds: 300));
      
      print('[AuthService] Logout complete, all caches cleared');
    } catch (e) {
      print('[AuthService] Error during Google logout: $e');
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
        name: data['name'] ?? '',
        email: data['email'],
        phoneNumber: data['phone_number'],
        profilePicture: data['profile_photo_url'],
        verified: data['verified'] == true ? 1 : 0,
        balance: data['balance'] ?? 0,
        cardNumber: data['card_number'],
        pin: data['pin'],
        walletAddress: data['wallet_address'],
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
  
  /// Get current user status (for AuthBloc)
  Future<Map<String, dynamic>> getCurrentUserStatus() async {
    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      
      if (firebaseUser == null) {
        return {
          'isLoggedIn': false,
          'user': null,
        };
      }
      
      try {
        // CRITICAL FIX: User documents may be stored under wallet address, not Firebase UID
        // First try to find user by current_firebase_uid field
        final db = FirebaseFirestore.instance;
        String? userDocId;
        
        // Try direct lookup first (Firebase UID as doc ID)
        final directDoc = await db.collection('users').doc(firebaseUser.uid).get();
        if (directDoc.exists) {
          userDocId = firebaseUser.uid;
          print('[AuthService] Found user by Firebase UID: $userDocId');
        } else {
          // Search by current_firebase_uid field (wallet address as doc ID)
          final querySnapshot = await db.collection('users')
              .where('current_firebase_uid', isEqualTo: firebaseUser.uid)
              .limit(1)
              .get();
          
          if (querySnapshot.docs.isNotEmpty) {
            userDocId = querySnapshot.docs.first.id;
            print('[AuthService] Found user by current_firebase_uid field: $userDocId');
          }
        }
        
        if (userDocId == null) {
          print('[AuthService] No user document found for Firebase UID: ${firebaseUser.uid}');
          return {
            'isLoggedIn': true,
            'user': null,
            'needsOnboarding': true,
          };
        }
        
        final user = await getUserById(userDocId);
        final needsOnboarding = await _checkNeedsOnboarding(userDocId);
        
        return {
          'isLoggedIn': true,
          'user': user,
          'needsOnboarding': needsOnboarding,
        };
      } catch (e) {
        print('[AuthService] Error getting user data: $e');
        return {
          'isLoggedIn': true,
          'user': null,
          'needsOnboarding': true,
          'error': e.toString(),
        };
      }
    } catch (e) {
      print('[AuthService] Error checking user status: $e');
      return {
        'isLoggedIn': false,
        'user': null,
        'error': e.toString(),
      };
    }
  }
  
  /// Get Firebase Auth token for API calls
  Future<String> getToken() async {
    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('User not logged in');
      }
      return await firebaseUser.getIdToken() ?? '';
    } catch (e) {
      print('[AuthService] Error getting token: $e');
      return '';
    }
  }
  
  /// Complete Google onboarding process
  Future<UserModel> completeGoogleOnboarding({
    required String uid,
    required String name,
    required String? phoneNumber,
    String? profilePictureUrl,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      
      // CRITICAL: First, find the existing document for this user
      // Priority 1: Check if uid is already a wallet address (starts with 0x)
      // Priority 2: Find document by current_firebase_uid field
      // Priority 3: Try Web3AuthService
      // Priority 4: Use uid as fallback (NOT RECOMMENDED)
      
      String? docId;
      
      // Priority 1: If uid is already a wallet address
      if (uid.startsWith('0x')) {
        docId = uid.toLowerCase();
        print('[AuthService] completeGoogleOnboarding: uid is wallet address: $docId');
      }
      
      // Priority 2: Find existing document by current_firebase_uid
      if (docId == null) {
        print('[AuthService] completeGoogleOnboarding: Searching for document with current_firebase_uid=$uid');
        final querySnapshot = await db.collection('users')
            .where('current_firebase_uid', isEqualTo: uid)
            .limit(1)
            .get();
        
        if (querySnapshot.docs.isNotEmpty) {
          docId = querySnapshot.docs.first.id;
          print('[AuthService] completeGoogleOnboarding: Found existing document: $docId');
        }
      }
      
      // Priority 3: Try to get wallet address from Web3Auth
      if (docId == null) {
        try {
          final web3Auth = Web3AuthService();
          final walletAddress = web3Auth.walletAddress;
          if (walletAddress != null && walletAddress.isNotEmpty && walletAddress.startsWith('0x')) {
            docId = walletAddress.toLowerCase();
            print('[AuthService] completeGoogleOnboarding: Got wallet from Web3Auth: $docId');
          }
        } catch (e) {
          print('[AuthService] completeGoogleOnboarding: Web3Auth error: $e');
        }
      }
      
      // Priority 4: Last resort - use Firebase UID (should NOT happen normally)
      if (docId == null) {
        print('[AuthService] WARNING: completeGoogleOnboarding falling back to Firebase UID: $uid');
        docId = uid;
      }
      
      print('[AuthService] completeGoogleOnboarding using docId: $docId');

      // Prepare update data
      final data = <String, dynamic>{
        'name': name,
        'phone_number': phoneNumber,
        'profile_completed': true,
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Only update profile photo URL if provided
      if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
        data['profile_photo_url'] = profilePictureUrl;
      }

      // Update the existing document (merge to preserve other fields)
      await db
          .collection('users')
          .doc(docId)
          .set(data, SetOptions(merge: true));
      
      // Get updated user data
      final user = await getUserById(docId);
      return user;
    } catch (e) {
      print('[AuthService] Error completing Google onboarding: $e');
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
    
    // CRITICAL: Always use wallet address as document ID
    // Priority 1: uid is already wallet address
    // Priority 2: Find document by current_firebase_uid and get its ID (wallet address)
    // Priority 3: Get wallet_address field from document
    String? docId;
    
    if (uid.startsWith('0x')) {
      // Already a wallet address
      docId = uid.toLowerCase();
      print('[AuthService] storeWalletPassword: uid is wallet address: $docId');
    } else {
      // Try querying by current_firebase_uid to find the wallet-based document
      try {
        final querySnapshot = await db.collection('users')
            .where('current_firebase_uid', isEqualTo: uid)
            .limit(1)
            .get();
        if (querySnapshot.docs.isNotEmpty) {
          // Use the document ID (which should be wallet address)
          docId = querySnapshot.docs.first.id;
          print('[AuthService] storeWalletPassword: Found document by current_firebase_uid: $docId');
        }
      } catch (e) {
        print('[AuthService] storeWalletPassword: Error querying by current_firebase_uid: $e');
      }
      
      // Fallback: Try direct lookup and get wallet_address field
      if (docId == null) {
        try {
          final userDoc = await db.collection('users').doc(uid).get();
          if (userDoc.exists) {
            final walletAddr = userDoc.data()?['wallet_address'] as String?;
            if (walletAddr != null && walletAddr.isNotEmpty && walletAddr.startsWith('0x')) {
              docId = walletAddr.toLowerCase();
              print('[AuthService] storeWalletPassword: Got wallet from user doc: $docId');
            }
          }
        } catch (e) {
          print('[AuthService] storeWalletPassword: Error getting user doc: $e');
        }
      }
    }
    
    // CRITICAL: Do NOT fallback to Firebase UID - throw error instead
    if (docId == null || !docId.startsWith('0x')) {
      print('[AuthService] ERROR: storeWalletPassword could not find wallet address for uid: $uid');
      throw Exception('Could not find wallet address for user. Please try logging in again.');
    }
    
    print('[AuthService] storeWalletPassword using docId: $docId (from uid: $uid)');
    await db.collection('user_private').doc(docId).set({
      'wallet_password_hash': hash,
      'wallet_password_salt': salt,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> verifyWalletPassword(String walletPassword) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) throw Exception('User not found');
    final db = FirebaseFirestore.instance;
    
    print('[AuthService] verifyWalletPassword - Firebase UID: ${firebaseUser.uid}');
    
    // Try to get wallet address from Web3Auth first
    String? walletAddress;
    try {
      final web3Auth = Web3AuthService();
      walletAddress = web3Auth.walletAddress?.toLowerCase();
      print('[AuthService] Web3Auth wallet address: $walletAddress');
    } catch (e) {
      print('[AuthService] Error getting Web3Auth wallet: $e');
    }
    
    // CRITICAL FIX: Also try to find user by current_firebase_uid field
    // This handles cases where Web3Auth session is not restored
    String? userDocId;
    Map<String, dynamic> userData = {};
    
    // Strategy 1: Direct lookup by wallet address
    if (walletAddress != null && walletAddress.isNotEmpty) {
      final walletDoc = await db.collection('users').doc(walletAddress).get();
      if (walletDoc.exists) {
        userDocId = walletAddress;
        userData = walletDoc.data() ?? {};
        print('[AuthService] Found user by wallet address: $userDocId');
      }
    }
    
    // Strategy 2: Direct lookup by Firebase UID
    if (userDocId == null) {
      final uidDoc = await db.collection('users').doc(firebaseUser.uid).get();
      if (uidDoc.exists) {
        userDocId = firebaseUser.uid;
        userData = uidDoc.data() ?? {};
        print('[AuthService] Found user by Firebase UID: $userDocId');
      }
    }
    
    // Strategy 3: Query by current_firebase_uid field
    if (userDocId == null) {
      final querySnapshot = await db.collection('users')
          .where('current_firebase_uid', isEqualTo: firebaseUser.uid)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        userDocId = querySnapshot.docs.first.id;
        userData = querySnapshot.docs.first.data();
        print('[AuthService] Found user by current_firebase_uid query: $userDocId');
      }
    }
    
    if (userDocId == null) {
      print('[AuthService] No user document found');
      throw Exception('User not found. Please sign in again.');
    }
    
    // Get wallet address from user doc if we don't have it
    if (walletAddress == null || walletAddress.isEmpty) {
      walletAddress = (userData['wallet_address'] as String?)?.toLowerCase();
      print('[AuthService] Got wallet address from user doc: $walletAddress');
    }
    
    // Try to find user_private document - prefer wallet address
    String privateDocId = walletAddress ?? userDocId;
    print('[AuthService] Looking for user_private with docId: $privateDocId');
    
    var privDoc = await db.collection('user_private').doc(privateDocId).get();
    
    // If not found with wallet address, try userDocId
    if (!privDoc.exists && privateDocId != userDocId) {
      print('[AuthService] user_private not found with wallet, trying userDocId: $userDocId');
      privDoc = await db.collection('user_private').doc(userDocId).get();
    }
    
    // If still not found, try Firebase UID
    if (!privDoc.exists && userDocId != firebaseUser.uid) {
      print('[AuthService] user_private not found with userDocId, trying Firebase UID: ${firebaseUser.uid}');
      privDoc = await db.collection('user_private').doc(firebaseUser.uid).get();
    }
    
    final data = privDoc.data() ?? <String, dynamic>{};
    final hash = data['wallet_password_hash'] as String?;
    final salt = data['wallet_password_salt'] as String?;
    
    print('[AuthService] user_private document exists: ${privDoc.exists}, hasHash: ${hash != null}, hasSalt: ${salt != null}');
    
    // If the current user has password set, verify it
    if (hash != null && salt != null && hash.isNotEmpty && salt.isNotEmpty) {
      final trimmed = walletPassword.trim();
      final combinedTrimmed = [...utf8.encode(trimmed), ...base64Decode(salt)];
      final providedTrimmed = sha256.convert(combinedTrimmed).toString();
      if (providedTrimmed == hash) {
        print('[AuthService] Password verified successfully (trimmed)');
        return true;
      }
      final combinedRaw = [...utf8.encode(walletPassword), ...base64Decode(salt)];
      final providedRaw = sha256.convert(combinedRaw).toString();
      if (providedRaw == hash) {
        print('[AuthService] Password verified successfully (raw)');
        return true;
      }
      
      // Password didn't match
      print('[AuthService] Password verification failed - hash mismatch');
      return false;
    }
    
    // No password set
    print('[AuthService] No wallet password found in user_private');
    throw Exception('Wallet password is not set. Please complete onboarding.');
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
      
      // CRITICAL: Always use wallet address as document ID
      // Priority 1: uid is already wallet address
      // Priority 2: Find document by current_firebase_uid and get its ID (wallet address)
      String? docId;
      
      if (uid.startsWith('0x')) {
        // Already a wallet address
        docId = uid.toLowerCase();
        print('[AuthService] storePIN: uid is wallet address: $docId');
      } else {
        // Try querying by current_firebase_uid to find the wallet-based document
        try {
          final querySnapshot = await db.collection('users')
              .where('current_firebase_uid', isEqualTo: uid)
              .limit(1)
              .get();
          if (querySnapshot.docs.isNotEmpty) {
            // Use the document ID (which should be wallet address)
            docId = querySnapshot.docs.first.id;
            print('[AuthService] storePIN: Found document by current_firebase_uid: $docId');
          }
        } catch (e) {
          print('[AuthService] storePIN: Error querying by current_firebase_uid: $e');
        }
        
        // Fallback: Try direct lookup and get wallet_address field
        if (docId == null) {
          try {
            final userDoc = await db.collection('users').doc(uid).get();
            if (userDoc.exists) {
              final walletAddr = userDoc.data()?['wallet_address'] as String?;
              if (walletAddr != null && walletAddr.isNotEmpty && walletAddr.startsWith('0x')) {
                docId = walletAddr.toLowerCase();
                print('[AuthService] storePIN: Got wallet from user doc: $docId');
              }
            }
          } catch (e) {
            print('[AuthService] storePIN: Error getting user doc: $e');
          }
        }
      }
      
      // CRITICAL: Do NOT fallback to Firebase UID - throw error instead
      if (docId == null || !docId.startsWith('0x')) {
        print('[AuthService] ERROR: storePIN could not find wallet address for uid: $uid');
        throw Exception('Could not find wallet address for user. Please try logging in again.');
      }
      
      print('[AuthService] storePIN using docId: $docId (from uid: $uid)');
      await db.collection('user_private').doc(docId).set({
        'pin_hash': pinHash,
        'pin_salt': salt,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  /// Verify PIN for a wallet address
  Future<bool> verifyPin(String walletAddress, String pin) async {
    try {
      // Validate PIN format
      if (pin.length != 6 || !RegExp(r'^\d{6}$').hasMatch(pin)) {
        return false;
      }

      final docId = walletAddress.toLowerCase();
      final db = FirebaseFirestore.instance;
      
      // Get stored PIN hash and salt from Firestore
      final privateDoc = await db.collection('user_private').doc(docId).get();
      if (!privateDoc.exists) {
        print('[AuthService] verifyPin: No private doc found for $docId');
        return false;
      }

      final data = privateDoc.data();
      final storedHash = data?['pin_hash'] as String?;
      final storedSalt = data?['pin_salt'] as String?;

      if (storedHash == null || storedSalt == null) {
        print('[AuthService] verifyPin: No PIN stored for $docId');
        return false;
      }

      // Hash the provided PIN with the stored salt
      final pinBytes = utf8.encode(pin);
      final saltBytes = base64Decode(storedSalt);
      final combined = [...pinBytes, ...saltBytes];
      final hash = sha256.convert(combined);
      final computedHash = hash.toString();

      // Compare hashes
      final isValid = computedHash == storedHash;
      print('[AuthService] verifyPin: PIN verification ${isValid ? 'successful' : 'failed'} for $docId');
      return isValid;
    } catch (e) {
      print('[AuthService] verifyPin error: $e');
      return false;
    }
  }
}
