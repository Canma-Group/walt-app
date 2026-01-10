import 'package:banking_app/blocs/auth/auth_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

class BankWalletScreen extends StatelessWidget {
  const BankWalletScreen({super.key});

  String _currentName(BuildContext context) {
    final state = context.read<AuthBloc>().state;
    if (state is AuthSuccess) {
      return state.user.name ?? state.user.email?.split('@')[0] ?? 'User';
    }
    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final s = screenWidth / 393; // Scale factor based on design width

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFFF8F8FA),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: EdgeInsets.all(8 * s),
                        child: Icon(
                          Icons.arrow_back,
                          color: const Color(0xFF1264EF),
                          size: 24 * s,
                        ),
                      ),
                    ),
                    SizedBox(width: 12 * s),
                    Text(
                      'Bank and Wallet Account',
                      style: GoogleFonts.poppins(
                        fontSize: 20 * s,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF1264EF),
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 24 * s),
              
              // Add card or wallet section
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32 * s),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Add card or wallet',
                      style: GoogleFonts.poppins(
                        fontSize: 16 * s,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF1264EF),
                      ),
                    ),
                    Container(
                      width: 35 * s,
                      height: 35 * s,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1264EF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 22 * s,
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 20 * s),
              
              // Cards list
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: 32 * s),
                  children: [
                    // Blue Card
                    _buildWalletCard(
                      s: s,
                      cardColor: const Color(0xFF4162FF),
                      gradientColors: [
                        const Color(0xFF506EFE),
                        const Color(0xFF3A4FB3),
                      ],
                      name: _currentName(context),
                      cardNumber: '2600',
                      balance: '\$ 1,200.82',
                    ),
                    SizedBox(height: 20 * s),
                    
                    // Green Card
                    _buildWalletCard(
                      s: s,
                      cardColor: const Color(0xFF4A915D),
                      gradientColors: [
                        const Color(0xFF57AB6D),
                        const Color(0xFF3A7249),
                      ],
                      name: _currentName(context),
                      cardNumber: '2600',
                      balance: '\$ 1,200.82',
                    ),
                    SizedBox(height: 20 * s),
                    
                    // Grey Card
                    _buildWalletCard(
                      s: s,
                      cardColor: const Color(0xFF767676),
                      gradientColors: [
                        const Color(0xFF9F9F9F),
                        const Color(0xFF737373),
                      ],
                      name: _currentName(context),
                      cardNumber: '2600',
                      balance: '\$ 1,200.82',
                    ),
                    SizedBox(height: 40 * s),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWalletCard({
    required double s,
    required Color cardColor,
    required List<Color> gradientColors,
    required String name,
    required String cardNumber,
    required String balance,
  }) {
    return Container(
      width: 308 * s,
      height: 147 * s,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 * s),
        child: Stack(
          children: [
            // Decorative shapes - Top Right
            Positioned(
              top: -38 * s,
              left: 130 * s,
              child: Transform.rotate(
                angle: -0.375, // ~338 degrees in radians
                child: Container(
                  width: 108 * s,
                  height: 180 * s,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                  ),
                ),
              ),
            ),
            
            // Decorative shapes - Bottom Left
            Positioned(
              top: 54 * s,
              left: -48 * s,
              child: Transform.rotate(
                angle: -0.285, // ~343 degrees in radians
                child: Container(
                  width: 107 * s,
                  height: 172 * s,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(30 * s),
                  ),
                ),
              ),
            ),
            
            // Decorative shapes - Far Right
            Positioned(
              top: -37 * s,
              left: 199 * s,
              child: Transform.rotate(
                angle: -0.357, // ~339 degrees in radians
                child: Container(
                  width: 102 * s,
                  height: 182 * s,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        gradientColors[0].withOpacity(0.9),
                        gradientColors[1],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Card content
            Padding(
              padding: EdgeInsets.all(13 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name label
                  Text(
                    'Name',
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w200,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2 * s),
                  // Name value
                  Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 16 * s,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 12 * s),
                  // Card number with dots
                  Row(
                    children: [
                      _buildDots(s),
                      SizedBox(width: 6 * s),
                      _buildDots(s),
                      SizedBox(width: 6 * s),
                      _buildDots(s),
                      SizedBox(width: 8 * s),
                      Text(
                        cardNumber,
                        style: GoogleFonts.poppins(
                          fontSize: 12 * s,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * s),
                  // Balance
                  Text(
                    'Balance',
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w200,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    balance,
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            // Mastercard circles (top right)
            Positioned(
              top: 14 * s,
              right: 22 * s,
              child: Row(
                children: [
                  Container(
                    width: 30 * s,
                    height: 30 * s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(-15 * s, 0),
                    child: Container(
                      width: 30 * s,
                      height: 30 * s,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Menu button (bottom right)
            Positioned(
              bottom: 14 * s,
              right: 14 * s,
              child: Icon(
                Icons.more_vert,
                color: Colors.white,
                size: 24 * s,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDots(double s) {
    return Row(
      children: List.generate(
        4,
        (index) => Container(
          margin: EdgeInsets.only(right: 2 * s),
          width: 5 * s,
          height: 5 * s,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

