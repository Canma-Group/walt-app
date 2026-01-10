import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/theme.dart';
import '../../blocs/auth/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MultiAuthPage extends StatefulWidget {
  const MultiAuthPage({Key? key}) : super(key: key);

  @override
  State<MultiAuthPage> createState() => _MultiAuthPageState();
}

class _MultiAuthPageState extends State<MultiAuthPage> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );

    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _slideController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              lightBackgroundColor,
              whiteColor,
              lightBackgroundColor.withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 60),
                    _buildHeader(),
                    const SizedBox(height: 50),
                    Expanded(
                      child: _buildAuthOptions(),
                    ),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome Back! 👋',
          style: blackTextStyle.copyWith(
            fontSize: 28,
            fontWeight: bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose your preferred way to continue',
          style: greyTextStyle.copyWith(
            fontSize: 16,
            fontWeight: regular,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthOptions() {
    return Column(
      children: [
        // Gmail Option
        _buildAuthButton(
          icon: Icons.email_outlined,
          title: 'Continue with Gmail',
          subtitle: 'Quick & secure Google login',
          gradient: LinearGradient(
            colors: [redColor.withOpacity(0.1), redColor.withOpacity(0.05)],
          ),
          iconColor: redColor,
          onTap: () => _handleGoogleLogin(),
        ),
      ],
    );
  }

  Widget _buildAuthButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Gradient gradient,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: gradient,
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: blackTextStyle.copyWith(
                          fontSize: 16,
                          fontWeight: semiBold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: greyTextStyle.copyWith(
                          fontSize: 14,
                          fontWeight: regular,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: greyColor,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: greyColor.withOpacity(0.3))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Secure & Protected',
                style: greyTextStyle.copyWith(
                  fontSize: 12,
                  fontWeight: medium,
                ),
              ),
            ),
            Expanded(child: Divider(color: greyColor.withOpacity(0.3))),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'By continuing, you agree to our Terms & Privacy Policy',
          textAlign: TextAlign.center,
          style: greyTextStyle.copyWith(
            fontSize: 12,
            fontWeight: regular,
          ),
        ),
      ],
    );
  }

  // Auth Methods
  void _handleGoogleLogin() {
    HapticFeedback.lightImpact();
    context.read<AuthBloc>().add(const AuthLoginWithGoogle());
  }

  // MetaMask login removed - Gmail is now the only login method
}
