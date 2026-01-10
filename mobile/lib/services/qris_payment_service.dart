import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/env.dart';

class QrisPaymentIntent {
  final String paymentId;
  final String? orderId; // bytes32 orderId for contract call
  final String escrowAddress;
  final double amountIdr;
  final String lskAmountExpected;
  final String lskTokenAddress;
  final int chainId;
  final DateTime expiresAt;
  final int? platformFeeBps;
  final String? calldata; // V3: pre-generated calldata for contract call
  final String? tokenAmountWei; // V3: amount in wei

  QrisPaymentIntent({
    required this.paymentId,
    this.orderId,
    required this.escrowAddress,
    required this.amountIdr,
    required this.lskAmountExpected,
    required this.lskTokenAddress,
    required this.chainId,
    required this.expiresAt,
    this.platformFeeBps,
    this.calldata,
    this.tokenAmountWei,
  });

  factory QrisPaymentIntent.fromJson(Map<String, dynamic> json) {
    final amountValue = json['amountIdr'];
    final amountIdr = amountValue is num 
        ? amountValue.toDouble() 
        : double.tryParse(amountValue?.toString() ?? '0') ?? 0.0;
    
    return QrisPaymentIntent(
      paymentId: json['paymentId'] ?? '',
      orderId: json['orderId'],
      escrowAddress: json['escrowAddress'] ?? '',
      amountIdr: amountIdr,
      lskAmountExpected: json['lskAmountExpected'] ?? '0',
      lskTokenAddress: json['lskTokenAddress'] ?? '',
      chainId: json['chainId'] ?? 4202,
      expiresAt: DateTime.tryParse(json['expiresAt'] ?? '') ?? DateTime.now(),
      platformFeeBps: json['platformFeeBps'],
    );
  }
}

class QrisPaymentStatus {
  final String paymentId;
  final String status;
  final double amountIdr;
  final String lskAmountExpected;
  final String escrowAddress;
  final String? txHash;
  final String? receiptId;
  final String? merchantName;
  final DateTime? verifiedAt;

  QrisPaymentStatus({
    required this.paymentId,
    required this.status,
    required this.amountIdr,
    required this.lskAmountExpected,
    required this.escrowAddress,
    this.txHash,
    this.receiptId,
    this.merchantName,
    this.verifiedAt,
  });

  factory QrisPaymentStatus.fromJson(Map<String, dynamic> json) {
    final amountValue = json['amount_idr'] ?? json['amountIdr'];
    final amountIdr = amountValue is num 
        ? amountValue.toDouble() 
        : double.tryParse(amountValue?.toString() ?? '0') ?? 0.0;
    
    return QrisPaymentStatus(
      paymentId: json['payment_id'] ?? json['paymentId'] ?? '',
      status: json['status'] ?? 'UNKNOWN',
      amountIdr: amountIdr,
      lskAmountExpected: json['lsk_amount_expected'] ?? json['lskAmountExpected'] ?? '0',
      escrowAddress: json['escrow_address'] ?? json['escrowAddress'] ?? '',
      txHash: json['tx_hash'] ?? json['txHash'],
      receiptId: json['receipt_id'] ?? json['receiptId'],
      merchantName: json['merchant_name'] ?? json['merchantName'],
      verifiedAt: json['verified_at'] != null 
          ? DateTime.tryParse(json['verified_at']) 
          : null,
    );
  }

  bool get isPaid => status == 'PAID';
  bool get isPending => status == 'CREATED' || status == 'TX_SUBMITTED';
  bool get isExpired => status == 'EXPIRED';
}

class QrisPaymentService {
  final String _backendUrl;
  final http.Client _httpClient;

  QrisPaymentService({
    String? backendUrl,
    http.Client? httpClient,
  }) : _backendUrl = backendUrl ?? 'http://203.194.112.143:3000',
       _httpClient = httpClient ?? http.Client();

  Future<QrisPaymentIntent> createPaymentIntent({
    required String walletAddress,
    required String qrisPayload,
    required double amountIdr,
  }) async {
    try {
      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] Creating payment intent...');
        print('[QrisPaymentService] Backend: $_backendUrl');
        print('[QrisPaymentService] Wallet: $walletAddress');
        print('[QrisPaymentService] Amount: $amountIdr IDR');
      }

