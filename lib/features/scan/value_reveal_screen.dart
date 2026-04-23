import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/database.dart';
import '../../core/discogs_api.dart';
import '../../core/theme.dart';

class ValueRevealScreen extends StatefulWidget {
  final Map<String, dynamic> release;

  const ValueRevealScreen({super.key, required this.release});

  @override
  State<ValueRevealScreen> createState() => _ValueRevealScreenState();
}

class _ValueRevealScreenState extends State<ValueRevealScreen> {
  final DiscogsApi _discogsApi = DiscogsApi();
  static const _uuid = Uuid();

  bool _isLoading = true;
  String? _errorMessage;

  // Release details
  Map<String, dynamic>? _releaseDetails;
  Map<String, dynamic>? _priceData;
  List<FlSpot>? _priceHistory;
  bool _inCollection = false;
  bool _inWantlist = false;
  bool _addingToCollection = false;
  bool _addingToWantlist = false;

  @override
  void initState() {
    super.initState();
    _discogsApi.init();
    _loadReleaseData();
  }

  Future<void> _loadReleaseData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final releaseId = widget.release['id'] as int;

      // Fetch release details and price suggestions in parallel.
      final detailsFuture = _discogsApi.getReleaseDetails(releaseId);
      final pricesFuture = _discogsApi.getPriceSuggestions(releaseId);
      final existingFuture = AppDatabase.getRecordByDiscogsId(releaseId);

      final details = await detailsFuture;
      final prices = await pricesFuture;

      // Check if already in local DB.
      final existing = await existingFuture;

      if (!mounted) return;

