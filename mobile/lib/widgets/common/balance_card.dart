import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

/// Premium Balance Card Widget with gradient background
class BalanceCard extends StatefulWidget {
  final String balance;
  final String currency;
  final String? walletAddress;
  final VoidCallback? onTopUp;
  final VoidCallback? onCopyAddress;

  const BalanceCard({
    super.key,
    required this.balance,
    this.currency = 'LSK',
    this.walletAddress,
    this.onTopUp,
    this.onCopyAddress,
  });

  @override
  State<BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<BalanceCard> {
  bool _isBalanceVisible = true;

  String get _truncatedAddress {
    if (widget.walletAddress == null || widget.walletAddress!.isEmpty) {
      return '';
    }
    final addr = widget.walletAddress!;
    if (addr.length > 12) {
      return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
    }
    return addr;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wallet Address Row
          if (_truncatedAddress.isNotEmpty)
            GestureDetector(
              onTap: () {
                if (widget.walletAddress != null) {
                  Clipboard.setData(ClipboardData(text: widget.walletAddress!));
                  widget.onCopyAddress?.call();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Address copied!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _truncatedAddress,
                          style: GoogleFonts.robotoMono(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.copy,
                          size: 14,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          const Spacer(),
          
          // Balance Label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Balance',
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
                child: Icon(
                  _isBalanceVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white.withOpacity(0.7),
                  size: 20,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Balance Amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _isBalanceVisible ? widget.balance : '••••••',
                  key: ValueKey(_isBalanceVisible),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  widget.currency,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
