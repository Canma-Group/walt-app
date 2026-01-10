import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Splash Page - Professional loading screen with gradient background
class SplashPage extends StatefulWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    
    _animationController.forward();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthBloc>().add(const AuthGetCurrentUser());
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: _authStateListener,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primaryBlue,
                primaryBlueMedium,
                primaryBlueAccent,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                // Animated Logo
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      // Logo container with glow effect
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: whiteColor,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: whiteColor.withOpacity(0.3),
                              blurRadius: 40,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 50,
                            color: primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // App name
                      Text(
                        'Walt',
                        style: whiteTextStyle.copyWith(
                          fontSize: 36,
                          fontWeight: bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your Digital Wallet',
                        style: whiteTextStyle.copyWith(
                          fontSize: 13,
                          fontWeight: medium,
                          letterSpacing: 1,
                          color: whiteColor.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                // Loading indicator
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: whiteColor.withOpacity(0.8),
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Securing your wallet...',
                  style: whiteTextStyle.copyWith(
                    fontSize: 13,
                    color: whiteColor.withOpacity(0.7),
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _authStateListener(BuildContext context, AuthState state) {
    if (state is AuthNeedsOnboarding) {
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (route) => false);
      return;
    }

    if (state is AuthNeedsWalletVerification) {
      Navigator.pushNamedAndRemoveUntil(context, '/password-verification', (route) => false);
      return;
    }

    if (state is AuthSuccess) {
      final isPasswordVerified = PasswordVerificationService().isPasswordVerified();
      Navigator.pushNamedAndRemoveUntil(
        context,
        isPasswordVerified ? '/home' : '/password-verification',
        (route) => false,
      );
      return;
    }

    if (state is AuthFailed || state is AuthInitial) {
      Navigator.pushNamedAndRemoveUntil(context, '/sign-in', (route) => false);
    }
  }
}
