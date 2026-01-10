import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:banking_app/ui/pages/home_page.dart';
import 'package:banking_app/ui/pages/onboarding/onboarding_main_page.dart';
import 'package:banking_app/ui/pages/password_verification_page.dart';
import 'package:banking_app/ui/pages/sign_in_page.dart';
import 'package:banking_app/ui/pages/splash_page.dart';
import 'package:banking_app/ui/pages/wallet_test_page.dart';
import 'package:banking_app/ui/pages/multi_auth_page.dart';
import 'package:banking_app/ui/widgets/auth_guard.dart';
import 'package:banking_app/ui/widgets/connection_status_widget.dart';
import 'package:banking_app/debug/web3auth_debug_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// Cleanup Firebase documents to enforce wallet-address-only document IDs
Future<void> _cleanupFirebaseDocuments() async {
  final db = FirebaseFirestore.instance;
  final usersCollection = await db.collection('users').get();
  
  // Identify and delete Firebase UID documents (not wallet addresses)
  for (final doc in usersCollection.docs) {
    final docId = doc.id;
    final docData = doc.data();
    final walletAddress = (docData['wallet_address'] as String?)?.toLowerCase() ?? '';
    
    // Is this a Firebase UID document? (not starting with 0x)
    if (!docId.startsWith('0x') && walletAddress.isNotEmpty && walletAddress.startsWith('0x')) {
      debugPrint('🧹 Deleting Firebase UID document: $docId with wallet: $walletAddress');
      
      try {
        // Copy data to wallet-based document if it doesn't exist
        final walletDoc = await db.collection('users').doc(walletAddress).get();
        if (!walletDoc.exists) {
          await db.collection('users').doc(walletAddress).set(docData);
          debugPrint('✅ Created wallet-based document: $walletAddress');
        }
        
        // Delete the Firebase UID document
        await db.collection('users').doc(docId).delete();
        debugPrint('🗑️ Deleted Firebase UID document: $docId');
      } catch (e) {
        debugPrint('❌ Error processing document $docId: $e');
      }
    }
  }
  
  // Also cleanup user_private collection
  final privateCollection = await db.collection('user_private').get();
  for (final doc in privateCollection.docs) {
    final docId = doc.id;
    if (!docId.startsWith('0x')) {
      // Try to find a matching wallet address in users collection
      final userDocs = await db.collection('users')
          .where('current_firebase_uid', isEqualTo: docId)
          .limit(1)
          .get();
      
      if (userDocs.docs.isNotEmpty) {
        final userData = userDocs.docs.first.data();
        final walletAddress = (userData['wallet_address'] as String?)?.toLowerCase() ?? '';
        
        if (walletAddress.isNotEmpty) {
          // Copy private data to wallet-based document
          await db.collection('user_private').doc(walletAddress).set(doc.data());
          debugPrint('✅ Migrated private data to wallet ID: $walletAddress');
          
          // Delete the Firebase UID document
          await db.collection('user_private').doc(docId).delete();
          debugPrint('🗑️ Deleted private Firebase UID document: $docId');
        }
      }
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with platform-specific options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Ensure online-only mode for Firestore
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false, // Disable offline persistence
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    debugPrint('Firestore configured for online-only mode');
    
    // NOTE: Cleanup disabled - allow both wallet address and Firebase UID documents
    // The Firebase rules now allow both formats
    // try {
    //   await _cleanupFirebaseDocuments();
    // } catch (e) {
    //   debugPrint('Error cleaning up Firebase documents: $e');
    // }
    
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    // If Firebase is already initialized, catch the error
    // This can happen during hot reload
    debugPrint('Firebase initialization: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Clear password verification on app start
    // User must verify password again after opening app
    // This ensures security - password verification required every time
    PasswordVerificationService().clearPasswordVerification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Clear password verification when app is paused or detached
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.detached) {
      // App is going to background or being terminated
      PasswordVerificationService().clearPasswordVerification();
    }
    
    // When app resumes, password verification will be required
    // This is handled by AuthGuard and SplashPage
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => AuthBloc(),
        ),
      ],
      child: MaterialApp(
        title: 'Banking App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: lightBackgroundColor,
          primaryColor: primaryColor,
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor,
            primary: primaryColor,
            secondary: secondaryColor,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: whiteColor,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(
              color: blackColor,
            ),
            titleTextStyle: blackTextStyle.copyWith(
              fontSize: 16,
              fontWeight: semiBold,
            ),
          ),
        ),
        builder: (context, child) {
          // Wrap the entire app with ConnectionStatusWidget
          return ConnectionStatusWidget(child: child!);
        },
        routes: {
          '/': (context) => const SplashPage(),
          '/sign-in': (context) => const SignInPage(),
          '/onboarding': (context) => const OnboardingMainPage(),
          '/password-verification': (context) => const PasswordVerificationPage(),
          '/home': (context) => AuthGuard(
                requirePasswordVerified: true,
                child: const HomePage(),
              ),
          '/wallet-test': (context) => AuthGuard(
                requirePasswordVerified: true,
                child: const WalletTestPage(),
              ),
          '/debug-web3auth': (context) => const Web3AuthDebugPage(),
          '/multi-auth': (context) => const MultiAuthPage(),
        },
        initialRoute: '/',
      ),
    );
  }
}
