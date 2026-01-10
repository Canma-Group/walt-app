import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/theme.dart';

class MetamaskAuthPage extends StatefulWidget {
  const MetamaskAuthPage({Key? key}) : super(key: key);

  @override
  State<MetamaskAuthPage> createState() => _MetamaskAuthPageState();
}

class _MetamaskAuthPageState extends State<MetamaskAuthPage> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  
  bool _isConnecting = false;
  bool _isConnected = false;
  String? _walletAddress;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _slideController.forward();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _slideController.dispose();
    _pulseController.dispose();
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
          'Connect Wallet',
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              _buildHeader(),
              const SizedBox(height: 60),
              _buildConnectionStatus(),
              const SizedBox(height: 40),
              _buildActionButton(),
              const SizedBox(height: 30),
              _buildSecurityNote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _isConnecting ? _pulseAnimation.value : 1.0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      purpleColor.withOpacity(0.2),
                      purpleColor.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: purpleColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  size: 48,
                  color: purpleColor,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 30),
        Text(
          'Connect MetaMask',
          style: blackTextStyle.copyWith(
            fontSize: 26,
            fontWeight: bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _isConnected 
            ? 'Wallet connected successfully!'
            : 'Use your existing MetaMask wallet',
          textAlign: TextAlign.center,
          style: greyTextStyle.copyWith(
            fontSize: 15,
            fontWeight: regular,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    if (_isConnected && _walletAddress != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: greenColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: greenColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.check_circle, color: greenColor, size: 32),
            const SizedBox(height: 12),
            Text(
              'Connected',
              style: greenTextStyle.copyWith(
                fontSize: 16,
                fontWeight: semiBold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: whiteColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: greyColor.withOpacity(0.2)),
              ),
              child: Text(
                _formatAddress(_walletAddress!),
                style: blackTextStyle.copyWith(
                  fontSize: 14,
                  fontWeight: medium,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: whiteColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: greyColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            _isConnecting ? Icons.sync : Icons.account_balance_wallet_outlined,
            color: purpleColor,
            size: 40,
          ),
          const SizedBox(height: 16),
          Text(
            _isConnecting ? 'Connecting...' : 'Ready to Connect',
            style: blackTextStyle.copyWith(
              fontSize: 18,
              fontWeight: semiBold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isConnecting 
              ? 'Please approve the connection in MetaMask'
              : 'Tap the button below to connect your MetaMask wallet',
            textAlign: TextAlign.center,
            style: greyTextStyle.copyWith(
              fontSize: 14,
              fontWeight: regular,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (_isConnected) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () => Navigator.pushReplacementNamed(context, '/onboarding'),
          style: ElevatedButton.styleFrom(
            backgroundColor: greenColor,
            foregroundColor: whiteColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: Text(
            'Continue to App',
            style: whiteTextStyle.copyWith(
              fontSize: 16,
              fontWeight: semiBold,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isConnecting ? null : _connectMetaMask,
        style: ElevatedButton.styleFrom(
          backgroundColor: purpleColor,
          foregroundColor: whiteColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isConnecting
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: whiteColor,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Connecting...',
                  style: whiteTextStyle.copyWith(
                    fontSize: 16,
                    fontWeight: semiBold,
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance_wallet, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Connect MetaMask',
                  style: whiteTextStyle.copyWith(
                    fontSize: 16,
                    fontWeight: semiBold,
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildSecurityNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: blueColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: blueColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.security, color: blueColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Security Notice',
                style: blueTextStyle.copyWith(
                  fontSize: 14,
                  fontWeight: semiBold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your wallet keys remain secure in MetaMask. Canma Wallet only accesses your wallet address and requires your approval for transactions.',
            style: greyTextStyle.copyWith(
              fontSize: 12,
              fontWeight: regular,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAddress(String address) {
    if (address.length > 10) {
      return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
    }
    return address;
  }

  // MetaMask Connection Methods
  Future<void> _connectMetaMask() async {
    setState(() => _isConnecting = true);
    
    try {
      // TODO: Implement actual MetaMask connection
      // For now, simulate connection
      await Future.delayed(const Duration(seconds: 3));
      
      // Simulate successful connection
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _walletAddress = '0x742d35Cc6Bb546B79ee8A4D26bCf3c5eC7A5ecBe'; // Example address
      });
      
      HapticFeedback.lightImpact();
      _showSnackBar('MetaMask connected successfully!');
      
    } catch (e) {
      setState(() => _isConnecting = false);
      _showSnackBar('Failed to connect MetaMask: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? redColor : greenColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
