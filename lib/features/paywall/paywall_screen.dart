import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _loading = false;
  String? _error;

  static const _proFeatures = [
    _Feature(
      icon: Icons.notifications_active,
      title: 'Wantlist Alerts',
      subtitle: 'Get notified when prices drop on records you want',
    ),
    _Feature(
      icon: Icons.all_inclusive,
      title: 'Unlimited Collection',
      subtitle: 'No cap on how many records you can track',
    ),
    _Feature(
      icon: Icons.show_chart,
      title: 'Price History',
      subtitle: 'See value trends over time for every record',
    ),
    _Feature(
      icon: Icons.account_balance_wallet,
      title: 'Collection Value',
      subtitle: 'Real-time total value of your entire collection',
    ),
    _Feature(
      icon: Icons.explore,
      title: 'Discovery',
      subtitle: 'Get personalized recommendations based on your taste',
    ),
    _Feature(
      icon: Icons.download,
      title: 'CSV Export',
      subtitle: 'Export your collection data anytime',
    ),
  ];

  static const _comparisonRows = [
    _ComparisonRow('Records tracked', '25', 'Unlimited'),
    _ComparisonRow('Price lookups', '10/mo', 'Unlimited'),
    _ComparisonRow('Wantlist alerts', '-', 'Included'),
    _ComparisonRow('Price history', '-', 'Included'),
    _ComparisonRow('Collection value', '-', 'Included'),
    _ComparisonRow('Discovery', '-', 'Included'),
    _ComparisonRow('CSV export', '-', 'Included'),
  ];

  Future<void> _startTrial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null || current.availablePackages.isEmpty) {
        throw Exception('No offerings available.');
      }

      final package = current.availablePackages.first;
      await Purchases.purchasePackage(package);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        // User cancelled -- not an error.
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = 'Purchase failed. Please try again.';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
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
      body: Stack(
        children: [
          // Scrollable content
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildFeaturesList()),
              SliverToBoxAdapter(child: _buildComparison()),
              // Bottom padding for CTA
              const SliverToBoxAdapter(child: SizedBox(height: 160)),
            ],
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SpinnerTheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: SpinnerTheme.border),
                ),
                child: Icon(
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

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 56,
        24,
        24,
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: SpinnerTheme.accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.star, color: SpinnerTheme.accent, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            'Upgrade to Pro',
            style: SpinnerTheme.nunito(
              size: 28,
              weight: FontWeight.w800,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '\$2.99/month',
            style: SpinnerTheme.nunito(
              size: 18,
              weight: FontWeight.w700,
              color: SpinnerTheme.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start with a 7-day free trial',
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w400,
              color: SpinnerTheme.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What's included",
            style: SpinnerTheme.nunito(
              size: 20,
              weight: FontWeight.w700,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 16),
          ..._proFeatures.map((f) => _buildFeatureTile(f)),
        ],
      ),
    );
  }

  Widget _buildFeatureTile(_Feature feature) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: SpinnerTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(feature.icon, color: SpinnerTheme.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: SpinnerTheme.nunito(
                    size: 16,
                    weight: FontWeight.w700,
                    color: SpinnerTheme.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  feature.subtitle,
                  style: SpinnerTheme.nunito(
                    size: 13,
                    weight: FontWeight.w400,
                    color: SpinnerTheme.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparison() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Free vs Pro',
            style: SpinnerTheme.nunito(
              size: 20,
              weight: FontWeight.w700,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: SpinnerTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SpinnerTheme.border),
            ),
            child: Column(
              children: [
                // Header row
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Feature',
                          style: SpinnerTheme.nunito(
                            size: 13,
                            weight: FontWeight.w600,
                            color: SpinnerTheme.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Free',
                          textAlign: TextAlign.center,
                          style: SpinnerTheme.nunito(
                            size: 13,
                            weight: FontWeight.w600,
                            color: SpinnerTheme.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Pro',
                          textAlign: TextAlign.center,
                          style: SpinnerTheme.nunito(
                            size: 13,
                            weight: FontWeight.w700,
                            color: SpinnerTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: SpinnerTheme.border),
                ..._comparisonRows.map((row) => _buildComparisonRow(row)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(_ComparisonRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              row.feature,
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w500,
                color: SpinnerTheme.white,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.free,
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w500,
                color: row.free == '-'
                    ? SpinnerTheme.grey
                    : SpinnerTheme.greyLight,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.pro,
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w600,
                color: SpinnerTheme.green,
              ),
            ),
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
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: SpinnerTheme.white,
                          ),
                        )
                      : Text(
                          'Start Free Trial',
                          style: SpinnerTheme.nunito(
                            size: 17,
                            weight: FontWeight.w700,
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
              GestureDetector(
                onTap: () => _openUrl('https://spinner.app/terms'),
                child: Text(
                  'Terms of Use',
                  style: SpinnerTheme.nunito(
                    size: 12,
                    weight: FontWeight.w500,
                    color: SpinnerTheme.grey,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '|',
                  style: SpinnerTheme.nunito(
                    size: 12,
                    weight: FontWeight.w400,
                    color: SpinnerTheme.grey,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _openUrl('https://spinner.app/privacy'),
                child: Text(
                  'Privacy Policy',
                  style: SpinnerTheme.nunito(
                    size: 12,
                    weight: FontWeight.w500,
                    color: SpinnerTheme.grey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String subtitle;

  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _ComparisonRow {
  final String feature;
  final String free;
  final String pro;

  const _ComparisonRow(this.feature, this.free, this.pro);
}
