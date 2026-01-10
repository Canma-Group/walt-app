import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/multi_chain_service.dart';

/// Widget to display a list of token balances
class TokenListWidget extends StatelessWidget {
  final List<TokenBalance> tokens;
  final double scale;
  final VoidCallback? onViewAll;
  final Function(TokenBalance)? onTokenTap;

  const TokenListWidget({
    Key? key,
    required this.tokens,
    this.scale = 1.0,
    this.onViewAll,
    this.onTokenTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = scale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 28 * s),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Tokens',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF3A3A3A),
                  fontSize: 18 * s,
                  fontWeight: FontWeight.w500,
                ),
              ),
              GestureDetector(
                onTap: onViewAll,
                child: Row(
                  children: [
                    Text(
                      'View All',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF3A3A3A),
                        fontSize: 15 * s,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 4 * s),
                    Text(
                      '>>',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF3A3A3A),
                        fontSize: 16 * s,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12 * s),

        // Token list
        if (tokens.isEmpty)
          _buildEmptyState(s)
        else
          ...tokens.take(3).map((token) => Padding(
            padding: EdgeInsets.only(bottom: 12 * s),
            child: _buildTokenItem(token, s),
          )).toList(),
      ],
    );
  }

  Widget _buildEmptyState(double s) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28 * s, vertical: 20 * s),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20 * s),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16 * s),
        ),
        child: Column(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 40 * s,
              color: Colors.grey,
            ),
            SizedBox(height: 8 * s),
            Text(
              'No tokens yet',
              style: GoogleFonts.poppins(
                color: Colors.grey,
                fontSize: 14 * s,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4 * s),
            Text(
              'Top up to receive tokens',
              style: GoogleFonts.poppins(
                color: Colors.grey.shade400,
                fontSize: 12 * s,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenItem(TokenBalance token, double s) {
    return GestureDetector(
      onTap: () => onTokenTap?.call(token),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 28 * s),
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
        decoration: BoxDecoration(
          color: const Color(0xFF4E4E4E).withOpacity(0.5),
          borderRadius: BorderRadius.circular(50 * s),
        ),
        child: Row(
          children: [
            // Token icon
            Container(
              width: 42 * s,
              height: 42 * s,
              decoration: BoxDecoration(
                color: _getChainColor(token.chainId).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: token.icon != null
                    ? Image.network(
                        token.icon!,
                        width: 24 * s,
                        height: 24 * s,
                        errorBuilder: (_, __, ___) => _buildDefaultIcon(token, s),
                      )
                    : _buildDefaultIcon(token, s),
              ),
            ),
            SizedBox(width: 12 * s),

            // Token info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    token.symbol,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16 * s,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    token.chainName,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFEEEEEE),
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),

            // Balance
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatBalance(token.balance),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16 * s,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (token.type == 'ledger')
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF08BFC1).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4 * s),
                    ),
                    child: Text(
                      'Recorded',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF08BFC1),
                        fontSize: 9 * s,
                        fontWeight: FontWeight.w500,
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

  Widget _buildDefaultIcon(TokenBalance token, double s) {
    return Text(
      token.symbol.isNotEmpty ? token.symbol[0] : '?',
      style: GoogleFonts.poppins(
        color: _getChainColor(token.chainId),
        fontSize: 18 * s,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Color _getChainColor(int chainId) {
    switch (chainId) {
      case 4202: // Lisk Sepolia
        return const Color(0xFF4070F4);
      case 137: // Polygon
        return const Color(0xFF8247E5);
      case 1: // Ethereum
        return const Color(0xFF627EEA);
      default:
        return const Color(0xFF08BFC1);
    }
  }

  String _formatBalance(String balance) {
    final value = double.tryParse(balance) ?? 0;
    if (value == 0) return '0';
    if (value < 0.0001) return '<0.0001';
    if (value < 1) return value.toStringAsFixed(4);
    if (value < 1000) return value.toStringAsFixed(2);
    return value.toStringAsFixed(0);
  }
}

/// Compact token chip for horizontal scroll
class TokenChip extends StatelessWidget {
  final TokenBalance token;
  final double scale;
  final VoidCallback? onTap;

  const TokenChip({
    Key? key,
    required this.token,
    this.scale = 1.0,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = scale;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
        decoration: BoxDecoration(
          color: _getChainColor(token.chainId).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(
            color: _getChainColor(token.chainId).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24 * s,
              height: 24 * s,
              decoration: BoxDecoration(
                color: _getChainColor(token.chainId),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  token.symbol.isNotEmpty ? token.symbol[0] : '?',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12 * s,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8 * s),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_formatBalance(token.balance)} ${token.symbol}',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF3A3A3A),
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  token.chainName,
                  style: GoogleFonts.poppins(
                    color: Colors.grey,
                    fontSize: 10 * s,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getChainColor(int chainId) {
    switch (chainId) {
      case 4202:
        return const Color(0xFF4070F4);
      case 137:
        return const Color(0xFF8247E5);
      case 1:
        return const Color(0xFF627EEA);
      default:
        return const Color(0xFF08BFC1);
    }
  }

  String _formatBalance(String balance) {
    final value = double.tryParse(balance) ?? 0;
    if (value == 0) return '0';
    if (value < 0.0001) return '<0.0001';
    if (value < 1) return value.toStringAsFixed(4);
    return value.toStringAsFixed(2);
  }
}
