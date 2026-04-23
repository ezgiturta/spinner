import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/home/home_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/collection/collection_wrapper.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/record_detail/record_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/explore/genre_explorer_screen.dart';
import 'theme.dart';

abstract class AppRoutes {
  static const home = '/home';
  static const scan = '/scan';
  static const explore = '/explore';
  static const collection = '/collection';
  static const record = '/record/:id';
  static const onboarding = '/onboarding';
  static const paywall = '/paywall';
  static const settings = '/settings';

  static String recordPath(String id) => '/record/$id';
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

  int _currentIndex(String location) {
    if (location.startsWith(AppRoutes.explore)) return 2;
    if (location.startsWith(AppRoutes.collection)) return 3;
    if (location.startsWith(AppRoutes.scan)) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(state.uri.path);

    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        type: BottomNavigationBarType.fixed,
        backgroundColor: SpinnerTheme.bg,
        selectedItemColor: SpinnerTheme.white,
        unselectedItemColor: SpinnerTheme.grey,
        selectedLabelStyle: SpinnerTheme.nunito(size: 11, weight: FontWeight.w600),
        unselectedLabelStyle: SpinnerTheme.nunito(size: 11),
        onTap: (i) => _onTabTap(context, i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner_outlined),
            activeIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.album_outlined),
            activeIcon: Icon(Icons.album),
            label: 'Collection',
          ),
        ],
      ),
    );
  }

  void _onTabTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.home);
      case 1:
        context.go(AppRoutes.scan);
      case 2:
        context.go(AppRoutes.explore);
      case 3:
        context.go(AppRoutes.collection);
    }
  }
}
