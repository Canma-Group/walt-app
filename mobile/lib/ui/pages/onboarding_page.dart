import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/services/auth_service.dart';
import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/shared/shared_methods.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:banking_app/ui/widgets/buttons.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Wallet onboarding after Google login (only when user profile is missing/incomplete)
/// Required fields:
/// 1) phone number, 2) full name, 3) wallet password, 4) wallet PIN
/// Profile photo: uses Google photo by default (no upload needed)
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({Key? key}) : super(key: key);

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _walletPasswordController = TextEditingController();
  final _pinController = TextEditingController();

  bool _isLoading = false;
  bool _obscureWalletPassword = true;
  bool _obscurePin = true;
  
  // Google profile photo URL (from Firebase Auth)
  String? _googlePhotoUrl;
  String? _googleDisplayName;

  @override
  void initState() {
    super.initState();
    // Pre-populate from Google account
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      _googlePhotoUrl = firebaseUser.photoURL;
      _googleDisplayName = firebaseUser.displayName;
      if (_googleDisplayName != null && _googleDisplayName!.isNotEmpty) {
        _nameController.text = _googleDisplayName!;
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _walletPasswordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Get current user ID
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) throw Exception('User not logged in');
      
      // Complete onboarding
      await AuthService().completeGoogleOnboarding(
        uid: firebaseUser.uid,
        name: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        profilePictureUrl: _googlePhotoUrl, // Use Google photo URL directly
      );
      
      // Store wallet password and PIN
      await AuthService().storeWalletPassword(firebaseUser.uid, _walletPasswordController.text);
      await AuthService().storePIN(firebaseUser.uid, _pinController.text);

      // User baru: langsung dianggap verified untuk session ini
      await PasswordVerificationService().setPasswordVerified();

      if (!mounted) return;

      // Refresh AuthBloc user state, then go to home
      context.read<AuthBloc>().add(const AuthGetCurrentUser());
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/home',
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // cannot bypass onboarding
      child: Scaffold(
        backgroundColor: lightBackgroundColor,
        appBar: AppBar(
          title: const Text('Complete Your Wallet Setup'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'We need a few details to secure your wallet.',
              style: greyTextStyle,
            ),
            const SizedBox(height: 20),

            // Profile photo (from Google)
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade200,
                  image: _googlePhotoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(_googlePhotoUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _googlePhotoUrl == null
                    ? Icon(Icons.person, size: 50, color: Colors.grey.shade700)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Photo from Google account',
              style: greyTextStyle.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: whiteColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        hintText: '+62xxxxxxxxxxx or 08xxxxxxxxxx',
                      ),
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return 'Phone number is required';
                        final phone = v.replaceAll(RegExp(r'[\s-]'), '');
                        final phoneRegex = RegExp(r'^(\+62|62|0)[0-9]{9,12}$');
                        if (!phoneRegex.hasMatch(phone)) {
                          return 'Invalid phone number format';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Full name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _walletPasswordController,
                      obscureText: _obscureWalletPassword,
                      decoration: InputDecoration(
                        labelText: 'Wallet Password',
                        suffixIcon: IconButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(
                                    () => _obscureWalletPassword =
                                        !_obscureWalletPassword,
                                  ),
                          icon: Icon(_obscureWalletPassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                        ),
                      ),
                      validator: (value) {
                        final v = value ?? '';
                        if (v.isEmpty) return 'Wallet password is required';
                        if (v.length < 6) return 'Minimum 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _pinController,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'PIN Transaksi (6 digits)',
                        suffixIcon: IconButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() => _obscurePin = !_obscurePin),
                          icon: Icon(
                              _obscurePin ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return 'PIN is required';
                        if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                          return 'PIN must be exactly 6 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),
                    CustomFilledButton(
                      title: _isLoading ? 'Please wait...' : 'Finish Setup',
                      onPressed: _isLoading ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
