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

  Future<void> _startTrial() async {
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

  String get _trialEndDate {
    final end = DateTime.now().add(const Duration(days: 3));
    return DateFormat('MMMM d').format(end);
  }

  String _priceFor(_Plan plan) {
    final pkg = plan == _Plan.weekly ? _weeklyPkg : _yearlyPkg;
    if (pkg != null) return pkg.storeProduct.priceString;
    return plan == _Plan.weekly ? '\$5.99' : '\$39.99';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                32,
                24,
                MediaQuery.of(context).padding.bottom + 180,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'Try Spinner Free',
                    textAlign: TextAlign.center,
                    style: SpinnerTheme.nunito(
                      size: 28,
                      weight: FontWeight.w800,
                      color: SpinnerTheme.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'AI condition grading, mood picks, and\nalbum stories — with no pressure.',
                    textAlign: TextAlign.center,
                    style: SpinnerTheme.nunito(
                      size: 14,
                      weight: FontWeight.w400,
                      color: SpinnerTheme.grey,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'How your free trial works',
                    style: SpinnerTheme.nunito(
                      size: 18,
                      weight: FontWeight.w800,
                      color: SpinnerTheme.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _TimelineItem(
                    icon: Icons.lock_open_rounded,
                    isFirst: true,
                    title: 'Today: Get Instant Access',
                    subtitle: 'Start your full access of Spinner Pro',
                  ),
                  _TimelineItem(
                    icon: Icons.notifications_rounded,
                    title: 'Day 2: Trial Reminder',
                    subtitle:
                        'Get a reminder about when your trial will end',
                  ),
                  _TimelineItem(
                    icon: Icons.event_available_rounded,
                    isLast: true,
                    title: 'Day 3: Trial Ends',
                    subtitle:
                        'Your subscription will start on $_trialEndDate',
                  ),
                  const SizedBox(height: 24),
                  _PlanCard(
                    selected: _selected == _Plan.weekly,
                    price: _priceFor(_Plan.weekly),
                    period: '/week',
                    subtitle: null,
                    onTap: () => setState(() => _selected = _Plan.weekly),
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    selected: _selected == _Plan.yearly,
                    price: _priceFor(_Plan.yearly),
                    period: '/year',
                    subtitle: '3-day FREE TRIAL · Just \$0.11/day',
                    onTap: () => setState(() => _selected = _Plan.yearly),
                  ),
                ],
              ),
            ),
          ),
          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: GestureDetector(
              onTap: _loading ? null : _exit,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SpinnerTheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: SpinnerTheme.border),
                ),
                child: const Icon(
                  Icons.close,
                  color: SpinnerTheme.grey,
                  size: 18,
                ),
              ),
            ),
          ),
          // Bottom CTA
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomCta(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCta() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 16,
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
              color: SpinnerTheme.accent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _loading ? null : _startTrial,
                borderRadius: BorderRadius.circular(14),
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
                      : Text(
                          'Start my 3-day trial',
                          style: SpinnerTheme.nunito(
                            size: 17,
                            weight: FontWeight.w800,
                            color: SpinnerTheme.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FooterLink(
                label: 'Terms of use',
                onTap: () => _openUrl('https://spinner-legal.vercel.app/terms'),
              ),
              _FooterDivider(),
              _FooterLink(
                label: 'Privacy Policy',
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

class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isFirst;
  final bool isLast;

  const _TimelineItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SpinnerTheme.accent.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: SpinnerTheme.accent, size: 22),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: SpinnerTheme.accent.withOpacity(0.25),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SpinnerTheme.nunito(
                      size: 15,
                      weight: FontWeight.w700,
                      color: SpinnerTheme.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w400,
                      color: SpinnerTheme.grey,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool selected;
  final String price;
  final String period;
  final String? subtitle;
  final VoidCallback onTap;

  const _PlanCard({
    required this.selected,
    required this.price,
    required this.period,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: SpinnerTheme.nunito(
                        size: 18,
                        weight: FontWeight.w800,
                        color: SpinnerTheme.white,
                      ),
                      children: [
                        TextSpan(text: price),
                        TextSpan(
                          text: period,
                          style: SpinnerTheme.nunito(
                            size: 14,
                            weight: FontWeight.w600,
                            color: SpinnerTheme.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: SpinnerTheme.nunito(
                        size: 12,
                        weight: FontWeight.w600,
                        color: SpinnerTheme.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? SpinnerTheme.accent : SpinnerTheme.grey,
                  width: 2,
                ),
                color: selected ? SpinnerTheme.accent : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

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
