import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppCurrency { usd, idr }

class CurrencySettingsPage extends StatelessWidget {
  const CurrencySettingsPage({
    super.key,
    required this.initialValue,
    this.iconBase = 'assets/icons/ProfileUsers/',
  });

  final AppCurrency initialValue;
  final String iconBase;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size.width / 393;

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
              Padding(
                padding: EdgeInsets.fromLTRB(24 * s, 16 * s, 24 * s, 16 * s),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: SvgPicture.asset(
                        '${iconBase}Frame-13.svg',
                        width: 20 * s,
                        height: 24 * s,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF1264EF),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    SizedBox(width: 16 * s),
                    Text(
                      'Currency',
                      style: GoogleFonts.poppins(
                        fontSize: 20 * s,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF1264EF),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 24 * s),
                  child: Column(
                    children: [
                      SizedBox(height: 16 * s),
                      Container(
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
                        child: Column(
                          children: [
                            _CurrencyRow(
                              s: s,
                              leading: _CurrencyBadge(
                                s: s,
                                text: '\$',
                                bg: const Color(0xFF1F8B5A),
                              ),
                              title: 'USD',
                              subtitle: 'United States Dollar',
                              selected: initialValue == AppCurrency.usd,
                              onTap: () => Navigator.pop(context, AppCurrency.usd),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 18 * s),
                              child: Divider(height: 1, thickness: 1, color: Colors.black.withOpacity(0.08)),
                            ),
                            _CurrencyRow(
                              s: s,
                              leading: _CurrencyBadge(
                                s: s,
                                text: 'Rp',
                                bg: const Color(0xFF6B1F1F),
                              ),
                              title: 'IDR',
                              subtitle: 'Indonesian Rupiah',
                              selected: initialValue == AppCurrency.idr,
                              onTap: () => Navigator.pop(context, AppCurrency.idr),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 40 * s),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.s,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final double s;
  final Widget leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30 * s),
      child: Container(
        height: 64 * s,
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
        child: Row(
          children: [
            leading,
            SizedBox(width: 14 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2B2B2B),
                    ),
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11 * s,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF3A3A3A).withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 20 * s,
              height: 20 * s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1264EF), width: 2),
                color: selected ? const Color(0xFF1264EF) : Colors.transparent,
              ),
              child: selected
                  ? Icon(Icons.check, size: 14 * s, color: Colors.white)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyBadge extends StatelessWidget {
  const _CurrencyBadge({required this.s, required this.text, required this.bg});

  final double s;
  final String text;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38 * s,
      height: 38 * s,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: bg.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 15 * s,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}


