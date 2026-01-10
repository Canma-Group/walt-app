import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({
    super.key,
    this.iconBase = 'assets/icons/ProfileUsers/',
  });

  final String iconBase;

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool payment = true;
  bool topUp = true;
  bool transfer = true;

  bool newDeviceLogin = true;
  bool accountChanges = true;

  bool bills = true;
  bool balanceReminder = true;

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
                        '${widget.iconBase}Frame-13.svg',
                        width: 20 * s,
                        height: 24 * s,
                        colorFilter: const ColorFilter.mode(Color(0xFF1264EF), BlendMode.srcIn),
                      ),
                    ),
                    SizedBox(width: 16 * s),
                    Text(
                      'Notification',
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 8 * s),
                      _sectionLabel('Transactions', s),
                      SizedBox(height: 10 * s),
                      _toggleRow(s: s, title: 'Payment', value: payment, onChanged: (v) => setState(() => payment = v)),
                      SizedBox(height: 10 * s),
                      _toggleRow(s: s, title: 'Top Up', value: topUp, onChanged: (v) => setState(() => topUp = v)),
                      SizedBox(height: 10 * s),
                      _toggleRow(s: s, title: 'Transfer', value: transfer, onChanged: (v) => setState(() => transfer = v)),
                      SizedBox(height: 16 * s),
                      _sectionLabel('Security', s),
                      SizedBox(height: 10 * s),
                      _toggleRow(
                        s: s,
                        title: 'New device login',
                        value: newDeviceLogin,
                        onChanged: (v) => setState(() => newDeviceLogin = v),
                      ),
                      SizedBox(height: 10 * s),
                      _toggleRow(
                        s: s,
                        title: 'Account changes',
                        value: accountChanges,
                        onChanged: (v) => setState(() => accountChanges = v),
                      ),
                      SizedBox(height: 16 * s),
                      _sectionLabel('Reminder', s),
                      SizedBox(height: 10 * s),
                      _toggleRow(s: s, title: 'Bills', value: bills, onChanged: (v) => setState(() => bills = v)),
                      SizedBox(height: 10 * s),
                      _toggleRow(
                        s: s,
                        title: 'Balance reminder',
                        value: balanceReminder,
                        onChanged: (v) => setState(() => balanceReminder = v),
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

  Widget _sectionLabel(String title, double s) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 12 * s,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF3A3A3A).withOpacity(0.75),
      ),
    );
  }

  Widget _toggleRow({
    required double s,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      height: 46 * s,
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
      padding: EdgeInsets.symmetric(horizontal: 18 * s),
      child: Row(
        children: [
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
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF1264EF),
              activeTrackColor: const Color(0xFF7A7A7A),
              inactiveThumbColor: const Color(0xFF1264EF),
              inactiveTrackColor: const Color(0xFF7A7A7A),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}






