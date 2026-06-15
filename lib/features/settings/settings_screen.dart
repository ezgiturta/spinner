import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database.dart';
import '../../core/router.dart';
import '../../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
          _buildSectionHeader('Collection'),
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
