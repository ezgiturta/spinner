import 'dart:async';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'discogs_api.dart';

/// Callback for sync progress updates.
/// [current] is the number of items processed so far.
/// [total] is the total number of items to sync (may update as pages are fetched).
typedef SyncProgressCallback = void Function(int current, int total);

/// Service for syncing Discogs collection and wantlist into the local database.
class SyncService {
  static const String _syncBoxName = 'sync_state';
  static const int _perPage = 100;
  static const _uuid = Uuid();

  final DiscogsApi _api;
  Box? _syncBox;
  bool _isSyncing = false;

  SyncService(this._api);

  bool get isSyncing => _isSyncing;

  /// Initialize the sync state box. Call once before syncing.
  Future<void> init() async {
    _syncBox = await Hive.openBox(_syncBoxName);
  }

  /// Get the Hive key for storing the last synced page of a folder.
  String _folderPageKey(int folderId) => 'folder_${folderId}_last_page';

  /// Get the Hive key for storing the last synced page of the wantlist.
  String get _wantlistPageKey => 'wantlist_last_page';

  /// Get the last successfully synced page for a folder.
  int _getLastSyncedPage(String key) {
    return _syncBox?.get(key, defaultValue: 0) as int? ?? 0;
  }

  /// Store the last successfully synced page.
  Future<void> _setLastSyncedPage(String key, int page) async {
    await _syncBox?.put(key, page);
  }

  /// Clear sync progress for a folder (call when sync completes).
  Future<void> _clearSyncProgress(String key) async {
    await _syncBox?.delete(key);
  }

