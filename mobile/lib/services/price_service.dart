import 'dart:convert';
import 'package:http/http.dart' as http;

/// Price data from Indodax including 24h changes
class IndodaxTicker {
  final double last;      // Last traded price
  final double buy;       // Best buy price
  final double sell;      // Best sell price
  final double high;      // 24h high
  final double low;       // 24h low
  final double volume;    // 24h volume in IDR
  final String name;      // Token name

  IndodaxTicker({
    required this.last,
    required this.buy,
    required this.sell,
    required this.high,
    required this.low,
    required this.volume,
    required this.name,
  });

  factory IndodaxTicker.fromJson(Map<String, dynamic> json) {
    return IndodaxTicker(
      last: double.tryParse(json['last']?.toString() ?? '0') ?? 0,
      buy: double.tryParse(json['buy']?.toString() ?? '0') ?? 0,
      sell: double.tryParse(json['sell']?.toString() ?? '0') ?? 0,
      high: double.tryParse(json['high']?.toString() ?? '0') ?? 0,
      low: double.tryParse(json['low']?.toString() ?? '0') ?? 0,
      volume: double.tryParse(json['vol_idr']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}

class PriceService {
  // Backend proxy for Indodax prices (phone can't reach Indodax directly)
  static const String _backendPriceApi = 'http://203.194.112.143:3000/prices';
  
  // Fallback: Direct Indodax API (if backend unavailable)
  static const String _indodaxApi = 'https://indodax.com/api';
  
  // Token pair mapping for Indodax (symbol -> ticker_id format)
  // Based on /api/pairs response, ticker_id uses underscore format like "btc_idr"
  static const Map<String, String> _indodaxPairs = {
    'POL': 'pol_idr',       // Polygon (POL)
    'MATIC': 'matic_idr',   // Polygon (legacy MATIC)
    'ETH': 'eth_idr',       // Ethereum
    'BTC': 'btc_idr',       // Bitcoin
    'USDT': 'usdt_idr',     // Tether
    'USDC': 'usdc_idr',     // USD Coin
    'LSK': 'lsk_idr',       // Lisk
    'SOL': 'sol_idr',       // Solana
    'BNB': 'bnb_idr',       // Binance Coin
    'XRP': 'xrp_idr',       // Ripple
    'DOGE': 'doge_idr',     // Dogecoin
    'ADA': 'ada_idr',       // Cardano
    'DOT': 'dot_idr',       // Polkadot
    'LINK': 'link_idr',     // Chainlink
    'UNI': 'uni_idr',       // Uniswap
    'AVAX': 'avax_idr',     // Avalanche
    'SHIB': 'shib_idr',     // Shiba Inu
  };
  
  // Fallback prices in IDR (updated regularly)
  static const Map<String, double> _fallbackPricesIDR = {
    'POL': 7500,
    'MATIC': 7500,
    'ETH': 58500000,
    'BTC': 1586500000,
    'LSK': 3200,
    'USDT': 16700,
    'USDC': 16700,
    'SOL': 3000000,
    'BNB': 10000000,
    'XRP': 31950,
    'DOGE': 2245,
    'ADA': 6200,
    'DOT': 33500,
    'LINK': 218000,
    'UNI': 99350,
    'AVAX': 223000,
    'SHIB': 0.37,     // Fixed SHIB price in IDR (was showing 0)
  };

  // Cache
  static Map<String, double> _priceCacheIDR = {};
  static Map<String, IndodaxTicker> _tickerCache = {};
  static Map<String, double> _prices24hAgo = {};
  static DateTime? _lastFetch;
  static DateTime? _lastBackendFailure;
  static const Duration _cacheDuration = Duration(seconds: 30); // Cache 30 detik untuk mengurangi spam
  static const Duration _backendCooldown = Duration(minutes: 1); // Cooldown setelah backend gagal
  
  // USD to IDR rate
  static const double _usdToIdr = 16700;

  final http.Client _httpClient;

  PriceService() : _httpClient = http.Client();

  /// Fetch all prices from Backend (which proxies to Indodax)
  /// Backend can reach Indodax, phone may not be able to
  /// Updates every 5 seconds for accurate LSK/IDR conversion
  Future<Map<String, double>> fetchPricesIDR(List<String> symbols) async {
    // Check cache (5 seconds)
    if (_lastFetch != null && 
        DateTime.now().difference(_lastFetch!) < _cacheDuration &&
        _priceCacheIDR.isNotEmpty) {
      final cached = <String, double>{};
      bool allFound = true;
      for (final symbol in symbols) {
        if (_priceCacheIDR.containsKey(symbol.toUpperCase())) {
          cached[symbol.toUpperCase()] = _priceCacheIDR[symbol.toUpperCase()]!;
        } else {
          allFound = false;
        }
      }
      if (allFound) return cached;
    }

    final prices = <String, double>{};

    // Skip backend if in cooldown after failure
    final shouldSkipBackend = _lastBackendFailure != null && 
        DateTime.now().difference(_lastBackendFailure!) < _backendCooldown;
    
    // Try backend first (backend can reach Indodax)
    if (!shouldSkipBackend) {
      try {
        final response = await _httpClient.get(
          Uri.parse(_backendPriceApi),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && data['prices'] != null) {
            final backendPrices = data['prices'] as Map<String, dynamic>;
            
            for (final entry in backendPrices.entries) {
              final symbol = entry.key.toUpperCase();
              final price = (entry.value is num) ? entry.value.toDouble() : double.tryParse(entry.value.toString()) ?? 0;
              if (price > 0) {
                prices[symbol] = price;
              }
            }
            
            // Update cache
            _priceCacheIDR = {..._priceCacheIDR, ...prices};
            _lastFetch = DateTime.now();
            _lastBackendFailure = null; // Reset failure state on success
          }
        }
      } catch (e) {
        // Set cooldown to avoid spamming failed backend
        _lastBackendFailure = DateTime.now();
        print('[PriceService] Backend proxy failed, using fallback for 1 minute');
      }
    }
    
    // Fallback: Try direct Indodax if no prices yet
    if (prices.isEmpty) {
      try {
        final response = await _httpClient.get(
          Uri.parse('$_indodaxApi/summaries'),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final tickers = data['tickers'] as Map<String, dynamic>?;
          
          if (tickers != null) {
            for (final entry in _indodaxPairs.entries) {
              final symbol = entry.key;
              final pair = entry.value;
              final ticker = tickers[pair];
              if (ticker != null) {
                final tickerData = IndodaxTicker.fromJson(ticker);
                _tickerCache[symbol] = tickerData;
                prices[symbol] = tickerData.last;
              }
            }
          }
          
          _priceCacheIDR = {..._priceCacheIDR, ...prices};
          _lastFetch = DateTime.now();
        }
      } catch (e2) {
        // Silent fail - will use fallback prices
      }
    }
    
    // Use fallback for missing symbols
    for (final symbol in symbols) {
      final upperSymbol = symbol.toUpperCase();
      if (!prices.containsKey(upperSymbol) && _fallbackPricesIDR.containsKey(upperSymbol)) {
        prices[upperSymbol] = _fallbackPricesIDR[upperSymbol]!;
        // Disabled verbose fallback logging
        // if (Env.enableDebugLogs) print('[PriceService] Fallback $upperSymbol: Rp ${_fallbackPricesIDR[upperSymbol]}');
      }
    }

    return prices;
  }

  /// Get 24h price change percentage for a symbol
  double get24hChangePercent(String symbol) {
    final current = _priceCacheIDR[symbol.toUpperCase()];
    final ago = _prices24hAgo[symbol.toUpperCase()];
    if (current == null || ago == null || ago == 0) return 0;
    return ((current - ago) / ago) * 100;
  }

  /// Get full ticker data for a symbol
  IndodaxTicker? getTicker(String symbol) {
    return _tickerCache[symbol.toUpperCase()];
  }

  /// Fetch prices in USD (converted from IDR)
  Future<Map<String, double>> fetchPricesUSD(List<String> symbols) async {
    final idrPrices = await fetchPricesIDR(symbols);
    
    final usdPrices = <String, double>{};
    for (final entry in idrPrices.entries) {
      usdPrices[entry.key] = entry.value / _usdToIdr;
    }
    
    return usdPrices;
  }

  double get usdToIdr => _usdToIdr;

  /// Clear all cached data (call on logout)
  static void clearCache() {
    _priceCacheIDR.clear();
    _tickerCache.clear();
    _prices24hAgo.clear();
    _lastFetch = null;
  }

  Future<TotalBalanceResult> calculateTotalIDR(List<TokenBalanceInput> balances) async {
    final symbols = balances.map((b) => b.symbol).toList();
    final pricesUSD = await fetchPricesUSD(symbols);
    
    double totalUSD = 0;
    final tokens = <TokenWithPrice>[];

    for (final balance in balances) {
      final priceUSD = pricesUSD[balance.symbol.toUpperCase()] ?? 0;
      final priceIDR = priceUSD * _usdToIdr;
      final valueUSD = balance.balance * priceUSD;
      final valueIDR = balance.balance * priceIDR;
      
      totalUSD += valueUSD;
      
      tokens.add(TokenWithPrice(
        symbol: balance.symbol,
        balance: balance.balance,
        priceUSD: priceUSD,
        priceIDR: priceIDR,
        valueUSD: valueUSD,
        valueIDR: valueIDR,
      ));
    }

    return TotalBalanceResult(
      tokens: tokens,
      totalUSD: totalUSD,
      totalIDR: totalUSD * _usdToIdr,
    );
  }

  void dispose() {
    _httpClient.close();
  }
}

class TokenBalanceInput {
  final String symbol;
  final double balance;

  TokenBalanceInput({required this.symbol, required this.balance});
}

class TokenWithPrice {
  final String symbol;
  final double balance;
  final double priceUSD;
  final double priceIDR;
  final double valueUSD;
  final double valueIDR;

  TokenWithPrice({
    required this.symbol,
    required this.balance,
    required this.priceUSD,
    required this.priceIDR,
    required this.valueUSD,
    required this.valueIDR,
  });
}

class TotalBalanceResult {
  final List<TokenWithPrice> tokens;
  final double totalUSD;
  final double totalIDR;

  TotalBalanceResult({
    required this.tokens,
    required this.totalUSD,
    required this.totalIDR,
  });

  String get totalIDRFormatted {
    if (totalIDR >= 1000000) {
      return 'Rp ${(totalIDR / 1000000).toStringAsFixed(2)} Jt';
    } else if (totalIDR >= 1000) {
      return 'Rp ${(totalIDR / 1000).toStringAsFixed(0)} Rb';
    }
    return 'Rp ${totalIDR.toStringAsFixed(0)}';
  }

  String get totalIDRFullFormatted {
    final formatted = totalIDR.toStringAsFixed(0);
    // Add thousand separators
    final chars = formatted.split('').reversed.toList();
    final result = <String>[];
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) result.add('.');
      result.add(chars[i]);
    }
    return 'Rp ${result.reversed.join('')}';
  }
}
