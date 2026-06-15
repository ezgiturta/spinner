import 'dart:async';

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/claude_api.dart';
import '../../core/database.dart';
import '../../core/discogs_api.dart';
import '../../core/itunes_api.dart';
import '../../core/subscription_gate.dart';
import '../../core/theme.dart';
import 'search_results_sheet.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  late final DiscogsApi _discogsApi;
  final ImagePicker _picker = ImagePicker();

  bool _isSearching = false;
  String? _errorMessage;
  bool _apiReady = false;

  // Manual search inline results
  List<Map<String, dynamic>>? _searchResults;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _discogsApi = DiscogsApi();
    _initApi();
    // No auto-open: the "Snap the cover" screen shows Take photo + Choose from
    // library side by side, so picking from the gallery is one tap (no need to
    // dismiss the camera first).
  }

  Future<void> _initApi() async {
    try {
      await _discogsApi.init();
      if (mounted) setState(() => _apiReady = true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to initialize Discogs API: $e');
      }
    }
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Cover scan — the primary flow. The user snaps the FRONT cover and the photo
  // goes straight to Claude vision, which identifies the album from the artwork
  // and any visible text. No barcode hardware, no OCR step: the multimodal model
  // handles stylized fonts, logos, blurry and angled shots in one round-trip.
  // ---------------------------------------------------------------------------

  Future<void> _captureCover(ImageSource source) async {
    final XFile? photo = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.rear,
      // Downscale before upload. A full-res iPhone photo (12MP, several MB)
      // base64-encodes past the proxy's body limit and returns HTTP 413.
      // ~1024px is plenty for AI cover recognition.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );
    if (photo == null) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    // Run identify + search first, but DON'T reveal anything yet. Whatever the
    // outcome — a match, no match, or an error — the paywall must appear before
    // the user sees the result. Paying is what unlocks the reveal.
    List<Map<String, dynamic>> results = [];
    String? failure;
    String? guess; // AI's best guess, used to prefill manual search on a miss
    try {
      final parsed = await ClaudeApi.instance.identifyCover(File(photo.path));
      guess = parsed.bestQuery;
      if (guess == null || guess.trim().isEmpty) {
        failure = "Couldn't read this cover. Search by name instead.";
      } else {
        results = await _runSearch(guess);
        if (results.isEmpty) {
          failure = 'No exact match. Refine the search below.';
        }
      }
    } catch (_) {
      failure = "Couldn't reach the server. Check your connection and "
          'try again, or search by name below.';
    }

    if (!mounted) return;
    setState(() => _isSearching = false);

    // Paywall gate — regardless of outcome, before revealing anything.
    if (!await SubscriptionGate.requirePro(context)) return;
    if (!mounted) return;

    // On a miss, don't dead-end on the camera screen: jump to Manual Search
    // with the AI's best guess prefilled and run it, so there's always a next
    // step and visible results.
    if (failure != null) {
      _searchController.text = guess ?? '';
      _tabController.animateTo(_manualTab);
      setState(() => _errorMessage = failure);
      if ((guess ?? '').trim().isNotEmpty) {
        await _searchDiscogs(query: guess!);
      }
      return;
    }
    if (results.length == 1) {
      await _saveAndNavigate(results.first);
    } else {
      final selected = await _showResultsSheet(results);
      if (selected != null && mounted) {
        await _saveAndNavigate(selected);
      }
    }
  }

  static const _manualTab = 1;

  /// Raw search: Discogs first, then iTunes. Returns whatever it finds (may be
  /// empty); swallows errors so the caller can treat "nothing found" uniformly.
  Future<List<Map<String, dynamic>>> _runSearch(String query) async {
    List<Map<String, dynamic>> results = [];
    if (_discogsKeysValid && _apiReady) {
      try {
        final searchResult = await _discogsApi.searchByText(query);
        // Tag each Discogs hit with its release id (Discogs uses 'id') so the
        // saved record carries discogs_id and can later pull Discogs price
        // suggestions. iTunes results are left untagged (no discogs_id).
        results = [
          for (final r in searchResult.results)
            {...r, 'discogs_id': (r['id'] as num?)?.toInt()},
        ];
      } catch (_) {
        // Discogs failed; fall through to iTunes.
      }
    }
    if (results.isEmpty) {
      try {
        results = await ItunesApi.searchAlbums(query);
      } catch (_) {
        // iTunes failed too; return empty.
      }
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Manual search
  // ---------------------------------------------------------------------------

  Future<void> _onManualSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    await _searchDiscogs(query: query);
  }

  // ---------------------------------------------------------------------------
  // Search: try Discogs first, fall back to iTunes
  // ---------------------------------------------------------------------------

  static const _discogsPlaceholderKey = 'YOUR_DISCOGS_CONSUMER_KEY';

  bool get _discogsKeysValid {
    return DiscogsApi.consumerKey != _discogsPlaceholderKey;
  }

  // Manual search shows its results inline (the user picks one, and the
  // paywall fires on tap, via _saveAndNavigate).
  Future<void> _searchDiscogs({required String query}) async {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults = null;
    });

    final results = await _runSearch(query);
    if (!mounted) return;

    setState(() {
      _isSearching = false;
      if (results.isEmpty) {
        _errorMessage = 'No results found. Try a different search.';
      } else {
        _searchResults = results;
      }
    });
  }

  /// Save a search result to the local database and navigate to its detail page.
  Future<void> _saveAndNavigate(Map<String, dynamic> result) async {
    // Scanning + identifying is free. Revealing the result (its value, and
    // saving it to the collection) is Pro — so the paywall appears HERE, after
    // the scan has already found a match. If the user subscribes on the paywall
    // we continue and show the result; otherwise we stop.
    if (!await SubscriptionGate.requirePro(context)) return;
    if (!mounted) return;

    setState(() => _isSearching = true);
    try {
      final id = const Uuid().v4();
      final title = result['title'] as String? ?? 'Unknown';
      final artist = result['artist'] as String? ?? 'Unknown Artist';
      final coverUrl = result['cover_url'] as String? ??
          result['cover_image'] as String? ??
          result['thumb'] as String? ??
          '';
      final year = int.tryParse(result['year']?.toString() ?? '');

      await AppDatabase.insertRecord({
        'id': id,
        'discogs_id': (result['discogs_id'] as num?)?.toInt(),
        'title': title,
        'artist': artist,
        'year': year,
        'cover_url': coverUrl,
        // genre may be a List (Discogs) or String (iTunes); whereType skips any
        // non-string entries safely (cast<String>() would throw on those).
        'genre': () {
          final g = result['genre'];
          if (g is List) return g.whereType<String>().join(', ');
          if (g is String) return g;
          return '';
        }(),
        'in_collection': 1,
        'in_wantlist': 0,
        'synced_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      setState(() => _isSearching = false);
      context.push('/record/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = 'Could not open this record. Please try again.';
      });
    }
  }

  Future<Map<String, dynamic>?> _showResultsSheet(
      List<Map<String, dynamic>> results) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SearchResultsSheet(results: results),
    );
  }

  void _navigateToRecord(Map<String, dynamic> release) {
    _saveAndNavigate(release);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      appBar: AppBar(
        backgroundColor: SpinnerTheme.bg,
        elevation: 0,
        title: Text(
          'Scan & Search',
          style: SpinnerTheme.nunito(
            size: 20,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: SpinnerTheme.accent,
          labelColor: SpinnerTheme.white,
          unselectedLabelColor: SpinnerTheme.grey,
          labelStyle: SpinnerTheme.nunito(
            size: 14,
            weight: FontWeight.w600,
            color: SpinnerTheme.white,
          ),
          unselectedLabelStyle: SpinnerTheme.nunito(
            size: 14,
            weight: FontWeight.w500,
            color: SpinnerTheme.grey,
          ),
          tabs: const [
            Tab(text: 'Scan Cover'),
            Tab(text: 'Manual Search'),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_errorMessage != null) _buildErrorBanner(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildCoverScanTab(),
                    _buildManualSearchTab(),
                  ],
                ),
              ),
            ],
          ),
          if (_isSearching) const Positioned.fill(child: _IdentifyingOverlay()),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: SpinnerTheme.red.withOpacity(0.15),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: SpinnerTheme.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: SpinnerTheme.nunito(
                size: 13,
                weight: FontWeight.w500,
                color: SpinnerTheme.red,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: Icon(Icons.close, color: SpinnerTheme.red, size: 18),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cover scan tab — AI vision is the primary identify path.
  // ---------------------------------------------------------------------------

  Widget _buildCoverScanTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: SpinnerTheme.accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.photo_camera_rounded,
                  size: 56, color: SpinnerTheme.accent),
            ),
            const SizedBox(height: 28),
            Text(
              'Snap the cover',
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 24,
                weight: FontWeight.w800,
                color: SpinnerTheme.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Take a straight-on photo of the front cover and AI identifies the '
              'exact record in seconds.',
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 15,
                weight: FontWeight.w400,
                color: SpinnerTheme.grey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isSearching ? null : _pickImageSource,
                icon: const Icon(Icons.add_a_photo_rounded, size: 20),
                label: Text(
                  'Scan a cover',
                  style: SpinnerTheme.nunito(
                    size: 16,
                    weight: FontWeight.w700,
                    color: SpinnerTheme.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpinnerTheme.accent,
                  foregroundColor: SpinnerTheme.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One entry point for both camera and gallery — a bottom sheet with both
  /// options, so the user doesn't hop between separate buttons/screens.
  void _pickImageSource() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpinnerTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.photo_camera_rounded,
                  color: SpinnerTheme.accent),
              title: Text(
                'Take Photo',
                style: SpinnerTheme.nunito(
                  size: 16,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.white,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _captureCover(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded,
                  color: SpinnerTheme.accent),
              title: Text(
                'Choose from Library',
                style: SpinnerTheme.nunito(
                  size: 16,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.white,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _captureCover(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Manual search tab
  // ---------------------------------------------------------------------------

  Widget _buildManualSearchTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            'Search Albums',
            style: SpinnerTheme.nunito(
              size: 20,
              weight: FontWeight.w700,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter an artist name, album title, or catalog number.',
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w400,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _searchController,
            style: SpinnerTheme.nunito(
              size: 16,
              weight: FontWeight.w500,
              color: SpinnerTheme.white,
            ),
            cursorColor: SpinnerTheme.accent,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _onManualSearch(),
            decoration: InputDecoration(
              hintText: 'e.g. "Miles Davis Kind of Blue"',
              hintStyle: SpinnerTheme.nunito(
                size: 15,
                weight: FontWeight.w400,
                color: SpinnerTheme.grey.withOpacity(0.6),
              ),
              filled: true,
              fillColor: SpinnerTheme.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: SpinnerTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: SpinnerTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: SpinnerTheme.accent, width: 2),
              ),
              prefixIcon:
                  Icon(Icons.search, color: SpinnerTheme.grey, size: 22),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (_, value, __) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: Icon(Icons.clear, color: SpinnerTheme.grey, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchResults = null);
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSearching ? null : _onManualSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: SpinnerTheme.accent,
                foregroundColor: SpinnerTheme.white,
                disabledBackgroundColor: SpinnerTheme.accent.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSearching
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(SpinnerTheme.white),
                      ),
                    )
                  : Text(
                      'Search',
                      style: SpinnerTheme.nunito(
                        size: 16,
                        weight: FontWeight.w600,
                        color: SpinnerTheme.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          // Inline search results
          if (_searchResults != null) Expanded(child: _buildInlineResults()),
        ],
      ),
    );
  }

  Widget _buildInlineResults() {
    final results = _searchResults!;
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No results found.',
          style: SpinnerTheme.nunito(
            size: 14,
            weight: FontWeight.w500,
            color: SpinnerTheme.grey,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: SpinnerTheme.border.withOpacity(0.5),
      ),
      itemBuilder: (context, index) {
        final result = results[index];
        final title = result['title'] as String? ?? 'Unknown Title';
        final artist = result['artist'] as String? ?? '';
        final year = result['year']?.toString() ?? '';
        final thumb = result['cover_url'] as String? ??
            result['thumb'] as String? ??
            result['cover_image'] as String? ??
            '';

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 48,
              height: 48,
              child: thumb.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: SpinnerTheme.surface,
                        child: Icon(Icons.album,
                            size: 24, color: SpinnerTheme.grey),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: SpinnerTheme.surface,
                        child: Icon(Icons.album,
                            size: 24, color: SpinnerTheme.grey),
                      ),
                    )
                  : Container(
                      color: SpinnerTheme.surface,
                      child: Icon(Icons.album,
                          size: 24, color: SpinnerTheme.grey),
                    ),
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w600,
              color: SpinnerTheme.white,
            ),
          ),
          subtitle: Text(
            [if (artist.isNotEmpty) artist, if (year.isNotEmpty) year]
                .join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SpinnerTheme.nunito(
              size: 12,
              weight: FontWeight.w400,
              color: SpinnerTheme.grey,
            ),
          ),
          trailing: Icon(Icons.chevron_right,
              color: SpinnerTheme.grey.withOpacity(0.5), size: 20),
          onTap: () => _navigateToRecord(result),
        );
      },
    );
  }
}

