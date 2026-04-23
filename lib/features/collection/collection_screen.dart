import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database.dart';
import '../../core/theme.dart';

enum CollectionFormat { all, vinyl, cd, cassette }

enum CollectionSort { artistAZ, recentlyAdded, valueHighLow, valueLowHigh }

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  CollectionFormat _selectedFormat = CollectionFormat.all;
  CollectionSort _selectedSort = CollectionSort.recentlyAdded;

  List<Map<String, dynamic>>? _records;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final records = await AppDatabase.getCollection();
      if (!mounted) return;
      setState(() {
        _records = records;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredAndSortedRecords {
    if (_records == null) return [];

    var result = List<Map<String, dynamic>>.from(_records!);

    // Filter by format
    if (_selectedFormat != CollectionFormat.all) {
      final formatStr = _selectedFormat.name.toLowerCase();
      result = result.where((r) {
        final fmt = (r['format'] as String?)?.toLowerCase() ?? '';
        return fmt == formatStr;
      }).toList();
    }

    // Filter by search query
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((r) {
        final title = (r['title'] as String?)?.toLowerCase() ?? '';
        final artist = (r['artist'] as String?)?.toLowerCase() ?? '';
        return title.contains(query) || artist.contains(query);
      }).toList();
    }

    // Sort
    switch (_selectedSort) {
      case CollectionSort.artistAZ:
        result.sort((a, b) =>
            ((a['artist'] as String?) ?? '').toLowerCase().compareTo(
                ((b['artist'] as String?) ?? '').toLowerCase()));
      case CollectionSort.recentlyAdded:
        result.sort((a, b) =>
            ((b['synced_at'] as String?) ?? '').compareTo(
                (a['synced_at'] as String?) ?? ''));
      case CollectionSort.valueHighLow:
        result.sort((a, b) =>
            ((b['median_value'] as num?) ?? 0).compareTo(
                (a['median_value'] as num?) ?? 0));
      case CollectionSort.valueLowHigh:
        result.sort((a, b) =>
            ((a['median_value'] as num?) ?? 0).compareTo(
                (b['median_value'] as num?) ?? 0));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      appBar: AppBar(
        backgroundColor: SpinnerTheme.bg,
        elevation: 0,
        title: Text(
          'Collection',
          style: SpinnerTheme.nunito(
            size: 22,
            weight: FontWeight.w700,
            color: SpinnerTheme.white,
          ),
        ),
        actions: [
          PopupMenuButton<CollectionSort>(
            icon: Icon(Icons.sort, color: SpinnerTheme.grey),
            color: SpinnerTheme.surface,
            onSelected: (sort) => setState(() => _selectedSort = sort),
            itemBuilder: (_) => [
              _buildSortItem(CollectionSort.artistAZ, 'Artist A\u2013Z'),
              _buildSortItem(CollectionSort.recentlyAdded, 'Recently Added'),
              _buildSortItem(CollectionSort.valueHighLow, 'Value High\u2013Low'),
              _buildSortItem(CollectionSort.valueLowHigh, 'Value Low\u2013High'),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.white),
        decoration: InputDecoration(
          hintText: 'Search by title or artist...',
          hintStyle: SpinnerTheme.nunito(size: 14, color: SpinnerTheme.grey),
          prefixIcon: Icon(Icons.search, color: SpinnerTheme.grey, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: SpinnerTheme.grey, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                  },
                )
              : null,
          filled: true,
          fillColor: SpinnerTheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
            borderSide: BorderSide(color: SpinnerTheme.accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: CollectionFormat.values.map((format) {
          final isSelected = _selectedFormat == format;
          final label = switch (format) {
            CollectionFormat.all => 'All',
            CollectionFormat.vinyl => 'Vinyl',
            CollectionFormat.cd => 'CD',
            CollectionFormat.cassette => 'Cassette',
          };

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(
                label,
                style: SpinnerTheme.nunito(
                  size: 13,
                  weight: FontWeight.w600,
                  color: isSelected ? SpinnerTheme.bg : SpinnerTheme.greyLight,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedFormat = format),
              backgroundColor: SpinnerTheme.surface,
              selectedColor: SpinnerTheme.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? SpinnerTheme.accent : SpinnerTheme.border,
                ),
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          );
        }).toList(),
      ),
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

    final records = _filteredAndSortedRecords;

    if (_records != null && _records!.isEmpty) {
      return _buildEmptyState();
    }

    if (records.isEmpty) {
      return _buildNoResultsState();
    }

    return RefreshIndicator(
      color: SpinnerTheme.accent,
      backgroundColor: SpinnerTheme.surface,
      onRefresh: _loadRecords,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: records.length,
        separatorBuilder: (_, __) => Divider(
          color: SpinnerTheme.border,
          height: 1,
        ),
        itemBuilder: (context, index) => _buildRecordTile(records[index]),
      ),
    );
  }

  Widget _buildRecordTile(Map<String, dynamic> record) {
    final valueFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    final id = record['id'] as String?;
    final title = record['title'] as String? ?? 'Unknown Title';
    final artist = record['artist'] as String? ?? 'Unknown Artist';
    final coverUrl = record['cover_url'] as String?;
    final medianValue = (record['median_value'] as num?)?.toDouble();

    return InkWell(
      onTap: () {
        if (id != null) context.push('/record/$id');
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // Cover art thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 56,
                height: 56,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: SpinnerTheme.surface,
                          child: Icon(Icons.album, color: SpinnerTheme.grey, size: 28),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: SpinnerTheme.surface,
                          child: Icon(Icons.album, color: SpinnerTheme.grey, size: 28),
                        ),
                      )
                    : Container(
                        color: SpinnerTheme.surface,
                        child: Icon(Icons.album, color: SpinnerTheme.grey, size: 28),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Title, artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SpinnerTheme.nunito(
                      size: 15,
                      weight: FontWeight.w600,
                      color: SpinnerTheme.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    style: SpinnerTheme.nunito(
                      size: 13,
                      color: SpinnerTheme.greyLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Value
            if (medianValue != null)
              Text(
                valueFmt.format(medianValue),
                style: SpinnerTheme.nunito(
                  size: 15,
                  weight: FontWeight.w700,
                  color: SpinnerTheme.green,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_outlined, size: 64, color: SpinnerTheme.grey),
            const SizedBox(height: 16),
            Text(
              'No records yet.\nScan your first vinyl!',
              textAlign: TextAlign.center,
              style: SpinnerTheme.nunito(
                size: 16,
                weight: FontWeight.w600,
                color: SpinnerTheme.greyLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: SpinnerTheme.grey),
            const SizedBox(height: 12),
            Text(
              'No records match your search.',
              style: SpinnerTheme.nunito(
                size: 15,
                color: SpinnerTheme.greyLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: SpinnerTheme.red),
            const SizedBox(height: 12),
            Text(
              'Failed to load collection.',
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
            FilledButton.icon(
              onPressed: _loadRecords,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: SpinnerTheme.accent,
                foregroundColor: SpinnerTheme.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuEntry<CollectionSort> _buildSortItem(CollectionSort sort, String label) {
    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          if (_selectedSort == sort)
            Icon(Icons.check, size: 16, color: SpinnerTheme.accent)
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: SpinnerTheme.nunito(
              size: 14,
              color: _selectedSort == sort ? SpinnerTheme.accent : SpinnerTheme.white,
            ),
          ),
        ],
      ),
    );
  }
}
