import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../pages/split_bill_page.dart';
import '../pages/near_sync_page.dart';

/// Shows the More menu bottom sheet with additional features
void showMoreMenuSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'More Features',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          _buildMoreMenuItem(
            ctx,
            context,
            icon: Icons.receipt_long,
            label: 'Split Bill',
            subtitle: 'Split payments with friends',
            color: Colors.orange,
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SplitBillPage()));
            },
          ),
          const SizedBox(height: 10),
          _buildMoreMenuItem(
            ctx,
            context,
            icon: Icons.wifi_tethering,
            label: 'Near Sync',
            subtitle: 'Find nearby wallet users',
            color: const Color(0xFF08BFC1),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NearSyncPage()));
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

Widget _buildMoreMenuItem(
  BuildContext sheetContext,
  BuildContext parentContext, {
  required IconData icon,
  required String label,
  required String subtitle,
  required Color color,
  required VoidCallback onTap,
}) {
  return ListTile(
    leading: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    ),
    title: Text(
      label,
      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500),
    ),
    subtitle: Text(
      subtitle,
      style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
    ),
    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
    onTap: onTap,
  );
}
