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

  // True once the Adjust ID has been pushed to RevenueCat + Scate. Guards the
  // resolver so the adid is applied exactly once across all callers.
  static bool _adjustIdApplied = false;
  static Future<void>? _forwardFuture;

  // Resolves once `Purchases.configure()` has returned (or failed). Paywall
  // screens await this before calling `getOfferings()` to avoid a race where
  // they open before SDK init has happened and get an empty offering.
  static final Completer<void> _revenueCatReady = Completer<void>();
  static Future<void> get revenueCatReady => _revenueCatReady.future;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Adjust SDK.
    try {
      final config = AdjustConfig(_adjustAppToken, AdjustEnvironment.production);
      config.attConsentWaitingInterval = 120;
      Adjust.initSdk(config);
    } catch (e) {
      log('Adjust init failed: $e', name: 'SdkInit');
    }

    // 2. Scate SDK — after Adjust, and BEFORE any Scate lifecycle event so the
    // events are actually received. Previously RevenuecatInitiated() fired
    // before ScateSDK.Init(), so Scate dropped it and `revenuecat_init` never
    // appeared in the dashboard.
    try {
      ScateSDK.Init(_scateAppId);
      try {
        ScateSDK.AdjustInitiated();
      } catch (_) {}
    } catch (e) {
      log('Scate init failed: $e', name: 'SdkInit');
    }

    // 3. ATT prompt (iOS only) — after Adjust init per Adjust docs. Scate is
    // already initialized (step 2), so these ATT lifecycle events land. Report
    // the prompt + the user's choice to Scate (per the Scate integration doc).
    try {
      if (Platform.isIOS) {
        final status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          try {
            ScateSDK.ATTPromptShown();
          } catch (_) {}
          final result =
              await AppTrackingTransparency.requestTrackingAuthorization();
          try {
            if (result == TrackingStatus.authorized) {
              ScateSDK.ATTPermissionGranted();
            } else if (result == TrackingStatus.denied ||
                result == TrackingStatus.restricted) {
              ScateSDK.ATTPermissionDenied();
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      log('ATT prompt failed: $e', name: 'SdkInit');
    }

    // 4. RevenueCat configure + send device identifiers.
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

    // 5. Resolve the Adjust ID and forward it to Scate + RevenueCat in the
    // background (non-blocking).
    unawaited(ensureAdjustIdForwarded());
  }

  /// Kicks off (once) the long-running Adjust-ID resolver and returns the shared
  /// in-flight future. Idempotent — repeat calls await the same work.
  static Future<void> ensureAdjustIdForwarded() {
    return _forwardFuture ??= _forwardAdjustIdAsync();
  }

  static Future<void> _forwardAdjustIdAsync() async {
    try {
      // Adjust does not assign an adid until it sends the first session, which
      // it delays until the user answers the ATT prompt OR
      // attConsentWaitingInterval (120s) elapses. Poll past that window so a
      // user who answers ATT slowly (most users) still gets their adid set. A
      // short 10s poll used to give up before the adid existed, leaving a blank
      // adid on RevenueCat so purchases could not be attributed in Adjust.
      final adid = await _resolveAdid(maxWait: const Duration(seconds: 140));
      if (adid == null) {
        log('adid-diag: background NEVER resolved an adid within 140s',
            name: 'SdkInit');
        return;
      }
      log('adid-diag: background resolved adid', name: 'SdkInit');
      await _applyAdid(adid);
    } catch (e) {
      log('Forward Adjust ID failed: $e', name: 'SdkInit');
    }
  }

  /// Best-effort, short guarantee that the Adjust ID is on the RevenueCat
  /// customer BEFORE a purchase, so the transaction is attributable in Adjust.
  /// No-op if already applied; bounded so it never noticeably delays checkout.
  static Future<void> flushAdjustIdBeforePurchase() async {
    if (_adjustIdApplied) {
      log('adid-diag: flush no-op, adid already applied before purchase',
          name: 'SdkInit');
      return;
    }
    try {
      final adid = await _resolveAdid(maxWait: const Duration(seconds: 3));
      if (adid == null) {
        // Instant-buyer edge: purchased before Adjust assigned an adid, so this
        // transaction may reach Adjust without attribution.
        log('adid-diag: flush FAILED, adid NOT ready at purchase (instant buyer)',
            name: 'SdkInit');
        return;
      }
      log('adid-diag: flush resolved adid at purchase, applying now',
          name: 'SdkInit');
      await _applyAdid(adid);
    } catch (e) {
      log('flushAdjustIdBeforePurchase failed: $e', name: 'SdkInit');
    }
  }

  /// Polls `Adjust.getAdid()` until it returns a non-empty value or [maxWait]
  /// elapses. Returns null if the adid never becomes available.
  static Future<String?> _resolveAdid({required Duration maxWait}) async {
    final deadline = DateTime.now().add(maxWait);
    var attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      String? adid;
      try {
        adid = await Adjust.getAdid();
      } catch (_) {
        adid = null;
      }
      if (adid != null && adid.isNotEmpty) return adid;
      // Poll quickly at first, then back off to avoid churn during the long
      // ATT wait.
      await Future<void>.delayed(
          Duration(milliseconds: attempt++ < 15 ? 700 : 3000));
    }
    return null;
  }

  /// Pushes the resolved adid to Scate + RevenueCat exactly once.
  static Future<void> _applyAdid(String adid) async {
    if (_adjustIdApplied) return;
    try {
      ScateSDK.SetAdid(adid);
    } catch (e) {
      log('ScateSDK.SetAdid failed: $e', name: 'SdkInit');
    }
    // Set the Adjust ID on RevenueCat via the SDK's reserved-attribute helper
    // (RevenueCat's recommended path). Must run after configure(), which
    // _revenueCatReady guarantees.
    await _setRevenueCatAdjustId(adid);
    try {
      ScateSDK.AdjustSetToRevenuecat();
    } catch (_) {}
    _adjustIdApplied = true;
  }

  static Future<void> _setRevenueCatAdjustId(String adid) async {
    try {
      await _revenueCatReady.future;
      await Purchases.setAdjustID(adid);
      // Log the appUserID too so alias fragmentation is visible: the purchasing
      // customer in RevenueCat must be this same id (or an alias of it).
      String uid = '';
      try {
        uid = await Purchases.appUserID;
      } catch (_) {}
      log('adid-diag: RC \$adjustId set (adid=$adid appUserID=$uid)',
          name: 'SdkInit');
    } catch (e) {
      log('setRevenueCatAdjustId failed: $e', name: 'SdkInit');
    }
  }
}
