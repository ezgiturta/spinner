import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Notification permission ask — shown AFTER the paywall (not during the
/// onboarding questions). Asking once the user has already committed converts
/// far better than priming it up front. Either action lands on /home.
class NotifPermissionScreen extends StatefulWidget {
  const NotifPermissionScreen({super.key});

  @override
  State<NotifPermissionScreen> createState() => _NotifPermissionScreenState();
}

class _NotifPermissionScreenState extends State<NotifPermissionScreen> {
  bool _busy = false;

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ios = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // Denial / unsupported platform must never block reaching the app.
    }
    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 48),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: SpinnerTheme.accent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_active_rounded,
                          color: SpinnerTheme.accent, size: 48),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Never miss a drop',
                      textAlign: TextAlign.center,
                      style: SpinnerTheme.nunito(
                        size: 26,
                        weight: FontWeight.w800,
                        color: SpinnerTheme.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Turn on alerts so you hear the moment a record drops in '
                      'price or your collection jumps in value.',
                      textAlign: TextAlign.center,
                      style: SpinnerTheme.nunito(
                        size: 15,
                        weight: FontWeight.w400,
                        color: SpinnerTheme.grey,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _notifPreview('💰', 'Price drop',
                        'Kind of Blue just dropped to \$32 on Discogs'),
                    _notifPreview('📈', 'Collection up',
                        'Your collection gained \$48 this week'),
                    _notifPreview('🔔', 'Wishlist hit',
                        'A near-mint copy of Rumours is now \$25'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _allow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SpinnerTheme.accent,
                        foregroundColor: SpinnerTheme.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: SpinnerTheme.white,
                              ),
                            )
                          : Text(
                              'Allow Notifications',
                              style: SpinnerTheme.nunito(
                                size: 17,
                                weight: FontWeight.w800,
                                color: SpinnerTheme.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _goHome,
                    child: Text(
                      'Maybe later',
                      style: SpinnerTheme.nunito(
                        size: 14,
                        weight: FontWeight.w600,
                        color: SpinnerTheme.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Faux iOS push banner used to prime the notification permission.
  Widget _notifPreview(String emoji, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: SpinnerTheme.accent,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: SpinnerTheme.nunito(
                          size: 13,
                          weight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    Text('now',
                        style: SpinnerTheme.nunito(
                            size: 11, color: Colors.black45)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: SpinnerTheme.nunito(size: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
