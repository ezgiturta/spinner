import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/ai/condition_grader_screen.dart';
import '../features/home/home_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/collection/collection_wrapper.dart';
import '../features/onboarding/onboarding_paywall_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/record_detail/record_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/explore/genre_explorer_screen.dart';
import 'subscription_gate.dart';
import 'theme.dart';

abstract class AppRoutes {
  static const home = '/home';
  static const scan = '/scan';
  static const explore = '/explore';
  static const collection = '/collection';
  static const record = '/record/:id';
  static const onboarding = '/onboarding';
  static const onboardingPaywall = '/onboarding-paywall';
  static const paywall = '/paywall';
  static const settings = '/settings';
  static const grade = '/grade/:id';

  static String recordPath(String id) => '/record/$id';
  static String gradePath(String id) => '/grade/$id';
}

abstract class _PrefKeys {
  static const onboardingComplete = 'onboarding_complete';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(SharedPreferences prefs) {
  final onboardingDone = prefs.getBool(_PrefKeys.onboardingComplete) ?? false;

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: onboardingDone ? AppRoutes.home : AppRoutes.onboarding,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingPaywall,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OnboardingPaywallScreen(),
      ),
      GoRoute(
        path: AppRoutes.paywall,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PaywallScreen(),
      ),
      GoRoute(
        path: AppRoutes.record,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return RecordDetailScreen(recordId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.grade,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final extra = state.extra as Map<String, dynamic>?;
          return ConditionGraderScreen(
            recordId: id,
            albumTitle: extra?['title'] as String?,
            artist: extra?['artist'] as String?,
          );
        },
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) =>
            _BottomNavShell(state: state, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.scan,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ScanScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.explore,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: GenreExplorerScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.collection,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CollectionWrapper(),
            ),
          ),
        ],
      ),
    ],
  );
}

class _BottomNavShell extends StatelessWidget {
  final GoRouterState state;
  final Widget child;

  const _BottomNavShell({required this.state, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = state.uri.path;
    final isHome = location.startsWith(AppRoutes.home);
    final isExplore = location.startsWith(AppRoutes.explore);
    final isCollection = location.startsWith(AppRoutes.collection);

    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: SpinnerTheme.bg,
          border: Border(top: BorderSide(color: SpinnerTheme.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _navItem(Icons.home_rounded, 'Home', isHome,
                    () => context.go(AppRoutes.home)),
                _navItem(Icons.explore_rounded, 'Explore', isExplore,
                    () => context.go(AppRoutes.explore)),
                _cameraButton(context),
                _navItem(Icons.album_rounded, 'Collection', isCollection,
                    () => context.go(AppRoutes.collection)),
                _navItem(Icons.settings_rounded, 'Settings', false,
                    () => context.push(AppRoutes.settings)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
      IconData icon, String label, bool active, VoidCallback onTap) {
    final color = active ? SpinnerTheme.white : SpinnerTheme.grey;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: SpinnerTheme.nunito(
                size: 11,
                weight: active ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Center, elevated camera button — Pro-gated like the Scan tab was.
  Widget _cameraButton(BuildContext context) {
    return Expanded(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -8),
          child: GestureDetector(
            onTap: () => _openScan(context),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF4F7BFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: SpinnerTheme.bg, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C5CE7).withOpacity(0.5),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: const Icon(Icons.photo_camera_rounded,
                  color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openScan(BuildContext context) async {
    if (await SubscriptionGate.requirePro(context)) {
      if (context.mounted) context.go(AppRoutes.scan);
    }
  }
}
