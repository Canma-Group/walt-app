import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/web3auth_service.dart';

class QRReceivePage extends StatefulWidget {
  const QRReceivePage({super.key});

  @override
  State<QRReceivePage> createState() => _QRReceivePageState();
}

class _QRReceivePageState extends State<QRReceivePage> {
  final Web3AuthService _web3Auth = Web3AuthService();
  final TextEditingController _amountController = TextEditingController();
  
  String? _walletAddress;
  String _selectedToken = 'LSK';
  final List<String> _tokens = ['LSK', 'ETH', 'POL'];
  bool _includeAmount = false;

  @override
  void initState() {
    super.initState();
    _walletAddress = _web3Auth.walletAddress;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String get _qrData {
    // Format: canmawallet://pay?address=0x...&token=LSK&amount=10
    String data = 'canmawallet://pay?address=$_walletAddress&token=$_selectedToken';
    if (_includeAmount && _amountController.text.isNotEmpty) {
      data += '&amount=${_amountController.text}';
    }
    return data;
  }

  String get _shareText {
    String text = 'Pay me with Canma Wallet\n\nWallet: $_walletAddress\nToken: $_selectedToken';
    if (_includeAmount && _amountController.text.isNotEmpty) {
      text += '\nAmount: ${_amountController.text} $_selectedToken';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final s = screenWidth / 375;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Receive Payment',
          style: GoogleFonts.poppins(
            fontSize: 18 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20 * s),
        child: Column(
          children: [
            // QR Code Card
            Container(
              padding: EdgeInsets.all(24 * s),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24 * s),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Scan to Pay',
                    style: GoogleFonts.poppins(
                      fontSize: 16 * s,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  SizedBox(height: 20 * s),
                  
                  // QR Code
                  Container(
                    padding: EdgeInsets.all(16 * s),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16 * s),
                      border: Border.all(
                        color: const Color(0xFF08BFC1).withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: QrImageView(
                      data: _qrData,
                      version: QrVersions.auto,
                      size: 200 * s,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF1A1A2E),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  SizedBox(height: 20 * s),

                  // Wallet Address
                  Container(
                    padding: EdgeInsets.all(12 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(12 * s),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _walletAddress ?? '',
                            style: GoogleFonts.sourceCodePro(
                              fontSize: 11 * s,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _walletAddress ?? ''));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Address copied!')),
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.all(8 * s),
                            decoration: BoxDecoration(
                              color: const Color(0xFF08BFC1).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8 * s),
                            ),
                            child: Icon(
                              Icons.copy,
                              size: 18 * s,
                              color: const Color(0xFF08BFC1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20 * s),

            // Token Selection
            Container(
              padding: EdgeInsets.all(16 * s),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16 * s),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Token',
                    style: GoogleFonts.poppins(
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  SizedBox(height: 12 * s),
                  Row(
                    children: _tokens.map((token) {
                      final isSelected = _selectedToken == token;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedToken = token),
                          child: Container(
                            margin: EdgeInsets.only(right: token != _tokens.last ? 8 * s : 0),
                            padding: EdgeInsets.symmetric(vertical: 12 * s),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF08BFC1)
                                  : const Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.circular(12 * s),
                              border: isSelected
                                  ? null
                                  : Border.all(color: Colors.grey[300]!),
                            ),
                            child: Center(
                              child: Text(
                                token,
                                style: GoogleFonts.poppins(
                                  fontSize: 14 * s,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16 * s),

            // Amount (Optional)
            Container(
              padding: EdgeInsets.all(16 * s),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16 * s),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Request Amount (Optional)',
                        style: GoogleFonts.poppins(
                          fontSize: 14 * s,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                      Switch(
                        value: _includeAmount,
                        onChanged: (value) => setState(() => _includeAmount = value),
                        activeColor: const Color(0xFF08BFC1),
                      ),
                    ],
                  ),
                  if (_includeAmount) ...[
                    SizedBox(height: 12 * s),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.poppins(
                        fontSize: 18 * s,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 18 * s,
                          color: Colors.grey[300],
                        ),
                        suffixText: _selectedToken,
                        suffixStyle: GoogleFonts.poppins(
                          fontSize: 16 * s,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF08BFC1),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12 * s),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12 * s),
                          borderSide: const BorderSide(color: Color(0xFF08BFC1)),
                        ),
                        contentPadding: EdgeInsets.all(16 * s),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 24 * s),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Share.share(_shareText);
                    },
                    icon: const Icon(Icons.share, color: Color(0xFF08BFC1)),
                    label: Text(
                      'Share',
                      style: GoogleFonts.poppins(
                        fontSize: 14 * s,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF08BFC1),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16 * s),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12 * s),
                        side: const BorderSide(color: Color(0xFF08BFC1)),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                SizedBox(width: 12 * s),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _qrData));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment link copied!')),
                      );
                    },
                    icon: const Icon(Icons.link, color: Colors.white),
                    label: Text(
                      'Copy Link',
                      style: GoogleFonts.poppins(
                        fontSize: 14 * s,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF08BFC1),
                      padding: EdgeInsets.symmetric(vertical: 16 * s),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12 * s),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
