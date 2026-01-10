import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:banking_app/services/auth_service.dart';
import 'package:banking_app/services/password_verification_service.dart';
import 'package:banking_app/shared/shared_methods.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:banking_app/ui/pages/onboarding/steps/personal_info_step.dart';
import 'package:banking_app/ui/pages/onboarding/steps/security_step.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Modern multi-step onboarding after Google login
/// Separates form into multiple steps for better UX
class OnboardingMainPage extends StatefulWidget {
  const OnboardingMainPage({Key? key}) : super(key: key);

  @override
  State<OnboardingMainPage> createState() => _OnboardingMainPageState();
}

class _OnboardingMainPageState extends State<OnboardingMainPage> {
  final PageController _pageController = PageController();
  
  // Form controllers
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _walletPasswordController = TextEditingController();
  final _pinController = TextEditingController();

  // Form keys for validation
  final _personalInfoFormKey = GlobalKey<FormState>();
  final _securityFormKey = GlobalKey<FormState>();

  // State variables
  bool _isLoading = false;
  int _currentStep = 0;
  final int _totalSteps = 2;
  
  // Google profile data
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
    _pageController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _walletPasswordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _nextStep() {
    // Validate current step before proceeding
    if (_currentStep == 0) {
      if (!_personalInfoFormKey.currentState!.validate()) return;
    } 
    
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submitOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _submitOnboarding() async {
    // Validate final step
    if (!_securityFormKey.currentState!.validate()) return;

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
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: lightBackgroundColor,
        body: Column(
          children: [
            // Header with gradient
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 24,
                right: 24,
                bottom: 20,
              ),
              decoration: BoxDecoration(
                gradient: primaryGradient,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    'Complete Your Wallet Setup',
                    style: whiteTextStyle.copyWith(
                      fontSize: 20,
                      fontWeight: bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Progress section
                  Row(
                    children: [
                      Text(
                        'Step ${_currentStep + 1} of $_totalSteps',
                        style: whiteTextStyle.copyWith(
                          fontSize: 13,
                          fontWeight: medium,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${((_currentStep + 1) / _totalSteps * 100).toInt()}%',
                          style: whiteTextStyle.copyWith(
                            fontSize: 12,
                            fontWeight: semiBold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_currentStep + 1) / _totalSteps,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      color: Colors.white,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  PersonalInfoStep(
                    formKey: _personalInfoFormKey,
                    nameController: _nameController,
                    phoneController: _phoneController,
                    googlePhotoUrl: _googlePhotoUrl,
                  ),
                  SecurityStep(
                    formKey: _securityFormKey,
                    walletPasswordController: _walletPasswordController,
                    pinController: _pinController,
                  ),
                ],
              ),
            ),
            
            // Navigation buttons - refined
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: whiteColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // Back button
                    if (_currentStep > 0)
                      Expanded(
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: primaryBlue, width: 1.5),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isLoading ? null : _previousStep,
                              borderRadius: BorderRadius.circular(12),
                              child: Center(
                                child: Text(
                                  'Previous',
                                  style: primaryTextStyle.copyWith(
                                    fontSize: 15,
                                    fontWeight: semiBold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    
                    if (_currentStep > 0) const SizedBox(width: 12),
                    
                    // Next/Finish button with gradient
                    Expanded(
                      flex: _currentStep > 0 ? 1 : 1,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: _isLoading ? null : primaryGradient,
                          color: _isLoading ? greyColor.withOpacity(0.3) : null,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _isLoading
                              ? null
                              : [
                                  BoxShadow(
                                    color: primaryBlue.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isLoading ? null : _nextStep,
                            borderRadius: BorderRadius.circular(12),
                            child: Center(
                              child: _isLoading
                                  ? SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(whiteColor),
                                      ),
                                    )
                                  : Text(
                                      _currentStep < _totalSteps - 1 ? 'Next' : 'Finish Setup',
                                      style: whiteTextStyle.copyWith(
                                        fontSize: 15,
                                        fontWeight: semiBold,
                                      ),
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
          ],
        ),
      ),
    );
  }
}
