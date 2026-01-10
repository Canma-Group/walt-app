import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../widgets/common/balance_card.dart';
import '../widgets/common/action_button.dart';
import '../widgets/common/transaction_tile.dart';
import 'receive_screen.dart';
import 'top_up_screen.dart';

/// Home Screen - Main Dashboard
class HomeScreen extends StatefulWidget {
  final String userName;
  final String walletAddress;
  final String balance;

  const HomeScreen({
    super.key,
    this.userName = 'User',
    this.walletAddress = '0x91A1Dc9CEf03BB67DfB181eed683d5Dd94244AAC',
    this.balance = '0.000000',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 0;

  // Mock transactions
  final List<Map<String, dynamic>> _transactions = [
    {
      'title': 'Received LSK',
      'subtitle': 'From 0x8f3A...2c1B',
      'amount': '50.00 LSK',
      'type': TransactionType.incoming,
    },
    {
      'title': 'Sent LSK',
      'subtitle': 'To 0x1a2B...9f4E',
      'amount': '25.50 LSK',
      'type': TransactionType.outgoing,
    },
    {
      'title': 'Top Up',
      'subtitle': 'Via Bank Transfer',
      'amount': '100.00 LSK',
      'type': TransactionType.incoming,
    },
  ];

  void _navigateToTopUp() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TopUpScreen()),
    );
  }

  void _navigateToReceive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiveScreen(walletAddress: widget.walletAddress),
      ),
    );
  }

  void _navigateToSend() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Send screen coming soon')),
    );
  }

  void _navigateToHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History screen coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(),
                
                const SizedBox(height: 24),
                
                // Balance Card
                SizedBox(
                  height: 180,
                  child: BalanceCard(
                    balance: widget.balance,
                    walletAddress: widget.walletAddress,
                    currency: 'LSK',
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Quick Actions
                QuickActionsGrid(
                  onTopUp: _navigateToTopUp,
                  onSend: _navigateToSend,
                  onReceive: _navigateToReceive,
                  onHistory: _navigateToHistory,
                ),
                
                const SizedBox(height: 24),
                
                // Recent Transactions Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Transactions',
                      style: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: _navigateToHistory,
                      child: Text(
                        'View All',
                        style: GoogleFonts.poppins(
                          color: AppColors.primaryDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Transaction List
                ..._transactions.map((tx) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TransactionTile(
                    title: tx['title'],
                    subtitle: tx['subtitle'],
                    amount: tx['amount'],
                    type: tx['type'],
                  ),
                )),
                
                const SizedBox(height: 80), // Space for bottom nav
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Avatar
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Greeting
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back,',
                style: GoogleFonts.poppins(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                widget.userName,
                style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        
        // Notification Bell
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: AppColors.textPrimary,
            onPressed: () {},
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                isActive: _currentNavIndex == 0,
                onTap: () => setState(() => _currentNavIndex = 0),
              ),
              _NavItem(
                icon: Icons.credit_card_rounded,
                label: 'Card',
                isActive: _currentNavIndex == 1,
                onTap: () => setState(() => _currentNavIndex = 1),
              ),
              _NavItem(
                icon: Icons.qr_code_scanner_rounded,
                label: 'Scan',
                isActive: _currentNavIndex == 2,
                onTap: () => setState(() => _currentNavIndex = 2),
                isCenter: true,
              ),
              _NavItem(
                icon: Icons.send_rounded,
                label: 'Send',
                isActive: _currentNavIndex == 3,
                onTap: () => setState(() => _currentNavIndex = 3),
              ),
              _NavItem(
                icon: Icons.person_rounded,
                label: 'Profile',
                isActive: _currentNavIndex == 4,
                onTap: () => setState(() => _currentNavIndex = 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isCenter;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isCenter = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCenter) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 28,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? AppColors.iconActive : AppColors.iconInactive,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isActive ? AppColors.iconActive : AppColors.iconInactive,
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
