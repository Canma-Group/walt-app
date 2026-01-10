import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../screens/receive_screen.dart';
import 'qris_payment_page.dart';

class ScanQrisScreen extends StatefulWidget {
  const ScanQrisScreen({Key? key}) : super(key: key);

  @override
  State<ScanQrisScreen> createState() => _ScanQrisScreenState();
}

class _ScanQrisScreenState extends State<ScanQrisScreen> with WidgetsBindingObserver {
  static const String _iconBase = 'assets/icons/ScanQris/';
  MobileScannerController? _cameraController;
  bool _isProcessing = false;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
        _cameraController?.stop();
        break;
      case AppLifecycleState.resumed:
        _cameraController?.start();
        break;
      default:
        break;
    }
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    
    if (status.isGranted) {
      setState(() {
        _permissionGranted = true;
        _cameraController = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: false,
        );
      });
    } else if (status.isPermanentlyDenied) {
      _showPermissionDialog();
    } else {
      _showPermissionDeniedSnackbar();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Camera Permission Required',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Please enable camera permission in settings to scan QRIS codes.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text('Open Settings', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Camera permission is required to scan QRIS',
          style: GoogleFonts.poppins(),
        ),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: _initializeCamera,
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      
      if (code != null && code.isNotEmpty) {
        setState(() {
          _isProcessing = true;
        });
        
        _cameraController?.stop();
        _showQRResult(code);
      }
    }
  }

  void _showQRResult(String code) {
    // Parse QRIS data
    final qrisData = _parseQrisData(code);
    
    // Check if it's a valid QRIS code (starts with "00" for EMV format)
    if (!code.startsWith('00')) {
      _showInvalidQrisDialog(code);
      return;
    }

    // Show payment confirmation dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          'QRIS Payment',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (qrisData['merchantName'] != null) ...[
              Text(
                'Merchant:',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
              ),
              Text(
                qrisData['merchantName']!,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Amount (IDR):',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
            ),
            if (qrisData['amount'] != null && qrisData['amount'] != '0')
              Text(
                'Rp ${qrisData['amount']}',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: const Color(0xFF1264EF),
                ),
              )
            else
              // Input amount manually for static QRIS
              _AmountInputField(
                onAmountChanged: (value) {
                  qrisData['amount'] = value;
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isProcessing = false;
              });
              _cameraController?.start();
            },
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToPayment(code, qrisData);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1264EF),
            ),
            child: Text(
              'Pay with my Asset',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showInvalidQrisDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          'Invalid QR Code',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'This QR code is not a valid QRIS payment code.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isProcessing = false;
              });
              _cameraController?.start();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1264EF),
            ),
            child: Text('Scan Again', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Map<String, String?> _parseQrisData(String qrisPayload) {
    final result = <String, String?>{
      'merchantName': null,
      'merchantCity': null,
      'amount': null,
    };

    try {
      int index = 0;
      while (index < qrisPayload.length - 4) {
        final tag = qrisPayload.substring(index, index + 2);
        final lengthStr = qrisPayload.substring(index + 2, index + 4);
        final length = int.tryParse(lengthStr) ?? 0;
        
        if (length <= 0 || index + 4 + length > qrisPayload.length) break;
        
        final value = qrisPayload.substring(index + 4, index + 4 + length);
        
        switch (tag) {
          case '59': // Merchant Name
            result['merchantName'] = value;
            break;
          case '60': // Merchant City
            result['merchantCity'] = value;
            break;
          case '54': // Transaction Amount
            result['amount'] = value;
            break;
        }
        
        index += 4 + length;
      }
    } catch (e) {
      print('Error parsing QRIS: $e');
    }

    return result;
  }

  void _navigateToPayment(String qrisPayload, Map<String, String?> qrisData) {
    final amountStr = qrisData['amount'] ?? '0';
    final amount = double.tryParse(amountStr.replaceAll('.', '').replaceAll(',', '')) ?? 0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid amount', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isProcessing = false;
      });
      _cameraController?.start();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QrisPaymentPage(
          qrisPayload: qrisPayload,
          amountIdr: amount,
          merchantName: qrisData['merchantName'],
        ),
      ),
    ).then((_) {
      setState(() {
        _isProcessing = false;
      });
      _cameraController?.start();
    });
  }

  void _onQrisTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'QRIS Tap feature coming soon!',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  void _onShowCode() {
    // Get user's wallet address
    final authState = context.read<AuthBloc>().state;
    String? walletAddress;
    
    if (authState is AuthSuccess) {
      walletAddress = authState.user.walletAddress;
    } else if (authState is AuthNeedsWalletVerification) {
      walletAddress = authState.user.walletAddress;
    }
    
    if (walletAddress == null || walletAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wallet address not found', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Navigate to ReceiveScreen instead of showing bottom sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReceiveScreen(walletAddress: walletAddress!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Stack(
        children: [
          // Full screen camera with gradient overlay
          if (_permissionGranted && _cameraController != null)
            Stack(
              children: [
                // Camera view
                Positioned.fill(
                  child: MobileScanner(
                    controller: _cameraController!,
                    onDetect: _onDetect,
                  ),
                ),
                
                // Top gradient overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 180,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.black.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Bottom gradient overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 205,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.9),
                          Colors.black.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    Color(0xFF0A3989),
                    Color(0xFF1264EF),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Initializing camera...',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top bar with back button and icons
          _buildTopBar(),

          // Bottom buttons (QRIS Tap & Show Code)
          _buildBottomButtons(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Back button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Image.asset(
                // Back arrow icon (matches `Frame@2x-2.png`)
                '${_iconBase}Frame@2x-2.png',
                width: 20,
                height: 24,
                fit: BoxFit.contain,
              ),
            ),
            
            // Right icons
            Row(
              children: [
                // Gallery icon (must be LEFT of info, same as Figma)
                GestureDetector(
                  onTap: () async {
                    try {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      
                      if (image != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Gallery scan feature coming soon!',
                              style: GoogleFonts.poppins(),
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      // Handle error
                    }
                  },
                  child: Container(
                    width: 35,
                    height: 35,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(right: 12),
                    child: Image.asset(
                      // Gallery icon (matches `Frame@2x-1.png`)
                      '${_iconBase}Frame@2x-1.png',
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // Info icon (RIGHTMOST)
                GestureDetector(
                  onTap: () {
                    // Show info dialog
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    child: Image.asset(
                      // Info icon (matches `Frame@2x-3.png`)
                      '${_iconBase}Frame@2x-3.png',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
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

  Widget _buildBottomButtons() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 22, right: 22, bottom: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // QRIS Tap button
              Expanded(
                child: GestureDetector(
                  onTap: _onQrisTap,
                  child: Container(
                    height: 47,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 241, 241, 241),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          // QR icon (matches `Frame@2x.png`)
                          '${_iconBase}Frame@2x.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'QRIS Tap',
                          style: GoogleFonts.poppins(
                            color: Colors.blueAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Show Code button
              Expanded(
                child: GestureDetector(
                  onTap: _onShowCode,
                  child: Container(
                    height: 47,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 241, 241, 241),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          // Show code icon (matches `Vector@2x.png`)
                          '${_iconBase}Vector@2x.png',
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Show Code',
                          style: GoogleFonts.poppins(
                            color: Colors.blueAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
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

class _AmountInputField extends StatefulWidget {
  final Function(String) onAmountChanged;

  const _AmountInputField({required this.onAmountChanged});

  @override
  State<_AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<_AmountInputField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      style: GoogleFonts.poppins(
        fontWeight: FontWeight.bold,
        fontSize: 24,
        color: const Color(0xFF1264EF),
      ),
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          fontSize: 24,
          color: Colors.grey,
        ),
        prefixText: 'Rp ',
        prefixStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          fontSize: 24,
          color: const Color(0xFF1264EF),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1264EF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1264EF), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onChanged: widget.onAmountChanged,
    );
  }
}
