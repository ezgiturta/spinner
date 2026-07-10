import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:scatesdk_flutter/scatesdk_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/sdk_init.dart';
import '../../core/theme.dart';
import '../paywall/paywall_content.dart';

class OnboardingPaywallScreen extends StatefulWidget {
  const OnboardingPaywallScreen({super.key});

  @override
  State<OnboardingPaywallScreen> createState() =>
      _OnboardingPaywallScreenState();
}

class _OnboardingPaywallScreenState extends State<OnboardingPaywallScreen> {
  PaywallPlan _selected = PaywallPlan.yearly;
  bool _loading = false;
  String? _error;

  Package? _weeklyPkg;
  Package? _yearlyPkg;

  @override
  void initState() {
    super.initState();
    try {
      ScateSDK.OnboardingPaywallShown();
    } catch (_) {}
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final t0 = DateTime.now();
    log('ONB-PAYWALL waiting for SdkInit.revenueCatReady',
        name: 'OnboardingPaywall');
    await SdkInit.revenueCatReady;
    log('ONB-PAYWALL revenueCatReady resolved in '
        '${DateTime.now().difference(t0).inMilliseconds}ms',
        name: 'OnboardingPaywall');

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final offerings = await Purchases.getOfferings();
        final current = offerings.current;
        final allKeys = offerings.all.keys.toList();
        log(
          'ONB-PAYWALL attempt ${attempt + 1}: '
          'current=${current?.identifier} '
          'all=$allKeys '
          'packages=${current?.availablePackages.map((p) => '${p.identifier}(${p.packageType}/${p.storeProduct.identifier})').toList()}',
          name: 'OnboardingPaywall',
        );
        if (current != null) {
          Package? weekly;
          Package? yearly;
          for (final pkg in current.availablePackages) {
            switch (pkg.packageType) {
              case PackageType.weekly:
                weekly = pkg;
              case PackageType.annual:
                yearly = pkg;
              default:
                break;
            }
          }
          if (weekly != null || yearly != null) {
            log(
              'ONB-PAYWALL packages resolved: '
              'weekly=${weekly?.storeProduct.identifier} '
              'yearly=${yearly?.storeProduct.identifier}',
              name: 'OnboardingPaywall',
            );
            if (!mounted) return;
            setState(() {
              _weeklyPkg = weekly;
              _yearlyPkg = yearly;
              if (_yearlyPkg == null && _weeklyPkg != null) {
                _selected = PaywallPlan.weekly;
              }
            });
            return;
          }
        }
      } catch (e, st) {
        log('ONB-PAYWALL attempt ${attempt + 1} threw: $e',
            name: 'OnboardingPaywall', error: e, stackTrace: st);
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    log('ONB-PAYWALL FAILED after 4 attempts — packages stayed null',
        name: 'OnboardingPaywall');
  }

  Future<void> _exit() async {
    try {
      ScateSDK.OnboardingPaywallClosed();
    } catch (_) {}
    try {
      ScateSDK.OnboardingFinish();
    } catch (_) {}
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _subscribe() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // On a fast first tap the offerings may still be loading; wait for them
    // rather than showing "Plan not available" until a second tap.
    if (_weeklyPkg == null && _yearlyPkg == null) {
      await _loadOfferings();
    }
    final pkg = _selected == PaywallPlan.weekly ? _weeklyPkg : _yearlyPkg;
    if (pkg == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Plan not available. Please try again later.';
      });
      return;
    }
    try {
      // Make sure the Adjust ID is on the RevenueCat customer before the
      // transaction, so this purchase can be attributed in Adjust. No-op if it
      // was already set by the background resolver.
      await SdkInit.flushAdjustIdBeforePurchase();
      try {
        ScateSDK.PaywallAttempted('onboarding');
      } catch (_) {}
      // Opens the native StoreKit purchase sheet.
      final info = await Purchases.purchasePackage(pkg);
      if (!mounted) return;
      // Only finish if the entitlement is actually active. A deferred purchase
      // (Ask-to-Buy / SCA / family approval) returns with no active
      // entitlement, so don't drop a non-Pro user into the app.
      if (info.entitlements.active.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Your purchase is pending approval. You can continue once it is approved.';
        });
        return;
      }
      try {
        ScateSDK.PaywallPurchased('onboarding');
      } catch (_) {}
      await _exit();
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        try {
          ScateSDK.PaywallCancelled('onboarding');
        } catch (_) {}
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = 'Purchase failed. Please try again.';
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await Purchases.restorePurchases();
      if (info.entitlements.active.isNotEmpty) {
        if (!mounted) return;
        await _exit();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = 'No active subscription found to restore.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Restore failed. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: PaywallContent(
        weeklyPkg: _weeklyPkg,
        yearlyPkg: _yearlyPkg,
        selected: _selected,
        onSelect: (p) => setState(() => _selected = p),
        loading: _loading,
        error: _error,
        onSubscribe: _subscribe,
        onRestore: _restore,
        onClose: _exit,
        onOpenUrl: _openUrl,
      ),
    );
  }
}
