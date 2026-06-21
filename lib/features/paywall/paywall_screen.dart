import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/sdk_init.dart';
import '../../core/theme.dart';
import 'paywall_content.dart';

/// In-app paywall, shown when a non-subscriber taps a Pro feature (scan, mood,
/// Discogs, price alerts), via Settings → Upgrade, or the home Pro badge.
/// Shares the Cardly-style UI with the onboarding paywall. Pops `true` on a
/// successful purchase/restore so the caller can refresh entitlement state.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _loading = false;
  String? _error;
  PaywallPlan _selected = PaywallPlan.yearly;
  Package? _weeklyPkg;
  Package? _yearlyPkg;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final t0 = DateTime.now();
    log('PAYWALL waiting for SdkInit.revenueCatReady', name: 'Paywall');
    await SdkInit.revenueCatReady;
    log('PAYWALL revenueCatReady resolved in '
        '${DateTime.now().difference(t0).inMilliseconds}ms',
        name: 'Paywall');

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final offerings = await Purchases.getOfferings();
        final current = offerings.current;
        final allKeys = offerings.all.keys.toList();
        log(
          'PAYWALL attempt ${attempt + 1}: '
          'current=${current?.identifier} '
          'all=$allKeys '
          'packages=${current?.availablePackages.map((p) => '${p.identifier}(${p.packageType}/${p.storeProduct.identifier})').toList()}',
          name: 'Paywall',
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
              'PAYWALL packages resolved: '
              'weekly=${weekly?.storeProduct.identifier} '
              'yearly=${yearly?.storeProduct.identifier}',
              name: 'Paywall',
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
        log('PAYWALL attempt ${attempt + 1} threw: $e',
            name: 'Paywall', error: e, stackTrace: st);
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    log('PAYWALL FAILED after 4 attempts — packages stayed null',
        name: 'Paywall');
  }

  Future<void> _subscribe() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // On a fast first tap the offerings may still be loading, which used to show
    // "Plan not available" until a second tap. Make sure they're in first.
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
      // Opens the native StoreKit purchase sheet.
      final info = await Purchases.purchasePackage(pkg);
      if (!mounted) return;
      // A deferred purchase returns with no active entitlement; don't treat it
      // as success or the user lands in the app still non-Pro.
      if (info.entitlements.active.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Your purchase is pending approval.';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
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
        Navigator.of(context).pop(true);
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
        onClose: () => Navigator.of(context).pop(),
        onOpenUrl: _openUrl,
      ),
    );
  }
}
