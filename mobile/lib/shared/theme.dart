import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================
// PRIMARY COLORS - Financial Blue Theme
// ============================================
Color primaryBlue = const Color(0xFF0D47A1);      // Primary Blue (main)
Color primaryBlueMedium = const Color(0xFF1565C0); // Blue Medium
Color primaryBlueAccent = const Color(0xFF1E88E5); // Blue Accent

// ============================================
// BACKGROUND & NEUTRAL COLORS
// ============================================
Color whiteColor = const Color(0xFFFFFFFF);        // Card/Surface
Color blackColor = const Color(0xFF1C1C1E);        // Text Primary
Color greyColor = const Color(0xFF6B7280);         // Text Secondary
Color lightBackgroundColor = const Color(0xFFF2F6FB); // Background Light
Color darkBackgroundColor = const Color(0xFF0D1117);  // Dark Background

// ============================================
// ACCENT COLORS
// ============================================
Color blueColor = const Color(0xFF2979FF);         // Icon/Link
Color redColor = const Color(0xFFE53935);          // Error
Color greenColor = const Color(0xFF43A047);        // Success

// ============================================
// LEGACY COLORS (for backward compatibility)
// ============================================
Color primaryColor = primaryBlue;
Color secondaryColor = primaryBlueMedium;
Color accentColor = primaryBlueAccent;
Color purpleColor = primaryBlue;                   // Map purple to primary blue
Color numberBackgroundColor = const Color(0xFF1A1D2E);

// ============================================
// GRADIENTS
// ============================================
LinearGradient primaryGradient = const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0D47A1), Color(0xFF1E88E5)],
);

LinearGradient cardGradient = const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
);

// ============================================
// TEXT STYLES
// ============================================
TextStyle blackTextStyle = GoogleFonts.poppins(
  color: blackColor,
);

TextStyle whiteTextStyle = GoogleFonts.poppins(
  color: whiteColor,
);

TextStyle greyTextStyle = GoogleFonts.poppins(
  color: greyColor,
);

TextStyle primaryTextStyle = GoogleFonts.poppins(
  color: primaryBlue,
);

TextStyle secondaryTextStyle = GoogleFonts.poppins(
  color: primaryBlueMedium,
);

TextStyle accentTextStyle = GoogleFonts.poppins(
  color: primaryBlueAccent,
);

TextStyle blueTextStyle = GoogleFonts.poppins(
  color: blueColor,
);

TextStyle greenTextStyle = GoogleFonts.poppins(
  color: greenColor,
);

TextStyle errorTextStyle = GoogleFonts.poppins(
  color: redColor,
);

// ============================================
// FONT WEIGHTS
// ============================================
FontWeight light = FontWeight.w300;
FontWeight regular = FontWeight.w400;
FontWeight medium = FontWeight.w500;
FontWeight semiBold = FontWeight.w600;
FontWeight bold = FontWeight.w700;
FontWeight extraBold = FontWeight.w800;
FontWeight black = FontWeight.w900;

// ============================================
// INPUT DECORATION THEME
// ============================================
InputDecoration authInputDecoration({
  required String hintText,
  IconData? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: GoogleFonts.poppins(
      color: greyColor,
      fontSize: 14,
    ),
    prefixIcon: prefixIcon != null
        ? Icon(prefixIcon, color: greyColor, size: 20)
        : null,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: whiteColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: primaryBlue, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: redColor),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: redColor, width: 1.5),
    ),
    errorStyle: GoogleFonts.poppins(
      color: redColor,
      fontSize: 12,
    ),
  );
}

// ============================================
// BUTTON STYLES
// ============================================
ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: primaryBlue,
  foregroundColor: whiteColor,
  elevation: 0,
  padding: const EdgeInsets.symmetric(vertical: 16),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  ),
  textStyle: GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  ),
);

ButtonStyle secondaryButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: whiteColor,
  foregroundColor: primaryBlue,
  elevation: 0,
  padding: const EdgeInsets.symmetric(vertical: 16),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: BorderSide(color: primaryBlue),
  ),
  textStyle: GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  ),
);

ButtonStyle textButtonStyle = TextButton.styleFrom(
  foregroundColor: primaryBlue,
  textStyle: GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  ),
);