      // Use V2 endpoint for escrow contract integration
      final response = await _httpClient.post(
        Uri.parse('$_backendUrl/qris/v2/payments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'walletAddress': walletAddress,
          'qrisPayload': qrisPayload,
          'amountIdr': amountIdr,
        }),
      ).timeout(const Duration(seconds: 30));

      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] Response: ${response.statusCode}');
      }

      // Accept both 200 (OK) and 201 (Created) as success
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return QrisPaymentIntent.fromJson(data['data']);
        }
        throw Exception(data['error'] ?? 'Failed to create payment');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (Env.enableDebugLogs) print('[QrisPaymentService] Error: $e');
      rethrow;
    }
  }

  Future<QrisPaymentStatus> getPaymentStatus(String paymentId) async {
    try {
      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] Getting payment status: $paymentId');
      }

      final response = await _httpClient.get(
        Uri.parse('$_backendUrl/qris/payments/$paymentId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return QrisPaymentStatus.fromJson(data['data']);
        }
        throw Exception(data['error'] ?? 'Failed to get payment status');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (Env.enableDebugLogs) print('[QrisPaymentService] Error: $e');
      rethrow;
    }
  }

  Future<QrisPaymentStatus> submitTxHash(String paymentId, String txHash) async {
    try {
      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] Submitting txHash: $txHash');
      }

      final response = await _httpClient.post(
        Uri.parse('$_backendUrl/qris/payments/$paymentId/tx'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'txHash': txHash}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return QrisPaymentStatus.fromJson(data['data']);
        }
        throw Exception(data['error'] ?? 'Failed to submit transaction');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (Env.enableDebugLogs) print('[QrisPaymentService] Error: $e');
      rethrow;
    }
  }

  /// Create payment intent with V3 (multi-token support)
  Future<QrisPaymentIntent> createPaymentIntentV3({
    required String walletAddress,
    required String qrisPayload,
    required double amountIdr,
    required String tokenSymbol, // LSK, ETH, or POL
  }) async {
    try {
      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] Creating V3 payment intent...');
        print('[QrisPaymentService] Token: $tokenSymbol');
        print('[QrisPaymentService] Amount: $amountIdr IDR');
      }

      final response = await _httpClient.post(
        Uri.parse('$_backendUrl/v3/qris/create-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'walletAddress': walletAddress,
          'qrisPayload': qrisPayload,
          'amountIdr': amountIdr,
          'tokenSymbol': tokenSymbol,
        }),
      ).timeout(const Duration(seconds: 30));

      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] V3 Response: ${response.statusCode}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final paymentData = data['data'];
          // Map V3 response to QrisPaymentIntent (includes calldata)
          return QrisPaymentIntent(
            paymentId: paymentData['paymentId'] ?? '',
            orderId: paymentData['orderId'],
            escrowAddress: paymentData['contractAddress'] ?? '',
            amountIdr: (paymentData['amountIdr'] as num).toDouble(),
            lskAmountExpected: paymentData['tokenAmount'] ?? '0',
            lskTokenAddress: paymentData['token']?['address'] ?? '',
            chainId: paymentData['chainId'] ?? 4202,
            expiresAt: DateTime.tryParse(paymentData['expiresAt'] ?? '') ?? DateTime.now(),
            platformFeeBps: paymentData['platformFeeBps'],
            calldata: paymentData['calldata'], // V3 returns calldata directly
            tokenAmountWei: paymentData['tokenAmountWei'],
          );
        }
        throw Exception(data['error'] ?? 'Failed to create V3 payment');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (Env.enableDebugLogs) print('[QrisPaymentService] V3 Error: $e');
      rethrow;
    }
  }

  /// Notify backend that V3 payment is completed (triggers settlement bot)
  Future<void> notifyV3PaymentCompleted({
    required String paymentId,
    required String txHash,
    required double amountIdr,
    required String tokenSymbol,
    String? merchantName,
  }) async {
    try {
      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] Notifying V3 payment completed: $txHash');
      }

      final response = await _httpClient.post(
        Uri.parse('$_backendUrl/v3/qris/payment-completed'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'paymentId': paymentId,
          'txHash': txHash,
          'amountIdr': amountIdr,
          'tokenSymbol': tokenSymbol,
          'merchantName': merchantName,
        }),
      ).timeout(const Duration(seconds: 15));

      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] V3 completion response: ${response.statusCode}');
      }
    } catch (e) {
      if (Env.enableDebugLogs) print('[QrisPaymentService] V3 completion error: $e');
      // Don't rethrow - payment is already complete on-chain
    }
  }

  /// Get ABI-encoded calldata for pay() function from backend
  Future<Map<String, dynamic>> getPayCalldata(String paymentId, String merchantId) async {
    try {
      if (Env.enableDebugLogs) {
        print('[QrisPaymentService] Getting calldata for: $paymentId');
      }

      final response = await _httpClient.post(
        Uri.parse('$_backendUrl/qris/payments/$paymentId/calldata'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'merchantId': merchantId}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return data['data'] as Map<String, dynamic>;
        }
        throw Exception(data['error'] ?? 'Failed to get calldata');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (Env.enableDebugLogs) print('[QrisPaymentService] Error: $e');
      rethrow;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
