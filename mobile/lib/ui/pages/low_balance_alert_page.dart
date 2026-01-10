import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

class LowBalanceAlertPage extends StatefulWidget {
  const LowBalanceAlertPage({
    super.key,
    required this.initialEnabled,
    required this.initialThreshold,
    this.iconBase = 'assets/icons/ProfileUsers/',
    this.currencySymbol = '\$',
  });

  final bool initialEnabled;
  final int initialThreshold;
  final String iconBase;
  final String currencySymbol;

  @override
  State<LowBalanceAlertPage> createState() => _LowBalanceAlertPageState();
}

class _LowBalanceAlertPageState extends State<LowBalanceAlertPage> {
  late bool enabled;
  late int threshold;

  @override
  void initState() {
    super.initState();
    enabled = widget.initialEnabled;
    threshold = widget.initialThreshold;
  }

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
                      onTap: () => Navigator.pop(context, _LowBalanceAlertResult(enabled: enabled, threshold: threshold)),
                      child: SvgPicture.asset(
                        '${widget.iconBase}Frame-13.svg',
                        width: 20 * s,
                        height: 24 * s,
                        colorFilter: const ColorFilter.mode(Color(0xFF1264EF), BlendMode.srcIn),
                      ),
                    ),
                    SizedBox(width: 16 * s),
                    Text(
                      'Low Balance Alert',
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
                  padding: EdgeInsets.fromLTRB(24 * s, 24 * s, 24 * s, 40 * s),
                  child: Column(
                    children: [
                      _alertToggleCard(s),
                      SizedBox(height: 24 * s),
                      _thresholdCard(s),
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

  Widget _alertToggleCard(double s) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20 * s, 16 * s, 16 * s, 16 * s),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set low balance alert',
                  style: GoogleFonts.poppins(
                    fontSize: 15 * s,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2B2B2B),
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 6 * s),
                Text(
                  'We will send an email if your balance\nbelow limit',
                  style: GoogleFonts.poppins(
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF3A3A3A).withOpacity(0.6),
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: 12 * s),
          Transform.scale(
            scale: 1.0,
            child: Switch(
              value: enabled,
              onChanged: (v) => setState(() => enabled = v),
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF1264EF),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFF9E9E9E),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thresholdCard(double s) {
    return GestureDetector(
      onTap: enabled ? () => _editThresholdDialog(s) : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 160 * s,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16 * s),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(24 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set nominal',
                style: GoogleFonts.poppins(
                  fontSize: 14 * s,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    widget.currencySymbol,
                    style: GoogleFonts.poppins(
                      fontSize: 48 * s,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2B2B2B),
                      height: 1.0,
                    ),
                  ),
                  SizedBox(width: 8 * s),
                  Text(
                    '$threshold',
                    style: GoogleFonts.poppins(
                      fontSize: 64 * s,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2B2B2B),
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              if (enabled) ...[
                SizedBox(height: 8 * s),
                Text(
                  'Tap to change',
                  style: GoogleFonts.poppins(
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF1264EF),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editThresholdDialog(double s) async {
    final controller = TextEditingController(text: threshold.toString());
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24 * s)),
          backgroundColor: Colors.white,
          child: Container(
            padding: EdgeInsets.all(28 * s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  'Set threshold',
                  style: GoogleFonts.poppins(
                    fontSize: 22 * s,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2B2B2B),
                  ),
                ),
                SizedBox(height: 24 * s),
                
                // Input field
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  style: GoogleFonts.poppins(
                    fontSize: 18 * s,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF2B2B2B),
                  ),
                  decoration: InputDecoration(
                    hintText: '30',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 18 * s,
                      color: const Color(0xFF9E9E9E),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: const Color(0xFF1264EF).withOpacity(0.3), width: 2),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF1264EF), width: 2),
                    ),
                  ),
                ),
                
                SizedBox(height: 32 * s),
                
                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 12 * s),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 15 * s,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                    SizedBox(width: 12 * s),
                    ElevatedButton(
                      onPressed: () {
                        final v = int.tryParse(controller.text.trim());
                        Navigator.pop(context, v);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1264EF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(horizontal: 32 * s, vertical: 14 * s),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12 * s),
                        ),
                      ),
                      child: Text(
                        'Save',
                        style: GoogleFonts.poppins(
                          fontSize: 15 * s,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null && result > 0) {
      setState(() => threshold = result);
    }
  }
}

class _LowBalanceAlertResult {
  final bool enabled;
  final int threshold;

  const _LowBalanceAlertResult({required this.enabled, required this.threshold});
}


