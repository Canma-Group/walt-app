import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

enum TransactionType { incoming, outgoing }

/// Transaction Tile Widget for displaying transaction history
class TransactionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final TransactionType type;
  final String? iconAsset;
  final IconData? icon;
  final DateTime? date;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.type,
    this.iconAsset,
    this.icon,
    this.date,
    this.onTap,
  });

  Color get _amountColor =>
      type == TransactionType.incoming ? AppColors.success : AppColors.error;

  String get _amountPrefix =>
      type == TransactionType.incoming ? '+' : '-';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon Container
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _amountColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: icon != null
                    ? Icon(icon, color: _amountColor, size: 24)
                    : iconAsset != null
                        ? Image.asset(iconAsset!, width: 24, height: 24)
                        : Icon(
                            type == TransactionType.incoming
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: _amountColor,
                            size: 24,
                          ),
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            
            // Amount
            Text(
              '$_amountPrefix$amount',
              style: GoogleFonts.poppins(
                color: _amountColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
