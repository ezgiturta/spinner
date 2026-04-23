import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/discogs_api.dart';
import '../../core/sync_service.dart';
import '../../core/theme.dart';

class SyncDialog extends StatefulWidget {
  const SyncDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SyncDialog(),
    );
  }

  @override
  State<SyncDialog> createState() => _SyncDialogState();
}

enum _SyncStep { selectFolders, syncing, done, error }

class _SyncDialogState extends State<SyncDialog> {
  _SyncStep _step = _SyncStep.selectFolders;

  final DiscogsApi _api = DiscogsApi();
  late final SyncService _syncService;

  List<Map<String, dynamic>>? _folders;
  final Set<int> _selectedFolderIds = {};
  bool _isLoadingFolders = true;
  String? _folderError;

  int _syncedCount = 0;
  int _totalCount = 0;
  String? _syncError;
  SyncResult? _syncResult;

  @override
  void initState() {
    super.initState();
    _syncService = SyncService(_api);
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoadingFolders = true;
      _folderError = null;
    });

    try {
      await _api.init();
      final folders = await _api.getUserCollectionFolders();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _isLoadingFolders = false;
        // Select all folders by default
        _selectedFolderIds.addAll(
          folders.map((f) => f['id'] as int),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _folderError = e.toString();
        _isLoadingFolders = false;
      });
    }
  }

  Future<void> _startSync() async {
    if (_selectedFolderIds.isEmpty) return;

    setState(() {
      _step = _SyncStep.syncing;
      _syncedCount = 0;
      _totalCount = 0;
      _syncError = null;
    });

    try {
      final result = await _syncService.syncCollection(
        folderIds: _selectedFolderIds.toList(),
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _syncedCount = current;
            _totalCount = total;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _syncResult = result;
        _step = _SyncStep.done;
      });
    } on SyncException catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _SyncStep.error;
        _syncError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _SyncStep.error;
        _syncError = e.toString();
      });
    }
  }

  void _cancelSync() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SpinnerTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _SyncStep.selectFolders => _buildFolderSelection(),
            _SyncStep.syncing => _buildSyncProgress(),
            _SyncStep.done => _buildDone(),
            _SyncStep.error => _buildError(),
          },
        ),
      ),
    );
  }

  Widget _buildFolderSelection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sync from Discogs',
          style: SpinnerTheme.nunito(
            size: 18,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select folders to import',
          style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
        ),
        const SizedBox(height: 16),
        Flexible(child: _buildFolderList()),
        const SizedBox(height: 16),
        _buildFolderActions(),
      ],
    );
  }

  Widget _buildFolderList() {
    if (_isLoadingFolders) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CircularProgressIndicator(color: SpinnerTheme.accent),
        ),
      );
    }

    if (_folderError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: SpinnerTheme.red, size: 36),
            const SizedBox(height: 8),
            Text(
              'Failed to load folders',
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w600,
                color: SpinnerTheme.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _folderError!,
              style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loadFolders,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: SpinnerTheme.accent),
            ),
          ],
        ),
      );
    }

    final folders = _folders;
    if (folders == null || folders.isEmpty) {
      return Center(
        child: Text(
          'No folders found in your Discogs account.',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.greyLight),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        final folderId = folder['id'] as int;
        final folderName = folder['name'] as String? ?? 'Unknown';
        final folderCount = folder['count'] as int? ?? 0;
        final isSelected = _selectedFolderIds.contains(folderId);

        return CheckboxListTile(
          value: isSelected,
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                _selectedFolderIds.add(folderId);
              } else {
                _selectedFolderIds.remove(folderId);
              }
            });
          },
          title: Text(
            folderName,
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w500,
              color: SpinnerTheme.white,
            ),
          ),
          subtitle: Text(
            '$folderCount items',
            style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey),
          ),
          activeColor: SpinnerTheme.accent,
          checkColor: SpinnerTheme.bg,
          dense: true,
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      },
    );
  }

  Widget _buildFolderActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: SpinnerTheme.grey),
          child: Text(
            'Cancel',
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _selectedFolderIds.isNotEmpty ? _startSync : null,
          style: FilledButton.styleFrom(
            backgroundColor: SpinnerTheme.accent,
            foregroundColor: SpinnerTheme.white,
            disabledBackgroundColor: SpinnerTheme.border,
          ),
          child: Text(
            'Start Sync',
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w600,
              color: _selectedFolderIds.isNotEmpty
                  ? SpinnerTheme.white
                  : SpinnerTheme.grey,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncProgress() {
    final percentage = _totalCount > 0 ? (_syncedCount / _totalCount) : 0.0;
    final percentText = '${(percentage * 100).toStringAsFixed(0)}%';
    final numberFmt = NumberFormat.decimalPattern();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Syncing...',
          style: SpinnerTheme.nunito(
            size: 18,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _totalCount > 0 ? percentage : null,
            backgroundColor: SpinnerTheme.border,
            color: SpinnerTheme.accent,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _totalCount > 0
              ? '${numberFmt.format(_syncedCount)} / ${numberFmt.format(_totalCount)} synced'
              : 'Preparing...',
          style: SpinnerTheme.nunito(
            size: 14,
            weight: FontWeight.w500,
            color: SpinnerTheme.white,
          ),
        ),
        if (_totalCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            percentText,
            style: SpinnerTheme.nunito(
              size: 24,
              weight: FontWeight.w700,
              color: SpinnerTheme.accent,
            ),
          ),
        ],
        const SizedBox(height: 24),
        TextButton(
          onPressed: _cancelSync,
          style: TextButton.styleFrom(foregroundColor: SpinnerTheme.red),
          child: Text(
            'Cancel',
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w600,
              color: SpinnerTheme.red,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDone() {
    final numberFmt = NumberFormat.decimalPattern();
    final total = _syncResult?.total ?? _syncedCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, color: SpinnerTheme.green, size: 48),
        const SizedBox(height: 16),
        Text(
          'Sync Complete',
          style: SpinnerTheme.nunito(
            size: 18,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${numberFmt.format(total)} records synced successfully.',
          style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.greyLight),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: SpinnerTheme.accent,
            foregroundColor: SpinnerTheme.white,
          ),
          child: Text(
            'Done',
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w600,
              color: SpinnerTheme.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: SpinnerTheme.red, size: 48),
        const SizedBox(height: 16),
        Text(
          'Sync Failed',
          style: SpinnerTheme.nunito(
            size: 18,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _syncError ?? 'An unexpected error occurred.',
          style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        if (_syncedCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$_syncedCount records were synced before the error.',
            style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.greyLight),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: SpinnerTheme.grey),
              child: Text(
                'Close',
                style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _startSync,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: SpinnerTheme.accent,
                foregroundColor: SpinnerTheme.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
