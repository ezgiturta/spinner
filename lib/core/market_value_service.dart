import 'dart:async';

import 'database.dart';
import 'discogs_api.dart';
import 'ebay_api.dart';
import 'reverb_api.dart';

/// A record's market value, derived from live marketplace listings.
class MarketValue {
  final double low;
  final double median;
  final double high;
  final int sampleCount;

  const MarketValue({
    required this.low,
    required this.median,
    required this.high,
    required this.sampleCount,
  });
}

/// Pulls real prices for a record from eBay + Reverb (and Discogs price
/// suggestions when the user has connected their Discogs account), then derives
/// low / median / high. This is what backs the "Live Discogs, eBay & Reverb
/// values" claim, the record detail value card, the collection's total worth,
/// and wishlist price-drop alerts.
class MarketValueService {
  MarketValueService._();
  static final MarketValueService instance = MarketValueService._();

  final EbayApi _ebay = EbayApi();
  final ReverbApi _reverb = ReverbApi();

  /// How long a stored value stays fresh before we re-fetch.
  static const Duration freshness = Duration(hours: 24);

  /// Collect every available price for [artist] + [title]. Returns an empty
  /// list (never throws) if nothing is found or no marketplace is configured.
  Future<List<double>> _collectPrices({
    required String artist,
    required String title,
    int? discogsId,
  }) async {
    final query =
        [artist, title].where((s) => s.trim().isNotEmpty).join(' ').trim();
    if (query.isEmpty) return const [];

    final prices = <double>[];

    // eBay + Reverb in parallel — both already swallow their own errors and
    // return [] when their keys are unset.
    final ebayFut = _ebay.searchVinyl(query, limit: 12);
    final reverbFut = _reverb.searchVinyl(query, limit: 12);
    final ebay = await ebayFut;
    final reverb = await reverbFut;

    for (final l in ebay) {
      final p = l.price;
      if (p != null && p > 0) prices.add(p);
    }
    for (final l in reverb) {
      final p = l.price;
      if (p != null && p > 0) prices.add(p);
    }

    // Optional: Discogs price suggestions, only if the user connected Discogs
    // and we know the release id.
    if (discogsId != null) {
      try {
        final discogs = DiscogsApi();
        await discogs.init();
        if (discogs.isAuthenticated) {
          final suggestions = await discogs.getPriceSuggestions(discogsId);
          if (suggestions != null) {
            for (final v in suggestions.values) {
              if (v is Map && v['value'] is num) {
                final n = (v['value'] as num).toDouble();
                if (n > 0) prices.add(n);
              }
            }
          }
        }
      } catch (_) {
        // Ignore Discogs failures; eBay/Reverb still stand.
      }
    }

    return prices;
  }

  /// Fetch the market value for a record. Returns null if no prices are found.
  Future<MarketValue?> fetch({
    required String artist,
    required String title,
    int? discogsId,
  }) async {
    final prices =
        await _collectPrices(artist: artist, title: title, discogsId: discogsId);
    if (prices.isEmpty) return null;
    prices.sort();
    return MarketValue(
      low: prices.first,
      median: _median(prices),
      high: prices.last,
      sampleCount: prices.length,
    );
  }

  /// Fetch the value and persist it onto the record row. Returns the value (or
  /// null if nothing was found — in which case the row is left untouched).
  Future<MarketValue?> fetchAndStore(Map<String, dynamic> record) async {
    final id = record['id'] as String?;
    if (id == null) return null;
    final mv = await fetch(
      artist: record['artist'] as String? ?? '',
      title: record['title'] as String? ?? '',
      discogsId: (record['discogs_id'] as num?)?.toInt(),
    );
    if (mv == null) return null;
    await AppDatabase.updateRecord(id, {
      'low_value': mv.low,
      'median_value': mv.median,
      'high_value': mv.high,
      'value_updated_at': DateTime.now().toIso8601String(),
    });
    return mv;
  }

  /// The single lowest available price for a query — used by price alerts.
  Future<double?> lowestPrice({
    required String artist,
    required String title,
    int? discogsId,
  }) async {
    final prices =
        await _collectPrices(artist: artist, title: title, discogsId: discogsId);
    if (prices.isEmpty) return null;
    prices.sort();
    return prices.first;
  }

  /// True when a stored value is missing or older than [freshness].
  static bool isStale(Map<String, dynamic> record) {
    if (record['median_value'] == null) return true;
    final updatedAt = record['value_updated_at'] as String?;
    if (updatedAt == null) return true;
    final ts = DateTime.tryParse(updatedAt);
    if (ts == null) return true;
    return DateTime.now().difference(ts) > freshness;
  }

  double _median(List<double> sorted) {
    final n = sorted.length;
    if (n == 0) return 0;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }
}
