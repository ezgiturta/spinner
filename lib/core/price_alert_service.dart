import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'discogs_api.dart';

/// Watches the wantlist for price drops and fires a local notification when
/// the lowest Discogs price for an item falls under the user's [alert_price].
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

  /// Run a one-shot price check against the entire wantlist.
  /// Silently no-ops if Discogs is not authenticated.
  Future<void> checkOnce() async {
    final api = DiscogsApi();
    await api.init();
    if (!api.isAuthenticated) return;

    final items = await AppDatabase.getWantlist();
    if (items.isEmpty) return;

    await _ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final lastSeenRaw = prefs.getStringList(_lastSeenKey) ?? const <String>[];
    final lastSeen = <String, double>{
      for (final entry in lastSeenRaw)
        if (entry.contains(':'))
          entry.split(':').first: double.tryParse(entry.split(':').last) ?? 0,
    };

    for (final item in items) {
      final alertPrice = (item['alert_price'] as num?)?.toDouble();
      if (alertPrice == null || alertPrice <= 0) continue;
      final discogsId = (item['discogs_id'] as num?)?.toInt();
      if (discogsId == null) continue;

      try {
        final suggestions = await api.getPriceSuggestions(discogsId);
        if (suggestions == null || suggestions.isEmpty) continue;
        final lowest = _extractLowest(suggestions);
        if (lowest == null) continue;

        final key = '$discogsId';
        final prev = lastSeen[key];
        lastSeen[key] = lowest;

        if (lowest <= alertPrice && (prev == null || prev > alertPrice)) {
          final title = (item['title'] as String?) ?? 'A wantlist item';
          final artist = (item['artist'] as String?) ?? '';
          await _notify(
            id: discogsId,
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
      [for (final e in lastSeen.entries) '${e.key}:${e.value}'],
    );
  }

  double? _extractLowest(Map<String, dynamic> suggestions) {
    // Discogs returns a map keyed by condition; pick the lowest "value".
    double? best;
    for (final v in suggestions.values) {
      if (v is Map && v['value'] is num) {
        final n = (v['value'] as num).toDouble();
        if (best == null || n < best) best = n;
      }
    }
    return best;
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
