import 'dart:convert' as dart_convert;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai_access.dart';
import '../../core/database.dart';
import '../../core/ebay_api.dart';
import '../../core/genre_likes.dart';
import '../../core/itunes_api.dart';
import '../../core/market_value_service.dart';
import '../../core/reverb_api.dart';
import '../../core/spotify_api.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import 'widgets/album_story_card.dart';

class RecordDetailScreen extends StatefulWidget {
  final String recordId;

  const RecordDetailScreen({super.key, required this.recordId});

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  Map<String, dynamic>? _record;
  List<Map<String, dynamic>>? _spinHistory;
  List<Map<String, dynamic>>? _cleanHistory;
  bool _isLoading = true;
  String? _error;
  bool _loadingValue = false;

  // Editable fields
  String? _selectedColor;
  String? _selectedCondition;
  final _notesController = TextEditingController();
  bool _isSigned = false;
  bool _isNumbered = false;

  static const _conditions = ['NM', 'VG+', 'VG', 'G+', 'G', 'F', 'P'];

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRecord() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final record = await AppDatabase.getRecordById(widget.recordId);
      if (record == null) throw Exception('Record not found');

      final spinHistory = await AppDatabase.getSpins(widget.recordId);
      final cleanHistory = await AppDatabase.getCleans(widget.recordId);

      if (!mounted) return;
      setState(() {
        _record = record;
        _spinHistory = spinHistory;
        _cleanHistory = cleanHistory;
        _selectedColor = record['vinyl_color'] as String?;
        _selectedCondition = record['condition'] as String?;
        _notesController.text = record['edition_notes'] as String? ?? '';
        _isSigned = record['is_signed'] == 1;
        _isNumbered = record['is_numbered'] == 1;
        _isLoading = false;
      });

      // Fetch live market value in the background (won't block the screen).
      _maybeFetchValue(record);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Pull live market value (eBay + Reverb + Discogs if connected) when the
  /// stored value is missing or stale, persist it, and update the card.
  Future<void> _maybeFetchValue(Map<String, dynamic> record) async {
    if (!MarketValueService.isStale(record)) return;
    setState(() => _loadingValue = true);
    final mv = await MarketValueService.instance.fetchAndStore(record);
    if (!mounted) return;
    setState(() {
      _loadingValue = false;
      if (mv != null && _record != null) {
        _record = {
          ..._record!,
          'low_value': mv.low,
          'median_value': mv.median,
          'high_value': mv.high,
        };
      }
    });
  }

