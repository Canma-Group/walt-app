import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppLanguage { english, indonesia }

class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({
    super.key,
    required this.initialValue,
    this.iconBase = 'assets/icons/ProfileUsers/',
  });

  final AppLanguage initialValue;
  final String iconBase;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size.width / 393;

    return _SettingsScaffold(
      title: 'Language',
      iconBase: iconBase,
      child: _OptionGroup(
        s: s,
        children: [
          _OptionRow(
            s: s,
            leading: _FlagCircle(s: s, emoji: '🇺🇸'),
            title: 'English',
            selected: initialValue == AppLanguage.english,
            onTap: () => Navigator.pop(context, AppLanguage.english),
          ),
          _GroupDivider(s: s),
          _OptionRow(
            s: s,
            leading: _FlagCircle(s: s, emoji: '🇮🇩'),
            title: 'Indonesia',
            selected: initialValue == AppLanguage.indonesia,
            onTap: () => Navigator.pop(context, AppLanguage.indonesia),
          ),
        ],
      ),
    );
  }
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.title,
    required this.child,
    required this.iconBase,
  });

  final String title;
  final Widget child;
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
                      title,
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
                      child,
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

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({required this.s, required this.children});

  final double s;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(children: children),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider({required this.s});

  final double s;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 18 * s),
      child: Divider(height: 1, thickness: 1, color: Colors.black.withOpacity(0.08)),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.s,
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final double s;
  final Widget leading;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30 * s),
      child: SizedBox(
        height: 52 * s,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Row(
            children: [
              leading,
              SizedBox(width: 12 * s),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF3A3A3A),
                  ),
                ),
              ),
              _SelectionMark(s: s, selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlagCircle extends StatelessWidget {
  const _FlagCircle({required this.s, required this.emoji});

  final double s;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30 * s,
      height: 30 * s,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: TextStyle(fontSize: 16 * s),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.s, required this.selected});

  final double s;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18 * s,
      height: 18 * s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF1264EF), width: 1.5),
        color: selected ? const Color(0xFF1264EF) : Colors.transparent,
      ),
      child: selected
          ? Icon(Icons.check, size: 12 * s, color: Colors.white)
          : const SizedBox.shrink(),
    );
  }
}






