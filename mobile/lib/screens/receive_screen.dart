import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web3dart/web3dart.dart';
import '../core/theme/app_colors.dart';
import '../services/blockchain_service.dart';
import '../services/network_service.dart';

/// Receive Screen - Display QR Code for receiving crypto
class ReceiveScreen extends StatefulWidget {
  final String walletAddress;
  final String? tokenSymbol;

  const ReceiveScreen({
    super.key,
    required this.walletAddress,
    this.tokenSymbol = 'Any Token',
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final NetworkService _networkService = NetworkService();
  late final BlockchainService _blockchainService;

  late NetworkInfo _activeNetwork;
  int? _chainId;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _activeNetwork = _networkService.activeNetwork;
    _blockchainService = BlockchainService(rpcUrl: _activeNetwork.rpcUrl);

    _networkService.activeNetworkListenable.addListener(_handleNetworkChange);
    _loadChainId();
  }

  @override
  void dispose() {
    _networkService.activeNetworkListenable.removeListener(_handleNetworkChange);
    _blockchainService.dispose();
    super.dispose();
  }

  void _handleNetworkChange() {
    final next = _networkService.activeNetwork;
    if (next.rpcUrl != _activeNetwork.rpcUrl) {
      _blockchainService.setRpcUrl(next.rpcUrl);
    }

    setState(() {
      _activeNetwork = next;
    });

    _loadChainId();
  }

  Future<void> _loadChainId() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _chainId = null;
    });

    try {
      final id = await _blockchainService.getChainId();
      if (!mounted) return;
      setState(() {
        _chainId = id;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String? get _checksummedAddress {
    final raw = widget.walletAddress.trim();
    if (raw.isEmpty) return null;

    try {
      final parsed = EthereumAddress.fromHex(raw);
      final checksummed = parsed.hexEip55;

      final hasBothCases = raw.toLowerCase() != raw && raw.toUpperCase() != raw;
      if (hasBothCases && raw != checksummed) {
        return null;
      }

      return checksummed;
    } catch (_) {
      return null;
    }
  }

  String get _truncatedAddress {
    final addr = _checksummedAddress ?? widget.walletAddress;
    if (addr.length > 16) {
      return '${addr.substring(0, 10)}...${addr.substring(addr.length - 6)}';
    }
    return addr;
  }

  void _copyAddress(BuildContext context) {
    final addr = _checksummedAddress ?? widget.walletAddress;
    Clipboard.setData(ClipboardData(text: addr));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Address copied to clipboard'),
        backgroundColor: AppColors.primaryDark,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareAddress(BuildContext context) {
    // TODO: Implement share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Share functionality coming soon'),
        backgroundColor: AppColors.primaryDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checksummed = _checksummedAddress;
    final chainId = _chainId;
    final bool canRenderQr = checksummed != null;
    final String qrData = checksummed ?? '';

    final String chainIdText = _isLoading
        ? 'loading...'
        : (_error != null || chainId == null || chainId <= 0)
            ? '-'
            : chainId.toString();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Siap Menerima Dana',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.tokenSymbol ?? 'Any Token',
                        style: GoogleFonts.poppins(
                          color: AppColors.primaryDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.border,
                          width: 2,
                        ),
                      ),
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: Builder(
                          builder: (_) {
                            if (checksummed == null) {
                              return Center(
                                child: Text(
                                  'Alamat wallet tidak valid',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }

                            return QrImageView(
                              data: qrData,
                              version: QrVersions.auto,
                              size: 220,
                              backgroundColor: Colors.white,
                              eyeStyle: QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black,
                              ),
                              dataModuleStyle: QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      'Network: ${_activeNetwork.name}',
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'ChainId: $chainIdText',
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 18),

                    Text(
                      'Wallet Address',
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 8),

                    GestureDetector(
                      onTap: canRenderQr ? () => _copyAddress(context) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                _truncatedAddress,
                                style: GoogleFonts.robotoMono(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.copy,
                              size: 18,
                              color: AppColors.primaryDark,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Minta pengirim scan QR ini untuk transfer crypto.\nDi MetaMask: Send → To → Scan.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: canRenderQr ? () => _shareAddress(context) : null,
              icon: const Icon(Icons.share, size: 20),
              label: Text(
                'Share Address',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
