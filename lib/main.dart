import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router.dart';
import 'core/sdk_init.dart';
import 'core/theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

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

  // Heavy SDK init runs AFTER runApp so any SDK failure can't produce a white
  // screen (App Store would reject under Guideline 2.1(a)).
  // SdkInit.init() is fully wrapped in try-catch internally.
  unawaited(SdkInit.init());
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