  Future<void> _logSpin() async {
    try {
      await AppDatabase.logSpin(widget.recordId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Spin logged!'),
          backgroundColor: SpinnerTheme.green,
          duration: const Duration(seconds: 1),
        ),
      );
      _loadRecord();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to log spin: $e'),
          backgroundColor: SpinnerTheme.red,
        ),
      );
    }
  }

  Future<void> _logClean() async {
    try {
      await AppDatabase.logClean(widget.recordId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Clean logged!'),
          backgroundColor: SpinnerTheme.green,
          duration: const Duration(seconds: 1),
        ),
      );
      _loadRecord();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to log clean: $e'),
          backgroundColor: SpinnerTheme.red,
        ),
      );
    }
  }

  Future<void> _saveEdits() async {
    try {
      await AppDatabase.updateRecord(widget.recordId, {
        'vinyl_color': _selectedColor,
        'condition': _selectedCondition,
        'edition_notes': _notesController.text.trim(),
        'is_signed': _isSigned ? 1 : 0,
        'is_numbered': _isNumbered ? 1 : 0,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Changes saved'),
          backgroundColor: SpinnerTheme.green,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: SpinnerTheme.red,
        ),
      );
    }
  }

  Future<void> _openAiGrader() async {
    final allowed = await AiAccess.canUseCondition();
    if (!mounted) return;
    if (!allowed) {
      context.push(AppRoutes.paywall);
      return;
    }
    final record = _record;
    context.push(
      AppRoutes.gradePath(widget.recordId),
      extra: {
        'title': record?['title'] as String?,
        'artist': record?['artist'] as String?,
      },
    );
    // When the grader returns, refresh in case condition was applied.
    if (mounted) _loadRecord();
  }

  Future<void> _openDiscogs() async {
    final record = _record;
    final discogsId = record?['discogs_id'];
    if (discogsId == null) return;
    final uri = Uri.tryParse('https://www.discogs.com/release/$discogsId');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: SpinnerTheme.accent),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final record = _record;
    if (record == null) {
      return Center(
        child: Text(
          'Record not found.',
          style: SpinnerTheme.nunito(size: 16, color: SpinnerTheme.greyLight),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        _buildSliverAppBar(record),
        SliverToBoxAdapter(child: _buildContent(record)),
      ],
    );
  }

  Widget _buildSliverAppBar(Map<String, dynamic> record) {
    final coverUrl = record['cover_url'] as String?;

    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: SpinnerTheme.bg,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        color: SpinnerTheme.white,
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: coverUrl != null && coverUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: SpinnerTheme.surface,
                  child: Center(
                    child: Icon(Icons.album, color: SpinnerTheme.grey, size: 80),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: SpinnerTheme.surface,
                  child: Center(
                    child: Icon(Icons.album, color: SpinnerTheme.grey, size: 80),
                  ),
                ),
              )
            : Container(
                color: SpinnerTheme.surface,
                child: Center(
                  child: Icon(Icons.album, color: SpinnerTheme.grey, size: 80),
                ),
              ),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> record) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _buildTitleSection(record),
          const SizedBox(height: 20),
          _buildValueCard(record),
          const SizedBox(height: 20),
          _CheapestCopiesCard(record: record),
          const SizedBox(height: 20),
          _PreviewTracksCard(record: record),
          const SizedBox(height: 20),
          _SpotifyRecsCard(record: record),
          const SizedBox(height: 20),
          _buildPriceChart(record),
          const SizedBox(height: 20),
          AlbumStoryCard(
            recordId: widget.recordId,
            title: (record['title'] as String?) ?? '',
            artist: (record['artist'] as String?) ?? '',
            year: record['year'] as int?,
            label: record['label'] as String?,
            country: record['pressing_country'] as String?,
          ),
          const SizedBox(height: 20),
          _buildPressingDetails(record),
          const SizedBox(height: 20),
          _buildEditSection(),
          const SizedBox(height: 20),
          _buildActionButtons(),
          const SizedBox(height: 20),
          _buildSpinHistorySection(),
          const SizedBox(height: 20),
          _buildCleanHistorySection(),
          const SizedBox(height: 16),
          _buildDiscogsButton(record),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Title
  // ---------------------------------------------------------------------------

  Widget _buildTitleSection(Map<String, dynamic> record) {
    final title = record['title'] as String? ?? 'Unknown Title';
    final artist = record['artist'] as String? ?? 'Unknown Artist';
    final year = record['year'] as int?;
    final label = record['label'] as String?;
    final catalogNo = record['catalog_no'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: SpinnerTheme.nunito(
            size: 24,
            weight: FontWeight.w800,
            color: SpinnerTheme.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          artist,
          style: SpinnerTheme.nunito(
            size: 17,
            color: SpinnerTheme.greyLight,
          ),
        ),
        const SizedBox(height: 8),
        _TasteMatchChip(record: record),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            if (year != null && year > 0)
              _buildMetaChip(Icons.calendar_today, '$year'),
            if (label != null && label.isNotEmpty)
              _buildMetaChip(Icons.business, label),
            if (catalogNo != null && catalogNo.isNotEmpty)
              _buildMetaChip(Icons.tag, catalogNo),
          ],
        ),
      ],
    );
  }

  Widget _buildMetaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: SpinnerTheme.grey),
        const SizedBox(width: 4),
        Text(
          text,
          style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Value card
  // ---------------------------------------------------------------------------

  Widget _buildValueCard(Map<String, dynamic> record) {
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final lowValue = (record['low_value'] as num?)?.toDouble();
    final highValue = (record['high_value'] as num?)?.toDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Market Value',
                style: SpinnerTheme.nunito(
                  size: 13,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.grey,
                ),
              ),
              if (_loadingValue) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation(SpinnerTheme.accent),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'checking live prices',
                  style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.grey),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // When eBay/Reverb return listings we have a real spread, so show
          // Min/Max. When only Discogs answers (a single lowest_price), Min
          // would equal Max and look broken — show one honest figure instead,
          // labelled as the Discogs floor.
          if (_hasRange(lowValue, highValue))
            Row(
              children: [
                Expanded(
                  child: _buildValueColumn(
                    'Min',
                    fmt.format(lowValue),
                    SpinnerTheme.red,
                  ),
                ),
                Expanded(
                  child: _buildValueColumn(
                    'Max',
                    fmt.format(highValue),
                    SpinnerTheme.green,
                  ),
                ),
              ],
            )
          else
            _buildValueColumn(
              'Lowest copy',
              lowValue != null ? fmt.format(lowValue) : '--',
              SpinnerTheme.accent,
              caption: 'cheapest listing found',
            ),
        ],
      ),
    );
  }

  // True only when we have two distinct prices (a genuine low→high spread).
  bool _hasRange(double? low, double? high) {
    if (low == null || high == null) return false;
    return (high - low).abs() >= 0.01;
  }

  Widget _buildValueColumn(String label, String value, Color color,
      {String? caption}) {
    return Column(
      children: [
        Text(
          label,
          style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: SpinnerTheme.nunito(
            size: 20,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption,
            style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.grey),
          ),
        ],
      ],
    );
  }


  // ---------------------------------------------------------------------------
  // Price chart
  // ---------------------------------------------------------------------------

  Widget _buildPriceChart(Map<String, dynamic> record) {
    // price_history is stored as JSON text in the database
    final priceHistoryJson = record['price_history'] as String?;
    if (priceHistoryJson == null || priceHistoryJson.isEmpty) {
      return const SizedBox.shrink();
    }

    // price_history is a TEXT column; it's always a String here, not a List.
    // We'd need to JSON-decode it; for now just skip chart if not parseable.
    List<dynamic> history;
    try {
      final decoded = priceHistoryJson;
      // If it was stored as a JSON array string, decode it
      if (decoded.startsWith('[')) {
        history = List<dynamic>.from(
          (dart_convert.jsonDecode(decoded) as List<dynamic>),
        );
      } else {
        return const SizedBox.shrink();
      }
    } catch (_) {
      return const SizedBox.shrink();
    }

    if (history.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      final entry = history[i];
      final price = entry is Map
          ? (entry['price'] as num?)?.toDouble() ?? 0.0
          : (entry is num ? entry.toDouble() : 0.0);
      spots.add(FlSpot(i.toDouble(), price));
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.15;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price History',
            style: SpinnerTheme.nunito(
              size: 13,
              weight: FontWeight.w600,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY) > 0 ? (maxY - minY) / 4 : 10,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: SpinnerTheme.border,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '\$${value.toStringAsFixed(0)}',
                          style: SpinnerTheme.nunito(
                            size: 10,
                            color: SpinnerTheme.grey,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (spots.length - 1).toDouble(),
                minY: (minY - padding).clamp(0, double.infinity),
                maxY: maxY + padding,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
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
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '\$${spot.y.toStringAsFixed(2)}',
                          SpinnerTheme.nunito(
                            size: 12,
                            weight: FontWeight.w600,
                            color: SpinnerTheme.white,
                          ),
                        );
                      }).toList();
                    },
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

  Widget _buildPressingDetails(Map<String, dynamic> record) {
    final details = <(String, String?)>[
      ('Country', record['pressing_country'] as String?),
      ('Plant', record['pressing_plant'] as String?),
      ('Matrix', record['matrix'] as String?),
      ('Mastering Engineer', record['mastering_engineer'] as String?),
    ];

    final hasAny = details.any((d) => d.$2 != null && d.$2!.isNotEmpty);
    if (!hasAny) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pressing Details',
            style: SpinnerTheme.nunito(
              size: 13,
              weight: FontWeight.w600,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 12),
          ...details
              .where((d) => d.$2 != null && d.$2!.isNotEmpty)
              .map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            d.$1,
                            style: SpinnerTheme.nunito(
                              size: 13,
                              color: SpinnerTheme.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            d.$2!,
                            style: SpinnerTheme.nunito(
                              size: 13,
                              weight: FontWeight.w500,
                              color: SpinnerTheme.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Edit section
  // ---------------------------------------------------------------------------

  Widget _buildEditSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Details',
            style: SpinnerTheme.nunito(
              size: 13,
              weight: FontWeight.w600,
              color: SpinnerTheme.grey,
            ),
          ),
          const SizedBox(height: 16),
          // Vinyl color picker
          _buildColorPicker(),
          const SizedBox(height: 16),
          // Condition dropdown
          _buildConditionDropdown(),
          const SizedBox(height: 8),
          _buildAiGradeTrigger(),
          const SizedBox(height: 16),
          // Notes
          TextField(
            controller: _notesController,
            maxLines: 3,
            style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
            decoration: InputDecoration(
              labelText: 'Notes',
              labelStyle: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
              hintText: 'Add personal notes...',
              hintStyle: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
              filled: true,
              fillColor: SpinnerTheme.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: SpinnerTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: SpinnerTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: SpinnerTheme.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Toggles
          Row(
            children: [
              Expanded(
                child: _buildToggle(
                  'Signed',
                  _isSigned,
                  (v) => setState(() => _isSigned = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildToggle(
                  'Numbered',
                  _isNumbered,
                  (v) => setState(() => _isNumbered = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saveEdits,
              style: FilledButton.styleFrom(
                backgroundColor: SpinnerTheme.accent,
                foregroundColor: SpinnerTheme.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Save Changes',
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    const vinylColors = <(String, Color)>[
      ('Black', Color(0xFF1A1A1A)),
      ('Red', Color(0xFFB71C1C)),
      ('Blue', Color(0xFF1565C0)),
      ('Green', Color(0xFF2E7D32)),
      ('White', Color(0xFFF5F5F5)),
      ('Clear', Color(0x66FFFFFF)),
      ('Orange', Color(0xFFE65100)),
      ('Yellow', Color(0xFFF9A825)),
      ('Purple', Color(0xFF6A1B9A)),
      ('Pink', Color(0xFFE91E63)),
      ('Gold', Color(0xFFFFD600)),
      ('Splatter', Color(0xFF9C27B0)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vinyl Color',
          style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: vinylColors.map((entry) {
            final isSelected = _selectedColor == entry.$1;
            return GestureDetector(
              onTap: () => setState(() => _selectedColor = entry.$1),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: entry.$2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? SpinnerTheme.accent : SpinnerTheme.border,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: entry.$1 == 'White' || entry.$1 == 'Yellow' || entry.$1 == 'Gold'
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
        if (_selectedColor != null) ...[
          const SizedBox(height: 4),
          Text(
            _selectedColor!,
            style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.greyLight),
          ),
        ],
      ],
    );
  }

  Widget _buildAiGradeTrigger() {
    return InkWell(
      onTap: _openAiGrader,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SpinnerTheme.accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SpinnerTheme.accent.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: SpinnerTheme.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI Grade with photo',
                style: SpinnerTheme.nunito(
                  size: 13,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.accent,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: SpinnerTheme.accent.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCondition,
      dropdownColor: SpinnerTheme.surface,
      style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
      decoration: InputDecoration(
        labelText: 'Condition',
        labelStyle: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
        filled: true,
        fillColor: SpinnerTheme.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: SpinnerTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: SpinnerTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: SpinnerTheme.accent, width: 1.5),
        ),
      ),
      items: _conditions.map((c) {
        final label = switch (c) {
          'NM' => 'NM (Near Mint)',
          'VG+' => 'VG+ (Very Good Plus)',
          'VG' => 'VG (Very Good)',
          'G+' => 'G+ (Good Plus)',
          'G' => 'G (Good)',
          'F' => 'F (Fair)',
          'P' => 'P (Poor)',
          _ => c,
        };
        return DropdownMenuItem(value: c, child: Text(label));
      }).toList(),
      onChanged: (value) => setState(() => _selectedCondition = value),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? SpinnerTheme.accent.withOpacity(0.12) : SpinnerTheme.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? SpinnerTheme.accent : SpinnerTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: value ? SpinnerTheme.accent : SpinnerTheme.grey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: SpinnerTheme.nunito(
                size: 13,
                weight: FontWeight.w500,
                color: value ? SpinnerTheme.accent : SpinnerTheme.greyLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Action buttons (Log Spin / Log Clean)
  // ---------------------------------------------------------------------------

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _logSpin,
            icon: const Text('\u25B6', style: TextStyle(fontSize: 16)),
            label: Text(
              'Log a Spin',
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w600,
                color: SpinnerTheme.white,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: SpinnerTheme.accent,
              foregroundColor: SpinnerTheme.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _logClean,
            icon: const Text('\u25CE', style: TextStyle(fontSize: 16)),
            label: Text(
              'Log a Clean',
              style: SpinnerTheme.nunito(
                size: 14,
                weight: FontWeight.w600,
                color: SpinnerTheme.accent,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: SpinnerTheme.accent,
              side: BorderSide(color: SpinnerTheme.accent),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Spin history
  // ---------------------------------------------------------------------------

  Widget _buildSpinHistorySection() {
    final spins = _spinHistory;
    if (spins == null || spins.isEmpty) return const SizedBox.shrink();

    final dateFmt = DateFormat('MMM d, yyyy \u2013 h:mm a');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Spin History',
                style: SpinnerTheme.nunito(
                  size: 13,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.grey,
                ),
              ),
              const Spacer(),
              Text(
                '${spins.length} spins',
                style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.greyLight),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...spins.take(10).map((spin) {
            final spunAtStr = spin['spun_at'] as String?;
            final spunAt = spunAtStr != null ? DateTime.tryParse(spunAtStr) : null;
            final notes = spin['notes'] as String?;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.play_arrow, size: 14, color: SpinnerTheme.accent),
                  const SizedBox(width: 8),
                  Text(
                    spunAt != null ? dateFmt.format(spunAt) : 'Unknown date',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      color: SpinnerTheme.white,
                    ),
                  ),
                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notes,
                        style: SpinnerTheme.nunito(
                          size: 12,
                          color: SpinnerTheme.greyLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          if (spins.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${spins.length - 10} more',
                style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Clean history
  // ---------------------------------------------------------------------------

  Widget _buildCleanHistorySection() {
    final cleans = _cleanHistory;
    if (cleans == null || cleans.isEmpty) return const SizedBox.shrink();

    final dateFmt = DateFormat('MMM d, yyyy \u2013 h:mm a');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Clean History',
                style: SpinnerTheme.nunito(
                  size: 13,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.grey,
                ),
              ),
              const Spacer(),
              Text(
                '${cleans.length} cleans',
                style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.greyLight),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...cleans.take(10).map((clean) {
            final cleanedAtStr = clean['cleaned_at'] as String?;
            final cleanedAt = cleanedAtStr != null ? DateTime.tryParse(cleanedAtStr) : null;
            final method = clean['method'] as String?;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.cleaning_services, size: 14, color: SpinnerTheme.green),
                  const SizedBox(width: 8),
                  Text(
                    cleanedAt != null ? dateFmt.format(cleanedAt) : 'Unknown date',
                    style: SpinnerTheme.nunito(
                      size: 13,
                      color: SpinnerTheme.white,
                    ),
                  ),
                  if (method != null && method.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: SpinnerTheme.surface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          method,
                          style: SpinnerTheme.nunito(
                            size: 11,
                            color: SpinnerTheme.greyLight,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          if (cleans.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${cleans.length - 10} more',
                style: SpinnerTheme.nunito(size: 12, color: SpinnerTheme.grey),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Discogs link
  // ---------------------------------------------------------------------------

  Widget _buildDiscogsButton(Map<String, dynamic> record) {
    if (record['discogs_id'] == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openDiscogs,
        icon: const Icon(Icons.open_in_new, size: 16),
        label: Text(
          'View on Discogs',
          style: SpinnerTheme.nunito(
            size: 14,
            weight: FontWeight.w600,
            color: SpinnerTheme.greyLight,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: SpinnerTheme.greyLight,
          side: BorderSide(color: SpinnerTheme.border),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Error state
  // ---------------------------------------------------------------------------

  Widget _buildErrorState() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: SpinnerTheme.red),
              const SizedBox(height: 12),
              Text(
                'Failed to load record.',
                style: SpinnerTheme.nunito(
                  size: 15,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error ?? 'Unknown error',
                style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      'Go Back',
                      style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _loadRecord,
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
          ),
        ),
      ),
    );
  }
}


/// Suitability chip — compares the record's genres (string CSV stored at
/// scan time) against the user's selected taste (onboarding genres + any
/// long-pressed genres from the Explore page). Hides itself when either
/// side is empty so it never shows a misleading 0% or 100%.
class _TasteMatchChip extends StatefulWidget {
  final Map<String, dynamic> record;
  const _TasteMatchChip({required this.record});
  @override
  State<_TasteMatchChip> createState() => _TasteMatchChipState();
}

class _TasteMatchChipState extends State<_TasteMatchChip> {
  int? _pct;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    final recordGenresRaw = (widget.record['genre'] as String? ?? '').trim();
    if (recordGenresRaw.isEmpty) return;
    final recordGenres = recordGenresRaw
        .split(RegExp(r'[,/]'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (recordGenres.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final tasteList = prefs.getStringList('genres') ?? const <String>[];
    final liked = await GenreLikes.instance.getAll();
    final taste = <String>{
      for (final g in tasteList) g.toLowerCase(),
      for (final g in liked) g.toLowerCase(),
    };
    if (taste.isEmpty) return;

    // Match = how many of the record's genres are in the user's taste set,
    // normalized by record genres (so a record tagged exactly with a liked
    // genre = 100%, even if user likes many other things).
    final hits = recordGenres.where(taste.contains).length;
    final pct = (hits / recordGenres.length * 100).round();
    if (!mounted) return;
    setState(() => _pct = pct);
  }

  @override
  Widget build(BuildContext context) {
    final pct = _pct;
    if (pct == null || pct == 0) return const SizedBox.shrink();
    final highMatch = pct >= 60;
    final color = highMatch ? SpinnerTheme.green : SpinnerTheme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(highMatch ? Icons.favorite : Icons.favorite_border,
              size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            '$pct% your taste',
            style: SpinnerTheme.nunito(
              size: 12,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Find cheapest copies card — fetches live cheapest listings from eBay and
/// Reverb when API keys are present, falls back to deep-link buttons for any
/// source without an API integration (Discogs marketplace + Vinted), and for
/// the API sources when the keys are missing or no results returned.
class _CheapestCopiesCard extends StatefulWidget {
  final Map<String, dynamic> record;
  const _CheapestCopiesCard({required this.record});

  @override
  State<_CheapestCopiesCard> createState() => _CheapestCopiesCardState();
}

class _CheapestCopiesCardState extends State<_CheapestCopiesCard> {
  List<EbayListing> _ebay = const [];
  List<ReverbListing> _reverb = const [];
  bool _loading = true;

  String get _query {
    final title = (widget.record['title'] as String? ?? '').trim();
    final artist = (widget.record['artist'] as String? ?? '').trim();
    return [artist, title, 'vinyl'].where((s) => s.isNotEmpty).join(' ');
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final q = _query;
    if (q.trim().isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      EbayApi().searchVinyl(q, limit: 3),
      ReverbApi().searchVinyl(q, limit: 3),
    ]);
    if (!mounted) return;
    setState(() {
      _ebay = results[0] as List<EbayListing>;
      _reverb = results[1] as List<ReverbListing>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final discogsId = widget.record['discogs_id'] as int?;
    final encoded = Uri.encodeQueryComponent(_query);
    final discogsUrl = discogsId != null
        ? 'https://www.discogs.com/sell/release/$discogsId?sort=price%2Casc'
        : 'https://www.discogs.com/search?q=$encoded&type=all';
    final ebayUrl = 'https://www.ebay.com/sch/i.html?_nkw=$encoded&_sop=15';
    final reverbUrl =
        'https://reverb.com/marketplace?query=$encoded&product_type=accessories';
    final vintedUrl = 'https://www.vinted.com/catalog?search_text=$encoded';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_outlined,
                  size: 16, color: SpinnerTheme.accent),
              const SizedBox(width: 6),
              Text(
                'Find cheapest copies',
                style: SpinnerTheme.nunito(
                  size: 13,
                  weight: FontWeight.w600,
                  color: SpinnerTheme.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Discogs prices high. We scan eBay and Reverb live, plus deep-link the rest.',
            style: SpinnerTheme.nunito(
              size: 12,
              color: SpinnerTheme.greyLight,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (_loading) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SpinnerTheme.accent,
                  ),
                ),
              ),
            ),
          ] else ...[
            for (final l in _ebay) _LiveListingTile.fromEbay(l),
            for (final l in _reverb) _LiveListingTile.fromReverb(l),
            if (_ebay.isNotEmpty || _reverb.isNotEmpty)
              const SizedBox(height: 6),
          ],
          _CheapestLinkButton(
            label: 'Discogs Marketplace · price low → high',
            url: discogsUrl,
          ),
          const SizedBox(height: 8),
          _CheapestLinkButton(
            label: _ebay.isEmpty ? 'eBay · cheapest first' : 'See all on eBay',
            url: ebayUrl,
          ),
          const SizedBox(height: 8),
          _CheapestLinkButton(
            label: _reverb.isEmpty
                ? 'Reverb · vinyl marketplace'
                : 'See all on Reverb',
            url: reverbUrl,
          ),
          const SizedBox(height: 8),
          _CheapestLinkButton(
            label: 'Vinted · secondhand (EU)',
            url: vintedUrl,
          ),
        ],
      ),
    );
  }
}

/// Single inline listing row (price + source + condition + open).
class _LiveListingTile extends StatelessWidget {
  final String source;
  final String title;
  final double price;
  final String currency;
  final String? condition;
  final String? url;

  const _LiveListingTile({
    required this.source,
    required this.title,
    required this.price,
    required this.currency,
    this.condition,
    this.url,
  });

  factory _LiveListingTile.fromEbay(EbayListing l) => _LiveListingTile(
        source: 'eBay',
        title: l.title,
        price: l.price ?? 0,
        currency: l.currency,
        condition: l.condition,
        url: l.itemWebUrl,
      );

  factory _LiveListingTile.fromReverb(ReverbListing l) => _LiveListingTile(
        source: 'Reverb',
        title: l.title,
        price: l.price ?? 0,
        currency: l.currency,
        condition: l.condition,
        url: l.webUrl,
      );

  Future<void> _open() async {
    final raw = url;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: _symbol(currency), decimalDigits: 2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: url == null ? null : _open,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: SpinnerTheme.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SpinnerTheme.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SpinnerTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  source.toUpperCase(),
                  style: SpinnerTheme.nunito(
                    size: 9,
                    weight: FontWeight.w700,
                    color: SpinnerTheme.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpinnerTheme.nunito(
                        size: 12,
                        weight: FontWeight.w600,
                        color: SpinnerTheme.white,
                      ),
                    ),
                    if (condition != null && condition!.isNotEmpty)
                      Text(
                        condition!,
                        style: SpinnerTheme.nunito(
                          size: 10,
                          color: SpinnerTheme.greyLight,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmt.format(price),
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.green,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new,
                  size: 12, color: SpinnerTheme.greyLight),
            ],
          ),
        ),
      ),
    );
  }

  String _symbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '$currency ';
    }
  }
}

/// Outlined button that opens a marketplace search URL in the browser.
/// Used in the "Find cheapest copies" section of record_detail.
class _CheapestLinkButton extends StatelessWidget {
  final String label;
  final String url;
  const _CheapestLinkButton({required this.label, required this.url});

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _open,
        icon: const Icon(Icons.open_in_new, size: 14),
        label: Text(
          label,
          style: SpinnerTheme.nunito(
            size: 13,
            weight: FontWeight.w600,
            color: SpinnerTheme.white,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: SpinnerTheme.white,
          backgroundColor: SpinnerTheme.bg,
          side: BorderSide(color: SpinnerTheme.border),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview tracks (iTunes 30-second clips, no auth)
// ---------------------------------------------------------------------------

class _PreviewTracksCard extends StatefulWidget {
  final Map<String, dynamic> record;
  const _PreviewTracksCard({required this.record});

  @override
  State<_PreviewTracksCard> createState() => _PreviewTracksCardState();
}

class _PreviewTracksCardState extends State<_PreviewTracksCard> {
  final AudioPlayer _player = AudioPlayer();
  List<Map<String, dynamic>> _tracks = const [];
  bool _loading = true;
  int? _currentIndex;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadTracks();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
          _currentIndex = null;
        });
      }
    });
  }

  Future<void> _loadTracks() async {
    final artist = (widget.record['artist'] as String?) ?? '';
    final title = (widget.record['title'] as String?) ?? '';
    final tracks = await ItunesApi.findAlbumTracks(artist: artist, title: title);
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
  }

  Future<void> _toggleTrack(int index) async {
    final track = _tracks[index];
    final url = (track['preview_url'] as String?) ?? '';
    if (url.isEmpty) return;

    if (_currentIndex == index && _isPlaying) {
      await _player.pause();
      return;
    }
    setState(() => _currentIndex = index);
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentIndex = null;
        _isPlaying = false;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _shell(
        child: Row(
          children: [
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Finding preview tracks…',
              style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.greyLight),
            ),
          ],
        ),
      );
    }
    if (_tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    final visible = _tracks.take(8).toList();
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_circle_outline, color: SpinnerTheme.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Preview tracks',
                style: SpinnerTheme.nunito(
                  size: 15,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.white,
                ),
              ),
              const Spacer(),
              Text(
                '30 sec · via Apple Music',
                style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.greyLight),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < visible.length; i++)
            _trackRow(i, visible[i]),
        ],
      ),
    );
  }

  Widget _trackRow(int index, Map<String, dynamic> track) {
    final isCurrent = _currentIndex == index;
    final playing = isCurrent && _isPlaying;
    final name = (track['track_name'] as String?) ?? '';
    final trackNo = track['track_number'] as int? ?? 0;

    return InkWell(
      onTap: () => _toggleTrack(index),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isCurrent ? SpinnerTheme.white : SpinnerTheme.bg,
                shape: BoxShape.circle,
                border: Border.all(color: SpinnerTheme.border),
              ),
              child: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                size: 18,
                color: isCurrent ? SpinnerTheme.bg : SpinnerTheme.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              trackNo > 0 ? '$trackNo.' : '·',
              style: SpinnerTheme.nunito(size: 13, color: SpinnerTheme.greyLight),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SpinnerTheme.nunito(
                  size: 14,
                  weight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: SpinnerTheme.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Spotify "you might also like" (artist seed → recommendations)
// ---------------------------------------------------------------------------

class _SpotifyRecsCard extends StatefulWidget {
  final Map<String, dynamic> record;
  const _SpotifyRecsCard({required this.record});

  @override
  State<_SpotifyRecsCard> createState() => _SpotifyRecsCardState();
}

class _SpotifyRecsCardState extends State<_SpotifyRecsCard> {
  List<SpotifyRecommendation> _recs = const [];
  bool _loading = true;
  final AudioPlayer _player = AudioPlayer();
  String? _playingId;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _load();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
          _playingId = null;
        });
      }
    });
  }

  Future<void> _load() async {
    if (!SpotifyApi.isConfigured) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final api = SpotifyApi();
    final artist = (widget.record['artist'] as String?) ?? '';
    final found = await api.findArtist(artist);
    final artistId = found?['id'] as String?;
    if (artistId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final recs = await api.recommendationsForArtist(artistId);
    if (!mounted) return;
    setState(() {
      _recs = recs;
      _loading = false;
    });
  }

  Future<void> _toggle(SpotifyRecommendation rec) async {
    if (rec.previewUrl.isEmpty) {
      final url = rec.spotifyUrl;
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (_playingId == rec.id && _isPlaying) {
      await _player.pause();
      return;
    }
    setState(() => _playingId = rec.id);
    try {
      await _player.setUrl(rec.previewUrl);
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _playingId = null;
        _isPlaying = false;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_recs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpinnerTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpinnerTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.recommend, color: SpinnerTheme.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'You might also like',
                style: SpinnerTheme.nunito(
                  size: 15,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.white,
                ),
              ),
              const Spacer(),
              Text(
                'via Spotify',
                style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.greyLight),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _recTile(_recs[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recTile(SpotifyRecommendation rec) {
    final isCurrent = _playingId == rec.id;
    final playing = isCurrent && _isPlaying;
    return SizedBox(
      width: 120,
      child: GestureDetector(
        onTap: () => _toggle(rec),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: rec.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: rec.coverUrl,
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 120,
                          height: 120,
                          color: SpinnerTheme.bg,
                        ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              rec.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpinnerTheme.nunito(
                size: 12,
                weight: FontWeight.w700,
                color: SpinnerTheme.white,
              ),
            ),
            Text(
              rec.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpinnerTheme.nunito(size: 11, color: SpinnerTheme.greyLight),
            ),
          ],
        ),
      ),
    );
  }
}
