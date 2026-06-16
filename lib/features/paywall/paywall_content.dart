import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/theme.dart';

/// The Cardly-style paywall UI, shared by the onboarding paywall and the
/// in-app paywall so both screens look identical. This widget is purely
/// presentational — the hosting screen owns offerings loading, the purchase
/// call, and what "close" / "purchased" do (go home vs pop).
enum PaywallPlan { weekly, yearly }

class PaywallContent extends StatelessWidget {
  final Package? weeklyPkg;
  final Package? yearlyPkg;
  final PaywallPlan selected;
  final ValueChanged<PaywallPlan> onSelect;
  final bool loading;
  final String? error;
  final VoidCallback onSubscribe;
  final VoidCallback onRestore;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenUrl;

  const PaywallContent({
    super.key,
    required this.weeklyPkg,
    required this.yearlyPkg,
    required this.selected,
    required this.onSelect,
    required this.loading,
    required this.error,
    required this.onSubscribe,
    required this.onRestore,
    required this.onClose,
    required this.onOpenUrl,
  });

  static const _termsUrl = 'https://spinner-legal.vercel.app/terms';
  static const _privacyUrl = 'https://spinner-legal.vercel.app/privacy';

  // ── Pricing ──
  double get _weeklyPrice => weeklyPkg?.storeProduct.price ?? 5.99;
  double get _yearlyPrice => yearlyPkg?.storeProduct.price ?? 39.99;

  String _priceString(PaywallPlan plan) {
    final pkg = plan == PaywallPlan.weekly ? weeklyPkg : yearlyPkg;
    if (pkg != null) return pkg.storeProduct.priceString;
    return plan == PaywallPlan.weekly ? '\$5.99' : '\$39.99';
  }

  String get _yearlyPerWeek {
    final code = yearlyPkg?.storeProduct.currencyCode ?? 'USD';
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
    // No scroll — everything fits on one screen. The middle section flexes to
    // fill whatever space is left between the hero and the pinned CTA.
    return Stack(
      children: [
        Column(
          children: [
            // HERO takes the flexible space (shrinks on small phones); the
            // title, features, social proof and plan cards below are FIXED and
            // compact. This guarantees one page — no scroll, no overflow/overlap
            // (the proven Draft layout).
            Expanded(child: _buildHero(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Join Spinner Pro',
                    textAlign: TextAlign.center,
                    style: SpinnerTheme.nunito(
                      size: 26,
                      weight: FontWeight.w800,
                      color: SpinnerTheme.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildFeatures(),
                  const SizedBox(height: 10),
                  _buildSocialProof(),
                  const SizedBox(height: 6),
                  _PlanCard(
                    title: 'Annual',
                    price: _priceString(PaywallPlan.yearly),
                    period: '/ year',
                    trailing: '$_yearlyPerWeek / week',
                    badge: _savePct > 0 ? 'SAVE $_savePct%' : null,
                    selected: selected == PaywallPlan.yearly,
                    onTap: () => onSelect(PaywallPlan.yearly),
                  ),
                  const SizedBox(height: 8),
                  _PlanCard(
                    title: 'Weekly',
                    price: _priceString(PaywallPlan.weekly),
                    period: '/ week',
                    trailing: null,
                    badge: null,
                    selected: selected == PaywallPlan.weekly,
                    onTap: () => onSelect(PaywallPlan.weekly),
                  ),
                ],
              ),
            ),
            _buildBottomCta(context),
          ],
        ),

        // Close button (top-left)
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          child: GestureDetector(
            onTap: loading ? null : onClose,
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
      ],
    );
  }

  // ── Hero: synthwave sunset + vinyl ──
  // No fixed height — it lives inside an Expanded and takes whatever vertical
  // space is left after the fixed content below, shrinking on small phones.
  Widget _buildHero(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
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
          Positioned(
            top: 96,
            left: 26,
            child: Transform.rotate(angle: -0.32, child: _floatingSquare(58)),
          ),
          Positioned(
            top: 110,
            right: 26,
            child: Transform.rotate(angle: 0.32, child: _floatingSquare(58)),
          ),
          const Center(child: _VinylDisc(size: 168)),
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
          BoxShadow(color: SpinnerTheme.accent.withOpacity(0.35), blurRadius: 16),
        ],
      ),
      child: const Icon(Icons.album, color: SpinnerTheme.grey, size: 22),
    );
  }

  // ── Features ──
  // Draft's exact compact bullet style: emoji in a fixed 28px column (so the
  // text left-edges align), 8px gap, 15px text, only 6px bottom padding. This
  // is what lets five rows + social proof + two plan cards fit one page with
  // no scroll and no overlap (Spinner's old rows were ~70% taller and
  // collided with the social-proof bubble).
  Widget _buildFeatures() {
    const feats = <List<String>>[
      ['💿', 'Unlimited vinyl scans'],
      ['💎', 'Live Discogs, eBay & Reverb values'],
      ['⚡', 'AI condition grading from a photo'],
      ['🔥', 'Album stories & mood picks'],
      ['✨', 'Price drop alerts on your collection'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final f in feats)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(f[0], style: const TextStyle(fontSize: 17)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f[1],
                    style: SpinnerTheme.nunito(
                      size: 15,
                      weight: FontWeight.w700,
                      color: SpinnerTheme.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Social proof ──
  // Matches Draft: a fully-rounded green pill with a clean downward triangle
  // tail (CustomPaint, not a rotated square), centered just above the plans.
  Widget _buildSocialProof() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: SpinnerTheme.green,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '2,847',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  TextSpan(
                    text: ' collectors joined this plan ',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  TextSpan(
                    text: 'today',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
          CustomPaint(size: const Size(18, 8), painter: _BubbleTailPainter()),
        ],
      ),
    );
  }

  // ── Bottom CTA ──
  Widget _buildBottomCta(BuildContext context) {
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
          if (error != null) ...[
            Text(
              error!,
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 13,
                weight: FontWeight.w500,
                color: SpinnerTheme.red,
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Draft order: cancel-anytime note and legal links sit ABOVE the
          // button so the Continue CTA stays pinned at the very bottom.
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
              _FooterLink(label: 'Terms', onTap: () => onOpenUrl(_termsUrl)),
              _FooterDivider(),
              _FooterLink(
                  label: 'Privacy', onTap: () => onOpenUrl(_privacyUrl)),
              _FooterDivider(),
              _FooterLink(label: 'Restore', onTap: loading ? null : onRestore),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: Material(
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF5B6CF0), Color(0xFF8B5CF6)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: InkWell(
                  onTap: loading ? null : onSubscribe,
                  child: Center(
                    child: loading
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
        ],
      ),
    );
  }
}

// ── Vinyl disc ──
class _VinylDisc extends StatefulWidget {
  final double size;
  const _VinylDisc({required this.size});

  @override
  State<_VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<_VinylDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return RotationTransition(
      turns: _spin,
      child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0B0B0B),
        border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
        boxShadow: [
          BoxShadow(
            color: SpinnerTheme.accent.withOpacity(0.45),
            blurRadius: 40,
            spreadRadius: 4,
          ),
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
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
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
      ),
    );
  }
}

// ── Plan card ──
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
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
                                size: 17,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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

// ── Social-proof bubble tail (clean downward triangle, like Draft) ──
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SpinnerTheme.green;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Footer links ──
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
