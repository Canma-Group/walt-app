import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/models/sign_up_form_model.dart';
import 'package:banking_app/shared/shared_methods.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:banking_app/ui/pages/sign_up_set_password_page.dart';
import 'package:banking_app/ui/widgets/buttons.dart';
import 'package:banking_app/ui/widgets/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Sign Up Page - Professional registration flow
class SignUpPage extends StatefulWidget {
  const SignUpPage({Key? key}) : super(key: key);

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: _authStateListener,
        builder: (context, state) {
          return SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          _buildBackButton(),
                          const SizedBox(height: 32),
                          _buildHeader(),
                          const SizedBox(height: 32),
                          _buildFormCard(),
                          const SizedBox(height: 24),
                          _buildSignInLink(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _authStateListener(BuildContext context, AuthState state) {
    if (state is AuthFailed) {
      setState(() => _isLoading = false);
      showCustomSnackBar(context, state.e);
    }

    if (state is AuthCheckEmailSuccess) {
      setState(() => _isLoading = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SignUpSetPasswordPage(
            data: SignUpFormModel(
              name: _nameController.text.trim(),
              phoneNumber: _phoneController.text.trim(),
              email: _emailController.text.trim(),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: whiteColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: blackColor,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create Account',
          style: blackTextStyle.copyWith(
            fontSize: 28,
            fontWeight: bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your information to get started',
          style: greyTextStyle.copyWith(
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: whiteColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
            // Progress indicator
            _buildProgressIndicator(),
            const SizedBox(height: 24),
            // Full Name
            CustomFormField(
              title: 'Full Name',
              controller: _nameController,
              prefixIcon: Icons.person_outline,
              hintText: 'Enter your full name',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                if (value.trim().length < 2) {
                  return 'Name must be at least 2 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            // Phone Number
            CustomFormField(
              title: 'Phone Number',
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
              hintText: '+62 or 08xxxxxxxxxx',
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Phone number is required';
                }
                final phone = value.replaceAll(RegExp(r'[\s-]'), '');
                final phoneRegex = RegExp(r'^(\+62|62|0)[0-9]{9,12}$');
                if (!phoneRegex.hasMatch(phone)) {
                  return 'Enter a valid Indonesian phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            // Email Address
            CustomFormField(
              title: 'Email Address',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.email_outlined,
              hintText: 'example@email.com',
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Email is required';
                }
                final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                if (!emailRegex.hasMatch(value)) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            // Continue Button
            CustomFilledButton(
              title: 'Continue',
              isLoading: _isLoading,
              onPressed: _handleContinue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Step 1',
              style: primaryTextStyle.copyWith(
                fontSize: 12,
                fontWeight: semiBold,
              ),
            ),
            Text(
              ' of 3',
              style: greyTextStyle.copyWith(
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: greyColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: greyColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignInLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: greyTextStyle.copyWith(fontSize: 14),
        ),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/sign-in'),
          child: Text(
            'Sign In',
            style: primaryTextStyle.copyWith(
              fontSize: 14,
              fontWeight: semiBold,
            ),
          ),
        ),
      ],
    );
  }

  void _handleContinue() {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      context.read<AuthBloc>().add(AuthCheckEmail(_emailController.text.trim()));
    }
  }
}
