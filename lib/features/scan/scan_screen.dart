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
  // The cover camera auto-opens once when the screen first appears so the user
  // doesn't have to tap twice. After that they use the on-screen buttons.
  bool _autoLaunched = false;

  // Manual search inline results
  List<Map<String, dynamic>>? _searchResults;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _discogsApi = DiscogsApi();
    _initApi();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_autoLaunched) {
        _autoLaunched = true;
        _captureCover(ImageSource.camera);
      }
    });
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
      imageQuality: 85,
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
    try {
      final parsed = await ClaudeApi.instance.identifyCover(File(photo.path));
      final query = parsed.bestQuery;
      if (query == null || query.trim().isEmpty) {
        failure = "Couldn't identify this cover. Try a clearer, straight-on "
            'photo of the front cover, or use Manual Search.';
      } else {
        results = await _runSearch(query);
        if (results.isEmpty) {
          failure = 'No match found for this cover. Try a clearer photo or '
              'use Manual Search.';
        }
      }
    } catch (e) {
      failure = 'Cover recognition failed: $e';
    }

    if (!mounted) return;
    setState(() => _isSearching = false);

    // Paywall gate — regardless of outcome, before revealing anything.
    if (!await SubscriptionGate.requirePro(context)) return;
    if (!mounted) return;

    // Paid (or already Pro): now reveal the outcome.
    if (failure != null) {
      setState(() => _errorMessage = failure);
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

  /// Raw search: Discogs first, then iTunes. Returns whatever it finds (may be
  /// empty); swallows errors so the caller can treat "nothing found" uniformly.
  Future<List<Map<String, dynamic>>> _runSearch(String query) async {
    List<Map<String, dynamic>> results = [];
    if (_discogsKeysValid && _apiReady) {
      try {
        final searchResult = await _discogsApi.searchByText(query);
        results = searchResult.results;
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
      'title': title,
      'artist': artist,
      'year': year,
      'cover_url': coverUrl,
      // Discogs returns 'genre' as a list of strings; flatten to comma list.
      'genre': () {
        final g = result['genre'];
        if (g is List) return g.cast<String>().join(', ');
        if (g is String) return g;
        return '';
      }(),
      'in_collection': 1,
      'in_wantlist': 0,
      'synced_at': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    context.push('/record/$id');
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
                onPressed: _isSearching
                    ? null
                    : () => _captureCover(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded, size: 20),
                label: Text(
                  'Take cover photo',
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
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _isSearching
                  ? null
                  : () => _captureCover(ImageSource.gallery),
              icon: Icon(Icons.photo_library_outlined,
                  size: 18, color: SpinnerTheme.grey),
              label: Text(
                'Choose from library',
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.grey,
                ),
              ),
            ),
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
