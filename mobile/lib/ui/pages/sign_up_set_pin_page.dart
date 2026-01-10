import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/models/sign_up_form_model.dart';
import 'package:banking_app/services/auth_service.dart';
import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/shared/shared_methods.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:banking_app/ui/widgets/buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Sign Up Set PIN Page
/// Step 3 of signup: Set PIN for transaction verification
class SignUpSetPINPage extends StatefulWidget {
  final SignUpFormModel data;

  const SignUpSetPINPage({
    Key? key,
    required this.data,
  }) : super(key: key);

  @override
  State<SignUpSetPINPage> createState() => _SignUpSetPINPageState();
}

class _SignUpSetPINPageState extends State<SignUpSetPINPage> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  String? _validatePIN(String? value) {
    if (value == null || value.isEmpty) {
      return 'PIN is required';
    }
    if (value.length != 6) {
      return 'PIN must be 6 digits';
    }
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      return 'PIN must contain only numbers';
    }
    return null;
  }

  String? _validateConfirmPIN(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your PIN';
    }
    if (value != _pinController.text) {
      return 'PINs do not match';
    }
    return null;
  }

  Future<void> _completeSignup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create signup data with PIN
      final signupData = widget.data.copyWith(
        pin: _pinController.text,
      );

      // Register user with Firebase Auth (this will also store PIN)
      final authService = AuthService();
      final user = await authService.registerWithPassword(signupData);

      // Set password verification flag (user baru signup, jadi sudah verified)
      // Tapi untuk security, kita tetap clear flag dan require verification
      // User akan verify password saat pertama kali login
      await PasswordVerificationService().clearPasswordVerification();

      // Trigger success state
      if (mounted) {
        context.read<AuthBloc>().add(AuthRegister(signupData));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showCustomSnackBar(context, 'Signup failed: ${e.toString()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        title: const Text('Set PIN'),
        backgroundColor: lightBackgroundColor,
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthSuccess) {
            // After signup, check password verification
            // Since flag is cleared, user will be redirected to password verification
            final isPasswordVerified = PasswordVerificationService().isPasswordVerified();
            
            if (isPasswordVerified) {
              // Password verified - go to home
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/home',
                (route) => false,
              );
            } else {
              // Password not verified - go to password verification page
              // This ensures user verifies password after signup
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/password-verification',
                (route) => false,
              );
            }
          }
          if (state is AuthFailed) {
            setState(() {
              _isLoading = false;
            });
            showCustomSnackBar(context, state.e);
          }
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 40),
            
            Text(
              'Create PIN',
              style: blackTextStyle.copyWith(
                fontSize: 24,
                fontWeight: semiBold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set a 6-digit PIN to verify transactions',
              style: greyTextStyle.copyWith(
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 40),

            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PIN Field
                  Text(
                    'PIN',
                    style: blackTextStyle.copyWith(
                      fontSize: 16,
                      fontWeight: medium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pinController,
                    obscureText: _obscurePin,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: 'Enter 6-digit PIN',
                      hintStyle: greyTextStyle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: greyColor.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: blueColor),
                      ),
                      filled: true,
                      fillColor: whiteColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePin
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: greyColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePin = !_obscurePin;
                          });
                        },
                      ),
                    ),
                    style: blackTextStyle.copyWith(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: semiBold,
                    ),
                    textAlign: TextAlign.center,
                    validator: _validatePIN,
                  ),

                  const SizedBox(height: 24),

                  // Confirm PIN Field
                  Text(
                    'Confirm PIN',
                    style: blackTextStyle.copyWith(
                      fontSize: 16,
                      fontWeight: medium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPinController,
                    obscureText: _obscureConfirmPin,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: 'Re-enter 6-digit PIN',
                      hintStyle: greyTextStyle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: greyColor.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: blueColor),
                      ),
                      filled: true,
                      fillColor: whiteColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPin
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: greyColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPin = !_obscureConfirmPin;
                          });
                        },
                      ),
                    ),
                    style: blackTextStyle.copyWith(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: semiBold,
                    ),
                    textAlign: TextAlign.center,
                    validator: _validateConfirmPIN,
                    onFieldSubmitted: (_) {
                      if (_formKey.currentState!.validate()) {
                        _completeSignup();
                      }
                    },
                  ),

                  const SizedBox(height: 30),

                  // Security Notice
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: blueColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.security,
                          color: blueColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your PIN is encrypted and stored securely. It will be required for all transactions.',
                            style: blueTextStyle.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Complete Signup Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _completeSignup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blueColor,
                        foregroundColor: whiteColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Complete Signup',
                              style: whiteTextStyle.copyWith(
                                fontSize: 16,
                                fontWeight: semiBold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

