import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai_access.dart';
import '../../core/database.dart';
import '../../core/discogs_api.dart';
import '../../core/router.dart';
import '../../core/subscription_gate.dart';
import '../../core/theme.dart';
import '../collection/sync_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  bool _discogsConnected = false;
  String? _discogsUsername;
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _checkConnections();
    _checkPro();
  }

  Future<void> _checkPro() async {
    final pro = await AiAccess.isPro();
    if (!mounted) return;
    setState(() => _isPro = pro);
  }

  Future<void> _checkConnections() async {
    final discogsToken =
        await _secureStorage.read(key: 'discogs_access_token');
    final discogsUser = await _secureStorage.read(key: 'discogs_username');
    if (!mounted) return;
    setState(() {
      _discogsConnected = discogsToken != null;
      _discogsUsername = discogsUser;
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
        ),
        backgroundColor: error ? SpinnerTheme.red : SpinnerTheme.surface,
      ),
    );
  }

  Future<void> _disconnectDiscogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpinnerTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Disconnect Discogs?',
          style: SpinnerTheme.nunito(
              size: 16, weight: FontWeight.w600, color: SpinnerTheme.white),
        ),
        content: Text(
          'Spinner will stop pulling Discogs price data. Your collection stays.',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.greyLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Disconnect',
                style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DiscogsApi().logout();
    if (!mounted) return;
    setState(() {
      _discogsConnected = false;
      _discogsUsername = null;
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
      setState(() {
        _discogsConnected = true;
        _discogsUsername = api.username;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            api.username != null
                ? 'Connected to Discogs as ${api.username}.'
                : 'Connected to Discogs.',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
          ),
          backgroundColor: SpinnerTheme.green,
        ),
      );
    } on PlatformException catch (e) {
      // flutter_web_auth_2 throws this when the user cancels/dismisses the
      // in-app browser — not a real failure, so stay quiet.
      if (e.code == 'CANCELED' || e.code == 'CANCELLED') return;
      showError('Discogs sign-in was cancelled.');
    } catch (e) {
      // Surface the real error so we can tell apart a bad key (HTTP 401), a
      // callback mismatch, or a network problem.
      showError('Discogs failed: $e');
    }
  }

  Future<void> _restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      if (!mounted) return;
      final hasActive = info.entitlements.active.isNotEmpty;
      // Refresh the Subscription section so it shows Active, not stale "Upgrade".
      if (hasActive) _checkPro();
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

  /// Import the user's Discogs collection. Requires a connected account; opens
  /// the real folder-selection + progress sync dialog.
  Future<void> _syncCollection() async {
    if (!_discogsConnected) {
      _snack('Connect your Discogs account first.', error: true);
      return;
    }
    await SyncDialog.show(context);
    if (!mounted) return;
    // Reflect any freshly imported records on the next collection visit.
    _snack('Collection synced from Discogs.');
  }

  /// Export the collection as a CSV file via the system share sheet.
  Future<void> _exportCSV() async {
    try {
      final records = await AppDatabase.getCollection();
      if (records.isEmpty) {
        _snack('Your collection is empty.', error: true);
        return;
      }
      final csv = _buildCsv(records);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/spinner_collection.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'My Spinner collection',
        text: '${records.length} records from my Spinner collection.',
      );
    } catch (e) {
      _snack('Export failed: $e', error: true);
    }
  }

  String _buildCsv(List<Map<String, dynamic>> records) {
    String cell(Object? v) =>
        '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final buf = StringBuffer()
      ..writeln('Artist,Title,Year,Condition,Low,Median,High');
    for (final r in records) {
      buf.writeln([
        cell(r['artist']),
        cell(r['title']),
        cell(r['year']),
        cell(r['condition']),
        cell(r['low_value']),
        cell(r['median_value']),
        cell(r['high_value']),
      ].join(','));
    }
    return buf.toString();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
          if (_isPro)
            _buildRow(
              icon: Icons.star,
              title: 'Spinner Pro',
              titleColor: SpinnerTheme.accent,
              trailing: Text(
                'Active',
                style: SpinnerTheme.nunito(
                  size: 13,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.green,
                ),
              ),
            )
          else
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
            title: _discogsConnected
                ? (_discogsUsername != null
                    ? 'Discogs: $_discogsUsername'
                    : 'Discogs connected')
                : 'Connect Discogs',
            trailing: _discogsConnected
                ? Text(
                    'Disconnect',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w600,
                      color: SpinnerTheme.grey,
                    ),
                  )
                : Icon(Icons.chevron_right, color: SpinnerTheme.grey),
            onTap: _discogsConnected ? _disconnectDiscogs : _connectDiscogs,
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
