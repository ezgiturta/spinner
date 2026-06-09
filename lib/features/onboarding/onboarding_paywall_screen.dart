import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:scatesdk_flutter/scatesdk_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/sdk_init.dart';
import '../../core/theme.dart';

class OnboardingPaywallScreen extends StatefulWidget {
  const OnboardingPaywallScreen({super.key});

  @override
  State<OnboardingPaywallScreen> createState() =>
      _OnboardingPaywallScreenState();
}

enum _Plan { weekly, yearly }

class _OnboardingPaywallScreenState extends State<OnboardingPaywallScreen> {
  _Plan _selected = _Plan.yearly;
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
                _selected = _Plan.weekly;
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
    final pkg = _selected == _Plan.weekly ? _weeklyPkg : _yearlyPkg;
    if (pkg == null) {
      setState(() => _error = 'Plan not available. Please try again later.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Opens the native StoreKit purchase sheet.
      await Purchases.purchasePackage(pkg);
      if (!mounted) return;
      await _exit();
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

  // ── Pricing helpers ─────────────────────────────────────────────────

  double get _weeklyPrice => _weeklyPkg?.storeProduct.price ?? 5.99;
  double get _yearlyPrice => _yearlyPkg?.storeProduct.price ?? 39.99;

  String _priceString(_Plan plan) {
    final pkg = plan == _Plan.weekly ? _weeklyPkg : _yearlyPkg;
    if (pkg != null) return pkg.storeProduct.priceString;
    return plan == _Plan.weekly ? '\$5.99' : '\$39.99';
  }

  String get _yearlyPerWeek {
    final code = _yearlyPkg?.storeProduct.currencyCode ?? 'USD';
    final perWeek = _yearlyPrice / 52.0;
    try {
      return NumberFormat.simpleCurrency(name: code).format(perWeek);
    } catch (_) {
      return '\$${perWeek.toStringAsFixed(2)}';
    }
  }

  int get _savePct {
    if (_weeklyPrice <= 0) return 0;
    final pct = (1 - (_yearlyPrice / 52.0) / _weeklyPrice) * 100;
    return pct.clamp(0, 99).round();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomInset + 210),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildHero(),
                const SizedBox(height: 18),
                Text(
                  'Join Spinner Pro',
                  textAlign: TextAlign.center,
                  style: SpinnerTheme.nunito(
                    size: 30,
                    weight: FontWeight.w800,
                    color: SpinnerTheme.white,
                  ),
                ),
                const SizedBox(height: 22),
                _buildFeatures(),
                const SizedBox(height: 26),
                _buildSocialProof(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Column(
                    children: [
                      _PlanCard(
                        title: 'Annual',
                        price: _priceString(_Plan.yearly),
                        period: '/ year',
                        trailing: '$_yearlyPerWeek / week',
                        badge: _savePct > 0 ? 'SAVE $_savePct%' : null,
                        selected: _selected == _Plan.yearly,
                        onTap: () =>
                            setState(() => _selected = _Plan.yearly),
                      ),
                      const SizedBox(height: 12),
                      _PlanCard(
                        title: 'Weekly',
                        price: _priceString(_Plan.weekly),
                        period: '/ week',
                        trailing: null,
                        badge: null,
                        selected: _selected == _Plan.weekly,
                        onTap: () =>
                            setState(() => _selected = _Plan.weekly),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Close button (top-left, like the reference)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: GestureDetector(
              onTap: _loading ? null : _exit,
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: SpinnerTheme.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.black, size: 20),
              ),
            ),
          ),

          // Pinned bottom CTA
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomCta()),
        ],
      ),
    );
  }

  // ── Hero: synthwave sunset + vinyl ──────────────────────────────────

  Widget _buildHero() {
    return SizedBox(
      height: 290,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Sky gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF120A24),
                  Color(0xFF3A1C5E),
                  Color(0xFF7A3D8F),
                  Color(0xFFE8615F),
                  Color(0xFFF2A65A),
                ],
                stops: [0.0, 0.32, 0.55, 0.78, 1.0],
              ),
            ),
          ),
          // Sun
          Positioned(
            top: 44,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 150,
                height: 150,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFC56B), Color(0xFFFF6B9D)],
                  ),
                ),
              ),
            ),
          ),
          // Floating album squares (the "flying cards" motif)
          Positioned(
            top: 96,
            left: 26,
            child: Transform.rotate(
              angle: -0.32,
              child: _floatingSquare(58),
            ),
          ),
          Positioned(
            top: 110,
            right: 26,
            child: Transform.rotate(
              angle: 0.32,
              child: _floatingSquare(58),
            ),
          ),
          // Vinyl disc, center
          const Center(child: _VinylDisc(size: 132)),
          // Fade into the dark feature list
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, SpinnerTheme.bg],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingSquare(double size) {
    return Container(
      width: size,
      height: size * 1.18,
      decoration: BoxDecoration(
        color: SpinnerTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SpinnerTheme.accent.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: SpinnerTheme.accent.withOpacity(0.35),
            blurRadius: 16,
          ),
        ],
      ),
      child: const Icon(Icons.album, color: SpinnerTheme.grey, size: 22),
    );
  }

  // ── Feature list ────────────────────────────────────────────────────

  Widget _buildFeatures() {
    const feats = <List<String>>[
      ['🎯', 'Scan any record — unlimited'],
      ['💎', 'Live Discogs, eBay & Reverb values'],
      ['⚡', 'AI condition grading from a photo'],
      ['🔥', 'Album stories & mood picks'],
      ['✨', 'Wishlist price-drop alerts'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          for (final f in feats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(f[0], style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      f[1],
                      style: SpinnerTheme.nunito(
                        size: 16,
                        weight: FontWeight.w700,
                        color: SpinnerTheme.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Social proof pill (points to the annual card) ───────────────────

  Widget _buildSocialProof() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: SpinnerTheme.green,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Join thousands ',
                  style: SpinnerTheme.nunito(
                    size: 13,
                    weight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                TextSpan(
                  text: 'of vinyl collectors',
                  style: SpinnerTheme.nunito(
                    size: 13,
                    weight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -3),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(width: 12, height: 12, color: SpinnerTheme.green),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  // ── Bottom CTA ──────────────────────────────────────────────────────

  Widget _buildBottomCta() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: SpinnerTheme.bg,
        border: Border(top: BorderSide(color: SpinnerTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 13,
                weight: FontWeight.w500,
                color: SpinnerTheme.red,
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: Material(
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFF4A7BFF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: InkWell(
                  onTap: _loading ? null : _subscribe,
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: SpinnerTheme.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: SpinnerTheme.nunito(
                                  size: 17,
                                  weight: FontWeight.w800,
                                  color: SpinnerTheme.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward,
                                  color: SpinnerTheme.white, size: 20),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Subscription can be canceled at any time',
            style: SpinnerTheme.nunito(
              size: 11,
              weight: FontWeight.w400,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FooterLink(
                label: 'Terms',
                onTap: () => _openUrl('https://spinner-legal.vercel.app/terms'),
              ),
              _FooterDivider(),
              _FooterLink(
                label: 'Privacy',
                onTap: () =>
                    _openUrl('https://spinner-legal.vercel.app/privacy'),
              ),
              _FooterDivider(),
              _FooterLink(
                label: 'Restore',
                onTap: _loading ? null : _restore,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Vinyl disc ────────────────────────────────────────────────────────

class _VinylDisc extends StatelessWidget {
  final double size;
  const _VinylDisc({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0B0B0B),
        border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.62,
          height: size * 0.62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          ),
          child: Center(
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFFE8615F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Container(
                  width: size * 0.07,
                  height: size * 0.07,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: SpinnerTheme.bg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String? trailing;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.period,
    required this.trailing,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: selected
                  ? SpinnerTheme.accent.withOpacity(0.12)
                  : SpinnerTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? SpinnerTheme.accent : SpinnerTheme.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Radio
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? SpinnerTheme.accent : Colors.transparent,
                    border: Border.all(
                      color: selected ? SpinnerTheme.accent : SpinnerTheme.grey,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 14),
                // Title + price
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: SpinnerTheme.nunito(
                          size: 15,
                          weight: FontWeight.w600,
                          color: SpinnerTheme.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: price,
                              style: SpinnerTheme.nunito(
                                size: 19,
                                weight: FontWeight.w800,
                                color: SpinnerTheme.white,
                              ),
                            ),
                            TextSpan(
                              text: ' $period',
                              style: SpinnerTheme.nunito(
                                size: 13,
                                weight: FontWeight.w600,
                                color: SpinnerTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: SpinnerTheme.nunito(
                      size: 14,
                      weight: FontWeight.w700,
                      color: SpinnerTheme.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -9,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: SpinnerTheme.green,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge!,
                style: SpinnerTheme.nunito(
                  size: 11,
                  weight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Footer links ──────────────────────────────────────────────────────

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: SpinnerTheme.nunito(
          size: 12,
          weight: FontWeight.w500,
          color: SpinnerTheme.grey,
        ),
      ),
    );
  }
}

class _FooterDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        '|',
        style: SpinnerTheme.nunito(
          size: 12,
          weight: FontWeight.w400,
          color: SpinnerTheme.grey,
        ),
      ),
    );
  }
}
