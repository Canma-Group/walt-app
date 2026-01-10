import 'package:banking_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Step 2: Security Setup
/// Clean, modern design with password strength indicator
class SecurityStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController walletPasswordController;
  final TextEditingController pinController;

  const SecurityStep({
    Key? key,
    required this.formKey,
    required this.walletPasswordController,
    required this.pinController,
  }) : super(key: key);

  @override
  State<SecurityStep> createState() => _SecurityStepState();
}

class _SecurityStepState extends State<SecurityStep> {
  bool _obscureWalletPassword = true;
  bool _obscurePin = true;
  bool _isPasswordFocused = false;
  bool _isPinFocused = false;
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _passwordFocusNode.addListener(() {
      setState(() => _isPasswordFocused = _passwordFocusNode.hasFocus);
    });
    _pinFocusNode.addListener(() {
      setState(() => _isPinFocused = _pinFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _passwordFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  // Simple password strength calculation
  int _getPasswordStrength(String password) {
    if (password.isEmpty) return 0;
    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.length >= 8) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
    return strength;
  }

  Color _getStrengthColor(int strength) {
    if (strength <= 1) return redColor;
    if (strength <= 2) return Colors.orange;
    if (strength <= 3) return Colors.amber;
    return greenColor;
  }

  String _getStrengthText(int strength) {
    if (strength <= 1) return 'Weak';
    if (strength <= 2) return 'Fair';
    if (strength <= 3) return 'Good';
    return 'Strong';
  }

  @override
  Widget build(BuildContext context) {
    final passwordStrength = _getPasswordStrength(widget.walletPasswordController.text);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step header
          Text(
            'Security Setup',
            style: blackTextStyle.copyWith(
              fontSize: 22,
              fontWeight: bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Set up your wallet security to protect your assets',
            style: greyTextStyle.copyWith(
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),

          // Security icon - refined
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: primaryBlue.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.shield_outlined,
                size: 42,
                color: primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Form card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: whiteColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: widget.formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wallet Password field
                  Text(
                    'Wallet Password',
                    style: blackTextStyle.copyWith(
                      fontSize: 14,
                      fontWeight: medium,
                      color: _isPasswordFocused ? primaryBlue : blackColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: widget.walletPasswordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _obscureWalletPassword,
                    style: blackTextStyle.copyWith(fontSize: 15),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Create a strong password',
                      hintStyle: greyTextStyle.copyWith(
                        fontSize: 14,
                        color: greyColor.withOpacity(0.6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: whiteColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryBlue, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: redColor),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: redColor, width: 1.5),
                      ),
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        color: _isPasswordFocused ? primaryBlue : greyColor,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscureWalletPassword = !_obscureWalletPassword),
                        icon: Icon(
                          _obscureWalletPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: greyColor,
                          size: 20,
                        ),
                      ),
                      errorStyle: errorTextStyle.copyWith(fontSize: 12),
                    ),
                    validator: (value) {
                      final v = value ?? '';
                      if (v.isEmpty) return 'Wallet password is required';
                      if (v.length < 6) return 'Minimum 6 characters';
                      return null;
                    },
                  ),
                  // Password strength indicator
                  if (widget.walletPasswordController.text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: passwordStrength / 5,
                              backgroundColor: greyColor.withOpacity(0.15),
                              color: _getStrengthColor(passwordStrength),
                              minHeight: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _getStrengthText(passwordStrength),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: medium,
                            color: _getStrengthColor(passwordStrength),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'This password will be used to access your wallet',
                    style: greyTextStyle.copyWith(
                      fontSize: 12,
                      color: greyColor.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // PIN field
                  Text(
                    'Transaction PIN (6 digits)',
                    style: blackTextStyle.copyWith(
                      fontSize: 14,
                      fontWeight: medium,
                      color: _isPinFocused ? primaryBlue : blackColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: widget.pinController,
                    focusNode: _pinFocusNode,
                    obscureText: _obscurePin,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: blackTextStyle.copyWith(
                      fontSize: 15,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '••••••',
                      hintStyle: greyTextStyle.copyWith(
                        fontSize: 14,
                        letterSpacing: 8,
                        color: greyColor.withOpacity(0.4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: whiteColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryBlue, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: redColor),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: redColor, width: 1.5),
                      ),
                      prefixIcon: Icon(
                        Icons.dialpad_rounded,
                        color: _isPinFocused ? primaryBlue : greyColor,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscurePin = !_obscurePin),
                        icon: Icon(
                          _obscurePin
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: greyColor,
                          size: 20,
                        ),
                      ),
                      errorStyle: errorTextStyle.copyWith(fontSize: 12),
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
                  const SizedBox(height: 8),
                  Text(
                    'This PIN will be used to authorize transactions',
                    style: greyTextStyle.copyWith(
                      fontSize: 12,
                      color: greyColor.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Security tips - lighter, more subtle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: primaryBlue.withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Security Tips',
                      style: primaryTextStyle.copyWith(
                        fontSize: 14,
                        fontWeight: semiBold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSecurityTip('Use letters, numbers, and symbols'),
                _buildSecurityTip('Never share your credentials'),
                _buildSecurityTip('Avoid easily guessable info'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: greyTextStyle.copyWith(
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
