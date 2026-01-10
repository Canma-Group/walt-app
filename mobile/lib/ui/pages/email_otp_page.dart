import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/theme.dart';

class EmailOtpPage extends StatefulWidget {
  const EmailOtpPage({Key? key}) : super(key: key);

  @override
  State<EmailOtpPage> createState() => _EmailOtpPageState();
}

class _EmailOtpPageState extends State<EmailOtpPage> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool _isOtpSent = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: blackColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Email Verification',
          style: blackTextStyle.copyWith(
            fontSize: 18,
            fontWeight: semiBold,
          ),
        ),
      ),
      body: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              _buildHeader(),
              const SizedBox(height: 40),
              if (!_isOtpSent) _buildEmailInput() else _buildOtpInput(),
              const SizedBox(height: 30),
              _buildActionButton(),
              if (_isOtpSent) ...[
                const SizedBox(height: 20),
                _buildResendTimer(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: blueColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.alternate_email,
            size: 32,
            color: blueColor,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isOtpSent ? 'Check Your Email' : 'Enter Email Address',
          style: blackTextStyle.copyWith(
            fontSize: 26,
            fontWeight: bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isOtpSent 
            ? 'We\'ve sent a verification code to ${_emailController.text}'
            : 'We\'ll send you a secure verification code',
          style: greyTextStyle.copyWith(
            fontSize: 15,
            fontWeight: regular,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email Address',
          style: blackTextStyle.copyWith(
            fontSize: 14,
            fontWeight: semiBold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: whiteColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: greyColor.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: blackTextStyle.copyWith(
              fontSize: 16,
              fontWeight: medium,
            ),
            decoration: InputDecoration(
              hintText: 'your.email@example.com',
              hintStyle: greyTextStyle.copyWith(fontSize: 16),
              prefixIcon: Icon(Icons.email_outlined, color: blueColor),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verification Code',
          style: blackTextStyle.copyWith(
            fontSize: 14,
            fontWeight: semiBold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: whiteColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: greyColor.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
          child: TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: blackTextStyle.copyWith(
              fontSize: 20,
              fontWeight: bold,
              letterSpacing: 4,
            ),
            decoration: InputDecoration(
              hintText: '000000',
              hintStyle: greyTextStyle.copyWith(
                fontSize: 20,
                letterSpacing: 4,
              ),
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : (_isOtpSent ? _verifyOtp : _sendOtp),
        style: ElevatedButton.styleFrom(
          backgroundColor: blueColor,
          foregroundColor: whiteColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isLoading
          ? CircularProgressIndicator(color: whiteColor, strokeWidth: 2)
          : Text(
              _isOtpSent ? 'Verify & Continue' : 'Send Verification Code',
              style: whiteTextStyle.copyWith(
                fontSize: 16,
                fontWeight: semiBold,
              ),
            ),
      ),
    );
  }

  Widget _buildResendTimer() {
    return Center(
      child: TextButton(
        onPressed: () => _sendOtp(),
        child: Text(
          'Didn\'t receive code? Resend',
          style: blueTextStyle.copyWith(
            fontSize: 14,
            fontWeight: medium,
          ),
        ),
      ),
    );
  }

  // Email Auth Methods
  Future<void> _sendOtp() async {
    if (_emailController.text.trim().isEmpty || !_emailController.text.contains('@')) {
      _showSnackBar('Please enter a valid email address', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      // TODO: Implement Email OTP via Firebase or custom service
      await Future.delayed(const Duration(seconds: 2)); // Simulate API call
      
      setState(() {
        _isOtpSent = true;
        _isLoading = false;
      });
      
      HapticFeedback.lightImpact();
      _showSnackBar('Verification code sent to your email!');
      
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Failed to send verification code: $e', isError: true);
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().length != 6) {
      _showSnackBar('Please enter 6-digit verification code', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      // TODO: Implement OTP verification
      await Future.delayed(const Duration(seconds: 2)); // Simulate API call
      
      HapticFeedback.lightImpact();
      Navigator.pushReplacementNamed(context, '/onboarding');
      
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Invalid verification code. Please try again.', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? redColor : blueColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