  /// Sync the user's Discogs collection for selected folders.
  ///
  /// [folderIds] specifies which folders to sync. If null, syncs all folders.
  /// [onProgress] is called with (current, total) as items are processed.
  ///
  /// Throws [SyncException] if a non-recoverable error occurs.
  Future<SyncResult> syncCollection({
    List<int>? folderIds,
    SyncProgressCallback? onProgress,
  }) async {
    if (_isSyncing) {
      throw SyncException('A sync is already in progress.');
    }

    _isSyncing = true;
    int totalInserted = 0;
    int totalUpdated = 0;
    int totalSkipped = 0;
    int totalErrors = 0;

    try {
      if (_syncBox == null) await init();

      // Fetch all user folders.
      final folders = await _api.getUserCollectionFolders();

      // Determine which folders to sync.
      final foldersToSync = folderIds != null
          ? folders.where((f) => folderIds.contains(f['id'] as int)).toList()
          : folders;

      // Calculate total items across selected folders.
      int totalItems = 0;
      for (final folder in foldersToSync) {
        totalItems += (folder['count'] as int?) ?? 0;
      }

      int processedItems = 0;
      onProgress?.call(processedItems, totalItems);

      for (final folder in foldersToSync) {
        final folderId = folder['id'] as int;
        // Skip the "All" folder (id=0) if specific folders are selected,
        // because it duplicates items from other folders.
        if (folderIds != null && folderId == 0) continue;

        final pageKey = _folderPageKey(folderId);
        final lastSyncedPage = _getLastSyncedPage(pageKey);
        final startPage = lastSyncedPage > 0 ? lastSyncedPage : 1;

        int currentPage = startPage;
        int totalPages = 1; // Will be updated after first request.

        while (currentPage <= totalPages) {
          try {
            final response = await _api.getFolderReleases(
              folderId,
              page: currentPage,
              perPage: _perPage,
            );

            final pagination =
                response['pagination'] as Map<String, dynamic>?;
            totalPages = (pagination?['pages'] as int?) ?? 1;

            // Update total items estimate from pagination.
            final paginationItems = (pagination?['items'] as int?) ?? 0;
            if (currentPage == startPage && paginationItems > 0) {
              // Recalculate total based on actual pagination data.
              final folderCount = (folder['count'] as int?) ?? 0;
              totalItems = totalItems - folderCount + paginationItems;
            }

            final releases = response['releases'] as List<dynamic>? ?? [];

            for (final release in releases) {
              try {
                final result = await _processCollectionRelease(
                  release as Map<String, dynamic>,
                  folderId,
                );
                switch (result) {
                  case _ProcessResult.inserted:
                    totalInserted++;
                    break;
                  case _ProcessResult.updated:
                    totalUpdated++;
                    break;
                  case _ProcessResult.skipped:
                    totalSkipped++;
                    break;
                }
              } catch (e) {
                totalErrors++;
              }

              processedItems++;
              onProgress?.call(processedItems, totalItems);
            }

            // Mark page as synced for resume capability.
            await _setLastSyncedPage(pageKey, currentPage);
            currentPage++;
          } catch (e) {
            // Store progress so we can resume from this page.
            await _setLastSyncedPage(pageKey, currentPage - 1);
            throw SyncException(
              'Failed syncing folder $folderId at page $currentPage: $e',
              folderId: folderId,
              lastPage: currentPage - 1,
            );
          }
        }

        // Folder fully synced - clear the resume marker.
        await _clearSyncProgress(pageKey);
      }

      return SyncResult(
        inserted: totalInserted,
        updated: totalUpdated,
        skipped: totalSkipped,
        errors: totalErrors,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync the user's Discogs wantlist.
  Future<SyncResult> syncWantlist({
    SyncProgressCallback? onProgress,
  }) async {
    if (_isSyncing) {
      throw SyncException('A sync is already in progress.');
    }

    _isSyncing = true;
    int totalInserted = 0;
    int totalUpdated = 0;
    int totalSkipped = 0;
    int totalErrors = 0;

    try {
      if (_syncBox == null) await init();

      final lastSyncedPage = _getLastSyncedPage(_wantlistPageKey);
      final startPage = lastSyncedPage > 0 ? lastSyncedPage : 1;

      int currentPage = startPage;
      int totalPages = 1;
      int totalItems = 0;
      int processedItems = 0;

      while (currentPage <= totalPages) {
        try {
          final response = await _api.getUserWantlist(
            page: currentPage,
            perPage: _perPage,
          );

          final pagination =
              response['pagination'] as Map<String, dynamic>?;
          totalPages = (pagination?['pages'] as int?) ?? 1;
          totalItems = (pagination?['items'] as int?) ?? 0;

          final wants = response['wants'] as List<dynamic>? ?? [];

          for (final want in wants) {
            try {
              final result = await _processWantlistRelease(
                want as Map<String, dynamic>,
              );
              switch (result) {
                case _ProcessResult.inserted:
                  totalInserted++;
                  break;
                case _ProcessResult.updated:
                  totalUpdated++;
                  break;
                case _ProcessResult.skipped:
                  totalSkipped++;
                  break;
              }
            } catch (e) {
              totalErrors++;
            }

            processedItems++;
            onProgress?.call(processedItems, totalItems);
          }

          await _setLastSyncedPage(_wantlistPageKey, currentPage);
          currentPage++;
        } catch (e) {
          await _setLastSyncedPage(_wantlistPageKey, currentPage - 1);
          throw SyncException(
            'Failed syncing wantlist at page $currentPage: $e',
            lastPage: currentPage - 1,
          );
        }
      }

      await _clearSyncProgress(_wantlistPageKey);

      return SyncResult(
        inserted: totalInserted,
        updated: totalUpdated,
        skipped: totalSkipped,
        errors: totalErrors,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Process a single release from the collection response.
  Future<_ProcessResult> _processCollectionRelease(
    Map<String, dynamic> releaseData,
    int folderId,
  ) async {
    final basicInfo =
        releaseData['basic_information'] as Map<String, dynamic>? ?? {};
    final discogsId = (basicInfo['id'] as num?)?.toInt();
    if (discogsId == null) return _ProcessResult.skipped;

    // Duplicate detection: check if this release already exists.
    final existing = await AppDatabase.getRecordByDiscogsId(discogsId);

    final artists = basicInfo['artists'] as List<dynamic>?;
    final artistName = artists?.isNotEmpty == true
        ? (artists!.first as Map<String, dynamic>)['name'] as String? ?? 'Unknown'
        : 'Unknown';

    final formats = basicInfo['formats'] as List<dynamic>?;
    final formatName = formats?.isNotEmpty == true
        ? (formats!.first as Map<String, dynamic>)['name'] as String? ?? ''
        : '';

    final labels = basicInfo['labels'] as List<dynamic>?;
    final labelName = labels?.isNotEmpty == true
        ? (labels!.first as Map<String, dynamic>)['name'] as String? ?? ''
        : '';
    final catalogNo = labels?.isNotEmpty == true
        ? (labels!.first as Map<String, dynamic>)['catno'] as String? ?? ''
        : '';

    final coverUrl = basicInfo['cover_image'] as String? ??
        basicInfo['thumb'] as String? ??
        '';

    final now = DateTime.now().toIso8601String();

    final record = <String, dynamic>{
      'discogs_id': discogsId,
      'title': basicInfo['title'] as String? ?? 'Unknown',
      'artist': artistName,
      'year': (basicInfo['year'] as num?)?.toInt() ?? 0,
      'label': labelName,
      'catalog_no': catalogNo,
      'format': formatName,
      'cover_url': coverUrl,
      'in_collection': 1,
      'in_wantlist': 0, // Strict separation: collection items are NOT wantlist.
      'folder_id': folderId,
      'synced_at': now,
    };

    if (existing != null) {
      // Update existing record but preserve user-specific fields.
      final id = existing['id'] as String;
      record.remove('id');
      // Preserve fields the user may have set manually.
      record.remove('condition');
      record.remove('median_value');
      record.remove('low_value');
      record.remove('high_value');
      record.remove('alert_price');
      record.remove('cover_local_path');
      await AppDatabase.updateRecord(id, record);
      return _ProcessResult.updated;
    } else {
      record['id'] = _uuid.v4();
      await AppDatabase.insertRecord(record);
      return _ProcessResult.inserted;
    }
  }

  /// Process a single release from the wantlist response.
  Future<_ProcessResult> _processWantlistRelease(
    Map<String, dynamic> wantData,
  ) async {
    final basicInfo =
        wantData['basic_information'] as Map<String, dynamic>? ?? {};
    final discogsId = (basicInfo['id'] as num?)?.toInt();
    if (discogsId == null) return _ProcessResult.skipped;

    final existing = await AppDatabase.getRecordByDiscogsId(discogsId);

    final artists = basicInfo['artists'] as List<dynamic>?;
    final artistName = artists?.isNotEmpty == true
        ? (artists!.first as Map<String, dynamic>)['name'] as String? ?? 'Unknown'
        : 'Unknown';

    final formats = basicInfo['formats'] as List<dynamic>?;
    final formatName = formats?.isNotEmpty == true
        ? (formats!.first as Map<String, dynamic>)['name'] as String? ?? ''
        : '';

    final labels = basicInfo['labels'] as List<dynamic>?;
    final labelName = labels?.isNotEmpty == true
        ? (labels!.first as Map<String, dynamic>)['name'] as String? ?? ''
        : '';
    final catalogNo = labels?.isNotEmpty == true
        ? (labels!.first as Map<String, dynamic>)['catno'] as String? ?? ''
        : '';

    final coverUrl = basicInfo['cover_image'] as String? ??
        basicInfo['thumb'] as String? ??
        '';

    final now = DateTime.now().toIso8601String();

    final record = <String, dynamic>{
      'discogs_id': discogsId,
      'title': basicInfo['title'] as String? ?? 'Unknown',
      'artist': artistName,
      'year': (basicInfo['year'] as num?)?.toInt() ?? 0,
      'label': labelName,
      'catalog_no': catalogNo,
      'format': formatName,
      'cover_url': coverUrl,
      'in_collection': 0, // Strict separation: wantlist items are NOT collection.
      'in_wantlist': 1,
      'folder_id': null,
      'synced_at': now,
    };

    if (existing != null) {
      final id = existing['id'] as String;
      // If already in collection, just mark as also in wantlist.
      if (existing['in_collection'] == 1) {
        await AppDatabase.updateRecord(id, {
          'in_wantlist': 1,
          'synced_at': now,
        });
      } else {
        record.remove('id');
        record.remove('condition');
        record.remove('median_value');
        record.remove('low_value');
        record.remove('high_value');
        record.remove('alert_price');
        record.remove('cover_local_path');
        await AppDatabase.updateRecord(id, record);
      }
      return _ProcessResult.updated;
    } else {
      record['id'] = _uuid.v4();
      await AppDatabase.insertRecord(record);
      return _ProcessResult.inserted;
    }
  }

  /// Reset all sync progress markers (e.g. before a full re-sync).
  Future<void> resetSyncProgress() async {
    if (_syncBox == null) await init();
    await _syncBox?.clear();
  }
}

// ── Internal Helpers ──

enum _ProcessResult { inserted, updated, skipped }

// ── Models ──

class SyncResult {
  final int inserted;
  final int updated;
  final int skipped;
  final int errors;

  const SyncResult({
    required this.inserted,
    required this.updated,
    required this.skipped,
    required this.errors,
  });

  int get total => inserted + updated + skipped + errors;

  @override
  String toString() =>
      'SyncResult(inserted: $inserted, updated: $updated, skipped: $skipped, errors: $errors)';
}

class SyncException implements Exception {
  final String message;
  final int? folderId;
  final int? lastPage;

  const SyncException(this.message, {this.folderId, this.lastPage});

  @override
  String toString() => 'SyncException: $message';
}
