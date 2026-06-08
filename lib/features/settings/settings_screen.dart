import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database.dart';
import '../../core/discogs_api.dart';
import '../../core/router.dart';
import '../../core/subscription_gate.dart';
import '../../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  bool _discogsConnected = false;
  bool _soundcloudConnected = false;

  @override
  void initState() {
    super.initState();
    _checkConnections();
  }

  Future<void> _checkConnections() async {
    final discogsToken =
        await _secureStorage.read(key: 'discogs_access_token');
    final soundcloudToken =
        await _secureStorage.read(key: 'soundcloud_access_token');
    if (!mounted) return;
    setState(() {
      _discogsConnected = discogsToken != null;
      _soundcloudConnected = soundcloudToken != null;
    });
  }

  Future<void> _connectDiscogs() async {
    // Importing your collection from Discogs is a Pro feature.
    if (!await SubscriptionGate.requirePro(context)) return;
    // OAuth 1.0a — three steps:
    //   1) ask Discogs for a request token, get an authorize URL back
    //   2) open it in an in-app browser; Discogs redirects to our
    //      spinner://discogs-callback URL once the user clicks Approve
    //   3) exchange the verifier in the callback for a permanent access
    //      token, persisted by DiscogsApi via flutter_secure_storage
    const callbackScheme = 'spinner';
    const callbackUrl = '$callbackScheme://discogs-callback';
    final api = DiscogsApi();

    void showError(String msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
          ),
          backgroundColor: SpinnerTheme.red,
        ),
      );
    }

    try {
      final auth = await api.getAuthorizationUrl(callbackUrl);
      final resultUri = await FlutterWebAuth2.authenticate(
        url: auth.authorizeUrl,
        callbackUrlScheme: callbackScheme,
      );
      final params = Uri.parse(resultUri).queryParameters;
      final verifier = params['oauth_verifier'];
      if (verifier == null || verifier.isEmpty) {
        showError('Authorization was cancelled.');
        return;
      }
      await api.completeAuthentication(
        requestToken: auth.requestToken,
        requestSecret: auth.requestSecret,
        oauthVerifier: verifier,
      );
      if (!mounted) return;
      setState(() => _discogsConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connected to Discogs.',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
          ),
          backgroundColor: SpinnerTheme.green,
        ),
      );
    } catch (e) {
      showError('Discogs connection failed. Please try again.');
    }
  }

  Future<void> _connectSoundCloud() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Coming soon',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
        ),
        backgroundColor: SpinnerTheme.surface,
      ),
    );
  }

  Future<void> _restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      if (!mounted) return;
      final hasActive = info.entitlements.active.isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasActive
                ? 'Subscription restored.'
                : 'No active subscription found.',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
          ),
          backgroundColor: SpinnerTheme.surface,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restore failed. Please try again.',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
          ),
          backgroundColor: SpinnerTheme.red,
        ),
      );
    }
  }

  Future<void> _syncCollection() async {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpinnerTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Sync Collection',
          style: SpinnerTheme.nunito(
            size: 18,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
        content: Text(
          'This will sync your Discogs collection. Make sure you are connected to Discogs first.',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.greyLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: SpinnerTheme.accent,
              foregroundColor: SpinnerTheme.white,
            ),
            child: Text(
              'Sync',
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w600,
                color: SpinnerTheme.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _exportCSV() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Coming soon',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
        ),
        backgroundColor: SpinnerTheme.surface,
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _resetOnboarding() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpinnerTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Reset Onboarding',
          style: SpinnerTheme.nunito(
            size: 16,
            weight: FontWeight.w600,
            color: SpinnerTheme.white,
          ),
        ),
        content: Text(
          'This will reset the onboarding flow. You will be taken back to the welcome screen.',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.greyLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Reset',
              style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', false);
    if (!mounted) return;
    context.go('/onboarding');
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpinnerTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Clear All Data',
          style: SpinnerTheme.nunito(
            size: 16,
            weight: FontWeight.w600,
            color: SpinnerTheme.white,
          ),
        ),
        content: Text(
          'This will permanently delete your entire collection, wantlist, spin history, and all preferences. This cannot be undone.',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.greyLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete Everything',
              style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final db = await AppDatabase.instance;
      await db.delete('spins');
      await db.delete('cleans');
      await db.delete('records');

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'All data cleared',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
          ),
          backgroundColor: SpinnerTheme.surface,
        ),
      );
      context.go('/onboarding');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to clear data: $e',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
          ),
          backgroundColor: SpinnerTheme.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      appBar: AppBar(
        backgroundColor: SpinnerTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: SpinnerTheme.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Settings',
          style: SpinnerTheme.nunito(
            size: 22,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildSectionHeader('Subscription'),
          _buildRow(
            icon: Icons.star_outline,
            title: 'Upgrade to Pro',
            trailing: Icon(Icons.chevron_right, color: SpinnerTheme.grey),
            onTap: () => context.push(AppRoutes.paywall),
          ),
          _buildRow(
            icon: Icons.restore,
            title: 'Restore Purchases',
            trailing: Icon(Icons.chevron_right, color: SpinnerTheme.grey),
            onTap: _restorePurchases,
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Account'),
          _buildRow(
            icon: Icons.album,
            title: 'Connect Discogs',
            trailing: _discogsConnected
                ? Text(
                    'Connected \u2713',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w600,
                      color: SpinnerTheme.green,
                    ),
                  )
                : Icon(Icons.chevron_right, color: SpinnerTheme.grey),
            onTap: _discogsConnected ? null : _connectDiscogs,
          ),
          _buildRow(
            icon: Icons.cloud_outlined,
            title: 'Connect SoundCloud',
            trailing: _soundcloudConnected
                ? Text(
                    'Connected \u2713',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w600,
                      color: SpinnerTheme.green,
                    ),
                  )
                : Icon(Icons.chevron_right, color: SpinnerTheme.grey),
            onTap: _soundcloudConnected ? null : _connectSoundCloud,
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Collection'),
          _buildRow(
            icon: Icons.sync,
            title: 'Sync Collection',
            trailing: Icon(Icons.chevron_right, color: SpinnerTheme.grey),
            onTap: _syncCollection,
          ),
          _buildRow(
            icon: Icons.file_download_outlined,
            title: 'Export CSV',
            trailing: Icon(Icons.chevron_right, color: SpinnerTheme.grey),
            onTap: _exportCSV,
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('About'),
          _buildRow(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            trailing: Icon(Icons.open_in_new, color: SpinnerTheme.grey, size: 18),
            onTap: () => _openUrl('https://spinner-legal.vercel.app/privacy'),
          ),
          _buildRow(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            trailing: Icon(Icons.open_in_new, color: SpinnerTheme.grey, size: 18),
            onTap: () => _openUrl('https://spinner-legal.vercel.app/terms'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Text(
              'Version 1.0.0',
              style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
            ),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Danger Zone'),
          _buildRow(
            icon: Icons.restart_alt,
            title: 'Reset Onboarding',
            titleColor: SpinnerTheme.red,
            trailing: Icon(Icons.chevron_right, color: SpinnerTheme.red),
            onTap: _resetOnboarding,
          ),
          _buildRow(
            icon: Icons.delete_forever_outlined,
            title: 'Clear All Data',
            titleColor: SpinnerTheme.red,
            trailing: Icon(Icons.chevron_right, color: SpinnerTheme.red),
            onTap: _clearAllData,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: SpinnerTheme.nunito(
          size: 12,
          weight: FontWeight.w700,
          color: SpinnerTheme.grey,
        ),
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    required Widget trailing,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: titleColor ?? SpinnerTheme.white, size: 22),
        title: Text(
          title,
          style: SpinnerTheme.nunito(
            size: 15,
            weight: FontWeight.w500,
            color: titleColor ?? SpinnerTheme.white,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
