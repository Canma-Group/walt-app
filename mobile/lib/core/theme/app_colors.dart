import 'package:flutter/material.dart';

/// Kandidat Wallet Color Palette
/// Neo-Bank Style with Blue gradient accent
class AppColors {
  AppColors._();

  // ============ PRIMARY COLORS (Blue Gradient - Brand Colors) ============
  static const Color primary = Color(0xFF1264EF);      // Main blue #1264EF
  static const Color primaryDark = Color(0xFF0A3989); // Dark blue for contrast
  static const Color secondary = Color(0xFFE8EEF6);   // Light blue tint
  
  // Primary gradient for cards and buttons
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0A3989),  // Dark blue
      Color(0xFF1264EF),  // Main blue  
      Color(0xFF4B8AF5),  // Light blue
    ],
  );
  
  // Card gradient (wallet card style)
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0A3989),  // Dark blue
      Color(0xFF1264EF),  // Main blue
      Color(0xFF4B8AF5),  // Light blue
    ],
  );

  // ============ BACKGROUND COLORS ============
  static const Color background = Color(0xFFF5F7FA);       // Very light grey
  static const Color backgroundDark = Color(0xFF020518);   // Dark mode bg
  static const Color surface = Color(0xFFFFFFFF);          // White for cards
  static const Color surfaceVariant = Color(0xFFF6F8FB);   // Slightly off-white

  // ============ TEXT COLORS ============
  static const Color textPrimary = Color(0xFF14193F);      // Dark blue-black
  static const Color textSecondary = Color(0xFFA4A8AE);    // Grey
  static const Color textOnPrimary = Color(0xFFFFFFFF);    // White text on primary
  static const Color textHint = Color(0xFF757575);         // Hint grey

  // ============ FUNCTIONAL COLORS ============
  static const Color success = Color(0xFF22B07D);  // Green - money in
  static const Color error = Color(0xFFFF2566);    // Red - money out/expense
  static const Color warning = Color(0xFFFFB800);  // Yellow/Orange - warnings
  static const Color info = Color(0xFF53C1F9);     // Blue - info

  // ============ UI ELEMENT COLORS ============
  static const Color divider = Color(0xFFE0E0E0);
  static const Color border = Color(0xFFE8E8E8);
  static const Color disabled = Color(0xFFBDBDBD);
  static const Color shadow = Color(0x1A000000);   // 10% black
  
  // ============ BOTTOM NAV / ICONS ============
  static const Color iconActive = Color(0xFF1264EF);
  static const Color iconInactive = Color(0xFFA4A8AE);
  
  // ============ TRANSACTION COLORS ============
  static const Color transactionIn = Color(0xFF22B07D);   // Same as success
  static const Color transactionOut = Color(0xFFFF2566);  // Same as error
}
