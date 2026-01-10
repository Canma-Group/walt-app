import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/payment_request_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';

class PaymentRequestService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // Collection reference
  CollectionReference get _requestsRef => _db.collection('payment_requests');

  /// Create a new payment request (invoice)
  Future<PaymentRequestModel> createPaymentRequest({
    required String requesterWallet,
    required String requesterName,
    String? requesterPhoto,
    required String payerWallet,
    required String payerName,
    String? payerPhoto,
    required String amount,
    required String token,
    int chainId = 4202,
    String chainName = 'Lisk Sepolia',
    String? memo,
    int expiryDays = 7,
  }) async {
    try {
      final docRef = _requestsRef.doc();
      final now = DateTime.now();
      final expiresAt = now.add(Duration(days: expiryDays));

      final request = PaymentRequestModel(
        id: docRef.id,
        requesterWallet: requesterWallet.toLowerCase(),
        requesterName: requesterName,
        requesterPhoto: requesterPhoto,
        payerWallet: payerWallet.toLowerCase(),
        payerName: payerName,
        payerPhoto: payerPhoto,
        amount: amount,
        token: token,
        chainId: chainId,
        chainName: chainName,
        memo: memo,
        status: PaymentRequestStatus.pending,
        createdAt: now,
        expiresAt: expiresAt,
      );

      await docRef.set(request.toJson());
      print('[PaymentRequestService] Created payment request: ${docRef.id}');

      // Send notification to payer
      await _notificationService.createNotification(
        userId: payerWallet,
        type: NotificationType.paymentRequest,
        title: 'Payment Request',
        body: '$requesterName requested ${request.formattedAmount} $token from you',
        imageUrl: requesterPhoto,
        data: {
          'request_id': docRef.id,
          'amount': amount,
          'token': token,
          'requester_wallet': requesterWallet,
          'requester_name': requesterName,
          'memo': memo,
        },
      );

      return request;
    } catch (e) {
      print('[PaymentRequestService] Error creating payment request: $e');
      rethrow;
    }
  }

  /// Mark payment request as paid
  Future<void> markAsPaid({
    required String requestId,
    required String txHash,
  }) async {
    try {
      final doc = await _requestsRef.doc(requestId).get();
      if (!doc.exists) {
        throw Exception('Payment request not found');
      }

      final request = PaymentRequestModel.fromJson(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      await _requestsRef.doc(requestId).update({
        'status': PaymentRequestStatus.paid.name,
        'paid_at': FieldValue.serverTimestamp(),
        'tx_hash': txHash,
      });

      print('[PaymentRequestService] Marked request $requestId as paid');

      // Send notification to requester
      await _notificationService.createNotification(
        userId: request.requesterWallet,
        type: NotificationType.paymentRequestPaid,
        title: 'Payment Received',
        body: '${request.payerName} paid your request of ${request.formattedAmount} ${request.token}',
        imageUrl: request.payerPhoto,
        data: {
          'request_id': requestId,
          'amount': request.amount,
          'token': request.token,
          'payer_wallet': request.payerWallet,
          'payer_name': request.payerName,
          'tx_hash': txHash,
        },
      );
    } catch (e) {
      print('[PaymentRequestService] Error marking as paid: $e');
      rethrow;
    }
  }

  /// Cancel a payment request
  Future<void> cancelRequest(String requestId) async {
    try {
      final doc = await _requestsRef.doc(requestId).get();
      if (!doc.exists) {
        throw Exception('Payment request not found');
      }

      final request = PaymentRequestModel.fromJson(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      await _requestsRef.doc(requestId).update({
        'status': PaymentRequestStatus.cancelled.name,
        'cancelled_at': FieldValue.serverTimestamp(),
      });

      print('[PaymentRequestService] Cancelled request $requestId');

      // Notify payer that request was cancelled
      await _notificationService.createNotification(
        userId: request.payerWallet,
        type: NotificationType.paymentRequestCancelled,
        title: 'Request Cancelled',
        body: '${request.requesterName} cancelled their payment request of ${request.formattedAmount} ${request.token}',
        imageUrl: request.requesterPhoto,
        data: {
          'request_id': requestId,
        },
      );
    } catch (e) {
      print('[PaymentRequestService] Error cancelling request: $e');
      rethrow;
    }
  }

  /// Get payment requests for a user (as requester or payer)
  Future<List<PaymentRequestModel>> getPaymentRequests({
    required String walletAddress,
    PaymentRequestStatus? statusFilter,
    bool asRequester = true,
    bool asPayer = true,
    int limit = 50,
  }) async {
    try {
      final normalizedWallet = walletAddress.toLowerCase();
      final List<PaymentRequestModel> requests = [];

      if (asRequester) {
        Query query = _requestsRef
            .where('requester_wallet', isEqualTo: normalizedWallet)
            .orderBy('created_at', descending: true);

        if (statusFilter != null) {
          query = query.where('status', isEqualTo: statusFilter.name);
        }

        final snapshot = await query.limit(limit).get();
        for (final doc in snapshot.docs) {
          requests.add(PaymentRequestModel.fromJson(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ));
        }
      }

      if (asPayer) {
        Query query = _requestsRef
            .where('payer_wallet', isEqualTo: normalizedWallet)
            .orderBy('created_at', descending: true);

        if (statusFilter != null) {
          query = query.where('status', isEqualTo: statusFilter.name);
        }

        final snapshot = await query.limit(limit).get();
        for (final doc in snapshot.docs) {
          if (!requests.any((r) => r.id == doc.id)) {
            requests.add(PaymentRequestModel.fromJson(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ));
          }
        }
      }

      // Sort by created_at descending
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return requests.take(limit).toList();
    } catch (e) {
      print('[PaymentRequestService] Error getting requests: $e');
      return [];
    }
  }

  /// Get pending payment requests where user is the payer
  Future<List<PaymentRequestModel>> getPendingRequestsForPayer(String walletAddress) async {
    return getPaymentRequests(
      walletAddress: walletAddress,
      statusFilter: PaymentRequestStatus.pending,
      asRequester: false,
      asPayer: true,
    );
  }

  /// Get payment request by ID
  Future<PaymentRequestModel?> getRequestById(String requestId) async {
    try {
      final doc = await _requestsRef.doc(requestId).get();
      if (doc.exists) {
        return PaymentRequestModel.fromJson(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }
      return null;
    } catch (e) {
      print('[PaymentRequestService] Error getting request: $e');
      return null;
    }
  }

  /// Stream of pending requests for real-time updates
  Stream<List<PaymentRequestModel>> pendingRequestsStream(String walletAddress) {
    final normalizedWallet = walletAddress.toLowerCase();

    return _requestsRef
        .where('payer_wallet', isEqualTo: normalizedWallet)
        .where('status', isEqualTo: PaymentRequestStatus.pending.name)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return PaymentRequestModel.fromJson(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
    });
  }

  /// Check and mark expired requests
  Future<void> checkExpiredRequests() async {
    try {
      final now = Timestamp.now();
      final snapshot = await _requestsRef
          .where('status', isEqualTo: PaymentRequestStatus.pending.name)
          .where('expires_at', isLessThan: now)
          .get();

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'status': PaymentRequestStatus.expired.name,
        });

        final request = PaymentRequestModel.fromJson(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );

        // Notify requester
        await _notificationService.createNotification(
          userId: request.requesterWallet,
          type: NotificationType.paymentRequestExpired,
          title: 'Request Expired',
          body: 'Your payment request of ${request.formattedAmount} ${request.token} to ${request.payerName} has expired',
          data: {
            'request_id': doc.id,
          },
        );
      }

      await batch.commit();
      print('[PaymentRequestService] Marked ${snapshot.docs.length} requests as expired');
    } catch (e) {
      print('[PaymentRequestService] Error checking expired requests: $e');
    }
  }
}