/// Full-screen "Identifying the record" overlay shown while a scan resolves —
/// a sequenced checklist (analyze -> search -> match) like the reference apps,
/// instead of a bare spinner.
class _IdentifyingOverlay extends StatefulWidget {
  const _IdentifyingOverlay();

  @override
  State<_IdentifyingOverlay> createState() => _IdentifyingOverlayState();
}

class _IdentifyingOverlayState extends State<_IdentifyingOverlay> {
  int _step = 0;
  Timer? _timer;

  static const _steps = [
    'Analyzing with AI',
    'Searching the catalog',
    'Matching the pressing',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!mounted) return;
      if (_step < _steps.length - 1) setState(() => _step++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SpinnerTheme.bg.withOpacity(0.97),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: CircularProgressIndicator(
              strokeWidth: 5,
              backgroundColor: SpinnerTheme.surface,
              valueColor: AlwaysStoppedAnimation(SpinnerTheme.accent),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Identifying the record',
            style: SpinnerTheme.nunito(
              size: 22,
              weight: FontWeight.w800,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  _statusDot(i),
                  const SizedBox(width: 12),
                  Text(
                    _steps[i],
                    style: SpinnerTheme.nunito(
                      size: 15,
                      weight: FontWeight.w600,
                      color: i <= _step ? SpinnerTheme.white : SpinnerTheme.grey,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusDot(int i) {
    if (i < _step) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: SpinnerTheme.green,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      );
    }
    if (i == _step) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation(SpinnerTheme.accent),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: SpinnerTheme.border, width: 2),
      ),
    );
  }
}
