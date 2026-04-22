import 'package:pocket_pilot/src/generated/pocket_pilot/v1/market_price_service.pbgrpc.dart';

/// Server-provided price cache. Natural key: (symbol, exchange). Read-only
/// from the app's perspective: MarketPriceSyncHandler only pulls, never pushes.
class MarketPriceModel {
  final String symbol;
  final String exchange;
  final String currencyCode;
  final double price;
  final String priceDate; // YYYY-MM-DD
  final String source; // yahoo | finnhub | manual
  final DateTime fetchedAt;
  final DateTime updatedAt;

  const MarketPriceModel({
    required this.symbol,
    required this.exchange,
    required this.currencyCode,
    required this.price,
    required this.priceDate,
    required this.source,
    required this.fetchedAt,
    required this.updatedAt,
  });

  /// Synthetic composite key used as SyncItem.id since the table has no UUID.
  String get syntheticId => '$symbol:$exchange';

  factory MarketPriceModel.fromProto(MarketPrice p) {
    return MarketPriceModel(
      symbol: p.symbol.toUpperCase(),
      exchange: p.exchange.toUpperCase(),
      currencyCode: p.currencyCode.toUpperCase(),
      price: p.price,
      priceDate: _dateOnly(p.priceDate),
      source: p.source.toLowerCase(),
      fetchedAt: p.fetchedAt.toDateTime().toUtc(),
      updatedAt: p.updatedAt.toDateTime().toUtc(),
    );
  }

  factory MarketPriceModel.fromMap(Map<String, dynamic> map) {
    return MarketPriceModel(
      symbol: (map['symbol'] as String).toUpperCase(),
      exchange: (map['exchange'] as String).toUpperCase(),
      currencyCode: (map['currency_code'] as String).toUpperCase(),
      price: _asDouble(map['price']!),
      priceDate: _dateOnly(map['price_date'] as String),
      source: (map['source'] as String).toLowerCase(),
      fetchedAt: DateTime.parse(map['fetched_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'symbol': symbol.toUpperCase(),
      'exchange': exchange.toUpperCase(),
      'currency_code': currencyCode.toUpperCase(),
      'price': price,
      'price_date': _dateOnly(priceDate),
      'source': source.toLowerCase(),
      'fetched_at': fetchedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  static String _dateOnly(String v) => v.length >= 10 ? v.substring(0, 10) : v;
  static double _asDouble(Object v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.parse(v.toString());
  }
}
