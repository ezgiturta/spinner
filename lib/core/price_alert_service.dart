import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'market_value_service.dart';

/// Watches the wantlist for price drops and fires a local notification when the
/// lowest live marketplace price (eBay + Reverb, and Discogs when connected)
/// for an item falls under the user's [alert_price].
///
/// iOS background fetch is unreliable, so we run the check on every cold start
/// and whenever the user opens the wantlist screen. Last-seen prices are
/// cached in SharedPreferences so we only notify on a meaningful drop.
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

  /// Run a one-shot price check against the entire wantlist using live
  /// marketplace prices. No account/auth required.
  Future<void> checkOnce() async {
    final items = await AppDatabase.getWantlist();
    if (items.isEmpty) return;

    await _ensureReady();
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

  Future<void> _notify({
    required int id,
    required String title,
    required String body,
  }) async {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Notified when a wantlist record drops in price',
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
