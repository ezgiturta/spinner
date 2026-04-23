import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../core/database.dart';
import '../../core/discogs_api.dart';
import '../../core/itunes_api.dart';
import '../../core/theme.dart';
import 'search_results_sheet.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  late final DiscogsApi _discogsApi;

  MobileScannerController? _barcodeScannerController;
  bool _isSearching = false;
  String? _errorMessage;
  bool _barcodeProcessing = false;
  bool _cameraFailed = false;
  bool _apiReady = false;

  // Manual search inline results
  List<Map<String, dynamic>>? _searchResults;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _discogsApi = DiscogsApi();
    _initApi();
    _initBarcodeScanner();
  }

  Future<void> _initApi() async {
    try {
      await _discogsApi.init();
      if (mounted) {
        setState(() => _apiReady = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize Discogs API: $e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app resumes and we are on the barcode tab, restart the scanner.
    if (state == AppLifecycleState.resumed && _tabController.index == 0) {
      _initBarcodeScanner();
    }
    // Pause scanner when app is not visible.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _disposeBarcodeScanner();
    }
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    setState(() {
      _errorMessage = null;
    });
    if (_tabController.index == 0) {
      _initBarcodeScanner();
    } else {
      _disposeBarcodeScanner();
    }
  }

  void _initBarcodeScanner() {
    _disposeBarcodeScanner();
    setState(() => _cameraFailed = false);
    try {
      _barcodeScannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        formats: [BarcodeFormat.ean13, BarcodeFormat.upcA, BarcodeFormat.ean8],
      );
    } catch (e) {
      setState(() {
        _cameraFailed = true;
        _errorMessage = 'Could not start camera: $e';
      });
    }
  }

  void _disposeBarcodeScanner() {
    try {
      _barcodeScannerController?.dispose();
    } catch (_) {
      // Ignore disposal errors.
    }
    _barcodeScannerController = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _disposeBarcodeScanner();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Barcode detection
  // ---------------------------------------------------------------------------

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_barcodeProcessing || _isSearching) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!;
    if (code.isEmpty) return;

    _barcodeProcessing = true;
    await _searchDiscogs(barcode: code);
    _barcodeProcessing = false;
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
    // If the consumer key is still a placeholder, Discogs won't work.
    return DiscogsApi.consumerKey != _discogsPlaceholderKey;
  }

  Future<void> _searchDiscogs({String? barcode, String? query}) async {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults = null;
    });

    try {
      List<Map<String, dynamic>> results = [];

      // --- Try Discogs first (only if real keys are configured) ---
      if (_discogsKeysValid && _apiReady) {
        try {
          final DiscogsSearchResult searchResult;
          if (barcode != null) {
            searchResult = await _discogsApi.searchByBarcode(barcode);
          } else {
            searchResult = await _discogsApi.searchByText(query!);
          }
          results = searchResult.results;
        } catch (_) {
          // Discogs failed; fall through to iTunes.
        }
      }

      // --- Fallback to iTunes if Discogs returned nothing ---
      if (results.isEmpty && query != null) {
        try {
          results = await ItunesApi.searchAlbums(query);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _errorMessage = 'Search failed: $e';
            _isSearching = false;
          });
          return;
        }
      }

      if (!mounted) return;

      if (results.isEmpty) {
        setState(() {
          _errorMessage = 'No results found. Try a different search.';
          _isSearching = false;
        });
        return;
      }

      // For manual search, show results inline.
      if (query != null && _tabController.index == 2) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Search failed: $e';
      });
      _showSnackBar('Search failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  /// Save a search result to the local database and navigate to its detail page.
  Future<void> _saveAndNavigate(Map<String, dynamic> result) async {
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
      'genre': result['genre'] as String? ?? '',
      'in_collection': 1,
      'in_wantlist': 0,
      'synced_at': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    context.push('/record/$id');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: SpinnerTheme.nunito(
            size: 13,
            weight: FontWeight.w500,
            color: SpinnerTheme.white,
          ),
        ),
        backgroundColor: SpinnerTheme.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
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
            Tab(text: 'Barcode'),
            Tab(text: 'Cover Art'),
            Tab(text: 'Manual Search'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_errorMessage != null) _buildErrorBanner(),
          if (_isSearching) _buildLoadingIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBarcodeTab(),
                _buildCoverArtTab(),
                _buildManualSearchTab(),
              ],
            ),
          ),
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

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(SpinnerTheme.accent),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Searching...',
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w500,
              color: SpinnerTheme.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Barcode tab
  // ---------------------------------------------------------------------------

  Widget _buildBarcodeTab() {
    if (_cameraFailed || _barcodeScannerController == null) {
      return _buildCameraUnavailable();
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _barcodeScannerController!,
          onDetect: _onBarcodeDetected,
          errorBuilder: (context, error, child) {
            return _buildCameraError(error);
          },
        ),
        // Scan overlay
        Center(
          child: Container(
            width: 280,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: SpinnerTheme.accent, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        // Instruction label
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: SpinnerTheme.surface.withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Align barcode within the frame',
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w500,
                  color: SpinnerTheme.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined,
                size: 64, color: SpinnerTheme.grey),
            const SizedBox(height: 16),
            Text(
              'Camera unavailable',
              style: SpinnerTheme.nunito(
                size: 16,
                weight: FontWeight.w600,
                color: SpinnerTheme.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please grant camera permission in your device settings and try again.',
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 13,
                weight: FontWeight.w400,
                color: SpinnerTheme.grey,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _initBarcodeScanner,
              style: OutlinedButton.styleFrom(
                foregroundColor: SpinnerTheme.accent,
                side: BorderSide(color: SpinnerTheme.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Retry',
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined,
                size: 64, color: SpinnerTheme.grey),
            const SizedBox(height: 16),
            Text(
              'Camera unavailable',
              style: SpinnerTheme.nunito(
                size: 16,
                weight: FontWeight.w600,
                color: SpinnerTheme.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.errorDetails?.message ??
                  'Please grant camera permission in Settings and try again.',
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 13,
                weight: FontWeight.w400,
                color: SpinnerTheme.grey,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _initBarcodeScanner,
              style: OutlinedButton.styleFrom(
                foregroundColor: SpinnerTheme.accent,
                side: BorderSide(color: SpinnerTheme.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Retry',
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cover Art tab (placeholder)
  // ---------------------------------------------------------------------------

  Widget _buildCoverArtTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_outlined, size: 80, color: SpinnerTheme.grey),
            const SizedBox(height: 24),
            Text(
              'Cover Art Recognition',
              style: SpinnerTheme.nunito(
                size: 20,
                weight: FontWeight.w700,
                color: SpinnerTheme.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Coming soon! This feature will use image recognition to '
              'identify albums from cover photos.',
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w400,
                color: SpinnerTheme.grey,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: SpinnerTheme.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SpinnerTheme.accent.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: SpinnerTheme.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Use Manual Search in the meantime',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      weight: FontWeight.w500,
                      color: SpinnerTheme.accent,
                    ),
                  ),
                ],
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
                        valueColor:
                            AlwaysStoppedAnimation(SpinnerTheme.white),
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
          if (_searchResults != null)
            Expanded(child: _buildInlineResults()),
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
                .join(' \u2022 '),
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
