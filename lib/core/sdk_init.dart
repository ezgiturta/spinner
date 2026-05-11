import 'dart:async';
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

    // 5. Resolve Adjust ID and forward to RevenueCat + Scate (non-blocking).
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
        Purchases.setAdjustID(adid);
      } catch (e) {
        log('Purchases.setAdjustID failed: $e', name: 'SdkInit');
      }
      try {
        ScateSDK.SetAdid(adid);
      } catch (e) {
        log('ScateSDK.SetAdid failed: $e', name: 'SdkInit');
      }
      try {
        ScateSDK.AdjustSetToRevenuecat();
      } catch (_) {}
    } catch (e) {
      log('Forward Adjust ID failed: $e', name: 'SdkInit');
    }
  }
}
