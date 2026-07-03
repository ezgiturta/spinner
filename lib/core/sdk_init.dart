import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:adjust_sdk/adjust.dart';
import 'package:adjust_sdk/adjust_config.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:scatesdk_flutter/scatesdk_flutter.dart';

/// Initializes attribution + monetization SDKs.
///
/// Per past App Store rejection: this MUST be called AFTER `runApp()` and every
/// step is wrapped in try-catch so an SDK failure never produces a white screen.
class SdkInit {
  SdkInit._();

  static const String _adjustAppToken = 'dttvdknibjls';
  static const String _scateAppId = 'sVJ8j';
  static const String _revenueCatApiKey = 'appl_EAbCIWVqwWunAfHEVNidgYgdAZo';

  static bool _initialized = false;

  // Resolves once `Purchases.configure()` has returned (or failed). Paywall
  // screens await this before calling `getOfferings()` to avoid a race where
  // they open before SDK init has happened and get an empty offering.
  static final Completer<void> _revenueCatReady = Completer<void>();
  static Future<void> get revenueCatReady => _revenueCatReady.future;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Adjust SDK
    try {
      final config = AdjustConfig(_adjustAppToken, AdjustEnvironment.production);
      config.attConsentWaitingInterval = 120;
      Adjust.initSdk(config);
    } catch (e) {
      log('Adjust init failed: $e', name: 'SdkInit');
    }

    // 2. ATT prompt (iOS only) — must run after Adjust init per Adjust docs.
    try {
      if (Platform.isIOS) {
        final status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      }
    } catch (e) {
      log('ATT prompt failed: $e', name: 'SdkInit');
    }

    // 3. RevenueCat configure + send device identifiers.
    try {
      await Purchases.configure(PurchasesConfiguration(_revenueCatApiKey));
      try {
        Purchases.collectDeviceIdentifiers();
      } catch (e) {
        log('collectDeviceIdentifiers failed: $e', name: 'SdkInit');
      }
      try {
        ScateSDK.RevenuecatInitiated();
      } catch (_) {}
    } catch (e) {
      log('RevenueCat configure failed: $e', name: 'SdkInit');
    } finally {
      if (!_revenueCatReady.isCompleted) _revenueCatReady.complete();
    }

    // 4. Scate SDK — must be initialized AFTER Adjust per Scate docs.
    try {
      ScateSDK.Init(_scateAppId);
      try {
        ScateSDK.AdjustInitiated();
      } catch (_) {}
    } catch (e) {
      log('Scate init failed: $e', name: 'SdkInit');
    }

    // 5. Resolve Adjust ID and forward to Scate (non-blocking).
    // NOTE: We deliberately do NOT call Purchases.setAdjustID() on
    // purchases_flutter v8 — every set* attribute method crashes with
    // EXC_BREAKPOINT inside CommonFunctionality (native Swift force-unwrap of
    // nil) and the crash is NOT catchable from Dart. Adjust→RevenueCat
    // attribution is wired server-side via the Adjust webhook configured in
    // the RevenueCat dashboard, so this client-side bridge is not required.
    unawaited(_forwardAdjustIdAsync());
  }

  static Future<void> _forwardAdjustIdAsync() async {
    try {
      String? adid;
      for (var i = 0; i < 10; i++) {
        try {
          adid = await Adjust.getAdid();
        } catch (_) {
          adid = null;
        }
        if (adid != null && adid.isNotEmpty) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      if (adid == null || adid.isEmpty) return;

      try {
        ScateSDK.SetAdid(adid);
      } catch (e) {
        log('ScateSDK.SetAdid failed: $e', name: 'SdkInit');
      }
      // Set the Adjust ID on RevenueCat as the reserved $adjustId attribute so
      // it rides along in the RevenueCat webhook payload (RevenueCat -> Scate ->
      // Adjust) and shows on the RevenueCat customer. We do this over the REST
      // API instead of Purchases.setAdjustID(), because the native set* methods
      // crash (uncatchable) on purchases_flutter v8. Pure HTTP: cannot crash.
      await _setRevenueCatAdjustId(adid);
      // AdjustSetToRevenuecat marks the lifecycle step Scate expects.
      try {
        ScateSDK.AdjustSetToRevenuecat();
      } catch (_) {}
    } catch (e) {
      log('Forward Adjust ID failed: $e', name: 'SdkInit');
    }
  }

  /// Set the RevenueCat reserved `$adjustId` subscriber attribute via the REST
  /// API. Crash-proof (plain HTTPS, no native SDK call). Uses the public SDK
  /// key, which is what the attributes endpoint accepts.
  static Future<void> _setRevenueCatAdjustId(String adid) async {
    try {
      // Ensure Purchases.configure() has finished before reading appUserID.
      await _revenueCatReady.future;
      final appUserId = await Purchases.appUserID;
      if (appUserId.isEmpty) return;
      final uri = Uri.parse(
          'https://api.revenuecat.com/v1/subscribers/${Uri.encodeComponent(appUserId)}/attributes');
      final client = HttpClient();
      try {
        final req = await client.postUrl(uri);
        req.headers.set('Authorization', 'Bearer $_revenueCatApiKey');
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('X-Platform', Platform.isIOS ? 'ios' : 'android');
        req.add(utf8.encode(jsonEncode({
          'attributes': {
            '\$adjustId': {'value': adid},
          }
        })));
        final resp = await req.close();
        await resp.drain<void>();
        log('RC \$adjustId set: HTTP ${resp.statusCode}', name: 'SdkInit');
      } finally {
        client.close();
      }
    } catch (e) {
      log('setRevenueCatAdjustId failed: $e', name: 'SdkInit');
    }
  }
}
