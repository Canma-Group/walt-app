import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

/// Circular Action Button for quick actions (Top Up, Send, Receive, etc.)
class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color? backgroundColor;
  final Color? iconColor;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.backgroundColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? 
        (isActive ? AppColors.primary : AppColors.textSecondary.withOpacity(0.15));
    final icColor = iconColor ?? 
        (isActive ? AppColors.textPrimary : AppColors.textSecondary);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: icColor,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick Actions Grid Widget
class QuickActionsGrid extends StatelessWidget {
  final VoidCallback onTopUp;
  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onHistory;

  const QuickActionsGrid({
    super.key,
    required this.onTopUp,
    required this.onSend,
    required this.onReceive,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          ActionButton(
            icon: Icons.add,
            label: 'Top Up',
            onTap: onTopUp,
            isActive: true,
          ),
          ActionButton(
            icon: Icons.arrow_upward,
            label: 'Send',
            onTap: onSend,
          ),
          ActionButton(
            icon: Icons.arrow_downward,
            label: 'Receive',
            onTap: onReceive,
          ),
          ActionButton(
            icon: Icons.history,
            label: 'History',
            onTap: onHistory,
          ),
        ],
      ),
    );
  }
}
