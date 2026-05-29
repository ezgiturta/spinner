import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/price_alert_service.dart';
import 'core/router.dart';
import 'core/sdk_init.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter();
  } catch (e) {
    debugPrint('Hive init failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();

  // Force show new onboarding with genres (remove after first run)
  if (!prefs.containsKey('genres')) {
    await prefs.remove('onboarding_complete');
  }

  runApp(SpinnerApp(prefs: prefs));

  // Heavy SDK init runs AFTER the first frame so the UI is already on screen
  // before any native SDK call. This both prevents a white-screen failure path
  // (Guideline 2.1(a)) and guarantees the ATT prompt — fired from inside
  // SdkInit — appears after the app is visible (Guideline 2.1 ATT), which is
  // what Apple reviewers expect to see on a fresh install.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    unawaited(SdkInit.init());
    // Wantlist price-drop check runs after first frame so it doesn't block
    // startup. Discogs auth gate is inside the service, so this no-ops for
    // signed-out users.
    unawaited(PriceAlertService.instance.checkOnce());
  });
}

class SpinnerApp extends StatelessWidget {
  final SharedPreferences prefs;

  const SpinnerApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Spinner',
      debugShowCheckedModeBanner: false,
      theme: SpinnerTheme.theme,
      routerConfig: buildRouter(prefs),
    );
  }
}
