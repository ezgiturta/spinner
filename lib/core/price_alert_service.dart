import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'market_value_service.dart';

/// Watches two things and fires local notifications:
///  - the WANTLIST for price drops below the user's [alert_price], and
///  - the COLLECTION for meaningful value changes (a record you own going up or
///    down by >=15%), so every scanned record is auto-watched with no setup.
///
/// Prices are live (eBay + Reverb, and Discogs when known). iOS background
/// fetch is unreliable, so we run on every cold start and when the wantlist
/// opens. Wantlist last-seen prices are cached in prefs; collection changes
/// compare against the median_value already stored on the record.
class PriceAlertService {
  PriceAlertService._();
  static final PriceAlertService instance = PriceAlertService._();

  static const String _channelId = 'price_alerts';
  static const String _channelName = 'Price drop alerts';
  static const String _lastSeenKey = 'price_alerts_last_seen_v1';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _ready = true;
  }

  /// One-shot check of both the wantlist (price drops) and the collection
  /// (value changes). No account/auth required.
  Future<void> checkOnce() async {
    await _ensureReady();
    await _checkWantlistDrops();
    await _checkCollectionChanges();
  }

  // ── Wantlist: notify when the lowest price drops below the target ──
  Future<void> _checkWantlistDrops() async {
    final items = await AppDatabase.getWantlist();
    if (items.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastSeenRaw = prefs.getStringList(_lastSeenKey) ?? const <String>[];
    final lastSeen = <String, double>{
      for (final entry in lastSeenRaw)
        if (entry.contains('='))
          entry.split('=').first:
              double.tryParse(entry.split('=').last) ?? 0,
    };

    for (final item in items) {
      final alertPrice = (item['alert_price'] as num?)?.toDouble();
      if (alertPrice == null || alertPrice <= 0) continue;
      final title = (item['title'] as String?) ?? '';
      if (title.isEmpty) continue;
      final artist = (item['artist'] as String?) ?? '';
      final key = (item['id'] as String?) ?? '$artist-$title';

      try {
        final lowest = await MarketValueService.instance.lowestPrice(
          artist: artist,
          title: title,
          discogsId: (item['discogs_id'] as num?)?.toInt(),
        );
        if (lowest == null) continue;

        final prev = lastSeen[key];
        lastSeen[key] = lowest;

        if (lowest <= alertPrice && (prev == null || prev > alertPrice)) {
          await _notify(
            id: key.hashCode & 0x7fffffff,
            title: 'Price drop: $title',
            body: artist.isNotEmpty
                ? '$artist · now \$${lowest.toStringAsFixed(2)} (target \$${alertPrice.toStringAsFixed(2)})'
                : 'Now \$${lowest.toStringAsFixed(2)} (target \$${alertPrice.toStringAsFixed(2)})',
          );
        }
      } catch (_) {
        // Skip this item, continue with the rest.
      }
    }

    await prefs.setStringList(
      _lastSeenKey,
      [for (final e in lastSeen.entries) '${e.key}=${e.value}'],
    );
  }

  // ── Collection: notify when an owned record's value moves >=15% ──
  // Every scanned record is auto-watched (no setup needed). We only refresh
  // values that are missing or stale (>24h) to keep API calls down, and
  // compare against the median already stored on the record.
  Future<void> _checkCollectionChanges() async {
    final items = await AppDatabase.getCollection();
    if (items.isEmpty) return;

    for (final item in items) {
      final id = item['id'] as String?;
      if (id == null) continue;
      if (!MarketValueService.isStale(item)) continue;
      final title = (item['title'] as String?) ?? '';
      if (title.isEmpty) continue;
      final artist = (item['artist'] as String?) ?? '';
      final oldMedian = (item['median_value'] as num?)?.toDouble();

      try {
        final mv = await MarketValueService.instance.fetch(
          artist: artist,
          title: title,
          discogsId: (item['discogs_id'] as num?)?.toInt(),
        );
        if (mv == null) continue;

        await AppDatabase.updateRecord(id, {
          'median_value': mv.median,
          'low_value': mv.low,
          'high_value': mv.high,
          'value_updated_at': DateTime.now().toIso8601String(),
        });

        if (oldMedian != null && oldMedian > 0) {
          final change = (mv.median - oldMedian) / oldMedian;
          if (change.abs() >= 0.15) {
            final up = mv.median > oldMedian;
            await _notify(
              id: id.hashCode & 0x7fffffff,
              title: up ? '$title is up in value' : '$title dropped in value',
              body: artist.isNotEmpty
                  ? '$artist · now \$${mv.median.toStringAsFixed(2)} (was \$${oldMedian.toStringAsFixed(2)})'
                  : 'Now \$${mv.median.toStringAsFixed(2)} (was \$${oldMedian.toStringAsFixed(2)})',
            );
          }
        }
      } catch (_) {
        // Skip this item, continue with the rest.
      }
    }
  }

  Future<void> _notify({
    required int id,
    required String title,
    required String body,
  }) async {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription:
          'Wantlist price drops and collection value changes',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
    );
  }
}
