import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';
import '../models/transaction_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';
import '../config/env.dart';

class TransactionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // Collection reference
  CollectionReference get _transactionsRef => _db.collection('transactions');

  /// Create a new transaction record
  Future<TransactionModel> createTransaction({
    required String senderWallet,
    required String senderName,
    String? senderPhoto,
    required String receiverWallet,
    required String receiverName,
    String? receiverPhoto,
    required String amount,
    required String token,
    required int chainId,
    required String chainName,
    required TransactionType type,
    String? memo,
    double? amountInIdr,
  }) async {
    try {
      final docRef = _transactionsRef.doc();
      final now = DateTime.now();

      final transaction = TransactionModel(
        id: docRef.id,
        senderWallet: senderWallet.toLowerCase(),
        senderName: senderName,
        senderPhoto: senderPhoto,
        receiverWallet: receiverWallet.toLowerCase(),
        receiverName: receiverName,
        receiverPhoto: receiverPhoto,
        amount: amount,
        token: token,
        chainId: chainId,
        chainName: chainName,
        type: type,
        status: TransactionStatus.pending,
        memo: memo,
        createdAt: now,
        amountInIdr: amountInIdr,
      );

      await docRef.set(transaction.toJson());
      print('[TransactionService] Created transaction: ${docRef.id}');

      return transaction;
    } catch (e) {
      print('[TransactionService] Error creating transaction: $e');
      rethrow;
    }
  }

  /// Update transaction status after blockchain confirmation
  Future<void> updateTransactionStatus({
    required String transactionId,
    required TransactionStatus status,
    String? txHash,
    String? failureReason,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': status.name,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (txHash != null) {
        updateData['tx_hash'] = txHash;
      }

      if (status == TransactionStatus.completed) {
        updateData['completed_at'] = FieldValue.serverTimestamp();
      }

      if (failureReason != null) {
        updateData['failure_reason'] = failureReason;
      }

      await _transactionsRef.doc(transactionId).update(updateData);
      print('[TransactionService] Updated transaction $transactionId to $status');

      // Get transaction details for notification
      final txDoc = await _transactionsRef.doc(transactionId).get();
      if (txDoc.exists) {
        final tx = TransactionModel.fromJson(
          txDoc.data() as Map<String, dynamic>,
          txDoc.id,
        );

        // Send notifications based on status
        if (status == TransactionStatus.completed) {
          await _sendTransferNotifications(tx);
        } else if (status == TransactionStatus.failed) {
          await _sendFailureNotification(tx, failureReason);
        }
      }
    } catch (e) {
      print('[TransactionService] Error updating transaction: $e');
      rethrow;
    }
  }

  /// Send notifications for completed transfer
  Future<void> _sendTransferNotifications(TransactionModel tx) async {
    print('[TransactionService] Sending notifications for tx: ${tx.id}');
    print('[TransactionService] Sender: ${tx.senderWallet}, Receiver: ${tx.receiverWallet}');
    
    // Notification for receiver
    try {
      await _notificationService.createNotification(
        userId: tx.receiverWallet,
        type: NotificationType.transferReceived,
        title: 'Payment Received',
        body: 'You received ${tx.formattedAmount} ${tx.token} from ${tx.senderName}',
        imageUrl: tx.senderPhoto,
        data: {
          'transaction_id': tx.id,
          'amount': tx.amount,
          'token': tx.token,
          'sender_wallet': tx.senderWallet,
          'sender_name': tx.senderName,
        },
      );
      print('[TransactionService] Receiver notification sent to: ${tx.receiverWallet}');
    } catch (e) {
      print('[TransactionService] Error sending receiver notification: $e');
    }

    // Notification for sender (skip if sender is 'faucet' for top-up)
    if (tx.senderWallet.toLowerCase() != 'faucet') {
      try {
        await _notificationService.createNotification(
          userId: tx.senderWallet,
          type: NotificationType.transferSent,
          title: 'Transfer Successful',
          body: 'You sent ${tx.formattedAmount} ${tx.token} to ${tx.receiverName}',
          imageUrl: tx.receiverPhoto,
          data: {
            'transaction_id': tx.id,
            'amount': tx.amount,
            'token': tx.token,
            'receiver_wallet': tx.receiverWallet,
            'receiver_name': tx.receiverName,
          },
        );
        print('[TransactionService] Sender notification sent to: ${tx.senderWallet}');
      } catch (e) {
        print('[TransactionService] Error sending sender notification: $e');
      }
    }
    
    // Top-up notification (if type is topUp, send to receiver)
    if (tx.type == TransactionType.topUp) {
      try {
        await _notificationService.createNotification(
          userId: tx.receiverWallet,
          type: NotificationType.topUpSuccess,
          title: 'Top Up Successful',
          body: 'Your wallet has been topped up with ${tx.formattedAmount} ${tx.token}',
          data: {
            'transaction_id': tx.id,
            'amount': tx.amount,
            'token': tx.token,
          },
        );
        print('[TransactionService] Top-up notification sent to: ${tx.receiverWallet}');
      } catch (e) {
        print('[TransactionService] Error sending top-up notification: $e');
      }
    }
  }

  /// Send failure notification
  Future<void> _sendFailureNotification(TransactionModel tx, String? reason) async {
    await _notificationService.createNotification(
      userId: tx.senderWallet,
      type: NotificationType.transferFailed,
      title: 'Transfer Failed',
      body: 'Failed to send ${tx.formattedAmount} ${tx.token} to ${tx.receiverName}. ${reason ?? ''}',
      data: {
        'transaction_id': tx.id,
        'amount': tx.amount,
        'token': tx.token,
        'failure_reason': reason,
      },
    );
  }

  /// Get transactions for a wallet (as sender or receiver)
  Future<List<TransactionModel>> getTransactions({
    required String walletAddress,
    int limit = 50,
    TransactionType? typeFilter,
    TransactionStatus? statusFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final normalizedWallet = walletAddress.toLowerCase();
      print('[TransactionService] Getting transactions for: $normalizedWallet');

      QuerySnapshot sentSnapshot;
      QuerySnapshot receivedSnapshot;

      try {
        // Try with orderBy (requires composite index)
        Query sentQuery = _transactionsRef
            .where('sender_wallet', isEqualTo: normalizedWallet)
            .orderBy('created_at', descending: true);

        Query receivedQuery = _transactionsRef
            .where('receiver_wallet', isEqualTo: normalizedWallet)
            .orderBy('created_at', descending: true);

        sentSnapshot = await sentQuery.limit(limit).get();
        receivedSnapshot = await receivedQuery.limit(limit).get();
      } catch (indexError) {
        // Fallback: query without orderBy if index not ready
        print('[TransactionService] Index not ready, using fallback query: $indexError');
        
        Query sentQuery = _transactionsRef
            .where('sender_wallet', isEqualTo: normalizedWallet);

        Query receivedQuery = _transactionsRef
            .where('receiver_wallet', isEqualTo: normalizedWallet);

        sentSnapshot = await sentQuery.limit(limit).get();
        receivedSnapshot = await receivedQuery.limit(limit).get();
      }

      print('[TransactionService] Found ${sentSnapshot.docs.length} sent, ${receivedSnapshot.docs.length} received');

      // Combine and sort results
      final List<TransactionModel> transactions = [];

      for (final doc in sentSnapshot.docs) {
        transactions.add(TransactionModel.fromJson(
          doc.data() as Map<String, dynamic>,
          doc.id,
        ));
      }

      for (final doc in receivedSnapshot.docs) {
        // Avoid duplicates (self-transfer)
        if (!transactions.any((t) => t.id == doc.id)) {
          transactions.add(TransactionModel.fromJson(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ));
        }
      }

      // Also fetch from backend API (for split bill transactions)
      // Only include backend transactions if they're not duplicates
      try {
        final backendTxs = await _fetchBackendTransactions(normalizedWallet);
        print('[TransactionService] Found ${backendTxs.length} backend transactions');
        for (final tx in backendTxs) {
          // Skip if already exists in Firestore transactions
          if (!transactions.any((t) => t.id == tx.id || t.txHash == tx.txHash)) {
            transactions.add(tx);
          }
        }
      } catch (e) {
        print('[TransactionService] Backend fetch failed: $e');
      }

      // Sort by created_at descending (always sort in memory for consistency)
      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Apply date filters in memory
      var filtered = transactions;
      if (startDate != null) {
        filtered = filtered.where((t) => t.createdAt.isAfter(startDate)).toList();
      }
      if (endDate != null) {
        filtered = filtered.where((t) => t.createdAt.isBefore(endDate)).toList();
      }

      return filtered.take(limit).toList();
    } catch (e) {
      print('[TransactionService] Error getting transactions: $e');
      return [];
    }
  }

  /// Get recent transactions (last 3)
  Future<List<TransactionModel>> getRecentTransactions(String walletAddress) async {
    print('[TransactionService] getRecentTransactions for: $walletAddress');
    final result = await getTransactions(walletAddress: walletAddress, limit: 3);
    print('[TransactionService] getRecentTransactions found: ${result.length} transactions');
    for (final tx in result) {
      print('[TransactionService] - ${tx.id}: ${tx.amount} ${tx.token} (${tx.status.name})');
    }
    return result;
  }

  /// Get transaction by ID
  Future<TransactionModel?> getTransactionById(String transactionId) async {
    try {
      final doc = await _transactionsRef.doc(transactionId).get();
      if (doc.exists) {
        return TransactionModel.fromJson(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }
      return null;
    } catch (e) {
      print('[TransactionService] Error getting transaction: $e');
      return null;
    }
  }

  /// Stream of transactions for real-time updates
  /// Merges both sent and received transaction streams for proper real-time updates
  Stream<List<TransactionModel>> transactionsStream(String walletAddress) {
    final normalizedWallet = walletAddress.toLowerCase();
    print('[TransactionService] Starting stream for wallet: $normalizedWallet');

    // Create streams for both sent and received transactions
    final sentStream = _transactionsRef
        .where('sender_wallet', isEqualTo: normalizedWallet)
        .orderBy('created_at', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          print('[TransactionService] Sent stream: ${snapshot.docs.length} docs');
          return snapshot;
        });

    final receivedStream = _transactionsRef
        .where('receiver_wallet', isEqualTo: normalizedWallet)
        .orderBy('created_at', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          print('[TransactionService] Received stream: ${snapshot.docs.length} docs');
          return snapshot;
        });

    // Use MergeStream to listen to both streams independently
    // This ensures updates from either stream trigger the listener
    return MergeStream([
      sentStream,
      receivedStream,
    ]).asyncMap((_) async {
      // Fetch latest from both collections
      final sentSnapshot = await _transactionsRef
          .where('sender_wallet', isEqualTo: normalizedWallet)
          .orderBy('created_at', descending: true)
          .limit(20)
          .get();
          
      final receivedSnapshot = await _transactionsRef
          .where('receiver_wallet', isEqualTo: normalizedWallet)
          .orderBy('created_at', descending: true)
          .limit(20)
          .get();

      final List<TransactionModel> transactions = [];
      final Set<String> addedIds = {};

      for (final doc in sentSnapshot.docs) {
        if (!addedIds.contains(doc.id)) {
          transactions.add(TransactionModel.fromJson(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ));
          addedIds.add(doc.id);
        }
      }

      for (final doc in receivedSnapshot.docs) {
        if (!addedIds.contains(doc.id)) {
          transactions.add(TransactionModel.fromJson(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ));
          addedIds.add(doc.id);
        }
      }

      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      print('[TransactionService] Stream update: ${transactions.length} total transactions');
      return transactions.take(20).toList();
    });
  }

  /// Get transaction statistics
  Future<Map<String, dynamic>> getTransactionStats(String walletAddress) async {
    try {
      final transactions = await getTransactions(
        walletAddress: walletAddress,
        limit: 1000,
      );

      final normalizedWallet = walletAddress.toLowerCase();

      double totalSent = 0;
      double totalReceived = 0;
      int sendCount = 0;
      int receiveCount = 0;

      for (final tx in transactions) {
        if (tx.status != TransactionStatus.completed) continue;

        final amount = double.tryParse(tx.amount) ?? 0;

        if (tx.senderWallet == normalizedWallet) {
          totalSent += amount;
          sendCount++;
        } else {
          totalReceived += amount;
          receiveCount++;
        }
      }

      return {
        'total_sent': totalSent,
        'total_received': totalReceived,
        'send_count': sendCount,
        'receive_count': receiveCount,
        'net_flow': totalReceived - totalSent,
      };
    } catch (e) {
      print('[TransactionService] Error getting stats: $e');
      return {};
    }
  }

  /// Fetch transactions from backend API (for split bill, etc.)
  Future<List<TransactionModel>> _fetchBackendTransactions(String walletAddress) async {
    try {
      final response = await http.get(
        Uri.parse('${Env.backendUrl}/transactions/${walletAddress.toLowerCase()}'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print('[TransactionService] Backend returned ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true || data['data'] == null) {
        return [];
      }

      final List<TransactionModel> transactions = [];
      for (final tx in data['data']) {
        try {
          final txType = tx['tx_type'] ?? '';
          final isSplitBillSent = txType == 'split_bill_sent';
          final isSplitBillReceived = txType == 'split_bill_received';
          
          TransactionType type = isSplitBillSent ? TransactionType.send : TransactionType.receive;
          if (txType == 'swap') {
            type = TransactionType.swap;
          }

          final createdAt = tx['created_at'] != null 
              ? DateTime.parse(tx['created_at']) 
              : DateTime.now();

          transactions.add(TransactionModel(
            id: tx['payment_id'] ?? '',
            senderWallet: isSplitBillSent ? walletAddress : (tx['counterparty'] ?? ''),
            senderName: isSplitBillSent ? 'You' : (tx['merchant_name'] ?? 'Split Bill'),
            receiverWallet: isSplitBillReceived ? walletAddress : (tx['counterparty'] ?? ''),
            receiverName: isSplitBillReceived ? 'You' : (tx['merchant_name'] ?? 'Split Bill'),
            amount: tx['lsk_amount']?.toString() ?? '0',
            token: tx['token_symbol'] ?? 'LSK',
            chainId: 4202,
            chainName: 'Lisk Sepolia',
            type: type,
            status: tx['status'] == 'completed' ? TransactionStatus.completed : TransactionStatus.pending,
            txHash: tx['tx_hash'],
            createdAt: createdAt,
            memo: tx['merchant_name'],
          ));
        } catch (e) {
          print('[TransactionService] Error parsing backend tx: $e');
        }
      }

      return transactions;
    } catch (e) {
      print('[TransactionService] Backend fetch error: $e');
      return [];
    }
  }
}
