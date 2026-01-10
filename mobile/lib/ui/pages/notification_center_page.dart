import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../services/web3auth_service.dart';
import '../../blocs/auth/auth_bloc.dart';
import 'transaction_history_page.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  final NotificationService _notificationService = NotificationService();
  final Web3AuthService _web3Auth = Web3AuthService();
  
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  String? _walletAddress;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    
    try {
      // Get wallet address from AuthBloc first (same as homepage), fallback to Web3Auth
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthSuccess) {
        _walletAddress = authState.user.walletAddress;
      } else if (authState is AuthNeedsWalletVerification) {
        _walletAddress = authState.user.walletAddress;
      } else {
        _walletAddress = _web3Auth.walletAddress;
      }
      
      print('[NotificationCenter] Loading notifications for wallet: $_walletAddress');
      
      if (_walletAddress == null || _walletAddress!.isEmpty) {
        print('[NotificationCenter] Wallet address is null or empty, cannot load notifications');
        setState(() => _isLoading = false);
        return;
      }

      final notifications = await _notificationService.getNotifications(
        userId: _walletAddress!,
        limit: 100,
      );

      print('[NotificationCenter] Loaded ${notifications.length} notifications');

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      print('[NotificationCenter] Error loading: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(NotificationModel notification) async {
    if (!notification.isRead) {
      await _notificationService.markAsRead(notification.id);
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notification.id);
        if (index != -1) {
          _notifications[index] = notification.copyWith(isRead: true);
        }
      });
    }
  }

  Future<void> _markAllAsRead() async {
    if (_walletAddress == null) return;
    
    await _notificationService.markAllAsRead(_walletAddress!);
    setState(() {
      _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final s = screenWidth / 375;
    final unreadCount = _notifications.where((n) => !n.isRead).length;

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
          'Notifications',
          style: GoogleFonts.poppins(
            fontSize: 18 * s,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.poppins(
                  fontSize: 12 * s,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF08BFC1),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF08BFC1)),
            )
          : _notifications.isEmpty
              ? _buildEmptyState(s)
              : _buildNotificationList(s),
    );
  }

  Widget _buildEmptyState(double s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80 * s,
            height: 80 * s,
            decoration: BoxDecoration(
              color: const Color(0xFF08BFC1).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none,
              size: 40 * s,
              color: const Color(0xFF08BFC1),
            ),
          ),
          SizedBox(height: 20 * s),
          Text(
            'No notifications yet',
            style: GoogleFonts.poppins(
              fontSize: 16 * s,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          SizedBox(height: 8 * s),
          Text(
            'You\'ll see your transaction updates here',
            style: GoogleFonts.poppins(
              fontSize: 13 * s,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList(double s) {
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: const Color(0xFF08BFC1),
      child: ListView.builder(
        padding: EdgeInsets.all(16 * s),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          return _buildNotificationCard(_notifications[index], s);
        },
      ),
    );
  }

  Widget _buildNotificationCard(NotificationModel notification, double s) {
    return GestureDetector(
      onTap: () {
        _markAsRead(notification);
        _handleNotificationTap(notification);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12 * s),
        padding: EdgeInsets.all(16 * s),
        decoration: BoxDecoration(
          color: notification.isRead ? Colors.white : const Color(0xFFE8F8F8),
          borderRadius: BorderRadius.circular(16 * s),
          border: notification.isRead
              ? null
              : Border.all(color: const Color(0xFF08BFC1).withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 44 * s,
              height: 44 * s,
              decoration: BoxDecoration(
                color: _getNotificationColor(notification.type).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getNotificationIcon(notification.type),
                color: _getNotificationColor(notification.type),
                size: 22 * s,
              ),
            ),
            SizedBox(width: 14 * s),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: GoogleFonts.poppins(
                            fontSize: 14 * s,
                            fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w600,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8 * s,
                          height: 8 * s,
                          decoration: const BoxDecoration(
                            color: Color(0xFF08BFC1),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    notification.body,
                    style: GoogleFonts.poppins(
                      fontSize: 12 * s,
                      color: Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 8 * s),
                  Text(
                    notification.timeAgo,
                    style: GoogleFonts.poppins(
                      fontSize: 11 * s,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.transferReceived:
        return Icons.arrow_downward;
      case NotificationType.transferSent:
        return Icons.arrow_upward;
      case NotificationType.transferFailed:
        return Icons.error_outline;
      case NotificationType.paymentRequest:
        return Icons.request_quote;
      case NotificationType.paymentRequestPaid:
        return Icons.check_circle_outline;
      case NotificationType.paymentRequestExpired:
        return Icons.timer_off;
      case NotificationType.paymentRequestCancelled:
        return Icons.cancel_outlined;
      case NotificationType.topUpSuccess:
        return Icons.add_circle_outline;
      case NotificationType.qrisPayment:
        return Icons.qr_code;
      case NotificationType.splitBillInvite:
        return Icons.receipt_long;
      case NotificationType.splitBillPayment:
        return Icons.payments;
      case NotificationType.splitBillComplete:
        return Icons.check_circle;
      case NotificationType.system:
        return Icons.info_outline;
    }
  }

  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.transferReceived:
        return Colors.green[600]!;
      case NotificationType.transferSent:
        return Colors.blue[600]!;
      case NotificationType.transferFailed:
        return Colors.red[600]!;
      case NotificationType.paymentRequest:
        return Colors.orange[600]!;
      case NotificationType.paymentRequestPaid:
        return Colors.green[600]!;
      case NotificationType.paymentRequestExpired:
        return Colors.grey[600]!;
      case NotificationType.paymentRequestCancelled:
        return Colors.grey[600]!;
      case NotificationType.topUpSuccess:
        return const Color(0xFF08BFC1);
      case NotificationType.qrisPayment:
        return Colors.purple[600]!;
      case NotificationType.splitBillInvite:
        return Colors.orange[600]!;
      case NotificationType.splitBillPayment:
        return Colors.green[600]!;
      case NotificationType.splitBillComplete:
        return const Color(0xFF08BFC1);
      case NotificationType.system:
        return Colors.blue[600]!;
    }
  }

  void _handleNotificationTap(NotificationModel notification) {
    // Navigate based on notification type
    switch (notification.type) {
      case NotificationType.transferReceived:
      case NotificationType.transferSent:
      case NotificationType.transferFailed:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransactionHistoryPage()),
        );
        break;
      case NotificationType.paymentRequest:
        // TODO: Navigate to payment request detail
        final requestId = notification.data?['request_id'];
        if (requestId != null) {
          // Navigate to pay request page
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opening payment request: $requestId')),
          );
        }
        break;
      case NotificationType.paymentRequestPaid:
      case NotificationType.paymentRequestExpired:
      case NotificationType.paymentRequestCancelled:
        // TODO: Navigate to request history
        break;
      default:
        break;
    }
  }
}
