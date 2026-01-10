import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'bank_wallet_screen.dart';
import 'currency_settings_page.dart';
import 'language_settings_page.dart';
import 'low_balance_alert_page.dart';
import 'notification_settings_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  // IMPORTANT: Per requirement, all icons on this screen must come ONLY from:
  // assets/icons/ProfileUsers/
  static const String _iconBase = 'assets/icons/ProfileUsers/';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppLanguage _language = AppLanguage.english;
  AppCurrency _currency = AppCurrency.usd;
  bool _lowBalanceEnabled = true;
  int _lowBalanceThreshold = 30;
  
  // User profile data from Firebase
  String? _profilePhotoUrl;
  String? _userName;
  bool _isLoadingProfile = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoadingProfile = true);
    
    try {
      // Get wallet address from AuthBloc (same approach as HomePage)
      final authState = context.read<AuthBloc>().state;
      String? walletAddress;
      
      if (authState is AuthSuccess) {
        walletAddress = authState.user.walletAddress;
      } else if (authState is AuthNeedsWalletVerification) {
        walletAddress = authState.user.walletAddress;
      }
      
      if (walletAddress != null && walletAddress.isNotEmpty) {
        // Use wallet address as document ID (same as HomePage)
        final docId = walletAddress.toLowerCase();
        print('[ProfileScreen] Loading profile for wallet: $docId');
        
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(docId)
            .get();
        
        if (doc.exists && mounted) {
          final data = doc.data();
          print('[ProfileScreen] Firebase data: $data');
          setState(() {
            _profilePhotoUrl = data?['profile_photo_url'] as String?;
            _userName = data?['name'] as String?;
          });
          print('[ProfileScreen] Loaded photo: $_profilePhotoUrl');
        } else {
          print('[ProfileScreen] Document not found for: $docId');
        }
      } else {
        print('[ProfileScreen] No wallet address found');
      }
    } catch (e) {
      print('[ProfileScreen] Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  void _showUnderDevelopment() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Dalam Pengembangan',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2B83FF),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = size.width / 393;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthInitial || state is AuthFailed) {
          Navigator.pushNamedAndRemoveUntil(context, '/sign-in', (route) => false);
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F8FA),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(s, context),
                
                // Scrollable Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 24 * s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: 20 * s),
                        
                        // Profile Photo
                        _buildProfilePhoto(s),
                        
                        SizedBox(height: 20 * s),
                        
                        // Name (dynamic) - use Firebase data first, fallback to AuthBloc
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            String name = _userName ?? 'User';
                            if (name == 'User' && state is AuthSuccess) {
                              name = state.user.name ??
                                  state.user.email?.split('@')[0] ??
                                  'User';
                            }
                            return Text(
                              name,
                              style: GoogleFonts.poppins(
                                fontSize: 30 * s,
                                color: const Color(0xFF3A3A3A),
                                fontWeight: FontWeight.w400,
                              ),
                            );
                          },
                        ),
                        
                        SizedBox(height: 8 * s),
                        
                        // Email (dynamic)
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            String email = '';
                            if (state is AuthSuccess) {
                              email = state.user.email ?? '';
                            }
                            return Text(
                              email,
                              style: GoogleFonts.poppins(
                                fontSize: 12 * s,
                                color: const Color(0xFF3A3A3A),
                                fontWeight: FontWeight.w400,
                                decoration: TextDecoration.underline,
                              ),
                            );
                          },
                        ),
                        
                        SizedBox(height: 16 * s),
                        
                        // Edit Profile Button
                        _buildEditProfileButton(s),
                        
                        SizedBox(height: 32 * s),
                        
                        // Payment Settings Section
                        _buildSectionTitle('Payment Settings', s),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Bank and Wallet Account', 'Frame-12.svg', s, () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const BankWalletScreen()));
                        }),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Payment Priority', 'Frame-11.svg', s, _showUnderDevelopment),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Low Balance Alert', 'Frame-9.svg', s, () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LowBalanceAlertPage(
                                initialEnabled: _lowBalanceEnabled,
                                initialThreshold: _lowBalanceThreshold,
                                iconBase: ProfileScreen._iconBase,
                                currencySymbol: _currency == AppCurrency.usd ? '\$' : 'Rp',
                              ),
                            ),
                          );

                          // result is a private type in the page file, so treat it dynamically
                          if (result != null && mounted) {
                            setState(() {
                              _lowBalanceEnabled = result.enabled as bool;
                              _lowBalanceThreshold = result.threshold as int;
                            });
                          }
                        }),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Payment Report', 'Frame-8.svg', s, _showUnderDevelopment),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Currency', 'Frame-10.svg', s, () async {
                          final selected = await Navigator.push<AppCurrency>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CurrencySettingsPage(
                                initialValue: _currency,
                                iconBase: ProfileScreen._iconBase,
                              ),
                            ),
                          );
                          if (selected != null && mounted) setState(() => _currency = selected);
                        }),
                        
                        SizedBox(height: 24 * s),
                        
                        // Security Settings Section
                        _buildSectionTitle('Security Settings', s),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Privacy and Security', 'Frame-15.svg', s, _showUnderDevelopment),
                        
                        SizedBox(height: 24 * s),
                        
                        // General Section
                        _buildSectionTitle('General', s),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Mode', 'Frame-7.svg', s, _showUnderDevelopment),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Notification', 'Vector.svg', s, () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotificationSettingsPage(iconBase: ProfileScreen._iconBase),
                            ),
                          );
                        }),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Language', 'Frame-6.svg', s, () async {
                          final selected = await Navigator.push<AppLanguage>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LanguageSettingsPage(
                                initialValue: _language,
                                iconBase: ProfileScreen._iconBase,
                              ),
                            ),
                          );
                          if (selected != null && mounted) setState(() => _language = selected);
                        }),
                        
                        SizedBox(height: 24 * s),
                        
                        // Others Section
                        _buildSectionTitle('Others', s),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Support Center', 'Frame-5.svg', s, _showUnderDevelopment),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Terms and Condition', 'Frame-4.svg', s, _showUnderDevelopment),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Community', 'Frame-2.svg', s, _showUnderDevelopment),
                        SizedBox(height: 10 * s),
                        _buildMenuItem('Privacy Policy', 'Frame-3.svg', s, _showUnderDevelopment),
                        SizedBox(height: 10 * s),
                        _buildLogOutItem(s, context),
                        
                        SizedBox(height: 40 * s),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double s, BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 16 * s),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: SvgPicture.asset(
              '${ProfileScreen._iconBase}Frame-13.svg',
              width: 20 * s,
              height: 24 * s,
              colorFilter: const ColorFilter.mode(
                Color(0xFF1264EF),
                BlendMode.srcIn,
              ),
            ),
          ),
          SizedBox(width: 20 * s),
          Text(
            'Setting',
            style: GoogleFonts.poppins(
              fontSize: 20 * s,
              color: const Color(0xFF1264EF),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePhoto(double s) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Gray circle background (like Figma)
        Container(
          width: 100 * s,
          height: 102 * s,
          decoration: const BoxDecoration(
            color: Color(0xFFD9D9D9),
            shape: BoxShape.circle,
          ),
        ),
        // Profile Photo with rounded rectangle
        Container(
          width: 100 * s,
          height: 107 * s,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20 * s),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20 * s),
            child: _buildProfileImage(s),
          ),
        ),
        
        // Edit Badge
        Positioned(
          bottom: 0,
          right: -5 * s,
          child: GestureDetector(
            onTap: _showUnderDevelopment,
            child: Container(
              width: 25 * s,
              height: 25 * s,
              decoration: const BoxDecoration(
                color: Color(0xFF2B83FF),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  '${ProfileScreen._iconBase}Frame.svg',
                  width: 18 * s,
                  height: 18 * s,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileImage(double s) {
    // Show loading indicator while loading
    if (_isLoadingProfile) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF2B83FF),
          ),
        ),
      );
    }
    
    // Show profile photo from Firebase if available
    if (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty) {
      return Image.network(
        _profilePhotoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildAvatarPlaceholder(s),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.white,
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF2B83FF),
              ),
            ),
          );
        },
      );
    }
    
    // Fallback to placeholder
    return _buildAvatarPlaceholder(s);
  }

  Widget _buildAvatarPlaceholder(double s) {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: Icon(
        Icons.person,
        size: 56 * s,
        color: const Color(0xFFD9D9D9),
      ),
    );
  }

  Widget _buildEditProfileButton(double s) {
    return GestureDetector(
      onTap: _showUnderDevelopment,
      child: Container(
        height: 27 * s,
        width: 132 * s,
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF2B83FF),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20 * s),
        ),
        child: Center(
          child: Text(
            'Edit Profile',
            style: GoogleFonts.poppins(
              fontSize: 10 * s,
              color: const Color(0xFF3A3A3A),
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, double s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 12 * s,
          color: const Color(0xFF3A3A3A),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildMenuItem(String title, String iconName, double s, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42 * s,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30 * s),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: 20 * s),
        child: Row(
          children: [
            // Icon
            SvgPicture.asset(
              '${ProfileScreen._iconBase}$iconName',
              width: 24 * s,
              height: 24 * s,
            ),
            
            SizedBox(width: 14 * s),
            
            // Title
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 12 * s,
                  color: const Color(0xFF3A3A3A),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            
            // Arrow Right
            SvgPicture.asset(
              '${ProfileScreen._iconBase}Frame-14.svg',
              width: 20 * s,
              height: 20 * s,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogOutItem(double s, BuildContext context) {
    return GestureDetector(
      onTap: () {
        _showLogOutDialog(context, s);
      },
      child: Container(
        height: 42 * s,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30 * s),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: 20 * s),
        child: Row(
          children: [
            // Icon
            SvgPicture.asset(
              '${ProfileScreen._iconBase}Frame-1.svg',
              width: 24 * s,
              height: 24 * s,
            ),
            
            SizedBox(width: 14 * s),
            
            // Title
            Expanded(
              child: Text(
                'Log Out',
                style: GoogleFonts.poppins(
                  fontSize: 12 * s,
                  color: const Color(0xFFF44336),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogOutDialog(BuildContext context, double s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20 * s),
        ),
        title: Row(
          children: [
            SvgPicture.asset(
              '${ProfileScreen._iconBase}Frame-1.svg',
              width: 28 * s,
              height: 28 * s,
              colorFilter: const ColorFilter.mode(
                Color(0xFFF44336),
                BlendMode.srcIn,
              ),
            ),
            SizedBox(width: 12 * s),
            Text(
              'Log Out',
              style: GoogleFonts.poppins(
                fontSize: 20 * s,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: GoogleFonts.poppins(
            fontSize: 14 * s,
            color: Colors.grey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              context.read<AuthBloc>().add(AuthLogout());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF44336),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12 * s),
              ),
            ),
            child: Text(
              'Log Out',
              style: GoogleFonts.poppins(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

