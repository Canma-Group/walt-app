import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Reusable wallet card widget with proper layer structure
class WalletCard extends StatelessWidget {
  final String name;
  final String cardNumber;
  final String balance;
  final String totalBalance;
  final String currency;
  final bool isVisible;
  final double scaleFactor;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onAdd;

  const WalletCard({
    Key? key,
    required this.name,
    required this.cardNumber,
    required this.balance,
    this.totalBalance = '25,867.40',
    this.currency = 'USD',
    this.isVisible = true,
    this.scaleFactor = 1.0,
    this.onToggleVisibility,
    this.onAdd,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = scaleFactor;
    final cardWidth = 326 * s;
    final cardHeight = 201 * s;

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Bottom layer - Teal gradient background
          Positioned(
            left: 3.5 * s,
            top: 41 * s,
            child: Container(
              width: 319 * s,
              height: 153 * s,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF008182), Color(0xFF054243)],
                ),
                borderRadius: BorderRadius.circular(10 * s),
              ),
            ),
          ),

          // Middle layer - Green card
          Positioned(
            left: 42 * s,
            top: 7 * s,
            child: Container(
              width: 250 * s,
              height: 130 * s,
              decoration: BoxDecoration(
                color: const Color(0xFF4A915D),
                borderRadius: BorderRadius.circular(20 * s),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20 * s),
                child: Stack(
                  children: [
                    // Green gradient overlay shapes
                    Positioned(
                      right: -20 * s,
                      top: -40 * s,
                      child: Transform.rotate(
                        angle: -0.37,
                        child: Container(
                          width: 120 * s,
                          height: 200 * s,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF57AB6D).withOpacity(0.6),
                                const Color(0xFF3A7249).withOpacity(0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: EdgeInsets.all(13 * s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Name', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12 * s, fontWeight: FontWeight.w200)),
                          Text(name, style: GoogleFonts.poppins(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.w500)),
                          SizedBox(height: 8 * s),
                          Row(
                            children: [
                              ...List.generate(3, (_) => _buildCardDots(s)),
                              SizedBox(width: 8 * s),
                              Text(cardNumber, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12 * s)),
                            ],
                          ),
                          const Spacer(),
                          Text('Balance', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12 * s, fontWeight: FontWeight.w200)),
                          Text('\$ $balance', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12 * s)),
                        ],
                      ),
                    ),
                    // Mastercard circles
                    Positioned(
                      right: 10 * s,
                      top: 14 * s,
                      child: Row(
                        children: [
                          Container(width: 30 * s, height: 30 * s, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withOpacity(0.7))),
                          Transform.translate(
                            offset: Offset(-10 * s, 0),
                            child: Container(width: 30 * s, height: 30 * s, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orange.withOpacity(0.7))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Top layer - Grey card
          Positioned(
            left: (cardWidth - 271 * s) / 2,
            top: 18 * s,
            child: Container(
              width: 271 * s,
              height: 133 * s,
              decoration: BoxDecoration(
                color: const Color(0xFF767676),
                borderRadius: BorderRadius.circular(20 * s),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20 * s),
                child: Stack(
                  children: [
                    // Grey gradient overlay shapes
                    Positioned(
                      right: -30 * s,
                      top: -40 * s,
                      child: Transform.rotate(
                        angle: -0.37,
                        child: Container(
                          width: 110 * s,
                          height: 200 * s,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF9F9F9F).withOpacity(0.6),
                                const Color(0xFF737373).withOpacity(0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: EdgeInsets.all(13 * s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: GoogleFonts.poppins(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.w500)),
                          SizedBox(height: 8 * s),
                          Row(
                            children: [
                              ...List.generate(3, (_) => _buildCardDots(s)),
                              SizedBox(width: 8 * s),
                              Text(cardNumber, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12 * s)),
                            ],
                          ),
                          const Spacer(),
                          Text('\$ $balance', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12 * s)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Front overlay - Dashed border card with balance
          Positioned(
            left: 18 * s,
            top: 61 * s,
            child: Container(
              width: 290 * s,
              height: 119 * s,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15 * s),
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 2,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(12 * s, 40 * s, 12 * s, 12 * s),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Balance info
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Balance', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14 * s, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4 * s),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              isVisible ? totalBalance : '••••••',
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 22 * s, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(width: 6 * s),
                            Text(currency, style: GoogleFonts.poppins(color: Colors.white, fontSize: 18 * s, fontWeight: FontWeight.w300)),
                          ],
                        ),
                      ],
                    ),
                    // Eye and Add buttons
                    Row(
                      children: [
                        GestureDetector(
                          onTap: onToggleVisibility,
                          child: Container(
                            width: 30 * s,
                            height: 30 * s,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            child: Icon(
                              isVisible ? Icons.visibility : Icons.visibility_off,
                              color: Colors.white,
                              size: 16 * s,
                            ),
                          ),
                        ),
                        SizedBox(width: 8 * s),
                        GestureDetector(
                          onTap: onAdd,
                          child: Container(
                            width: 30 * s,
                            height: 30 * s,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            child: Icon(Icons.add, color: Colors.white, size: 18 * s),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardDots(double s) {
    return Container(
      width: 24 * s,
      height: 24 * s,
      margin: EdgeInsets.only(right: 4 * s),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          4,
          (_) => Container(
            width: 4 * s,
            height: 4 * s,
            margin: EdgeInsets.symmetric(horizontal: 1 * s),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable transaction item widget with glassy background
class TransactionItem extends StatelessWidget {
  final String title;
  final String category;
  final String amount;
  final String? letter;
  final Color? letterColor;
  final String? iconPath;
  final double scaleFactor;

  const TransactionItem({
    Key? key,
    required this.title,
    required this.category,
    required this.amount,
    this.letter,
    this.letterColor,
    this.iconPath,
    this.scaleFactor = 1.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = scaleFactor;

    return Container(
      width: double.infinity,
      height: 58 * s,
      margin: EdgeInsets.only(bottom: 12 * s),
      decoration: BoxDecoration(
        // WHITE TRANSPARENT / GLASSY background
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(50 * s),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 58 * s,
            height: 58 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: letterColor?.withOpacity(0.2) ?? const Color(0xFF757575).withOpacity(0.3),
            ),
            child: Center(
              child: letter != null
                  ? Text(
                      letter!,
                      style: GoogleFonts.poppins(
                        color: letterColor ?? Colors.white,
                        fontSize: 24 * s,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : iconPath != null
                      ? SvgPicture.asset(
                          iconPath!,
                          width: 28 * s,
                          height: 28 * s,
                          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                        )
                      : Icon(Icons.receipt, color: Colors.white, size: 24 * s),
            ),
          ),
          SizedBox(width: 12 * s),
          // Title and subtitle
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFFFFEFE),
                    fontSize: 18 * s,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  category,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFEEEEEE),
                    fontSize: 13 * s,
                    fontWeight: FontWeight.w200,
                  ),
                ),
              ],
            ),
          ),
          // Amount
          Padding(
            padding: EdgeInsets.only(right: 16 * s),
            child: Text(
              amount,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16 * s,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick action button widget
class QuickActionButton extends StatelessWidget {
  final String iconPath;
  final String label;
  final bool isActive;
  final double scaleFactor;
  final VoidCallback? onTap;

  const QuickActionButton({
    Key? key,
    required this.iconPath,
    required this.label,
    this.isActive = false,
    this.scaleFactor = 1.0,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = scaleFactor;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52 * s,
            height: 52 * s,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF08BFC1) : const Color(0x78000000),
              borderRadius: BorderRadius.circular(10 * s),
            ),
            child: Center(
              child: SvgPicture.asset(
                iconPath,
                width: 27 * s,
                height: 27 * s,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
          ),
          SizedBox(height: 8 * s),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: const Color(0xFF4E4E4E),
              fontSize: 13 * s,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}
