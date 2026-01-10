import 'package:banking_app/models/sign_up_form_model.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:banking_app/ui/pages/sign_up_set_photo_page.dart';
import 'package:banking_app/ui/widgets/buttons.dart';
import 'package:flutter/material.dart';

/// Sign Up Set Password Page
/// Step 2 of signup: Set password for Firebase Auth
class SignUpSetPasswordPage extends StatefulWidget {
  final SignUpFormModel data;

  const SignUpSetPasswordPage({
    Key? key,
    required this.data,
  }) : super(key: key);

  @override
  State<SignUpSetPasswordPage> createState() => _SignUpSetPasswordPageState();
}

class _SignUpSetPasswordPageState extends State<SignUpSetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _passwordStrength;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*[0-9])').hasMatch(value)) {
      return 'Password must contain letters and numbers';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  void _checkPasswordStrength(String password) {
    if (password.length < 8) {
      setState(() => _passwordStrength = null);
      return;
    }

    int strength = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;

    if (strength <= 2) {
      setState(() => _passwordStrength = 'Weak');
    } else if (strength == 3) {
      setState(() => _passwordStrength = 'Medium');
    } else {
      setState(() => _passwordStrength = 'Strong');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        title: const Text('Set Password'),
        backgroundColor: lightBackgroundColor,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 40),
          
          Text(
            'Create Password',
            style: blackTextStyle.copyWith(
              fontSize: 24,
              fontWeight: semiBold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a strong password to secure your account',
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
                // Password Field
                Text(
                  'Password',
                  style: blackTextStyle.copyWith(
                    fontSize: 16,
                    fontWeight: medium,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onChanged: _checkPasswordStrength,
                  decoration: InputDecoration(
                    hintText: 'Enter password (min 8 characters)',
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
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: greyColor,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  style: blackTextStyle.copyWith(fontSize: 16),
                  validator: _validatePassword,
                ),

                // Password Strength Indicator
                if (_passwordStrength != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Strength: ',
                        style: greyTextStyle.copyWith(fontSize: 12),
                      ),
                      Text(
                        _passwordStrength!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: semiBold,
                          color: _passwordStrength == 'Strong'
                              ? greenColor
                              : _passwordStrength == 'Medium'
                                  ? Colors.orange
                                  : redColor,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),

                // Confirm Password Field
                Text(
                  'Confirm Password',
                  style: blackTextStyle.copyWith(
                    fontSize: 16,
                    fontWeight: medium,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    hintText: 'Re-enter password',
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
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: greyColor,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  style: blackTextStyle.copyWith(fontSize: 16),
                  validator: _validateConfirmPassword,
                  onFieldSubmitted: (_) {
                    if (_formKey.currentState!.validate()) {
                      _continue();
                    }
                  },
                ),

                const SizedBox(height: 30),

                // Continue Button
                CustomFilledButton(
                  title: 'Continue',
                  onPressed: _continue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _continue() {
    if (_formKey.currentState!.validate()) {
      // Navigate to Photo setup page (NEW)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SignUpSetPhotoPage(
            data: widget.data.copyWith(
              password: _passwordController.text,
            ),
          ),
        ),
      );
    }
  }
}

