import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/shared/shared_methods.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Sign In Page - Professional entry point for Google login
class SignInPage extends StatefulWidget {
  const SignInPage({Key? key}) : super(key: key);

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
                'Please sign in to continue',
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
        body: BlocConsumer<AuthBloc, AuthState>(
          listener: _authStateListener,
          builder: (context, state) {
            return SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              const Spacer(flex: 1),
                              _buildHeader(),
                              const SizedBox(height: 48),
                              _buildLoginCard(),
                              const SizedBox(height: 24),
                              _buildSecurityNotice(),
                              const Spacer(flex: 2),
                              _buildFooter(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _authStateListener(BuildContext context, AuthState state) {
    if (state is AuthFailed) {
      setState(() => _isLoading = false);
      showCustomSnackBar(context, state.e);
    }

    if (state is AuthNeedsOnboarding) {
      setState(() => _isLoading = false);
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (route) => false);
    }

    if (state is AuthNeedsWalletVerification) {
      setState(() => _isLoading = false);
      Navigator.pushNamedAndRemoveUntil(context, '/password-verification', (route) => false);
    }

    if (state is AuthSuccess) {
      setState(() => _isLoading = false);
      final isPasswordVerified = PasswordVerificationService().isPasswordVerified();
      Navigator.pushNamedAndRemoveUntil(
        context,
        isPasswordVerified ? '/home' : '/password-verification',
        (route) => false,
      );
    }
  }

  Widget _buildHeader() {
    return Column(
      children: [
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
              Icons.account_balance_wallet_rounded,
              size: 40,
              color: whiteColor,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Welcome Back',
          style: blackTextStyle.copyWith(
            fontSize: 28,
            fontWeight: bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to access your wallet',
          style: greyTextStyle.copyWith(
            fontSize: 15,
            fontWeight: regular,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: whiteColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Large prominent Google Sign In Button
          Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              gradient: _isLoading ? null : primaryGradient,
              color: _isLoading ? greyColor.withOpacity(0.3) : null,
              borderRadius: BorderRadius.circular(16),
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
                onTap: _isLoading ? null : _handleSignIn,
                borderRadius: BorderRadius.circular(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isLoading)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(whiteColor),
                        ),
                      )
                    else ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: whiteColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/icons/ic_google.png',
                            width: 18,
                            height: 18,
                            errorBuilder: (context, error, stackTrace) => Text(
                              'G',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: primaryBlue,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Sign in with Google',
                        style: whiteTextStyle.copyWith(
                          fontSize: 17,
                          fontWeight: semiBold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: greyColor.withOpacity(0.15))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Secure login',
                  style: greyTextStyle.copyWith(fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: greyColor.withOpacity(0.15))),
            ],
          ),
          const SizedBox(height: 20),
          // Security info
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: primaryBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Your wallet will be created securely using Web3Auth technology.',
                  style: greyTextStyle.copyWith(
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityNotice() {
    return Container(
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
              'Protected by industry-standard encryption',
              style: primaryTextStyle.copyWith(
                fontSize: 13,
                fontWeight: medium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'By continuing, you agree to our',
          style: greyTextStyle.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                // TODO: Navigate to Terms
              },
              child: Text(
                'Terms of Service',
                style: primaryTextStyle.copyWith(
                  fontSize: 12,
                  fontWeight: medium,
                ),
              ),
            ),
            Text(
              ' and ',
              style: greyTextStyle.copyWith(fontSize: 12),
            ),
            GestureDetector(
              onTap: () {
                // TODO: Navigate to Privacy
              },
              child: Text(
                'Privacy Policy',
                style: primaryTextStyle.copyWith(
                  fontSize: 12,
                  fontWeight: medium,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleSignIn() {
    setState(() => _isLoading = true);
    context.read<AuthBloc>().add(const AuthLoginWithGoogle());
  }
}
