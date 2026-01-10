import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentRequestStatus {
  pending,
  paid,
  cancelled,
  expired,
}

class PaymentRequestModel {
  final String id;
  final String requesterWallet;
  final String requesterName;
  final String? requesterPhoto;
  final String payerWallet;
  final String payerName;
  final String? payerPhoto;
  final String amount;
  final String token;
  final int chainId;
  final String chainName;
  final String? memo;
  final PaymentRequestStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? paidAt;
  final String? txHash;

  PaymentRequestModel({
    required this.id,
    required this.requesterWallet,
    required this.requesterName,
    this.requesterPhoto,
    required this.payerWallet,
    required this.payerName,
    this.payerPhoto,
    required this.amount,
    required this.token,
    required this.chainId,
    required this.chainName,
    this.memo,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.paidAt,
    this.txHash,
  });

  factory PaymentRequestModel.fromJson(Map<String, dynamic> json, String docId) {
    return PaymentRequestModel(
      id: docId,
      requesterWallet: json['requester_wallet'] ?? '',
      requesterName: json['requester_name'] ?? 'Unknown',
      requesterPhoto: json['requester_photo'],
      payerWallet: json['payer_wallet'] ?? '',
      payerName: json['payer_name'] ?? 'Unknown',
      payerPhoto: json['payer_photo'],
      amount: json['amount'] ?? '0',
      token: json['token'] ?? 'LSK',
      chainId: json['chain_id'] ?? 4202,
      chainName: json['chain_name'] ?? 'Lisk Sepolia',
      memo: json['memo'],
      status: PaymentRequestStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => PaymentRequestStatus.pending,
      ),
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (json['expires_at'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 7)),
      paidAt: (json['paid_at'] as Timestamp?)?.toDate(),
      txHash: json['tx_hash'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requester_wallet': requesterWallet,
      'requester_name': requesterName,
      'requester_photo': requesterPhoto,
      'payer_wallet': payerWallet,
      'payer_name': payerName,
      'payer_photo': payerPhoto,
      'amount': amount,
      'token': token,
      'chain_id': chainId,
      'chain_name': chainName,
      'memo': memo,
      'status': status.name,
      'created_at': Timestamp.fromDate(createdAt),
      'expires_at': Timestamp.fromDate(expiresAt),
      'paid_at': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'tx_hash': txHash,
    };
  }

  PaymentRequestModel copyWith({
    String? id,
    String? requesterWallet,
    String? requesterName,
    String? requesterPhoto,
    String? payerWallet,
    String? payerName,
    String? payerPhoto,
    String? amount,
    String? token,
    int? chainId,
    String? chainName,
    String? memo,
    PaymentRequestStatus? status,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? paidAt,
    String? txHash,
  }) {
    return PaymentRequestModel(
      id: id ?? this.id,
      requesterWallet: requesterWallet ?? this.requesterWallet,
      requesterName: requesterName ?? this.requesterName,
      requesterPhoto: requesterPhoto ?? this.requesterPhoto,
      payerWallet: payerWallet ?? this.payerWallet,
      payerName: payerName ?? this.payerName,
      payerPhoto: payerPhoto ?? this.payerPhoto,
      amount: amount ?? this.amount,
      token: token ?? this.token,
      chainId: chainId ?? this.chainId,
      chainName: chainName ?? this.chainName,
      memo: memo ?? this.memo,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      paidAt: paidAt ?? this.paidAt,
      txHash: txHash ?? this.txHash,
    );
  }

  String get formattedAmount {
    final double amt = double.tryParse(amount) ?? 0;
    if (amt >= 1) {
      return amt.toStringAsFixed(4);
    } else {
      return amt.toStringAsFixed(8);
    }
  }

  String get truncatedRequesterWallet {
    if (requesterWallet.length > 12) {
      return '${requesterWallet.substring(0, 6)}...${requesterWallet.substring(requesterWallet.length - 4)}';
    }
    return requesterWallet;
  }

  String get truncatedPayerWallet {
    if (payerWallet.length > 12) {
      return '${payerWallet.substring(0, 6)}...${payerWallet.substring(payerWallet.length - 4)}';
    }
    return payerWallet;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  String get timeUntilExpiry {
    if (isExpired) return 'Expired';
    final difference = expiresAt.difference(DateTime.now());
    if (difference.inDays > 0) {
      return '${difference.inDays}d left';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h left';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m left';
    } else {
      return 'Expiring soon';
    }
  }
}