      setState(() {
        _releaseDetails = details;
        _priceData = prices ?? <String, dynamic>{};
        _priceHistory = _buildPriceSpots(_priceData!);
        _inCollection = existing != null && existing['in_collection'] == 1;
        _inWantlist = existing != null && existing['in_wantlist'] == 1;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load release data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  List<FlSpot> _buildPriceSpots(Map<String, dynamic> priceData) {
    // Price suggestions returns condition-keyed data; build spots from available values.
    final spots = <FlSpot>[];
    int i = 0;
    for (final key in ['Poor (P)', 'Fair (F)', 'Good (G)', 'Good Plus (G+)', 'Very Good (VG)', 'Very Good Plus (VG+)', 'Near Mint (NM or M-)', 'Mint (M)']) {
      final entry = priceData[key] as Map<String, dynamic>?;
      if (entry != null) {
        final value = (entry['value'] as num?)?.toDouble() ?? 0.0;
        spots.add(FlSpot(i.toDouble(), value));
      }
      i++;
    }
    return spots;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _addToCollection() async {
    if (_addingToCollection || _inCollection) return;

    setState(() => _addingToCollection = true);

    try {
      final releaseId = widget.release['id'] as int;
      final existing = await AppDatabase.getRecordByDiscogsId(releaseId);

      if (existing != null) {
        await AppDatabase.updateRecord(existing['id'] as String, {
          'in_collection': 1,
          'synced_at': DateTime.now().toIso8601String(),
        });
      } else {
        final record = _buildRecordMap(inCollection: true, inWantlist: false);
        await AppDatabase.insertRecord(record);
      }

      if (!mounted) return;
      setState(() {
        _inCollection = true;
        _addingToCollection = false;
      });
      _showSnackBar('Added to collection');
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingToCollection = false);
      _showSnackBar('Failed to add: ${e.toString()}', isError: true);
    }
  }

  Future<void> _addToWantlist() async {
    if (_addingToWantlist || _inWantlist) return;

    setState(() => _addingToWantlist = true);

    try {
      final releaseId = widget.release['id'] as int;
      final existing = await AppDatabase.getRecordByDiscogsId(releaseId);

      if (existing != null) {
        await AppDatabase.updateRecord(existing['id'] as String, {
          'in_wantlist': 1,
          'synced_at': DateTime.now().toIso8601String(),
        });
      } else {
        final record = _buildRecordMap(inCollection: false, inWantlist: true);
        await AppDatabase.insertRecord(record);
      }

      if (!mounted) return;
      setState(() {
        _inWantlist = true;
        _addingToWantlist = false;
      });
      _showSnackBar('Added to wantlist');
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingToWantlist = false);
      _showSnackBar('Failed to add: ${e.toString()}', isError: true);
    }
  }

  Map<String, dynamic> _buildRecordMap({
    required bool inCollection,
    required bool inWantlist,
  }) {
    final details = _releaseDetails ?? widget.release;
    final artists = details['artists'] as List<dynamic>?;
    final artistName = artists?.isNotEmpty == true
        ? (artists!.first as Map<String, dynamic>)['name'] as String? ?? 'Unknown'
        : (widget.release['title'] as String?)?.split(' - ').firstOrNull ?? 'Unknown';

    final labels = details['labels'] as List<dynamic>?;
    final labelName = labels?.isNotEmpty == true
        ? (labels!.first as Map<String, dynamic>)['name'] as String? ?? ''
        : '';
    final catalogNo = labels?.isNotEmpty == true
        ? (labels!.first as Map<String, dynamic>)['catno'] as String? ?? ''
        : '';

    return {
      'id': _uuid.v4(),
      'discogs_id': widget.release['id'] as int,
      'title': details['title'] as String? ?? 'Unknown',
      'artist': artistName,
      'year': (details['year'] as num?)?.toInt() ?? 0,
      'label': labelName,
      'catalog_no': catalogNo,
      'cover_url': widget.release['cover_image'] as String? ??
          widget.release['thumb'] as String? ?? '',
      'in_collection': inCollection ? 1 : 0,
      'in_wantlist': inWantlist ? 1 : 0,
      'synced_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _viewOnDiscogs() async {
    final uri = widget.release['uri'] as String?;
    if (uri == null) return;

    final url = Uri.parse(
      uri.startsWith('http') ? uri : 'https://www.discogs.com$uri',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: SpinnerTheme.nunito(
            size: 14,
            weight: FontWeight.w500,
            color: SpinnerTheme.white,
          ),
        ),
        backgroundColor: isError ? SpinnerTheme.red : SpinnerTheme.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String get _artist {
    final details = _releaseDetails;
    final artists = details?['artists'] as List<dynamic>?;
    if (artists != null && artists.isNotEmpty) {
      return (artists.first as Map<String, dynamic>)['name'] as String? ?? 'Unknown Artist';
    }
    // Fallback: try splitting "Artist - Title" from search result title
    final fullTitle = widget.release['title'] as String? ?? '';
    if (fullTitle.contains(' - ')) {
      return fullTitle.split(' - ').first.trim();
    }
    return 'Unknown Artist';
  }

  String get _title {
    final details = _releaseDetails;
    final title = details?['title'] as String? ?? widget.release['title'] as String? ?? 'Unknown Title';
    // If title has "Artist - Title" format, extract just the title part
    if (title.contains(' - ')) {
      return title.split(' - ').skip(1).join(' - ').trim();
    }
    return title;
  }

  String get _year {
    final y = widget.release['year'] ?? _releaseDetails?['year'];
    return y != null ? y.toString() : '';
  }

  String get _coverUrl {
    final cover = widget.release['cover_image'] as String?;
    if (cover != null && cover.isNotEmpty) return cover;
    final thumb = widget.release['thumb'] as String?;
    if (thumb != null && thumb.isNotEmpty) return thumb;
    final images = _releaseDetails?['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      final uri = (images.first as Map<String, dynamic>)['uri'] as String?;
      if (uri != null && uri.isNotEmpty) return uri;
    }
    return '';
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '--';
    final value = (price is num) ? price.toDouble() : 0.0;
    return '\$${value.toStringAsFixed(2)}';
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: SpinnerTheme.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Value',
          style: SpinnerTheme.nunito(
            size: 18,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
      ),
      body: _isLoading
          ? _buildLoading()
          : _errorMessage != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(SpinnerTheme.accent),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading release data...',
            style: SpinnerTheme.nunito(
              size: 15,
              weight: FontWeight.w500,
              color: SpinnerTheme.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: SpinnerTheme.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w500,
                color: SpinnerTheme.grey,
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _loadReleaseData,
              child: Text(
                'Retry',
                style: SpinnerTheme.nunito(
                  size: 15,
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

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAlbumHeader(),
          const SizedBox(height: 28),
          _buildValueSection(),
          const SizedBox(height: 24),
          _buildPriceChart(),
          const SizedBox(height: 28),
          _buildPressingDetails(),
          const SizedBox(height: 28),
          _buildActionButtons(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Album header
  // ---------------------------------------------------------------------------

  Widget _buildAlbumHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Album art
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 120,
            height: 120,
            child: _coverUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: _coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: SpinnerTheme.surface,
                      child: Center(
                        child: Icon(Icons.album,
                            size: 40, color: SpinnerTheme.grey),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: SpinnerTheme.surface,
                      child: Center(
                        child: Icon(Icons.album,
                            size: 40, color: SpinnerTheme.grey),
                      ),
                    ),
                  )
                : Container(
                    color: SpinnerTheme.surface,
                    child: Center(
                      child:
                          Icon(Icons.album, size: 40, color: SpinnerTheme.grey),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        // Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title,
                style: SpinnerTheme.nunito(
                  size: 20,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _artist,
                style: SpinnerTheme.nunito(
                  size: 16,
                  weight: FontWeight.w500,
                  color: SpinnerTheme.grey,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_year.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _year,
                  style: SpinnerTheme.nunito(
                    size: 14,
                    weight: FontWeight.w400,
                    color: SpinnerTheme.grey,
                  ),
                ),
              ],
              if (_inCollection) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SpinnerTheme.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'In Collection \u2713',
                    style: SpinnerTheme.nunito(
                      size: 12,
                      weight: FontWeight.w600,
                      color: SpinnerTheme.green,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Value section
  // ---------------------------------------------------------------------------

  Widget _buildValueSection() {
    // Extract prices from price suggestions keyed by condition
    final vgPlus = _priceData?['Very Good Plus (VG+)'] as Map<String, dynamic>?;
    final nearMint = _priceData?['Near Mint (NM or M-)'] as Map<String, dynamic>?;
    final good = _priceData?['Good (G)'] as Map<String, dynamic>?;

    final median = nearMint?['value'] ?? vgPlus?['value'];
    final low = good?['value'];
    final high = nearMint?['value'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        children: [
          Text(
            'Estimated Value',
            style: SpinnerTheme.nunito(
              size: 13,
              weight: FontWeight.w500,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatPrice(median),
            style: SpinnerTheme.nunito(
              size: 40,
              weight: FontWeight.w800,
              color: SpinnerTheme.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildPriceColumn('Low', low)),
              Container(
                width: 1,
                height: 40,
                color: SpinnerTheme.border,
              ),
              Expanded(child: _buildPriceColumn('Median', median)),
              Container(
                width: 1,
                height: 40,
                color: SpinnerTheme.border,
              ),
              Expanded(child: _buildPriceColumn('High', high)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceColumn(String label, dynamic price) {
    return Column(
      children: [
        Text(
          label,
          style: SpinnerTheme.nunito(
            size: 12,
            weight: FontWeight.w500,
            color: SpinnerTheme.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatPrice(price),
          style: SpinnerTheme.nunito(
            size: 18,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Price chart
  // ---------------------------------------------------------------------------

  Widget _buildPriceChart() {
    if (_priceHistory == null || _priceHistory!.length < 2) {
      return const SizedBox.shrink();
    }

    final minY =
        _priceHistory!.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY =
        _priceHistory!.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.15;

    return Container(
      width: double.infinity,
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price by Condition',
            style: SpinnerTheme.nunito(
              size: 13,
              weight: FontWeight.w500,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: ((maxY - minY) / 4).clamp(1, 1000),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: SpinnerTheme.border.withOpacity(0.5),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, _) => Text(
                        '\$${value.toInt()}',
                        style: SpinnerTheme.nunito(
                          size: 10,
                          weight: FontWeight.w400,
                          color: SpinnerTheme.grey,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minY: (minY - padding).clamp(0, double.infinity),
                maxY: maxY + padding,
                lineBarsData: [
                  LineChartBarData(
                    spots: _priceHistory!,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: SpinnerTheme.accent,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: SpinnerTheme.accent.withOpacity(0.08),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => SpinnerTheme.surface,
                    getTooltipItems: (spots) => spots
                        .map((spot) => LineTooltipItem(
                              '\$${spot.y.toStringAsFixed(2)}',
                              SpinnerTheme.nunito(
                                size: 13,
                                weight: FontWeight.w600,
                                color: SpinnerTheme.white,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pressing details
  // ---------------------------------------------------------------------------

  Widget _buildPressingDetails() {
    final details = _releaseDetails;
    if (details == null) return const SizedBox.shrink();

    final labels = details['labels'] as List<dynamic>?;
    final labelName = labels?.isNotEmpty == true
        ? (labels!.first as Map<String, dynamic>)['name']?.toString()
        : null;
    final catalogNo = labels?.isNotEmpty == true
        ? (labels!.first as Map<String, dynamic>)['catno']?.toString()
        : null;

    final formats = details['formats'] as List<dynamic>?;
    final formatName = formats?.isNotEmpty == true
        ? (formats!.first as Map<String, dynamic>)['name']?.toString()
        : null;

    final pills = <_PressingPill>[
      if (labelName != null)
        _PressingPill(label: 'Label', value: labelName),
      if (catalogNo != null)
        _PressingPill(label: 'Cat #', value: catalogNo),
      if (details['country'] != null)
        _PressingPill(label: 'Country', value: details['country'].toString()),
      if (formatName != null)
        _PressingPill(label: 'Format', value: formatName),
    ];

    if (pills.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pressing Details',
          style: SpinnerTheme.nunito(
            size: 16,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: pills.map((pill) => _buildPressingPill(pill)).toList(),
        ),
      ],
    );
  }

  Widget _buildPressingPill(_PressingPill pill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SpinnerTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pill.label,
            style: SpinnerTheme.nunito(
              size: 11,
              weight: FontWeight.w500,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            pill.value,
            style: SpinnerTheme.nunito(
              size: 14,
              weight: FontWeight.w600,
              color: SpinnerTheme.white,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Action buttons
  // ---------------------------------------------------------------------------

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                label: _inCollection ? 'In Collection \u2713' : 'Add to Collection',
                icon: _inCollection ? Icons.check_circle : Icons.add_circle_outline,
                color: _inCollection ? SpinnerTheme.green : SpinnerTheme.accent,
                isLoading: _addingToCollection,
                onTap: _inCollection ? null : _addToCollection,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                label: _inWantlist ? 'In Wantlist \u2713' : 'Add to Wantlist',
                icon: _inWantlist ? Icons.check_circle : Icons.favorite_border,
                color: _inWantlist ? SpinnerTheme.green : SpinnerTheme.amber,
                isLoading: _addingToWantlist,
                onTap: _inWantlist ? null : _addToWantlist,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _buildActionButton(
            label: 'View on Discogs',
            icon: Icons.open_in_new,
            color: SpinnerTheme.grey,
            onTap: _viewOnDiscogs,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null && !isLoading;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: isDisabled
              ? color.withOpacity(0.1)
              : color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(isDisabled ? 0.2 : 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              )
            else
              Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w600,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data class for pressing detail pills
// ---------------------------------------------------------------------------

class _PressingPill {
  final String label;
  final String value;

  const _PressingPill({required this.label, required this.value});
}
