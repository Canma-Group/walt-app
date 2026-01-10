import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:banking_app/services/auth_service.dart';

/// Password Verification Page
/// User MUST enter password to continue - cannot bypass
/// 
/// Security:
/// - Password is verified via Firebase Auth
/// - Cannot navigate back or bypass
/// - Auto-focus on password field
class PasswordVerificationPage extends StatefulWidget {
  const PasswordVerificationPage({Key? key}) : super(key: key);

  @override
  State<PasswordVerificationPage> createState() => _PasswordVerificationPageState();
}

class _PasswordVerificationPageState extends State<PasswordVerificationPage> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Auto-focus on password field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(FocusNode());
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          FocusScope.of(context).requestFocus(FocusNode());
        }
      });
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verifyPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final password = _passwordController.text.trim();
      
      // Get current Firebase user
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('User not found. Please sign in again.');
      }

      // Google-only login: verify the WALLET PASSWORD (stored hashed+salt in Firestore user_private)
      final ok = await AuthService().verifyWalletPassword(password);
      if (!ok) {
        setState(() {
          _errorMessage = 'Incorrect wallet password. Please try again.';
          _isLoading = false;
        });
        return;
      }

      // Password verified - set flag
      await PasswordVerificationService().setPasswordVerified();
      
      // Navigate to home
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
          (route) => false,
        );
      }
    } catch (e) {
      final errorMsg = e.toString();
      // Check if password not set - offer to reset
      if (errorMsg.contains('not set') || errorMsg.contains('onboarding')) {
        setState(() {
          _errorMessage = 'Wallet password not found. Please set up a new password.';
          _isLoading = false;
        });
        _showResetPasswordDialog();
      } else {
        setState(() {
          _errorMessage = 'Verifikasi gagal: $errorMsg';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Set New Wallet Password', style: blackTextStyle.copyWith(fontWeight: semiBold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your wallet password was not found. Please set a new password to continue.',
              style: greyTextStyle.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: greyTextStyle),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newPasswordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters')),
                );
                return;
              }
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
            child: Text('Set Password', style: whiteTextStyle),
          ),
        ],
      ),
    );
    
    if (result == true && mounted) {
      setState(() => _isLoading = true);
      try {
        final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
        if (firebaseUser == null) throw Exception('User not found');
        
        // Store the new password
        await AuthService().storeWalletPassword(firebaseUser.uid, newPasswordController.text);
        
        // Also store a default PIN if not exists
        await AuthService().storePIN(firebaseUser.uid, '123456');
        
        // Set password verified
        await PasswordVerificationService().setPasswordVerified();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password set successfully!')),
          );
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'Failed to set password: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
    
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please enter your password to continue',
                style: whiteTextStyle.copyWith(fontSize: 14),
              ),
              backgroundColor: primaryBlue,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: lightBackgroundColor,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Spacer(flex: 1),
                      
                      // Logo with gradient background
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: primaryBlue.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 40,
                            color: whiteColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Title
                      Text(
                        'Wallet Verification',
                        style: blackTextStyle.copyWith(
                          fontSize: 26,
                          fontWeight: bold,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your wallet password to continue',
                        style: greyTextStyle.copyWith(
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 40),

                      // Password Form Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: whiteColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Password Field Label
                              Text(
                                'Wallet Password',
                                style: blackTextStyle.copyWith(
                                  fontSize: 14,
                                  fontWeight: medium,
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Large Password Input
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                enabled: !_isLoading,
                                autofocus: true,
                                style: blackTextStyle.copyWith(fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: 'Enter your password',
                                  hintStyle: greyTextStyle.copyWith(
                                    fontSize: 15,
                                    color: greyColor.withOpacity(0.5),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: primaryBlue, width: 1.5),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: redColor),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: redColor, width: 1.5),
                                  ),
                                  filled: true,
                                  fillColor: whiteColor,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 18,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.lock_outline_rounded,
                                    color: greyColor,
                                    size: 22,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: greyColor,
                                      size: 22,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Password is required';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _verifyPassword(),
                              ),

                              // Error Message
                              if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: redColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: redColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: redColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: redColor,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                              // Large Prominent Verify Button
                              Container(
                                width: double.infinity,
                                height: 58,
                                decoration: BoxDecoration(
                                  gradient: _isLoading ? null : primaryGradient,
                                  color: _isLoading ? greyColor.withOpacity(0.3) : null,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: _isLoading
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: primaryBlue.withOpacity(0.35),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _isLoading ? null : _verifyPassword,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Center(
                                      child: _isLoading
                                          ? SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(whiteColor),
                                              ),
                                            )
                                          : Text(
                                              'Verify & Continue',
                                              style: whiteTextStyle.copyWith(
                                                fontSize: 17,
                                                fontWeight: semiBold,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Security Notice
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryBlue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: primaryBlue.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: primaryBlue,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Your password is securely hashed. We never store plain text passwords.',
                                style: primaryTextStyle.copyWith(
                                  fontSize: 12,
                                  fontWeight: medium,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

