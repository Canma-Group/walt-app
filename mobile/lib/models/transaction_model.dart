import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType {
  send,
  receive,
  swap,
  requestPayment,
  qrisPayment,
  topUp,
}

enum TransactionStatus {
  pending,
  completed,
  failed,
  cancelled,
  expired,
}

class TransactionModel {
  final String id;
  final String senderWallet;
  final String senderName;
  final String? senderPhoto;
  final String receiverWallet;
  final String receiverName;
  final String? receiverPhoto;
  final String amount;
  final String token;
  final int chainId;
  final String chainName;
  final TransactionType type;
  final TransactionStatus status;
  final String? txHash;
  final String? memo;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? failureReason;
  final double? amountInIdr;
  
  // Swap-specific fields
  final String? fromAmount;
  final String? fromToken;
  final String? toAmount;
  final String? toToken;

  TransactionModel({
    required this.id,
    required this.senderWallet,
    required this.senderName,
    this.senderPhoto,
    required this.receiverWallet,
    required this.receiverName,
    this.receiverPhoto,
    required this.amount,
    required this.token,
    required this.chainId,
    required this.chainName,
    required this.type,
    required this.status,
    this.txHash,
    this.memo,
    required this.createdAt,
    this.completedAt,
    this.failureReason,
    this.amountInIdr,
    this.fromAmount,
    this.fromToken,
    this.toAmount,
    this.toToken,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json, String docId) {
    return TransactionModel(
      id: docId,
      senderWallet: json['sender_wallet'] ?? '',
      senderName: json['sender_name'] ?? 'Unknown',
      senderPhoto: json['sender_photo'],
      receiverWallet: json['receiver_wallet'] ?? '',
      receiverName: json['receiver_name'] ?? 'Unknown',
      receiverPhoto: json['receiver_photo'],
      amount: (json['amount'] ?? '0').toString(),
      token: json['token'] ?? 'LSK',
      chainId: json['chain_id'] ?? 4202,
      chainName: json['chain_name'] ?? 'Lisk Sepolia',
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransactionType.send,
      ),
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TransactionStatus.pending,
      ),
      txHash: json['tx_hash'],
      memo: json['memo'],
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (json['completed_at'] as Timestamp?)?.toDate(),
      failureReason: json['failure_reason'],
      amountInIdr: (json['amount_idr'] as num?)?.toDouble(),
      fromAmount: json['from_amount']?.toString(),
      fromToken: json['from_token'],
      toAmount: json['to_amount']?.toString(),
      toToken: json['to_token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sender_wallet': senderWallet,
      'sender_name': senderName,
      'sender_photo': senderPhoto,
      'receiver_wallet': receiverWallet,
      'receiver_name': receiverName,
      'receiver_photo': receiverPhoto,
      'amount': amount,
      'token': token,
      'chain_id': chainId,
      'chain_name': chainName,
      'type': type.name,
      'status': status.name,
      'tx_hash': txHash,
      'memo': memo,
      'created_at': Timestamp.fromDate(createdAt),
      'completed_at': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'failure_reason': failureReason,
      'amount_idr': amountInIdr,
    };
  }

  TransactionModel copyWith({
    String? id,
    String? senderWallet,
    String? senderName,
    String? senderPhoto,
    String? receiverWallet,
    String? receiverName,
    String? receiverPhoto,
    String? amount,
    String? token,
    int? chainId,
    String? chainName,
    TransactionType? type,
    TransactionStatus? status,
    String? txHash,
    String? memo,
    DateTime? createdAt,
    DateTime? completedAt,
    String? failureReason,
    double? amountInIdr,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      senderWallet: senderWallet ?? this.senderWallet,
      senderName: senderName ?? this.senderName,
      senderPhoto: senderPhoto ?? this.senderPhoto,
      receiverWallet: receiverWallet ?? this.receiverWallet,
      receiverName: receiverName ?? this.receiverName,
      receiverPhoto: receiverPhoto ?? this.receiverPhoto,
      amount: amount ?? this.amount,
      token: token ?? this.token,
      chainId: chainId ?? this.chainId,
      chainName: chainName ?? this.chainName,
      type: type ?? this.type,
      status: status ?? this.status,
      txHash: txHash ?? this.txHash,
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      failureReason: failureReason ?? this.failureReason,
      amountInIdr: amountInIdr ?? this.amountInIdr,
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

  String get truncatedSenderWallet {
    if (senderWallet.length > 12) {
      return '${senderWallet.substring(0, 6)}...${senderWallet.substring(senderWallet.length - 4)}';
    }
    return senderWallet;
  }

  String get truncatedReceiverWallet {
    if (receiverWallet.length > 12) {
      return '${receiverWallet.substring(0, 6)}...${receiverWallet.substring(receiverWallet.length - 4)}';
    }
    return receiverWallet;
  }

  bool isSender(String walletAddress) {
    return senderWallet.toLowerCase() == walletAddress.toLowerCase();
  }

  bool isReceiver(String walletAddress) {
    return receiverWallet.toLowerCase() == walletAddress.toLowerCase();
  }
}
