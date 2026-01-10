import '../config/env.dart';
import 'package:flutter/foundation.dart';

class NetworkInfo {
  final String rpcUrl;
  final String name;

  const NetworkInfo({
    required this.rpcUrl,
    required this.name,
  });

  NetworkInfo copyWith({
    String? rpcUrl,
    String? name,
  }) {
    return NetworkInfo(
      rpcUrl: rpcUrl ?? this.rpcUrl,
      name: name ?? this.name,
    );
  }
}

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final ValueNotifier<NetworkInfo> _activeNetwork = ValueNotifier(
    const NetworkInfo(
      rpcUrl: Env.liskRpcUrl,
      name: Env.liskChainName,
    ),
  );

  ValueListenable<NetworkInfo> get activeNetworkListenable => _activeNetwork;
  NetworkInfo get activeNetwork => _activeNetwork.value;

  void setActiveNetwork({
    required String rpcUrl,
    required String name,
  }) {
    if (_activeNetwork.value.rpcUrl == rpcUrl && _activeNetwork.value.name == name) {
      return;
    }

    _activeNetwork.value = NetworkInfo(rpcUrl: rpcUrl, name: name);
  }
}
